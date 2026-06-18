import Foundation

struct WikiLink: Equatable, Hashable, Sendable {
    let original: String
    let target: String
    let label: String
    let anchor: String?
    /// UTF-16 range of the original `[[...]]` token in the source markdown.
    /// Nil for synthetic links constructed by tests or callers.
    var sourceRange: NSRange? = nil

    var normalizedTarget: String {
        LinkIndex.normalize(target)
    }
}

struct ResolvedLink: Equatable, Hashable, Sendable {
    let link: WikiLink
    let targetURL: URL?
    let anchor: String?

    var isResolved: Bool {
        targetURL != nil
    }
}
