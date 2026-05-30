import Foundation

/// Who authored a chat turn in the Local Chat HUD.
enum ChatRole: String, Codable, Hashable {
    case user
    case assistant
}

/// A single message in a HUD conversation. The `attachments` are the `@file`
/// tokens the user pinned to a user turn; they are rendered as badges and their
/// contents are folded into the model prompt by `ContextAssembler`.
struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let role: ChatRole
    var text: String
    var attachments: [TaggedFileToken]
    /// True while the assistant turn is still streaming tokens in.
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        attachments: [TaggedFileToken] = [],
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.isStreaming = isStreaming
    }
}

/// A reference to a workspace Markdown file that the user tagged with `@`.
/// Lightweight and `Hashable` so it can drive SwiftUI lists and dedup sets.
struct TaggedFileToken: Identifiable, Hashable {
    let id: UUID
    let filename: String
    let fileURL: URL

    init(id: UUID = UUID(), filename: String, fileURL: URL) {
        self.id = id
        self.filename = filename
        self.fileURL = fileURL
    }

    /// The label shown inside the inline capsule / badge.
    var displayName: String {
        fileURL.deletingPathExtension().lastPathComponent
    }
}

/// Transient state describing an in-progress `@` autocomplete session in the
/// input bar. Owned by `ChatHUDViewModel`, consumed by the popover view.
struct FileAutocompleteState: Equatable {
    /// The substring typed after the most recent `@`, without the `@`.
    var query: String
    /// Up to a handful of matching files, best-first.
    var matches: [TaggedFileToken]

    var isEmpty: Bool { matches.isEmpty }
}
