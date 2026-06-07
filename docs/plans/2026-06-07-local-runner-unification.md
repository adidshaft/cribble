# Local Runner Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the OpenAI-compatible local runner support (PR #2, Intelligence-only) to the Chat HUD and every other AI entry point, behind one shared config store (issue #3).

**Architecture:** A new `@MainActor` singleton `LocalRunnerStore` is the single source of truth for runner config (base URL, cached model list, default model). The runner becomes a first-class `ModelKind.localRunner` with dynamic `LocalModel`s (`id: "runner:<modelID>"`) and a streaming `LocalRunnerChatEngine: LocalChatEngine` (SSE on `POST /v1/chat/completions`). Because Chat HUD, quick actions, attachment digests, and Pathfinder all resolve engines via `ModelCatalog` → `LocalLLM.shared.engine(for:)`, they inherit runner support from that one seam. `AIService` (AI Link Notes / README fill) gains a `.localRunner` provider that inlines vault context and calls the existing non-streaming `OpenAICompatibleProvider`.

**Tech Stack:** Swift 6 (strict concurrency — new types must be `Sendable`-correct), SwiftPM, XCTest. Test with `swift test`. Design doc: `docs/plans/2026-06-07-local-runner-unification-design.md`.

**Key design refinement vs. design doc:** `LocalRunnerStore` persists under its own key `localRunner.baseURL` and **migrates** from `intelligence.runnerURL` on first read, instead of sharing that key live. Reason: `IntelligenceEngine.setModel()` nils `intelligence.runnerURL` when the user moves Intelligence back to an on-device model — with a shared key that would silently unconfigure the runner for Chat too. Migration keeps "configure once, use everywhere" while letting Intelligence opt out independently. All config writes still flow through one place (`LocalRunnerStore.configure` / `clear`, called from the existing Intelligence HUD panel).

---

## Existing code you must understand first (read these before Task 1)

| File | Why |
|---|---|
| `Sources/Cribble/Services/LocalLLM/LocalChatEngine.swift` | The protocol `LocalRunnerChatEngine` implements; `EngineMessage`, `ModelLoadProgress`, `LocalChatEngineError` |
| `Sources/Cribble/Services/LocalLLM/ModelCatalog.swift` | `ModelKind`, `LocalModel`, catalog statics you will extend |
| `Sources/Cribble/Services/LocalLLM/ModelInventory.swift` | `ModelAvailability` enum you will extend |
| `Sources/Cribble/Services/LocalLLM/MLXChatEngine.swift:156-172` | `LocalChatEngineFactory` you will extend; `UnavailableChatEngine` as the minimal engine example |
| `Sources/Cribble/Services/Intelligence/OpenAICompatibleProvider.swift` | Non-streaming HTTP client you reuse (`availableModelIDs`, `generate`, `knownLocalEndpoints`, `extractText`) |
| `Sources/Cribble/Views/ChatHUD/ChatHUDViewModel.swift` | `selectedModel`, `currentEngine()`, `ensureModelReady()`, `ModelDefaultsKey` |
| `Sources/Cribble/Views/IntelligenceHUD/IntelligenceHUDView.swift:362-411` | `configureLocalRunner`/`probeLocalRunner`/`useLocalRunner` — the config UI that will write to the store |
| `Tests/CribbleTests/ChatHUDLogicTests.swift` | Test style, `withCleanEngineChoiceDefaults` pattern |

Conventions: 4-space indent, `///` doc comments explaining *why*, errors as `LocalizedError` enums, `@MainActor` for UI-adjacent state, `@unchecked Sendable` + `NSLock` for engine classes. CHANGELOG.md follows Keep-a-Changelog style (see repo `CHANGELOG.md` head).

---

### Task 1: `LocalRunnerStore` — shared config store

