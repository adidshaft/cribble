import Foundation

/// `LocalChatEngine` backed by the user's OpenAI-compatible local runner
/// (Ollama, llama.cpp, LM Studio, …) configured in `LocalRunnerStore`. This is
/// what lets the Chat HUD — and everything that shares its engine path: quick
/// actions, attachment digests, Pathfinder — use the same runner Intelligence
/// uses, instead of a separate model stack (issue #3).
///
/// Streams real tokens: `POST /v1/chat/completions` with `stream: true`,
/// parsing SSE `data:` chunks. Runners that ignore `stream` and answer with a
/// plain JSON body still work via the non-streaming fallback.
///
/// `@unchecked Sendable`: mutable state (`config`, `cancelRequested`) is
/// guarded by `lock`, mirroring the other engines.
final class LocalRunnerChatEngine: LocalChatEngine, @unchecked Sendable {
    private struct Config {
        let baseURL: URL
        let modelID: String
    }

    private let session: URLSession
    /// Reads the configured base URL; injectable for tests. The default reads
    /// `LocalRunnerStore` on the main actor.
    private let baseURLProvider: @Sendable () async -> URL?
    private let lock = NSLock()
    private var config: Config?
    private var cancelRequested = false

    init(
        session: URLSession = .shared,
        baseURLProvider: (@Sendable () async -> URL?)? = nil
    ) {
        self.session = session
        self.baseURLProvider = baseURLProvider ?? { await MainActor.run { LocalRunnerStore.shared.baseURL } }
    }

    // MARK: - LocalChatEngine

    /// Unlike the on-device engines, `prepare` re-probes the runner each call
    /// (cheap on localhost) so base-URL changes are picked up immediately;
    /// the view model already avoids per-send calls via its ready check.
    func prepare(
        model: LocalModel,
        onProgress: @escaping @Sendable (ModelLoadProgress) -> Void
    ) async throws {
        guard model.id.hasPrefix(LocalModel.runnerIDPrefix) else {
            throw LocalChatEngineError.modelLoadFailed("\(model.name) is not a local runner model.")
        }
        let modelID = String(model.id.dropFirst(LocalModel.runnerIDPrefix.count))
        guard let baseURL = await baseURLProvider() else {
            throw LocalChatEngineError.modelLoadFailed(
                "No local runner is configured. Set one up from the Intelligence HUD's model menu."
            )
        }

        // Reachability probe — same contract as OpenAICompatibleProvider's
        // availability check: a 2xx on /models means the runner is up.
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 3
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw LocalChatEngineError.modelLoadFailed(
                    "The local runner at \(baseURL.host ?? "localhost") isn't responding. Is it running?"
                )
            }
        } catch let error as LocalChatEngineError {
            throw error
        } catch {
            throw LocalChatEngineError.modelLoadFailed(
                "Can't reach the local runner at \(baseURL.host ?? "localhost"): \(error.localizedDescription)"
            )
        }

        lock.withLock { config = Config(baseURL: baseURL, modelID: modelID) }
        onProgress(ModelLoadProgress(fraction: 1))
    }

    func generate(
        messages: [EngineMessage],
        maxTokens: Int,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let config = lock.withLock({ self.config }) else {
            throw LocalChatEngineError.generationFailed("The local runner engine isn't prepared.")
        }
        lock.withLock { cancelRequested = false }

        let body: [String: Any] = [
            "model": config.modelID,
            "max_tokens": maxTokens,
            "temperature": 0.7,
            "stream": true,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LocalChatEngineError.generationFailed("Unexpected response from the local runner.")
        }
        guard (200..<300).contains(http.statusCode) else {
            // Drain the (small) error body so the message names the real cause,
            // e.g. Ollama's "model 'x' not found".
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 4_096 { break } // cap the diagnostic drain
            }
            let detail = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw LocalChatEngineError.generationFailed("Local runner error (HTTP \(http.statusCode)): \(detail)")
        }

        let isSSE = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
            .lowercased().contains("text/event-stream")

        if isSSE {
            var full = ""
            for try await line in bytes.lines {
                if lock.withLock({ cancelRequested }) { throw CancellationError() }
                try Task.checkCancellation()
                guard let delta = Self.deltaText(fromSSELine: line) else { continue }
                full += delta
                onToken(delta)
            }
            return full
        }

        // Fallback: the runner ignored `stream: true` and sent one JSON body.
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        let text = try Self.messageText(fromResponseBody: data)
        onToken(text)
        return text
    }

    func cancelGeneration() async {
        lock.withLock { cancelRequested = true }
    }

    // MARK: - Parsing (static & pure, unit-tested directly)

    /// Extracts the text delta from one SSE line. Returns nil for keepalives,
    /// `[DONE]`, role-only chunks, and finish chunks.
    static func deltaText(fromSSELine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", !payload.isEmpty else { return nil }
        guard
            let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let choice = choices.first
        else { return nil }
        if let delta = choice["delta"] as? [String: Any], let text = delta["content"] as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    /// Parses a complete (non-streaming) chat-completions body. Delegates the
    /// message-shape handling to `OpenAICompatibleProvider.extractText` so both
    /// runner clients tolerate the same response dialects.
    static func messageText(fromResponseBody data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let choice = choices.first,
            let text = OpenAICompatibleProvider.extractText(from: choice)
        else {
            throw LocalChatEngineError.generationFailed("Unexpected response shape from the local runner.")
        }
        return text
    }
}
