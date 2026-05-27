import XCTest
@testable import Cribble

@MainActor
final class ReadingAnnotationsStoreTests: XCTestCase {
    func testPersistsBookmarksAndHighlights() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directory.appendingPathComponent("ReadingAnnotations.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let documentURL = directory.appendingPathComponent("Note.md").standardizedFileURL
        try "# Note\n\n".write(to: documentURL, atomically: true, encoding: .utf8)

        let store = ReadingAnnotationsStore(fileURL: storeURL)
        store.dropBookmark(for: documentURL, offsetY: 128.5, sectionTitle: "Middle")
        store.addHighlight(for: documentURL, quote: "important sentence", note: "Revisit this")

        let restored = ReadingAnnotationsStore(fileURL: storeURL)
        XCTAssertEqual(restored.bookmark(for: documentURL)?.scrollOffsetY, 128.5)
        XCTAssertEqual(restored.bookmark(for: documentURL)?.sectionTitle, "Middle")
        XCTAssertEqual(restored.highlights(for: documentURL).map(\.quote), ["important sentence"])
        XCTAssertEqual(restored.highlights(for: documentURL).map(\.note), ["Revisit this"])
    }

    func testUpdatesHighlightNoteBySelectedQuote() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directory.appendingPathComponent("ReadingAnnotations.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let documentURL = directory.appendingPathComponent("Note.md").standardizedFileURL

        let store = ReadingAnnotationsStore(fileURL: storeURL)
        store.addHighlight(for: documentURL, quote: "important sentence with context", note: "")

        XCTAssertTrue(store.updateHighlightNote(for: documentURL, matching: "important sentence", note: "Ask about this"))
        XCTAssertEqual(store.highlight(for: documentURL, matching: "important sentence")?.note, "Ask about this")

        let restored = ReadingAnnotationsStore(fileURL: storeURL)
        XCTAssertEqual(restored.highlights(for: documentURL).first?.note, "Ask about this")
    }

    func testHighlightActionsDoNotDuplicateAndCanRemoveBySelectedQuote() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directory.appendingPathComponent("ReadingAnnotations.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let documentURL = directory.appendingPathComponent("Note.md").standardizedFileURL

        let store = ReadingAnnotationsStore(fileURL: storeURL)
        store.addHighlight(for: documentURL, quote: "important sentence with context", note: "")
        store.addHighlight(for: documentURL, quote: "important sentence", note: "")
        store.addHighlight(for: documentURL, quote: "important sentence", note: "Ask about this")

        XCTAssertEqual(store.highlights(for: documentURL).count, 1)
        XCTAssertEqual(store.highlight(for: documentURL, matching: "important sentence")?.note, "Ask about this")
        XCTAssertTrue(store.removeHighlight(for: documentURL, matching: "important sentence"))
        XCTAssertTrue(store.highlights(for: documentURL).isEmpty)

        let restored = ReadingAnnotationsStore(fileURL: storeURL)
        XCTAssertTrue(restored.highlights(for: documentURL).isEmpty)
    }

    func testUpdatesHighlightNoteByIDWhenQuotesRepeat() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directory.appendingPathComponent("ReadingAnnotations.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let documentURL = directory.appendingPathComponent("Note.md").standardizedFileURL
        let store = ReadingAnnotationsStore(fileURL: storeURL)

        let first = store.addHighlight(
            for: documentURL,
            quote: "repeat",
            note: "",
            anchor: HighlightAnchor(sectionAnchor: "a", blockIndex: 0, blockSignature: "one", startOffset: 0, length: 6)
        )
        let second = store.addHighlight(
            for: documentURL,
            quote: "repeat",
            note: "",
            anchor: HighlightAnchor(sectionAnchor: "a", blockIndex: 0, blockSignature: "one", startOffset: 12, length: 6)
        )

        XCTAssertNotEqual(first?.id, second?.id)
        XCTAssertTrue(store.updateHighlightNote(id: second!.id, in: documentURL, note: "second only"))

        let highlights = store.highlights(for: documentURL)
        XCTAssertEqual(highlights.first(where: { $0.id == first?.id })?.note, "")
        XCTAssertEqual(highlights.first(where: { $0.id == second?.id })?.note, "second only")
    }
}