**Files:**
- Create: `Sources/Cribble/Services/LocalLLM/LocalRunnerStore.swift`
- Test: `Tests/CribbleTests/LocalRunnerStoreTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import Cribble

@MainActor
final class LocalRunnerStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "LocalRunnerStoreTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testUnconfiguredByDefault() {
        let store = LocalRunnerStore(defaults: defaults)
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(store.baseURL)
        XCTAssertTrue(store.cachedModelIDs.isEmpty)
    }

    func testConfigurePersistsAcrossInstances() {
        let store = LocalRunnerStore(defaults: defaults)
        store.configure(
            baseURLString: "http://127.0.0.1:11434/v1",
            displayName: "Ollama",
            modelIDs: ["qwen2.5:7b", "llama3.2:3b"],
            defaultModelID: "qwen2.5:7b"
        )
        let reloaded = LocalRunnerStore(defaults: defaults)
        XCTAssertTrue(reloaded.isConfigured)
        XCTAssertEqual(reloaded.baseURL?.absoluteString, "http://127.0.0.1:11434/v1")
        XCTAssertEqual(reloaded.displayName, "Ollama")
        XCTAssertEqual(reloaded.cachedModelIDs, ["qwen2.5:7b", "llama3.2:3b"])
        XCTAssertEqual(reloaded.defaultModelID, "qwen2.5:7b")
    }

    func testMigratesLegacyIntelligenceRunnerURL() {
        // A user who configured a runner via PR #2 (Intelligence-only) must come
        // out configured app-wide without touching anything.
        defaults.set("http://127.0.0.1:11434/v1", forKey: "intelligence.runnerURL")
        defaults.set("qwen2.5:7b", forKey: "intelligence.modelID")
        let store = LocalRunnerStore(defaults: defaults)
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.baseURL?.absoluteString, "http://127.0.0.1:11434/v1")
        XCTAssertEqual(store.defaultModelID, "qwen2.5:7b")
    }

    func testClearRemovesConfig() {
        let store = LocalRunnerStore(defaults: defaults)
        store.configure(baseURLString: "http://127.0.0.1:8080/v1", displayName: "llama.cpp", modelIDs: ["m"], defaultModelID: "m")
        store.clear()
        XCTAssertFalse(store.isConfigured)
        XCTAssertFalse(LocalRunnerStore(defaults: defaults).isConfigured)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter LocalRunnerStoreTests`
Expected: FAIL — `cannot find 'LocalRunnerStore' in scope`

**Step 3: Write the implementation**

```swift
import Foundation

/// App-wide source of truth for the OpenAI-compatible local runner (Ollama,
/// llama.cpp, LM Studio, …). Intelligence, the Chat HUD, Pathfinder, and AI
/// Link Notes all read the same configuration from here, so there is exactly
/// one place to point Cribble at a runner (issue #3).
///
/// Persists under its own keys and migrates the legacy Intelligence-only key
/// (`intelligence.runnerURL`, PR #2) on first read. The legacy key remains
/// owned by `IntelligenceSettings` as "Intelligence currently uses the runner";
/// this store answers the broader "a runner is configured for the app".
@MainActor
final class LocalRunnerStore: ObservableObject {
    static let shared = LocalRunnerStore()

    /// Base URL string, e.g. `http://127.0.0.1:11434/v1`; nil when unconfigured.
    @Published private(set) var baseURLString: String?
    /// Friendly runner name shown in pickers, e.g. "Ollama".
    @Published private(set) var displayName: String?
    /// Model ids last probed from `GET /v1/models`, for instant picker lists.
    @Published private(set) var cachedModelIDs: [String]
    /// The model chosen when the runner was configured — the default for
    /// features without their own model picker (e.g. AI Link Notes).
    @Published private(set) var defaultModelID: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Keys.baseURL) {
            baseURLString = stored
            displayName = defaults.string(forKey: Keys.displayName)
            cachedModelIDs = defaults.stringArray(forKey: Keys.modelIDs) ?? []
            defaultModelID = defaults.string(forKey: Keys.defaultModelID)
        } else if let legacy = defaults.string(forKey: Keys.legacyIntelligenceRunnerURL) {
            // One-time migration from the Intelligence-only configuration.
            baseURLString = legacy
            displayName = nil
            cachedModelIDs = []
            defaultModelID = defaults.string(forKey: Keys.legacyIntelligenceModelID)
            persist()
        } else {
            baseURLString = nil
            displayName = nil
            cachedModelIDs = []
            defaultModelID = nil
        }
    }

    var baseURL: URL? { baseURLString.flatMap(URL.init(string:)) }
    var isConfigured: Bool { baseURL != nil }

    func configure(baseURLString: String, displayName: String?, modelIDs: [String], defaultModelID: String?) {
        self.baseURLString = baseURLString
        self.displayName = displayName
        self.cachedModelIDs = modelIDs
        self.defaultModelID = defaultModelID
        persist()
    }

    func clear() {
        baseURLString = nil
        displayName = nil
        cachedModelIDs = []
        defaultModelID = nil
        persist()
    }

    /// Re-probes `GET /v1/models` and refreshes the cached list. Silent on
    /// failure — the stale cache is still more useful than an empty picker.
    func refreshModels(session: URLSession = .shared) async {
        guard let baseURL else { return }
        guard let models = try? await OpenAICompatibleProvider.availableModelIDs(baseURL: baseURL, session: session) else { return }
        cachedModelIDs = models
        persist()
    }

    private func persist() {
        defaults.set(baseURLString, forKey: Keys.baseURL)
        defaults.set(displayName, forKey: Keys.displayName)
        defaults.set(cachedModelIDs, forKey: Keys.modelIDs)
        defaults.set(defaultModelID, forKey: Keys.defaultModelID)
    }

    private enum Keys {
        static let baseURL = "localRunner.baseURL"
        static let displayName = "localRunner.displayName"
        static let modelIDs = "localRunner.modelIDs"
        static let defaultModelID = "localRunner.defaultModelID"
        static let legacyIntelligenceRunnerURL = "intelligence.runnerURL"
        static let legacyIntelligenceModelID = "intelligence.modelID"
    }
}
```

Note: `defaults.set(nil as String?, forKey:)` removes the key — that is what `clear()` relies on.

**Step 4: Run tests to verify they pass**

Run: `swift test --filter LocalRunnerStoreTests`
Expected: 4 tests PASS

**Step 5: Commit**

```bash
git add Sources/Cribble/Services/LocalLLM/LocalRunnerStore.swift Tests/CribbleTests/LocalRunnerStoreTests.swift
git commit -m "Add LocalRunnerStore: shared app-wide local runner config (issue #3)"
```

---

### Task 2: `.localRunner` ModelKind + dynamic runner models in the catalog

**Files:**
- Modify: `Sources/Cribble/Services/LocalLLM/ModelCatalog.swift`
- Modify: `Sources/Cribble/Services/LocalLLM/ModelInventory.swift`
- Test: `Tests/CribbleTests/ChatHUDLogicTests.swift` (append to `// MARK: - Catalog` section)

