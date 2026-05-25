import Foundation

struct MarkdownNode: Identifiable, Hashable {
    enum Kind: String, Codable, Hashable {
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
}
