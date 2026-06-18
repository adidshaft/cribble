import Foundation

struct ResolvedEmbed: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case resolved
        case unresolved
        case cyclic
        case depthLimited
    }

    let reference: EmbedReference
    let state: State
    let targetURL: URL?
    let title: String
    let markdown: String
}

struct EmbedResolver: Sendable {
    static let defaultMaxDepth = 3

    private let documentsByURL: [URL: MarkdownDocument]
    private let linkIndex: LinkIndex
    private let maxDepth: Int

    init(documents: [MarkdownDocument], rootURL: URL, maxDepth: Int = Self.defaultMaxDepth) {
        documentsByURL = Dictionary(uniqueKeysWithValues: documents.map { ($0.url.standardizedFileURL, $0) })
        linkIndex = LinkIndex(documents: documents, rootURL: rootURL)
        self.maxDepth = max(0, maxDepth)
    }

    func resolve(_ reference: EmbedReference, sourceURL: URL? = nil, depth: Int = 0, visited: Set<URL> = []) -> ResolvedEmbed {
        guard depth <= maxDepth else {
            return stub(reference, state: .depthLimited, title: reference.label, markdown: "Embed depth limit reached for ![[\(reference.label)]].")
        }

        let link = WikiLink(
            original: reference.original,
            target: reference.target,
            label: reference.label,
            anchor: reference.heading
        )
        let resolved = linkIndex.resolve(link)
        guard let targetURL = resolved.targetURL?.standardizedFileURL,
              let document = documentsByURL[targetURL] else {
            return stub(reference, state: .unresolved, title: reference.label, markdown: "Cannot resolve \(reference.original).")
        }

        let visitedWithSource = sourceURL.map { visited.union([$0.standardizedFileURL]) } ?? visited
        guard !visitedWithSource.contains(targetURL) else {
            return stub(reference, state: .cyclic, targetURL: targetURL, title: document.title, markdown: "Cyclic embed: \(document.title).")
        }

        return ResolvedEmbed(
            reference: reference,
            state: .resolved,
            targetURL: targetURL,
            title: document.title,
            markdown: markdownSlice(for: reference, in: document)
        )
    }

    func containsCycle(in markdown: String, sourceURL: URL, depth: Int = 0, visited: Set<URL> = []) -> Bool {
        let visited = visited.union([sourceURL.standardizedFileURL])
        for reference in WikiLinkParser.parseEmbeds(markdown) {
            let resolved = resolve(reference, sourceURL: sourceURL, depth: depth, visited: visited)
            if resolved.state == .cyclic {
                return true
            }
            guard depth < maxDepth, let targetURL = resolved.targetURL, !resolved.markdown.isEmpty else {
                continue
            }
            if containsCycle(in: resolved.markdown, sourceURL: targetURL, depth: depth + 1, visited: visited) {
                return true
            }
        }
        return false
    }

    private func markdownSlice(for reference: EmbedReference, in document: MarkdownDocument) -> String {
        if let blockID = reference.blockID {
            return Self.blockSlice(blockID: blockID, in: document.rawMarkdown) ?? ""
        }
        if let heading = reference.heading {
            return Self.headingSlice(heading: heading, in: document.rawMarkdown) ?? ""
        }
        return document.rawMarkdown
    }

    private func stub(
        _ reference: EmbedReference,
        state: ResolvedEmbed.State,
        targetURL: URL? = nil,
        title: String,
        markdown: String
    ) -> ResolvedEmbed {
        ResolvedEmbed(
            reference: reference,
            state: state,
            targetURL: targetURL,
            title: title,
            markdown: markdown
        )
    }

    static func headingSlice(heading: String, in markdown: String) -> String? {
        let requested = Slugger.slug(heading)
        let lines = markdown.components(separatedBy: "\n")
        var start: Int?
        var startLevel = 0

        for (index, line) in lines.enumerated() {
            guard let parsed = parseHeading(line) else { continue }
            if let start, parsed.level <= startLevel {
                return lines[start..<index].joined(separator: "\n").trimmingCharacters(in: .newlines)
            }
            if start == nil, parsed.anchor == requested {
                start = index
                startLevel = parsed.level
            }
        }

        guard let start else { return nil }
        return lines[start...].joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    static func blockSlice(blockID: String, in markdown: String) -> String? {
        for line in markdown.components(separatedBy: "\n") {
            guard Self.blockAnchor(in: line) == blockID else { continue }
            return Self.lineWithoutBlockAnchor(line).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func blockAnchor(in line: String) -> String? {
        guard let regex = blockAnchorRegex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let idRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[idRange])
    }

    private static func lineWithoutBlockAnchor(_ line: String) -> String {
        guard let regex = blockAnchorRegex else { return line }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
    }

    private static func parseHeading(_ line: String) -> (level: Int, anchor: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let markerCount = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount),
              trimmed.dropFirst(markerCount).first?.isWhitespace == true else {
            return nil
        }
        let title = trimmed.dropFirst(markerCount).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (markerCount, Slugger.slug(title))
    }

    private static let blockAnchorRegex = try? NSRegularExpression(
        pattern: #"\s+\^([A-Za-z0-9][A-Za-z0-9_-]*)\s*$"#
    )
}
