import Foundation

enum WikiLinkParser {
    static func parse(_ markdown: String) -> [WikiLink] {
        let pattern = #"\[\[([^\]\n]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.matches(in: markdown, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: markdown) else {
                return nil
            }

            let inner = String(markdown[range])
            let originalRange = Range(match.range(at: 0), in: markdown).map { String(markdown[$0]) } ?? "[[\(inner)]]"
            return parseInner(inner, original: originalRange)
        }
    }

    static func renderForMarkdown(_ markdown: String, index: LinkIndex?) -> String {
        let links = parse(markdown)
        guard !links.isEmpty else { return markdown }

        var rendered = markdown
        for link in links.reversed() {
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

            rendered = rendered.replacingOccurrences(
                of: link.original,
                with: "[\(escapeMarkdownLabel(link.label))](\(destination))"
            )
        }
        return rendered
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
}
