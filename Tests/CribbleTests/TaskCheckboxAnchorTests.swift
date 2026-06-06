import XCTest
@testable import Cribble

final class TaskCheckboxAnchorTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("anchor-\(UUID().uuidString).md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ text: String) throws {
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func read() throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    func testStripsTrailingBlockAnchor() {
        XCTAssertEqual(TaskCheckbox.strippingBlockAnchor("- [ ] Buy milk ^cribble-ab12"), "- [ ] Buy milk")
        XCTAssertEqual(TaskCheckbox.blockAnchor(in: "- [ ] Buy milk ^cribble-ab12"), "cribble-ab12")
        XCTAssertNil(TaskCheckbox.blockAnchor(in: "- [ ] Buy milk"))
    }

    func testLocateCreatesAndPersistsAnchor() throws {
        try write("# Notes\n\n- [ ] First task\n- [ ] Second task\n")
        let located = try TaskCheckbox.locateAndAnchor(fileURL: fileURL, ordinal: 1)
        let unwrapped = try XCTUnwrap(located)
        XCTAssertEqual(unwrapped.label, "Second task")
        XCTAssertTrue(unwrapped.anchor.hasPrefix("cribble-"))

        let contents = try read()
        XCTAssertTrue(contents.contains("- [ ] Second task ^\(unwrapped.anchor)"), contents)
        // First task is untouched.
        XCTAssertTrue(contents.contains("- [ ] First task\n"), contents)
    }

    func testLocateReusesExistingAnchor() throws {
        try write("- [ ] Existing ^myid\n")
        let located = try TaskCheckbox.locateAndAnchor(fileURL: fileURL, ordinal: 0)
        XCTAssertEqual(located?.anchor, "myid")
        XCTAssertEqual(located?.label, "Existing")
        // No duplicate anchor was appended.
        let contents = try read()
        XCTAssertEqual(contents.components(separatedBy: "^myid").count - 1, 1, contents)
    }

    func testLocateSkipsFencedCode() throws {
        try write("- [ ] Real task\n\n```\n- [ ] fake in code\n```\n")
        let located = try TaskCheckbox.locateAndAnchor(fileURL: fileURL, ordinal: 0)
        XCTAssertEqual(located?.label, "Real task")
    }
}
