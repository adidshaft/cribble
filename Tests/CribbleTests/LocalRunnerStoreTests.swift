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
