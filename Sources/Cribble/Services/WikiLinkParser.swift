import Foundation

enum WikiLinkParser {
    static func parse(_ markdown: String) -> [WikiLink] {
        guard let regex = Self.regex else { return [] }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let codeRanges = Self.codeRanges(in: markdown)
        return regex.matches(in: markdown, range: nsRange).compactMap { match in
            guard !codeRanges.contains(where: { NSIntersectionRange($0, match.range(at: 0)).length > 0 }) else {
                return nil
            }
            guard !isEmbedMatch(match, in: markdown) else {
                return nil
            }
            guard let innerRange = Range(match.range(at: 1), in: markdown),
                  let outerRange = Range(match.range(at: 0), in: markdown) else {
                return nil
            }
            return parseInner(
                String(markdown[innerRange]),
                original: String(markdown[outerRange]),
                sourceRange: match.range(at: 0)
            )
        }
    }

    static func renderForMarkdown(_ markdown: String, index: LinkIndex?) -> String {
        guard let regex = Self.regex else { return markdown }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let codeRanges = Self.codeRanges(in: markdown)
        let matches = regex.matches(in: markdown, range: nsRange).filter { match in
            !codeRanges.contains { NSIntersectionRange($0, match.range(at: 0)).length > 0 }
                && !isEmbedMatch(match, in: markdown)
        }
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

    static func parseEmbeds(_ markdown: String) -> [EmbedReference] {
        guard let regex = Self.embedRegex else { return [] }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let codeRanges = Self.codeRanges(in: markdown)
        return regex.matches(in: markdown, range: nsRange).compactMap { match in
            guard !codeRanges.contains(where: { NSIntersectionRange($0, match.range(at: 0)).length > 0 }) else {
                return nil
            }
            guard let innerRange = Range(match.range(at: 1), in: markdown),
                  let outerRange = Range(match.range(at: 0), in: markdown) else {
                return nil
            }
            return parseEmbedInner(
                String(markdown[innerRange]),
                original: String(markdown[outerRange]),
                sourceRange: match.range(at: 0)
            )
        }
    }

    private static func replacement(for link: WikiLink, index: LinkIndex?) -> String {
        let resolved = index?.resolve(link)
        let destination: String
        if let targetURL = resolved?.targetURL {
            // Block anchors (`#^id`) are passed through raw so the reader can map
            // them to the line's enclosing section; heading anchors stay slugged.
            let anchorValue: String?
            if let raw = link.anchor, raw.hasPrefix("^") {
                anchorValue = raw
            } else {
                anchorValue = resolved?.anchor
            }
            var components = URLComponents()
            components.scheme = "cribble"
            components.host = "open"
            components.queryItems = [
                URLQueryItem(name: "path", value: targetURL.path),
                URLQueryItem(name: "anchor", value: anchorValue)
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

    private static func parseInner(_ inner: String, original: String, sourceRange: NSRange? = nil) -> WikiLink {
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
            anchor: anchor.isEmpty ? nil : anchor,
            sourceRange: sourceRange
        )
    }

    private static func parseEmbedInner(_ inner: String, original: String, sourceRange: NSRange? = nil) -> EmbedReference {
        let parts = inner.components(separatedBy: "|")
        let targetPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let label = parts.dropFirst().joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)

        let parsedTarget = parseEmbedTarget(targetPart)
        return EmbedReference(
            original: original,
            target: parsedTarget.target,
            label: label.isEmpty ? targetPart : label,
            heading: parsedTarget.heading,
            blockID: parsedTarget.blockID,
            sourceRange: sourceRange
        )
    }

    private static func parseEmbedTarget(_ targetPart: String) -> (target: String, heading: String?, blockID: String?) {
        let hashPieces = targetPart.components(separatedBy: "#")
        let targetAndInlineBlock = hashPieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let anchor = hashPieces.dropFirst().joined(separator: "#").trimmingCharacters(in: .whitespacesAndNewlines)

        let targetPieces = targetAndInlineBlock.components(separatedBy: "^")
        let target = targetPieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let inlineBlock = targetPieces.dropFirst().joined(separator: "^").trimmingCharacters(in: .whitespacesAndNewlines)

        if !inlineBlock.isEmpty {
            return (target, nil, inlineBlock)
        }
        if anchor.hasPrefix("^") {
            return (target, nil, String(anchor.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (target, anchor.isEmpty ? nil : anchor, nil)
    }

    private static func escapeMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#)
    }()

    private static let embedRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"!\[\[([^\]\n]+)\]\]"#)
    }()

    private static func isEmbedMatch(_ match: NSTextCheckingResult, in markdown: String) -> Bool {
        guard let range = Range(match.range(at: 0), in: markdown),
              range.lowerBound > markdown.startIndex else {
            return false
        }
        return markdown[markdown.index(before: range.lowerBound)] == "!"
    }

    private static func codeRanges(in markdown: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var inFence = false
        var fenceMarker: String?
        var lineStart = markdown.startIndex

        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let nextLineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : markdown.endIndex
            let line = String(markdown[lineStart..<lineEnd])
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = fenceStartMarker(in: trimmed)

            if inFence {
                ranges.append(NSRange(lineStart..<nextLineStart, in: markdown))
                if let marker, marker == fenceMarker {
                    inFence = false
                    fenceMarker = nil
                }
            } else if let marker {
                inFence = true
                fenceMarker = marker
                ranges.append(NSRange(lineStart..<nextLineStart, in: markdown))
            } else {
                ranges.append(contentsOf: inlineCodeRanges(in: markdown, lineStart: lineStart, lineEnd: lineEnd))
            }

            lineStart = nextLineStart
        }

        return ranges
    }

    private static func fenceStartMarker(in trimmedLine: String) -> String? {
        if trimmedLine.hasPrefix("```") { return "```" }
        if trimmedLine.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func inlineCodeRanges(in markdown: String, lineStart: String.Index, lineEnd: String.Index) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = lineStart

        while cursor < lineEnd {
            guard markdown[cursor] == "`" else {
                cursor = markdown.index(after: cursor)
                continue
            }

            let tickStart = cursor
            var tickEnd = cursor
            while tickEnd < lineEnd, markdown[tickEnd] == "`" {
                tickEnd = markdown.index(after: tickEnd)
            }
            let tickCount = markdown.distance(from: tickStart, to: tickEnd)
            var search = tickEnd
            var closingEnd: String.Index?

            while search < lineEnd {
                guard markdown[search] == "`" else {
                    search = markdown.index(after: search)
                    continue
                }
                let closeStart = search
                var closeEnd = search
                while closeEnd < lineEnd, markdown[closeEnd] == "`" {
                    closeEnd = markdown.index(after: closeEnd)
                }
                if markdown.distance(from: closeStart, to: closeEnd) == tickCount {
                    closingEnd = closeEnd
                    break
                }
                search = closeEnd
            }

            if let closingEnd {
                ranges.append(NSRange(tickStart..<closingEnd, in: markdown))
                cursor = closingEnd
            } else {
                cursor = tickEnd
            }
        }

        return ranges
    }
}
