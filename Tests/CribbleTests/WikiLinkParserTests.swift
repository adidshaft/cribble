import XCTest
@testable import Cribble

final class WikiLinkParserTests: XCTestCase {
    func testParsesTargetsLabelsAndAnchors() {
        let links = WikiLinkParser.parse("See [[Alpha#Road Map|the plan]] and [[Beta]].")

        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].target, "Alpha")
        XCTAssertEqual(links[0].anchor, "Road Map")
        XCTAssertEqual(links[0].label, "the plan")
        XCTAssertNotNil(links[0].sourceRange)
        XCTAssertEqual(links[1].target, "Beta")
        XCTAssertEqual(links[1].label, "Beta")
    }

    func testSkipsWikiLinksInsideInlineAndFencedCode() {
        let markdown = """
        See [[Real]] and `[[Inline Code]]`.

        ```swift
        let link = "[[Fenced Code]]"
        ```

        Also [[Another Real]].
        """

        let links = WikiLinkParser.parse(markdown)

        XCTAssertEqual(links.map(\.target), ["Real", "Another Real"])
        XCTAssertFalse(WikiLinkParser.renderForMarkdown(markdown, index: nil).contains("cribble://unresolved?target=Inline"))
    }
}
