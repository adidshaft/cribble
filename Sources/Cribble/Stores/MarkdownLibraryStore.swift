import AppKit
import Foundation
import SwiftUI

@MainActor
final class MarkdownLibraryStore: ObservableObject {
    @Published var rootURLs: [URL] = []
    @Published var nodes: [MarkdownNode] = [] {
        didSet { cachedFilteredNodes = nil }
    }
    @Published var selectedURL: URL?
    @Published var selectedDocument: MarkdownDocument?
    @Published var selectedRenderedMarkdown: String = ""
    @Published var selectedLinkedFiles: [LinkedFileSummary] = []
    @Published var searchText = "" {
        didSet { cachedFilteredNodes = nil }
    }
    @Published var history: [URL] = []
    @Published var historyIndex: Int = -1
    @Published var activeScrollAnchor: String?
    @Published var selectedUnresolvedTarget: UnresolvedTarget?
    private var isNavigatingHistory = false
    @Published var statusMessage: String? {
        didSet {
            if let statusMessage {
                DiagnosticsCenter.shared.record(level: .info, message: statusMessage)
            }
        }
    }
    @Published var errorMessage: String? {
        didSet {
            if let errorMessage {
                DiagnosticsCenter.shared.record(level: .error, message: errorMessage)
            }
        }
    }
    @Published var isRunningAI = false
    @Published var pendingDiff: UnifiedDiff?
    @Published var pendingDiffError: String?
    @Published var pathfinderRequest: PathfinderRequest?
    @Published private(set) var pinnedPaths: Set<String> = [] {
        didSet { cachedFilteredNodes = nil }
    }
    @Published private var rootDisplayNames: [String: String] = [:]

    private let loader = DocumentLoader()
    private let monitor = FileChangeMonitor()
    private(set) var documents: [MarkdownDocument] = []
    private var linkIndex: LinkIndex?
    private var currentSortMode: FileSortMode = .name
    private var renderTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var pendingDiffRootURL: URL?
    private var pendingDiffMode: AIMode?
    private var pendingDiffSuccessMessage: String?

    // LRU render cache. Keyed by document URL; entries are invalidated when
    // the underlying file content changes (we compare a hash of rawMarkdown).
    // Bounded so a long browsing session can't pin all rendered HTML in RAM.
    private struct RenderCacheEntry {
        let sourceHash: Int
        let rendered: String
        let linkedFiles: [LinkedFileSummary]
    }
    private var renderCache: [URL: RenderCacheEntry] = [:]
    private var renderCacheOrder: [URL] = []
    private static let renderCacheLimit = 20

    // Memoized result of `filteredNodes`. Invalidated whenever `nodes` or
    // `searchText` change (see their didSet).
    private var cachedFilteredNodes: [MarkdownNode]?

    // Bounded concurrency for the initial parallel-load fan-out. Empirically
    // 16 saturates an SSD without thrashing the dispatch queue.
    private static let loadConcurrency = 16

