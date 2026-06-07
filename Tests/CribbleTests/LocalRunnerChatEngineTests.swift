import XCTest
@testable import Cribble

final class LocalRunnerChatEngineTests: XCTestCase {

    // MARK: - SSE line parsing (pure)

    func testParsesDeltaContentFromSSELine() {
        let line = #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#
        XCTAssertEqual(LocalRunnerChatEngine.deltaText(fromSSELine: line), "Hel")
    }

    func testIgnoresDoneSentinelAndBlankLines() {
        XCTAssertNil(LocalRunnerChatEngine.deltaText(fromSSELine: "data: [DONE]"))
        XCTAssertNil(LocalRunnerChatEngine.deltaText(fromSSELine: ""))
        XCTAssertNil(LocalRunnerChatEngine.deltaText(fromSSELine: ": keepalive"))
    }

    func testIgnoresChunksWithoutContent() {
        // Role-only first chunk and finish chunk both carry no text.
        XCTAssertNil(LocalRunnerChatEngine.deltaText(fromSSELine: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#))
        XCTAssertNil(LocalRunnerChatEngine.deltaText(fromSSELine: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#))
    }

    // MARK: - End-to-end with stubbed HTTP

    @MainActor
    func testStreamsSSEResponseAndAssemblesFullText() async throws {
        let body = """
        data: {"choices":[{"delta":{"role":"assistant"}}]}

        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" world"}}]}

        data: [DONE]

        """
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/models") {
                return (200, ["Content-Type": "application/json"], Data(#"{"data":[{"id":"m"}]}"#.utf8))
            }
            return (200, ["Content-Type": "text/event-stream"], Data(body.utf8))
        }
        let engine = LocalRunnerChatEngine(session: StubURLProtocol.session()) {
            URL(string: "http://stub.local/v1")
        }
        try await engine.prepare(model: .runnerModel(modelID: "m")) { _ in }

        let collector = TokenCollector()
        let full = try await engine.generate(
            messages: [EngineMessage(role: .user, content: "hi")],
            maxTokens: 64
        ) { delta in collector.append(delta) }

        XCTAssertEqual(full, "Hello world")
        XCTAssertEqual(collector.tokens, ["Hello", " world"])
    }

    @MainActor
    func testFallsBackToNonStreamingJSONResponse() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/models") {
                return (200, ["Content-Type": "application/json"], Data(#"{"data":[{"id":"m"}]}"#.utf8))
            }
            let body = #"{"choices":[{"message":{"role":"assistant","content":"All at once"}}]}"#
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let engine = LocalRunnerChatEngine(session: StubURLProtocol.session()) {
            URL(string: "http://stub.local/v1")
        }
        try await engine.prepare(model: .runnerModel(modelID: "m")) { _ in }
        let full = try await engine.generate(
            messages: [EngineMessage(role: .user, content: "hi")],
            maxTokens: 64
        ) { _ in }
        XCTAssertEqual(full, "All at once")
    }

    @MainActor
    func testPrepareFailsClearlyWhenNoRunnerConfigured() async {
        let engine = LocalRunnerChatEngine(session: StubURLProtocol.session()) { nil }
        do {
            try await engine.prepare(model: .runnerModel(modelID: "m")) { _ in }
            XCTFail("Expected modelLoadFailed")
        } catch {
            // The message must tell the user where to configure the runner —
            // this is the "clearly explain" acceptance criterion.
            XCTAssertTrue(error.localizedDescription.contains("runner"), "got: \(error.localizedDescription)")
        }
    }

    @MainActor
    func testGenerateSurfacesHTTPErrorBody() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/models") {
                return (200, ["Content-Type": "application/json"], Data(#"{"data":[{"id":"m"}]}"#.utf8))
            }
            return (404, ["Content-Type": "application/json"], Data(#"{"error":"model 'm' not found"}"#.utf8))
        }
        let engine = LocalRunnerChatEngine(session: StubURLProtocol.session()) {
            URL(string: "http://stub.local/v1")
        }
        try await engine.prepare(model: .runnerModel(modelID: "m")) { _ in }
        do {
            _ = try await engine.generate(messages: [EngineMessage(role: .user, content: "x")], maxTokens: 8) { _ in }
            XCTFail("Expected generationFailed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("not found"), "got: \(error.localizedDescription)")
        }
    }
}

/// Thread-safe token sink for streaming assertions.
private final class TokenCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ token: String) { lock.withLock { storage.append(token) } }
    var tokens: [String] { lock.withLock { storage } }
}

/// Minimal URLProtocol stub. `handler` maps a request to (status, headers, body).
/// Intentionally `internal`: AIServiceRunnerTests reuses it.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
