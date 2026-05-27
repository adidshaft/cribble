import AppKit
import SwiftUI
import Textual

struct HighlightInteractionOverlay: ViewModifier {
    let highlights: [ResolvedHighlight]
    let onUpdateNote: (UUID, String) -> Void
    @State private var model: TextSelectionModel?
    @State private var regions: [TextInteractionCursorRegion] = []
    @State private var hoveredHighlightID: UUID?
    @State private var editingHighlightID: UUID?
    @State private var editingNote: String = ""

    func body(content: Content) -> some View {
        content
            .environment(\.textInteractionCursorRegions, regions)
            .onPreferenceChange(TextSelectionModelPreferenceKey.self) { newModel in
                self.model = newModel
            }
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                GeometryReader { geometry in
                    let rectsByHighlight = computeRects(
                        layouts: layouts,
                        geometry: geometry
                    )
                    
                    let allRects = rectsByHighlight.values.flatMap { $0 }
                    let newRegions = allRects.map { TextInteractionCursorRegion(rect: $0, cursor: .cribbleHighlightHand) }
                    
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
                            .onChange(of: newRegions.map(\.rect), initial: true) { _, _ in
                                self.regions = newRegions
                            }

                        ForEach(highlights, id: \.id) { h in
                            ForEach(Array(rectsByHighlight[h.id, default: []].enumerated()), id: \.offset) { _, rect in
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .onHover { hovering in
                                        if hovering, !h.note.isEmpty {
                                            hoveredHighlightID = h.id
                                        } else if hoveredHighlightID == h.id {
                                            hoveredHighlightID = nil
                                        }
                                    }
                                    .onTapGesture {
                                        guard !h.note.isEmpty else { return }
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
            let range: Textual.TextRange
            switch h.strategy {
            case .offset(let start, let length):
                guard let resolvedRange = resolvedTextRange(
                    startOffset: start,
                    length: length,
                    blockText: blockText,
                    model: model
                )
                else { continue }
                range = resolvedRange
                
            case .textSearch(let quote):
                guard let stringRange = blockText.range(of: quote, options: [.caseInsensitive, .diacriticInsensitive]),
                      let lowerUTF16 = stringRange.lowerBound.samePosition(in: blockText.utf16),
                      let upperUTF16 = stringRange.upperBound.samePosition(in: blockText.utf16)
                else { continue }
                let startOffset = blockText.utf16.distance(from: blockText.utf16.startIndex, to: lowerUTF16)
                let length = blockText.utf16.distance(from: lowerUTF16, to: upperUTF16)
                
                guard let resolvedRange = resolvedTextRange(
                    startOffset: startOffset,
                    length: length,
                    blockText: blockText,
                    model: model
                )
                else { continue }
                range = resolvedRange
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

    private func activeHoverHighlight(rectsByHighlight: [UUID: [CGRect]]) -> ResolvedHighlight? {
        guard let hoveredHighlightID,
              let highlight = highlights.first(where: { $0.id == hoveredHighlightID }),
              !highlight.note.isEmpty,
              rectsByHighlight[highlight.id]?.isEmpty == false
        else { return nil }
        return highlight
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
        .onAppear { focused = true }
    }
}
