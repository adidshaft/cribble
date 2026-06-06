import XCTest
@testable import Cribble

final class MarkdownImageRewriterTests: XCTestCase {
    private var root: URL!
    private var noteDir: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rewriter-\(UUID().uuidString)", isDirectory: true)
        noteDir = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ relativeToRoot: String) throws {
        let url = root.appendingPathComponent(relativeToRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    private func rewrite(_ md: String, loadRemote: Bool = false) -> String {
        MarkdownImageRewriter.rewrite(md, noteDirectory: noteDir, rootURL: root, loadRemoteImages: loadRemote)
    }

    func testWikiEmbedResolvesToAdjacentFile() throws {
        try touch("notes/diagram.png")
        let out = rewrite("![[diagram.png]]")
        XCTAssertTrue(out.hasPrefix("![diagram.png](file://"), out)
        XCTAssertTrue(out.contains("diagram.png)"), out)
    }

    func testWikiEmbedDropsSizeHint() throws {
        try touch("notes/diagram.png")
        let out = rewrite("![[diagram.png|320]]")
        XCTAssertTrue(out.contains("![diagram.png](file://"), out)
    }

    func testWikiEmbedResolvesVaultAttachmentFolder() throws {
        try touch("attachments/photo.jpg")
        let out = rewrite("![[photo.jpg]]")
        XCTAssertTrue(out.contains("attachments/photo.jpg)"), out)
    }

    func testNonImageEmbedDowngradesToWikiLink() {
        let out = rewrite("![[Some Note]]")
        XCTAssertEqual(out, "[[Some Note]]")
    }

    func testHTMLImageBecomesMarkdown() throws {
        try touch("notes/pic.png")
        let out = rewrite("<img src=\"pic.png\" alt=\"My pic\">")
        XCTAssertTrue(out.contains("![My pic](file://"), out)
    }

    func testStandardRelativeImageResolvedFromAttachmentFolder() throws {
        try touch("assets/chart.png")
        let out = rewrite("![chart](chart.png)")
        XCTAssertTrue(out.contains("assets/chart.png)"), out)
    }

    func testRemoteImageBecomesLinkWhenDisabled() {
        let out = rewrite("![banner](https://example.com/banner.png)")
        XCTAssertTrue(out.contains("[🖼 banner](https://example.com/banner.png)"), out)
        XCTAssertFalse(out.hasPrefix("!"), out)
    }

    func testRemoteImageStaysInlineWhenEnabled() {
        let out = rewrite("![banner](https://example.com/banner.png)", loadRemote: true)
        XCTAssertEqual(out, "![banner](https://example.com/banner.png)")
    }

    func testUnresolvedImageLeftUntouched() {
        let out = rewrite("![missing](nope.png)")
        XCTAssertEqual(out, "![missing](nope.png)")
    }
}
