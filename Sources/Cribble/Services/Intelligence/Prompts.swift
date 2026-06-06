import Foundation

/// Central home for every SLM prompt the intelligence pipeline issues. Keeping
/// them in one pure, dependency-free enum makes the wording reviewable and locks
/// the format down (design plan §11.3). Every prompt follows the same shape:
/// a strict system instruction + bounded input + an explicit output format, and
/// every one forbids inventing files or symbols (the anti-hallucination rule).
enum Prompts {
    private static let antiHallucination =
        "Never invent file paths, type names, or functions that are not present in the input. "
        + "If you are unsure, say so rather than guessing."

    static func fileSummary(path: String, source: String) -> [EngineMessage] {
        [
            EngineMessage(role: .system, content: """
            You are a code analysis assistant for a developer who did not hand-write all of \
            this code and needs to recover its intent. \(antiHallucination) Summarize the file \
            in concise Markdown: purpose, key types/functions, notable fallbacks or error \
            handling, and anything surprising. Output only the Markdown summary.
            """),
            EngineMessage(role: .user, content: "File: \(path)\n\n```\n\(source)\n```")
        ]
    }

    static func fileAnalysisBundle(path: String, language: String?, source: String) -> [EngineMessage] {
        [
            EngineMessage(role: .system, content: """
            You are analyzing one project file for Cribble Intelligence. \(antiHallucination) \
            Produce exactly three Markdown sections, in this order:

            ## Summary
            Purpose, key types/functions, and notable behavior in a concise paragraph or bullets.

            ## Fallbacks
            Each fallback, default value, catch/recover, retry, or silent-failure path with the \
            relevant symbol. If none are visible, write "No explicit fallbacks found."

            ## I/O Behavior
            External inputs/outputs: network/API calls, file/disk reads or writes, environment or \
            config reads, user input, and side effects, each with the relevant symbol. If none are \
            visible, write "No external I/O found."

            Output only Markdown. Do not wrap the answer in a code fence.
            """),
            EngineMessage(role: .user, content: "File: \(path)\nLanguage: \(language ?? "unknown")\n\n```\n\(source)\n```")
        ]
    }

    static func projectIndex(projectName: String, summaries: [(path: String, summary: String)]) -> [EngineMessage] {
        let body = summaries
            .map { "### \($0.path)\n\($0.summary)" }
            .joined(separator: "\n\n")
        return [
            EngineMessage(role: .system, content: """
            You are assembling a project index from per-file summaries. \(antiHallucination) \
            Produce a single Markdown document titled "# \(projectName) — Project Index" with: \
            a one-paragraph overview, a "## Components" section grouping related files, and a \
            "## Entry points" section. Reference only the files listed below. Output only Markdown.
            """),
            EngineMessage(role: .user, content: body)
        ]
    }

    static func diffSummary(diff: String) -> [EngineMessage] {
        [
            EngineMessage(role: .system, content: """
            You explain code changes to the author, who generated much of this code via AI and \
            needs to understand what actually changed. \(antiHallucination) Given a unified diff, \
            write a concise Markdown summary: what changed, why it likely changed, and any risk \
            or behavior change. Group by file. Output only Markdown.
            """),
            EngineMessage(role: .user, content: "```diff\n\(diff)\n```")
        ]
    }

    static func commitSummary(subject: String, diff: String) -> [EngineMessage] {
        [
            EngineMessage(role: .system, content: """
            Summarize a single git commit for someone reviewing project history. \
            \(antiHallucination) One short Markdown paragraph: what the commit does and its \
            effect. Output only Markdown.
            """),
            EngineMessage(role: .user, content: "Subject: \(subject)\n\n```diff\n\(diff)\n```")
        ]
    }

    static func fallbackAudit(path: String, source: String) -> [EngineMessage] {
        [
            EngineMessage(role: .system, content: """
            You are auditing error handling. \(antiHallucination) For the file below, list each \
            fallback, default value, catch/recover, retry, or silent-failure path you can see, \
            as a Markdown bullet list with the relevant symbol name. If there are none, say \
            "No explicit fallbacks found." Output only Markdown.
            """),
            EngineMessage(role: .user, content: "File: \(path)\n\n```\n\(source)\n```")
        ]
    }

    static func ioBehavior(path: String, source: String) -> [EngineMessage] {
        [
            EngineMessage(role: .system, content: """
            You are mapping a file's external behavior. \(antiHallucination) For the file below, \
            list its inputs and outputs as Markdown: network/API calls, file or disk reads/writes, \
            environment/config it reads, user input it consumes, and side effects it produces, each \
            with the relevant symbol. If there are none, say "No external I/O found." Output only Markdown.
            """),
            EngineMessage(role: .user, content: "File: \(path)\n\n```\n\(source)\n```")
        ]
    }

    static func architectureNarration(graphMermaid: String, summaries: [(path: String, summary: String)]) -> [EngineMessage] {
        let context = summaries.prefix(40)
            .map { "- \($0.path): \($0.summary.prefix(160))" }
            .joined(separator: "\n")
        return [
            EngineMessage(role: .system, content: """
            You write a high-level architecture overview. \(antiHallucination) You are given a \
            validated dependency graph (Mermaid) and short file summaries. Produce a Markdown \
            document: "# Architecture" with a 2-3 sentence overview, then "## Modules" describing \
            the main groupings and how they depend on each other. Base every statement on the \
            provided graph and summaries only. Output only Markdown (do not repeat the diagram).
            """),
            EngineMessage(role: .user, content: "Dependency graph:\n```mermaid\n\(graphMermaid)\n```\n\nFile summaries:\n\(context)")
        ]
    }

    static func connectionResearch(summaries: [(path: String, summary: String)]) -> [EngineMessage] {
        let context = summaries.prefix(80)
            .map { "### \($0.path)\n\($0.summary.prefix(700))" }
            .joined(separator: "\n\n")
        return [
            EngineMessage(role: .system, content: """
            You are Cribble's local autoresearch assistant. \(antiHallucination) Find useful \
            conceptual connections between the listed files. Prefer connections that would help \
            a reader understand the project or decide where a `[[wiki link]]` might belong.

            Output Markdown only:
            # Suggested Connections
            - `from/path.ext` => `to/path.ext`: one sentence reason grounded in the summaries.

            Include at most 12 suggestions. Use only file paths present below.
            """),
            EngineMessage(role: .user, content: context)
        ]
    }

    static let summarySchema = JSONSchemaHint(
        name: "markdown_summary",
        example: "# Title\n\nA concise paragraph describing purpose and key behavior."
    )
}
