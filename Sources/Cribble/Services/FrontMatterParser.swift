import Foundation

struct FrontMatter {
    var aliases: [String] = []
    var keywords: [String] = []
    var tags: [String] = []
}

enum FrontMatterParser {
    static func parse(_ markdown: String) -> FrontMatter {
        guard markdown.hasPrefix("---") else { return FrontMatter() }

        var metadata = FrontMatter()
        var isFirst = true
        var linesToProcess: [String] = []
        var lineCount = 0

        markdown.enumerateLines { line, stop in
            if isFirst {
                isFirst = false
                if line != "---" {
                    stop = true
                    return
                }
                return
            }

            if line == "---" {
                stop = true
                return
            }

            lineCount += 1
            if lineCount > 100 { // Limit front matter scan to first 100 lines
                stop = true
                return
            }

            linesToProcess.append(line)
        }

        for line in linesToProcess {
            if line.hasPrefix("aliases:") {
                metadata.aliases = parseListValue(line, key: "aliases")
            } else if line.hasPrefix("keywords:") {
                metadata.keywords = parseListValue(line, key: "keywords")
            } else if line.hasPrefix("tags:") {
                metadata.tags = parseListValue(line, key: "tags")
            }
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
