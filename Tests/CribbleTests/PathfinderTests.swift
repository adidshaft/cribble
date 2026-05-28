import XCTest
@testable import Cribble

final class PathfinderTests: XCTestCase {
    @MainActor
    func testWikiLinkShortestPath() throws {
        let root = try Fixture.makeFolder()
        let a = root.appendingPathComponent("NoteA.md")
        let b = root.appendingPathComponent("NoteB.md")
        let c = root.appendingPathComponent("NoteC.md")
        let d = root.appendingPathComponent("NoteD.md")

        try "# Note A\n\nSee [[Note B]].".write(to: a, atomically: true, encoding: .utf8)
        try "# Note B\n\nSee [[Note C]].".write(to: b, atomically: true, encoding: .utf8)
        try "# Note C\n\nLeaf.".write(to: c, atomically: true, encoding: .utf8)
        try "# Note D\n\nUnconnected.".write(to: d, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(root, sortMode: .name)

        let exp = expectation(description: "scan")
        Task { await store.waitForLoadToComplete(); exp.fulfill() }
        wait(for: [exp], timeout: 3.0)

        // A → B → C is reachable via wiki links.
        let path = store.wikiLinkPath(from: a, to: c)
        XCTAssertEqual(
            path?.map(\.standardizedFileURL.lastPathComponent),
            ["NoteA.md", "NoteB.md", "NoteC.md"]
        )

        // Direct neighbours.
        XCTAssertEqual(
            store.wikiLinkPath(from: a, to: b)?.map(\.standardizedFileURL.lastPathComponent),
            ["NoteA.md", "NoteB.md"]
        )

        // D is unreachable from A.
        XCTAssertNil(store.wikiLinkPath(from: a, to: d))

        // Same-note path is the note itself.
        XCTAssertEqual(store.wikiLinkPath(from: a, to: a)?.count, 1)
    }
}
