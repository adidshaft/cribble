import AppKit
import SwiftUI
import Textual

struct HighlightInteractionOverlay: ViewModifier {
    let highlights: [ResolvedHighlight]
    @State private var model: TextSelectionModel?
    @State private var regions: [TextInteractionCursorRegion] = []

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
                        // Invisible active state to update state safely in the rendering cycle
                        Color.clear
                            .onChange(of: newRegions.map(\.rect), initial: true) { _, _ in
                                self.regions = newRegions
                            }

                        ForEach(highlights, id: \.id) { h in
                            ForEach(Array(rectsByHighlight[h.id, default: []].enumerated()), id: \.offset) { _, rect in
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .help(h.note.isEmpty ? "Highlight" : h.note)
                            }
                        }
                    }
                }
            }
    }

    private func computeRects(
        layouts: [Text.LayoutKey.AnchoredLayout],
        geometry: GeometryProxy
    ) -> [UUID: [CGRect]] {
        guard let model else { return [:] }
        var result: [UUID: [CGRect]] = [:]
        
        for h in highlights {
            let range: Textual.TextRange
            switch h.strategy {
            case .offset(let start, let length):
                guard let startPos = model.position(from: model.startPosition, offset: start),
                      let endPos = model.position(from: startPos, offset: length)
                else { continue }
                range = Textual.TextRange(start: startPos, end: endPos)
                
            case .textSearch(let quote):
                let fullRange = Textual.TextRange(start: model.startPosition, end: model.endPosition)
                let blockText = model.text(in: fullRange)
                guard let stringRange = blockText.range(of: quote, options: [.caseInsensitive, .diacriticInsensitive]),
                      let lowerUTF16 = stringRange.lowerBound.samePosition(in: blockText.utf16),
                      let upperUTF16 = stringRange.upperBound.samePosition(in: blockText.utf16)
                else { continue }
                let startOffset = blockText.utf16.distance(from: blockText.utf16.startIndex, to: lowerUTF16)
                let length = blockText.utf16.distance(from: lowerUTF16, to: upperUTF16)
                
                guard let startPos = model.position(from: model.startPosition, offset: startOffset),
                      let endPos = model.position(from: startPos, offset: length)
                else { continue }
                range = Textual.TextRange(start: startPos, end: endPos)
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
}

extension View {
    func highlightInteractionOverlay(_ highlights: [ResolvedHighlight]) -> some View {
        modifier(HighlightInteractionOverlay(highlights: highlights))
    }
}
