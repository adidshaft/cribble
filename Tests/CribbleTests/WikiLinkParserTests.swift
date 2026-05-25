import XCTest
@testable import Cribble

final class WikiLinkParserTests: XCTestCase {
    func testParsesTargetsLabelsAndAnchors() {
        let links = WikiLinkParser.parse("See [[Alpha#Road Map|the plan]] and [[Beta]].")

        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].target, "Alpha")
        XCTAssertEqual(links[0].anchor, "Road Map")
        XCTAssertEqual(links[0].label, "the plan")
        XCTAssertEqual(links[1].target, "Beta")
        XCTAssertEqual(links[1].label, "Beta")
    }
}
