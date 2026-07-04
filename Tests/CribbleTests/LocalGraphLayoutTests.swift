import XCTest
@testable import Cribble

final class LocalGraphLayoutTests: XCTestCase {
    func testLayoutCentersCurrentNodeAndPlacesNeighborsInBounds() {
        let center = URL(fileURLWithPath: "/tmp/Center.md")
        let near = URL(fileURLWithPath: "/tmp/Near.md")
        let far = URL(fileURLWithPath: "/tmp/Far.md")
        let graph = LocalNoteGraph(
            center: center,
            nodes: [
                .init(url: center, title: "Center", distance: 0, isCurrent: true),
                .init(url: near, title: "Near", distance: 1, isCurrent: false),
                .init(url: far, title: "Far", distance: 2, isCurrent: false)
            ],
            edges: [.init(source: center, target: near), .init(source: near, target: far)]
        )

        let positions = LocalGraphLayout.positions(for: graph, in: CGSize(width: 300, height: 220))

        XCTAssertEqual(positions[center], CGPoint(x: 150, y: 110))
        XCTAssertEqual(positions.count, 3)
        for point in positions.values {
            XCTAssertGreaterThanOrEqual(point.x, 0)
            XCTAssertLessThanOrEqual(point.x, 300)
            XCTAssertGreaterThanOrEqual(point.y, 0)
            XCTAssertLessThanOrEqual(point.y, 220)
        }
    }

    func testLayoutIsDeterministicForSameGraph() {
        let center = URL(fileURLWithPath: "/tmp/Center.md")
        let a = URL(fileURLWithPath: "/tmp/A.md")
        let b = URL(fileURLWithPath: "/tmp/B.md")
        let graph = LocalNoteGraph(
            center: center,
            nodes: [
                .init(url: center, title: "Center", distance: 0, isCurrent: true),
                .init(url: b, title: "B", distance: 1, isCurrent: false),
                .init(url: a, title: "A", distance: 1, isCurrent: false)
            ],
            edges: []
        )

        XCTAssertEqual(
            LocalGraphLayout.positions(for: graph, in: CGSize(width: 240, height: 180)),
            LocalGraphLayout.positions(for: graph, in: CGSize(width: 240, height: 180))
        )
    }

    func testLayoutSpreadsHorizontallyInWideCards() {
        // Reader cards are much wider than tall; the ring must use that width
        // so 92pt labels don't pile up in the middle.
        let center = URL(fileURLWithPath: "/tmp/Center.md")
        let east = URL(fileURLWithPath: "/tmp/B-east.md")
        let graph = LocalNoteGraph(
            center: center,
            nodes: [
                .init(url: center, title: "Center", distance: 0, isCurrent: true),
                .init(url: URL(fileURLWithPath: "/tmp/A.md"), title: "A", distance: 1, isCurrent: false),
                .init(url: east, title: "B", distance: 1, isCurrent: false),
                .init(url: URL(fileURLWithPath: "/tmp/C.md"), title: "C", distance: 1, isCurrent: false),
                .init(url: URL(fileURLWithPath: "/tmp/D.md"), title: "D", distance: 1, isCurrent: false)
            ],
            edges: []
        )

        let size = CGSize(width: 600, height: 200)
        let positions = LocalGraphLayout.positions(for: graph, in: size)
        let maxX = positions.values.map(\.x).max() ?? 0

        // The old min-side circle capped x at 300 + 0.34*200 = 368.
        XCTAssertGreaterThan(maxX, 400)
        for point in positions.values {
            XCTAssertGreaterThanOrEqual(point.x, 0)
            XCTAssertLessThanOrEqual(point.x, size.width)
            XCTAssertGreaterThanOrEqual(point.y, 0)
            XCTAssertLessThanOrEqual(point.y, size.height)
        }
    }

    func testLayoutReturnsEmptyForEmptySize() {
        let graph = LocalNoteGraph(center: URL(fileURLWithPath: "/tmp/A.md"), nodes: [], edges: [])
        XCTAssertEqual(LocalGraphLayout.positions(for: graph, in: .zero), [:])
    }
}
