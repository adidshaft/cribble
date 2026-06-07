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
        StubURLProtocol.handler = nil
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
        // The migrated model seeds the cache so pickers have something to show.
        XCTAssertEqual(store.cachedModelIDs, ["qwen2.5:7b"])
    }

    func testConfigureSeedsCacheWithDefaultModelWhenListEmpty() {
        // A manually-typed model ID (runner reachable but /v1/models empty)
        // must still surface in pickers.
        let store = LocalRunnerStore(defaults: defaults)
        store.configure(baseURLString: "http://127.0.0.1:11434/v1", displayName: nil, modelIDs: [], defaultModelID: "typed-model")
        XCTAssertEqual(store.cachedModelIDs, ["typed-model"])
    }

    func testConfigureNormalizesEmptyDisplayName() {
        let store = LocalRunnerStore(defaults: defaults)
        store.configure(baseURLString: "http://127.0.0.1:11434/v1", displayName: "", modelIDs: ["m"], defaultModelID: "m")
        XCTAssertNil(store.displayName)
        store.configure(baseURLString: "http://127.0.0.1:11434/v1", displayName: "  ", modelIDs: ["m"], defaultModelID: "m")
        XCTAssertNil(store.displayName)
    }

    func testClearSurvivesRelaunchDespiteLegacyKey() {
        // clear() must stick even though IntelligenceSettings still has the
        // legacy runner key — migration is one-shot, not on every launch.
        defaults.set("http://127.0.0.1:11434/v1", forKey: "intelligence.runnerURL")
        defaults.set("qwen2.5:7b", forKey: "intelligence.modelID")
        let migrated = LocalRunnerStore(defaults: defaults)
        XCTAssertTrue(migrated.isConfigured)
        migrated.clear()
        XCTAssertFalse(LocalRunnerStore(defaults: defaults).isConfigured)
    }

    func testRefreshModelsUpdatesAndPersistsCache() async {
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"data":[{"id":"b"},{"id":"a"}]}"#.utf8))
        }
        let store = LocalRunnerStore(defaults: defaults)
        store.configure(baseURLString: "http://stub.local/v1", displayName: nil, modelIDs: ["old"], defaultModelID: "old")
        await store.refreshModels(session: StubURLProtocol.session())
        XCTAssertEqual(store.cachedModelIDs, ["a", "b"], "probe results are sorted")
        // Persisted: a fresh instance sees the refreshed list.
        XCTAssertEqual(LocalRunnerStore(defaults: defaults).cachedModelIDs, ["a", "b"])
    }

    func testRefreshModelsKeepsStaleCacheOnFailure() async {
        StubURLProtocol.handler = { _ in (500, [:], Data()) }
        let store = LocalRunnerStore(defaults: defaults)
        store.configure(baseURLString: "http://stub.local/v1", displayName: nil, modelIDs: ["stale"], defaultModelID: "stale")
        await store.refreshModels(session: StubURLProtocol.session())
        // Silent-on-failure by design: the stale cache beats an empty picker.
        XCTAssertEqual(store.cachedModelIDs, ["stale"])
    }

    func testClearRemovesConfig() {
        let store = LocalRunnerStore(defaults: defaults)
        store.configure(baseURLString: "http://127.0.0.1:8080/v1", displayName: "llama.cpp", modelIDs: ["m"], defaultModelID: "m")
        store.clear()
        XCTAssertFalse(store.isConfigured)
        XCTAssertFalse(LocalRunnerStore(defaults: defaults).isConfigured)
    }
}
