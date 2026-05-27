import AppKit
import SwiftUI
import Textual

struct ReaderView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if let unresolved = library.selectedUnresolvedTarget {
                UnresolvedTargetView(target: unresolved)
            } else if let document = library.selectedDocument {
                ReaderDocumentView(
                    document: document,
                    rendered: library.selectedRenderedMarkdown,
                    linkedFiles: library.selectedLinkedFiles,
                    showLinkedFileCards: settings.showLinkedFileCards,
                    fontScale: settings.readerFontScale,
                    isRunningAI: library.isRunningAI,
                    onSelectLink: { library.select(url: $0.url) },
                    onOpenURL: { library.handleOpenURL($0) },
                    onFillReadme: { provider in
                        library.runAILinking(provider: provider, mode: .updateReadme)
                    }
                )
                .id(document.url)
            } else {
                WelcomeView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = library.statusMessage {
                HStack {
                    if library.isRunningAI {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .cribbleGlass(in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }
}

@MainActor
private final class ReaderScrollState {
    var offsetY: Double = 0
}

private struct ReaderDocumentView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var readingAnnotations: ReadingAnnotationsStore
    // Reference type so the bridge's per-scroll-tick writes don't invalidate
    // this view's body (which used to re-trigger LazyVStack diffing and
    // updateNSView on every pixel of scrolling — the dominant lag source).
    @State private var scrollState = ReaderScrollState()
    @State private var restoreScrollOffsetY: Double?
    @State private var currentSectionTitle: String?
    @State private var restoredDocumentURL: URL?
    @State private var isHighlightMode = false
    @State private var lastHighlightedQuote: String?
    @State private var shortcutToken = UUID()

    let document: MarkdownDocument
    let rendered: String
    let linkedFiles: [LinkedFileSummary]
    let showLinkedFileCards: Bool
    let fontScale: Double
    let isRunningAI: Bool
    let onSelectLink: (LinkedFileSummary) -> Void
    let onOpenURL: (URL) -> OpenURLAction.Result
    let onFillReadme: (AIProvider) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ScrollPositionBridge(
                            scrollState: scrollState,
                            targetOffsetY: $restoreScrollOffsetY
                        )
                        .frame(width: 0, height: 0)

                        if let bookmark = readingAnnotations.bookmark(for: document.url) {
                            ReadingBookmarkStrip(
                                bookmark: bookmark,
                                documentURL: document.url
                            ) {
                                resumeBookmark(bookmark)
                            }
                        }

                        Text(document.title)
                            .font(.system(size: 30 * fontScale))
                            .fontWeight(.semibold)
                            .textSelection(.enabled)

                        if showLinkedFileCards, !linkedFiles.isEmpty {
                            LinkedFilesCardPanel(links: linkedFiles, onSelect: onSelectLink)
                        }

                        if document.isEssentiallyEmptyReadme {
                            EmptyReadmePanel(
                                folderName: document.url.deletingLastPathComponent().lastPathComponent,
                                isRunningAI: isRunningAI,
                                onFillReadme: onFillReadme
                            )
                        } else if rendered.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.top, 8)
                        } else {
                            // LazyVStack so a 10 MB note with hundreds of
                            // sections doesn't eagerly parse + lay out every
                            // section on first appearance. Combined with the
                            // sectioning logic above, only what's near the
                            // viewport pays the StructuredText parse cost.
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(ReadingSection.sections(from: rendered)) { section in
                                    ReaderMarkdownSection(
                                        section: section,
                                        baseURL: document.url.deletingLastPathComponent(),
                                        fontScale: fontScale,
                                        highlights: readingAnnotations.highlights(for: document.url)
                                    )
                                    .id(section.anchor)
                                    .background {
                                        SectionVisibilityReporter(section: section)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: settings.isFocusMode ? 640 : 840, alignment: .leading)
                    .padding(.horizontal, settings.isFocusMode ? 56 : 42)
                    .padding(.vertical, 34)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .coordinateSpace(name: "readerScroll")
                .onPreferenceChange(SectionVisibilityPreferenceKey.self) { frames in
                    updateCurrentSection(from: frames)
                }
                .onChange(of: library.activeScrollAnchor) { _, newAnchor in
                    if let newAnchor {
                        withAnimation(.spring()) {
                            proxy.scrollTo(newAnchor, anchor: .top)
                        }
                        library.activeScrollAnchor = nil
                    }
                }
                .onChange(of: rendered) { _, newRendered in
                    if !newRendered.isEmpty, let anchor = library.activeScrollAnchor {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring()) {
                                proxy.scrollTo(anchor, anchor: .top)
                            }
                            library.activeScrollAnchor = nil
                        }
                    }
                }
                .onChange(of: rendered, initial: true) { _, newRendered in
                    guard !newRendered.isEmpty else { return }
                    restoreBookmarkIfNeeded()
                    announceOrphanedHighlightsIfNeeded()
                }
            }

            if settings.showOutline && !settings.isFocusMode {
                Divider()
                OutlineView()
                    .frame(width: 220)
                    .transition(.move(edge: .trailing))
            }
        }
        .onAppear {
            ReaderShortcutHub.shared.activate(
                token: shortcutToken,
                isHighlightMode: $isHighlightMode,
                onDropBookmark: { dropReadingBookmark() },
                onHighlightKey: { handleHighlightKey() },
                onHighlightMouseUp: { captureHighlightFromSelection(keepModeActive: true) }
            )
        }
        .onDisappear {
            ReaderShortcutHub.shared.deactivate(token: shortcutToken)
        }
        .animation(.snappy(duration: 0.2), value: settings.showOutline)
        .animation(.snappy(duration: 0.2), value: settings.isFocusMode)
        .environment(\.openURL, OpenURLAction { url in
            onOpenURL(url)
        })
        .focusedSceneValue(\.dropReadingBookmarkAction, { dropReadingBookmark() })
        .focusedSceneValue(\.highlightSelectionAction, { handleHighlightKey() })
        .contextMenu {
            Button("Highlight Selection") {
                captureHighlightFromSelection(keepModeActive: false)
            }

            Button("Drop Reading Bookmark") {
                dropReadingBookmark()
            }
        }
        .cribbleBackgroundExtension()
        .navigationTitle(document.title)
    }

    private func restoreBookmarkIfNeeded() {
        guard restoredDocumentURL != document.url else { return }
        guard let bookmark = readingAnnotations.bookmark(for: document.url) else { return }
        restoredDocumentURL = document.url
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            resumeBookmark(bookmark)
        }
    }

    /// Resume from a bookmark with a graceful fallback chain that copes with
    /// the file having changed since the bookmark was dropped:
    ///   1. Exact section anchor still present  → scroll there.
    ///   2. Bookmarked heading title fuzzy-matches a current heading
    ///      (substring in either direction, case-insensitive) → scroll to
    ///      the closest match.
    ///   3. No heading match but a recorded scroll offset → scroll by offset
    ///      with a "file may have changed" hint.
    ///   4. Nothing usable → restore to top and tell the user.
    private func resumeBookmark(_ bookmark: ReadingBookmark) {
        let sections = ReadingSection.sections(from: rendered)

        if let title = bookmark.sectionTitle, !title.isEmpty {
            let anchor = title.textualSlug()

            if sections.contains(where: { $0.anchor == anchor }) {
                library.activeScrollAnchor = anchor
                library.statusMessage = "Resumed at \(title)"
                return
            }

            if let nearest = Self.nearestHeading(to: title, in: sections) {
                library.activeScrollAnchor = nearest.anchor
                let label = nearest.title ?? nearest.anchor
                library.statusMessage = "Bookmarked section \"\(title)\" not found — resumed near \(label)"
                return
            }
        }

        if bookmark.scrollOffsetY > 0 {
            restoreScrollOffsetY = bookmark.scrollOffsetY
            library.statusMessage = "Bookmarked section gone — restored to approximate scroll position"
            return
        }

        library.activeScrollAnchor = sections.first?.anchor
        library.statusMessage = "Bookmark target couldn't be located — restored to top"
    }

    private static func nearestHeading(to title: String, in sections: [ReadingSection]) -> ReadingSection? {
        let target = title.normalizedReadingText
        guard !target.isEmpty else { return nil }

        let withTitles = sections.compactMap { section -> (section: ReadingSection, title: String)? in
            guard let raw = section.title?.normalizedReadingText, !raw.isEmpty else { return nil }
            return (section, raw)
        }

        // Substring in either direction handles common edits: "Setup" still
        // matches a renamed "Project Setup", and an old "Project Setup" still
        // matches a renamed "Setup". Falls through (returns nil) only when
        // the bookmarked title shares no token with any current heading.
        return withTitles.first(where: { $0.title.contains(target) || target.contains($0.title) })?.section
    }

    /// Surface a one-shot status message when some of the document's stored
    /// highlights can't be located in the current rendered text — happens
    /// when the user has edited the file in their external editor since the
    /// highlights were made. The highlight records stay in the store so
    /// they re-anchor automatically if the original text comes back.
    private func announceOrphanedHighlightsIfNeeded() {
        let all = readingAnnotations.highlights(for: document.url)
        guard !all.isEmpty, !rendered.isEmpty else { return }

        let body = rendered.normalizedReadingText
        let orphaned = all.filter { !body.contains($0.quote.normalizedReadingText) }
        guard !orphaned.isEmpty else { return }

        let noun = orphaned.count == 1 ? "highlight" : "highlights"
        library.statusMessage = "\(orphaned.count) \(noun) couldn't be located in the current file — likely edited since"
    }

    private func updateCurrentSection(from frames: [ReadingSectionFrame]) {
        let candidates = frames.sorted { abs($0.minY) < abs($1.minY) }
        currentSectionTitle = candidates.first?.title
    }

    private func dropReadingBookmark() {
        // Immediate user-visible confirmation — proves the action fired even
        // if downstream rendering (the bookmark strip) is somehow not picking
        // up the @Published change.
        library.statusMessage = "Dropping bookmark…"
        readingAnnotations.dropBookmark(
            for: document.url,
            offsetY: scrollState.offsetY,
            sectionTitle: currentSectionTitle
        )
        library.statusMessage = "Dropped bookmark\(currentSectionTitle.map { " at \($0)" } ?? "")"
    }

    private func handleHighlightKey() {
        let wasHighlighting = isHighlightMode
        if wasHighlighting {
            isHighlightMode = false
            library.statusMessage = "Highlight mode off"
        } else {
            isHighlightMode = true
            lastHighlightedQuote = nil
            library.statusMessage = "Highlight mode on - drag over text to mark passages"
        }

        captureHighlightFromSelection(keepModeActive: false) { captured in
            if captured {
                isHighlightMode = false
            }
        }
    }

    private func captureHighlightFromSelection(
        keepModeActive: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        Self.captureSelectedText { selectedText in
            guard let quote = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !quote.isEmpty
            else {
                completion?(false)
                return
            }

            guard quote != lastHighlightedQuote else {
                completion?(false)
                return
            }

            readingAnnotations.addHighlight(for: document.url, quote: quote, note: "")
            lastHighlightedQuote = quote
            library.statusMessage = keepModeActive
                ? "Highlighted selection - highlight mode still on"
                : "Highlighted selection"
            completion?(true)
        }
    }

    /// Capture the currently selected text by piggy-backing on the standard
    /// AppKit `copy:` action, restoring the user's clipboard afterwards.
    ///
    /// The copy result is read on the next run-loop turn instead of
    /// synchronously waiting inside the menu/keyboard action. That keeps
    /// highlight capture from parking the UI in an intermediate state.
    private static func captureSelectedText(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let previousItems = PasteboardSnapshot(items: pasteboard.pasteboardItems ?? [])
        let previousChangeCount = pasteboard.changeCount

        _ = NSApp.sendAction(NSSelectorFromString("copy:"), to: nil, from: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let copied = pasteboard.changeCount != previousChangeCount
                ? pasteboard.string(forType: .string)
                : nil
            pasteboard.clearContents()
            previousItems.restore(to: pasteboard)
            completion(copied)
        }
    }

    private struct PasteboardSnapshot {
        private let items: [[NSPasteboard.PasteboardType: Data]]

        init(items pasteboardItems: [NSPasteboardItem]) {
            items = pasteboardItems.map { item in
                Dictionary(
                    uniqueKeysWithValues: item.types.compactMap { type in
                        guard let data = item.data(forType: type) else { return nil }
                        return (type, data)
                    }
                )
            }
            .filter { !$0.isEmpty }
        }

        func restore(to pasteboard: NSPasteboard) {
            guard !items.isEmpty else { return }

            let restoredItems = items.map { storedTypes in
                let item = NSPasteboardItem()
                for (type, data) in storedTypes {
                    item.setData(data, forType: type)
                }
                return item
            }
            pasteboard.writeObjects(restoredItems)
        }
    }
}

