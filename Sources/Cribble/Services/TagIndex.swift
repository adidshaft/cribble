import Foundation

struct TagIndex: Sendable {
    struct Tag: Equatable, Sendable {
        let name: String
        let normalized: String
        let count: Int
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
        var foundTags: [String] = []
        var isInFence = false
        var isFrontMatter = false
        var isFirstLine = true

        markdown.enumerateLines { line, _ in
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

            foundTags.append(contentsOf: tags(inLine: line))
        }

        return uniqued(foundTags)
    }

    static func normalize(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        return LinkIndex.normalize(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func tags(inLine line: String) -> [String] {
        let scalars = Array(line.unicodeScalars)
        var tags: [String] = []
        var index = 0
        var isInInlineCode = false

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "`" {
                isInInlineCode.toggle()
                index += 1
                continue
            }

            guard !isInInlineCode, scalar == "#" else {
                index += 1
                continue
            }

            let previous = index > 0 ? scalars[index - 1] : nil
            guard previous == nil || isTagBoundary(previous!) else {
                index += 1
                continue
            }

            var cursor = index + 1
            while cursor < scalars.count, isTagCharacter(scalars[cursor]) {
                cursor += 1
            }

            if cursor > index + 1 {
                let value = String(String.UnicodeScalarView(scalars[index + 1..<cursor]))
                tags.append(value)
                index = cursor
            } else {
                index += 1
            }
        }

        return tags
    }

    private static func isTagBoundary(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(scalar)
            || CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.symbols.contains(scalar)
    }

    private static func isTagCharacter(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
            || scalar == "-"
            || scalar == "_"
            || scalar == "/"
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
