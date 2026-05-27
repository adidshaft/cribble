import Foundation

enum RichMarkdownBlock: Identifiable, Equatable {
    case markdown(id: String, text: String)
    case fencedCode(id: String, language: String?, code: String)

    var id: String {
        switch self {
        case .markdown(let id, _), .fencedCode(let id, _, _):
            id
        }
    }

    static func blocks(from markdown: String) -> [RichMarkdownBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [RichMarkdownBlock] = []
        var markdownLines: [String] = []
        var index = 0
        var blockIndex = 0

        func appendMarkdown() {
            let text = markdownLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            markdownLines.removeAll(keepingCapacity: true)
            guard !text.isEmpty else { return }
            blocks.append(.markdown(id: "markdown-\(blockIndex)", text: text))
            blockIndex += 1
        }

        while index < lines.count {
            let line = lines[index]
            if let openingFence = MarkdownFence(line: line) {
                appendMarkdown()
                index += 1

                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index]
                    if openingFence.closes(candidate) {
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }

                if index < lines.count {
                    index += 1
                }

                let language = openingFence.language?.isEmpty == false ? openingFence.language : nil
                blocks.append(
                    .fencedCode(
                        id: "fence-\(blockIndex)",
                        language: language,
                        code: codeLines.joined(separator: "\n")
                    )
                )
                blockIndex += 1
            } else {
                markdownLines.append(line)
                index += 1
            }
        }

        appendMarkdown()
        return blocks
    }
}

private struct MarkdownFence {
    let marker: Character
    let length: Int
    let language: String?

    init?(line: String) {
        let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmedLeading.first, first == "`" || first == "~" else { return nil }

        let markerCount = trimmedLeading.prefix(while: { $0 == first }).count
        guard markerCount >= 3 else { return nil }

        let remainder = String(trimmedLeading.dropFirst(markerCount)).trimmingCharacters(in: .whitespaces)
        marker = first
        length = markerCount
        language = remainder
            .split(whereSeparator: \.isWhitespace)
            .first
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "{}")).lowercased() }
    }

    func closes(_ line: String) -> Bool {
        let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
        let closingMarkerCount = trimmedLeading.prefix(while: { $0 == marker }).count
        guard closingMarkerCount >= length else { return false }
        let remainder = trimmedLeading.dropFirst(closingMarkerCount)
        return remainder.allSatisfy(\.isWhitespace)
    }
}
