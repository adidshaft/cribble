import XCTest
@testable import Cribble

final class TaskCheckboxTests: XCTestCase {
    private func tempFile(_ data: Data, name: String = "tasks.md") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CribbleTaskTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func tempFile(_ text: String, name: String = "tasks.md") throws -> URL {
        try tempFile(Data(text.utf8), name: name)
    }

    // MARK: - Parsing

    func testParsesTaskVariants() {
        XCTAssertEqual(TaskCheckbox.parse(line: "- [ ] buy milk")?.isChecked, false)
        XCTAssertEqual(TaskCheckbox.parse(line: "- [x] done")?.isChecked, true)
        XCTAssertEqual(TaskCheckbox.parse(line: "* [X] star marker")?.isChecked, true)
        XCTAssertEqual(TaskCheckbox.parse(line: "  + [ ] indented")?.indent, 2)
        XCTAssertEqual(TaskCheckbox.parse(line: "- [ ] label here")?.label, "label here")
    }

    func testRejectsNonTaskLines() {
        XCTAssertNil(TaskCheckbox.parse(line: "- a normal bullet"))
        XCTAssertNil(TaskCheckbox.parse(line: "regular text"))
        XCTAssertNil(TaskCheckbox.parse(line: "[ ] no bullet"))
        XCTAssertNil(TaskCheckbox.parse(line: "- [] missing state"))
    }

    // MARK: - Toggle

    func testToggleFlipsCorrectOrdinalAndPreservesEverythingElse() throws {
        let url = try tempFile("# Tasks\n- [ ] zero\n- [ ] one\n- [x] two\n")
        let result = try TaskCheckbox.toggle(fileURL: url, ordinal: 1, expectedCurrentChecked: false)
        XCTAssertEqual(result, .toggled)
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(after, "# Tasks\n- [ ] zero\n- [x] one\n- [x] two\n")
    }

    func testToggleUnchecks() throws {
        let url = try tempFile("- [x] done\n")
        XCTAssertEqual(try TaskCheckbox.toggle(fileURL: url, ordinal: 0, expectedCurrentChecked: true), .toggled)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "- [ ] done\n")
    }

    func testToggleRefusesOnStateMismatch() throws {
        let url = try tempFile("- [x] already done\n")
        // We think it's unchecked, but on disk it's checked → must not write.
        let result = try TaskCheckbox.toggle(fileURL: url, ordinal: 0, expectedCurrentChecked: false)
        XCTAssertEqual(result, .stateMismatch)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "- [x] already done\n")
    }

    func testToggleSkipsCheckboxesInsideFencedCode() throws {
        let text = """
        - [ ] real one
        ```
        - [ ] fake (in code block)
        ```
        - [ ] real two
        """
        let url = try tempFile(text)
        // ordinal 1 should be "real two", NOT the one inside the code fence.
        XCTAssertEqual(try TaskCheckbox.toggle(fileURL: url, ordinal: 1, expectedCurrentChecked: false), .toggled)
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("- [x] real two"))
        XCTAssertTrue(after.contains("- [ ] fake (in code block)"), "Checkbox inside a code fence must be untouched")
    }

    func testToggleSkipsFrontMatter() throws {
        let text = """
        ---
        tasks:
          - [ ] not a real task (yaml)
        ---
        - [ ] the real task
        """
        let url = try tempFile(text)
        XCTAssertEqual(try TaskCheckbox.toggle(fileURL: url, ordinal: 0, expectedCurrentChecked: false), .toggled)
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("- [x] the real task"))
        XCTAssertTrue(after.contains("- [ ] not a real task (yaml)"), "Front-matter content must be untouched")
    }

    func testTogglePreservesNonUTF8Bytes() throws {
        // "- [ ] café\n" but with café encoded as Latin-1 (0xE9 for é).
        var bytes = Array("- [ ] caf".utf8)
        bytes.append(0xE9) // é in Latin-1 — invalid UTF-8
        bytes.append(0x0A)
        let url = try tempFile(Data(bytes))

        XCTAssertEqual(try TaskCheckbox.toggle(fileURL: url, ordinal: 0, expectedCurrentChecked: false), .toggled)

        let after = try Data(contentsOf: url)
        var expected = Array("- [x] caf".utf8)
        expected.append(0xE9)
        expected.append(0x0A)
        XCTAssertEqual(Array(after), expected, "Only the state byte should change; the 0xE9 byte must be preserved.")
    }

    func testToggleNotFoundForOutOfRangeOrdinal() throws {
        let url = try tempFile("- [ ] only one\n")
        XCTAssertEqual(try TaskCheckbox.toggle(fileURL: url, ordinal: 5, expectedCurrentChecked: false), .notFound)
    }
}
