import Foundation

enum MarkdownDisplayPreprocessor {
    static func prepare(_ markdown: String, documentTitle: String) -> String {
        let withoutFrontMatter = stripFrontMatter(markdown)
        let withoutDuplicateTitle = stripLeadingTitle(withoutFrontMatter, title: documentTitle)
        let withFootnotes = renderFootnotes(withoutDuplicateTitle)
        // NOTE: task-list markers (`- [ ]` / `- [x]`) are intentionally left
        // untouched here. The reader detects them downstream and renders them as
        // interactive checkboxes (`TaskListView`); rewriting them to ☐/☑ glyphs
        // would both look worse (bullet + box) and hide them from that detector.
        return withFootnotes
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

    private static func renderFootnotes(_ markdown: String) -> String {
        let definitionRegex = try! NSRegularExpression(pattern: #"(?m)^\[\^([^\]]+)\]:\s*(.+)$"#, options: [])
        
        var definitions: [String: String] = [:]
        let nsString = markdown as NSString
        let matches = definitionRegex.matches(in: markdown, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            if match.numberOfRanges >= 3 {
                let id = nsString.substring(with: match.range(at: 1))
                let text = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                definitions[id] = text
            }
        }
        
        let cleanMarkdown = definitionRegex.stringByReplacingMatches(in: markdown, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "")
        
        let referenceRegex = try! NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#, options: [])
        
        var referencedIds: [String] = []
        var idToNumber: [String: Int] = [:]
        
        let refMatches = referenceRegex.matches(in: cleanMarkdown, options: [], range: NSRange(location: 0, length: (cleanMarkdown as NSString).length))
        
        for match in refMatches {
            if match.numberOfRanges >= 2 {
                let id = (cleanMarkdown as NSString).substring(with: match.range(at: 1))
                if definitions[id] != nil {
                    if idToNumber[id] == nil {
                        referencedIds.append(id)
                        idToNumber[id] = referencedIds.count
                    }
                }
            }
        }
        
        if referencedIds.isEmpty {
            return markdown
        }
        
        var resultString = cleanMarkdown as NSString
        for match in refMatches.reversed() {
            if match.numberOfRanges >= 2 {
                let id = resultString.substring(with: match.range(at: 1))
                if let number = idToNumber[id] {
                    let replacement = superscriptString(for: number)
                    resultString = resultString.replacingCharacters(in: match.range, with: replacement) as NSString
                }
            }
        }
        
        var finalMarkdown = resultString as String
        finalMarkdown += "\n\n***\n\n**Footnotes**\n"
        for id in referencedIds {
            if let number = idToNumber[id], let text = definitions[id] {
                let superStr = superscriptString(for: number)
                finalMarkdown += "\(number). \(superStr) \(text)\n"
            }
        }
        
        return finalMarkdown
    }

    private static func superscriptString(for number: Int) -> String {
        let digits = String(number)
        return digits.map { char -> String in
            switch char {
            case "0": return "⁰"
            case "1": return "¹"
            case "2": return "²"
            case "3": return "³"
            case "4": return "⁴"
            case "5": return "⁵"
            case "6": return "⁶"
            case "7": return "⁷"
            case "8": return "⁸"
            case "9": return "⁹"
            default: return String(char)
            }
        }.joined()
    }
}
