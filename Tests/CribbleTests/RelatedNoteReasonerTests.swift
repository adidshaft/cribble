import XCTest
@testable import Cribble

@MainActor
final class RelatedNoteReasonerTests: XCTestCase {
    func testCleanReturnsSingleBoundedLine() {
        let cleaned = RelatedNoteReasoner.clean("  These notes\n\nshare   a planning thread.  ")
        XCTAssertEqual(cleaned, "These notes share a planning thread.")
    }

    func testMessagesBoundInputAndAskForOneSentence() {
        let longText = String(repeating: "a", count: RelatedNoteReasoner.inputCharacterLimit + 20)
        let messages = RelatedNoteReasoner.messages(
            modelName: "Local",
            sourceTitle: "Source",
            sourceText: longText,
            relatedTitle: "Related",
            relatedText: longText
        )

        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[0].content.contains("one plain sentence"))
        XCTAssertTrue(messages[1].content.contains("Current note: Source"))
        XCTAssertTrue(messages[1].content.contains("Related note: Related"))
        XCTAssertFalse(messages[1].content.contains(String(repeating: "a", count: RelatedNoteReasoner.inputCharacterLimit + 1)))
    }

    func testAvailableLocalModelDoesNotReturnCloudOrUndownloadedFallback() {
        let entitlement = LLMEntitlementStore()
        let model = RelatedNoteReasoner.availableLocalModel(entitlement: entitlement)

        if let model {
            XCTAssertEqual(model.kind, .localMLX)
            XCTAssertEqual(ModelInventory.availability(of: model), .downloaded)
        } else {
            XCTAssertFalse(ModelCatalog.isOnDeviceAvailable)
        }
    }
}