@MainActor
final class ReaderShortcutHub {
    static let shared = ReaderShortcutHub()

    private var activeToken: UUID?
    private var isHighlightMode: Binding<Bool>?
    private var onDropBookmark: (() -> Void)?
    private var onHighlightKey: (() -> Void)?
    private var onHighlightMouseUp: (() -> Void)?
    nonisolated(unsafe) private var monitor: Any?

    private init() {}

    func activate(
        token: UUID,
        isHighlightMode: Binding<Bool>,
        onDropBookmark: @escaping () -> Void,
        onHighlightKey: @escaping () -> Void,
        onHighlightMouseUp: @escaping () -> Void
    ) {
        activeToken = token
        self.isHighlightMode = isHighlightMode
        self.onDropBookmark = onDropBookmark
        self.onHighlightKey = onHighlightKey
        self.onHighlightMouseUp = onHighlightMouseUp
        installMonitorIfNeeded()
    }

    func deactivate(token: UUID) {
        guard activeToken == token else { return }
        activeToken = nil
        isHighlightMode = nil
        onDropBookmark = nil
        onHighlightKey = nil
        onHighlightMouseUp = nil
    }

    func performDropBookmark() {
        onDropBookmark?()
    }

    func performHighlightKey() {
        onHighlightKey?()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard activeToken != nil, NSApp.keyWindow != nil else { return event }

        switch event.type {
        case .keyDown:
            return handleKeyDown(event)
        case .leftMouseUp:
            if isHighlightMode?.wrappedValue == true {
                DispatchQueue.main.async { [weak self] in
                    self?.onHighlightMouseUp?()
                }
            }
            return event
        default:
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isEditable {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .shift])
        guard flags.isEmpty else { return event }

        if event.keyCode == 53 {
            if isHighlightMode?.wrappedValue == true {
                isHighlightMode?.wrappedValue = false
                return nil
            }
            return event
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return event
        }

        switch key {
        case "b", "d":
            performDropBookmark()
            return nil
        case "h":
            performHighlightKey()
            return nil
        default:
            return event
        }
    }
}

