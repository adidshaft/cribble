import Foundation

struct MarkdownDocument: Equatable {
    let url: URL
    let title: String
    let rawMarkdown: String
    let headings: [DocumentHeading]
    let outboundLinks: [WikiLink]
}

struct DocumentHeading: Equatable, Hashable {
    let level: Int
    let title: String

    var anchor: String {
        Slugger.slug(title)
    }
}
