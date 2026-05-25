import XCTest
@testable import Cribble

final class FolderScannerTests: XCTestCase {
    func testScannerIncludesOnlyFoldersWithMarkdownAndMarkdownFiles() throws {
        let root = try Fixture.makeFolder()
        try "# One".write(to: root.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)
        try "ignore".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        try "# Two".write(to: root.appendingPathComponent("Nested/two.md"), atomically: true, encoding: .utf8)

        let nodes = try FolderScanner().scan(rootURL: root)

        XCTAssertEqual(nodes.map(\.name), ["Nested", "one", "README"])
        XCTAssertEqual(nodes.first?.children.map(\.name), ["README", "two"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Nested/README.md").path))
    }

    func testScannerSortsMarkdownFilesByModifiedDateNewestFirst() throws {
        let root = try Fixture.makeFolder()
        let older = root.appendingPathComponent("older.md")
        let newer = root.appendingPathComponent("newer.md")
        try "# Older".write(to: older, atomically: true, encoding: .utf8)
        try "# Newer".write(to: newer, atomically: true, encoding: .utf8)

        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: newer.path)

        let nodes = try FolderScanner(fileSortMode: .modified).scan(rootURL: root)
        let markdownNames = nodes.filter { $0.kind == .markdown && $0.name != "README" }.map(\.name)

        XCTAssertEqual(markdownNames, ["newer", "older"])
    }
}