private struct ReadingBookmarkStrip: View {
    let bookmark: ReadingBookmark
    let documentURL: URL
    let onResume: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.yellow)

            Text(bookmark.sectionTitle.map { "Bookmark: \($0)" } ?? "Reading bookmark")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if fileWasEditedSinceBookmark {
                Text("• file edited since")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help("This file was modified after the bookmark was saved — the saved position may have shifted.")
            }

            Spacer(minLength: 8)

            Button("Resume", action: onResume)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 8))
    }

    private var fileWasEditedSinceBookmark: Bool {
        guard let values = try? documentURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let mtime = values.contentModificationDate
        else {
            return false
        }
        // 1-second slack absorbs filesystem timestamp granularity differences
        // (HFS+ stores seconds, APFS nanoseconds) so saving a bookmark and
        // then immediately re-opening doesn't false-positive.
        return mtime.timeIntervalSince(bookmark.updatedAt) > 1
    }
}

private struct ReaderMarkdownSection: View {
    let section: ReadingSection
    let baseURL: URL
    let fontScale: Double
    let highlights: [ReadingHighlight]

    var body: some View {
        let applicableHighlights = highlightsInSection
        StructuredText(
            section.markdown,
            parser: HighlightedMarkdownParser(
                baseURL: baseURL,
                highlights: applicableHighlights
            )
        )
        // Force re-parse when the highlight set changes. StructuredText
        // caches its rendered AttributedString keyed on `markup` alone, so
        // changing the parser (the only carrier of highlights) wouldn't
        // otherwise trigger a re-parse and the highlight would never appear.
        .id(highlightIdentity(for: applicableHighlights))
        .font(.system(size: 17 * fontScale))
        .textual.structuredTextStyle(.gitHub)
        .textual.inlineStyle(
            InlineStyle()
                .code(.font(.system(size: 14 * fontScale, design: .monospaced)))
                .strong(.fontWeight(.semibold))
        )
        .textual.codeBlockStyle(CribbleCodeBlockStyle(fontSize: 13 * fontScale))
        .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
        .textual.textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .help(applicableHighlights.map(\.note).filter { !$0.isEmpty }.joined(separator: "\n\n"))
    }

