import Foundation

/// A workspace file whose contents have already been read off disk, ready to be
/// folded into the model context. Kept separate from `TaggedFileToken` so the
/// assembler stays pure (no file IO) and fully unit-testable.
struct ResolvedFile: Equatable {
    let filename: String
    let content: String
}

/// Builds the prompt handed to the model. Pure string assembly — no file IO, no
/// MLX — so the format is locked down by unit tests. Describes the four jobs the
/// assistant does inside Cribble (Q&A, wiki-linking, note synthesis, connection
/// explanations) and how to format each so Cribble can route the output safely.
enum ContextAssembler {
    /// Hard cap on how much of any single file we inline, so a huge note can't
    /// blow the context window. Trimmed files are marked as truncated.
    static let perFileCharacterBudget = 12_000

    static func systemPrompt(
        modelName: String,
        currentNote: ResolvedFile?,
        files: [ResolvedFile]
    ) -> String {
        var sections: [String] = []
        sections.append(
            "You are the Cribble AI Assistant, a careful helper for a personal Markdown "
            + "knowledge base, running on \(modelName). Never invent files, links, or facts "
            + "that are not present in the notes provided below."
        )

        if let currentNote {
            sections.append(
                "CURRENT NOTE — this is the note the user is reading right now. When they say "
                + "\"this note\", \"here\", or \"this section\", they mean this file:\n"
                + "--- BEGIN CURRENT NOTE: \(currentNote.filename) ---\n\(truncate(currentNote.content))\n"
                + "--- END CURRENT NOTE: \(currentNote.filename) ---"
            )
        }

        if !files.isEmpty {
            sections.append("REFERENCED NOTES — files the user tagged with @:")
            for file in files {
                sections.append(
                    "--- BEGIN FILE: \(file.filename) ---\n\(truncate(file.content))\n--- END FILE: \(file.filename) ---"
                )
            }
        }

        if currentNote == nil && files.isEmpty {
            sections.append("No notes are attached to this message yet.")
        }

        sections.append(
            """
            You can do four things. Pick the one that matches the user's request and format \
            your reply EXACTLY as described:

            1. ANSWER A QUESTION about the current or referenced notes (explanations, summaries, \
            "what are the setup steps here?"). Reply in normal Markdown prose. This is the default.

            2. AUTO-LINK NOTES: when the user asks to link, connect, or cross-reference the tagged \
            notes, insert sparse, high-confidence `[[Wiki Links]]` where one note clearly refers to \
            another. Reply with ONLY a standard Unified Diff — each file starting with `--- a/<path>` \
            and `+++ b/<path>` and using `@@` hunks. No prose, no Markdown fences around it.

            3. CREATE A NEW NOTE: when the user asks to synthesize, index, summarize-into-a-file, or \
            generate a dashboard/overview, output the new note's full Markdown inside ONE fenced block \
            whose info string is `CREATE: filename.md` (for example: ```CREATE: bug-status-index.md```).

            4. EXPLAIN A CONNECTION between two notes: reply with a single concise paragraph describing \
            the conceptual bridge between them.

            Default to plain answers (mode 1) unless the user clearly asks to link (2), create a file (3), \
            or explain a connection (4).
            """
        )

        return sections.joined(separator: "\n\n")
    }

    /// Full message array for a send: a system turn carrying the context and
    /// rules, then the running conversation.
    static func engineMessages(
        modelName: String,
        history: [ChatMessage],
        currentNote: ResolvedFile?,
        files: [ResolvedFile]
    ) -> [EngineMessage] {
        var messages: [EngineMessage] = [
            EngineMessage(
                role: .system,
                content: systemPrompt(modelName: modelName, currentNote: currentNote, files: files)
            )
        ]
        for message in history {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let role: EngineMessage.Role = message.role == .user ? .user : .assistant
            messages.append(EngineMessage(role: role, content: message.text))
        }
        return messages
    }

    /// Messages for Pathfinder: explain the conceptual bridge between two notes
    /// in a single concise paragraph (the assistant's fourth job).
    static func connectionMessages(
        modelName: String,
        source: ResolvedFile,
        target: ResolvedFile
    ) -> [EngineMessage] {
        let system = """
        You are the Cribble AI Assistant, running on \(modelName). Explain how two Markdown \
        notes are conceptually connected, using ONLY the content provided. Reply with a single \
        concise paragraph (at most ~90 words). Do not invent facts, do not output a list, and do \
        not write any files.

        --- BEGIN NOTE A: \(source.filename) ---
        \(truncate(source.content))
        --- END NOTE A: \(source.filename) ---

        --- BEGIN NOTE B: \(target.filename) ---
        \(truncate(target.content))
        --- END NOTE B: \(target.filename) ---
        """
        return [
            EngineMessage(role: .system, content: system),
            EngineMessage(
                role: .user,
                content: "Explain the conceptual bridge between \"\(source.filename)\" and \"\(target.filename)\"."
            )
        ]
    }

    private static func truncate(_ content: String) -> String {
        guard content.count > perFileCharacterBudget else { return content }
        let cutoff = content.index(content.startIndex, offsetBy: perFileCharacterBudget)
        return String(content[..<cutoff]) + "\n…[truncated]…"
    }
}
