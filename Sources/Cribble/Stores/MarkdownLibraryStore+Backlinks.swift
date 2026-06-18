import Foundation

extension MarkdownLibraryStore {
    func backlinks(for url: URL) -> [Backlink] {
        guard let backlinkIndex else { return [] }
        return backlinkIndex.backlinks(for: url) { sourceURL, range in
            guard let markdown = try? DocumentLoader.readText(at: sourceURL) else { return nil }
            return BacklinkIndex.snippet(in: markdown, around: range)
        }
    }
}
