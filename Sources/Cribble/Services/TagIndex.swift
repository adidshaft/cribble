import Foundation

struct TagIndex: Sendable {
    struct Tag: Equatable, Sendable {
        let name: String
        let normalized: String
        let count: Int
    }

    struct TagOccurrence: Equatable, Sendable {
        let tag: String
        let range: Range<String.Index>
    }

    private var displayNames: [String: String] = [:]
    private var urlsByTag: [String: Set<URL>] = [:]

    init(documents: [MarkdownDocumentMeta]) {
        for document in documents {
            let tags = document.frontMatterTags + document.inlineTags
            for tag in tags {
                let normalized = Self.normalize(tag)
                guard !normalized.isEmpty else { continue }
                displayNames[normalized] = displayNames[normalized] ?? Self.displayName(for: tag)
                urlsByTag[normalized, default: []].insert(document.url.standardizedFileURL)
            }
        }
    }

    func allTags() -> [Tag] {
        urlsByTag.map { normalized, urls in
            Tag(
                name: displayNames[normalized] ?? normalized,
                normalized: normalized,
                count: urls.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func notes(forTag tag: String) -> [URL] {
        let normalized = Self.normalize(tag)
        guard !normalized.isEmpty else { return [] }
        let urls = urlsByTag
            .filter { candidate, _ in
                candidate == normalized || candidate.hasPrefix("\(normalized)/")
            }
            .flatMap(\.value)
        return Array(Set(urls))
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    static func tags(in markdown: String) -> [String] {
        uniqued(tagOccurrences(in: markdown).map(\.tag))
    }

    static func tagOccurrences(in markdown: String) -> [TagOccurrence] {
        var foundTags: [TagOccurrence] = []
        var isInFence = false
        var isFrontMatter = false
        var isFirstLine = true

        markdown.enumerateSubstrings(in: markdown.startIndex..<markdown.endIndex, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = String(markdown[lineRange])

            if isFirstLine {
                isFirstLine = false
                if line == "---" {
                    isFrontMatter = true
                    return
                }
            } else if isFrontMatter {
                if line == "---" {
                    isFrontMatter = false
                }
                return
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                isInFence.toggle()
                return
            }
            guard !isInFence, !trimmed.hasPrefix("#") else { return }

            foundTags.append(contentsOf: tagOccurrences(inLine: line, lineStart: lineRange.lowerBound, source: markdown))
        }

        return foundTags
    }

    static func normalize(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        return LinkIndex.normalize(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func tagOccurrences(inLine line: String, lineStart: String.Index, source: String) -> [TagOccurrence] {
        var occurrences: [TagOccurrence] = []
        var index = line.startIndex
        var isInInlineCode = false

        while index < line.endIndex {
            let character = line[index]
            if character == "`" {
                isInInlineCode.toggle()
                index = line.index(after: index)
                continue
            }

            guard !isInInlineCode, character == "#" else {
                index = line.index(after: index)
                continue
            }

            let previous = index > line.startIndex ? line[line.index(before: index)] : nil
            guard previous == nil || isTagBoundary(previous!) else {
                index = line.index(after: index)
                continue
            }

            var cursor = line.index(after: index)
            while cursor < line.endIndex, isTagCharacter(line[cursor]) {
                cursor = line.index(after: cursor)
            }

            if cursor > line.index(after: index) {
                let value = String(line[line.index(after: index)..<cursor])
                let lower = source.index(lineStart, offsetBy: line.distance(from: line.startIndex, to: index))
                let upper = source.index(lineStart, offsetBy: line.distance(from: line.startIndex, to: cursor))
                occurrences.append(TagOccurrence(tag: value, range: lower..<upper))
                index = cursor
            } else {
                index = line.index(after: index)
            }
        }

        return occurrences
    }

    private static func isTagBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }
    }

    private static func isTagCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-"
                || scalar == "_"
                || scalar == "/"
        }
    }

    private static func displayName(for tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        return value
    }

    private static func uniqued(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for tag in tags {
            let normalized = normalize(tag)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(tag)
        }
        return ordered
    }
}