    init(restore: Bool = true, includeBundledDemo: Bool = true) {
        if restore {
            pinnedPaths = Set(UserDefaults.standard.stringArray(forKey: Keys.pinnedFolders) ?? [])
            restoreFolders(includeBundledDemo: includeBundledDemo)
        }
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

    func rootURL(for url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        return rootURLs.first { standardized.isSameFileOrDescendant(of: $0) } ?? activeRootURL
    }

    var filteredNodes: [MarkdownNode] {
        if let cachedFilteredNodes { return cachedFilteredNodes }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [MarkdownNode]
        if query.isEmpty {
            base = nodes
        } else {
            base = nodes.compactMap { filter($0, query: query) }
        }
        let result = pinnedPaths.isEmpty ? base : floatingPinnedFolders(in: base)
        cachedFilteredNodes = result
        return result
    }

    func isPinned(_ url: URL) -> Bool {
        pinnedPaths.contains(url.standardizedFileURL.path)
    }

    /// Pin/unpin a folder so it floats to the top of its sibling group. Pinning
    /// is purely a sidebar-ordering preference; it never moves files on disk.
    func togglePin(_ url: URL) {
        let key = url.standardizedFileURL.path
        if pinnedPaths.contains(key) {
            pinnedPaths.remove(key)
        } else {
            pinnedPaths.insert(key)
        }
        UserDefaults.standard.set(Array(pinnedPaths), forKey: Keys.pinnedFolders)
    }

    /// Recursively reorders so pinned folders come first within each level,
    /// preserving the existing order otherwise (a stable partition).
    private func floatingPinnedFolders(in nodes: [MarkdownNode]) -> [MarkdownNode] {
        let reordered = nodes.map { node -> MarkdownNode in
            guard node.kind == .folder, !node.children.isEmpty else { return node }
            var copy = node
            copy.children = floatingPinnedFolders(in: node.children)
            return copy
        }
        let pinned = reordered.filter { $0.kind == .folder && pinnedPaths.contains($0.url.standardizedFileURL.path) }
        guard !pinned.isEmpty else { return reordered }
        let pinnedIDs = Set(pinned.map(\.id))
        return pinned + reordered.filter { !pinnedIDs.contains($0.id) }
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
        rootDisplayNames.removeValue(forKey: standardized.path)
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

    func renameImportedFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard rootURLs.contains(standardized) else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Imported Folder"
        alert.informativeText = "This changes only the name shown in Cribble. The actual folder on disk is not renamed."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = displayName(forRoot: standardized)
        field.placeholderString = standardized.lastPathComponent
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            setImportedFolderDisplayName(field.stringValue, for: standardized)
        }
    }

    func setImportedFolderDisplayName(_ name: String, for url: URL) {
        let standardized = url.standardizedFileURL
        guard rootURLs.contains(standardized) else { return }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == standardized.lastPathComponent {
            rootDisplayNames.removeValue(forKey: standardized.path)
        } else {
            rootDisplayNames[standardized.path] = trimmed
        }

        persistFolderDisplayNames()
        refresh(sortMode: currentSortMode, keepStatusQuiet: true)
        statusMessage = "Renamed \(standardized.lastPathComponent) in Cribble"
    }

    func copyActualPath(for url: URL) {
        let standardized = url.standardizedFileURL
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(standardized.path, forType: .string)
        statusMessage = "Copied \(standardized.path)"
    }

    func refresh(sortMode: FileSortMode? = nil, keepStatusQuiet: Bool = false) {
        if let sortMode {
            currentSortMode = sortMode
        }

        let roots = rootURLs
        let sort = currentSortMode
        let displayNames = rootDisplayNames

        loadTask?.cancel()
        let concurrency = Self.loadConcurrency
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (nodes: [MarkdownNode], documents: [MarkdownDocument], linkIndex: LinkIndex?, skippedFiles: [URL], failedRoots: [URL]) in
                    var nodesList: [MarkdownNode] = []
                    var failedRoots: [URL] = []
                    for rootURL in roots {
                        // A single unscannable root (permissions, an offline
                        // iCloud folder, etc.) must not take down every other
                        // folder — skip it and report it instead.
                        do {
                            let values = try rootURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                            let children = try FolderScanner(fileSortMode: sort).scan(rootURL: rootURL)
                            let readmeURL = rootURL.appendingPathComponent("README.md")
                            let displayName = displayNames[rootURL.standardizedFileURL.path] ?? rootURL.lastPathComponent
                            nodesList.append(MarkdownNode(
                                id: rootURL.standardizedFileURL,
                                name: displayName,
                                url: rootURL,
                                kind: .folder,
                                createdAt: values.creationDate,
                                modifiedAt: values.contentModificationDate,
                                readmeURL: readmeURL,
                                children: children
                            ))
                        } catch {
                            failedRoots.append(rootURL)
                        }
                    }

                    func collect(_ nodes: [MarkdownNode]) -> [URL] {
                        nodes.flatMap { node -> [URL] in
                            switch node.kind {
                            case .folder:
                                let ownReadme = node.readmeURL.map { [$0] } ?? []
                                return ownReadme + collect(node.children)
                            case .markdown:
                                return [node.url]
                            }
                        }
                    }
                    let urls = collect(nodesList).uniqued()
                    let loader = DocumentLoader()

                    // Bounded-concurrency fan-out. Each file loads independently:
                    // a file that can't be read (unsupported encoding handled in
                    // DocumentLoader, an offline iCloud placeholder, a permission
                    // error) is skipped and reported rather than aborting the
                    // whole folder open — real Obsidian/iCloud vaults routinely
                    // contain such files.
                    let outcomes = await withTaskGroup(of: (URL, MarkdownDocument?).self) { group -> [(URL, MarkdownDocument?)] in
                        var iterator = urls.makeIterator()
                        var inFlight = 0
                        while inFlight < concurrency, let url = iterator.next() {
                            group.addTask { (url, try? loader.load(url: url)) }
                            inFlight += 1
                        }
                        var collected: [(URL, MarkdownDocument?)] = []
                        collected.reserveCapacity(urls.count)
                        while let outcome = await group.next() {
                            collected.append(outcome)
                            if let url = iterator.next() {
                                group.addTask { (url, try? loader.load(url: url)) }
                            }
                        }
                        return collected
                    }

                    var docs: [MarkdownDocument] = []
                    docs.reserveCapacity(outcomes.count)
                    var skippedFiles: [URL] = []
                    for (url, document) in outcomes {
                        if let document {
                            docs.append(document)
                        } else {
                            skippedFiles.append(url)
                        }
                    }

                    let index: LinkIndex?
                    if let firstRoot = roots.first {
                        index = LinkIndex(documents: docs, rootURL: firstRoot)
                    } else {
                        index = nil
                    }

                    return (nodesList, docs, index, skippedFiles, failedRoots)
                }.value

