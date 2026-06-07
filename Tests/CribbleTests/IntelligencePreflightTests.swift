import XCTest
@testable import Cribble

final class IntelligencePreflightTests: XCTestCase {
    func testRemoteRunnerSummaryIncludesEndpointModelAndTrustLabel() {
        let profile = ExtensionIntelligenceProviderProfile(
            id: "com.example.runner.research-gpu",
            title: "Research GPU",
            baseURL: URL(string: "https://ai.example.com/v1")!,
            modelID: "qwen3-32b",
            embeddingModelID: "text-embedding-3-small",
            trustLabel: "Team-controlled VPS",
            sourceName: "Team Runner"
        )

        let summary = IntelligencePreflightRunnerSummary.current(
            runnerURL: "https://ai.example.com/v1",
            modelID: "qwen3-32b",
            onDeviceModelLabel: "Local",
            extensionProfiles: [profile]
        )

        XCTAssertTrue(summary.isRemote)
        XCTAssertEqual(summary.title, "Remote runner selected")
        XCTAssertTrue(summary.detail.contains("Endpoint: ai.example.com"))
        XCTAssertTrue(summary.detail.contains("Model: qwen3-32b"))
        XCTAssertTrue(summary.detail.contains("Trust: Team-controlled VPS"))
        XCTAssertEqual(
            summary.dataBoundaryDetail,
            "Prompts, note excerpts, generated summaries, and embedding requests may leave this Mac for the selected runner."
        )
    }

    func testRemoteRunnerSummaryMatchesExtensionProfileByURLAndModel() {
        let wrongModel = ExtensionIntelligenceProviderProfile(
            id: "com.example.runner.small",
            title: "Small GPU",
            baseURL: URL(string: "https://ai.example.com/v1")!,
            modelID: "qwen3-14b",
            embeddingModelID: nil,
            trustLabel: "Wrong trust label",
            sourceName: "Small Runner"
        )
        let rightModel = ExtensionIntelligenceProviderProfile(
            id: "com.example.runner.large",
            title: "Large GPU",
            baseURL: URL(string: "https://ai.example.com/v1")!,
            modelID: "qwen3-32b",
            embeddingModelID: nil,
            trustLabel: "Approved large runner",
            sourceName: "Large Runner"
        )

        let summary = IntelligencePreflightRunnerSummary.current(
            runnerURL: "https://ai.example.com/v1",
            modelID: "qwen3-32b",
            onDeviceModelLabel: "Local",
            extensionProfiles: [wrongModel, rightModel]
        )

        XCTAssertTrue(summary.detail.contains("Trust: Approved large runner"))
        XCTAssertFalse(summary.detail.contains("Wrong trust label"))
    }

    func testExtensionRunnerHandoffNamesTrustAndRevocationPath() {
        let profile = ExtensionIntelligenceProviderProfile(
            id: "com.example.runner.research-gpu",
            title: "Research GPU",
            baseURL: URL(string: "https://ai.example.com/v1")!,
            modelID: "qwen3-32b",
            embeddingModelID: "text-embedding-3-small",
            trustLabel: "Team-controlled VPS",
            sourceName: "Team Runner"
        )

        let handoff = profile.handoffSummary

        XCTAssertTrue(handoff.contains("Endpoint: https://ai.example.com/v1"))
        XCTAssertTrue(handoff.contains("Model: qwen3-32b"))
        XCTAssertTrue(handoff.contains("Embeddings: text-embedding-3-small"))
        XCTAssertTrue(handoff.contains("Trust label: Team-controlled VPS"))
        XCTAssertTrue(handoff.contains("note context may leave this Mac"))
        XCTAssertTrue(handoff.contains("store in Keychain"))
        XCTAssertTrue(handoff.contains("Disable/revoke"))
    }

    func testOnDeviceSummaryStaysLocal() {
        let summary = IntelligencePreflightRunnerSummary.current(
            runnerURL: nil,
            modelID: "unused",
            onDeviceModelLabel: "Qwen 3",
            extensionProfiles: []
        )

        XCTAssertFalse(summary.isRemote)
        XCTAssertEqual(summary.title, "Local processing")
        XCTAssertTrue(summary.detail.contains("Qwen 3"))
        XCTAssertTrue(summary.detail.contains("app support cache"))
        XCTAssertNil(summary.dataBoundaryDetail)
    }

    func testExtensionRunnerConsentStoreRequiresApprovalForRemoteProfiles() {
        let suiteName = "ExtensionRunnerConsentStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profile = ExtensionIntelligenceProviderProfile(
            id: "com.example.runner.research-gpu",
            title: "Research GPU",
            baseURL: URL(string: "https://ai.example.com/v1")!,
            modelID: "qwen3-32b",
            embeddingModelID: nil,
            trustLabel: "Team-controlled VPS",
            sourceName: "Team Runner"
        )
        let changedModel = ExtensionIntelligenceProviderProfile(
            id: profile.id,
            title: profile.title,
            baseURL: profile.baseURL,
            modelID: "qwen3-14b",
            embeddingModelID: nil,
            trustLabel: profile.trustLabel,
            sourceName: profile.sourceName
        )
        let store = ExtensionRunnerConsentStore(defaults: defaults)

        XCTAssertFalse(store.hasApproved(profile))
        store.approve(profile)
        XCTAssertTrue(store.hasApproved(profile))
        XCTAssertFalse(store.hasApproved(changedModel))
        XCTAssertNil(store.requiredApprovalProfile(
            runnerURL: profile.baseURL.absoluteString,
            modelID: profile.modelID,
            profiles: [profile]
        ))
        XCTAssertEqual(store.requiredApprovalProfile(
            runnerURL: changedModel.baseURL.absoluteString,
            modelID: changedModel.modelID,
            profiles: [changedModel]
        ), changedModel)
    }

    func testExtensionRunnerConsentStoreApprovesLoopbackProfiles() {
        let suiteName = "ExtensionRunnerLoopbackConsentStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profile = ExtensionIntelligenceProviderProfile(
            id: "com.example.runner.local",
            title: "Local Runner",
            baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
            modelID: "llama3.2",
            embeddingModelID: nil,
            trustLabel: "Local runner",
            sourceName: "Local Runner Extension"
        )

        XCTAssertTrue(ExtensionRunnerConsentStore(defaults: defaults).hasApproved(profile))
    }
}
