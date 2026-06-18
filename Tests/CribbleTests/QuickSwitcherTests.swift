import XCTest
@testable import Cribble

final class QuickSwitcherTests: XCTestCase {
    func testFiltersTitlesAliasesAndRelativePaths() {
        let root = URL(fileURLWithPath: "/tmp/Vault")
        let alpha = document(
            root.appendingPathComponent("Projects/Alpha Plan.md"),
            title: "Alpha Plan",
            aliases: ["Launch Map"]
        )
        let beta = document(
            root.appendingPathComponent("Research/Beta Notes.md"),
            title: "Beta Notes",
            aliases: ["Study Log"]
        )
        let items = QuickSwitcherModel.items(
            documents: [alpha, beta],
            recentURLs: [],
            relativePath: { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
        )

        XCTAssertEqual(QuickSwitcherModel.results(query: "launch", items: items).map(\.url), [alpha.url])
        XCTAssertEqual(QuickSwitcherModel.results(query: "research", items: items).map(\.url), [beta.url])
        XCTAssertEqual(QuickSwitcherModel.results(query: "alpha", items: items).map(\.url), [alpha.url])
    }

    func testEmptyQueryShowsRecentNotesFirst() {
        let root = URL(fileURLWithPath: "/tmp/Vault")
        let one = document(root.appendingPathComponent("One.md"), title: "One")
        let two = document(root.appendingPathComponent("Two.md"), title: "Two")
        let three = document(root.appendingPathComponent("Three.md"), title: "Three")
        let items = QuickSwitcherModel.items(
            documents: [one, two, three],
            recentURLs: [one.url, three.url],
            relativePath: { $0.lastPathComponent }
        )

        XCTAssertEqual(QuickSwitcherModel.results(query: "", items: items).map(\.url), [
            three.url.standardizedFileURL,
            one.url.standardizedFileURL,
            two.url.standardizedFileURL
        ])
    }

    private func document(_ url: URL, title: String, aliases: [String] = []) -> MarkdownDocumentMeta {
        MarkdownDocumentMeta(
            url: url.standardizedFileURL,
            title: title,
            headings: [],
            outboundLinks: [],
            linkAliases: aliases,
            contentHash: 0,
            embeddingPrefix: ""
        )
    }
}
