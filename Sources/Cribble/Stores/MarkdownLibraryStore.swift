import AppKit
import Foundation
import SwiftUI

@MainActor
final class MarkdownLibraryStore: ObservableObject {
    @Published var rootURLs: [URL] = []
    @Published var nodes: [MarkdownNode] = []
    @Published var selectedURL: URL?
    @Published var selectedDocument: MarkdownDocument?
    @Published var selectedRenderedMarkdown: String = ""
    @Published var selectedLinkedFiles: [LinkedFileSummary] = []
    @Published var searchText = ""
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var isRunningAI = false
    @Published var pendingDiff: UnifiedDiff?

    private let loader = DocumentLoader()
    private let monitor = FileChangeMonitor()
    private var documents: [MarkdownDocument] = []
    private var linkIndex: LinkIndex?
    private var currentSortMode: FileSortMode = .name
    private var securityScopedRoots: Set<URL> = []
    private var renderTask: Task<Void, Never>?

    init() {
        restoreFolders()
    }

    var hasFolders: Bool {
        !rootURLs.isEmpty
    }

    var activeRootURL: URL? {
        guard let selectedURL else { return rootURLs.first }
        return rootURLs.first { root in
            selectedURL.isSameFileOrDescendant(of: root)
        } ?? rootURLs.first
    }

    var selectedRootURL: URL? {
        guard let selectedURL else { return nil }
        return rootURLs.first { selectedURL.isSameFileOrDescendant(of: $0) }
    }

