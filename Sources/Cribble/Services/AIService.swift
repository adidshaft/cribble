import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claude = "Claude"

    var id: String { rawValue }

    var lowestModelName: String {
        switch self {
        case .codex: "gpt-5.5"
        case .claude: "haiku"
        }
    }
}

enum AIMode: String, CaseIterable, Identifiable {
    case suggestLinks
    case updateReadme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .suggestLinks: "Suggest Wiki Links"
        case .updateReadme: "Update README"
        }
    }

    var subtitle: String {
        switch self {
        case .suggestLinks:
            "Insert sparse, high-confidence wiki links across existing notes."
        case .updateReadme:
            "Rewrite the folder README with a short gist and a table of contents."
        }
    }

    var systemImage: String {
        switch self {
        case .suggestLinks: "link"
        case .updateReadme: "doc.text.below.ecg"
        }
    }
}

struct AIService {
    func generateLinkPatch(provider: AIProvider, mode: AIMode, folderURL: URL) async throws -> UnifiedDiff {
        let prompt = Self.prompt(for: mode)
        let output: String

        switch provider {
        case .codex:
            let outputFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("cribble-codex-\(UUID().uuidString).txt")
            output = try await run(
                executable: "/usr/bin/env",
                arguments: [
                    "codex",
                    "--ask-for-approval", "never",
                    "-c", "model_reasoning_effort=\"low\"",
                    "exec",
                    "--model", provider.lowestModelName,
                    "-C", folderURL.path,
                    "--skip-git-repo-check",
                    "--sandbox", "read-only",
                    "--color", "never",
                    "--ephemeral",
                    "-o", outputFile.path,
                    prompt
                ],
                currentDirectory: folderURL,
                provider: provider,
                outputFile: outputFile
            )
        case .claude:
            output = try await run(
                executable: "/usr/bin/env",
                arguments: [
                    "claude",
                    "--print",
                    "--no-session-persistence",
                    "--model", provider.lowestModelName,
                    "--permission-mode", "plan",
                    "--allowedTools", "Read Grep Glob",
                    "--output-format", "text",
                    "--add-dir", folderURL.path,
                    prompt
                ],
                currentDirectory: folderURL,
                provider: provider
            )
        }

        return UnifiedDiffParser.parse(UnifiedDiffParser.extractDiffText(from: output))
    }

    /// Spawns the local Claude/Codex CLI (read-only, no file mutations) to
    /// reason about how two notes connect through the rest of the folder.
    /// Returns the model's prose explanation. Reused by Semantic Pathfinding.
    func explainRelationship(
        provider: AIProvider,
        sourceTitle: String,
        targetTitle: String,
        folderURL: URL
    ) async throws -> String {
        let prompt = Self.relationshipPrompt(sourceTitle: sourceTitle, targetTitle: targetTitle)

        switch provider {
        case .codex:
            let outputFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("cribble-codex-\(UUID().uuidString).txt")
            return try await run(
                executable: "/usr/bin/env",
                arguments: [
                    "codex",
                    "--ask-for-approval", "never",
                    "-c", "model_reasoning_effort=\"low\"",
                    "exec",
                    "--model", provider.lowestModelName,
                    "-C", folderURL.path,
                    "--skip-git-repo-check",
                    "--sandbox", "read-only",
                    "--color", "never",
                    "--ephemeral",
                    "-o", outputFile.path,
                    prompt
                ],
                currentDirectory: folderURL,
                provider: provider,
                outputFile: outputFile
            )
        case .claude:
            return try await run(
                executable: "/usr/bin/env",
                arguments: [
                    "claude",
                    "--print",
                    "--no-session-persistence",
                    "--model", provider.lowestModelName,
                    "--permission-mode", "plan",
                    "--allowedTools", "Read Grep Glob",
                    "--output-format", "text",
                    "--add-dir", folderURL.path,
                    prompt
                ],
                currentDirectory: folderURL,
                provider: provider
            )
        }
    }

    private static func relationshipPrompt(sourceTitle: String, targetTitle: String) -> String {
        """
        Analyze the relationship between the note titled "\(sourceTitle)" and the note titled "\(targetTitle)" in this folder of Markdown notes. Find a logical chain of semantic connections that bridges them, using other notes in this folder where helpful. Output a short structured path of the form `A -> B -> C` followed by one sentence explaining each step. Keep the whole answer under 120 words. Do not modify, create, or write any files.
        """
    }

