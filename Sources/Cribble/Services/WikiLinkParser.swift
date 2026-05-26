import Foundation

enum WikiLinkParser {
    static func parse(_ markdown: String) -> [WikiLink] {
        guard let regex = Self.regex else { return [] }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.matches(in: markdown, range: nsRange).compactMap { match in
            guard let innerRange = Range(match.range(at: 1), in: markdown),
                  let outerRange = Range(match.range(at: 0), in: markdown) else {
                return nil
            }
            return parseInner(String(markdown[innerRange]), original: String(markdown[outerRange]))
        }
    }

    static func renderForMarkdown(_ markdown: String, index: LinkIndex?) -> String {
        guard let regex = Self.regex else { return markdown }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = regex.matches(in: markdown, range: nsRange)
        guard !matches.isEmpty else { return markdown }

        var result = markdown
        for match in matches.reversed() {
            guard let innerRange = Range(match.range(at: 1), in: result),
                  let outerRange = Range(match.range(at: 0), in: result) else {
                continue
            }
            let link = parseInner(String(result[innerRange]), original: String(result[outerRange]))
            result.replaceSubrange(outerRange, with: replacement(for: link, index: index))
        }
        return result
    }

    private static func replacement(for link: WikiLink, index: LinkIndex?) -> String {
        let resolved = index?.resolve(link)
        let destination: String
        if let targetURL = resolved?.targetURL {
            var components = URLComponents()
            components.scheme = "cribble"
            components.host = "open"
            components.queryItems = [
                URLQueryItem(name: "path", value: targetURL.path),
                URLQueryItem(name: "anchor", value: resolved?.anchor)
            ].compactMap { $0.value == nil ? nil : $0 }
            destination = components.url?.absoluteString ?? "cribble://unresolved"
        } else {
            var components = URLComponents()
            components.scheme = "cribble"
            components.host = "unresolved"
            components.queryItems = [URLQueryItem(name: "target", value: link.target)]
            destination = components.url?.absoluteString ?? "cribble://unresolved"
        }
        let prefix = resolved?.targetURL == nil ? "⟂ " : "↗ "
        return "[\(prefix)\(escapeMarkdownLabel(link.label))](\(destination))"
    }

    private static func parseInner(_ inner: String, original: String) -> WikiLink {
        let parts = inner.components(separatedBy: "|")
        let targetPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let label = parts.dropFirst().joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)

        let targetPieces = targetPart.components(separatedBy: "#")
        let target = targetPieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let anchor = targetPieces.dropFirst().joined(separator: "#").trimmingCharacters(in: .whitespacesAndNewlines)

        return WikiLink(
            original: original,
            target: target,
            label: label.isEmpty ? target : label,
            anchor: anchor.isEmpty ? nil : anchor
        )
    }

    private static func escapeMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#)
    }()
}
