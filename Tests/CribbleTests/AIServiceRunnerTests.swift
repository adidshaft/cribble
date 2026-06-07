import XCTest
@testable import Cribble

final class AIServiceRunnerTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    // MARK: - Vault context assembly

    func testVaultContextInlinesMarkdownFilesWithinBudget() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIServiceRunnerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "# Alpha".write(to: dir.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        try "# Beta beta".write(to: dir.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
        try "not markdown".write(to: dir.appendingPathComponent("C.txt"), atomically: true, encoding: .utf8)

        let context = AIService.vaultContext(folderURL: dir, maxCharacters: 32_000)
        XCTAssertTrue(context.contains("=== A.md ==="))
        XCTAssertTrue(context.contains("# Alpha"))
        XCTAssertTrue(context.contains("=== B.md ==="))
        XCTAssertFalse(context.contains("not markdown"))
    }

    func testVaultContextMarksOmittedFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIServiceRunnerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try String(repeating: "a", count: 500).write(to: dir.appendingPathComponent("small.md"), atomically: true, encoding: .utf8)
        try String(repeating: "b", count: 50_000).write(to: dir.appendingPathComponent("big.md"), atomically: true, encoding: .utf8)

        let context = AIService.vaultContext(folderURL: dir, maxCharacters: 2_000)
        XCTAssertTrue(context.contains("1 file(s) omitted"))
    }

    func testVaultContextRespectsBudget() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIServiceRunnerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try String(repeating: "a", count: 500).write(to: dir.appendingPathComponent("small.md"), atomically: true, encoding: .utf8)
        try String(repeating: "b", count: 50_000).write(to: dir.appendingPathComponent("big.md"), atomically: true, encoding: .utf8)

        let context = AIService.vaultContext(folderURL: dir, maxCharacters: 2_000)
        // Smallest-first packing: the small file fits, the big one is skipped.
        XCTAssertTrue(context.contains("=== small.md ==="))
        XCTAssertFalse(context.contains("=== big.md ==="))
        XCTAssertLessThan(context.count, 2_100)
    }

    // MARK: - Provider routing (issue #3: non-Intelligence action uses runner)

    @MainActor
    func testRunnerProviderWithoutConfigThrowsActionableError() async {
        let service = AIService(runnerEndpointSource: .fixed(nil))
        do {
            _ = try await service.generateLinkPatch(
                provider: .localRunner,
                mode: .suggestLinks,
                folderURL: FileManager.default.temporaryDirectory
            )
            XCTFail("Expected commandFailed")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("runner"))
        }
    }

    @MainActor
    func testRunnerProviderSendsPromptAndParsesDiff() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIServiceRunnerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "# Note".write(to: dir.appendingPathComponent("Note.md"), atomically: true, encoding: .utf8)

        let diff = """
        --- a/Note.md
        +++ b/Note.md
        @@ -1,1 +1,1 @@
        -# Note
        +# [[Note]]
        """
        let body = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": diff]]]
        ])
        StubURLProtocol.handler = { _ in (200, ["Content-Type": "application/json"], body) }

        let service = AIService(
            runnerEndpointSource: .fixed(RunnerEndpoint(
                baseURL: URL(string: "http://stub.local/v1")!,
                modelID: "qwen2.5:7b"
            )),
            session: StubURLProtocol.session()
        )
        let parsed = try await service.generateLinkPatch(provider: .localRunner, mode: .suggestLinks, folderURL: dir)
        XCTAssertEqual(parsed.files.first?.newPath, "Note.md")
    }

    @MainActor
    func testRunnerRequestExplainsVaultFormatToModel() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIServiceRunnerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "# Note".write(to: dir.appendingPathComponent("Note.md"), atomically: true, encoding: .utf8)

        let captured = CapturedRequestBody()
        let body = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": "no changes"]]]
        ])
        StubURLProtocol.handler = { request in
            captured.store(Self.bodyData(of: request))
            return (200, ["Content-Type": "application/json"], body)
        }
        let service = AIService(
            runnerEndpointSource: .fixed(RunnerEndpoint(
                baseURL: URL(string: "http://stub.local/v1")!,
                modelID: "m"
            )),
            session: StubURLProtocol.session()
        )
        _ = try? await service.generateLinkPatch(provider: .localRunner, mode: .suggestLinks, folderURL: dir)

        let sent = String(data: captured.data ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sent.contains("You cannot access the filesystem"), "system adapter missing from request")
        XCTAssertTrue(sent.contains("=== Note.md ==="), "vault content missing from request")
    }

    /// Reads a URLRequest body whether it arrived as data or a stream.
    private static func bodyData(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 16_384
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class CapturedRequestBody: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Data?
    func store(_ data: Data?) { lock.withLock { storage = data } }
    var data: Data? { lock.withLock { storage } }
}