    private var highlightsInSection: [ReadingHighlight] {
        let normalizedSection = section.markdown.normalizedReadingText
        return highlights.filter { normalizedSection.contains($0.quote.normalizedReadingText) }
    }

    private func highlightIdentity(for highlights: [ReadingHighlight]) -> String {
        // Identity = (section + sorted highlight ids). Stable across re-renders
        // when nothing changed, unique when highlights are added/removed.
        let ids = highlights.map(\.id.uuidString).sorted().joined(separator: "|")
        return "\(section.id)#\(ids)"
    }
}

private struct HighlightedMarkdownParser: MarkupParser {
    let baseURL: URL
    let highlights: [ReadingHighlight]

    func attributedString(for input: String) throws -> AttributedString {
        var attributed = try AttributedStringMarkdownParser.markdown(
            baseURL: baseURL,
            syntaxExtensions: [.math]
        )
        .attributedString(for: input)

        for highlight in highlights {
            applyHighlight(highlight, to: &attributed)
        }

        return attributed
    }

    private func applyHighlight(_ highlight: ReadingHighlight, to attributed: inout AttributedString) {
        let quote = highlight.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { return }
        guard let stringRange = String(attributed.characters).range(of: quote, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return
        }
        guard let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let upper = AttributedString.Index(stringRange.upperBound, within: attributed)
        else {
            return
        }

        attributed[lower..<upper].backgroundColor = NSColor.systemYellow.withAlphaComponent(0.35)
    }
}

