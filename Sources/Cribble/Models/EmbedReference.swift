import Foundation

struct EmbedReference: Equatable, Hashable, Sendable {
    let original: String
    let target: String
    let label: String
    let heading: String?
    let blockID: String?
    /// UTF-16 range of the original `![[...]]` token in the source markdown.
    /// Nil for synthetic embeds constructed by tests or future callers.
    var sourceRange: NSRange? = nil

    var normalizedTarget: String {
        LinkIndex.normalize(target)
    }
}
