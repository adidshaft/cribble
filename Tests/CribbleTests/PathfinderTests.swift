import XCTest
@testable import Cribble

final class PathfinderTests: XCTestCase {
    func testPathfinderHandoffSummaryIncludesPathBridgeAndExplanation() {
        let summary = PathfinderHandoffSummary.markdown(
            sourceTitle: "Launch Brief",
            targetTitle: "Decision Log",
            wikiPathTitles: ["Launch Brief", "Research Review", "Decision Log"],
            bridgeTitles: ["Workflow Playbook"],
            explanation: "Research links the launch to a recorded decision."
        )

        XCTAssertTrue(summary.contains("# Pathfinder Summary"))
        XCTAssertTrue(summary.contains("Source: Launch Brief"))
        XCTAssertTrue(summary.contains("Target: Decision Log"))
        XCTAssertTrue(summary.contains("Launch Brief -> Research Review -> Decision Log"))
        XCTAssertTrue(summary.contains("Launch Brief -> Workflow Playbook -> Decision Log"))
        XCTAssertTrue(summary.contains("Research links the launch to a recorded decision."))
    }

    func testPathfinderHandoffSummaryNamesMissingPaths() {
        let summary = PathfinderHandoffSummary.markdown(
            sourceTitle: "Alpha",
            targetTitle: "Beta",
            wikiPathTitles: nil,
            bridgeTitles: [],
            explanation: " "
        )

        XCTAssertTrue(summary.contains("No existing wiki-link path."))
        XCTAssertTrue(summary.contains("No stepping-stone notes selected."))
        XCTAssertFalse(summary.contains("## Explanation"))
    }

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
