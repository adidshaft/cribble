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

    func testDocumentSignatureIgnoresLoadOrder() {
        let first = MarkdownDocumentMeta(document(title: "A", body: "Alpha"))
        let second = MarkdownDocumentMeta(document(title: "B", body: "Beta"))

        XCTAssertEqual(
            SemanticSearchIndex.documentSignature([first, second]),
            SemanticSearchIndex.documentSignature([second, first])
        )
    }

    func testDocumentSignatureChangesWithPathOrContent() {
        let original = MarkdownDocumentMeta(document(title: "A", body: "Alpha"))
        let edited = MarkdownDocumentMeta(document(title: "A", body: "Alpha edited"))
        let moved = MarkdownDocumentMeta(
            url: URL(fileURLWithPath: "/tmp/Subfolder/A.md"),
            title: original.title,
            headings: original.headings,
            outboundLinks: original.outboundLinks,
            contentHash: original.contentHash,
            embeddingPrefix: original.embeddingPrefix
        )

        let originalSignature = SemanticSearchIndex.documentSignature([original])

        XCTAssertNotEqual(originalSignature, SemanticSearchIndex.documentSignature([edited]))
        XCTAssertNotEqual(originalSignature, SemanticSearchIndex.documentSignature([moved]))
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

    func testRelatedNotesForURLRanksByCosineAndExcludesSelf() {
        let source = URL(fileURLWithPath: "/tmp/source.md")
        let near = URL(fileURLWithPath: "/tmp/near.md")
        let far = URL(fileURLWithPath: "/tmp/far.md")
        let index = SemanticSearchIndex(fileURL: temporaryIndexURL())
        index.replaceIndexForTesting([
            (source, "Source", normalize([1, 0, 0])),
            (near, "Near", normalize([0.8, 0.2, 0])),
            (far, "Far", normalize([0.2, 0.8, 0]))
        ])

        let hits = index.relatedNotes(to: source, limit: 5)

        XCTAssertEqual(hits.map(\.url), [near.standardizedFileURL, far.standardizedFileURL])
        XCTAssertGreaterThan(hits[0].score, hits[1].score)
    }

    func testRelatedNotesForURLRespectsLimitAndStableTieOrdering() {
        let source = URL(fileURLWithPath: "/tmp/source.md")
        let a = URL(fileURLWithPath: "/tmp/a.md")
        let b = URL(fileURLWithPath: "/tmp/b.md")
        let index = SemanticSearchIndex(fileURL: temporaryIndexURL())
        index.replaceIndexForTesting([
            (source, "Source", normalize([1, 0])),
            (b, "B", normalize([0.6, 0.8])),
            (a, "A", normalize([0.6, 0.8]))
        ])

        XCTAssertEqual(index.relatedNotes(to: source, limit: 1).map(\.url), [a.standardizedFileURL])
        XCTAssertEqual(index.relatedNotes(to: source, limit: 2).map(\.url), [a.standardizedFileURL, b.standardizedFileURL])
    }

    func testRelatedNotesForURLSkipsNearDuplicatesAndMissingIndexes() {
        let source = URL(fileURLWithPath: "/tmp/source.md")
        let duplicate = URL(fileURLWithPath: "/tmp/duplicate.md")
        let index = SemanticSearchIndex(fileURL: temporaryIndexURL())

        XCTAssertEqual(index.relatedNotes(to: source, limit: 5), [])

        index.replaceIndexForTesting([
            (source, "Source", normalize([1, 0])),
            (duplicate, "Duplicate", normalize([1, 0]))
        ])

        XCTAssertEqual(index.relatedNotes(to: source, limit: 5), [])
        XCTAssertEqual(index.relatedNotes(to: source, limit: 0), [])
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let magnitude = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return magnitude > 0 ? vector.map { $0 / magnitude } : vector
    }

    private func temporaryIndexURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
