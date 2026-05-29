import XCTest
import Textual
@testable import Cribble

@MainActor
final class TaskHighlightResolutionTests: XCTestCase {
    private func highlight(quote: String, anchor: HighlightAnchor? = nil) -> ReadingHighlight {
        ReadingHighlight(
            id: UUID(),
            documentPath: "/doc.md",
            quote: quote,
            note: "remember",
            createdAt: Date(),
            anchor: anchor
        )
    }

    func testTextSearchHighlightResolvesToTaskItem() {
        let rendered = """
        ## Things to do

        - [ ] alpha task here
        - [x] beta task here
        """
        let h = highlight(quote: "alpha task here")
        let plan = ReaderSectionPlan.build(rendered: rendered, highlights: [h])

        // Resolved to a unit in the task block-index namespace.
        let taskKeys = plan.highlightsByBlock.keys.filter { $0.blockIndex >= HighlightBlockSpace.taskBase }
        XCTAssertFalse(taskKeys.isEmpty, "A highlight whose quote matches a task label should resolve to a task unit")

        let resolved = plan.highlightsByBlock.values.flatMap { $0 }
        XCTAssertTrue(resolved.contains { $0.id == h.id }, "The highlight must be resolved somewhere")
    }

    func testOffsetAnchoredHighlightResolvesToTaskItem() {
        let rendered = """
        ## Things to do

        - [ ] alpha task here
        - [x] beta task here
        """
        // Anchor the highlight to the first task item (global ordinal 0) with the
        // label's signature — mirrors what the renderer captures.
        let label = "alpha task here"
        let anchor = HighlightAnchor(
            sectionAnchor: Slugger.slug("Things to do"),
            blockIndex: HighlightBlockSpace.taskBlockIndex(globalOrdinal: 0),
            blockSignature: TextInteractionSelectionSnapshot.signature(for: label),
            startOffset: 0,
            length: 5 // "alpha"
        )
        let h = highlight(quote: "alpha", anchor: anchor)
        let plan = ReaderSectionPlan.build(rendered: rendered, highlights: [h])

        let key = BlockKey(
            sectionAnchor: anchor.sectionAnchor,
            blockIndex: anchor.blockIndex
        )
        let resolvedForKey = plan.highlightsByBlock[key] ?? []
        XCTAssertTrue(
            resolvedForKey.contains { $0.id == h.id },
            "An offset-anchored highlight on a task item should resolve to that item's block key"
        )
    }
}
