import Foundation

extension MarkdownLibraryStore {
    func allTags() -> [TagIndex.Tag] {
        tagIndex?.allTags() ?? []
    }

    func notes(forTag tag: String) -> [URL] {
        tagIndex?.notes(forTag: tag) ?? []
    }
}
