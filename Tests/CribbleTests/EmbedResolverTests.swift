import XCTest
@testable import Cribble

final class EmbedResolverTests: XCTestCase {
    func testResolvesWholeNoteHeadingAndBlockSlices() throws {
        let root = try Fixture.makeFolder()
        let source = root.appendingPathComponent("Source.md")
        let target = root.appendingPathComponent("Target.md")

        try "# Source\n\n![[Target]]".write(to: source, atomically: true, encoding: .utf8)
        try """
        # Target

        Intro.

        ## Decisions
        Keep this.
        ### Detail
        Keep detail.
        ## Later
        Skip this.

        - [ ] Task body ^task-1
        """.write(to: target, atomically: true, encoding: .utf8)

        let loader = DocumentLoader()
        let documents = try [loader.load(url: source), loader.load(url: target)]
        let resolver = EmbedResolver(documents: documents, rootURL: root)

        let whole = resolver.resolve(reference("![[Target]]"), sourceURL: source)
        XCTAssertEqual(whole.state, .resolved)
        XCTAssertEqual(whole.targetURL, target.standardizedFileURL)
        XCTAssertTrue(whole.markdown.contains("# Target"))

        let heading = resolver.resolve(reference("![[Target#Decisions]]"), sourceURL: source)
        XCTAssertEqual(heading.markdown, "## Decisions\nKeep this.\n### Detail\nKeep detail.")

        let block = resolver.resolve(reference("![[Target^task-1]]"), sourceURL: source)
        XCTAssertEqual(block.markdown, "- [ ] Task body")
    }

    func testUnresolvedEmbedReturnsMutedFallbackState() throws {
        let root = try Fixture.makeFolder()
        let source = root.appendingPathComponent("Source.md")
        try "# Source".write(to: source, atomically: true, encoding: .utf8)

        let document = try DocumentLoader().load(url: source)
        let resolved = EmbedResolver(documents: [document], rootURL: root)
            .resolve(reference("![[Missing]]"), sourceURL: source)

        XCTAssertEqual(resolved.state, .unresolved)
        XCTAssertNil(resolved.targetURL)
        XCTAssertTrue(resolved.markdown.contains("Cannot resolve"))
    }

    func testDetectsCyclesAcrossNestedEmbeds() throws {
        let root = try Fixture.makeFolder()
        let a = root.appendingPathComponent("A.md")
        let b = root.appendingPathComponent("B.md")

        try "# A\n\n![[B]]".write(to: a, atomically: true, encoding: .utf8)
        try "# B\n\n![[A]]".write(to: b, atomically: true, encoding: .utf8)

        let loader = DocumentLoader()
        let resolver = EmbedResolver(documents: try [loader.load(url: a), loader.load(url: b)], rootURL: root)

        XCTAssertTrue(resolver.containsCycle(in: "![[B]]", sourceURL: a))
        let cyclic = resolver.resolve(reference("![[A]]"), sourceURL: b, visited: [a.standardizedFileURL])
        XCTAssertEqual(cyclic.state, .cyclic)
        XCTAssertTrue(cyclic.markdown.contains("Cyclic embed"))
    }

    func testDepthLimitStopsResolution() throws {
        let root = try Fixture.makeFolder()
        let a = root.appendingPathComponent("A.md")
        let b = root.appendingPathComponent("B.md")

        try "# A\n\n![[B]]".write(to: a, atomically: true, encoding: .utf8)
        try "# B\n\nBody".write(to: b, atomically: true, encoding: .utf8)

        let loader = DocumentLoader()
        let resolver = EmbedResolver(documents: try [loader.load(url: a), loader.load(url: b)], rootURL: root, maxDepth: 0)
        let resolved = resolver.resolve(reference("![[B]]"), sourceURL: a, depth: 1)

        XCTAssertEqual(resolved.state, .depthLimited)
        XCTAssertTrue(resolved.markdown.contains("depth limit"))
    }

    private func reference(_ markdown: String) -> EmbedReference {
        guard let reference = WikiLinkParser.parseEmbeds(markdown).first else {
            XCTFail("Expected embed reference")
            return EmbedReference(original: markdown, target: "", label: "", heading: nil, blockID: nil)
        }
        return reference
    }
}
