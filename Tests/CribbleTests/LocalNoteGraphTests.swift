import XCTest
@testable import Cribble

final class LocalNoteGraphTests: XCTestCase {
    func testNeighborhoodIncludesForwardLinksAndBacklinks() throws {
        let fixture = try makeFixture([
            "Center.md": "# Center\nSee [[Forward]].",
            "Forward.md": "# Forward",
            "Backlink.md": "# Backlink\nMentions [[Center]].",
            "Other.md": "# Other"
        ])
        defer { fixture.cleanup() }

        let graph = LocalNoteGraph.neighborhood(
            of: fixture.url("Center.md"),
            documents: fixture.metas,
            rootURL: fixture.root,
            hops: 1
        )

        XCTAssertEqual(graph.nodes.map(\.title), ["Center", "Backlink", "Forward"])
        XCTAssertTrue(graph.edges.contains(.init(source: fixture.url("Center.md").standardizedFileURL, target: fixture.url("Forward.md").standardizedFileURL)))
        XCTAssertTrue(graph.edges.contains(.init(source: fixture.url("Backlink.md").standardizedFileURL, target: fixture.url("Center.md").standardizedFileURL)))
        XCTAssertFalse(graph.nodes.map(\.title).contains("Other"))
    }

    func testNeighborhoodRespectsHopLimit() throws {
        let fixture = try makeFixture([
            "A.md": "# A\n[[B]]",
            "B.md": "# B\n[[C]]",
            "C.md": "# C"
        ])
        defer { fixture.cleanup() }

        let oneHop = LocalNoteGraph.neighborhood(of: fixture.url("A.md"), documents: fixture.metas, rootURL: fixture.root, hops: 1)
        let twoHop = LocalNoteGraph.neighborhood(of: fixture.url("A.md"), documents: fixture.metas, rootURL: fixture.root, hops: 2)

        XCTAssertEqual(oneHop.nodes.map(\.title), ["A", "B"])
        XCTAssertEqual(twoHop.nodes.map(\.title), ["A", "B", "C"])
    }

    func testNeighborhoodRespectsNodeCapAndZeroHop() throws {
        let fixture = try makeFixture([
            "A.md": "# A\n[[B]] [[C]] [[D]]",
            "B.md": "# B",
            "C.md": "# C",
            "D.md": "# D"
        ])
        defer { fixture.cleanup() }

        let zero = LocalNoteGraph.neighborhood(of: fixture.url("A.md"), documents: fixture.metas, rootURL: fixture.root, hops: 0)
        let capped = LocalNoteGraph.neighborhood(of: fixture.url("A.md"), documents: fixture.metas, rootURL: fixture.root, hops: 1, maxNodes: 2)

        XCTAssertEqual(zero.nodes.map(\.title), ["A"])
        XCTAssertEqual(capped.nodes.map(\.title), ["A", "B"])
    }

    func testNeighborhoodNodeSetIsDeterministic() throws {
        let fixture = try makeFixture([
            "B.md": "# B\n[[A]]",
            "A.md": "# A\n[[C]]",
            "C.md": "# C\n[[B]]"
        ])
        defer { fixture.cleanup() }

        let shuffled = fixture.metas.reversed()
        let first = LocalNoteGraph.neighborhood(of: fixture.url("A.md"), documents: fixture.metas, rootURL: fixture.root, hops: 2)
        let second = LocalNoteGraph.neighborhood(of: fixture.url("A.md"), documents: Array(shuffled), rootURL: fixture.root, hops: 2)

        XCTAssertEqual(first.nodes, second.nodes)
        XCTAssertEqual(first.edges, second.edges)
    }

    private func makeFixture(_ files: [String: String]) throws -> GraphFixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cribble-local-graph-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, body) in files {
            try body.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let loader = DocumentLoader()
        let metas = try files.keys.sorted().map { name in
            try MarkdownDocumentMeta(loader.load(url: root.appendingPathComponent(name)))
        }
        return GraphFixture(root: root, metas: metas)
    }

    private struct GraphFixture {
        let root: URL
        let metas: [MarkdownDocumentMeta]

        func url(_ name: String) -> URL {
            root.appendingPathComponent(name)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
