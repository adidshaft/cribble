import Foundation

/// Validates SLM output before it is stored as an artifact. SLMs produce
/// unreliable output (design plan §7.4); the two highest-value checks are cheap
/// and deterministic: (1) referenced file paths must actually exist, and (2)
/// Mermaid must be structurally sane. Failing validation lets `JobRunner` retry
/// with a correction prompt or flag the artifact as unvalidated.
enum OutputValidator {

    struct Result: Sendable, Equatable {
        var isValid: Bool
        var issues: [String]
    }

    /// Cross-checks any `path/like/this.swift` tokens in Markdown against the set
    /// of known project paths. Unknown paths are reported (likely hallucinations).
    static func validateMarkdown(_ markdown: String, knownPaths: Set<String>) -> Result {
        var issues: [String] = []
        if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Result(isValid: false, issues: ["empty output"])
        }
        // Heuristic path token: contains a slash and a file-ish extension.
        let pattern = #"[A-Za-z0-9_./-]+\.(swift|md|js|ts|py|go|rs|json|yaml|yml)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Result(isValid: true, issues: [])
        }
        let ns = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        var unknown: Set<String> = []
        for match in matches {
            let token = ns.substring(with: match.range)
            // Only flag multi-segment paths; bare "file.swift" mentions are fine.
            guard token.contains("/") else { continue }
            let normalized = token.hasPrefix("./") ? String(token.dropFirst(2)) : token
            if !knownPaths.contains(normalized) && !knownPaths.contains(where: { $0.hasSuffix(normalized) }) {
                unknown.insert(token)
            }
        }
        if !unknown.isEmpty {
            issues.append("references unknown paths: \(unknown.sorted().joined(separator: ", "))")
        }
        return Result(isValid: issues.isEmpty, issues: issues)
    }

    /// Structural Mermaid sanity check (not a full parser): must start with a
    /// known diagram keyword and have balanced brackets. A headless WKWebView
    /// render check (plan §7.4) is a later, heavier upgrade.
    static func validateMermaid(_ source: String) -> Result {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(isValid: false, issues: ["empty diagram"]) }

        let keywords = ["graph ", "flowchart ", "sequenceDiagram", "classDiagram", "stateDiagram", "erDiagram", "gantt", "pie", "mindmap", "journey"]
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? ""
        guard keywords.contains(where: { firstLine.hasPrefix($0) }) else {
            return Result(isValid: false, issues: ["missing diagram type header (got \"\(firstLine.prefix(20))\")"])
        }
        var issues: [String] = []
        if unbalanced(trimmed, open: "[", close: "]") { issues.append("unbalanced []") }
        if unbalanced(trimmed, open: "(", close: ")") { issues.append("unbalanced ()") }
        if unbalanced(trimmed, open: "{", close: "}") { issues.append("unbalanced {}") }
        return Result(isValid: issues.isEmpty, issues: issues)
    }

    private static func unbalanced(_ s: String, open: Character, close: Character) -> Bool {
        var depth = 0
        for c in s {
            if c == open { depth += 1 }
            else if c == close { depth -= 1 }
            if depth < 0 { return true }
        }
        return depth != 0
    }
}
