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
}
