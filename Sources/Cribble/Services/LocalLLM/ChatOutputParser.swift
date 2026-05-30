import Foundation

/// Classifies a completed assistant turn into an actionable proposal. The HUD
/// never writes to disk itself — it routes these through the existing safe
/// preview/apply pipeline (`MarkdownLibraryStore.pendingDiff` /
/// `presentNewNoteProposal`).
enum ChatActionableOutput: Equatable {
    /// Plain conversational answer — nothing to apply.
    case none
    /// A unified diff the model proposed against existing files.
    case diff(UnifiedDiff)
    /// A brand-new file proposal from a `CREATE: filename.md` fenced block.
    case create(fileName: String, content: String)
}

enum ChatOutputParser {
    /// Inspects assistant output and extracts a `CREATE:` block or a unified
    /// diff if present. `CREATE` takes precedence because a creation block is an
    /// explicit, unambiguous instruction.
    static func parse(_ text: String) -> ChatActionableOutput {
        if let create = parseCreateBlock(text) {
            return .create(fileName: create.fileName, content: create.content)
        }
        let diff = UnifiedDiffParser.parse(UnifiedDiffParser.extractDiffText(from: text))
        if !diff.isEmpty {
            return .diff(diff)
        }
        return .none
    }

    /// Finds the first fenced block whose info string starts with `CREATE:`,
    /// e.g. ```` ```CREATE: ideas.md ````. Tolerates an optional space after the
    /// backticks and case-insensitive `create`.
    static func parseCreateBlock(_ text: String) -> (fileName: String, content: String)? {
        let lines = text.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if let fileName = createFenceFileName(trimmed) {
                var content: [String] = []
                var cursor = index + 1
                var foundClose = false
                while cursor < lines.count {
                    if lines[cursor].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        foundClose = true
                        break
                    }
                    content.append(lines[cursor])
                    cursor += 1
                }
                // Only treat it as a creation when the block actually closed and
                // carried content; otherwise fall through to other parsing.
                if foundClose, !content.isEmpty {
                    let body = content.joined(separator: "\n")
                    return (fileName, body.hasSuffix("\n") ? body : body + "\n")
                }
            }
            index += 1
        }
        return nil
    }

    /// Returns the filename if `line` opens a `CREATE:` fence, else nil.
    private static func createFenceFileName(_ line: String) -> String? {
        guard line.hasPrefix("```") else { return nil }
        let info = line.drop(while: { $0 == "`" }).trimmingCharacters(in: .whitespaces)
        guard info.lowercased().hasPrefix("create:") else { return nil }
        let name = info.dropFirst("create:".count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
