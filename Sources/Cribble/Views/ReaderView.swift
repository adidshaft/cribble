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
    // Cached section partitioning + highlight assignments. Rebuilt only when
    // the document body or its highlight set changes, so scroll-triggered
    // re-renders no longer pay O(sections * highlights * text-length) for
    // normalization on every body invocation.
    @State private var sectionPlan: ReaderSectionPlan = .empty

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
                                ForEach(sectionPlan.sections) { section in
                                    ReaderMarkdownSection(
                                        section: section,
                                        baseURL: document.url.deletingLastPathComponent(),
                                        fontScale: fontScale,
                                        highlights: sectionPlan.highlightsByAnchor[section.id] ?? []
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
                    rebuildSectionPlan(rendered: newRendered)
                    guard !newRendered.isEmpty else { return }
                    restoreBookmarkIfNeeded()
                    announceOrphanedHighlightsIfNeeded()
                }
                .onReceive(readingAnnotations.$highlights) { newHighlights in
                    let documentHighlights = newHighlights[document.url.standardizedFileURL.path] ?? []
                    rebuildSectionPlan(rendered: rendered, highlights: documentHighlights)
                }
            }

            if settings.showOutline && !settings.isFocusMode {
                Divider()
                OutlineView()
                    .frame(width: 220)
                    .transition(.move(edge: .trailing))
            }
        }
        .highlightModeCursor(isHighlightMode)
        // Textual installs its own I-beam via onContinuousHover on every
        // sample, which would stomp the cursor pushed by the modifier above
        // the instant the mouse enters text. Pushing the cursor through
        // Textual's env override means Textual itself sets our cursor over
        // text, so highlight mode actually shows a visual signal.
        .environment(\.textInteractionCursorOverride, isHighlightMode ? NSCursor.cribbleHighlightLine : nil)
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
        // Textual's NSTextInteractionView shows its own NSMenu on right-click
        // over text, which shadowed any SwiftUI `.contextMenu` we attached
        // here. Inject our custom items through Textual's env hook so they
        // appear alongside Share / Copy.
        .environment(\.textInteractionAdditionalMenuItems) { selected, anchor in
            buildHighlightContextMenuItems(forSelection: selected, anchor: anchor)
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

    private func buildHighlightContextMenuItems(
        forSelection selected: String,
        anchor: TextInteractionContextAnchor
    ) -> [TextInteractionMenuItem] {
        // Sanitize once so we work with what `applyHighlight` ultimately
        // sees (no leading bullet, etc.).
        let cleaned = Self.sanitizeHighlightQuote(selected)
        guard !cleaned.isEmpty else { return [] }

        let existing = readingAnnotations.highlight(for: document.url, matching: cleaned)
        var items: [TextInteractionMenuItem]
        if existing == nil {
            items = [
                TextInteractionMenuItem(title: "Highlight Selection") { [self] in
                    addHighlightForCapturedSelection(cleaned)
                },
                TextInteractionMenuItem(title: "Highlight with Note") { [self] in
                    presentNoteEditor(forQuote: cleaned, anchor: anchor)
                }
            ]
        } else {
            items = [
                TextInteractionMenuItem(title: existing?.note.isEmpty == false ? "Edit Highlight Note" : "Add Highlight Note") { [self] in
                    presentNoteEditor(forQuote: cleaned, anchor: anchor)
                },
                TextInteractionMenuItem(title: "Remove Highlight") { [self] in
                    removeHighlight(matching: cleaned)
                }
            ]
        }
        items.append(
            TextInteractionMenuItem(title: "Drop Reading Bookmark") { [self] in
                dropReadingBookmark()
            }
        )
        return items
    }

    private func addHighlightForCapturedSelection(_ quote: String) {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        readingAnnotations.addHighlight(for: document.url, quote: trimmed, note: "")
        lastHighlightedQuote = trimmed
        library.statusMessage = "Highlighted selection"
    }

    private func presentNoteEditor(forQuote quote: String, anchor: TextInteractionContextAnchor) {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = readingAnnotations.highlight(for: document.url, matching: trimmed)
        let initialNote = existing?.note ?? ""

        HighlightNotePopover.present(
            quote: existing?.quote ?? trimmed,
            initialNote: initialNote,
            anchorView: anchor.view,
            anchorRect: anchor.selectionRect
        ) { [self] result in
            switch result {
            case .cancelled:
                return
            case .saved(let note):
                if readingAnnotations.updateHighlightNote(
                    for: document.url,
                    matching: trimmed,
                    note: note
                ) {
                    library.statusMessage = note.isEmpty ? "Removed highlight note" : "Updated highlight note"
                } else {
                    readingAnnotations.addHighlight(for: document.url, quote: trimmed, note: note)
                    lastHighlightedQuote = trimmed
                    library.statusMessage = note.isEmpty
                        ? "Highlighted selection"
                        : "Highlighted selection with note"
                }
            }
        }
    }

    private func removeHighlight(matching quote: String) {
        guard readingAnnotations.removeHighlight(for: document.url, matching: quote) else { return }
        library.statusMessage = "Removed highlight"
    }

    private func rebuildSectionPlan(rendered: String, highlights: [ReadingHighlight]? = nil) {
        let documentHighlights = highlights ?? readingAnnotations.highlights(for: document.url)
        sectionPlan = ReaderSectionPlan.build(rendered: rendered, highlights: documentHighlights)
    }

    private func updateCurrentSection(from frames: [ReadingSectionFrame]) {
        // Preference reduction already collapsed to the single nearest frame.
        let nextSectionTitle = frames.first?.title
        guard currentSectionTitle != nextSectionTitle else { return }
        currentSectionTitle = nextSectionTitle
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
            guard let raw = selectedText,
                  case let quote = Self.sanitizeHighlightQuote(raw),
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

    /// Trim the noise Textual's plain-text copy adds — list bullets (`• `,
    /// `- `, `* `, `+ `) and ordered markers (`1. `, `1) `) — that exist only
    /// in the rendered clipboard string and NOT in the underlying
    /// AttributedString the highlight parser later searches. Without this
    /// strip, a triple-click on a bulleted line yields a stored quote like
    /// "• View attendance history." that `applyHighlight`'s
    /// `String(attributed.characters).range(of:)` can never match, so the
    /// yellow background never appears.
    fileprivate nonisolated static func sanitizeHighlightQuote(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Repeated strip handles nested lists ("• 1. item").
        while let stripped = stripLeadingListMarker(from: text), stripped != text {
            text = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    fileprivate nonisolated static func stripLeadingListMarker(from text: String) -> String? {
        guard let match = listMarkerRegex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ),
        match.range.location == 0,
        let upper = Range(match.range, in: text)?.upperBound
        else {
            return nil
        }
        return String(text[upper...])
    }

    fileprivate nonisolated static let listMarkerRegex: NSRegularExpression = {
        // Leading whitespace, then either a bullet glyph (Textual emits U+2022)
        // / dash / asterisk / plus, or "<digits>." / "<digits>)", followed by
        // at least one space. Matches what Formatter+PlainText emits in the
        // copy-buffer text Cribble reads from when capturing highlights.
        let pattern = #"^\s*(?:[•\-*+]|\d+[.)])\s+"#
        return try! NSRegularExpression(pattern: pattern)
    }()

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
        // Parent already partitioned highlights to the sections that contain
        // them (see ReaderSectionPlan). No per-render filtering needed here.
        let applicableHighlights = highlights
        VStack(alignment: .leading, spacing: 12) {
            ForEach(RichMarkdownBlock.blocks(from: section.markdown)) { block in
                switch block {
                case .markdown(_, let markdown):
                    StructuredText(
                        markdown,
                        parser: HighlightedMarkdownParser(
                            baseURL: baseURL,
                            highlights: applicableHighlights
                        )
                    )
                    .font(.system(size: 17 * fontScale))
                    .textual.structuredTextStyle(.gitHub)
                    .textual.inlineStyle(
                        InlineStyle()
                            .code(.font(.system(size: 14 * fontScale, design: .monospaced)))
                            .strong(.fontWeight(.semibold))
                    )
                    .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
                    .textual.textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                case .fencedCode(_, let language, let code):
                    RichCodeBlockView(language: language, code: code, fontScale: fontScale)
                }
            }
        }
        // Force re-parse when the highlight set changes. StructuredText
        // caches its rendered AttributedString keyed on `markup` alone, so
        // changing the parser (the only carrier of highlights) wouldn't
        // otherwise trigger a re-parse and the highlight would never appear.
        .id(highlightIdentity(for: applicableHighlights))
    }

    private func highlightIdentity(for highlights: [ReadingHighlight]) -> String {
        // Identity = (section + sorted highlight ids). Stable across re-renders
        // when nothing changed, unique when highlights are added/removed.
        let ids = highlights.map(\.id.uuidString).sorted().joined(separator: "|")
        return "\(section.id)#\(ids)"
    }
}

private struct RichCodeBlockView: View {
    let language: String?
    let code: String
    let fontScale: Double

    private var normalizedLanguage: String {
        language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var displayLanguage: String {
        guard !normalizedLanguage.isEmpty else { return "Code" }
        switch normalizedLanguage {
        case "mermaid":
            return "Mermaid"
        case "dot", "graphviz":
            return "Graphviz"
        case "vega":
            return "Vega"
        case "vega-lite", "vegalite":
            return "Vega-Lite"
        default:
            return normalizedLanguage.uppercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(displayLanguage)
                    .font(.system(size: 12 * fontScale, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy block")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.primary.opacity(0.035))

            if normalizedLanguage == "mermaid" {
                MermaidDiagramView(source: code, fontScale: fontScale)
                    .padding(12)
            } else if ["dot", "graphviz", "vega", "vega-lite", "vegalite", "chart", "graph"].contains(normalizedLanguage) {
                DiagramSourceView(source: code, fontScale: fontScale, iconName: "chart.xyaxis.line")
                    .padding(12)
            } else {
                CodeSourceView(source: code, fontScale: fontScale)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch normalizedLanguage {
        case "mermaid", "dot", "graphviz":
            return "point.3.connected.trianglepath.dotted"
        case "vega", "vega-lite", "vegalite", "chart", "graph":
            return "chart.bar.xaxis"
        default:
            return "curlybraces"
        }
    }
}

private struct MermaidDiagramView: View {
    let source: String
    let fontScale: Double

    var body: some View {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first?.lowercased() ?? ""

        if firstLine.hasPrefix("sequenceDiagram".lowercased()) {
            MermaidSequenceView(messages: MermaidSequenceMessage.messages(from: source), fontScale: fontScale, source: source)
        } else if firstLine.hasPrefix("pie") {
            MermaidPieView(slices: MermaidPieSlice.slices(from: source), fontScale: fontScale)
        } else {
            MermaidFlowchartView(edges: MermaidFlowchartEdge.edges(from: source), fontScale: fontScale, source: source)
        }
    }
}

private struct MermaidFlowchartView: View {
    let edges: [MermaidFlowchartEdge]
    let fontScale: Double
    let source: String

    var body: some View {
        if edges.isEmpty {
            DiagramSourceView(source: source, fontScale: fontScale, iconName: "point.3.connected.trianglepath.dotted")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(edges.prefix(10)) { edge in
                    HStack(spacing: 8) {
                        MermaidNodeChip(label: edge.from, fontScale: fontScale)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        MermaidNodeChip(label: edge.to, fontScale: fontScale)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if edges.count > 10 {
                    Text("+ \(edges.count - 10) more connections")
                        .font(.system(size: 12 * fontScale))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MermaidNodeChip: View {
    let label: String
    let fontScale: Double

    var body: some View {
        Text(label)
            .font(.system(size: 13 * fontScale, weight: .semibold, design: .rounded))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(.blue.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct MermaidSequenceView: View {
    let messages: [MermaidSequenceMessage]
    let fontScale: Double
    let source: String

    var body: some View {
        if messages.isEmpty {
            DiagramSourceView(source: source, fontScale: fontScale, iconName: "arrow.left.arrow.right")
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(messages.prefix(10)) { message in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(message.from)
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(message.to)
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 12 * fontScale, design: .rounded))

                        Text(message.label)
                            .font(.system(size: 13 * fontScale))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }
}

private struct MermaidPieView: View {
    let slices: [MermaidPieSlice]
    let fontScale: Double

    var body: some View {
        if slices.isEmpty {
            DiagramSourceView(source: "", fontScale: fontScale, iconName: "chart.pie")
        } else {
            let maxValue = slices.map(\.value).max() ?? 1
            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices.prefix(10)) { slice in
                    HStack(spacing: 10) {
                        Text(slice.label)
                            .font(.system(size: 13 * fontScale))
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.green.opacity(0.28))
                                .frame(width: max(8, proxy.size.width * slice.value / maxValue))
                        }
                        .frame(height: 8)

                        Text(slice.value.formatted())
                            .font(.system(size: 11 * fontScale, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct DiagramSourceView: View {
    let source: String
    let fontScale: Double
    let iconName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                Text("Diagram preview")
                    .font(.system(size: 13 * fontScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if !source.isEmpty {
                CodeSourceView(source: source, fontScale: fontScale)
            }
        }
    }
}

private struct CodeSourceView: View {
    let source: String
    let fontScale: Double

    var body: some View {
        ScrollView(.horizontal) {
            Text(source.isEmpty ? " " : source)
                .font(.system(size: 13 * fontScale, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(2)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct MermaidFlowchartEdge: Identifiable, Equatable {
    let id = UUID()
    let from: String
    let to: String

    static func edges(from source: String) -> [MermaidFlowchartEdge] {
        source
            .components(separatedBy: .newlines)
            .compactMap { line -> MermaidFlowchartEdge? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      !trimmed.lowercased().hasPrefix("flowchart"),
                      !trimmed.lowercased().hasPrefix("graph")
                else { return nil }

                let sanitized = trimmed
                    .replacingOccurrences(of: #"\|[^|]*\|"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

                let separators = ["-->", "---", "==>", "-.->", "~~~"]
                guard let separator = separators.first(where: { sanitized.contains($0) }) else { return nil }
                let parts = sanitized.components(separatedBy: separator)
                guard parts.count >= 2 else { return nil }

                let from = normalizeNode(parts[0])
                let to = normalizeNode(parts[1])
                guard !from.isEmpty, !to.isEmpty else { return nil }
                return MermaidFlowchartEdge(from: from, to: to)
            }
    }

    private static func normalizeNode(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"^[A-Za-z0-9_]+\s*[\[\(\{<"](.+)[\]\)\}>"]$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[;\[\]\(\)\{\}<"]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MermaidSequenceMessage: Identifiable, Equatable {
    let id = UUID()
    let from: String
    let to: String
    let label: String

    static func messages(from source: String) -> [MermaidSequenceMessage] {
        source
            .components(separatedBy: .newlines)
            .compactMap { line -> MermaidSequenceMessage? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let arrows = ["-->>", "->>", "-->", "->", "-x", "--x"]
                guard let arrow = arrows.first(where: { trimmed.contains($0) }),
                      let arrowRange = trimmed.range(of: arrow),
                      let colonIndex = trimmed[arrowRange.upperBound...].firstIndex(of: ":")
                else { return nil }

                let from = String(trimmed[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let to = String(trimmed[arrowRange.upperBound..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let label = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !from.isEmpty, !to.isEmpty, !label.isEmpty else { return nil }
                return MermaidSequenceMessage(from: from, to: to, label: label)
            }
    }
}

private struct MermaidPieSlice: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: Double

    static func slices(from source: String) -> [MermaidPieSlice] {
        source
            .components(separatedBy: .newlines)
            .compactMap { line -> MermaidPieSlice? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.contains(":"),
                      !trimmed.lowercased().hasPrefix("pie"),
                      !trimmed.lowercased().hasPrefix("title")
                else { return nil }

                let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      let value = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                else { return nil }

                let label = parts[0]
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                guard !label.isEmpty else { return nil }
                return MermaidPieSlice(label: label, value: value)
            }
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
        let trimmed = highlight.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let haystack = String(attributed.characters)
        // Try the stored quote, then a marker-stripped variant. The second
        // path keeps legacy highlights captured before the capture-time
        // sanitizer existed (their quotes still carry "• " from Textual's
        // plain-text copy) actually rendering.
        let candidates: [String] = {
            let stripped = ReaderDocumentView.sanitizeHighlightQuote(trimmed)
            return stripped == trimmed ? [trimmed] : [trimmed, stripped]
        }()

        for candidate in candidates {
            guard !candidate.isEmpty else { continue }
            guard let stringRange = haystack.range(
                of: candidate,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) else { continue }
            guard let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attributed)
            else { continue }

            attributed[lower..<upper].backgroundColor = NSColor.systemYellow.withAlphaComponent(0.35)
            return
        }
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

private struct ReaderSectionPlan {
    let sections: [ReadingSection]
    let highlightsByAnchor: [String: [ReadingHighlight]]

    static let empty = ReaderSectionPlan(sections: [], highlightsByAnchor: [:])

    static func build(rendered: String, highlights: [ReadingHighlight]) -> ReaderSectionPlan {
        let sections = ReadingSection.sections(from: rendered)
        guard !sections.isEmpty, !highlights.isEmpty else {
            return ReaderSectionPlan(sections: sections, highlightsByAnchor: [:])
        }

        // Normalize each highlight quote exactly once. Strip list markers
        // first so a legacy "• View attendance history." quote still
        // partitions into the right section.
        let normalizedHighlights: [(ReadingHighlight, String)] = highlights.compactMap { highlight in
            let cleaned = ReaderDocumentView.sanitizeHighlightQuote(highlight.quote)
            let normalized = cleaned.normalizedReadingText
            return normalized.isEmpty ? nil : (highlight, normalized)
        }
        guard !normalizedHighlights.isEmpty else {
            return ReaderSectionPlan(sections: sections, highlightsByAnchor: [:])
        }

        var assignments: [String: [ReadingHighlight]] = [:]
        for section in sections {
            let normalizedSection = section.markdown.normalizedReadingText
            var matches: [ReadingHighlight] = []
            for (highlight, normalizedQuote) in normalizedHighlights
            where normalizedSection.contains(normalizedQuote) {
                matches.append(highlight)
            }
            if !matches.isEmpty {
                assignments[section.id] = matches
            }
        }
        return ReaderSectionPlan(sections: sections, highlightsByAnchor: assignments)
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
    // Carry only the single section whose minY is closest to the viewport
    // origin. Reducing at collection time keeps the per-scroll-tick payload
    // O(1) instead of O(sections) and removes the sort that ran in
    // updateCurrentSection on every callback.
    static let defaultValue: [ReadingSectionFrame] = []

    static func reduce(value: inout [ReadingSectionFrame], nextValue: () -> [ReadingSectionFrame]) {
        for frame in nextValue() {
            if let current = value.first {
                if abs(frame.minY) < abs(current.minY) {
                    value = [frame]
                }
            } else {
                value = [frame]
            }
        }
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
        // Skip the async hop when nothing has changed: attach() is idempotent
        // and re-firing it on every SwiftUI invalidation kept enqueuing
        // identical work that the coordinator just no-ops. Only re-dispatch
        // when there's a scroll target to consume.
        guard let targetOffsetY else {
            context.coordinator.attach(to: nsView.enclosingScrollView)
            return
        }
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.enclosingScrollView)
            context.coordinator.scroll(to: targetOffsetY)
            self.targetOffsetY = nil
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
