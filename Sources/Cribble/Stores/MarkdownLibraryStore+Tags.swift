import Foundation

extension MarkdownLibraryStore {
    func allTags() -> [TagIndex.Tag] {
        tagIndex?.allTags() ?? []
    }

    func notes(forTag tag: String) -> [URL] {
        tagIndex?.notes(forTag: tag) ?? []
    }

    func selectTag(_ tag: String) {
        let normalized = TagIndex.normalize(tag)
        guard !normalized.isEmpty else { return }
        let existing = allTags().first { $0.normalized == normalized }
        let count = notes(forTag: normalized).count
        selectedTag = existing ?? TagIndex.Tag(name: normalized, normalized: normalized, count: count)
        statusMessage = "Filtered notes tagged #\(selectedTag?.name ?? normalized)"
    }

    func clearSelectedTag() {
        selectedTag = nil
    }
}
