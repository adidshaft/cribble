import XCTest
@testable import Cribble

final class RelatedNotesSectionTests: XCTestCase {
    func testScoreFractionClampsBelowThreshold() {
        XCTAssertEqual(RelatedNotesSectionModel.scoreFraction(0), 0, accuracy: 0.0001)
        XCTAssertEqual(RelatedNotesSectionModel.scoreFraction(0.16), 0, accuracy: 0.0001)
    }

    func testScoreFractionScalesSemanticScores() {
        XCTAssertEqual(RelatedNotesSectionModel.scoreFraction(0.58), 0.5, accuracy: 0.0001)
    }

    func testScoreFractionClampsHighScores() {
        XCTAssertEqual(RelatedNotesSectionModel.scoreFraction(1), 1, accuracy: 0.0001)
        XCTAssertEqual(RelatedNotesSectionModel.scoreFraction(1.2), 1, accuracy: 0.0001)
    }
}
