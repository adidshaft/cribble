import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
    /// Folder path -> chosen SF Symbol name, for custom sidebar folder icons.
    @Published private(set) var folderIcons: [String: String] = [:]
    @Published private var rootDisplayNames: [String: String] = [:]

    private let loader = DocumentLoader()
    private let monitor = FileChangeMonitor()
    private struct RefreshFileSignature: Equatable, Sendable {
        let modifiedAt: TimeInterval
        let fileSize: Int
    }
    /// Body-free metadata for every note in the open folders. The full text is
    /// loaded on demand (for the selected note, semantic re-embeds, previews) so
    /// a large vault never pins all note contents in RAM.
    private(set) var documents: [MarkdownDocumentMeta] = []
    private var documentRefreshSignatures: [String: RefreshFileSignature] = [:]
    private var linkIndex: LinkIndex?
    private var currentSortMode: FileSortMode = .name
    private var renderTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var pendingDiffRootURL: URL?
    private var pendingDiffMode: AIMode?
    private var pendingDiffSuccessMessage: String?
    // While set (briefly after a checkbox write), the file monitor ignores the
    // filesystem echo of our own write instead of triggering a full rescan.
    private var selfWriteSuppressionDeadline: Date?

    // LRU render cache. Keyed by document URL; entries are invalidated when
    // the underlying file content or remote-image policy changes.
    // Bounded so a long browsing session can't pin all rendered HTML in RAM.
    private struct RenderCacheEntry {
        let contentHash: UInt64
        let loadRemoteImages: Bool
        let rendered: String
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

    /// Whether this instance persists session state (last-opened note). False
    /// for test/preview instances so they don't pollute UserDefaults.
    private let persistsState: Bool

    init(restore: Bool = true, includeBundledDemo: Bool = true) {
        persistsState = restore
        if restore {
            pinnedPaths = Set(UserDefaults.standard.stringArray(forKey: Keys.pinnedFolders) ?? [])
            folderIcons = UserDefaults.standard.dictionary(forKey: Keys.folderIcons) as? [String: String] ?? [:]
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

    /// The chosen SF Symbol for a folder, or nil for the default folder icon.
    func folderIcon(for url: URL) -> String? {
        folderIcons[url.standardizedFileURL.path]
    }

    /// Assigns (or, with nil, clears) a custom SF Symbol icon for a folder.
    func setFolderIcon(_ symbol: String?, for url: URL) {
        let key = url.standardizedFileURL.path
        if let symbol, !symbol.isEmpty {
            folderIcons[key] = symbol
        } else {
            folderIcons.removeValue(forKey: key)
        }
        UserDefaults.standard.set(folderIcons, forKey: Keys.folderIcons)
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

    func chooseImportFile(capabilities: [ExtensionImporterCapability]) {
        guard !capabilities.isEmpty else {
            statusMessage = "No import lanes are enabled"
            return
        }

        var seenExtensions: Set<String> = []
        let extensions = capabilities
            .flatMap(\.fileExtensions)
            .map { $0.lowercased() }
            .filter { seenExtensions.insert($0).inserted }
        let panel = NSOpenPanel()
        panel.title = "Choose File to Import"
        panel.prompt = "Choose"
        panel.message = "Cribble will match this file to an enabled declarative import lane. Converter execution is not enabled yet."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let contentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        if !contentTypes.isEmpty {
            panel.allowedContentTypes = contentTypes
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let ext = url.pathExtension.lowercased()
        let matches = capabilities.filter { $0.fileExtensions.contains(ext) }
        if let match = matches.first {
            statusMessage = "Matched \(url.lastPathComponent) to \(match.title) (\(match.outputFormat)); converter execution is not enabled yet"
        } else {
            statusMessage = "No enabled import lane matches .\(ext)"
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

    func openDemoLibrary(sortMode: FileSortMode, reset: Bool = false) {
        do {
            let demoURL = try installBundledDemo(reset: reset)
            openFolder(demoURL, sortMode: sortMode)
            let readmeURL = demoURL.appendingPathComponent("README.md")
            if FileManager.default.fileExists(atPath: readmeURL.path) {
                select(url: readmeURL)
            }
            statusMessage = reset ? "Reset and opened DemoNotes" : "Opened DemoNotes"
        } catch {
            errorMessage = "Couldn't open DemoNotes: \(error.localizedDescription)"
        }
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
        let previousDocuments = Dictionary(uniqueKeysWithValues: documents.map { ($0.url.standardizedFileURL.path, $0) })
        let previousSignatures = documentRefreshSignatures

        loadTask?.cancel()
        let concurrency = Self.loadConcurrency
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (nodes: [MarkdownNode], documents: [MarkdownDocumentMeta], signatures: [String: RefreshFileSignature], linkIndex: LinkIndex?, reusedCount: Int, loadedCount: Int, skippedFiles: [URL], failedRoots: [URL]) in
                    var nodesList: [MarkdownNode] = []
                    var failedRoots: [URL] = []
                    for rootURL in roots {
                        // A single unscannable root (permissions, an offline
                        // iCloud folder, etc.) must not take down every other
                        // folder — skip it and report it instead.
                        do {
                            let values = try rootURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                            let children = try FolderScanner(fileSortMode: sort, autoCreateReadmes: false).scan(rootURL: rootURL)
                            let readmeURL = Self.existingReadmeURL(in: rootURL)
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
                    let fileSignatures = Dictionary(uniqueKeysWithValues: urls.compactMap { url -> (String, RefreshFileSignature)? in
                        guard let signature = Self.refreshFileSignature(for: url) else { return nil }
                        return (url.standardizedFileURL.path, signature)
                    })
                    var reusedDocuments: [String: MarkdownDocumentMeta] = [:]
                    var urlsToLoad: [URL] = []
                    urlsToLoad.reserveCapacity(urls.count)
                    for url in urls {
                        let path = url.standardizedFileURL.path
                        if let signature = fileSignatures[path],
                           previousSignatures[path] == signature,
                           let previousDocument = previousDocuments[path] {
                            reusedDocuments[path] = previousDocument
                        } else {
                            urlsToLoad.append(url)
                        }
                    }

                    // Bounded-concurrency fan-out. Each file loads independently:
                    // a file that can't be read (unsupported encoding handled in
                    // DocumentLoader, an offline iCloud placeholder, a permission
                    // error) is skipped and reported rather than aborting the
                    // whole folder open — real Obsidian/iCloud vaults routinely
                    // contain such files.
                    let outcomes = await withTaskGroup(of: (URL, MarkdownDocument?).self) { group -> [(URL, MarkdownDocument?)] in
                        var iterator = urlsToLoad.makeIterator()
                        var inFlight = 0
                        while inFlight < concurrency, let url = iterator.next() {
                            group.addTask { (url, try? loader.load(url: url)) }
                            inFlight += 1
                        }
                        var collected: [(URL, MarkdownDocument?)] = []
                        collected.reserveCapacity(urlsToLoad.count)
                        while let outcome = await group.next() {
                            collected.append(outcome)
                            if let url = iterator.next() {
                                group.addTask { (url, try? loader.load(url: url)) }
                            }
                        }
                        return collected
                    }

                    var loadedMetas: [String: MarkdownDocumentMeta] = [:]
                    loadedMetas.reserveCapacity(outcomes.count)
                    var skippedFiles: [URL] = []
                    for (url, document) in outcomes {
                        if let document {
                            loadedMetas[url.standardizedFileURL.path] = MarkdownDocumentMeta(document)
                        } else {
                            skippedFiles.append(url)
                        }
                    }

                    let metas = urls.compactMap { url -> MarkdownDocumentMeta? in
                        let path = url.standardizedFileURL.path
                        return reusedDocuments[path] ?? loadedMetas[path]
                    }

                    let index: LinkIndex?
                    if let firstRoot = roots.first {
                        index = LinkIndex(documentMetas: metas, rootURL: firstRoot)
                    } else {
                        index = nil
                    }

                    return (nodesList, metas, fileSignatures, index, reusedDocuments.count, loadedMetas.count, skippedFiles, failedRoots)
                }.value

                guard !Task.isCancelled else { return }

                self.nodes = result.nodes
                self.documents = result.documents
                self.documentRefreshSignatures = result.signatures
                self.linkIndex = result.linkIndex
                // Render cache keys by URL, so prune entries whose file changed
                // or disappeared while preserving unchanged notes across a full
                // folder refresh. This keeps back/forward navigation warm after
                // a single external edit without depending on fragile changed
                // path delivery from FSEvents.
                self.pruneRenderCache(using: result.documents)
                self.filterHistory()

                if let selectedURL = self.selectedURL {
                    self.select(url: selectedURL)
                } else if let restored = self.restorableLastOpenedURL() {
                    self.select(url: restored)
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
                if result.reusedCount > 0 {
                    DiagnosticsCenter.shared.record(
                        level: .info,
                        message: "Refresh reused \(result.reusedCount) unchanged note metadata record(s); loaded \(result.loadedCount) changed/new note(s)."
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

    func waitForRenderToComplete() async {
        _ = await renderTask?.result
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
            if persistsState {
                UserDefaults.standard.set(documentURL.standardizedFileURL.path, forKey: Keys.lastOpenedFile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleRender(for document: MarkdownDocument) {
        renderTask?.cancel()

        // Fast path: if we already rendered this exact body recently
        // (back/forward navigation, or re-select), publish the cached
        // version synchronously and skip the detached pipeline entirely.
        let loadRemoteImages = UserDefaults.standard.bool(forKey: "loadRemoteImages")
        let documentRoot = rootURL(for: document.url)
        let contentHash = SemanticSearchIndex.stableHash(title: document.title, body: document.rawMarkdown)
        if let cached = renderCache[document.url],
           cached.contentHash == contentHash,
           cached.loadRemoteImages == loadRemoteImages {
            selectedRenderedMarkdown = cached.rendered
            selectedLinkedFiles = Self.linkedFiles(
                for: document,
                index: linkIndex,
                allDocuments: documents
            )
            touchRenderCacheEntry(for: document.url)
            return
        }

        let index = linkIndex
        let documentsSnapshot = documents
        let documentURL = document.url
        renderTask = Task { [document, index, documentsSnapshot, documentURL, contentHash, documentRoot, loadRemoteImages] in
            let result = await Task.detached(priority: .userInitiated) { () -> (rendered: String, linkedFiles: [LinkedFileSummary]) in
                let preprocessed = MarkdownDisplayPreprocessor.prepare(
                    document.rawMarkdown,
                    documentTitle: document.title
                )
                // Normalize embeds / HTML <img> / attachment-folder paths into
                // resolvable image refs *before* the wiki-link pass (which would
                // otherwise mangle `![[…]]` embeds).
                let withImages = MarkdownImageRewriter.rewrite(
                    preprocessed,
                    noteDirectory: document.url.deletingLastPathComponent(),
                    rootURL: documentRoot,
                    loadRemoteImages: loadRemoteImages
                )
                let rendered = WikiLinkParser.renderForMarkdown(withImages, index: index)
                let linkedFiles = MarkdownLibraryStore.linkedFiles(
                    for: document,
                    index: index,
                    allDocuments: documentsSnapshot
                )
                return (rendered, linkedFiles)
            }.value
            guard !Task.isCancelled else { return }
            guard selectedDocument?.url == documentURL else { return }
            selectedRenderedMarkdown = result.rendered
            selectedLinkedFiles = result.linkedFiles
            storeRenderCacheEntry(
                url: documentURL,
                entry: RenderCacheEntry(
                    contentHash: contentHash,
                    loadRemoteImages: loadRemoteImages,
                    rendered: result.rendered
                )
            )
        }
    }

    func rerenderSelectedDocument() {
        guard let selectedDocument else { return }
        scheduleRender(for: selectedDocument)
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

    nonisolated private static func refreshFileSignature(for url: URL) -> RefreshFileSignature? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modifiedAt = values.contentModificationDate,
              let fileSize = values.fileSize
        else { return nil }
        return RefreshFileSignature(
            modifiedAt: modifiedAt.timeIntervalSinceReferenceDate,
            fileSize: fileSize
        )
    }

    private func pruneRenderCache(using documents: [MarkdownDocumentMeta]) {
        let hashesByPath = Dictionary(uniqueKeysWithValues: documents.map { meta in
            (meta.url.standardizedFileURL.path, meta.contentHash)
        })

        renderCache = renderCache.filter { url, entry in
            hashesByPath[url.standardizedFileURL.path] == entry.contentHash
        }
        renderCacheOrder.removeAll { renderCache[$0] == nil }
    }

    nonisolated private static func linkedFiles(
        for document: MarkdownDocument,
        index: LinkIndex?,
        allDocuments: [MarkdownDocumentMeta]
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
            let anchor = components.queryItems?.first(where: { $0.name == "anchor" })?.value
            select(url: URL(fileURLWithPath: path))
            if let anchor, anchor.hasPrefix("^") {
                // Block reference (`#^id`): map it to the enclosing heading
                // section of the just-loaded document so the reader can scroll
                // close to the exact line.
                let blockID = String(anchor.dropFirst())
                activeScrollAnchor = selectedDocument
                    .map { Self.sectionAnchor(forBlockID: blockID, in: $0.rawMarkdown) } ?? nil
            } else {
                activeScrollAnchor = anchor
            }
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

    /// Finds the line carrying the Obsidian-style block anchor `^blockID` and
    /// returns the slug of its nearest preceding heading — the scroll target the
    /// reader understands. Returns "top" when the block sits above any heading,
    /// and nil when the anchor isn't found.
    nonisolated static func sectionAnchor(forBlockID blockID: String, in markdown: String) -> String? {
        let lines = markdown.components(separatedBy: "\n")
        var currentHeadingSlug = "top"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let markerCount = trimmed.prefix { $0 == "#" }.count
                if (1...6).contains(markerCount) {
                    let title = trimmed.dropFirst(markerCount).trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty { currentHeadingSlug = title.textualSlug() }
                }
            }
            if TaskCheckbox.blockAnchor(in: line) == blockID {
                return currentHeadingSlug
            }
        }
        return nil
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

    func fuzzyMatches(for targetName: String) -> [MarkdownDocumentMeta] {
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

        // If the note already exists, never clobber it — just open it.
        if FileManager.default.fileExists(atPath: fileURL.standardizedFileURL.path) {
            statusMessage = "\(fileURL.lastPathComponent) already exists — opening it"
            select(url: fileURL)
            return
        }

        do {
            try SafeFileWriter.create(defaultContent, at: fileURL)
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

    /// Proposes appending content to the end of an existing note, routed through
    /// the same safe diff preview/apply path. Used by the chat HUD's "Insert into
    /// current note" action. The whole file is shown as context so the patch
    /// always applies cleanly.
    func presentAppendProposal(to url: URL, content: String, rootURL: URL? = nil) {
        guard let root = rootURL ?? activeRootURL else {
            errorMessage = "Open a folder before inserting into a note."
            return
        }
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "Couldn't read \(url.lastPathComponent)."
            return
        }

        let rootPath = root.standardizedFileURL.path
        let relativePath = url.standardizedFileURL.path.hasPrefix(rootPath + "/")
            ? String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            : url.lastPathComponent

        let existingLines = existing.components(separatedBy: "\n")
        let addedLines = ["", "---", ""] + content.components(separatedBy: "\n")
        let hunkLines = existingLines.map { DiffLine(kind: .context, text: $0) }
            + addedLines.map { DiffLine(kind: .addition, text: $0) }
        let hunk = DiffHunk(
            header: "@@ -1,\(existingLines.count) +1,\(existingLines.count + addedLines.count) @@",
            lines: hunkLines
        )
        let file = DiffFile(oldPath: relativePath, newPath: relativePath, hunks: [hunk])

        pendingDiffRootURL = root
        pendingDiffMode = nil
        pendingDiffError = nil
        pendingDiffSuccessMessage = "Inserted into \(relativePath)"
        pendingDiff = UnifiedDiff(files: [file])
    }

    /// Path of a file relative to whichever opened root contains it (e.g.
    /// "Projects/Auth.md"), or nil if it isn't inside an opened folder.
    func relativePath(for url: URL) -> String? {
        let path = url.standardizedFileURL.path
        for root in rootURLs {
            let rootPath = root.standardizedFileURL.path
            if path.hasPrefix(rootPath + "/") {
                return String(path.dropFirst(rootPath.count + 1))
            }
        }
        return nil
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
        let children = try FolderScanner(fileSortMode: sortMode, autoCreateReadmes: false).scan(rootURL: rootURL)
        let readmeURL = Self.existingReadmeURL(in: rootURL)
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
            guard let self else { return }
            // Ignore the filesystem echo of our own checkbox write — we already
            // updated the document in place, and a full rescan here would be
            // wasteful and could fight the optimistic UI.
            if let deadline = self.selfWriteSuppressionDeadline, Date() < deadline {
                return
            }
            self.refresh(keepStatusQuiet: true)
        }
    }

    /// Flips a single Markdown task checkbox (the only in-reader write Cribble
    /// makes to a note). Writes one byte, then reloads just that document in
    /// place so the change is reflected without a full library rescan.
    func toggleTaskCheckbox(in documentURL: URL, ordinal: Int, currentlyChecked: Bool) {
        let url = documentURL.standardizedFileURL
        do {
            let result = try TaskCheckbox.toggle(
                fileURL: url,
                ordinal: ordinal,
                expectedCurrentChecked: currentlyChecked
            )
            switch result {
            case .toggled:
                selfWriteSuppressionDeadline = Date().addingTimeInterval(1.5)
                reloadDocumentInPlace(url)
            case .stateMismatch:
                // The on-disk checkbox no longer matches what we rendered (edited
                // elsewhere). Reload so the reader reflects the real state.
                reloadDocumentInPlace(url)
                statusMessage = "Checkbox changed on disk — reloaded"
            case .notFound:
                DiagnosticsCenter.shared.record(level: .warning, message: "Could not locate task checkbox #\(ordinal) in \(url.lastPathComponent)")
            }
        } catch {
            errorMessage = "Couldn't update the checkbox: \(error.localizedDescription)"
        }
    }

    /// Sends a note's checkbox to a tracker. Always records it in the vault's
    /// `Tasks.md` aggregator (backlinked to the exact source line via a block
    /// anchor), and optionally also creates a Reminder / Calendar event.
    func addTaskToTracker(in documentURL: URL, ordinal: Int, exportTo target: TaskExportTarget?) async {
        let url = documentURL.standardizedFileURL
        let located: TaskCheckbox.LocatedTask?
        do {
            located = try TaskCheckbox.locateAndAnchor(fileURL: url, ordinal: ordinal)
        } catch {
            errorMessage = "Couldn't read the task: \(error.localizedDescription)"
            return
        }
        guard let located, !located.label.isEmpty else {
            statusMessage = "Couldn't locate that checkbox"
            return
        }

        // The anchor may have just been written into the source note.
        selfWriteSuppressionDeadline = Date().addingTimeInterval(1.5)
        reloadDocumentInPlace(url)

        let stem = url.deletingPathExtension().lastPathComponent
        let backlink = "[[\(stem)#^\(located.anchor)]]"
        let addedToTasks = appendToTasksFile(root: rootURL(for: url), label: located.label, backlink: backlink)

        guard let target else {
            statusMessage = addedToTasks ? "Added to Tasks" : "Already in Tasks"
            return
        }
        do {
            let notes = "From Cribble note: \(stem)\n\(backlink)"
            try await TaskExporter.export(target, title: located.label, notes: notes)
            statusMessage = target == .reminders ? "Added to Reminders" : "Added to Calendar"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Appends a task to the vault-root `Tasks.md`, creating it if missing and
    /// de-duplicating by backlink. This is the single living index of everything
    /// the user has flagged across the whole vault.
    @discardableResult
    private func appendToTasksFile(root: URL?, label: String, backlink: String) -> Bool {
        guard let root else { return false }
        let tasksURL = root.appendingPathComponent("Tasks.md").standardizedFileURL
        var existing = (try? String(contentsOf: tasksURL, encoding: .utf8)) ?? ""
        if existing.isEmpty {
            existing = "# Tasks\n\nCollected from your notes by Cribble. Each item links back to its source.\n\n"
        }
        guard !existing.contains(backlink) else {
            return false
        }
        if !existing.hasSuffix("\n") { existing += "\n" }
        existing += "- [ ] \(label) — \(backlink)\n"
        do {
            selfWriteSuppressionDeadline = Date().addingTimeInterval(1.5)
            try SafeFileWriter.overwrite(existing, at: tasksURL)
            if documents.contains(where: { $0.url.standardizedFileURL == tasksURL }) {
                reloadDocumentInPlace(tasksURL)
            } else {
                refresh(keepStatusQuiet: true)
            }
            return true
        } catch {
            errorMessage = "Couldn't update Tasks.md: \(error.localizedDescription)"
            return false
        }
    }

    /// Opens (creating if needed) the vault's `Tasks.md` aggregator.
    func openTasksFile() {
        guard let root = activeRootURL else {
            statusMessage = "Open a folder to collect tasks"
            return
        }
        let tasksURL = root.appendingPathComponent("Tasks.md").standardizedFileURL
        if !FileManager.default.fileExists(atPath: tasksURL.path) {
            let seed = "# Tasks\n\nCollected from your notes by Cribble. Each item links back to its source.\n"
            try? SafeFileWriter.create(seed, at: tasksURL)
            refresh(keepStatusQuiet: true)
        }
        select(url: tasksURL)
    }

    /// Whether the currently open note has a Cribble backup that can be reverted.
    var canUndoSelectedNote: Bool {
        guard let url = selectedDocument?.url else { return false }
        return SafeFileWriter.hasBackup(for: url)
    }

    /// Reverts the open note to the most recent contents Cribble backed up before
    /// one of its own writes (a checkbox flip, AI diff, task anchor, etc.).
    func undoLastChangeToSelectedNote() {
        guard let url = selectedDocument?.url else {
            statusMessage = "Open a note to undo"
            return
        }
        let standardized = url.standardizedFileURL
        selfWriteSuppressionDeadline = Date().addingTimeInterval(1.5)
        if SafeFileWriter.restoreMostRecentBackup(for: standardized) != nil {
            reloadDocumentInPlace(standardized)
            statusMessage = "Reverted \(url.lastPathComponent) to the previous version"
        } else {
            statusMessage = "No Cribble backup to undo for \(url.lastPathComponent)"
        }
    }

    private func reloadDocumentInPlace(_ url: URL) {
        guard let reloaded = try? loader.load(url: url) else { return }
        if let index = documents.firstIndex(where: { $0.url.standardizedFileURL == url }) {
            documents[index] = MarkdownDocumentMeta(reloaded)
        }
        documentRefreshSignatures[url.standardizedFileURL.path] = Self.refreshFileSignature(for: url)
        renderCache.removeValue(forKey: reloaded.url)
        renderCacheOrder.removeAll { $0 == reloaded.url }
        if selectedDocument?.url.standardizedFileURL == url {
            selectedDocument = reloaded
            scheduleRender(for: reloaded)
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
            .filter(Self.isExistingDirectory)
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
        let installedDemoURL = Self.installedDemoNotesURL()
        let shouldInstallDemo = rootURLs.isEmpty || rootURLs.contains(installedDemoURL)
        guard shouldInstallDemo else { return }

        do {
            let demoURL = try installBundledDemo(reset: !alreadySeeded)
            if !rootURLs.contains(demoURL) {
                rootURLs.append(demoURL)
            }
            defaults.set(Self.bundledDemoNotesVersion, forKey: Keys.bundledDemoNotesVersion)
        } catch {
            DiagnosticsCenter.shared.record(level: .error, message: "Failed to install DemoNotes: \(error.localizedDescription)")
        }
    }

    private func installBundledDemo(reset: Bool) throws -> URL {
        let installedDemoURL = Self.applicationSupportDirectory()
            .appendingPathComponent("DemoNotes", isDirectory: true)
            .standardizedFileURL
        guard let bundledDemoURL = Self.bundledResourceURL(forResource: "DemoNotes", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: installedDemoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: installedDemoURL.path) {
            if reset {
                try fileManager.removeItem(at: installedDemoURL)
                try fileManager.copyItem(at: bundledDemoURL, to: installedDemoURL)
            } else {
                try Self.copyMissingDemoItems(from: bundledDemoURL, to: installedDemoURL)
            }
        } else {
            try fileManager.copyItem(at: bundledDemoURL, to: installedDemoURL)
        }
        UserDefaults.standard.set(Self.bundledDemoNotesVersion, forKey: Keys.bundledDemoNotesVersion)
        return installedDemoURL
    }

    nonisolated private static func copyMissingDemoItems(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let sourceItems = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        for sourceItem in sourceItems {
            let destinationItem = destinationURL.appendingPathComponent(sourceItem.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationItem.path) else { continue }
            try fileManager.copyItem(at: sourceItem, to: destinationItem)
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
            return Self.existingReadmeURL(in: url)
        }

        return url.pathExtension.lowercased() == "md" ? url : nil
    }

    nonisolated private static func existingReadmeURL(in folderURL: URL) -> URL? {
        let readmeURL = folderURL.appendingPathComponent("README.md")
        return FileManager.default.fileExists(atPath: readmeURL.path) ? readmeURL : nil
    }

    nonisolated private static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
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

    /// The last note the user had open, if it still exists inside a currently
    /// open folder — so launching reopens where they left off instead of jumping
    /// to the first file.
    private func restorableLastOpenedURL() -> URL? {
        guard persistsState,
              let path = UserDefaults.standard.string(forKey: Keys.lastOpenedFile),
              !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              rootURLs.contains(where: { url.isSameFileOrDescendant(of: $0) }) else { return nil }
        return url
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

    private static let bundledDemoNotesVersion = "1.3.1"

    private static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Cribble", isDirectory: true)
    }

    private static func installedDemoNotesURL() -> URL {
        applicationSupportDirectory()
            .appendingPathComponent("DemoNotes", isDirectory: true)
            .standardizedFileURL
    }

    private enum Keys {
        static let folderBookmarks = "folderBookmarks"
        static let folderDisplayNames = "folderDisplayNames"
        static let folderPaths = "folderPaths"
        static let pinnedFolders = "pinnedFolders"
        static let folderIcons = "folderIcons"
        static let legacyLastFolderPath = "lastFolderPath"
        static let lastOpenedFile = "lastOpenedFile"
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
