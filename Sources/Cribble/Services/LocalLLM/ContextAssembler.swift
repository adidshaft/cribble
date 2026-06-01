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

    /// Hard cap on the *combined* size of all inlined notes. Prevents an
    /// "Attach All Notes" on a large vault from producing a multi-megabyte prompt
    /// that blows the model's context window, balloons memory, or (on the CLI
    /// path, where the prompt rides in an env var) exceeds the OS `ARG_MAX` and
    /// fails the whole send with an opaque error. Files past the budget are
    /// dropped and the model is told how many were omitted.
    static let totalContextCharacterBudget = 60_000

    static func systemPrompt(
        modelName: String,
        currentNote: ResolvedFile?,
        files: [ResolvedFile],
        related: [ResolvedFile] = []
    ) -> String {
        var sections: [String] = []
        sections.append(
            "You are the Cribble AI Assistant, a careful helper for a personal Markdown "
            + "knowledge base, running on \(modelName). Never invent files, links, or facts "
            + "that are not present in the notes provided below."
        )

        // Shared budget consumed in priority order: the current note first, then
        // user-tagged files, then semantic matches — so the least important
        // context (loose related notes) is the first to be dropped when space
        // runs out.
        var remaining = totalContextCharacterBudget
        var omittedNotes = 0

        // Fits as much of `content` as the shared budget allows (after the
        // per-file cap), or nil when there's no meaningful room left.
        func budgeted(_ content: String) -> String? {
            let capped = truncate(content)
            if capped.count <= remaining {
                remaining -= capped.count
                return capped
            }
            guard remaining > 500 else { return nil }
            let slice = String(capped.prefix(remaining))
            remaining = 0
            return slice + "\n…[truncated]…"
        }

        if let currentNote {
            if let body = budgeted(currentNote.content) {
                sections.append(
                    "CURRENT NOTE — this is the note the user is reading right now. When they say "
                    + "\"this note\", \"here\", or \"this section\", they mean this file:\n"
                    + "--- BEGIN CURRENT NOTE: \(currentNote.filename) ---\n\(body)\n"
                    + "--- END CURRENT NOTE: \(currentNote.filename) ---"
                )
            } else {
                omittedNotes += 1
            }
        }

        if !files.isEmpty {
            var rendered: [String] = []
            for file in files {
                if let body = budgeted(file.content) {
                    rendered.append(
                        "--- BEGIN FILE: \(file.filename) ---\n\(body)\n--- END FILE: \(file.filename) ---"
                    )
                } else {
                    omittedNotes += 1
                }
            }
            if !rendered.isEmpty {
                sections.append("REFERENCED NOTES — files the user tagged with @:")
                sections.append(contentsOf: rendered)
            }
        }

        if !related.isEmpty {
            var rendered: [String] = []
            for file in related {
                if let body = budgeted(file.content) {
                    rendered.append(
                        "--- BEGIN RELATED: \(file.filename) ---\n\(body)\n--- END RELATED: \(file.filename) ---"
                    )
                } else {
                    omittedNotes += 1
                }
            }
            if !rendered.isEmpty {
                sections.append("RELATED NOTES — automatically found in the workspace by semantic search; use them if relevant:")
                sections.append(contentsOf: rendered)
            }
        }

        if omittedNotes > 0 {
            sections.append(
                "NOTE: \(omittedNotes) attached file(s) were omitted to keep within the context limit. "
                + "Answer from the notes shown above, and ask the user to narrow to specific files if needed."
            )
        }

        if currentNote == nil && files.isEmpty && related.isEmpty {
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
        files: [ResolvedFile],
        related: [ResolvedFile] = []
    ) -> [EngineMessage] {
        var messages: [EngineMessage] = [
            EngineMessage(
                role: .system,
                content: systemPrompt(modelName: modelName, currentNote: currentNote, files: files, related: related)
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
