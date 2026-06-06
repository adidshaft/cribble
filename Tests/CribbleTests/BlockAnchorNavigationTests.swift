import XCTest
@testable import Cribble

final class BlockAnchorNavigationTests: XCTestCase {
    func testResolvesBlockToEnclosingHeading() {
        let md = """
        # Intro

        Some text.

        ## Plans

        - [ ] Ship it ^cribble-ab12
        """
        XCTAssertEqual(MarkdownLibraryStore.sectionAnchor(forBlockID: "cribble-ab12", in: md), "plans")
    }

    func testBlockAboveAnyHeadingReturnsTop() {
        let md = "- [ ] Early task ^xyz\n\n# Later\n"
        XCTAssertEqual(MarkdownLibraryStore.sectionAnchor(forBlockID: "xyz", in: md), "top")
    }

    func testMissingBlockReturnsNil() {
        let md = "# A\n\n- [ ] Task ^one\n"
        XCTAssertNil(MarkdownLibraryStore.sectionAnchor(forBlockID: "missing", in: md))
    }
}
