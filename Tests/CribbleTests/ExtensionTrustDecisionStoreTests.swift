import Foundation
import Testing
@testable import Cribble

struct ExtensionTrustDecisionStoreTests {
    @Test
    func recordsApproveRevokeAndClear() throws {
        let fixture = try Fixture()
        let store = ExtensionTrustDecisionStore(defaults: fixture.defaults)
        let manifest = Self.manifest()

        #expect(store.decision(for: manifest) == nil)

        store.approve(manifest, at: Date(timeIntervalSince1970: 100))
        #expect(store.decision(for: manifest) == .approved)

        store.revoke(manifest, at: Date(timeIntervalSince1970: 200))
        #expect(store.decision(for: manifest) == .revoked)

        store.clearDecision(for: manifest)
        #expect(store.decision(for: manifest) == nil)
    }

    @Test
    func normalizesDecisionKeys() {
        #expect(
            ExtensionTrustDecisionRecord.key(
                extensionID: " COM.EXAMPLE.CRIBBLE.TOOL ",
                signingIdentifier: " COM.EXAMPLE.CRIBBLE.SIGNED ",
                teamIdentifier: " abcde12345 "
            ) == "com.example.cribble.tool|com.example.cribble.signed|ABCDE12345"
        )
    }

    @Test
    func prunesDecisionsForMissingTrustIdentities() throws {
        let fixture = try Fixture()
        let store = ExtensionTrustDecisionStore(defaults: fixture.defaults)
        let kept = Self.manifest(id: "com.example.cribble.keep")
        let stale = Self.manifest(id: "com.example.cribble.stale")

        store.approve(kept)
        store.revoke(stale)
        store.prune(toInstalledManifests: [kept])

        #expect(store.decision(for: kept) == .approved)
        #expect(store.decision(for: stale) == nil)
    }

    private static func manifest(id: String = "com.example.cribble.tool") -> CribbleExtensionManifest {
        CribbleExtensionManifest(
            id: id,
            name: "Trusted Tool",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Declares trust metadata.",
            trust: CribbleExtensionTrustDeclaration(
                developerName: "Example Team",
                signingIdentifier: "com.example.cribble.signed-tool",
                teamIdentifier: "ABCDE12345",
                sourceURL: URL(string: "https://example.com/source")!
            )
        )
    }

    private final class Fixture {
        /// In-memory (see `EphemeralDefaults`): persistent test suites leaked
        /// stub plists into ~/Library/Preferences on every run.
        let defaults: UserDefaults

        init() throws {
            defaults = EphemeralDefaults()
        }
    }
}
