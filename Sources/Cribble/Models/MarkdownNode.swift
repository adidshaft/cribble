import Foundation

struct MarkdownNode: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case folder
        case markdown
    }

    let id: URL
    let name: String
    let url: URL
    let kind: Kind
    let createdAt: Date?
    let modifiedAt: Date?
    let readmeURL: URL?
    var children: [MarkdownNode]

    var isMarkdownFile: Bool {
        kind == .markdown
    }

    var selectableURL: URL {
        readmeURL ?? url
    }

    var childNodes: [MarkdownNode]? {
        kind == .folder ? children : nil
    }
}
