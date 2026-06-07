import XCTest
@testable import Cribble

final class SafeFileWriterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safewriter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testCreateRefusesToClobber() throws {
        let url = dir.appendingPathComponent("note.md")
        try SafeFileWriter.create("first", at: url)
        XCTAssertThrowsError(try SafeFileWriter.create("second", at: url))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "first")
    }

    func testOverwriteIsRecoverable() throws {
        let url = dir.appendingPathComponent("note.md")
        try SafeFileWriter.create("v1", at: url)
        try SafeFileWriter.overwrite("v2", at: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "v2")
        XCTAssertTrue(SafeFileWriter.hasBackup(for: url))

        let restored = SafeFileWriter.restoreMostRecentBackup(for: url)
        XCTAssertEqual(restored, "v1")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "v1")
    }

    func testOverwriteAbortsOnExternalChange() throws {
        let url = dir.appendingPathComponent("note.md")
        try SafeFileWriter.create("original", at: url)
        // Simulate an external edit.
        try "edited elsewhere".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(
            try SafeFileWriter.overwrite("cribble change", at: url, expectedPriorContent: "original")
        ) { error in
            guard case SafeFileWriter.WriteError.externalChange = error else {
                return XCTFail("expected externalChange, got \(error)")
            }
        }
        // The external edit survives.
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "edited elsewhere")
    }

    func testBackUpExistingThenRestore() throws {
        let url = dir.appendingPathComponent("note.md")
        try "before".write(to: url, atomically: true, encoding: .utf8)
        SafeFileWriter.backUpExisting(at: url)
        try "after".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(SafeFileWriter.restoreMostRecentBackup(for: url), "before")
    }
}
