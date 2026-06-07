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
        XCTAssertEqual(
            SemanticSearchIndex.stableHash(title: "Setup", body: "Install the toolchain."),
            SemanticSearchIndex.stableHash(title: "Setup", body: "Install the toolchain."),
            "Identical content must hash identically so warm launches skip re-embedding."
        )
    }

    func testStableHashChangesWithContent() {
        let original = SemanticSearchIndex.stableHash(title: "Setup", body: "Install the toolchain.")
        let editedBody = SemanticSearchIndex.stableHash(title: "Setup", body: "Install the toolchain and run tests.")
        let editedTitle = SemanticSearchIndex.stableHash(title: "Setup Guide", body: "Install the toolchain.")

        XCTAssertNotEqual(original, editedBody)
        XCTAssertNotEqual(original, editedTitle)
    }

    func testMetaDerivesHashFromDocument() {
        let doc = document(title: "Setup", body: "Install the toolchain.")
        let meta = MarkdownDocumentMeta(doc)
        XCTAssertEqual(meta.contentHash, SemanticSearchIndex.stableHash(title: "Setup", body: "Install the toolchain."))
    }

    func testMetaBoundsRetainedText() {
        // A huge note must not pin its full body in the resident metadata — only
        // a bounded embedding prefix is kept.
        let big = String(repeating: "word ", count: 100_000) // ~500 KB
        let meta = MarkdownDocumentMeta(document(title: "Big", body: big))
        XCTAssertLessThanOrEqual(meta.embeddingPrefix.count, 1500)
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
