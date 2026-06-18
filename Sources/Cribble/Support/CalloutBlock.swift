import Foundation

struct CalloutBlock: Equatable, Identifiable {
    enum Fold: Equatable {
        case none
        case expanded
        case collapsed
    }

    let id: String
    let type: String
    let title: String
    let fold: Fold
    let bodyMarkdown: String
    let originalMarkdown: String

    static func parse(id: String, blockquoteLines: [String]) -> CalloutBlock? {
        guard let firstLine = blockquoteLines.first else { return nil }
        let first = stripBlockquoteMarker(firstLine)
        guard let parsed = parseHeader(first) else { return nil }
        let bodyLines = blockquoteLines.dropFirst().map(stripBlockquoteMarker)
        return CalloutBlock(
            id: id,
            type: parsed.type,
            title: parsed.title,
            fold: parsed.fold,
            bodyMarkdown: bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines),
            originalMarkdown: blockquoteLines.joined(separator: "\n")
        )
    }

    private static func parseHeader(_ line: String) -> (type: String, title: String, fold: Fold)? {
        guard let regex = try? NSRegularExpression(pattern: #"^\[!(?<type>[\w-]+)\](?<fold>[+-]?)\s*(?<title>.*)$"#) else {
            return nil
        }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange),
              let typeRange = Range(match.range(withName: "type"), in: line) else {
            return nil
        }

        let rawType = String(line[typeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawType.isEmpty else { return nil }
        let type = rawType.lowercased()

        let fold: Fold
        if let foldRange = Range(match.range(withName: "fold"), in: line) {
            switch String(line[foldRange]) {
            case "+": fold = .expanded
            case "-": fold = .collapsed
            default: fold = .none
            }
        } else {
            fold = .none
        }

        let title: String
        if let titleRange = Range(match.range(withName: "title"), in: line) {
            let customTitle = String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            title = customTitle.isEmpty ? type.capitalized : customTitle
        } else {
            title = type.capitalized
        }

        return (type, title, fold)
    }

    private static func stripBlockquoteMarker(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return line }
        trimmed.removeFirst()
        if trimmed.first == " " {
            trimmed.removeFirst()
        }
        return trimmed
    }
}