**Step 1: Write the failing tests** (append to ChatHUDLogicTests)

```swift
    // MARK: - Local runner catalog entries

    func testRunnerModelIDRoundTrips() {
        let model = LocalModel.runnerModel(modelID: "qwen2.5:7b")
        XCTAssertEqual(model.id, "runner:qwen2.5:7b")
        XCTAssertEqual(model.kind, .localRunner)
        XCTAssertEqual(model.name, "qwen2.5:7b")
        // Resolution is pure — a persisted runner selection resolves even
        // before the store has probed the runner.
        let resolved = ModelCatalog.model(withID: "runner:qwen2.5:7b")
        XCTAssertEqual(resolved?.id, "runner:qwen2.5:7b")
        XCTAssertEqual(resolved?.kind, .localRunner)
    }

    func testRunnerKindIsLocalNotCloud() {
        XCTAssertFalse(ModelKind.localRunner.isCloud)
    }

    func testRunnerAvailabilityIsRunner() {
        let model = LocalModel.runnerModel(modelID: "m")
        if case .runner = ModelInventory.availability(of: model) {} else {
            XCTFail("Expected .runner availability")
        }
    }
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ChatHUDLogicTests/testRunnerModelIDRoundTrips`
Expected: FAIL — `type 'LocalModel' has no member 'runnerModel'`

**Step 3: Implement**

In `ModelCatalog.swift`, extend `ModelKind` (keep `isCloud` correct — a runner is local):

```swift
enum ModelKind: String, Hashable {
    /// On-device Apple MLX model (requires the Metal library; Xcode build).
    case localMLX
    /// Anthropic Claude via the local `claude` CLI (cloud).
    case claudeCLI
    /// OpenAI Codex via the local `codex` CLI (cloud).
    case codexCLI
    /// A model served by the user's OpenAI-compatible local runner
    /// (Ollama, llama.cpp, LM Studio, …) configured in `LocalRunnerStore`.
    case localRunner

    var isCloud: Bool { self == .claudeCLI || self == .codexCLI }
}
```

Add to `LocalModel` (below `shortName`):

```swift
    /// Prefix marking a model served by the local runner; the suffix is the
    /// runner-side model id, so the selection is self-describing and survives
    /// restarts without needing the runner to be reachable.
    static let runnerIDPrefix = "runner:"

    /// A dynamic catalog entry for a model served by the configured runner.
    static func runnerModel(modelID: String) -> LocalModel {
        LocalModel(
            id: runnerIDPrefix + modelID,
            name: modelID,
            speedLabel: "Runner",
            approximateSize: "Local runner",
            blurb: "Served by your OpenAI-compatible local runner.",
            recommendedMemoryGB: 0,
            kind: .localRunner
        )
    }
```

In `ModelCatalog`, add (and update `model(withID:)`):

```swift
    /// Models served by the configured local runner, from the store's cached
    /// `/v1/models` probe. Empty when no runner is configured.
    @MainActor
    static var runnerModels: [LocalModel] {
        LocalRunnerStore.shared.cachedModelIDs.map(LocalModel.runnerModel(modelID:))
    }

    static func model(withID id: String) -> LocalModel? {
        if id.hasPrefix(LocalModel.runnerIDPrefix) {
            let modelID = String(id.dropFirst(LocalModel.runnerIDPrefix.count))
            guard !modelID.isEmpty else { return nil }
            return .runnerModel(modelID: modelID)
        }
        return all.first { $0.id == id }
    }
```

