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

    /// Detects when a provider returned an *error message* instead of a real
    /// answer (e.g. an unauthenticated CLI printing "Failed to authenticate. API
    /// Error: 401"). Without this, such text passes the markdown check and gets
    /// stored as a bogus artifact. Returns the matched reason, or nil if clean.
    ///
    /// Tuned to avoid false positives on legitimate summaries that merely discuss
    /// auth: "strong" phrases reject anywhere; "weak" tokens only reject when the
    /// whole output is short (real error responses are short and terse).
    static func looksLikeError(_ text: String) -> String? {
        let lower = text.lowercased()
        let strong = [
            "invalid authentication", "failed to authenticate", "authentication credentials",
            "api error", "command not found", "could not find", "please run /login",
            "not logged in", "econnrefused", "connection refused", "rate limit exceeded",
            "credit balance is too low", "no such file or directory", "permission denied",
            "invalid api key", "missing api key", "401 unauthorized", "403 forbidden"
        ]
        for phrase in strong where lower.contains(phrase) {
            return "provider returned an error (\"\(phrase)\")"
        }
        // Weak tokens: only suspicious in a short, terse output.
        if text.count < 320 {
            let weak = ["401", "403", "429", "unauthorized", "forbidden", "error:", "traceback"]
            for token in weak where lower.contains(token) {
                return "provider returned a short error-like response (\"\(token)\")"
            }
        }
        return nil
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
