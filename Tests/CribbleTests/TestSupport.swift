import XCTest
@testable import Cribble

/// Minimal URLProtocol stub. `handler` maps a request to (status, headers, body).
/// Shared test support: every HTTP-touching test file in this suite uses it.
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

extension StubURLProtocol {
    /// Handler that answers `GET /models` with one model ("m") and delegates
    /// every other request to `chat` — the common shape of engine tests.
    static func modelsThen(
        _ chat: @escaping @Sendable (URLRequest) -> (Int, [String: String], Data)
    ) -> @Sendable (URLRequest) -> (Int, [String: String], Data) {
        { request in
            if request.url!.path.hasSuffix("/models") {
                return (200, ["Content-Type": "application/json"], Data(#"{"data":[{"id":"m"}]}"#.utf8))
            }
            return chat(request)
        }
    }

    /// Reads a URLRequest body whether it arrived as data or a stream.
    static func bodyData(of request: URLRequest) -> Data? {
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

/// Thread-safe token sink for streaming assertions.
final class TokenCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ token: String) { lock.withLock { storage.append(token) } }
    var tokens: [String] { lock.withLock { storage } }
}

final class CapturedRequestBody: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Data?
    func store(_ data: Data?) { lock.withLock { storage = data } }
    var data: Data? { lock.withLock { storage } }
}
