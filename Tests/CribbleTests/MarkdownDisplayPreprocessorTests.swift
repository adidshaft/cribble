import XCTest
@testable import Cribble

final class MarkdownDisplayPreprocessorTests: XCTestCase {
    func testStripsFrontMatterAndLeadingTitleForReading() {
        let prepared = MarkdownDisplayPreprocessor.prepare(
            """
            ---
            aliases: [home]
            ---
            # Home

            Body
            """,
            documentTitle: "Home"
        )

        XCTAssertEqual(prepared, "Body")
    }

    func testEnrichesTaskListMarkers() {
        let prepared = MarkdownDisplayPreprocessor.prepare(
            """
            - [x] Done
            - [ ] Next
            """,
            documentTitle: "Tasks"
        )

        XCTAssertEqual(prepared, "- ☑ Done\n- ☐ Next")
    }

    func testDetectsAutoCreatedReadmeAsEssentiallyEmpty() {
        XCTAssertTrue(MarkdownDisplayPreprocessor.isEssentiallyEmpty("# docs\n", documentTitle: "docs"))
        XCTAssertTrue(MarkdownDisplayPreprocessor.isEssentiallyEmpty("---\ntags: [index]\n---\n# images\n", documentTitle: "images"))
        XCTAssertFalse(MarkdownDisplayPreprocessor.isEssentiallyEmpty("# docs\n\n## Contents\n- [Guide](Guide.md)", documentTitle: "docs"))
    }
}
