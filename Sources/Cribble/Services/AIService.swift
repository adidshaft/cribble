import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claude = "Claude"
    case localRunner = "Local Runner"

    var id: String { rawValue }

    /// The CLI-spawning providers (the runner is HTTP, not a CLI).
    static var cliProviders: [AIProvider] { [.codex, .claude] }

    var lowestModelName: String {
        switch self {
        case .codex: "gpt-5.5"
        case .claude: "haiku"
        case .localRunner: "" // model comes from LocalRunnerStore
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
    /// Resolved runner endpoint + model for the `.localRunner` provider.
    struct RunnerConfig: Sendable {
        let baseURL: URL
        let modelID: String
    }

    /// Test hook: `.some(config)` / `.some(nil)` bypasses LocalRunnerStore.
    private let runnerConfigOverride: RunnerConfig??
    private let session: URLSession

    init(runnerConfigOverride: RunnerConfig?? = nil, session: URLSession = .shared) {
        self.runnerConfigOverride = runnerConfigOverride
        self.session = session
    }

    @MainActor
    private func resolveRunnerConfig() -> RunnerConfig? {
        if let runnerConfigOverride { return runnerConfigOverride }
        let store = LocalRunnerStore.shared
        guard let baseURL = store.baseURL,
              let modelID = store.defaultModelID ?? store.cachedModelIDs.first
        else { return nil }
        return RunnerConfig(baseURL: baseURL, modelID: modelID)
    }

    /// Concatenates the folder's Markdown files (smallest first) into a
    /// fenced context block, stopping at `maxCharacters`. Smallest-first
    /// packs the most files into the budget.
    static func vaultContext(folderURL: URL, maxCharacters: Int) -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return "" }

        // Resolve symlinks so prefix-stripping works when the folder is e.g.
        // `/var/folders/…` but enumerated URLs come back `/private/var/folders/…`.
        let basePrefix = folderURL.resolvingSymlinksInPath().path + "/"
        var files: [(path: String, size: Int, url: URL)] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            let filePath = url.resolvingSymlinksInPath().path
            let relative = filePath.hasPrefix(basePrefix)
                ? String(filePath.dropFirst(basePrefix.count))
                : filePath
            files.append((relative, size, url))
        }
        files.sort { $0.size < $1.size }

        var sections: [String] = []
        var remaining = maxCharacters
        var omitted = 0
        for file in files {
            // Cheap pre-check: a file's byte size lower-bounds its section
            // length, so skip the content read entirely when it cannot fit.
            // (`continue` rather than `break` keeps the omitted count exact.)
            guard file.size <= remaining else {
                omitted += 1
                continue
            }
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            let section = "=== \(file.path) ===\n\(content)\n"
            guard section.count <= remaining else {
                omitted += 1
                continue
            }
            remaining -= section.count
            sections.append(section)
        }
        if omitted > 0 {
            sections.append("=== NOTE: \(omitted) file(s) omitted — context budget exhausted ===\n")
        }
        return sections.joined(separator: "\n")
    }

    /// Sends `prompt` (plus inlined vault context, since an HTTP runner can't
    /// read the folder like the CLIs do) to the configured local runner via
    /// the same OpenAI-compatible client Intelligence uses.
    private func runViaLocalRunner(prompt: String, folderURL: URL) async throws -> String {
        guard let config = await resolveRunnerConfig() else {
            throw AIServiceError.commandFailed(
                "No local runner is configured. Set one up from the Intelligence HUD's model menu, then try again."
            )
        }
        let context = Self.vaultContext(folderURL: folderURL, maxCharacters: 32_000)
        let provider = OpenAICompatibleProvider(
            baseURL: config.baseURL,
            model: config.modelID,
            session: session
        )
        // The shared prompts assume CLI filesystem access; adapt them for the
        // runner, which only sees the inlined <vault> block.
        let systemPrompt = prompt + """


        NOTE: You cannot access the filesystem. The folder's full contents are inlined in the <vault> block of the user message; each file begins with a `=== relative/path.md ===` header. Treat those as the folder's files, and use exactly those relative paths in any diff headers (`--- a/<path>` / `+++ b/<path>`).
        """
        let messages = [
            EngineMessage(role: .system, content: systemPrompt),
            EngineMessage(role: .user, content: "<vault>\n\(context)\n</vault>")
        ]
        do {
            // 4k tokens: diff outputs are long; CLI paths have no cap.
            return try await provider.generate(prompt: messages, schema: nil, maxTokens: 4_096)
        } catch {
            throw AIServiceError.commandFailed(error.localizedDescription)
        }
    }

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
        case .localRunner:
            output = try await runViaLocalRunner(prompt: prompt, folderURL: folderURL)
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
        case .localRunner:
            return try await runViaLocalRunner(prompt: prompt, folderURL: folderURL)
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
