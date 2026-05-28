import XCTest
@testable import Cribble

@MainActor
final class ReadingTrailStoreTests: XCTestCase {
    private func url(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CribbleTrailTests", isDirectory: true)
            .appendingPathComponent(name)
            .standardizedFileURL
    }

    func testRecordsLinearChainWithDepths() {
        let store = ReadingTrailStore()
        store.recordVisit(url: url("A.md"), title: "A")
        store.recordVisit(url: url("B.md"), title: "B")
        store.recordVisit(url: url("C.md"), title: "C")

        let ordered = store.orderedNodes
        XCTAssertEqual(ordered.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(ordered.map(\.depth), [0, 1, 2])
    }

    func testGoingBackToAncestorCreatesBranch() {
        let store = ReadingTrailStore()
        store.recordVisit(url: url("A.md"), title: "A")
        store.recordVisit(url: url("B.md"), title: "B")
        store.recordVisit(url: url("C.md"), title: "C")
        // Navigate back up to A, then off in a new direction.
        store.recordVisit(url: url("A.md"), title: "A")
        store.recordVisit(url: url("D.md"), title: "D")

        let ordered = store.orderedNodes
        // Preorder DFS of the tree A( B(C), D ).
        XCTAssertEqual(ordered.map(\.title), ["A", "B", "C", "D"])

        let d = try? XCTUnwrap(ordered.first { $0.title == "D" })
        XCTAssertEqual(d?.depth, 1, "D should branch from A, not continue the chain")
        // No duplicate A node was created when navigating back.
        XCTAssertEqual(store.nodes.filter { $0.title == "A" }.count, 1)
    }

    func testRevisitingChildDoesNotDuplicate() {
        let store = ReadingTrailStore()
        store.recordVisit(url: url("A.md"), title: "A")
        store.recordVisit(url: url("B.md"), title: "B")
        store.recordVisit(url: url("A.md"), title: "A") // back to A
        store.recordVisit(url: url("B.md"), title: "B") // re-enter existing child B

        XCTAssertEqual(store.nodes.count, 2)
        let b = store.nodes.first { $0.title == "B" }
        XCTAssertEqual(b?.visitCount, 2)
    }

    func testEmptyTrailHasNoNote() {
        let store = ReadingTrailStore()
        let annotations = ReadingAnnotationsStore(fileURL: url("annotations-empty.json"))
        XCTAssertNil(store.makeTrailNote(annotations: annotations))
    }

    func testTrailNoteIncludesPathAndHighlights() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let aURL = directory.appendingPathComponent("A.md").standardizedFileURL
        let bURL = directory.appendingPathComponent("B.md").standardizedFileURL

        let annotations = ReadingAnnotationsStore(fileURL: directory.appendingPathComponent("annotations.json"))
        annotations.addHighlight(for: bURL, quote: "a key idea", note: "remember this")

        let store = ReadingTrailStore()
        store.recordVisit(url: aURL, title: "A")
        store.recordVisit(url: bURL, title: "B")

        let note = try XCTUnwrap(store.makeTrailNote(annotations: annotations))
        XCTAssertEqual(note.fileName, "Trail - A.md")
        XCTAssertTrue(note.content.contains("# Trail - A"))
        XCTAssertTrue(note.content.contains("## Path"))
        XCTAssertTrue(note.content.contains("[[A]]"))
        XCTAssertTrue(note.content.contains("[[B]]"))
        XCTAssertTrue(note.content.contains("## Highlights & Notes"))
        XCTAssertTrue(note.content.contains("a key idea"))
        XCTAssertTrue(note.content.contains("remember this"))
    }
}