    var filteredNodes: [MarkdownNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nodes }
        return nodes.compactMap { filter($0, query: query) }
    }

    func chooseFolder(sortMode: FileSortMode) {
        let panel = NSOpenPanel()
        panel.title = "Open Markdown Folder"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url, sortMode: sortMode)
        }
    }

    func openFolder(_ url: URL, sortMode: FileSortMode) {
        currentSortMode = sortMode
        let standardized = url.standardizedFileURL
        startAccessingFolder(standardized)
        if !rootURLs.contains(standardized) {
            rootURLs.append(standardized)
            persistFolders()
        }
        refresh(sortMode: sortMode)
        startMonitoring()
    }

    func isImportedRoot(_ url: URL) -> Bool {
        rootURLs.contains(url.standardizedFileURL)
    }

    func removeSelectedFolder() {
        guard let selectedRootURL else { return }
        removeFolder(selectedRootURL)
    }

    func removeFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard rootURLs.contains(standardized) else { return }

        let removedSelectedDocument = selectedURL?.isSameFileOrDescendant(of: standardized) ?? false
        rootURLs.removeAll { $0.standardizedFileURL == standardized }
        persistFolders()
        stopAccessingFolder(standardized)

        if removedSelectedDocument {
            selectedURL = nil
            selectedDocument = nil
        }

        guard !rootURLs.isEmpty else {
            monitor.stop()
            nodes = []
            documents = []
            linkIndex = nil
            statusMessage = "Removed \(standardized.lastPathComponent)"
            return
        }

        refresh(sortMode: currentSortMode, keepStatusQuiet: true)
        startMonitoring()
        statusMessage = "Removed \(standardized.lastPathComponent)"
    }

    func refresh(sortMode: FileSortMode? = nil, keepStatusQuiet: Bool = false) {
        if let sortMode {
            currentSortMode = sortMode
        }

        do {
            nodes = try rootURLs.map { try rootNode(for: $0, sortMode: currentSortMode) }
            documents = try collectMarkdownURLs(nodes).map(loader.load)
            if let firstRoot = rootURLs.first {
                linkIndex = LinkIndex(documents: documents, rootURL: firstRoot)
            } else {
                linkIndex = nil
            }

            if let selectedURL {
                select(url: selectedURL)
            } else if let first = firstReadableURL(in: nodes) {
                select(url: first)
            }

            if !keepStatusQuiet {
                statusMessage = "Loaded \(documents.count) Markdown files"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(url: URL?) {
        guard let url else {
            selectedURL = nil
            selectedDocument = nil
            selectedRenderedMarkdown = ""
            selectedLinkedFiles = []
            renderTask?.cancel()
            return
        }

        let documentURL = documentURL(for: url)
        selectedURL = url

        guard let documentURL else {
            selectedDocument = nil
            selectedRenderedMarkdown = ""
            selectedLinkedFiles = []
            return
        }

        if selectedDocument?.url != documentURL {
            selectedRenderedMarkdown = ""
            selectedLinkedFiles = []
        }

        do {
            let document = try loader.load(url: documentURL)
            selectedDocument = document
            scheduleRender(for: document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleRender(for document: MarkdownDocument) {
        renderTask?.cancel()
        let index = linkIndex
        let documentsSnapshot = documents
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            let preprocessed = MarkdownDisplayPreprocessor.prepare(
                document.rawMarkdown,
                documentTitle: document.title
            )
            if Task.isCancelled { return }
            let rendered = WikiLinkParser.renderForMarkdown(preprocessed, index: index)
            if Task.isCancelled { return }
            let linkedFiles = MarkdownLibraryStore.linkedFiles(
                for: document,
                index: index,
                allDocuments: documentsSnapshot
            )
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                guard self.selectedDocument?.url == document.url else { return }
                self.selectedRenderedMarkdown = rendered
                self.selectedLinkedFiles = linkedFiles
            }
        }
    }

    nonisolated private static func linkedFiles(
        for document: MarkdownDocument,
        index: LinkIndex?,
        allDocuments: [MarkdownDocument]
    ) -> [LinkedFileSummary] {
        guard let index else { return [] }
        var seen = Set<URL>()
        return document.outboundLinks.compactMap { link in
            let resolved = index.resolve(link)
            guard let targetURL = resolved.targetURL, seen.insert(targetURL).inserted else {
                return nil
            }
            let targetDocument = allDocuments.first { $0.url == targetURL }
            let title = link.label.isEmpty ? targetDocument?.title ?? targetURL.deletingPathExtension().lastPathComponent : link.label
            let folderName = targetURL.deletingLastPathComponent().lastPathComponent
            let subtitle = resolved.anchor.map { "#\($0)" } ?? folderName
            return LinkedFileSummary(
                id: targetURL,
                title: title,
                subtitle: subtitle,
                url: targetURL,
                anchor: resolved.anchor
            )
        }
    }

    func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "cribble" else {
            NSWorkspace.shared.open(url)
            return .handled
        }

        guard url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value
        else {
            errorMessage = "No matching Markdown file found for that link."
            return .handled
        }

        select(url: URL(fileURLWithPath: path))
        return .handled
    }

    func openSelectedInEditor(settings: AppSettings) {
        guard selectedDocument != nil else { return }
        if let editorURL = settings.editorApplicationURL {
            openSelectedDocument(with: editorURL)
        } else {
            openSelectedDocumentWithDefaultApp()
        }
    }

    func openSelectedDocumentWithDefaultApp() {
        guard let selectedDocument else { return }
        NSWorkspace.shared.open(selectedDocument.url)
    }

    func openSelectedDocument(with applicationURL: URL) {
        guard let selectedDocument else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([selectedDocument.url], withApplicationAt: applicationURL, configuration: configuration) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.errorMessage = error.localizedDescription }
            }
        }
    }

    func revealSelectedDocumentInFinder() {
        guard let selectedDocument else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedDocument.url])
    }

    func runAILinking(provider: AIProvider, mode: AIMode) {
        guard let rootURL = activeRootURL else { return }
        isRunningAI = true
        pendingDiff = nil
        let actionLabel = mode == .updateReadme ? "rewrite the folder README" : "suggest links"
        statusMessage = "Asking \(provider.rawValue) \(provider.lowestModelName) to \(actionLabel)..."

        Task {
            do {
                let diff = try await AIService().generateLinkPatch(
                    provider: provider,
                    mode: mode,
                    folderURL: rootURL
                )
                pendingDiff = diff
                if diff.isEmpty {
                    statusMessage = mode == .updateReadme ? "No README changes suggested" : "No link changes suggested"
                } else {
                    statusMessage = mode == .updateReadme ? "Review README changes" : "Review suggested link changes"
                }
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "AI request failed"
            }
            isRunningAI = false
        }
    }

    func applyPendingDiff() {
        guard let rootURL = activeRootURL, let pendingDiff else { return }
        do {
            try DiffApplier().apply(pendingDiff, rootURL: rootURL)
            self.pendingDiff = nil
            refresh()
            statusMessage = "Applied AI link suggestions"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelPendingDiff() {
        pendingDiff = nil
        statusMessage = "AI link changes discarded"
    }

    private func rootNode(for rootURL: URL, sortMode: FileSortMode) throws -> MarkdownNode {
        let values = try rootURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let children = try FolderScanner(fileSortMode: sortMode).scan(rootURL: rootURL)
        let readmeURL = rootURL.appendingPathComponent("README.md")
        return MarkdownNode(
            id: rootURL.standardizedFileURL,
            name: rootURL.lastPathComponent,
            url: rootURL,
            kind: .folder,
            createdAt: values.creationDate,
            modifiedAt: values.contentModificationDate,
            readmeURL: readmeURL,
            children: children
        )
    }

    private func startMonitoring() {
        monitor.start(rootURLs: rootURLs) { [weak self] in
            self?.refresh(keepStatusQuiet: true)
        }
    }

    private func restoreFolders() {
        let bookmarkedURLs = restoreBookmarkedFolders()
        let paths = UserDefaults.standard.stringArray(forKey: Keys.folderPaths)
        let legacyPath = UserDefaults.standard.string(forKey: Keys.legacyLastFolderPath)
        let pathURLs = (paths ?? legacyPath.map { [$0] } ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }

        rootURLs = (bookmarkedURLs + pathURLs)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .uniqued()

        if !rootURLs.isEmpty {
            rootURLs.forEach(startAccessingFolder)
            persistFolders()
            refresh()
            startMonitoring()
        }
    }

    private func persistFolders() {
        UserDefaults.standard.set(rootURLs.map(\.path), forKey: Keys.folderPaths)
        let bookmarks = rootURLs.compactMap { url in
            try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        UserDefaults.standard.set(bookmarks, forKey: Keys.folderBookmarks)
    }

    private func restoreBookmarkedFolders() -> [URL] {
        let bookmarks = UserDefaults.standard.array(forKey: Keys.folderBookmarks) as? [Data] ?? []
        return bookmarks.compactMap { bookmark in
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL {
                startAccessingFolder(url)
                return url
            }

            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL {
                startAccessingFolder(url)
                return url
            }

            return nil
        }
    }

    private func startAccessingFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !securityScopedRoots.contains(standardized) else { return }
        if standardized.startAccessingSecurityScopedResource() {
            securityScopedRoots.insert(standardized)
        }
    }

    private func stopAccessingFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard securityScopedRoots.remove(standardized) != nil else { return }
        standardized.stopAccessingSecurityScopedResource()
    }

    private func stopAccessingAllFolders() {
        for url in securityScopedRoots {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedRoots.removeAll()
    }

    private func documentURL(for url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let readmeURL = url.appendingPathComponent("README.md")
            return FileManager.default.fileExists(atPath: readmeURL.path) ? readmeURL : nil
        }

        return url.pathExtension.lowercased() == "md" ? url : nil
    }

    private func collectMarkdownURLs(_ nodes: [MarkdownNode]) -> [URL] {
        nodes.flatMap { node -> [URL] in
            switch node.kind {
            case .folder:
                let ownReadme = node.readmeURL.map { [$0] } ?? []
                return ownReadme + collectMarkdownURLs(node.children)
            case .markdown:
                return [node.url]
            }
        }
        .uniqued()
    }

    private func firstReadableURL(in nodes: [MarkdownNode]) -> URL? {
        for node in nodes {
            if node.readmeURL != nil {
                return node.url
            }
            if node.kind == .markdown {
                return node.url
            }
            if let childURL = firstReadableURL(in: node.children) {
                return childURL
            }
        }
        return nil
    }

    private func filter(_ node: MarkdownNode, query: String) -> MarkdownNode? {
        if node.name.localizedCaseInsensitiveContains(query) {
            return node
        }

        let children = node.children.compactMap { filter($0, query: query) }
        if !children.isEmpty {
            return MarkdownNode(
                id: node.id,
                name: node.name,
                url: node.url,
                kind: node.kind,
                createdAt: node.createdAt,
                modifiedAt: node.modifiedAt,
                readmeURL: node.readmeURL,
                children: children
            )
        }
        return nil
    }

    private enum Keys {
        static let folderBookmarks = "folderBookmarks"
        static let folderPaths = "folderPaths"
        static let legacyLastFolderPath = "lastFolderPath"
    }
}

private extension URL {
    func isSameFileOrDescendant(of rootURL: URL) -> Bool {
        let path = standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}
