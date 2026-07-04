import Foundation

/// A workspace file whose contents have already been read off disk, ready to be
/// folded into the model context. Kept separate from `TaggedFileToken` so the
/// assembler stays pure (no file IO) and fully unit-testable.
struct ResolvedFile: Equatable {
    let filename: String
    let content: String
}

/// Explicit HUD attachments can fail preflight before the assembler sees file
/// contents (security scope, encoding, file disappearance). Keep that state in
/// a pure value so the prompt can still carry a receipt for every tagged file.
struct ContextAttachment: Equatable {
    let filename: String
    let content: String?
    let digest: String?
    let unavailableReason: String?

    init(filename: String, content: String, digest: String? = nil) {
        self.filename = filename
        self.content = content
        self.digest = digest
        self.unavailableReason = nil
    }

    init(unavailable filename: String, reason: String) {
        self.filename = filename
        self.content = nil
        self.digest = nil
        self.unavailableReason = reason
    }
}

enum ContextSourceKind: String, Equatable {
    case currentNote = "current_note"
    case explicitAttachment = "explicit_attachment"
    case relatedNote = "related_note"
    case projectIntelligence = "project_intelligence"
}

enum ContextReceiptStatus: String, Equatable {
    case included
    case truncated
    case summarized
    case omitted
    case blockedNeedsSummary = "blocked_needs_summary"
    case unavailable
}

struct ContextReceipt: Equatable {
    struct Item: Equatable {
        let source: ContextSourceKind
        let filename: String
        let status: ContextReceiptStatus
        let originalCharacters: Int
        let includedCharacters: Int
        let reason: String?
    }

    var items: [Item]

    var hasBlockedExplicitAttachments: Bool {
        items.contains {
            $0.source == .explicitAttachment
                && ($0.status == .blockedNeedsSummary || $0.status == .unavailable)
        }
    }
}

struct ContextWarning: Equatable {
    enum Kind: String, Equatable {
        case contextBudgetExceeded = "context_budget_exceeded"
        case attachmentNeedsSummary = "attachment_needs_summary"
        case attachmentUnavailable = "attachment_unavailable"
    }

    let kind: Kind
    let filename: String?
    let message: String
}

struct ContextPacket: Equatable {
    let systemPrompt: String
    let receipt: ContextReceipt
    let warnings: [ContextWarning]
}

/// Builds the prompt handed to the model. Pure string assembly — no file IO, no
/// MLX — so the format is locked down by unit tests. Describes the four jobs the
/// assistant does inside Cribble (Q&A, wiki-linking, note synthesis, connection
/// explanations) and how to format each so Cribble can route the output safely.
enum ContextAssembler {
    /// Hard cap on how much of any single ambient file we inline, so a huge note
    /// can't blow the context window. Explicit attachments over this cap are
    /// blocked until a digest/summary is available.
    static let perFileCharacterBudget = 12_000

    /// Hard cap on the *combined* size of all inlined notes. Prevents an
    /// "Attach All Notes" on a large vault from producing a multi-megabyte prompt
    /// that blows the model's context window, balloons memory, or (on the CLI
    /// path, where the prompt rides in an env var) exceeds the OS `ARG_MAX` and
    /// fails the whole send with an opaque error. Context past the budget is
    /// represented in the receipt instead of disappearing.
    static let totalContextCharacterBudget = 60_000

    static func systemPrompt(
        modelName: String,
        currentNote: ResolvedFile?,
        files: [ResolvedFile],
        related: [ResolvedFile] = []
    ) -> String {
        contextPacket(
            modelName: modelName,
            currentNote: currentNote,
            files: files,
            related: related
        ).systemPrompt
    }

    static func contextPacket(
        modelName: String,
        currentNote: ResolvedFile?,
        files: [ResolvedFile],
        related: [ResolvedFile] = []
    ) -> ContextPacket {
        contextPacket(
            modelName: modelName,
            currentNote: currentNote,
            attachments: files.map { ContextAttachment(filename: $0.filename, content: $0.content) },
            related: related
        )
    }

