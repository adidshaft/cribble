import XCTest
@testable import Cribble

@MainActor
final class SemanticSearchIndexTests: XCTestCase {
    private func document(title: String, body: String) -> MarkdownDocument {
        MarkdownDocument(
            url: URL(fileURLWithPath: "/tmp/\(title).md"),
            title: title,
            rawMarkdown: body,
            headings: [],
            outboundLinks: []
        )
    }

    func testStableHashIsDeterministicAcrossInstances() {
        let a = document(title: "Setup", body: "Install the toolchain.")
        let b = document(title: "Setup", body: "Install the toolchain.")
        XCTAssertEqual(
            SemanticSearchIndex.stableHash(for: a),
            SemanticSearchIndex.stableHash(for: b),
            "Identical content must hash identically so warm launches skip re-embedding."
        )
    }

    func testStableHashChangesWithContent() {
        let original = document(title: "Setup", body: "Install the toolchain.")
        let editedBody = document(title: "Setup", body: "Install the toolchain and run tests.")
        let editedTitle = document(title: "Setup Guide", body: "Install the toolchain.")

        XCTAssertNotEqual(SemanticSearchIndex.stableHash(for: original), SemanticSearchIndex.stableHash(for: editedBody))
        XCTAssertNotEqual(SemanticSearchIndex.stableHash(for: original), SemanticSearchIndex.stableHash(for: editedTitle))
    }

    func testCosineOfIdenticalNormalizedVectorsIsOne() {
        let vector: [Float] = normalize([0.2, 0.5, -0.1, 0.84])
        XCTAssertEqual(SemanticSearchIndex.cosine(vector, vector), 1, accuracy: 0.0001)
    }

    func testCosineOfOrthogonalVectorsIsZero() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        XCTAssertEqual(SemanticSearchIndex.cosine(a, b), 0, accuracy: 0.0001)
    }

    func testCosineHandlesMismatchedLengthsSafely() {
        XCTAssertEqual(SemanticSearchIndex.cosine([1, 0], [1, 0, 0]), 0)
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let magnitude = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return magnitude > 0 ? vector.map { $0 / magnitude } : vector
    }
}
