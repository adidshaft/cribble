import Foundation

struct FrontMatter {
    var aliases: [String] = []
    var keywords: [String] = []
    var tags: [String] = []
}

enum FrontMatterParser {
    static func parse(_ markdown: String) -> FrontMatter {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first == "---" else { return FrontMatter() }

        var metadata = FrontMatter()
        var index = 1

        while index < lines.count {
            let line = lines[index]
            if line == "---" { break }

            if line.hasPrefix("aliases:") {
                metadata.aliases = parseListValue(line, key: "aliases")
            } else if line.hasPrefix("keywords:") {
                metadata.keywords = parseListValue(line, key: "keywords")
            } else if line.hasPrefix("tags:") {
                metadata.tags = parseListValue(line, key: "tags")
            }

            index += 1
        }

        return metadata
    }

    private static func parseListValue(_ line: String, key: String) -> [String] {
        let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("[") && value.hasSuffix("]") {
            return value
                .dropFirst()
                .dropLast()
                .split(separator: ",")
                .map(clean)
                .filter { !$0.isEmpty }
        }

        return value
            .split(separator: ",")
            .map(clean)
            .filter { !$0.isEmpty }
    }

    private static func clean(_ value: Substring) -> String {
        String(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
