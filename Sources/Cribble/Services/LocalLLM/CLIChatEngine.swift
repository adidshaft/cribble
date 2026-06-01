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
        guard let process, process.isRunning else { return }
        process.terminate() // SIGTERM
        // Some CLIs trap or ignore SIGTERM; escalate to SIGKILL after a short
        // grace period so Stop always works and the HUD never stays wedged on a
        // child that refuses to die.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
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

            // Both pipes are drained continuously. macOS pipe buffers are ~64 KB;
            // if either fills, the child blocks on write() and never exits — the
            // termination handler then never fires and the continuation leaks.
            // codex is the worst case: it streams progress chatter to stdout even
            // though we read its real answer from a file, so stdout MUST be
            // drained whether or not we forward it as tokens.
            let stdoutReader = StreamingUTF8Decoder()
            let stderrReader = StreamingUTF8Decoder()

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                let text = stdoutReader.consume(chunk)
                if streaming, !text.isEmpty { onToken(text) }
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                _ = stderrReader.consume(chunk)
            }

            process.terminationHandler = { proc in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                // Drain whatever was buffered between the last read and exit, then
                // flush any bytes held back at a partial UTF-8 boundary.
                let tailOut = stdoutReader.consume(outputPipe.fileHandleForReading.readDataToEndOfFile())
                if streaming, !tailOut.isEmpty { onToken(tailOut) }
                let streamedTail = stdoutReader.finish()
                if streaming, !streamedTail.isEmpty { onToken(streamedTail) }

                _ = stderrReader.consume(errorPipe.fileHandleForReading.readDataToEndOfFile())
                _ = stderrReader.finish()
                let errorText = stderrReader.value

                self.lock.withLock { self.current = nil }

                let fileText = outputFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                if let outputFile { try? FileManager.default.removeItem(at: outputFile) }

                let output = (fileText?.isEmpty == false ? fileText! : stdoutReader.value)
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

/// Thread-safe, UTF-8-aware accumulator for streaming pipe output.
///
/// A `Process` pipe hands us arbitrary byte boundaries, so a multi-byte UTF-8
/// scalar (emoji, CJK, smart quotes, `…`) is frequently split across two reads.
/// Decoding each raw chunk in isolation would return `nil` for the split chunk
/// and silently drop it — losing characters and corrupting Markdown structure
/// (a dropped ``` fence or `]` breaks the whole block). This decoder holds back
/// the partial trailing sequence and prepends it to the next chunk.
final class StreamingUTF8Decoder: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()   // bytes of an incomplete trailing scalar
    private var text = ""          // everything decoded so far

    /// Appends raw bytes and returns only the newly-decodable text.
    func consume(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        return lock.withLock {
            pending.append(data)
            let (decodable, remainder) = Self.splitOnScalarBoundary(pending)
            pending = remainder
            guard !decodable.isEmpty, let chunk = String(data: decodable, encoding: .utf8) else { return "" }
            text += chunk
            return chunk
        }
    }

    /// Flushes any bytes still held back at end of stream. If they're genuinely
    /// invalid UTF-8 they're decoded lossily (U+FFFD) rather than dropped.
    func finish() -> String {
        lock.withLock {
            guard !pending.isEmpty else { return "" }
            let chunk = String(decoding: pending, as: UTF8.self)
            pending.removeAll()
            text += chunk
            return chunk
        }
    }

    var value: String { lock.withLock { text } }

    /// Splits `data` into (complete-scalars, incomplete-trailing-bytes) on a
    /// UTF-8 scalar boundary.
    static func splitOnScalarBoundary(_ data: Data) -> (Data, Data) {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return (Data(), Data()) }

        // Walk back from the end to the lead byte of the final scalar (skip
        // continuation bytes 0b10xxxxxx). A UTF-8 scalar is at most 4 bytes.
        var i = bytes.count - 1
        let lowerBound = max(0, bytes.count - 4)
        while i > lowerBound, bytes[i] & 0b1100_0000 == 0b1000_0000 {
            i -= 1
        }

        let lead = bytes[i]
        let scalarLength: Int
        if lead & 0b1000_0000 == 0 { scalarLength = 1 }
        else if lead & 0b1110_0000 == 0b1100_0000 { scalarLength = 2 }
        else if lead & 0b1111_0000 == 0b1110_0000 { scalarLength = 3 }
        else if lead & 0b1111_1000 == 0b1111_0000 { scalarLength = 4 }
        else { scalarLength = 1 } // invalid lead — treat as complete, decoded lossily

        let available = bytes.count - i
        // Complete final scalar (or it's already over-long/invalid) → all decodable.
        let cut = available >= scalarLength ? bytes.count : i
        return (Data(bytes[0..<cut]), Data(bytes[cut...]))
    }
}
