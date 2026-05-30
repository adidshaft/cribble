import Foundation

/// A workspace file whose contents have already been read off disk, ready to be
/// folded into the model context. Kept separate from `TaggedFileToken` so the
/// assembler stays pure (no file IO) and fully unit-testable.
struct ResolvedFile: Equatable {
    let filename: String
    let content: String
}

/// Builds the prompt handed to the on-device model. Pure string assembly — no
/// file IO, no MLX — so the prompt format is locked down by unit tests.
enum ContextAssembler {
    /// Hard cap on how much of any single file we inline, so a huge note can't
    /// blow the context window. Trimmed files are marked as truncated.
    static let perFileCharacterBudget = 12_000

    static func systemPrompt(modelName: String, files: [ResolvedFile]) -> String {
        var sections: [String] = []
        sections.append(
            "You are the Cribble AI Assistant, running locally on \(modelName). "
            + "You help with a personal Markdown knowledge base. Be concise and accurate, "
            + "and never invent files or facts that aren't in the provided notes."
        )

        if files.isEmpty {
            sections.append("The user has not attached any notes to this message.")
        } else {
            sections.append("Below is the content of the referenced notes from the user's workspace:")
            for file in files {
                let body = truncate(file.content)
                sections.append(
                    "--- BEGIN FILE: \(file.filename) ---\n\(body)\n--- END FILE: \(file.filename) ---"
                )
            }
        }

        sections.append(
            """
            Output rules:
            - If the user asks to modify or link existing files, reply ONLY with a standard \
            Unified Diff. Start each file with "--- a/<path>" and "+++ b/<path>" headers \
            and use "@@" hunks. Do not wrap the diff in Markdown fences or add commentary.
            - If the user asks to organize, structure, or create a NEW file, output the \
            proposed Markdown inside a single fenced block whose info string is \
            "CREATE: filename.md" (for example: ```CREATE: ideas.md```).
            - For any other question, answer normally in Markdown.
            """
        )

        return sections.joined(separator: "\n\n")
    }

    /// Full message array for a send: a system turn carrying the file context
    /// and rules, followed by the running conversation.
    static func engineMessages(
        modelName: String,
        history: [ChatMessage],
        files: [ResolvedFile]
    ) -> [EngineMessage] {
        var messages: [EngineMessage] = [
            EngineMessage(role: .system, content: systemPrompt(modelName: modelName, files: files))
        ]
        for message in history {
            // Skip empty placeholder turns (e.g. the streaming assistant bubble
            // before any tokens arrive).
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let role: EngineMessage.Role = message.role == .user ? .user : .assistant
            messages.append(EngineMessage(role: role, content: message.text))
        }
        return messages
    }

    private static func truncate(_ content: String) -> String {
        guard content.count > perFileCharacterBudget else { return content }
        let cutoff = content.index(content.startIndex, offsetBy: perFileCharacterBudget)
        return String(content[..<cutoff]) + "\n…[truncated]…"
    }
}
