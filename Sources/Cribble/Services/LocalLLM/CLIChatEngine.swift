import Foundation

/// Cloud chat engine that drives the local `claude` / `codex` CLIs — the same
/// tools the AI-Link-Notes feature uses. No Metal needed, so this works in the
/// SwiftPM-CLI build where on-device MLX can't run.
///
/// The CLIs are run through the user's **login shell** (`$SHELL -lc`) so they
/// inherit the same PATH and environment as Terminal — this is what makes the
/// binary discoverable AND lets the CLI find its existing login/session. The
/// prompt is passed via an environment variable (`CRIBBLE_PROMPT`) so arbitrary
/// content needs no shell quoting and can't be injected.
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
                "`\(provider.executableName)` wasn't found in your shell's PATH. Install it, run "
                + "`\(provider.executableName)` once in Terminal to sign in, then try again."
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
            // `claude --print` streams plain text; prompt comes from $CRIBBLE_PROMPT.
            return try await run(
                command: "claude --print --output-format text \"$CRIBBLE_PROMPT\"",
                prompt: prompt,
                streaming: true,
                onToken: onToken
            )
        case .codex:
            // Codex prints progress chatter to stdout, so capture the clean final
            // message via an output file.
            let outputFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("cribble-hud-codex-\(UUID().uuidString).txt")
            let text = try await run(
                command: "codex exec --skip-git-repo-check --color never --sandbox read-only -o \"$CRIBBLE_OUT\" \"$CRIBBLE_PROMPT\"",
                prompt: prompt,
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
        command: String,
        prompt: String,
        streaming: Bool,
        onToken: @escaping @Sendable (String) -> Void,
        outputFile: URL? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.loginShell())
            // `-l` sources the login profile (full PATH/env); `-c` runs the command.
            process.arguments = ["-l", "-c", command]
            process.currentDirectoryURL = FileManager.default.temporaryDirectory

            var environment = ProcessInfo.processInfo.environment
            environment["CRIBBLE_PROMPT"] = prompt
            if let outputFile { environment["CRIBBLE_OUT"] = outputFile.path }
            process.environment = environment

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
                        Self.friendlyError(provider: self.provider, status: proc.terminationStatus, stderr: errorText)
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

    private static func friendlyError(provider: Provider, status: Int32, stderr: String) -> String {
        let raw = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.localizedCaseInsensitiveContains("logged in") == false,
           raw.localizedCaseInsensitiveContains("login") || raw.localizedCaseInsensitiveContains("auth")
            || raw.localizedCaseInsensitiveContains("401") {
            return "\(provider.executableName) isn't signed in. Run `\(provider.executableName)` in Terminal to log in, then try again.\n\n\(raw)"
        }
        return raw.isEmpty ? "\(provider.executableName) exited with code \(status)." : raw
    }

    private static func loginShell() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"]
        if let shell, !shell.isEmpty, FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    /// Checks the binary is reachable from the login shell (same PATH as Terminal).
    private static func executableExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: loginShell())
        process.arguments = ["-l", "-c", "command -v \(name)"]
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
}

/// Thread-safe text accumulator for streaming stdout.
private final class TextAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func append(_ text: String) { lock.withLock { storage += text } }
    var value: String { lock.withLock { storage } }
}
