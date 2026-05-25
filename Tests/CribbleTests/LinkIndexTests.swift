import XCTest
@testable import Cribble

final class LinkIndexTests: XCTestCase {
    func testResolvesByTitleAliasKeywordTagAndAnchor() throws {
        let root = try Fixture.makeFolder()
        let alpha = root.appendingPathComponent("Alpha.md")
        let beta = root.appendingPathComponent("Beta Note.md")

        try """
        ---
        aliases: [Project A]
        keywords: planning
        tags: [strategy]
        ---
        # Alpha Title
        ## Road Map
        """.write(to: alpha, atomically: true, encoding: .utf8)
        try "# Beta".write(to: beta, atomically: true, encoding: .utf8)

        let loader = DocumentLoader()
        let index = LinkIndex(documents: try [loader.load(url: alpha), loader.load(url: beta)], rootURL: root)

        XCTAssertEqual(index.resolve(WikiLink(original: "", target: "Project A", label: "", anchor: nil)).targetURL, alpha)
        XCTAssertEqual(index.resolve(WikiLink(original: "", target: "planning", label: "", anchor: nil)).targetURL, alpha)
        XCTAssertEqual(index.resolve(WikiLink(original: "", target: "strategy", label: "", anchor: nil)).targetURL, alpha)
        XCTAssertEqual(index.resolve(WikiLink(original: "", target: "Alpha Title", label: "", anchor: "Road Map")).targetURL, alpha)
        XCTAssertEqual(index.resolve(WikiLink(original: "", target: "Beta Note", label: "", anchor: nil)).targetURL, beta)
    }
}
