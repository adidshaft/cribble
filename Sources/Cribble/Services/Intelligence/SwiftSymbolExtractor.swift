import Foundation

/// A coarse code symbol pulled from a source file.
struct SwiftSymbol: Sendable, Equatable {
    enum Kind: String, Sendable {
        case type        // class / struct / enum / actor
        case protocolType = "protocol"
        case function
        case extensionDecl = "extension"
        case importDecl = "import"
        case property
    }

    let name: String
    let kind: Kind
    /// 1-based line where the declaration begins / ends. For single-line
    /// declarations (imports, properties) start == end.
    let startLine: Int
    let endLine: Int
    /// The trimmed declaration line(s), for prompt context.
    let signature: String?
}

/// Regex-based Swift symbol extraction. This is deliberately *imprecise*: per the
/// design plan (§11.2), summarization prompts don't need a perfect AST — they need
/// enough structure to anchor a summary and to seed a dependency graph. A real
/// SwiftSyntax/IndexStore parser is a later upgrade for the call-graph ground
/// truth; this keeps Phase 1 dependency-free.
///
/// Limitations (accepted): brace matching is naive (counts `{`/`}` and is fooled
/// by braces inside strings/comments), nested types are flattened, and only
/// top-level `import`s and declaration keywords are recognized. Good enough to
/// list "what's in this file" without parsing the language.
enum SwiftSymbolExtractor {

    private static let typeKeywords: Set<String> = ["class", "struct", "enum", "actor"]

    static func extract(from source: String) -> [SwiftSymbol] {
        let lines = source.components(separatedBy: .newlines)
        var symbols: [SwiftSymbol] = []

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lineNumber = index + 1
            guard let token = firstDeclarationToken(in: line) else { continue }

            switch token {
            case "import":
                if let name = line.split(separator: " ").dropFirst().first {
                    symbols.append(SwiftSymbol(
                        name: String(name), kind: .importDecl,
                        startLine: lineNumber, endLine: lineNumber, signature: line
                    ))
                }
            case "func":
                if let name = identifier(after: "func", in: line) {
                    let endLine = matchingBraceLine(from: index, in: lines) ?? lineNumber
                    symbols.append(SwiftSymbol(
                        name: name, kind: .function,
                        startLine: lineNumber, endLine: endLine, signature: line
                    ))
                }
            case "protocol":
                if let name = identifier(after: "protocol", in: line) {
                    let endLine = matchingBraceLine(from: index, in: lines) ?? lineNumber
                    symbols.append(SwiftSymbol(
                        name: name, kind: .protocolType,
                        startLine: lineNumber, endLine: endLine, signature: line
                    ))
                }
            case "extension":
                if let name = identifier(after: "extension", in: line) {
                    let endLine = matchingBraceLine(from: index, in: lines) ?? lineNumber
                    symbols.append(SwiftSymbol(
                        name: name, kind: .extensionDecl,
                        startLine: lineNumber, endLine: endLine, signature: line
                    ))
                }
            default: // a type keyword
                if let name = identifier(after: token, in: line) {
                    let endLine = matchingBraceLine(from: index, in: lines) ?? lineNumber
                    symbols.append(SwiftSymbol(
                        name: name, kind: .type,
                        startLine: lineNumber, endLine: endLine, signature: line
                    ))
                }
            }
        }
        return symbols
    }

    /// The leading declaration keyword on a line, if any. We require the keyword
    /// to be a whole word at a word boundary so `function`/`structure` don't match.
    private static func firstDeclarationToken(in line: String) -> String? {
        // Strip common access/modifier prefixes so "public final class Foo" works.
        var words = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let modifiers: Set<String> = ["public", "private", "internal", "fileprivate", "open",
                                      "final", "static", "class", "indirect", "@objc",
                                      "override", "convenience", "required", "mutating",
                                      "nonisolated", "lazy", "weak", "unowned", "dynamic"]
        // Special-case: leading `class` is a modifier for `class func`, but a
        // declaration for `class Foo`. Handle by peeking the next word.
        while let first = words.first {
            if first == "class" {
                if words.count > 1, typeKeywords.contains(words[1]) || words[1] == "func" || words[1] == "var" || words[1] == "let" {
                    words.removeFirst() // `class` acts as a modifier here
                    continue
                }
                return "class"
            }
            if modifiers.contains(first) { words.removeFirst(); continue }
            break
        }
        guard let head = words.first else { return nil }
        if head == "import" || head == "func" || head == "protocol" || head == "extension" || typeKeywords.contains(head) {
            return head
        }
        return nil
    }

    /// The identifier immediately following `keyword` on the line, stripped of
    /// generic params, inheritance, and signature punctuation.
    private static func identifier(after keyword: String, in line: String) -> String? {
        guard let range = line.range(of: keyword + " ") else { return nil }
        let rest = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        // Cut at the first delimiter that can't be part of a name.
        let delimiters = CharacterSet(charactersIn: " <(:{").union(.whitespaces)
        let name = rest.unicodeScalars.prefix { !delimiters.contains($0) }
        let result = String(String.UnicodeScalarView(name))
        return result.isEmpty ? nil : result
    }

    /// Walks forward counting braces to find the line that closes the block
    /// opened on/after `startIndex`. Returns nil if no opening brace is found on
    /// the start line's logical declaration (e.g. a protocol requirement `func`).
    private static func matchingBraceLine(from startIndex: Int, in lines: [String]) -> Int? {
        var depth = 0
        var sawOpen = false
        for i in startIndex..<lines.count {
            for char in lines[i] {
                if char == "{" { depth += 1; sawOpen = true }
                else if char == "}" {
                    depth -= 1
                    if sawOpen && depth == 0 { return i + 1 }
                }
            }
            // A declaration with no brace by the time we hit a blank separator is
            // treated as bodyless (protocol requirement / abstract).
            if !sawOpen && i > startIndex && lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                return nil
            }
        }
        return sawOpen ? lines.count : nil
    }
}
