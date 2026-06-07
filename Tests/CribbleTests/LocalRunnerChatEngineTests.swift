import XCTest
@testable import Cribble

final class LocalRunnerChatEngineTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

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

    func testMessageTextHandlesContentPartArrays() throws {
        // Some runners answer with content-part arrays instead of a string.
        let body = #"{"choices":[{"message":{"role":"assistant","content":[{"type":"text","text":"Part one."},{"type":"text","text":" Part two."}]}}]}"#
        let text = try LocalRunnerChatEngine.messageText(fromResponseBody: Data(body.utf8))
        XCTAssertEqual(text, "Part one. Part two.")
    }

    func testRecognizesReasoningDeltas() {
        XCTAssertTrue(LocalRunnerChatEngine.isReasoningDelta(fromSSELine: #"data: {"choices":[{"delta":{"reasoning_content":"hmm"}}]}"#))
        XCTAssertFalse(LocalRunnerChatEngine.isReasoningDelta(fromSSELine: #"data: {"choices":[{"delta":{"content":"hi"}}]}"#))
        XCTAssertFalse(LocalRunnerChatEngine.isReasoningDelta(fromSSELine: "data: [DONE]"))
        XCTAssertFalse(LocalRunnerChatEngine.isReasoningDelta(fromSSELine: #"data: {"choices":[{"delta":{"reasoning_content":""}}]}"#))
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
        StubURLProtocol.handler = StubURLProtocol.modelsThen { _ in
            (200, ["Content-Type": "text/event-stream"], Data(body.utf8))
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
    func testReasoningDeltasEmitLivenessAndContentStillAssembles() async throws {
        let body = """
        data: {"choices":[{"delta":{"role":"assistant"}}]}

        data: {"choices":[{"delta":{"reasoning_content":"thinking..."}}]}

        data: {"choices":[{"delta":{"reasoning_content":"more thinking"}}]}

        data: {"choices":[{"delta":{"content":"Answer."}}]}

        data: [DONE]

        """
        StubURLProtocol.handler = StubURLProtocol.modelsThen { _ in
            (200, ["Content-Type": "text/event-stream"], Data(body.utf8))
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

        XCTAssertEqual(full, "Answer.")
        // Two liveness pings (empty) + one real token, in order.
        XCTAssertEqual(collector.tokens, ["", "", "Answer."])
    }

    @MainActor
    func testReasoningOnlyStreamFailsWithActionableError() async throws {
        let body = """
        data: {"choices":[{"delta":{"reasoning_content":"endless thinking"}}]}

        data: {"choices":[{"delta":{"content":"\\n"}}]}

        data: [DONE]

        """
        StubURLProtocol.handler = StubURLProtocol.modelsThen { _ in
            (200, ["Content-Type": "text/event-stream"], Data(body.utf8))
        }
        let engine = LocalRunnerChatEngine(session: StubURLProtocol.session()) {
            URL(string: "http://stub.local/v1")
        }
        try await engine.prepare(model: .runnerModel(modelID: "m")) { _ in }
        do {
            _ = try await engine.generate(messages: [EngineMessage(role: .user, content: "hi")], maxTokens: 8) { _ in }
            XCTFail("Expected generationFailed for whitespace-only content")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no answer text"), "got: \(error.localizedDescription)")
        }
    }

    @MainActor
    func testFallsBackToNonStreamingJSONResponse() async throws {
        StubURLProtocol.handler = StubURLProtocol.modelsThen { _ in
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
        StubURLProtocol.handler = StubURLProtocol.modelsThen { _ in
            (404, ["Content-Type": "application/json"], Data(#"{"error":"model 'm' not found"}"#.utf8))
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
