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
        XCTAssertTrue(summary.detail.contains("may leave this Mac"))
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
    }
}
