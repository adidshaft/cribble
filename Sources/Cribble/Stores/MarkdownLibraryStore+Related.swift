import Foundation

extension MarkdownLibraryStore {
    func relatedNotes(for url: URL, semanticIndex: SemanticSearchIndex, limit: Int = 5) -> [SemanticHit] {
        semanticIndex.relatedNotes(to: url, limit: limit)
    }
}
