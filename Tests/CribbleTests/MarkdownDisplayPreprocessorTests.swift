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

    func testPreservesTaskListMarkers() {
        // Task markers are intentionally left intact so the reader can render
        // them as interactive checkboxes (TaskListView) rather than glyphs.
        let input = """
        - [x] Done
        - [ ] Next
        * [X] Shouted
        + [ ] Plus
          - [ ] Nested
        """
        let prepared = MarkdownDisplayPreprocessor.prepare(input, documentTitle: "Tasks")
        XCTAssertEqual(prepared, input)
    }

    func testDetectsAutoCreatedReadmeAsEssentiallyEmpty() {
        XCTAssertTrue(MarkdownDisplayPreprocessor.isEssentiallyEmpty("# docs\n", documentTitle: "docs"))
        XCTAssertTrue(MarkdownDisplayPreprocessor.isEssentiallyEmpty("---\ntags: [index]\n---\n# images\n", documentTitle: "images"))
        XCTAssertFalse(MarkdownDisplayPreprocessor.isEssentiallyEmpty("# docs\n\n## Contents\n- [Guide](Guide.md)", documentTitle: "docs"))
    }
}
