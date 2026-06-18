import XCTest
@testable import Cribble

final class FuzzyMatchTests: XCTestCase {
    func testRankingPrefersExactPrefixAcronymThenScattered() {
        let candidates = [
            "pm",
            "pm notes",
            "Product Milestones",
            "problem"
        ]

        let ranked = FuzzyMatch.ranked(query: "pm", candidates: candidates) { [$0] }

        XCTAssertEqual(ranked, [
            "pm",
            "pm notes",
            "Product Milestones",
            "problem"
        ])
    }

    func testAcronymBeatsScatteredSubsequence() {
        let acronym = FuzzyMatch.score(query: "pm", candidate: "Product Milestones")?.score
        let scattered = FuzzyMatch.score(query: "pm", candidate: "problem")?.score

        XCTAssertNotNil(acronym)
        XCTAssertNotNil(scattered)
        XCTAssertGreaterThan(acronym ?? 0, scattered ?? 0)
    }

    func testRecencyBreaksOtherwiseEqualCandidates() {
        let candidates = ["Alpha Plan", "Alpha Plan"]
        let ranked = FuzzyMatch.ranked(
            query: "alpha",
            candidates: Array(candidates.enumerated()),
            recencyRank: { $0.offset == 0 ? 3 : 0 },
            text: { [$0.element] }
        )

        XCTAssertEqual(ranked.first?.offset, 1)
    }

    func testScoreMatchesCaseAndDiacriticsCalmly() {
        let plain = FuzzyMatch.score(query: "cafe", candidate: "Café Notes")

        XCTAssertNotNil(plain)
        XCTAssertEqual(plain?.matchedOffsets, [0, 1, 2, 3])
    }
}
