import Foundation

struct MarkdownDocument: Equatable, Sendable {
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

/// Lightweight, body-free description of a note. The library keeps one of these
/// per file resident (instead of the full `MarkdownDocument` with its complete
/// text) so a large vault doesn't pin every note's contents in RAM. The full
/// body is loaded on demand for the note actually being read, and a small
/// `embeddingPrefix` + precomputed `contentHash` keep the semantic index working
/// without retaining whole files.
struct MarkdownDocumentMeta: Equatable, Sendable, Identifiable {
    let url: URL
    let title: String
    let headings: [DocumentHeading]
    let outboundLinks: [WikiLink]
    let linkAliases: [String]
    /// Stable (cross-launch) hash of title + body, for change detection.
    let contentHash: UInt64
    /// De-noised leading slice of the body used to build the semantic embedding.
    let embeddingPrefix: String

    var id: URL { url }

    var isReadme: Bool {
        url.lastPathComponent.localizedCaseInsensitiveCompare("README.md") == .orderedSame
    }

    init(
        url: URL,
        title: String,
        headings: [DocumentHeading],
        outboundLinks: [WikiLink],
        linkAliases: [String] = [],
        contentHash: UInt64,
        embeddingPrefix: String
    ) {
        self.url = url
        self.title = title
        self.headings = headings
        self.outboundLinks = outboundLinks
        self.linkAliases = linkAliases
        self.contentHash = contentHash
        self.embeddingPrefix = embeddingPrefix
    }

    /// Derives metadata (including the embedding inputs) from a fully-loaded doc.
    init(_ document: MarkdownDocument) {
        self.url = document.url
        self.title = document.title
        self.headings = document.headings
        self.outboundLinks = document.outboundLinks
        let metadata = FrontMatterParser.parse(document.rawMarkdown)
        self.linkAliases = metadata.aliases + metadata.keywords + metadata.tags
        self.contentHash = SemanticSearchIndex.stableHash(title: document.title, body: document.rawMarkdown)
        self.embeddingPrefix = SemanticSearchIndex.embeddingPrefix(forBody: document.rawMarkdown)
    }
}

struct DocumentHeading: Equatable, Hashable, Sendable {
    let level: Int
    let title: String

    var anchor: String {
        Slugger.slug(title)
    }
}
