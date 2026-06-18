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

    func testParsesEmbedReferencesSeparatelyFromWikiLinks() {
        let markdown = "Embed ![[Alpha#Road Map|the plan]], block ![[Beta^block-id]], standard ![[Gamma#^anchor]]."

        let embeds = WikiLinkParser.parseEmbeds(markdown)

        XCTAssertEqual(WikiLinkParser.parse(markdown).map(\.target), [])
        XCTAssertEqual(embeds.count, 3)
        XCTAssertEqual(embeds[0].target, "Alpha")
        XCTAssertEqual(embeds[0].heading, "Road Map")
        XCTAssertNil(embeds[0].blockID)
        XCTAssertEqual(embeds[0].label, "the plan")
        XCTAssertEqual(embeds[1].target, "Beta")
        XCTAssertNil(embeds[1].heading)
        XCTAssertEqual(embeds[1].blockID, "block-id")
        XCTAssertEqual(embeds[2].target, "Gamma")
        XCTAssertEqual(embeds[2].blockID, "anchor")
        XCTAssertNotNil(embeds[2].sourceRange)
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

    func testSkipsEmbedsInsideInlineAndFencedCode() {
        let markdown = """
        Show ![[Real]] and `![[Inline Code]]`.

        ```markdown
        ![[Fenced Code]]
        ```
        """

        XCTAssertEqual(WikiLinkParser.parseEmbeds(markdown).map(\.target), ["Real"])
        XCTAssertFalse(WikiLinkParser.renderForMarkdown(markdown, index: nil).contains("!\\["))
    }
}