private struct ReadingSection: Identifiable, Hashable {
    let id: String
    let anchor: String
    let title: String?
    let markdown: String

    static func sections(from markdown: String) -> [ReadingSection] {
        var sections: [ReadingSection] = []
        var currentLines: [String] = []
        var currentTitle: String?
        var currentAnchor = "top"
        var sectionIndex = 0

        func flush() {
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            guard !body.isEmpty else { return }
            sections.append(
                ReadingSection(
                    id: "\(sectionIndex)-\(currentAnchor)",
                    anchor: currentAnchor,
                    title: currentTitle,
                    markdown: body
                )
            )
            sectionIndex += 1
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let heading = parseHeading(line), !currentLines.isEmpty {
                flush()
                currentLines = [line]
                currentTitle = heading
                currentAnchor = heading.textualSlug()
            } else {
                if let heading = parseHeading(line), currentLines.isEmpty {
                    currentTitle = heading
                    currentAnchor = heading.textualSlug()
                }
                currentLines.append(line)
            }
        }

        flush()
        return sections
    }

    private static func parseHeading(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount) else { return nil }
        let rest = line.dropFirst(markerCount)
        guard rest.first == " " else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }
}

private struct ReadingSectionFrame: Equatable {
    let title: String?
    let minY: CGFloat
}

private struct SectionVisibilityReporter: View {
    let section: ReadingSection

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: SectionVisibilityPreferenceKey.self,
                value: [
                    ReadingSectionFrame(
                        title: section.title,
                        minY: proxy.frame(in: .named("readerScroll")).minY
                    )
                ]
            )
        }
    }
}

private struct SectionVisibilityPreferenceKey: PreferenceKey {
    static let defaultValue: [ReadingSectionFrame] = []