                guard !Task.isCancelled else { return }

                self.nodes = result.nodes
                self.documents = result.documents
                self.linkIndex = result.linkIndex
                // Render cache keys by URL but the file content may have
                // changed under us (e.g. user edited externally and the
                // FSEvents monitor triggered this refresh). Drop everything
                // — the next selection will re-render and re-cache.
                self.renderCache.removeAll()
                self.renderCacheOrder.removeAll()
                self.filterHistory()

                if let selectedURL = self.selectedURL {
                    self.select(url: selectedURL)
                } else if let first = self.firstReadableURL(in: result.nodes) {
                    self.select(url: first)
                }

                for failedRoot in result.failedRoots {
                    DiagnosticsCenter.shared.record(level: .warning, message: "Couldn't open folder (skipped): \(failedRoot.path)")
                }
                if !result.skippedFiles.isEmpty {
                    let names = result.skippedFiles.prefix(5).map(\.lastPathComponent).joined(separator: ", ")
                    let suffix = result.skippedFiles.count > 5 ? ", …" : ""
                    DiagnosticsCenter.shared.record(
                        level: .warning,
                        message: "Skipped \(result.skippedFiles.count) unreadable file(s): \(names)\(suffix)"
                    )
                }

                if !keepStatusQuiet {
                    let skippedCount = result.skippedFiles.count
                    let skippedSuffix = skippedCount > 0 ? " · \(skippedCount) skipped" : ""
                    self.statusMessage = "Loaded \(result.documents.count) Markdown files\(skippedSuffix)"
                }
        }
    }

    func waitForLoadToComplete() async {
        _ = await loadTask?.result
    }

    func select(url: URL?) {
        guard let url else {
            selectedURL = nil
            selectedDocument = nil
            selectedRenderedMarkdown = ""
            selectedLinkedFiles = []
            selectedUnresolvedTarget = nil
            renderTask?.cancel()
            return
        }

        let documentURL = documentURL(for: url)
        selectedURL = url
        selectedUnresolvedTarget = nil

        guard let documentURL else {
            selectedDocument = nil
            selectedRenderedMarkdown = ""
            selectedLinkedFiles = []
            return
        }

        if !isNavigatingHistory {
            if historyIndex < history.count - 1 {
                history.removeSubrange((historyIndex + 1)...)
            }
            if history.isEmpty || history[historyIndex] != documentURL {
                history.append(documentURL)
                historyIndex = history.count - 1
            }
        }

        if selectedDocument?.url != documentURL {
            selectedRenderedMarkdown = ""
            selectedLinkedFiles = []
        }

        do {
            // Synchronous read on purpose: callers (including the test
            // suite) expect `selectedDocument` to be populated by the time
            // select() returns. The heavy work — markdown preprocessing,
            // wiki-link rewriting, linked-files resolution — happens off
            // the main thread inside scheduleRender(), and a recent render
            // is served from the LRU cache for free.
            let document = try loader.load(url: documentURL)
            selectedDocument = document
            scheduleRender(for: document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleRender(for document: MarkdownDocument) {
        renderTask?.cancel()

        // Fast path: if we already rendered this exact body recently
        // (back/forward navigation, or re-select), publish the cached
        // version synchronously and skip the detached pipeline entirely.
        let sourceHash = document.rawMarkdown.hashValue
        if let cached = renderCache[document.url], cached.sourceHash == sourceHash {
            selectedRenderedMarkdown = cached.rendered
            selectedLinkedFiles = cached.linkedFiles
            touchRenderCacheEntry(for: document.url)
            return
        }

        let index = linkIndex
        let documentsSnapshot = documents
        let documentURL = document.url
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
                guard self.selectedDocument?.url == documentURL else { return }
                self.selectedRenderedMarkdown = rendered
                self.selectedLinkedFiles = linkedFiles
                self.storeRenderCacheEntry(
                    url: documentURL,
                    entry: RenderCacheEntry(
                        sourceHash: sourceHash,
                        rendered: rendered,
                        linkedFiles: linkedFiles
                    )
                )
            }
        }
    }

    private func storeRenderCacheEntry(url: URL, entry: RenderCacheEntry) {
        renderCache[url] = entry
        renderCacheOrder.removeAll { $0 == url }
        renderCacheOrder.append(url)
        while renderCacheOrder.count > Self.renderCacheLimit {
            let evicted = renderCacheOrder.removeFirst()
            renderCache.removeValue(forKey: evicted)
        }
    }

    private func touchRenderCacheEntry(for url: URL) {
        guard renderCache[url] != nil else { return }
        renderCacheOrder.removeAll { $0 == url }
        renderCacheOrder.append(url)
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
        if url.scheme == "cribble" {
            return handleCribbleURL(url)
        }

        if let internalURL = internalMarkdownURL(for: url) {
            select(url: internalURL)
            return .handled
        }

        if url.isFileURL, url.pathExtension.lowercased() == "md" {
            errorMessage = "No matching Markdown file found for that link."
            return .handled
        }

        if url.scheme == nil, url.pathExtension.lowercased() == "md" {
            errorMessage = "No matching Markdown file found for that link."
            return .handled
        }

        NSWorkspace.shared.open(url)
        return .handled
    }

    private func handleCribbleURL(_ url: URL) -> OpenURLAction.Result {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .handled
        }

        if url.host == "open", let path = components.queryItems?.first(where: { $0.name == "path" })?.value {
            if let anchor = components.queryItems?.first(where: { $0.name == "anchor" })?.value {
                activeScrollAnchor = anchor
            } else {
                activeScrollAnchor = nil
            }
            select(url: URL(fileURLWithPath: path))
            return .handled
        }

        if url.host == "unresolved", let target = components.queryItems?.first(where: { $0.name == "target" })?.value {
            if let root = activeRootURL {
                selectedURL = nil
                selectedDocument = nil
                selectedRenderedMarkdown = ""
                selectedLinkedFiles = []
                selectedUnresolvedTarget = UnresolvedTarget(targetName: target, folderURL: root)
            }
            return .handled
        }

        errorMessage = "No matching Markdown file found for that link."
        return .handled
    }

    var canNavigateBack: Bool {
        historyIndex > 0
    }

    var canNavigateForward: Bool {
        historyIndex >= 0 && historyIndex < history.count - 1
    }

    func navigateBack() {
        guard canNavigateBack else { return }
        isNavigatingHistory = true
        historyIndex -= 1
        let targetURL = history[historyIndex]
        select(url: targetURL)
        isNavigatingHistory = false
    }

    func navigateForward() {
        guard canNavigateForward else { return }
        isNavigatingHistory = true
        historyIndex += 1
        let targetURL = history[historyIndex]
        select(url: targetURL)
        isNavigatingHistory = false
    }

    func filterHistory() {
        let validURLs = history.filter { url in
            FileManager.default.fileExists(atPath: url.path) && rootURLs.contains(where: { url.isSameFileOrDescendant(of: $0) })
        }
        if validURLs != history {
            if let currentURL = selectedDocument?.url, let index = validURLs.firstIndex(of: currentURL) {
                history = validURLs
                historyIndex = index
            } else {
                history = validURLs
                historyIndex = validURLs.isEmpty ? -1 : validURLs.count - 1
            }
        }
    }

    func fuzzyMatches(for targetName: String) -> [MarkdownDocument] {
        let normalizedQuery = LinkIndex.normalize(targetName)
        return documents.filter { doc in
            let filename = doc.url.deletingPathExtension().lastPathComponent
            let normalizedFile = LinkIndex.normalize(filename)
            let title = doc.title
            let normalizedTitle = LinkIndex.normalize(title)
            
            return normalizedFile.contains(normalizedQuery) ||
                   normalizedQuery.contains(normalizedFile) ||
                   normalizedTitle.contains(normalizedQuery) ||
                   normalizedQuery.contains(normalizedTitle)
        }
    }

    func createDocument(named filename: String, in folderURL: URL) {
        let fileURL = folderURL.appendingPathComponent(filename.hasSuffix(".md") ? filename : "\(filename).md")
        let title = fileURL.deletingPathExtension().lastPathComponent
        let defaultContent = "# \(title)\n\n"
        
        do {
            try defaultContent.write(to: fileURL, atomically: true, encoding: .utf8)
            refresh(sortMode: currentSortMode, keepStatusQuiet: true)
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run {
                    select(url: fileURL)
                }
            }
        } catch {
            errorMessage = "Failed to create note: \(error.localizedDescription)"
        }
    }

    private func internalMarkdownURL(for url: URL) -> URL? {
        guard url.pathExtension.lowercased() == "md" else { return nil }

        let candidate: URL
        if url.isFileURL {
            candidate = url.standardizedFileURL
        } else if url.scheme == nil, let selectedDocument {
            let relativePath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? url.relativeString
            candidate = selectedDocument.url
                .deletingLastPathComponent()
                .appendingPathComponent(relativePath.removingPercentEncoding ?? relativePath)
                .standardizedFileURL
        } else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: candidate.path),
              rootURLs.contains(where: { candidate.isSameFileOrDescendant(of: $0) })
        else {
            return nil
        }

        return candidate
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
        guard let folderURL = folderURLForAI(mode: mode) else { return }
        isRunningAI = true
        pendingDiff = nil
        pendingDiffError = nil
        pendingDiffRootURL = folderURL
        pendingDiffMode = mode
        let actionLabel = mode == .updateReadme ? "rewrite the folder README" : "suggest links"
        statusMessage = "Asking \(provider.rawValue) \(provider.lowestModelName) to \(actionLabel)..."

        Task {
            do {
                let diff = try await AIService().generateLinkPatch(
                    provider: provider,
                    mode: mode,
                    folderURL: folderURL
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
                pendingDiffRootURL = nil
                pendingDiffMode = nil
            }
            isRunningAI = false
        }
    }

    func applyPendingDiff() {
        guard let rootURL = pendingDiffRootURL ?? activeRootURL, let pendingDiff else { return }
        do {
            try DiffApplier().apply(pendingDiff, rootURL: rootURL)
            let appliedMode = pendingDiffMode
            let successMessage = pendingDiffSuccessMessage
            self.pendingDiff = nil
            self.pendingDiffError = nil
            self.pendingDiffRootURL = nil
            self.pendingDiffMode = nil
            self.pendingDiffSuccessMessage = nil
            refresh()
            statusMessage = successMessage ?? (appliedMode == .updateReadme ? "Applied README changes" : "Applied AI link suggestions")
        } catch {
            pendingDiffError = error.localizedDescription
            statusMessage = "Could not apply AI changes"
        }
    }

    func cancelPendingDiff() {
        let discardMessage = pendingDiffSuccessMessage == nil ? "AI link changes discarded" : "Discarded proposed note"
        pendingDiff = nil
        pendingDiffError = nil
        pendingDiffRootURL = nil
        pendingDiffMode = nil
        pendingDiffSuccessMessage = nil
        statusMessage = discardMessage
    }

    /// Proposes creating a brand-new Markdown file as a unified diff so it flows
    /// through the same safe preview/apply path as AI edits. Used by Reading
    /// Trails to write a synthesized note without ever silently touching disk.
    func presentNewNoteProposal(fileName: String, content: String, rootURL: URL? = nil) {
        guard let root = rootURL ?? activeRootURL else {
            errorMessage = "Open a folder before saving a note."
            return
        }

        let relativePath = uniqueRelativeFileName(for: fileName, in: root)
        let bodyLines = content.components(separatedBy: "\n")
        let hunk = DiffHunk(
            header: "@@ -0,0 +1,\(bodyLines.count) @@",
            lines: bodyLines.map { DiffLine(kind: .addition, text: $0) }
        )
        let file = DiffFile(oldPath: "/dev/null", newPath: relativePath, hunks: [hunk])

        pendingDiffRootURL = root
        pendingDiffMode = nil
        pendingDiffError = nil
        pendingDiffSuccessMessage = "Created \(relativePath)"
        pendingDiff = UnifiedDiff(files: [file])
    }

    /// Title for a document URL, used by the Pathfinder HUD and link proposals.
    func title(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        return documents.first { $0.url.standardizedFileURL == standardized }?.title
            ?? url.deletingPathExtension().lastPathComponent
    }

    /// Breadth-first shortest path between two notes over the (undirected)
    /// wiki-link graph. Returns the chain of URLs including both endpoints, or
    /// nil when no link path connects them.
    func wikiLinkPath(from source: URL, to target: URL) -> [URL]? {
        let start = source.standardizedFileURL
        let goal = target.standardizedFileURL
        guard start != goal else { return [start] }
        guard let linkIndex else { return nil }

        var adjacency: [URL: Set<URL>] = [:]
        for document in documents {
            let from = document.url.standardizedFileURL
            for link in document.outboundLinks {
                guard let to = linkIndex.resolve(link).targetURL?.standardizedFileURL, to != from else { continue }
                adjacency[from, default: []].insert(to)
                adjacency[to, default: []].insert(from)
            }
        }

        var queue: [URL] = [start]
        var head = 0
        var previous: [URL: URL] = [:]
        var visited: Set<URL> = [start]

        while head < queue.count {
            let node = queue[head]
            head += 1
            if node == goal {
                var path: [URL] = [goal]
                var cursor = goal
                while let parent = previous[cursor] {
                    path.append(parent)
                    cursor = parent
                }
                return path.reversed()
            }
            for neighbour in adjacency[node] ?? [] where !visited.contains(neighbour) {
                visited.insert(neighbour)
                previous[neighbour] = node
                queue.append(neighbour)
            }
        }
        return nil
    }

    /// Proposes adding a `[[wiki link]]` from `source` to `target` as a unified
    /// diff (safe preview/apply), appending a "## Related" reference.
    func presentLinkProposal(from source: URL, to target: URL) {
        let sourceURL = source.standardizedFileURL
        guard let root = rootURLs.first(where: { sourceURL.isSameFileOrDescendant(of: $0) }) ?? activeRootURL else {
            errorMessage = "Open a folder before linking notes."
            return
        }
        guard let existing = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            errorMessage = "Could not read \(sourceURL.lastPathComponent)."
            return
        }

        let targetTitle = title(for: target)
        let relativePath = sourceURL.relativePath(from: root)

        let lines = existing.components(separatedBy: "\n")
        let lastIndex = max(0, lines.count - 1)
        let contextLine = lines.isEmpty ? "" : lines[lastIndex]

        let additions = ["", "## Related", "", "- [[\(targetTitle)]]"]
        var hunkLines = [DiffLine(kind: .context, text: contextLine)]
        hunkLines.append(contentsOf: additions.map { DiffLine(kind: .addition, text: $0) })

        let header = "@@ -\(lastIndex + 1),1 +\(lastIndex + 1),\(1 + additions.count) @@"
        let file = DiffFile(
            oldPath: relativePath,
            newPath: relativePath,
            hunks: [DiffHunk(header: header, lines: hunkLines)]
        )

        pendingDiffRootURL = root
        pendingDiffMode = nil
        pendingDiffError = nil
        pendingDiffSuccessMessage = "Linked [[\(targetTitle)]] into \(sourceURL.lastPathComponent)"
        pendingDiff = UnifiedDiff(files: [file])
    }

    private func uniqueRelativeFileName(for fileName: String, in root: URL) -> String {
        let sanitized = fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let nsName = sanitized as NSString
        let ext = nsName.pathExtension.isEmpty ? "md" : nsName.pathExtension
        let base = nsName.deletingPathExtension

        var candidate = "\(base).\(ext)"
        var counter = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    func folderURLForAI(mode: AIMode) -> URL? {
        guard mode == .updateReadme else { return activeRootURL }

        if let selectedDocument, selectedDocument.isReadme {
            return selectedDocument.url.deletingLastPathComponent().standardizedFileURL
        }

        if let selectedURL {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return selectedURL.standardizedFileURL
            }
        }

        return activeRootURL
    }

    private func rootNode(for rootURL: URL, sortMode: FileSortMode) throws -> MarkdownNode {
        let values = try rootURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let children = try FolderScanner(fileSortMode: sortMode).scan(rootURL: rootURL)
        let readmeURL = rootURL.appendingPathComponent("README.md")
        return MarkdownNode(
            id: rootURL.standardizedFileURL,
            name: displayName(forRoot: rootURL),
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

    private func restoreFolders(includeBundledDemo: Bool) {
        rootDisplayNames = UserDefaults.standard.dictionary(forKey: Keys.folderDisplayNames) as? [String: String] ?? [:]
        let bookmarkedURLs = restoreBookmarkedFolders()
        let paths = UserDefaults.standard.stringArray(forKey: Keys.folderPaths)
        let legacyPath = UserDefaults.standard.string(forKey: Keys.legacyLastFolderPath)
        let pathURLs = (paths ?? legacyPath.map { [$0] } ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }

        rootURLs = (bookmarkedURLs + pathURLs)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .uniqued()

        if includeBundledDemo {
            seedBundledDemoIfNeeded()
        }

        if !rootURLs.isEmpty {
            rootURLs.forEach(startAccessingFolder)
            persistFolders()
            refresh()
            startMonitoring()
        }
    }

    private func seedBundledDemoIfNeeded() {
        let defaults = UserDefaults.standard
        let alreadySeeded = defaults.string(forKey: Keys.bundledDemoNotesVersion) == Self.bundledDemoNotesVersion
        let installedDemoURL = Self.applicationSupportDirectory()
            .appendingPathComponent("DemoNotes", isDirectory: true)
            .standardizedFileURL
        let shouldInstallDemo = rootURLs.isEmpty || rootURLs.contains(installedDemoURL)
        guard !alreadySeeded,
              shouldInstallDemo,
              let bundledDemoURL = Self.bundledResourceURL(forResource: "DemoNotes", withExtension: nil)
        else { return }

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: installedDemoURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: installedDemoURL.path) {
                try fileManager.removeItem(at: installedDemoURL)
            }
            try fileManager.copyItem(at: bundledDemoURL, to: installedDemoURL)
            if !rootURLs.contains(installedDemoURL) {
                rootURLs.append(installedDemoURL)
            }
            defaults.set(Self.bundledDemoNotesVersion, forKey: Keys.bundledDemoNotesVersion)
        } catch {
            DiagnosticsCenter.shared.record(level: .error, message: "Failed to install DemoNotes: \(error.localizedDescription)")
        }
    }

    /// Locate a bundled resource WITHOUT ever touching SwiftPM's generated
    /// `Bundle.module` accessor.
    ///
    /// `Bundle.module` is a `static let` whose generated initializer calls
    /// `fatalError("unable to find bundle …")` when the resource bundle isn't
    /// at one of its hard-coded paths. In a packaged/notarized `.app` the
    /// SwiftPM resource bundle lives at `Contents/Resources/<Name>.bundle`,
    /// which that accessor doesn't reliably check — so on other machines the
    /// very first access trapped at launch (EXC_BREAKPOINT) inside
    /// `seedBundledDemoIfNeeded()`. We instead probe candidate locations with
    /// the non-trapping `Bundle(url:)` initializer and return `nil` when the
    /// resource genuinely isn't present, letting callers degrade gracefully.
    static func bundledResourceURL(
        forResource name: String,
        withExtension ext: String?,
        subdirectory: String? = nil
    ) -> URL? {
        func lookup(in bundle: Bundle) -> URL? {
            if let subdirectory,
               let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
            return bundle.url(forResource: name, withExtension: ext)
        }

        // 1. Flat in the app's main bundle (Contents/Resources/<name>).
        if let url = lookup(in: .main) {
            return url
        }

        let moduleBundleName = "Cribble_Cribble.bundle"
        let classBundle = Bundle(for: MarkdownLibraryStore.self)

        // 2. Inside the SwiftPM resource bundle at known candidate roots.
        var searchBases: [URL] = []
        if let resourceURL = Bundle.main.resourceURL { searchBases.append(resourceURL) }
        searchBases.append(Bundle.main.bundleURL)
        searchBases.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        if let resourceURL = classBundle.resourceURL { searchBases.append(resourceURL) }
        searchBases.append(classBundle.bundleURL)

        for base in searchBases {
            let candidate = base.appendingPathComponent(moduleBundleName)
            if let bundle = Bundle(url: candidate), let url = lookup(in: bundle) {
                return url
            }
        }

        // 3. Last resort: scan resource directories for any *.bundle that
        //    happens to carry the resource (covers unexpected layouts).
        let scanDirs = [Bundle.main.resourceURL, classBundle.resourceURL].compactMap { $0 }
        let fileManager = FileManager.default
        for dir in scanDirs {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ) else { continue }
            for entry in entries where entry.pathExtension == "bundle" {
                if let bundle = Bundle(url: entry), let url = lookup(in: bundle) {
                    return url
                }
            }
        }

        return nil
    }

    private func persistFolders() {
        UserDefaults.standard.set(rootURLs.map(\.path), forKey: Keys.folderPaths)
        // Cribble ships unsandboxed via Developer ID, so plain bookmarks are
        // enough to survive folder renames/moves. Security-scoped bookmarks
        // require the app sandbox + user-selected file entitlement; calling
        // them here on a non-sandboxed binary silently throws and used to
        // wipe the persisted folder list on every clean machine.
        let bookmarks = rootURLs.compactMap { url in
            try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        UserDefaults.standard.set(bookmarks, forKey: Keys.folderBookmarks)
        persistFolderDisplayNames()
    }

    private func persistFolderDisplayNames() {
        let rootPaths = Set(rootURLs.map(\.standardizedFileURL.path))
        rootDisplayNames = rootDisplayNames.filter { rootPaths.contains($0.key) }
        UserDefaults.standard.set(rootDisplayNames, forKey: Keys.folderDisplayNames)
    }

    private func displayName(forRoot url: URL) -> String {
        rootDisplayNames[url.standardizedFileURL.path] ?? url.lastPathComponent
    }

    private func restoreBookmarkedFolders() -> [URL] {
        let bookmarks = UserDefaults.standard.array(forKey: Keys.folderBookmarks) as? [Data] ?? []
        return bookmarks.compactMap { bookmark in
            var isStale = false
            // Try plain bookmarks first (current format). Fall back to
            // security-scoped resolution so that defaults written by older
            // builds (which used .withSecurityScope) still round-trip.
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL {
                startAccessingFolder(url)
                return url
            }

            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
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
        // No-op for unsandboxed builds. Kept as a hook so callers don't
        // change shape if Cribble is ever sandboxed (App Store target etc.).
        _ = url
    }

    private func stopAccessingFolder(_ url: URL) {
        _ = url
    }

    private func stopAccessingAllFolders() {
        // No-op for unsandboxed builds.
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

    private static let bundledDemoNotesVersion = "1.1.1"

    private static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Cribble", isDirectory: true)
    }

    private enum Keys {
        static let folderBookmarks = "folderBookmarks"
        static let folderDisplayNames = "folderDisplayNames"
        static let folderPaths = "folderPaths"
        static let pinnedFolders = "pinnedFolders"
        static let legacyLastFolderPath = "lastFolderPath"
        static let bundledDemoNotesVersion = "bundledDemoNotesVersion"
    }
}

private extension URL {
    func isSameFileOrDescendant(of rootURL: URL) -> Bool {
        let path = standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}
