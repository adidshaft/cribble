import Foundation

extension MarkdownLibraryStore {
    func localGraph(for url: URL, hops: Int = 2, maxNodes: Int = 40) -> LocalNoteGraph? {
        guard let root = rootURL(for: url), !documents.isEmpty else { return nil }
        return LocalNoteGraph.neighborhood(
            of: url,
            documents: documents,
            rootURL: root,
            hops: hops,
            maxNodes: maxNodes
        )
    }
}
