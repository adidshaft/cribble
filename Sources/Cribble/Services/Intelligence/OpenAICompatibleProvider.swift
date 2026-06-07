import Foundation

/// One provider for *any* OpenAI-compatible local runner — Ollama
/// (`localhost:11434/v1`), llama.cpp's `llama-server` (`localhost:8080/v1`),
/// LM Studio, vLLM, etc. The research doc (§3.1) recommends collapsing the
/// separate Ollama/llama.cpp providers into this single client: they speak the
/// same dialect, so "works with anything OpenAI-compatible on localhost" is both
/// less code and a stronger story than naming specific runners.
///
/// `@unchecked Sendable`: holds only immutable config + a `URLSession`.
final class OpenAICompatibleProvider: IntelligenceProvider, @unchecked Sendable {
    let displayName: String
    private let baseURL: URL
    private let apiKey: String?
    private let model: String
    private let embedModel: String?
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: e.g. `http://localhost:11434/v1` or `http://localhost:8080/v1`.
    ///   - model: chat model id served by the runner.
    ///   - embedModel: embeddings model id, or nil to disable embeddings.
    init(
        baseURL: URL,
        model: String,
        embedModel: String? = nil,
        apiKey: String? = nil,
        displayName: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = Self.normalizedLoopbackURL(baseURL)
        self.model = model
        self.embedModel = embedModel
        self.apiKey = apiKey
        self.displayName = displayName ?? "\(model) (\(self.baseURL.host ?? "local"))"
        self.session = session
    }

    func checkAvailability() async -> ProviderAvailability {
        // Probe `/models`; a 200 means the runner is up and reachable.
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 3
        authorize(&request)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .unavailable(reason: "Runner at \(baseURL.host ?? "localhost") not responding")
            }
            return .available
        } catch {
            return .unavailable(reason: "Can't reach \(baseURL.host ?? "localhost"): \(error.localizedDescription)")
        }
    }

    static func availableModelIDs(baseURL: URL, session: URLSession = .shared) async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleProviderError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw OpenAICompatibleProviderError.httpError(http.statusCode, String(detail))
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArray = json["data"] as? [[String: Any]]
        else {
            throw OpenAICompatibleProviderError.unexpectedResponse
        }
        return dataArray.compactMap { $0["id"] as? String }.sorted()
    }

    func generate(prompt: [EngineMessage], schema: JSONSchemaHint?, maxTokens: Int) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": 0.2,
            "messages": prompt.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        // Schema-constrained generation when the caller supplied a hint. Runners
        // that ignore `response_format` simply fall back to free-form text.
        if let schema {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": schema.name, "strict": false]
            ]
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw LocalChatEngineError.generationFailed("HTTP error: \(detail)")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let choice = choices.first
        else {
            throw LocalChatEngineError.generationFailed("Unexpected response shape")
        }
        guard let content = Self.extractText(from: choice) else {
            throw LocalChatEngineError.generationFailed("Unexpected response shape")
        }
        return content
    }

    func embed(text: String) async throws -> [Float]? {
        guard let embedModel else { return nil }
        let body: [String: Any] = ["model": embedModel, "input": text]
        var request = URLRequest(url: baseURL.appendingPathComponent("embeddings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArray = json["data"] as? [[String: Any]],
            let embedding = dataArray.first?["embedding"] as? [Double]
        else { return nil }
        return embedding.map(Float.init)
    }

    private func authorize(_ request: inout URLRequest) {
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
    }

    private static func normalizedLoopbackURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "localhost"
        else { return url }
        components.host = "127.0.0.1"
        return components.url ?? url
    }

    private static func extractText(from choice: [String: Any]) -> String? {
        if let message = choice["message"] as? [String: Any] {
            if let text = message["content"] as? String, !text.isEmpty {
                return text
            }
            if let parts = message["content"] as? [[String: Any]] {
                let text = parts.compactMap { part -> String? in
                    if let value = part["text"] as? String { return value }
                    if let text = part["text"] as? [String: Any] { return text["value"] as? String }
                    return nil
                }.joined()
                if !text.isEmpty { return text }
            }
            if let text = message["content"] as? String {
                return text
            }
        }
        return choice["text"] as? String
    }

    /// Common local runner endpoints, probed in order during first-run setup.
    static let knownLocalEndpoints: [(name: String, url: URL)] = [
        ("Ollama", URL(string: "http://127.0.0.1:11434/v1")!),
        ("llama.cpp", URL(string: "http://127.0.0.1:8080/v1")!),
        ("LM Studio", URL(string: "http://127.0.0.1:1234/v1")!)
    ]
}

private enum OpenAICompatibleProviderError: LocalizedError {
    case httpError(Int, String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .httpError(let status, let detail):
            return detail.isEmpty ? "Runner returned HTTP \(status)." : "Runner returned HTTP \(status): \(detail)"
        case .unexpectedResponse:
            return "Runner did not return an OpenAI-compatible models list."
        }
    }
}
