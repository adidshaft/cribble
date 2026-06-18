import Foundation

extension MarkdownLibraryStore {
    func backlinks(for url: URL) -> [Backlink] {
        Self.backlinks(for: url, index: backlinkIndex)
    }

    nonisolated static func backlinks(for url: URL, index: BacklinkIndex?) -> [Backlink] {
        guard let backlinkIndex = index else { return [] }
        return backlinkIndex.backlinks(for: url) { sourceURL, range in
            guard let markdown = try? DocumentLoader.readText(at: sourceURL) else { return nil }
            return BacklinkIndex.snippet(in: markdown, around: range)
        }
    }
}