In `ModelInventory.swift`, extend the enum and the check:

```swift
enum ModelAvailability {
    /// Cloud provider — nothing to download.
    case cloud
    /// On-device model already present in the Hugging Face cache.
    case downloaded
    /// On-device model that will download on first use.
    case notDownloaded
    /// Served by the user's local runner — nothing to download.
    case runner
}
```

and in `availability(of:)` (first line):

```swift
        if model.kind == .localRunner { return .runner }
```

**Step 4: Run tests**

Run: `swift test --filter ChatHUDLogicTests`
Expected: all PASS (including the pre-existing catalog tests — `runner:` ids don't collide with `all`).

**Step 5: Commit**

```bash
git add Sources/Cribble/Services/LocalLLM/ModelCatalog.swift Sources/Cribble/Services/LocalLLM/ModelInventory.swift Tests/CribbleTests/ChatHUDLogicTests.swift
git commit -m "Add .localRunner ModelKind with dynamic runner catalog entries"
```

---

### Task 3: `LocalRunnerChatEngine` — streaming SSE engine

**Files:**
- Create: `Sources/Cribble/Services/LocalLLM/LocalRunnerChatEngine.swift`
- Test: `Tests/CribbleTests/LocalRunnerChatEngineTests.swift`

**Step 1: Write the failing tests**

Pure-parsing tests first (no networking), then end-to-end via a `URLProtocol` stub.

```swift
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

        var streamed: [String] = []
        let collector = TokenCollector()
        let full = try await engine.generate(
            messages: [EngineMessage(role: .user, content: "hi")],
            maxTokens: 64
        ) { delta in collector.append(delta) }
        streamed = collector.tokens

        XCTAssertEqual(full, "Hello world")
        XCTAssertEqual(streamed, ["Hello", " world"])
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
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter LocalRunnerChatEngineTests`
Expected: FAIL — `cannot find 'LocalRunnerChatEngine' in scope`

**Step 3: Implement**

```swift
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
            for try await byte in bytes { data.append(byte) }
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

    /// Parses a complete (non-streaming) chat-completions body.
    static func messageText(fromResponseBody data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let choice = choices.first,
            let message = choice["message"] as? [String: Any],
            let text = message["content"] as? String
        else {
            throw LocalChatEngineError.generationFailed("Unexpected response shape from the local runner.")
        }
        return text
    }
}
```

Swift 6 notes for the implementer:
- `URLSession.bytes(for:)` and `.lines` are the async sequence APIs — no delegate needed.
- `lock.withLock { ... }` is `NSLock`'s closure API (already used in `AIService.PipeBuffer`).
- If the compiler rejects `nonisolated(unsafe) static var handler` in the test stub, that exact spelling is required (it is the standard escape hatch for URLProtocol stubs under strict concurrency).

**Step 4: Run tests**

Run: `swift test --filter LocalRunnerChatEngineTests`
Expected: 7 tests PASS

**Step 5: Commit**

```bash
git add Sources/Cribble/Services/LocalLLM/LocalRunnerChatEngine.swift Tests/CribbleTests/LocalRunnerChatEngineTests.swift
git commit -m "Add LocalRunnerChatEngine: streaming SSE chat over the shared runner"
```

---

### Task 4: Wire the engine into factory + Chat HUD view model

**Files:**
- Modify: `Sources/Cribble/Services/LocalLLM/MLXChatEngine.swift:156-172` (`LocalChatEngineFactory`)
- Modify: `Sources/Cribble/Views/ChatHUD/ChatHUDViewModel.swift:400` (`ensureModelReady`)
- Test: `Tests/CribbleTests/ChatHUDLogicTests.swift`

**Step 1: Write the failing tests** (append to ChatHUDLogicTests)

```swift
    // MARK: - Local runner selection (issue #3 acceptance)

    @MainActor
    func testRunnerSelectionPersistsAndDoesNotFallBackToDefault() {
        withCleanEngineChoiceDefaults {
            let runner = LocalModel.runnerModel(modelID: "qwen2.5:7b")
            let first = ChatHUDViewModel(library: MarkdownLibraryStore(restore: false, includeBundledDemo: false))
            first.selectModel(runner)
            XCTAssertEqual(UserDefaults.standard.string(forKey: "chatHUD.selectedModelID"), "runner:qwen2.5:7b")

            // A fresh view model (app relaunch) must restore the runner model,
            // NOT silently fall back to ModelCatalog.defaultModel.
            let recreated = ChatHUDViewModel(library: MarkdownLibraryStore(restore: false, includeBundledDemo: false))
            XCTAssertEqual(recreated.selectedModel.id, "runner:qwen2.5:7b")
            XCTAssertEqual(recreated.selectedModel.kind, .localRunner)
        }
    }

    func testFactoryMakesRunnerEngineForRunnerKind() {
        let engine = LocalChatEngineFactory.make(for: .runnerModel(modelID: "m"))
        XCTAssertTrue(engine is LocalRunnerChatEngine)
    }
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ChatHUDLogicTests/testFactoryMakesRunnerEngineForRunnerKind`
Expected: FAIL — switch over `ModelKind` in factory is not exhaustive (compile error after Task 2 actually surfaces here; if the project already fails to compile, fix the factory as below and re-run)

NOTE: Task 2's new enum case makes every `switch` over `ModelKind` non-exhaustive. The compiler will list them all — they are exactly the ones this task and Task 5 fix. If `swift build` broke at the end of Task 2, that is expected; Tasks 4–5 restore it. Run `swift build 2>&1 | grep "error:"` to enumerate the sites.

**Step 3: Implement**

`LocalChatEngineFactory` in `MLXChatEngine.swift`:

```swift
        case .localRunner:
            return LocalRunnerChatEngine()
```

`ChatHUDViewModel.ensureModelReady()` — the runner never downloads, so it must show the `.loading` phase, not a download bar. Change line 400 from:

```swift
        modelPhase = selectedModel.kind.isCloud ? .loading : .downloading(ModelLoadProgress(fraction: 0))
```

to:

```swift
        // Only on-device MLX models download; cloud CLIs and the local runner
        // just need a (fast) readiness check.
        modelPhase = selectedModel.kind == .localMLX ? .downloading(ModelLoadProgress(fraction: 0)) : .loading
```

**Step 4: Run tests**

Run: `swift test --filter ChatHUDLogicTests`
Expected: all PASS. Also run `swift build` — there may be remaining non-exhaustive switches in views (`ChatModelPicker.dotColor`); if so, fix them now with the Task 5 code (the compiler errors point at the exact lines) and fold them into this commit only if needed to keep the build green — otherwise leave for Task 5.

**Step 5: Commit**

```bash
git add -A Sources/Cribble Tests/CribbleTests/ChatHUDLogicTests.swift
git commit -m "Route .localRunner models through LocalRunnerChatEngine in chat"
```

---

### Task 5: Chat HUD picker UI + first-run chooser

**Files:**
- Modify: `Sources/Cribble/Views/ChatHUD/ChatModelPicker.swift`
- Modify: `Sources/Cribble/Views/ChatHUD/EngineChoiceView.swift`

This task is UI-only (no view-model logic), so it has no unit tests; verification is `swift build` + the manual checklist in Task 9.

**Step 1: `ModelPickerButton.dotColor`** — make the switch exhaustive with a distinct runner color:

```swift
    private var dotColor: Color {
        switch viewModel.selectedModel.kind {
        case .localMLX: .blue
        case .claudeCLI, .codexCLI: .green
        case .localRunner: .orange
        }
    }
```

**Step 2: `ModelPickerList`** — add a LOCAL RUNNER section between ON-DEVICE and CLOUD, listing the store's cached models, refreshed on appear. Replace the `body` with:

```swift
    @ObservedObject private var runnerStore = LocalRunnerStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            section(title: "ON-DEVICE", models: ModelCatalog.localModels)
            if runnerStore.isConfigured, !ModelCatalog.runnerModels.isEmpty {
                Divider().padding(.vertical, 4)
                section(
                    title: "LOCAL RUNNER" + (runnerStore.displayName.map { " — \($0.uppercased())" } ?? ""),
                    models: ModelCatalog.runnerModels
                )
            }
            if !ModelCatalog.cloudModels.isEmpty {
                Divider().padding(.vertical, 4)
                section(title: "CLOUD", models: ModelCatalog.cloudModels)
            }

            Divider().padding(.vertical, 4)
            Text("On-device models download once (~1–3 GB); tap ↓ to download. Local runner models are served by your configured runner (set up in the Intelligence HUD). Cloud models (Claude/Codex) use the sessions already logged in your Terminal.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .frame(width: 264, alignment: .leading)
        }
        .padding(8)
        .frame(width: 284)
        .task { await runnerStore.refreshModels() }
    }
```

(`@ObservedObject` on the shared store is the repo's pattern for singleton observation; `private var runnerStore` with a default value is fine because `LocalRunnerStore.shared` is `@MainActor` and views are too.)

**Step 3: `ModelRow.trailing`** — handle the new availability case:

```swift
            case .runner:
                Image(systemName: "network").foregroundStyle(.orange)
                    .help("Served by your local runner")
```

**Step 4: `EngineChoiceView`** — offer the runner on first run when one is configured. Add after the on-device card (inside the `VStack(spacing: 10)`):

```swift
                if LocalRunnerStore.shared.isConfigured,
                   let runnerModelID = LocalRunnerStore.shared.defaultModelID {
                    EngineOptionCard(
                        title: "Local runner (\(LocalRunnerStore.shared.displayName ?? "OpenAI-compatible"))",
                        subtitle: "Private — uses \(runnerModelID) served by the runner already configured for Intelligence.",
                        systemImage: "network",
                        badge: nil,
                        isEnabled: true
                    ) {
                        viewModel.chooseEngine(.runnerModel(modelID: runnerModelID))
                    }
                }
```

**Step 5: Build & commit**

Run: `swift build`
Expected: compiles with no warnings about non-exhaustive switches.

```bash
git add Sources/Cribble/Views/ChatHUD/ChatModelPicker.swift Sources/Cribble/Views/ChatHUD/EngineChoiceView.swift
git commit -m "Surface local runner models in chat picker and first-run chooser"
```

---

### Task 6: Intelligence HUD writes through the store

**Files:**
- Modify: `Sources/Cribble/Views/IntelligenceHUD/IntelligenceHUDView.swift:400-411` (`useLocalRunner`)

The Intelligence HUD's runner panel stays the app's single config surface. When the user taps "Use", it must now also publish the config app-wide.

**Step 1: Implement** — in `useLocalRunner()`, after `await engine.setLocalRunner(baseURL: baseURL, model: modelID)` add:

```swift
        // Publish the runner app-wide: chat, Pathfinder, and AI Link Notes all
        // resolve the runner from this store (issue #3 — one config surface).
        LocalRunnerStore.shared.configure(
            baseURLString: baseURL,
            displayName: localRunnerName == "Custom" ? nil : localRunnerName,
            modelIDs: localRunnerModelIDs,
            defaultModelID: modelID
        )
```

**Step 2: Build, spot-check, commit**

Run: `swift build && swift test --filter LocalRunnerStoreTests`
Expected: PASS

```bash
git add Sources/Cribble/Views/IntelligenceHUD/IntelligenceHUDView.swift
git commit -m "Publish runner config app-wide when set from the Intelligence HUD"
```

---

### Task 7: AIService runner path (AI Link Notes / README fill)

**Files:**
- Modify: `Sources/Cribble/Services/AIService.swift`
- Modify: `Sources/Cribble/Views/AIProviderSheet.swift`
- Modify: `Sources/Cribble/Views/PathfinderSheet.swift:158-181` (menu) — runner section + CLI filter
- Test: `Tests/CribbleTests/AIServiceRunnerTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import Cribble

final class AIServiceRunnerTests: XCTestCase {

    // MARK: - Vault context assembly (pure given a temp folder)

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
        let service = AIService(runnerConfigOverride: .some(nil))
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
            runnerConfigOverride: .some(AIService.RunnerConfig(
                baseURL: URL(string: "http://stub.local/v1")!,
                modelID: "qwen2.5:7b"
            )),
            session: StubURLProtocol.session()
        )
        let parsed = try await service.generateLinkPatch(provider: .localRunner, mode: .suggestLinks, folderURL: dir)
        XCTAssertEqual(parsed.files.first?.newPath, "Note.md")
    }
}
```

(`StubURLProtocol` is the one from Task 3's test file — it is `internal` in the test target, so it is visible here.)

**Step 2: Run tests to verify they fail**

Run: `swift test --filter AIServiceRunnerTests`
Expected: FAIL — `AIProvider` has no member `localRunner`, `AIService` has no such initializer

**Step 3: Implement in `AIService.swift`**

Extend the provider enum (and keep CLI loops in views working via `cliProviders`):

```swift
enum AIProvider: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claude = "Claude"
    case localRunner = "Local Runner"

    var id: String { rawValue }

    /// The CLI-spawning providers (the runner is HTTP, not a CLI).
    static var cliProviders: [AIProvider] { [.codex, .claude] }

    var lowestModelName: String {
        switch self {
        case .codex: "gpt-5.5"
        case .claude: "haiku"
        case .localRunner: "" // model comes from LocalRunnerStore
        }
    }
}
```

Give `AIService` injectable runner config + session (default behavior unchanged):

```swift
struct AIService {
    /// Resolved runner endpoint + model for the `.localRunner` provider.
    struct RunnerConfig: Sendable {
        let baseURL: URL
        let modelID: String
    }

    /// Test hook: `.some(config)` / `.some(nil)` bypasses LocalRunnerStore.
    private let runnerConfigOverride: RunnerConfig??
    private let session: URLSession

    init(runnerConfigOverride: RunnerConfig?? = nil, session: URLSession = .shared) {
        self.runnerConfigOverride = runnerConfigOverride
        self.session = session
    }

    @MainActor
    private func resolveRunnerConfig() -> RunnerConfig? {
        if let runnerConfigOverride { return runnerConfigOverride }
        let store = LocalRunnerStore.shared
        guard let baseURL = store.baseURL,
              let modelID = store.defaultModelID ?? store.cachedModelIDs.first
        else { return nil }
        return RunnerConfig(baseURL: baseURL, modelID: modelID)
    }
```

Add the vault-context builder (the CLI providers read files themselves; an HTTP runner only sees the prompt, so the folder must be inlined — smallest-first so many small notes beat one huge one):

```swift
    /// Concatenates the folder's Markdown files (smallest first) into a
    /// fenced context block, stopping at `maxCharacters`. Smallest-first
    /// packs the most files into the budget.
    static func vaultContext(folderURL: URL, maxCharacters: Int) -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return "" }

        var files: [(path: String, size: Int, url: URL)] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            let relative = url.path.replacingOccurrences(of: folderURL.path + "/", with: "")
            files.append((relative, size, url))
        }
        files.sort { $0.size < $1.size }

        var sections: [String] = []
        var remaining = maxCharacters
        for file in files {
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            let section = "=== \(file.path) ===\n\(content)\n"
            guard section.count <= remaining else { continue }
            remaining -= section.count
            sections.append(section)
        }
        return sections.joined(separator: "\n")
    }
```

Add a runner generation helper and route both public methods through it. In `generateLinkPatch`, add the case:

```swift
        case .localRunner:
            output = try await runViaLocalRunner(prompt: prompt, folderURL: folderURL)
```

and in `explainRelationship`:

```swift
        case .localRunner:
            return try await runViaLocalRunner(prompt: prompt, folderURL: folderURL)
```

with:

```swift
    /// Sends `prompt` (plus inlined vault context, since an HTTP runner can't
    /// read the folder like the CLIs do) to the configured local runner via
    /// the same OpenAI-compatible client Intelligence uses.
    private func runViaLocalRunner(prompt: String, folderURL: URL) async throws -> String {
        guard let config = await resolveRunnerConfig() else {
            throw AIServiceError.commandFailed(
                "No local runner is configured. Set one up from the Intelligence HUD's model menu, then try again."
            )
        }
        let context = Self.vaultContext(folderURL: folderURL, maxCharacters: 32_000)
        let provider = OpenAICompatibleProvider(
            baseURL: config.baseURL,
            model: config.modelID,
            session: session
        )
        let messages = [
            EngineMessage(role: .system, content: prompt),
            EngineMessage(role: .user, content: "<vault>\n\(context)\n</vault>")
        ]
        do {
            return try await provider.generate(prompt: messages, schema: nil, maxTokens: 2_048)
        } catch {
            throw AIServiceError.commandFailed(error.localizedDescription)
        }
    }
```

Concurrency note: `generateLinkPatch`/`explainRelationship` are not actor-isolated; `resolveRunnerConfig()` is `@MainActor`, hence the `await`.

**Step 4: Implement in `AIProviderSheet.swift`** — show the runner button only when configured. Replace the provider `HStack` loop source:

```swift
            HStack(spacing: 12) {
                ForEach(availableProviders) { provider in
                    Button {
                        onSelect(provider, mode)
                    } label: {
                        Label(provider.rawValue, systemImage: icon(for: provider))
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .cribbleGlassButton(prominent: true)
                    .help(help(for: provider))
                }
            }
```

with helpers in the struct:

```swift
    private var availableProviders: [AIProvider] {
        LocalRunnerStore.shared.isConfigured ? AIProvider.allCases : AIProvider.cliProviders
    }

    private func icon(for provider: AIProvider) -> String {
        switch provider {
        case .codex: "terminal"
        case .claude: "brain.head.profile"
        case .localRunner: "network"
        }
    }

    private func help(for provider: AIProvider) -> String {
        provider == .localRunner
            ? "Run your configured local runner for: \(mode.title)"
            : "Run \(provider.rawValue) locally for: \(mode.title)"
    }
```

**Step 5: Implement in `PathfinderSheet.swift`** — the explanation menu gains a runner section, and the Cloud section must stop iterating `allCases` (which now includes the runner). Replace lines 158-173's menu content with:

```swift
                Menu {
                    let downloaded = ModelCatalog.localModels.filter { ModelInventory.isDownloaded($0) }
                    Section("On-device") {
                        if downloaded.isEmpty {
                            Button("Download a model in Cribble AI first") {}.disabled(true)
                        } else {
                            ForEach(downloaded) { model in
                                Button(model.name) { explainLocally(model: model) }
                            }
                        }
                    }
                    if LocalRunnerStore.shared.isConfigured {
                        Section("Local runner") {
                            ForEach(ModelCatalog.runnerModels) { model in
                                Button(model.name) { explainLocally(model: model) }
                            }
                        }
                    }
                    Section("Cloud") {
                        ForEach(AIProvider.cliProviders) { provider in
                            Button(provider.rawValue) { explain(with: provider) }
                        }
                    }
                } label: {
```

(`explainLocally(model:)` already goes through `LocalLLM.shared.engine(for:)` → with Task 4 it transparently handles `.localRunner` models. No other change needed.)

**Step 6: Run tests**

Run: `swift test --filter AIServiceRunnerTests && swift build`
Expected: 4 tests PASS, clean build

**Step 7: Commit**

```bash
git add Sources/Cribble/Services/AIService.swift Sources/Cribble/Views/AIProviderSheet.swift Sources/Cribble/Views/PathfinderSheet.swift Tests/CribbleTests/AIServiceRunnerTests.swift
git commit -m "Add local runner provider to AI Link Notes, README fill, and Pathfinder"
```

---

### Task 8: Docs — entry-point audit table, READMEs, CHANGELOG

**Files:**
- Modify: `Sources/Cribble/Services/LocalLLM/README.md`
- Modify: `CHANGELOG.md`

**Step 1:** Append to `Sources/Cribble/Services/LocalLLM/README.md` a section:

```markdown
## Local runner support (issue #3)

`LocalRunnerStore` is the app-wide source of truth for the OpenAI-compatible
runner (Ollama, llama.cpp, LM Studio, …). Configure it once from the
Intelligence HUD's model menu; every eligible AI feature resolves it from the
store.

| AI entry point | Runner support | Path |
|---|---|---|
| Chat HUD | Supported | `ModelKind.localRunner` → `LocalRunnerChatEngine` (streaming SSE) |
| Quick actions (slash commands) | Supported | inherits chat's selected engine |
| Attachment digestion | Supported | inherits chat's selected engine |
| Pathfinder explanation | Supported | runner section in the model menu |
| AI Link Notes / README fill | Supported | `AIProvider.localRunner` → `OpenAICompatibleProvider` with inlined vault context |
| First-run engine chooser | Supported | runner card shown when configured |
| Intelligence jobs | Supported (PR #2) | `OpenAICompatibleProvider` |
| Semantic search / embeddings | Intentionally unsupported | on-device embedding index, not a generative path |
```

**Step 2:** Add a CHANGELOG entry under the current unreleased/next heading, matching the existing entry style:

```markdown
- Local runner (Ollama/llama.cpp/LM Studio) support now extends beyond
  Intelligence to the Chat HUD (with streaming), quick actions, attachment
  digests, Pathfinder explanations, AI Link Notes, and the first-run engine
  chooser — all resolved from one shared configuration (#3).
```

**Step 3: Commit**

```bash
git add Sources/Cribble/Services/LocalLLM/README.md CHANGELOG.md
git commit -m "Document app-wide local runner support and entry-point audit"
```

---

### Task 9: Full verification

**Step 1:** Run the complete suite:

Run: `swift test`
Expected: all tests PASS (the suite includes UI-adjacent tests; they run headless fine).

**Step 2:** Build the app and manually verify (requires Ollama or any runner locally; if none is installed, `ollama serve` + `ollama pull qwen2.5:0.5b` is the fastest setup):

Run: `./script/build_and_run.sh` (repo's run script)

Manual checklist:
1. Intelligence HUD → model menu → LOCAL RUNNER → pick/configure runner → "Use".
2. Open Chat HUD → model chip popover shows a "LOCAL RUNNER" section listing the runner's models; pick one — chip dot turns orange, chip shows the model id.
3. Send a chat message → answer streams token-by-token.
4. Type `/` → run "Summarize" → uses the runner (watch `ollama ps` or runner logs).
5. Stop the runner (`pkill ollama`) → send a message → clear error in chat ("Can't reach the local runner…"), NO silent fallback to another model.
6. Right-click a folder → AI Link Notes → sheet shows "Local Runner" button → produces a diff preview.
7. Drag one note onto another → Pathfinder → "Explain the connection" menu shows the "Local runner" section → explanation works.
8. Quit and relaunch → chat still has the runner model selected.

**Step 3:** Re-read the issue's acceptance criteria and confirm each:
- [ ] Chat HUD uses configured local runner incl. Ollama `/v1/chat/completions` — Tasks 3-5
- [ ] Model/provider UI shows which runner/model is active — Task 5 (chip + picker section)
- [ ] All AI entry points audited & documented — Task 8 table
- [ ] Tests cover runner selection for Chat HUD + one non-Intelligence action — Tasks 4 & 7

**Step 4:** Use superpowers:verification-before-completion, then superpowers:finishing-a-development-branch (PR targets `adidshaft/cribble`, base branch `cribble-intelligence`, referencing issue #3).
