import XCTest
@testable import Cribble

@MainActor
final class BacklinkIndexTests: XCTestCase {
    func testBacklinksResolveLikeForwardLinksAndGroupOccurrences() throws {
        let root = try Fixture.makeFolder()
        let target = root.appendingPathComponent("Target.md")
        let aliasSource = root.appendingPathComponent("Alias Source.md")
        let headingSource = root.appendingPathComponent("Heading Source.md")
        let unresolved = root.appendingPathComponent("Unresolved.md")
        let selfLinked = root.appendingPathComponent("Self.md")

        try """
        ---
        aliases: [Project Target]
        keywords: target-keyword
        tags: [target-tag]
        ---
        # Target Title
        ## Road Map
        """.write(to: target, atomically: true, encoding: .utf8)
        try """
        # Alias Source
        See [[Project Target|project]] and [[target-keyword]] in context.
        """.write(to: aliasSource, atomically: true, encoding: .utf8)
        try """
        # Heading Source
        Jump to [[Target Title#Road Map|the roadmap]].
        """.write(to: headingSource, atomically: true, encoding: .utf8)
        try "# Unresolved\nSee [[Missing]].".write(to: unresolved, atomically: true, encoding: .utf8)
        try "# Self\nSee [[Self]].".write(to: selfLinked, atomically: true, encoding: .utf8)

        let loader = DocumentLoader()
        let documents = try [target, aliasSource, headingSource, unresolved, selfLinked].map(loader.load(url:))
        let index = BacklinkIndex(documentMetas: documents.map(MarkdownDocumentMeta.init), rootURL: root)

        let backlinks = index.backlinks(for: target) { sourceURL, range in
            let markdown = (try? DocumentLoader.readText(at: sourceURL)) ?? ""
            return BacklinkIndex.snippet(in: markdown, around: range)
        }

        XCTAssertEqual(backlinks.map(\.sourceTitle), ["Alias Source", "Heading Source"])
        XCTAssertEqual(backlinks[0].occurrences.count, 2)
        XCTAssertEqual(backlinks[0].occurrences.map(\.linkLabel), ["project", "target-keyword"])
        XCTAssertEqual(backlinks[1].occurrences.map(\.linkLabel), ["the roadmap"])
        XCTAssertTrue(backlinks[0].occurrences[0].snippet.contains("See project and target-keyword in context."))
    }

    func testLinksInsideCodeAndSelfLinksAreIgnored() throws {
        let root = try Fixture.makeFolder()
        let target = root.appendingPathComponent("Target.md")
        let source = root.appendingPathComponent("Source.md")

        try "# Target\nSee [[Target]].".write(to: target, atomically: true, encoding: .utf8)
        try """
        # Source
        `[[Target]]`

        ```md
        [[Target]]
        ```

        Real [[Target]] mention.
        """.write(to: source, atomically: true, encoding: .utf8)

        let documents = try [target, source].map(DocumentLoader().load(url:))
        let index = BacklinkIndex(documentMetas: documents.map(MarkdownDocumentMeta.init), rootURL: root)
        let backlinks = index.backlinks(for: target)

        XCTAssertEqual(backlinks.count, 1)
        XCTAssertEqual(backlinks[0].sourceTitle, "Source")
        XCTAssertEqual(backlinks[0].occurrences.count, 1)
        XCTAssertEqual(backlinks[0].occurrences[0].linkLabel, "Target")
    }

    func testSnippetStripsAndTruncates() throws {
        let markdown = "Before [[Target|label]] " + String(repeating: "word ", count: 60)
        let link = try XCTUnwrap(WikiLinkParser.parse(markdown).first)
        let snippet = BacklinkIndex.snippet(in: markdown, around: try XCTUnwrap(link.sourceRange), maxLength: 40)

        XCTAssertFalse(snippet.contains("[["))
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertLessThanOrEqual(snippet.count, 40)
    }

    func testStoreExposesBacklinksAfterRefresh() async throws {
        let root = try Fixture.makeFolder()
        let target = root.appendingPathComponent("Target.md")
        let source = root.appendingPathComponent("Source.md")
        try "# Target\n".write(to: target, atomically: true, encoding: .utf8)
        try "# Source\nMentions [[Target]] here.".write(to: source, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(root, sortMode: .name)
        await store.waitForLoadToComplete()

        let backlinks = store.backlinks(for: target)

        XCTAssertEqual(backlinks.map(\.sourceTitle), ["Source"])
        XCTAssertEqual(backlinks.first?.occurrences.first?.snippet, "Mentions Target here.")
    }

    func testSelectingDocumentPublishesSelectedBacklinks() async throws {
        let root = try Fixture.makeFolder()
        let target = root.appendingPathComponent("Target.md")
        let source = root.appendingPathComponent("Source.md")
        try "# Target\n".write(to: target, atomically: true, encoding: .utf8)
        try "# Source\nMentions [[Target]] here.".write(to: source, atomically: true, encoding: .utf8)

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(root, sortMode: .name)
        await store.waitForLoadToComplete()
        store.select(url: target)
        await store.waitForRenderToComplete()

        XCTAssertEqual(store.selectedBacklinks.map(\.sourceTitle), ["Source"])
        XCTAssertEqual(store.selectedBacklinks.first?.occurrences.first?.snippet, "Mentions Target here.")
    }
}
