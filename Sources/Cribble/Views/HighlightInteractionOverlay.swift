import AppKit
import SwiftUI
import Textual

private struct HighlightHoverRegion: Equatable {
    let highlightID: UUID
    let rect: CGRect
}

struct HighlightInteractionOverlay: ViewModifier {
    let highlights: [ResolvedHighlight]
    let onUpdateNote: (UUID, String) -> Void
    @State private var model: TextSelectionModel?
    @State private var regions: [TextInteractionCursorRegion] = []
    @State private var hoverRegions: [HighlightHoverRegion] = []
    @State private var hoverNoteRegions: [TextInteractionHoverNoteRegion] = []
    @State private var hoveredHighlightID: UUID?
    @State private var pendingHoverClear: DispatchWorkItem?
    @State private var editingHighlightID: UUID?
    @State private var editingNote: String = ""

    func body(content: Content) -> some View {
        content
            .environment(\.textInteractionCursorRegions, regions)
            .environment(\.textInteractionHoverHandler) { location in
                updateHover(from: location)
            }
            .environment(\.textInteractionHoverNoteRegions, hoverNoteRegions)
            .onPreferenceChange(TextSelectionModelPreferenceKey.self) { newModel in
                self.model = newModel
            }
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                GeometryReader { geometry in
                    let rectsByHighlight = computeRects(
                        layouts: layouts,
                        geometry: geometry
                    )
                    let localRectsByHighlight = computeLocalRects()
                    
                    let allRects = localRectsByHighlight.values.flatMap { $0 }
                    let newRegions = allRects.map { TextInteractionCursorRegion(rect: $0, cursor: .cribbleHighlightHand) }
                    let newHoverRegions = highlights.flatMap { highlight in
                        localRectsByHighlight[highlight.id, default: []].map {
                            HighlightHoverRegion(highlightID: highlight.id, rect: $0)
                        }
                    }
                    let newHoverNoteRegions = highlights.flatMap { highlight in
                        guard !highlight.note.isEmpty else { return [TextInteractionHoverNoteRegion]() }
                        return localRectsByHighlight[highlight.id, default: []].map {
                            TextInteractionHoverNoteRegion(rect: $0, note: highlight.note)
                        }
                    }
                    let hoverTrackingSurface = HighlightHoverTrackingSurface(
                        rectsByHighlight: rectsByHighlight,
                        highlights: highlights,
                        onBeginEditing: { highlightID in
                            guard let highlight = highlights.first(where: { $0.id == highlightID }) else { return }
                            beginInlineEditing(highlight)
                        },
                        onDeleteNote: { highlightID in
                            onUpdateNote(highlightID, "")
                        }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    ZStack(alignment: .topLeading) {
                        if editingHighlightID != nil {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    saveInlineEditor()
                                }
                        }

                        // Invisible active state to update state safely in the rendering cycle
                        Color.clear
                            .onChange(of: hoverStateSignature(regions: newRegions, notes: newHoverNoteRegions), initial: true) { _, _ in
                                self.regions = newRegions
                                self.hoverRegions = newHoverRegions
                                self.hoverNoteRegions = newHoverNoteRegions
                            }

                        if editingHighlightID == nil {
                            hoverTrackingSurface
                        }

                        ForEach(highlights, id: \.id) { h in
                            ForEach(Array(rectsByHighlight[h.id, default: []].enumerated()), id: \.offset) { _, rect in
                                Rectangle()
                                    // These tiny overlays own hover-card
                                    // visibility. The AppKit tracking view is
                                    // retained for cursor/right-click fallback,
                                    // but relying on NSTrackingArea alone proved
                                    // too lifecycle-sensitive inside Textual.
                                    .fill(Color.white.opacity(0.001))
                                    .contentShape(Rectangle())
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .onHover { hovering in
                                        if hovering, !h.note.isEmpty {
                                            updateTrackedHover(h.id)
                                        } else if hoveredHighlightID == h.id {
                                            updateTrackedHover(nil)
                                        }
                                    }
                                    .onTapGesture(count: 2) {
                                        beginInlineEditing(h)
                                    }
                                    .contextMenu {
                                        Button(h.note.isEmpty ? "Add Highlight Note" : "Edit Highlight Note") {
                                            beginInlineEditing(h)
                                        }
                                        if !h.note.isEmpty {
                                            Button("Delete Highlight Note") {
                                                onUpdateNote(h.id, "")
                                            }
                                        }
                                    }
                                    .allowsHitTesting(editingHighlightID == nil)
                            }
                        }

                        if let h = activeHoverHighlight(
                            rectsByHighlight: rectsByHighlight
                        ), editingHighlightID == nil {
                            HighlightNoteHoverCard(note: h.note)
                                .position(
                                    x: cardPosition(for: rectsByHighlight[h.id, default: []], in: geometry.size).x,
                                    y: cardPosition(for: rectsByHighlight[h.id, default: []], in: geometry.size).y
                                )
                                .onTapGesture {
                                    beginInlineEditing(h)
                                }
                        }

                        if let h = activeEditingHighlight(
                            rectsByHighlight: rectsByHighlight
                        ) {
                            HighlightInlineNoteEditor(
                                note: $editingNote,
                                onSubmit: { saveInlineEditor() }
                            )
                            .position(
                                x: editorPosition(for: rectsByHighlight[h.id, default: []], in: geometry.size).x,
                                y: editorPosition(for: rectsByHighlight[h.id, default: []], in: geometry.size).y
                            )
                        }
                    }
                }
            }
    }

    private func computeRects(
        layouts: [Text.LayoutKey.AnchoredLayout],
        geometry: GeometryProxy
    ) -> [UUID: [CGRect]] {
        guard let model, model.hasText, !layouts.isEmpty else { return [:] }
        var result: [UUID: [CGRect]] = [:]
        let fullRange = Textual.TextRange(start: model.startPosition, end: model.endPosition)
        let blockText = model.text(in: fullRange)
        
        for h in highlights {
            guard let range = resolvedRange(for: h, blockText: blockText, model: model) else {
                continue
            }
            
            var rects: [CGRect] = []
            for anchoredLayout in layouts {
                let selectionRects = model.selectionRects(for: range, layout: anchoredLayout.layout)
                let layoutOrigin = geometry[anchoredLayout.origin]
                for selRect in selectionRects {
                    let absoluteRect = selRect.rect.offsetBy(dx: layoutOrigin.x, dy: layoutOrigin.y)
                    rects.append(absoluteRect)
                }
            }
            result[h.id] = rects
        }
        
        return result
    }

    private func computeLocalRects() -> [UUID: [CGRect]] {
        guard let model, model.hasText else { return [:] }
        let fullRange = Textual.TextRange(start: model.startPosition, end: model.endPosition)
        let blockText = model.text(in: fullRange)
        var result: [UUID: [CGRect]] = [:]

        for highlight in highlights {
            guard let range = resolvedRange(for: highlight, blockText: blockText, model: model) else {
                continue
            }
            result[highlight.id] = model.selectionRects(for: range).map(\.rect)
        }

        return result
    }

    private func resolvedRange(
        for highlight: ResolvedHighlight,
        blockText: String,
        model: TextSelectionModel
    ) -> Textual.TextRange? {
        switch highlight.strategy {
        case .offset(let start, let length):
            return resolvedTextRange(
                startOffset: start,
                length: length,
                blockText: blockText,
                model: model
            )

        case .textSearch(let quote):
            guard let stringRange = blockText.range(of: quote, options: [.caseInsensitive, .diacriticInsensitive]),
                  let lowerUTF16 = stringRange.lowerBound.samePosition(in: blockText.utf16),
                  let upperUTF16 = stringRange.upperBound.samePosition(in: blockText.utf16)
            else { return nil }

            let startOffset = blockText.utf16.distance(from: blockText.utf16.startIndex, to: lowerUTF16)
            let length = blockText.utf16.distance(from: lowerUTF16, to: upperUTF16)
            return resolvedTextRange(
                startOffset: startOffset,
                length: length,
                blockText: blockText,
                model: model
            )
        }
    }

    private func activeHoverHighlight(rectsByHighlight: [UUID: [CGRect]]) -> ResolvedHighlight? {
        guard let hoveredHighlightID,
              let highlight = highlights.first(where: { $0.id == hoveredHighlightID }),
              !highlight.note.isEmpty,
              rectsByHighlight[highlight.id]?.isEmpty == false
        else { return nil }
        return highlight
    }

    private func hoverStateSignature(
        regions: [TextInteractionCursorRegion],
        notes: [TextInteractionHoverNoteRegion]
    ) -> String {
        let rects = regions.map { "\($0.rect.origin.x),\($0.rect.origin.y),\($0.rect.size.width),\($0.rect.size.height)" }
        let noteBits = notes.map { "\($0.rect.origin.x),\($0.rect.origin.y):\($0.note.hashValue)" }
        return (rects + noteBits).joined(separator: "|")
    }

    private func updateTrackedHover(_ highlightID: UUID?) {
        if let highlightID {
            pendingHoverClear?.cancel()
            pendingHoverClear = nil
            if hoveredHighlightID != highlightID {
                hoveredHighlightID = highlightID
            }
            return
        }

        guard hoveredHighlightID != nil, pendingHoverClear == nil else { return }
        let clear = DispatchWorkItem {
            hoveredHighlightID = nil
            pendingHoverClear = nil
        }
        pendingHoverClear = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: clear)
    }

    private func updateHover(from location: CGPoint?) {
        guard let location else {
            updateTrackedHover(nil)
            return
        }

        let highlightID = hoverRegions
            .first { region in
                guard highlights.first(where: { $0.id == region.highlightID })?.note.isEmpty == false else {
                    return false
                }
                return region.rect.insetBy(dx: -2, dy: -2).contains(location)
            }?
            .highlightID

        updateTrackedHover(highlightID)
    }

    private func activeEditingHighlight(rectsByHighlight: [UUID: [CGRect]]) -> ResolvedHighlight? {
        guard let editingHighlightID,
              let highlight = highlights.first(where: { $0.id == editingHighlightID }),
              rectsByHighlight[highlight.id]?.isEmpty == false
        else { return nil }
        return highlight
    }

    private func beginInlineEditing(_ highlight: ResolvedHighlight) {
        editingHighlightID = highlight.id
        editingNote = highlight.note
        hoveredHighlightID = nil
    }

    private func saveInlineEditor() {
        guard let editingHighlightID else { return }
        onUpdateNote(editingHighlightID, editingNote)
        self.editingHighlightID = nil
        editingNote = ""
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func cardPosition(for rects: [CGRect], in size: CGSize) -> CGPoint {
        let anchor = rects.first ?? .zero
        let width: CGFloat = 320
        let height: CGFloat = 96
        let x = min(max(anchor.midX, width / 2 + 12), max(width / 2 + 12, size.width - width / 2 - 12))
        let y = max(anchor.minY - height / 2 - 12, height / 2 + 12)
        return CGPoint(x: x, y: y)
    }

    private func editorPosition(for rects: [CGRect], in size: CGSize) -> CGPoint {
        let anchor = rects.first ?? .zero
        let width: CGFloat = 320
        let height: CGFloat = 150
        let x = min(max(anchor.midX, width / 2 + 12), max(width / 2 + 12, size.width - width / 2 - 12))
        let below = anchor.maxY + height / 2 + 12
        let above = anchor.minY - height / 2 - 12
        let y = below + height / 2 < size.height ? below : max(above, height / 2 + 12)
        return CGPoint(x: x, y: y)
    }

    private func resolvedTextRange(
        startOffset: Int,
        length: Int,
        blockText: String,
        model: TextSelectionModel
    ) -> Textual.TextRange? {
        let textLength = blockText.utf16.count
        guard startOffset >= 0,
              length > 0,
              startOffset < textLength,
              startOffset + length <= textLength
        else { return nil }

        guard let startPos = model.position(from: model.startPosition, offset: startOffset),
              let endPos = model.position(from: model.startPosition, offset: startOffset + length)
        else { return nil }

        return Textual.TextRange(start: startPos, end: endPos)
    }
}

