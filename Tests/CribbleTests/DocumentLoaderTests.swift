import XCTest
@testable import Cribble

final class DocumentLoaderTests: XCTestCase {
    private func tempURL(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CribbleLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    func testReadsValidUTF8Verbatim() throws {
        let url = try tempURL("a.md")
        let content = "# Héllo\nWörld 🌍 — café"
        try content.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try DocumentLoader.readText(at: url), content)
    }

    func testReadsInvalidUTF8WithoutThrowing() throws {
        // Bytes that are not valid UTF-8 (lone continuation / overlong / 0xFF).
        let url = try tempURL("b.md")
        try Data([0x23, 0x20, 0x42, 0xFF, 0xFE, 0xC0, 0x80, 0x0A]).write(to: url)

        let text = try DocumentLoader.readText(at: url)
        XCTAssertFalse(text.isEmpty, "A non-UTF-8 file should still decode via a fallback encoding, not throw.")
    }

    func testLoadDoesNotThrowOnBinaryishMarkdown() throws {
        // JPEG-like header bytes saved under a .md extension.
        let url = try tempURL("c.md")
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]).write(to: url)

        XCTAssertNoThrow(try DocumentLoader().load(url: url),
                         "A binary file with a .md extension must not break loading the folder it lives in.")
    }

    @MainActor
    func testFolderWithUnreadableFileStillLoadsTheRest() throws {
        let root = try Fixture.makeFolder()
        try "# Good Note\n\nReadable.".write(to: root.appendingPathComponent("Good.md"), atomically: true, encoding: .utf8)
        try Data([0xFF, 0xFE, 0xFD, 0xFC]).write(to: root.appendingPathComponent("Weird.md"))

        let store = MarkdownLibraryStore(restore: false, includeBundledDemo: false)
        store.openFolder(root, sortMode: .name)
        let exp = expectation(description: "scan")
        Task { await store.waitForLoadToComplete(); exp.fulfill() }
        wait(for: [exp], timeout: 3.0)

        // The whole folder open must succeed — no fatal error surfaced.
        XCTAssertNil(store.errorMessage)
        // The readable note is available for selection.
        let goodURL = root.appendingPathComponent("Good.md")
        store.select(url: goodURL)
        XCTAssertEqual(store.selectedDocument?.url.standardizedFileURL, goodURL.standardizedFileURL)
    }
}
