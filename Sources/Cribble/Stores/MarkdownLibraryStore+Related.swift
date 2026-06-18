import Foundation

extension MarkdownLibraryStore {
    func relatedNotes(for url: URL, semanticIndex: SemanticSearchIndex, limit: Int = 5) -> [SemanticHit] {
        semanticIndex.relatedNotes(to: url, limit: limit)
    }

    func relatedNotesOffMain(for url: URL, semanticIndex: SemanticSearchIndex, limit: Int = 5) async -> [SemanticHit] {
        await semanticIndex.relatedNotesOffMain(to: url, limit: limit)
    }
}