    private func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL,
        provider: AIProvider,
        outputFile: URL? = nil
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.environment = Self.processEnvironment()

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let outputBuffer = PipeBuffer(fileHandle: outputPipe.fileHandleForReading)
            let errorBuffer = PipeBuffer(fileHandle: errorPipe.fileHandleForReading)
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

            outputBuffer.start()
            errorBuffer.start()
            try process.run()
            process.waitUntilExit()

            let output = outputBuffer.finish()
            let error = errorBuffer.finish()
            let finalOutput = outputFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            if let outputFile {
                try? FileManager.default.removeItem(at: outputFile)
            }

            if process.terminationStatus != 0 {
                throw AIServiceError.commandFailed(Self.friendlyFailureMessage(
                    for: provider,
                    output: output,
                    error: error
                ))
            }

            return finalOutput?.isEmpty == false ? finalOutput ?? output : output
        }.value
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let appPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (appPaths + existingPath.split(separator: ":").map(String.init))
            .uniquedStrings()
            .joined(separator: ":")
        return environment
    }

    private static func friendlyFailureMessage(for provider: AIProvider, output: String, error: String) -> String {
        let rawMessage = error.isEmpty ? output : error
        guard provider == .claude, rawMessage.localizedCaseInsensitiveContains("401") else {
            return rawMessage
        }

        return """
        Claude is installed, but `claude --print` failed with 401 Invalid authentication credentials. Run `claude auth status` in Terminal; if it still says logged in, refresh the token with `claude auth logout` followed by `claude auth login`, or run `claude setup-token`, then try AI Link Notes again.

        \(rawMessage)
        """
    }

    private static func prompt(for mode: AIMode) -> String {
        switch mode {
        case .suggestLinks:
            return suggestLinksPrompt
        case .updateReadme:
            return updateReadmePrompt
        }
    }

    private static let suggestLinksPrompt = """
    Analyze only visible .md files in this folder tree. Suggest sparse, high-confidence wiki links between existing Markdown files. Do not invent files. Do not rewrite prose except to add meaningful [[Wiki Links]] where a note clearly references another note, title, alias, keyword, or tag. Output a unified diff only. Do not include explanation, Markdown fences, or commentary. Do not run editing commands or write files.
    """

    private static let updateReadmePrompt = """
    Analyze every visible .md file in this folder (non-recursive root level first; if README.md sits at the root, only the root level matters). Produce or update README.md so that:

    1. The very top of README.md has a section titled "## Contents" that lists every other .md file in the same folder as a bullet point with a relative Markdown link. Use the document H1 title if present, otherwise the filename without extension. Sort alphabetically by display title. Do not include README.md itself.
    2. Immediately below the table of contents, add or refresh a "## Gist" section. For each linked file, add one short bullet (one or two sentences max) summarising what that file is about, based only on the file's actual content. Do not invent details.
    3. Preserve any existing prose in README.md that is not the Contents or Gist sections. Place Contents first, then Gist, then the pre-existing prose. If there is no pre-existing prose, the README may just contain Contents and Gist.

    Output a single unified diff against README.md (and only README.md). Do not modify any other files. Do not include explanation, Markdown fences, or commentary. If README.md does not exist, emit a diff that creates it. Use standard unified diff format with `--- a/README.md` / `+++ b/README.md` headers and `@@` hunks.
    """
}

enum AIServiceError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            message.isEmpty ? "The AI command failed." : message
        }
    }
}

private extension Array where Element == String {
    func uniquedStrings() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private final class PipeBuffer: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let lock = NSLock()
    private var data = Data()

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func start() {
        fileHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.append(chunk)
        }
    }

    func finish() -> String {
        fileHandle.readabilityHandler = nil
        append(fileHandle.readDataToEndOfFile())
        return String(data: snapshot(), encoding: .utf8) ?? ""
    }

    private func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.withLock {
            data.append(chunk)
        }
    }

    private func snapshot() -> Data {
        lock.withLock {
            data
        }
    }
}