extension View {
    func highlightInteractionOverlay(
        _ highlights: [ResolvedHighlight],
        onUpdateNote: @escaping (UUID, String) -> Void
    ) -> some View {
        modifier(HighlightInteractionOverlay(highlights: highlights, onUpdateNote: onUpdateNote))
    }
}

private struct HighlightHoverTrackingSurface: NSViewRepresentable {
    let rectsByHighlight: [UUID: [CGRect]]
    let highlights: [ResolvedHighlight]
    let onBeginEditing: (UUID) -> Void
    let onDeleteNote: (UUID) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onBeginEditing = onBeginEditing
        view.onDeleteNote = onDeleteNote
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.rectsByHighlight = rectsByHighlight
        view.highlightsByID = Dictionary(uniqueKeysWithValues: highlights.map { ($0.id, $0) })
        view.onBeginEditing = onBeginEditing
        view.onDeleteNote = onDeleteNote
        view.refreshTrackingArea()
    }

    final class TrackingView: NSView {
        var rectsByHighlight: [UUID: [CGRect]] = [:]
        var highlightsByID: [UUID: ResolvedHighlight] = [:]
        var onBeginEditing: ((UUID) -> Void)?
        var onDeleteNote: ((UUID) -> Void)?
        private var menuHighlightID: UUID?

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            refreshTrackingArea()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let localPoint = convert(point, from: superview)
            return highlightID(at: localPoint, includeEmptyNotes: true) == nil ? nil : self
        }

        func refreshTrackingArea() {
            trackingAreas.forEach(removeTrackingArea)

            let fullSurfaceArea = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(fullSurfaceArea)

            for (highlightID, rects) in rectsByHighlight {
                for rect in rects {
                    let area = NSTrackingArea(
                        rect: rect.insetBy(dx: -3, dy: -3),
                        options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
                        owner: self,
                        userInfo: ["highlightID": highlightID.uuidString]
                    )
                    addTrackingArea(area)
                }
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            refreshTrackingArea()
        }

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount >= 2,
                  let highlightID = highlightID(at: convert(event.locationInWindow, from: nil), includeEmptyNotes: true)
            else { return }
            DispatchQueue.main.async { [onBeginEditing] in
                onBeginEditing?(highlightID)
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let highlightID = highlightID(at: point, includeEmptyNotes: true),
                  let highlight = highlightsByID[highlightID]
            else { return }

            menuHighlightID = highlightID
            let menu = NSMenu()
            let editTitle = highlight.note.isEmpty ? "Add Highlight Note" : "Edit Highlight Note"
            let editItem = NSMenuItem(title: editTitle, action: #selector(editHighlightNote), keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)

            if !highlight.note.isEmpty {
                let deleteItem = NSMenuItem(title: "Delete Highlight Note", action: #selector(deleteHighlightNote), keyEquivalent: "")
                deleteItem.target = self
                menu.addItem(deleteItem)
            }

            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func editHighlightNote() {
            guard let menuHighlightID else { return }
            DispatchQueue.main.async { [onBeginEditing] in
                onBeginEditing?(menuHighlightID)
            }
        }

        @objc private func deleteHighlightNote() {
            guard let menuHighlightID else { return }
            DispatchQueue.main.async { [onDeleteNote] in
                onDeleteNote?(menuHighlightID)
            }
        }

        private func highlightID(at point: CGPoint, includeEmptyNotes: Bool) -> UUID? {
            rectsByHighlight.first { highlightID, rects in
                guard includeEmptyNotes || highlightsByID[highlightID]?.note.isEmpty == false else { return false }
                return rects.contains { $0.insetBy(dx: -2, dy: -2).contains(point) }
            }?.key
        }
    }
}

private struct HighlightNoteHoverCard: View {
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Highlight Note")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
    }
}

private struct HighlightInlineNoteEditor: View {
    @Binding var note: String
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Note to highlight")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            ZStack(alignment: .bottomTrailing) {
                TextField("Write a note", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(4...5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 106, alignment: .topLeading)
                    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.28), lineWidth: 0.75)
                    }
                    .focused($focused)
                    .onSubmit(onSubmit)

                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 8)
                    .padding(.bottom, 7)
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
        .onAppear {
            DispatchQueue.main.async {
                focused = true
            }
        }
    }
}
