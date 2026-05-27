import Foundation

enum MarkdownDisplayPreprocessor {
    static func prepare(_ markdown: String, documentTitle: String) -> String {
        let withoutFrontMatter = stripFrontMatter(markdown)
        let withoutDuplicateTitle = stripLeadingTitle(withoutFrontMatter, title: documentTitle)
        return enrichTaskListMarkers(withoutDuplicateTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isEssentiallyEmpty(_ markdown: String, documentTitle: String) -> Bool {
        prepare(markdown, documentTitle: documentTitle).isEmpty
    }

    private static func stripFrontMatter(_ markdown: String) -> String {
        var lines = markdown.components(separatedBy: .newlines)
        guard lines.first == "---" else { return markdown }

        var endIndex: Int?
        for index in lines.indices.dropFirst() where lines[index] == "---" {
            endIndex = index
            break
        }

        guard let endIndex else { return markdown }
        lines.removeSubrange(0...endIndex)
        return lines.joined(separator: "\n")
    }

    private static func stripLeadingTitle(_ markdown: String, title: String) -> String {
        var lines = markdown.components(separatedBy: .newlines)

        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }

        guard let first = lines.first else { return markdown }
        let expected = "# \(title)"
        if first.trimmingCharacters(in: .whitespacesAndNewlines) == expected {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    private static func enrichTaskListMarkers(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(
                of: #"(?m)^(\s*)((?:[-*+])|(?:\d+[.)]))\s+\[[xX]\]\s+"#,
                with: "$1$2 ☑ ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?m)^(\s*)((?:[-*+])|(?:\d+[.)]))\s+\[ \]\s+"#,
                with: "$1$2 ☐ ",
                options: .regularExpression
            )
    }
}
