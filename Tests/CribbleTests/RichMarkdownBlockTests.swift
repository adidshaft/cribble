import XCTest
@testable import Cribble

final class RichMarkdownBlockTests: XCTestCase {
    func testSplitsMarkdownAroundCodeAndMermaidFences() {
        let blocks = RichMarkdownBlock.blocks(
            from: """
            Intro

            ```mermaid
            graph TD
              A[Start] --> B{Choose}
            ```

            ```swift
            let answer = 42
            ```

            Outro
            """
        )

        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0], .markdown(id: "markdown-0", text: "Intro"))
        XCTAssertEqual(blocks[1], .fencedCode(id: "fence-1", language: "mermaid", code: "graph TD\n  A[Start] --> B{Choose}"))
        XCTAssertEqual(blocks[2], .fencedCode(id: "fence-2", language: "swift", code: "let answer = 42"))
        XCTAssertEqual(blocks[3], .markdown(id: "markdown-3", text: "Outro"))
    }

    func testSplitsTaskRunsIntoTaskListBlocks() {
        let blocks = RichMarkdownBlock.blocks(
            from: """
            ## To do

            - [ ] first
            - [x] second

            Closing prose.
            """
        )

        XCTAssertEqual(blocks.count, 3)
        guard case .markdown(_, let intro) = blocks[0] else { return XCTFail("expected prose first") }
        XCTAssertEqual(intro, "## To do")

        guard case .taskList(_, let items) = blocks[1] else { return XCTFail("expected task list") }
        XCTAssertEqual(items.map(\.label), ["first", "second"])
        XCTAssertEqual(items.map(\.isChecked), [false, true])

        guard case .markdown(_, let outro) = blocks[2] else { return XCTFail("expected trailing prose") }
        XCTAssertEqual(outro, "Closing prose.")
    }

    func testSupportsTildeFencesAndBraceLanguages() {
        let blocks = RichMarkdownBlock.blocks(
            from: """
            ~~~~{vega-lite}
            {"mark":"bar"}
            ~~~~
            """
        )

        XCTAssertEqual(blocks, [.fencedCode(id: "fence-0", language: "vega-lite", code: "{\"mark\":\"bar\"}")])
    }

    func testSplitsStandaloneImagesAwayFromSurroundingProse() {
        let blocks = RichMarkdownBlock.blocks(
            from: """
            Adjacent markdown image:

            ![alt](file:///tmp/pic.png)

            Obsidian embed:

            ![pic.png](file:///tmp/pic.png)

            Remote image should be blocked until enabled:

            [🖼 remote](https://example.com/y.png)
            """
        )

        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0], .markdown(id: "markdown-0", text: "Adjacent markdown image:"))
        XCTAssertEqual(blocks[1], .markdown(id: "markdown-1", text: "![alt](file:///tmp/pic.png)"))
        XCTAssertEqual(blocks[2], .markdown(id: "markdown-2", text: "Obsidian embed:"))
        XCTAssertEqual(blocks[3], .markdown(id: "markdown-3", text: "![pic.png](file:///tmp/pic.png)"))
        XCTAssertEqual(
            blocks[4],
            .markdown(
                id: "markdown-4",
                text: "Remote image should be blocked until enabled:\n\n[🖼 remote](https://example.com/y.png)"
            )
        )
    }

    func testParsesObsidianCalloutBlocks() {
        let blocks = RichMarkdownBlock.blocks(
            from: """
            Intro

            > [!warning]- Custom title
            > First line
            > - nested item

            Outro
            """
        )

        XCTAssertEqual(blocks.count, 3)
        guard case .callout(_, let callout) = blocks[1] else {
            return XCTFail("expected callout block")
        }

        XCTAssertEqual(callout.type, "warning")
        XCTAssertEqual(callout.title, "Custom title")
        XCTAssertEqual(callout.fold, .collapsed)
        XCTAssertEqual(callout.bodyMarkdown, "First line\n- nested item")
        XCTAssertEqual(callout.originalMarkdown, "> [!warning]- Custom title\n> First line\n> - nested item")
    }

    func testCalloutDefaultsTitleAndExpandedFold() {
        let callout = CalloutBlock.parse(id: "callout-test", blockquoteLines: [
            "> [!tip]+",
            "> Body"
        ])

        XCTAssertEqual(callout?.type, "tip")
        XCTAssertEqual(callout?.title, "Tip")
        XCTAssertEqual(callout?.fold, .expanded)
        XCTAssertEqual(callout?.bodyMarkdown, "Body")
    }

    func testPlainBlockquoteRemainsMarkdown() {
        let blocks = RichMarkdownBlock.blocks(
            from: """
            > A plain quoted paragraph
            > without a callout marker.
            """
        )

        XCTAssertEqual(blocks, [
            .markdown(id: "markdown-0", text: "> A plain quoted paragraph\n> without a callout marker.")
        ])
    }
}
