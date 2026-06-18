import XCTest
@testable import Cribble

@MainActor
final class TagIndexTests: XCTestCase {
    func testUnifiesFrontMatterAndInlineTagsWithCounts() throws {
        let root = try Fixture.makeFolder()
        let alpha = root.appendingPathComponent("Alpha.md")
        let beta = root.appendingPathComponent("Beta.md")

        try """
        ---
        tags: [Research, nested/topic]
        ---
        # Alpha
        Body with #research and #Launch-Plan.
        """.write(to: alpha, atomically: true, encoding: .utf8)
        try """
        ---
        tags: launch-plan
        ---
        # Beta
        Body with #nested/topic/deep.
        """.write(to: beta, atomically: true, encoding: .utf8)

        let documents = try [alpha, beta].map(DocumentLoader().load(url:)).map(MarkdownDocumentMeta.init)
        let index = TagIndex(documents: documents)

        let tags = Dictionary(uniqueKeysWithValues: index.allTags().map { ($0.normalized, $0.count) })
        XCTAssertEqual(tags["research"], 1)
        XCTAssertEqual(tags["launch-plan"], 2)
        XCTAssertEqual(tags["nested/topic"], 1)
        XCTAssertEqual(tags["nested/topic/deep"], 1)
    }

    func testNestedTagSelectionIncludesDescendants() throws {
        let root = try Fixture.makeFolder()
        let parent = root.appendingPathComponent("Parent.md")
        let child = root.appendingPathComponent("Child.md")
        let other = root.appendingPathComponent("Other.md")

        try "# Parent\nBody #area".write(to: parent, atomically: true, encoding: .utf8)
        try "# Child\nBody #area/project".write(to: child, atomically: true, encoding: .utf8)
        try "# Other\nBody #archive".write(to: other, atomically: true, encoding: .utf8)

        let documents = try [parent, child, other].map(DocumentLoader().load(url:)).map(MarkdownDocumentMeta.init)
        let index = TagIndex(documents: documents)

        XCTAssertEqual(index.notes(forTag: "area"), [child.standardizedFileURL, parent.standardizedFileURL].sorted { $0.path < $1.path })
        XCTAssertEqual(index.notes(forTag: "area/project"), [child.standardizedFileURL])
    }

    func testInlineScanIgnoresHeadingsInlineCodeAndFencedCode() {
        let markdown = """
        # #heading-tag
        Real #body-tag and `#code-tag`.

        ```md
        #fenced-tag
        ```

        After #later/tag.
        """

        XCTAssertEqual(TagIndex.tags(in: markdown), ["body-tag", "later/tag"])
    }

    func testNormalizationMatchesLinkIndexCaseAndDiacriticBehavior() {
        XCTAssertEqual(TagIndex.normalize("#Résumé/Ideas"), LinkIndex.normalize("Résumé/Ideas"))
        XCTAssertEqual(TagIndex.normalize(" /Research/ "), "research")
    }

    func testStoreExposesTagsAfterRefresh() async throws {
        let root = try Fixture.makeFolder()
        let note = root.appendingPathComponent("Note.md")
        try """
        ---
        tags: [Project]
        ---
        # Note
        Inline #project/next.
        """.write(to: note, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(root, sortMode: .name)
        await store.waitForLoadToComplete()

        XCTAssertEqual(store.allTags().map(\.normalized), ["project", "project/next"])
        XCTAssertEqual(store.notes(forTag: "project"), [note.standardizedFileURL])
    }
}
