import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claude = "Claude"

    var id: String { rawValue }
}

struct AIService {
    func generateLinkPatch(provider: AIProvider, folderURL: URL) async throws -> UnifiedDiff {
        let prompt = Self.prompt
        let output: String

        switch provider {
        case .codex:
            let outputFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("cribble-codex-\(UUID().uuidString).txt")
            output = try await run(
                executable: "/usr/bin/env",
                arguments: [
                    "codex", "exec",
                    "-C", folderURL.path,
                    "--skip-git-repo-check",
                    "--sandbox", "read-only",
                    "--color", "never",
                    "--ephemeral",
                    "-o", outputFile.path,
                    prompt
                ],
                currentDirectory: folderURL,
                outputFile: outputFile
            )
        case .claude:
            output = try await run(
                executable: "/usr/bin/env",
                arguments: [
                    "claude",
                    "--print",
                    "--bare",
                    "--no-session-persistence",
                    "--permission-mode", "dontAsk",
                    "--tools=Read,Grep,Glob",
                    "--allowedTools=Read,Grep,Glob",
                    "--output-format", "text",
                    "--",
                    prompt
                ],
                currentDirectory: folderURL
            )
        }

        return UnifiedDiffParser.parse(UnifiedDiffParser.extractDiffText(from: output))
    }

    private func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL,
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
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let finalOutput = outputFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            if let outputFile {
                try? FileManager.default.removeItem(at: outputFile)
            }

            if process.terminationStatus != 0 {
                throw AIServiceError.commandFailed(error.isEmpty ? output : error)
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

    private static let prompt = """
    Analyze only visible .md files in this folder tree. Suggest sparse, high-confidence wiki links between existing Markdown files. Do not invent files. Do not rewrite prose except to add meaningful [[Wiki Links]] where a note clearly references another note, title, alias, keyword, or tag. Output a unified diff only. Do not include explanation, Markdown fences, or commentary. Do not run editing commands or write files.
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
