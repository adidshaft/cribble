import XCTest
@testable import Cribble

final class UnifiedDiffTests: XCTestCase {
    func testParsesAndAppliesUnifiedDiff() throws {
        let root = try Fixture.makeFolder()
        let note = root.appendingPathComponent("Note.md")
        try """
        # Note
        This mentions Alpha.
        """.write(to: note, atomically: true, encoding: .utf8)

        let diff = UnifiedDiffParser.parse("""
        --- a/Note.md
        +++ b/Note.md
        @@ -1,2 +1,2 @@
         # Note
        -This mentions Alpha.
        +This mentions [[Alpha]].
        """)

        try DiffApplier().apply(diff, rootURL: root)
        let updated = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(updated.contains("[[Alpha]]"))
    }

    func testExtractsDiffFromNoisyCLIOutputAndCleansOnlyLeadingPrefixes() {
        let diff = UnifiedDiffParser.parse(UnifiedDiffParser.extractDiffText(from: """
        warning: noisy cli prelude
        diff --git a/data/brain.md b/data/brain.md
        --- a/data/brain.md\t2026-05-25
        +++ b/data/brain.md\t2026-05-25
        @@ -1 +1 @@
        -Alpha
        +[[Alpha]]
        """))

        XCTAssertEqual(diff.files.first?.oldPath, "data/brain.md")
        XCTAssertEqual(diff.files.first?.newPath, "data/brain.md")
    }
}