    static func reduce(value: inout [ReadingSectionFrame], nextValue: () -> [ReadingSectionFrame]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ScrollPositionBridge: NSViewRepresentable {
    let scrollState: ReaderScrollState
    @Binding var targetOffsetY: Double?

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollState: scrollState)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.enclosingScrollView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.enclosingScrollView)
            if let targetOffsetY {
                context.coordinator.scroll(to: targetOffsetY)
                self.targetOffsetY = nil
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        // Reference, not Binding — boundsDidChange fires on every scroll
        // tick. Writing to a SwiftUI @State/Binding here invalidated the
        // entire ReaderDocumentView body once per pixel of scroll.
        private let scrollState: ReaderScrollState
        private weak var scrollView: NSScrollView?

        init(scrollState: ReaderScrollState) {
            self.scrollState = scrollState
        }

        func attach(to scrollView: NSScrollView?) {
            guard self.scrollView !== scrollView, let scrollView else { return }
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            scrollState.offsetY = scrollView.contentView.bounds.origin.y
        }

        func scroll(to offsetY: Double) {
            guard let scrollView else { return }
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maxY = max(0, documentHeight - scrollView.contentView.bounds.height)
            let y = min(max(0, offsetY), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            scrollState.offsetY = y
        }

        @objc nonisolated private func boundsDidChange(_ notification: Notification) {
            // NSScrollView always posts bounds-changed on the main thread,
            // so MainActor.assumeIsolated is sound. We deliberately avoid
            // pulling `notification.object` across the actor boundary (Swift
            // 6 sendability) by reading our own cached scrollView reference.
            MainActor.assumeIsolated {
                guard let scrollView else { return }
                scrollState.offsetY = scrollView.contentView.bounds.origin.y
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private extension String {
    var normalizedReadingText: String {
        lowercased()
            .map { character in
                if character.isLetter || character.isNumber || character.isWhitespace {
                    return character
                }
                return " "
            }
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }
}

private struct EmptyReadmePanel: View {
    let folderName: String
    let isRunningAI: Bool
    let onFillReadme: (AIProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("This README is empty")
                        .font(.system(size: 17))
                        .fontWeight(.semibold)

                    Text("Generate a folder overview, contents list, and useful links from the Markdown files in \(folderName).")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ForEach(AIProvider.allCases) { provider in
                    Button {
                        onFillReadme(provider)
                    } label: {
                        Label("Fill + Link with \(provider.rawValue)", systemImage: provider == .codex ? "terminal" : "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isRunningAI)
                    .help("Use \(provider.rawValue) \(provider.lowestModelName) to draft this README, then review the patch before applying")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LinkedFilesCardPanel: View {
    let links: [LinkedFileSummary]
    let onSelect: (LinkedFileSummary) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "text.book.closed")
                        .foregroundStyle(.secondary)

                    Text("Linked files")
                        .font(.system(size: 14))
                        .fontWeight(.semibold)

                    Text("\(links.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .cribbleGlass(in: Capsule())

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse linked files" : "Expand linked files")

            if isExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(links) { link in
                        Button {
                            onSelect(link)
                        } label: {
                            LinkedFileCard(link: link)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .pointingHandOnHover()
                        .notePreviewPopover(url: link.url)
                        .help("Open \(link.title)")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct LinkedFileCard: View {
    let link: LinkedFileSummary

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.text")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.system(size: 13))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(link.subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text("MD")
                .font(.system(size: 10, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.pink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.045))
        }
    }
}

private struct CribbleCodeBlockStyle: StructuredText.CodeBlockStyle {
    let fontSize: Double

    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .font(.system(size: fontSize, design: .monospaced))
                .textual.lineSpacing(.fontScaled(0.25))
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 8))
        .textual.blockSpacing(.init(top: 8, bottom: 18))
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ContentUnavailableView {
            Label("Open a Markdown Folder", systemImage: "text.book.closed")
        } description: {
            Text("Cribble reads folders in place and keeps Markdown editing in your editor.")
        } actions: {
            Button("Open Folder") {
                library.chooseFolder(sortMode: settings.fileSortMode)
            }
            .controlSize(.large)
            .cribbleGlassButton(prominent: true)
            .help("Open a Markdown folder and keep it in the sidebar")
        }
    }
}
