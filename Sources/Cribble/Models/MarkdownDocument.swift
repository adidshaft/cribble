import Foundation

struct MarkdownDocument: Equatable {
    let url: URL
    let title: String
    let rawMarkdown: String
    let headings: [DocumentHeading]
    let outboundLinks: [WikiLink]

    var isReadme: Bool {
        url.lastPathComponent.localizedCaseInsensitiveCompare("README.md") == .orderedSame
    }

    var isEssentiallyEmptyReadme: Bool {
        isReadme && MarkdownDisplayPreprocessor.isEssentiallyEmpty(rawMarkdown, documentTitle: title)
    }
}

struct DocumentHeading: Equatable, Hashable {
    let level: Int
    let title: String

    var anchor: String {
        Slugger.slug(title)
    }
}