    static func contextPacket(
        modelName: String,
        currentNote: ResolvedFile?,
        attachments: [ContextAttachment],
        related: [ResolvedFile] = [],
        intelligence: [ResolvedFile] = []
    ) -> ContextPacket {
        var sections: [String] = []
        var receiptItems: [ContextReceipt.Item] = []
        var warnings: [ContextWarning] = []

        sections.append(
            "You are the Cribble AI Assistant, a careful helper for a personal Markdown "
            + "knowledge base, running on \(modelName). Never invent files, links, or facts "
            + "that are not present in the notes provided below."
        )

        // Shared budget consumed in priority order: the current note first, then
        // user-tagged files, then semantic matches. Explicit attachments are
        // never silently omitted: if they cannot fit whole (or via digest), they
        // are represented as blocked/needs-summary in the receipt.
        var remaining = totalContextCharacterBudget

        func appendReceipt(
            source: ContextSourceKind,
            filename: String,
            status: ContextReceiptStatus,
            originalCharacters: Int,
            includedCharacters: Int,
            reason: String? = nil
        ) {
            receiptItems.append(ContextReceipt.Item(
                source: source,
                filename: filename,
                status: status,
                originalCharacters: originalCharacters,
                includedCharacters: includedCharacters,
                reason: reason
            ))
        }

        // Fits ambient context as much as the shared budget allows. Current and
        // related notes may still be truncated/omitted; only explicit attachments
        // require complete inclusion or a blocked receipt.
        func budgetedAmbient(_ file: ResolvedFile, source: ContextSourceKind) -> String? {
            let wasTruncatedByFileBudget = file.content.count > perFileCharacterBudget
            let capped = truncate(file.content)
            if capped.count <= remaining {
                remaining -= capped.count
                appendReceipt(
                    source: source,
                    filename: file.filename,
                    status: wasTruncatedByFileBudget ? .truncated : .included,
                    originalCharacters: file.content.count,
                    includedCharacters: capped.count,
                    reason: wasTruncatedByFileBudget ? "exceeds per-file context budget" : nil
                )
                return capped
            }
            guard remaining > 500 else { return nil }
            let included = remaining
            let slice = String(capped.prefix(remaining))
            remaining = 0
            appendReceipt(
                source: source,
                filename: file.filename,
                status: .truncated,
                originalCharacters: file.content.count,
                includedCharacters: included,
                reason: "exceeds remaining context budget"
            )
            return slice + "\n…[truncated]…"
        }

        if let currentNote {
            if let body = budgetedAmbient(currentNote, source: .currentNote) {
                sections.append(
                    "CURRENT NOTE — this is the note the user is reading right now. When they say "
                    + "\"this note\", \"here\", or \"this section\", they mean this file:\n"
                    + "--- BEGIN CURRENT NOTE: \(currentNote.filename) ---\n\(body)\n"
                    + "--- END CURRENT NOTE: \(currentNote.filename) ---"
                )
            } else {
                appendReceipt(
                    source: .currentNote,
                    filename: currentNote.filename,
                    status: .omitted,
                    originalCharacters: currentNote.content.count,
                    includedCharacters: 0,
                    reason: "context budget exhausted"
                )
                warnings.append(ContextWarning(
                    kind: .contextBudgetExceeded,
                    filename: currentNote.filename,
                    message: "\(currentNote.filename) was omitted because the context budget was exhausted."
                ))
            }
        }

        if !attachments.isEmpty {
            var rendered: [String] = []
            for attachment in attachments {
                if let reason = attachment.unavailableReason {
                    appendReceipt(
                        source: .explicitAttachment,
                        filename: attachment.filename,
                        status: .unavailable,
                        originalCharacters: 0,
                        includedCharacters: 0,
                        reason: reason
                    )
                    warnings.append(ContextWarning(
                        kind: .attachmentUnavailable,
                        filename: attachment.filename,
                        message: "\(attachment.filename) was attached explicitly but could not be read: \(reason)"
                    ))
                    continue
                }

                guard let content = attachment.content else {
                    appendReceipt(
                        source: .explicitAttachment,
                        filename: attachment.filename,
                        status: .unavailable,
                        originalCharacters: 0,
                        includedCharacters: 0,
                        reason: "missing attachment contents"
                    )
                    warnings.append(ContextWarning(
                        kind: .attachmentUnavailable,
                        filename: attachment.filename,
                        message: "\(attachment.filename) was attached explicitly but no contents were available."
                    ))
                    continue
                }

                if content.count <= perFileCharacterBudget && content.count <= remaining {
                    remaining -= content.count
                    appendReceipt(
                        source: .explicitAttachment,
                        filename: attachment.filename,
                        status: .included,
                        originalCharacters: content.count,
                        includedCharacters: content.count
                    )
                    rendered.append(
                        "--- BEGIN FILE: \(attachment.filename) ---\n\(content)\n--- END FILE: \(attachment.filename) ---"
                    )
                } else if let digest = attachment.digest,
                          digest.count <= perFileCharacterBudget,
                          digest.count <= remaining {
                    remaining -= digest.count
                    appendReceipt(
                        source: .explicitAttachment,
                        filename: attachment.filename,
                        status: .summarized,
                        originalCharacters: content.count,
                        includedCharacters: digest.count,
                        reason: "digest used because attachment exceeds inline budget"
                    )
                    rendered.append(
                        "--- BEGIN FILE SUMMARY: \(attachment.filename) ---\n\(digest)\n--- END FILE SUMMARY: \(attachment.filename) ---"
                    )
                } else {
                    let reason = content.count > perFileCharacterBudget
                        ? "exceeds per-file context budget; no digest available"
                        : "exceeds remaining context budget; no digest available"
                    appendReceipt(
                        source: .explicitAttachment,
                        filename: attachment.filename,
                        status: .blockedNeedsSummary,
                        originalCharacters: content.count,
                        includedCharacters: 0,
                        reason: reason
                    )
                    warnings.append(ContextWarning(
                        kind: .attachmentNeedsSummary,
                        filename: attachment.filename,
                        message: "\(attachment.filename) was attached explicitly but needs a summary before it can fit in context."
                    ))
                }
            }
            if !rendered.isEmpty {
                sections.append("REFERENCED NOTES — files the user tagged with @:")
                sections.append(contentsOf: rendered)
            }
        }

        // Curated project intelligence outranks loose semantic matches in the
        // shared budget: it's a generated map of the whole workspace, so it
        // answers "big picture" questions the related-note lane can't.
        if !intelligence.isEmpty {
            var rendered: [String] = []
            for file in intelligence {
                if let body = budgetedAmbient(file, source: .projectIntelligence) {
                    rendered.append(
                        "--- BEGIN INTELLIGENCE: \(file.filename) ---\n\(body)\n--- END INTELLIGENCE: \(file.filename) ---"
                    )
                } else {
                    appendReceipt(
                        source: .projectIntelligence,
                        filename: file.filename,
                        status: .omitted,
                        originalCharacters: file.content.count,
                        includedCharacters: 0,
                        reason: "context budget exhausted"
                    )
                    warnings.append(ContextWarning(
                        kind: .contextBudgetExceeded,
                        filename: file.filename,
                        message: "\(file.filename) was omitted because the context budget was exhausted."
                    ))
                }
            }
            if !rendered.isEmpty {
                sections.append(
                    "PROJECT INTELLIGENCE — generated, regularly refreshed reference documents "
                    + "about this workspace: an index of its structure and key notes, and "
                    + "possibly a contradiction report, glossary, or timeline. Prefer these for "
                    + "questions about the project as a whole (\"what is this workspace about?\", "
                    + "\"where do my notes disagree?\"), and cite specific notes from them rather "
                    + "than guessing:"
                )
                sections.append(contentsOf: rendered)
            }
        }

        if !related.isEmpty {
            var rendered: [String] = []
            for file in related {
                if let body = budgetedAmbient(file, source: .relatedNote) {
                    rendered.append(
                        "--- BEGIN RELATED: \(file.filename) ---\n\(body)\n--- END RELATED: \(file.filename) ---"
                    )
                } else {
                    appendReceipt(
                        source: .relatedNote,
                        filename: file.filename,
                        status: .omitted,
                        originalCharacters: file.content.count,
                        includedCharacters: 0,
                        reason: "context budget exhausted"
                    )
                    warnings.append(ContextWarning(
                        kind: .contextBudgetExceeded,
                        filename: file.filename,
                        message: "\(file.filename) was omitted because the context budget was exhausted."
                    ))
                }
            }
            if !rendered.isEmpty {
                sections.append("RELATED NOTES — automatically found in the workspace by semantic search; use them if relevant:")
                sections.append(contentsOf: rendered)
            }
        }

        if !warnings.isEmpty {
            sections.append(renderWarnings(warnings))
        }

        if !receiptItems.isEmpty {
            sections.append(renderReceipt(ContextReceipt(items: receiptItems)))
        }

        if currentNote == nil && attachments.isEmpty && related.isEmpty && intelligence.isEmpty {
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

        return ContextPacket(
            systemPrompt: sections.joined(separator: "\n\n"),
            receipt: ContextReceipt(items: receiptItems),
            warnings: warnings
        )
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
        let packet = contextPacket(
            modelName: modelName,
            currentNote: currentNote,
            files: files,
            related: related
        )
        return engineMessages(packet: packet, history: history)
    }

    static func engineMessages(packet: ContextPacket, history: [ChatMessage]) -> [EngineMessage] {
        var messages: [EngineMessage] = [
            EngineMessage(
                role: .system,
                content: packet.systemPrompt
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

    private static func renderWarnings(_ warnings: [ContextWarning]) -> String {
        let lines = warnings.map { warning in
            "- \(warning.kind.rawValue): \(warning.message)"
        }
        return """
        CONTEXT WARNINGS — these files were not fully available. Do not claim to have read blocked \
        or unavailable attachments; ask the user to narrow the file or provide a summary when needed.
        \(lines.joined(separator: "\n"))
        """
    }

    private static func renderReceipt(_ receipt: ContextReceipt) -> String {
        let lines = receipt.items.map { item in
            let reason = item.reason.map { " reason=\"\($0)\"" } ?? ""
            return "- \(item.source.rawValue) \(item.filename): \(item.status.rawValue) "
                + "original_chars=\(item.originalCharacters) included_chars=\(item.includedCharacters)\(reason)"
        }
        return """
        CONTEXT RECEIPT — every selected context source and what was sent to the model:
        \(lines.joined(separator: "\n"))
        """
    }
}
