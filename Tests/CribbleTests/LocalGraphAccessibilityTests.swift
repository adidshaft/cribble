import XCTest
@testable import Cribble

final class LocalGraphAccessibilityTests: XCTestCase {
    func testCurrentNodeLabelNamesCurrentNote() {
        let node = LocalNoteGraph.Node(
            url: URL(fileURLWithPath: "/tmp/A.md"),
            title: "A",
            distance: 0,
            isCurrent: true
        )

        XCTAssertEqual(LocalGraphAccessibility.label(for: node), "A, current note")
    }

    func testNeighborNodeLabelNamesHopDistance() {
        let oneHop = LocalNoteGraph.Node(
            url: URL(fileURLWithPath: "/tmp/B.md"),
            title: "B",
            distance: 1,
            isCurrent: false
        )
        let twoHops = LocalNoteGraph.Node(
            url: URL(fileURLWithPath: "/tmp/C.md"),
            title: "C",
            distance: 2,
            isCurrent: false
        )

        XCTAssertEqual(LocalGraphAccessibility.label(for: oneHop), "B, 1 hop away")
        XCTAssertEqual(LocalGraphAccessibility.label(for: twoHops), "C, 2 hops away")
    }
}
