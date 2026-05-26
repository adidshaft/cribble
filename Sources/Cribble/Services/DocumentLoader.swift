import Foundation
import Markdown

struct DocumentLoader {
    func load(url: URL) throws -> MarkdownDocument {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let headings = parseHeadings(from: raw)
        let title = headings.first(where: { $0.level == 1 })?.title ?? url.deletingPathExtension().lastPathComponent
        let outboundLinks = WikiLinkParser.parse(raw)
        return MarkdownDocument(url: url, title: title, rawMarkdown: raw, headings: headings, outboundLinks: outboundLinks)
    }

    private func parseHeadings(from raw: String) -> [DocumentHeading] {
        raw.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            let text = String(line)
            guard text.hasPrefix("#") else { return nil }
            let markerCount = text.prefix { $0 == "#" }.count
            guard (1...6).contains(markerCount) else { return nil }
            let rest = text.dropFirst(markerCount)
            guard rest.first == " " else { return nil }
            let title = rest.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return DocumentHeading(level: markerCount, title: title)
        }
    }
}
