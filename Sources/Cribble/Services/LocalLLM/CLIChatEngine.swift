import Foundation

/// Cloud chat engine that drives the local `claude` / `codex` CLIs — the same
/// tools the AI-Link-Notes feature uses. No Metal needed, so this works in the
/// SwiftPM-CLI build where on-device MLX can't run. The model context (including
/// `@file` contents) is already inlined into the prompt by `ContextAssembler`,
/// so the CLI is run without filesystem access.
final class CLIChatEngine: LocalChatEngine, @unchecked Sendable {
    enum Provider {
        case claude
        case codex
        var executableName: String { self == .claude ? "claude" : "codex" }
    }

    let provider: Provider
    private let lock = NSLock()
    private var current: Process?

    init(provider: Provider) {
        self.provider = provider
    }

    func prepare(model: LocalModel, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard Self.executableExists(provider.executableName) else {
            throw LocalChatEngineError.modelLoadFailed(
                "`\(provider.executableName)` isn't installed or isn't on your PATH. "
                + "Install it, run `\(provider.executableName)` once in Terminal to sign in, then try again."
            )
        }
        onProgress(1.0)
    }

    func generate(
        messages: [EngineMessage],
        maxTokens: Int,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let prompt = Self.flatten(messages)
        switch provider {
        case .claude:
            return try await run(
                arguments: ["--print", "--output-format", "text", prompt],
                streaming: true,
                onToken: onToken
            )
        case .codex:
            // Codex prints progress chatter to stdout, so capture the clean final
            // message via an output file (matching AIService's approach).
            let outputFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("cribble-hud-codex-\(UUID().uuidString).txt")
            let text = try await run(
                arguments: [
                    "exec", "--skip-git-repo-check", "--color", "never",
                    "--sandbox", "read-only", "-o", outputFile.path, prompt
                ],
                streaming: false,
                onToken: onToken,
                outputFile: outputFile
            )
            onToken(text)
            return text
        }
    }

    func cancelGeneration() async {
        let process = lock.withLock { current }
        process?.terminate()
    }

    // MARK: - Process runner

    private func run(
        arguments: [String],
        streaming: Bool,
        onToken: @escaping @Sendable (String) -> Void,
        outputFile: URL? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [provider.executableName] + arguments
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.environment = Self.processEnvironment()

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

            let accumulator = TextAccumulator()
            if streaming {
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
                    accumulator.append(text)
                    onToken(text)
                }
            }

            process.terminationHandler = { proc in
                if streaming {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    accumulator.append(
                        String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    )
                }
                let errorText = String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""
                self.lock.withLock { self.current = nil }

                let fileText = outputFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                if let outputFile { try? FileManager.default.removeItem(at: outputFile) }

                let output = (fileText?.isEmpty == false ? fileText! : accumulator.value)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if proc.terminationStatus != 0 && output.isEmpty {
                    continuation.resume(throwing: LocalChatEngineError.generationFailed(
                        errorText.isEmpty ? "\(self.provider.executableName) exited with code \(proc.terminationStatus)." : errorText
                    ))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                lock.withLock { current = process }
                try process.run()
            } catch {
                lock.withLock { current = nil }
                continuation.resume(throwing: LocalChatEngineError.modelLoadFailed(error.localizedDescription))
            }
        }
    }

    /// Flattens the role/content turns into a single prompt string. The system
    /// turn (file context + output rules) leads, then the running transcript.
    static func flatten(_ messages: [EngineMessage]) -> String {
        var parts: [String] = []
        for message in messages {
            switch message.role {
            case .system: parts.append(message.content)
            case .user: parts.append("User: \(message.content)")
            case .assistant: parts.append("Assistant: \(message.content)")
            }
        }
        parts.append("Assistant:")
        return parts.joined(separator: "\n\n")
    }

    private static func executableExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.environment = processEnvironment()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (extraPaths + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }
}

/// Thread-safe text accumulator for streaming stdout.
private final class TextAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func append(_ text: String) { lock.withLock { storage += text } }
    var value: String { lock.withLock { storage } }
}
