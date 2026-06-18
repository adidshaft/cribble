import XCTest
@testable import Cribble

final class CalloutStyleTests: XCTestCase {
    func testKnownCalloutTypesMapToSymbolsAndTitles() {
        let warning = CalloutBlock(
            id: "callout-1",
            type: "warning",
            title: "Careful",
            fold: .none,
            bodyMarkdown: "Body",
            originalMarkdown: "> [!warning] Careful\n> Body"
        )

        let style = CalloutStyle.style(for: warning)

        XCTAssertEqual(style.title, "Careful")
        XCTAssertEqual(style.symbolName, "exclamationmark.triangle")
    }

    func testAliasesAndUnknownTypesFallbackCalmly() {
        let failure = CalloutBlock(
            id: "callout-1",
            type: "failure",
            title: "Failure",
            fold: .none,
            bodyMarkdown: "",
            originalMarkdown: "> [!failure]"
        )
        let custom = CalloutBlock(
            id: "callout-2",
            type: "custom",
            title: "Custom",
            fold: .none,
            bodyMarkdown: "",
            originalMarkdown: "> [!custom]"
        )

        XCTAssertEqual(CalloutStyle.style(for: failure).symbolName, "xmark.octagon")
        XCTAssertEqual(CalloutStyle.style(for: custom).symbolName, "info.circle")
    }
}
