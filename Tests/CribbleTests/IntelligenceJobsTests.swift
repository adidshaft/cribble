import XCTest
@testable import Cribble

private final class StubProvider: IntelligenceProvider {
    let displayName = "Stub"
    let text: String
    init(text: String) { self.text = text }
    func checkAvailability() async -> ProviderAvailability { .available }
    func generate(prompt: [EngineMessage], schema: JSONSchemaHint?, maxTokens: Int) async throws -> String { text }
    func embed(text: String) async throws -> [Float]? { nil }
}

private final class SlowStubProvider: IntelligenceProvider {
    let displayName = "Slow Stub"
    func checkAvailability() async -> ProviderAvailability { .available }
    func generate(prompt: [EngineMessage], schema: JSONSchemaHint?, maxTokens: Int) async throws -> String {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return "# Too late"
    }
    func embed(text: String) async throws -> [Float]? { nil }
}

final class IntelligenceJobsTests: XCTestCase {

    // MARK: - DependencyGraph

    func testDependencyGraphBuildsImportAndUsesEdges() {
        let symbols = [
            SymbolRecord(fileID: 1, filePath: "A.swift", name: "Foundation", kind: "import", startLine: 1, endLine: 1, signature: "import Foundation"),
            SymbolRecord(fileID: 1, filePath: "A.swift", name: "Engine", kind: "type", startLine: 3, endLine: 9, signature: "struct Engine"),
            SymbolRecord(fileID: 2, filePath: "B.swift", name: "run", kind: "function", startLine: 1, endLine: 3, signature: "func run(engine: Engine)")
        ]
        let graph = DependencyGraph.build(from: symbols)
        XCTAssertTrue(graph.edges.contains(.init(from: "A.swift", to: "module:Foundation", label: "import")))
        XCTAssertTrue(graph.edges.contains(.init(from: "B.swift", to: "A.swift", label: "uses")))
        let mermaid = graph.mermaid()
        XCTAssertTrue(OutputValidator.validateMermaid(mermaid).isValid)
    }

    func testDependencyGraphDrift() {
        let base: [DependencyGraph.Edge] = [.init(from: "A", to: "B", label: "uses")]
        let graph = DependencyGraph(nodes: ["A": "A", "C": "C"], edges: [.init(from: "A", to: "C", label: "uses")])
        let drift = graph.drift(comparedToDocumented: base)
        XCTAssertEqual(drift.count, 2)
        XCTAssertTrue(drift.contains { $0.kind == .missingInCode && $0.edge.to == "B" })
        XCTAssertTrue(drift.contains { $0.kind == .missingInDiagram && $0.edge.to == "C" })
    }

    // MARK: - OutputValidator

    func testMarkdownValidatorFlagsUnknownPaths() {
        let known: Set<String> = ["Sources/App/Engine.swift"]
        XCTAssertTrue(OutputValidator.validateMarkdown("Uses Sources/App/Engine.swift here", knownPaths: known).isValid)
        XCTAssertFalse(OutputValidator.validateMarkdown("See made/up/path.swift", knownPaths: known).isValid)
        // Bare filename mention (no slash) is allowed.
        XCTAssertTrue(OutputValidator.validateMarkdown("The Engine.swift file", knownPaths: known).isValid)
    }

    func testMermaidValidator() {
        XCTAssertTrue(OutputValidator.validateMermaid("graph LR\n  a-->b").isValid)
        XCTAssertFalse(OutputValidator.validateMermaid("not a diagram").isValid)
        XCTAssertFalse(OutputValidator.validateMermaid("graph LR\n  a[unbalanced-->b").isValid)
    }

    // MARK: - Error-output rejection (the 401 bug)

    func testLooksLikeErrorRejectsAuthFailures() {
        XCTAssertNotNil(OutputValidator.looksLikeError("Failed to authenticate. API Error: 401 Invalid authentication credentials"))
        XCTAssertNotNil(OutputValidator.looksLikeError("Error: 403"))
        XCTAssertNotNil(OutputValidator.looksLikeError("zsh: command not found: claude"))
        // A real, longer summary that merely discusses auth must NOT be rejected.
        let realSummary = String(repeating: "This module validates bearer tokens and returns a status when the session is missing. ", count: 6)
        XCTAssertNil(OutputValidator.looksLikeError(realSummary))
    }

    func testStripReasoningPreambleKeepsRequestedMarkdown() {
        let raw = """
        <think>I should reason about the user's request first.</think>
        The user wants me to find conceptual connections and output Markdown only.

        # Suggested Connections
        - `A.swift` => `B.swift`: B uses A.
        """
        let cleaned = OutputValidator.stripReasoningPreamble(raw)
        XCTAssertTrue(cleaned.hasPrefix("# Suggested Connections"))
        XCTAssertFalse(cleaned.contains("The user wants me"))
        XCTAssertFalse(cleaned.contains("<think>"))
        XCTAssertTrue(OutputValidator.looksLikeReasoningLeak("The user wants me to output Markdown only."))
        XCTAssertFalse(OutputValidator.looksLikeReasoningLeak(cleaned))
    }

    func testReasoningLeakDetectsPlannerWithoutRecoverableHeading() {
        let raw = """
        The user wants a chronological timeline of events in the document collection.
        I need to scan through the provided text for dates and ordering cues.

        Let's look at the input text:
        1. README.md: no explicit dates.
        """

        let cleaned = OutputValidator.stripReasoningPreamble(raw)
        XCTAssertEqual(cleaned, raw.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertTrue(OutputValidator.looksLikeReasoningLeak(cleaned))
    }

    func testRunnerDoesNotStoreErrorOutput() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-err-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct A {}".write(to: root.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        _ = await WorkspaceScanner(db: db, projectID: "p", rootURL: root).scan()
        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        let provider = StubProvider(text: "Failed to authenticate. API Error: 401 Invalid authentication credentials")
        let runner = JobRunner(db: db, scheduler: scheduler, artifacts: artifacts, provider: provider, projectID: "p", rootURL: root)

        await runner.drain(limit: 10)
        let produced = await db.artifacts(projectID: "p")
        XCTAssertTrue(produced.isEmpty, "Auth-error output must not be stored as an artifact")
        // The job should have failed rather than completed.
        let completed = await db.jobs(projectID: "p", status: .completed).count
        XCTAssertEqual(completed, 0)
    }

    // MARK: - Memory-pressure gating

    func testSchedulerHaltsUnderMemoryPressure() {
        let c = BackgroundScheduler.Conditions(
            userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false,
            appIsActive: false, appIsForeground: false, memoryPressured: true
        )
        XCTAssertEqual(BackgroundScheduler.policy(for: c, idleThreshold: 60), .none)
    }

    // MARK: - Vector index (semantic Ask)

    func testVectorIndexSearchRanksBySimilarity() async throws {
        let db = try IntelligenceDatabase(path: ":memory:")
        func artifact(_ id: String) -> IntelligenceArtifact {
            IntelligenceArtifact(id: id, projectID: "p", type: .fileSummary, relativePath: "\(id).md",
                                 title: id, contentHash: "c", sourceHashes: ["h"], isPublished: false)
        }
        await db.insertArtifact(artifact("a"))
        await db.insertArtifact(artifact("b"))
        await db.upsertEmbedding(artifactID: "a", projectID: "p", vector: [1, 0, 0])
        await db.upsertEmbedding(artifactID: "b", projectID: "p", vector: [0, 1, 0])

        let index = SQLiteVectorIndex(db: db, projectID: "p")
        let count = await index.count()
        XCTAssertEqual(count, 2)
        let hits = await index.search([0.9, 0.1, 0], limit: 2)
        XCTAssertEqual(hits.first?.id, "a", "Closest vector should rank first")
    }

    // MARK: - DemoNotes seeding

    func testDemoSeederSeedsExampleArtifacts() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Welcome".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "# Getting Started".write(to: root.appendingPathComponent("Getting Started.md"), atomically: true, encoding: .utf8)
        try "# Tour".write(to: root.appendingPathComponent("Feature Tour.md"), atomically: true, encoding: .utf8)
        try "# Showcase".write(to: root.appendingPathComponent("Markdown Showcase.md"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        let store = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        let seeded = await DemoSeeder.seedIfDemoNotes(rootURL: root, store: store, db: db, projectID: "p")
        XCTAssertTrue(seeded)
        let artifacts = await db.artifacts(projectID: "p")
        let types = Set(artifacts.map(\.type))
        XCTAssertTrue(types.contains(.projectIndex))
        XCTAssertTrue(types.contains(.architectureDiagram))
        let seededContent = artifacts
            .compactMap { store.content(for: $0) }
            .joined(separator: "\n")
        XCTAssertFalse(seededContent.contains("Diagnostics.md"))
        XCTAssertTrue(seededContent.contains("Extensions and Remote Intelligence"))
        XCTAssertTrue(seededContent.contains("Tasks and Intelligence"))
        XCTAssertTrue(seededContent.contains("Team Extension Kit"))
        XCTAssertTrue(seededContent.contains("Decision Log"))

        let staleDemo = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-stale-demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staleDemo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staleDemo) }
        try "# Tour".write(to: staleDemo.appendingPathComponent("Feature Tour.md"), atomically: true, encoding: .utf8)
        try "# Showcase".write(to: staleDemo.appendingPathComponent("Markdown Showcase.md"), atomically: true, encoding: .utf8)
        let staleDB = try IntelligenceDatabase(path: ":memory:")
        let staleStore = ArtifactStore(db: staleDB, projectID: "stale", cacheDirectory: staleDemo.appendingPathComponent("c"))
        let staleSeeded = await DemoSeeder.seedIfDemoNotes(rootURL: staleDemo, store: staleStore, db: staleDB, projectID: "stale")
        XCTAssertFalse(staleSeeded)

        // A non-demo folder is left alone.
        let empty = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-nodemo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let db2 = try IntelligenceDatabase(path: ":memory:")
        let store2 = ArtifactStore(db: db2, projectID: "q", cacheDirectory: empty.appendingPathComponent("c"))
        let seeded2 = await DemoSeeder.seedIfDemoNotes(rootURL: empty, store: store2, db: db2, projectID: "q")
        XCTAssertFalse(seeded2)
    }

    // MARK: - Clickable diagram links

    func testDependencyGraphEmitsClickLinks() {
        let symbols = [
            SymbolRecord(fileID: 1, filePath: "App/Engine.swift", name: "Engine", kind: "type", startLine: 1, endLine: 5, signature: "struct Engine")
        ]
        let graph = DependencyGraph.build(from: symbols)
        let mermaid = graph.mermaid(clickable: true)
        XCTAssertTrue(mermaid.contains("click "))
        XCTAssertTrue(mermaid.contains("call cribbleOpen(\"App/Engine.swift\")"))
        // Still structurally valid.
        XCTAssertTrue(OutputValidator.validateMermaid(mermaid).isValid)
    }

    // MARK: - Note connections graph

    func testNoteConnectionsGraphFromWikiLinks() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-conn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "See [[Beta]] and [[Gamma|the third]].".write(to: root.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8)
        try "Back to [[Alpha]].".write(to: root.appendingPathComponent("Beta.md"), atomically: true, encoding: .utf8)
        try "# Gamma".write(to: root.appendingPathComponent("Gamma.md"), atomically: true, encoding: .utf8)

        let files = ["Alpha.md", "Beta.md", "Gamma.md"].map { (path: $0, url: root.appendingPathComponent($0)) }
        let graph = NoteConnectionsGraph.build(markdownFiles: files)
        XCTAssertTrue(graph.edges.contains(.init(from: "Alpha.md", to: "Beta.md", label: "links")))
        XCTAssertTrue(graph.edges.contains(.init(from: "Alpha.md", to: "Gamma.md", label: "links")))
        XCTAssertTrue(graph.edges.contains(.init(from: "Beta.md", to: "Alpha.md", label: "links")))
        // Alias + heading targets parse to the bare note name.
        XCTAssertEqual(Set(NoteConnectionsGraph.wikiLinkTargets(in: "[[A|x]] [[B#h]]")), ["A", "B"])
    }

    // MARK: - IO behavior executor

    func testIOBehaviorAuditIsGeneratedForCodeFiles() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-io-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "import Foundation\nstruct Net { func get() {} }".write(to: root.appendingPathComponent("Net.swift"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        _ = await WorkspaceScanner(db: db, projectID: "p", rootURL: root).scan()
        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        let provider = StubProvider(text: "# I/O\n\n- Network: `get()` performs a request.")
        let runner = JobRunner(db: db, scheduler: scheduler, artifacts: artifacts, provider: provider, projectID: "p", rootURL: root)
        await runner.drain(limit: 20)

        let types = Set(await db.artifacts(projectID: "p").map(\.type))
        XCTAssertTrue(types.contains(.ioBehavior))
        XCTAssertTrue(types.contains(.fallbackAudit))
    }

    func testScannerEnqueuesOneAnalysisJobForCodeFiles() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-analysis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct Net { func get() {} }".write(to: root.appendingPathComponent("Net.swift"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        _ = await WorkspaceScanner(db: db, projectID: "p", rootURL: root).scan()
        let jobs = await db.jobs(projectID: "p", status: .pending)
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.type, .analyzeFile)
    }

    func testAnalyzeFileSplitsStructuredOutputIntoArtifacts() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct Net { func get() {} }".write(to: root.appendingPathComponent("Net.swift"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        _ = await WorkspaceScanner(db: db, projectID: "p", rootURL: root).scan()
        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        let provider = StubProvider(text: """
        ## Summary
        Net owns a request helper.

        ## Fallbacks
        No explicit fallbacks found.

        ## I/O Behavior
        - `get()` performs network I/O.
        """)
        let runner = JobRunner(db: db, scheduler: scheduler, artifacts: artifacts, provider: provider, projectID: "p", rootURL: root)
        await runner.drain(limit: 10)

        let produced = await db.artifacts(projectID: "p")
        let types = Set(produced.map(\.type))
        XCTAssertTrue(types.contains(.fileSummary))
        XCTAssertTrue(types.contains(.fallbackAudit))
        XCTAssertTrue(types.contains(.ioBehavior))
        let nodes = await db.knowledgeNodes(projectID: "p")
        XCTAssertTrue(nodes.contains { $0.path == "Net.swift" })
    }

    func testProjectIndexFallsBackWhenProviderReturnsEmptyOutput() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-index-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Alpha\n\nDefines the first note.".write(to: root.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8)
        try "# Beta\n\nReferences Alpha.".write(to: root.appendingPathComponent("Beta.md"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        let alphaHash = try XCTUnwrap(ContentHasher.hashFile(at: root.appendingPathComponent("Alpha.md")))
        let betaHash = try XCTUnwrap(ContentHasher.hashFile(at: root.appendingPathComponent("Beta.md")))
        _ = await db.upsertFile(projectID: "p", path: "Alpha.md", hash: alphaHash, sizeBytes: 29, language: "markdown")
        _ = await db.upsertFile(projectID: "p", path: "Beta.md", hash: betaHash, sizeBytes: 25, language: "markdown")
        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        for file in await db.files(projectID: "p") {
            _ = try await artifacts.store(
                type: .fileSummary,
                relativePath: "summaries/\(file.hash).md",
                title: file.path,
                content: "\(file.path) is available for indexing.",
                sourceHashes: [file.hash]
            )
        }
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .updateProjectIndex, inputHash: "project-index", priority: 0))

        let provider = StubProvider(text: "")
        let runner = JobRunner(db: db, scheduler: scheduler, artifacts: artifacts, provider: provider, projectID: "p", rootURL: root)
        await runner.drain(limit: 5)

        let produced = await db.artifacts(projectID: "p", type: .projectIndex)
        let index = try XCTUnwrap(produced.first)
        let content = try XCTUnwrap(artifacts.content(for: index))
        XCTAssertTrue(content.hasPrefix("# cribble-index-fallback-"))
        XCTAssertTrue(content.contains("## Components"))
        XCTAssertTrue(content.contains("`Alpha.md`"))
        XCTAssertTrue(content.contains("`Beta.md`"))
        let failed = await db.jobs(projectID: "p", status: .failed)
        XCTAssertTrue(failed.isEmpty)
    }

    func testGenericInsightsFallBackWhenProviderReturnsEmptyOutput() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-insights-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Alpha\n\nThe Alpha launch plan mentions WWDC 2026 and Project Atlas.".write(to: root.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8)
        try "# Beta\n\nBeta tracks Project Atlas decisions from 2026-06-07.".write(to: root.appendingPathComponent("Beta.md"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        let alphaHash = try XCTUnwrap(ContentHasher.hashFile(at: root.appendingPathComponent("Alpha.md")))
        let betaHash = try XCTUnwrap(ContentHasher.hashFile(at: root.appendingPathComponent("Beta.md")))
        _ = await db.upsertFile(projectID: "p", path: "Alpha.md", hash: alphaHash, sizeBytes: 66, language: "markdown")
        _ = await db.upsertFile(projectID: "p", path: "Beta.md", hash: betaHash, sizeBytes: 58, language: "markdown")

        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        _ = try await artifacts.store(
            type: .fileSummary,
            relativePath: "summaries/alpha.md",
            title: "Alpha.md",
            content: "Alpha.md covers the Alpha launch plan, WWDC 2026, and Project Atlas.",
            sourceHashes: [alphaHash]
        )
        _ = try await artifacts.store(
            type: .fileSummary,
            relativePath: "summaries/beta.md",
            title: "Beta.md",
            content: "Beta.md tracks Project Atlas decisions on 2026-06-07.",
            sourceHashes: [betaHash]
        )

        let combined = ContentHasher.combine([alphaHash, betaHash].sorted())
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .detectContradictions, inputHash: combined, priority: 200))
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .buildGlossary, inputHash: combined, priority: 190))
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .buildTimeline, inputHash: combined, priority: 180))

        let provider = StubProvider(text: "")
        let runner = JobRunner(db: db, scheduler: scheduler, artifacts: artifacts, provider: provider, projectID: "p", rootURL: root)
        await runner.drain(limit: 10)

        let produced = await db.artifacts(projectID: "p")
        let types = Set(produced.map(\.type))
        XCTAssertTrue(types.contains(.contradictionReport))
        XCTAssertTrue(types.contains(.glossary))
        XCTAssertTrue(types.contains(.timeline))

        let contradiction = try XCTUnwrap(produced.first { $0.type == .contradictionReport })
        let glossary = try XCTUnwrap(produced.first { $0.type == .glossary })
        let timeline = try XCTUnwrap(produced.first { $0.type == .timeline })
        XCTAssertTrue(try XCTUnwrap(artifacts.content(for: contradiction)).contains("No contradictions found"))
        XCTAssertTrue(try XCTUnwrap(artifacts.content(for: glossary)).contains("Project Atlas"))
        XCTAssertTrue(try XCTUnwrap(artifacts.content(for: timeline)).contains("2026-06-07"))
        let failed = await db.jobs(projectID: "p", status: .failed)
        XCTAssertTrue(failed.isEmpty)
    }

    func testGenericInsightCompletesWithFallbackWhenProviderTimesOut() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-insights-timeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let db = try IntelligenceDatabase(path: ":memory:")
        let alphaHash = ContentHasher.hash("alpha")
        let betaHash = ContentHasher.hash("beta")
        _ = await db.upsertFile(projectID: "p", path: "Alpha.md", hash: alphaHash, sizeBytes: 5, language: "markdown")
        _ = await db.upsertFile(projectID: "p", path: "Beta.md", hash: betaHash, sizeBytes: 4, language: "markdown")
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        _ = try await artifacts.store(type: .fileSummary, relativePath: "summaries/alpha.md", title: "Alpha.md", content: "Alpha mentions Project Atlas.", sourceHashes: [alphaHash])
        _ = try await artifacts.store(type: .fileSummary, relativePath: "summaries/beta.md", title: "Beta.md", content: "Beta mentions Project Atlas.", sourceHashes: [betaHash])

        let combined = ContentHasher.combine([alphaHash, betaHash].sorted())
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .detectContradictions, inputHash: combined, priority: 200))
        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let runner = JobRunner(
            db: db,
            scheduler: scheduler,
            artifacts: artifacts,
            provider: SlowStubProvider(),
            projectID: "p",
            rootURL: root,
            jobTimeoutSeconds: 0.05
        )

        await runner.drain(limit: 1)

        let reports = await db.artifacts(projectID: "p", type: .contradictionReport)
        let report = try XCTUnwrap(reports.first)
        XCTAssertTrue(try XCTUnwrap(artifacts.content(for: report)).contains("No contradictions found"))
        let completed = await db.jobs(projectID: "p", status: .completed)
        let pending = await db.jobs(projectID: "p", status: .pending)
        let failed = await db.jobs(projectID: "p", status: .failed)
        XCTAssertEqual(completed.count, 1)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(failed.isEmpty)
    }

    func testDiscoverConnectionsCompletesWithFallbackWhenProviderTimesOut() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-research-timeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let db = try IntelligenceDatabase(path: ":memory:")
        let alphaHash = ContentHasher.hash("alpha")
        let betaHash = ContentHasher.hash("beta")
        _ = await db.upsertFile(projectID: "p", path: "Alpha.md", hash: alphaHash, sizeBytes: 5, language: "markdown")
        _ = await db.upsertFile(projectID: "p", path: "Beta.md", hash: betaHash, sizeBytes: 4, language: "markdown")
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        _ = try await artifacts.store(type: .fileSummary, relativePath: "summaries/alpha.md", title: "Alpha.md", content: "Alpha mentions Project Atlas.", sourceHashes: [alphaHash])
        _ = try await artifacts.store(type: .fileSummary, relativePath: "summaries/beta.md", title: "Beta.md", content: "Beta mentions Project Atlas.", sourceHashes: [betaHash])

        let combined = ContentHasher.combine([alphaHash, betaHash].sorted())
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .discoverConnections, inputHash: combined, priority: 200))
        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let runner = JobRunner(
            db: db,
            scheduler: scheduler,
            artifacts: artifacts,
            provider: SlowStubProvider(),
            projectID: "p",
            rootURL: root,
            jobTimeoutSeconds: 0.05
        )

        await runner.drain(limit: 1)

        let researchArtifacts = await db.artifacts(projectID: "p", type: .researchInsight)
        let artifact = try XCTUnwrap(researchArtifacts.first)
        let body = try XCTUnwrap(artifacts.content(for: artifact))
        XCTAssertTrue(body.contains("No new suggested connections"))
        let insights = await db.researchInsights(projectID: "p")
        XCTAssertEqual(insights.first?.artifactID, artifact.id)
        let completed = await db.jobs(projectID: "p", status: .completed)
        let pending = await db.jobs(projectID: "p", status: .pending)
        let failed = await db.jobs(projectID: "p", status: .failed)
        XCTAssertEqual(completed.count, 1)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(failed.isEmpty)
    }

    func testDiscoverConnectionsCreatesVirtualResearchAndSuggestedEdges() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-research-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct A {}".write(to: root.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "struct B { let a: A }".write(to: root.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        let fileAHash = try XCTUnwrap(ContentHasher.hashFile(at: root.appendingPathComponent("A.swift")))
        let fileBHash = try XCTUnwrap(ContentHasher.hashFile(at: root.appendingPathComponent("B.swift")))
        _ = await db.upsertFile(projectID: "p", path: "A.swift", hash: fileAHash, sizeBytes: 11, language: "swift")
        _ = await db.upsertFile(projectID: "p", path: "B.swift", hash: fileBHash, sizeBytes: 22, language: "swift")
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        _ = try await artifacts.store(type: .fileSummary, relativePath: "summaries/a.md", title: "A.swift", content: "Defines A.", sourceHashes: [fileAHash])
        _ = try await artifacts.store(type: .fileSummary, relativePath: "summaries/b.md", title: "B.swift", content: "Uses A.", sourceHashes: [fileBHash])

        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let provider = StubProvider(text: """
        The user wants me to find conceptual connections between files.

        # Suggested Connections
        - `A.swift` => `B.swift`: B stores a value of A.
        """)
        let runner = JobRunner(db: db, scheduler: scheduler, artifacts: artifacts, provider: provider, projectID: "p", rootURL: root)
        let combined = ContentHasher.combine([fileAHash, fileBHash].sorted())
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .discoverConnections, inputHash: combined))
        await runner.drain(limit: 10)

        let produced = await db.artifacts(projectID: "p")
        XCTAssertTrue(produced.contains { $0.type == .researchInsight })
        let researchArtifact = try XCTUnwrap(produced.first { $0.type == .researchInsight })
        let body = try XCTUnwrap(artifacts.content(for: researchArtifact))
        XCTAssertTrue(body.hasPrefix("# Suggested Connections"))
        XCTAssertFalse(body.contains("The user wants me"))
        let insights = await db.researchInsights(projectID: "p")
        XCTAssertEqual(insights.first?.kind, .suggestedConnection)
        let edges = await db.knowledgeEdges(projectID: "p")
        let edge = try XCTUnwrap(edges.first)
        XCTAssertEqual(edge.status, .suggested)
        XCTAssertEqual(edge.origin, .llmSuggested)
    }

    // MARK: - GitInspector

    func testGitInspectorOnNonRepoIsGraceful() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-nogit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let git = GitInspector(rootURL: tmp)
        let isRepo = await git.isRepository()
        XCTAssertFalse(isRepo)
        let commits = await git.recentCommits()
        XCTAssertTrue(commits.isEmpty)
    }

    // MARK: - Expanded executors

    func testRunnerProducesAggregateArtifacts() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-agg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "import Foundation\nstruct Engine { func go() {} }".write(to: root.appendingPathComponent("Engine.swift"), atomically: true, encoding: .utf8)
        try "struct Runner { func run(e: Engine) {} }".write(to: root.appendingPathComponent("Runner.swift"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        let scanner = WorkspaceScanner(db: db, projectID: "p", rootURL: root)
        _ = await scanner.scan()

        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: root.appendingPathComponent(".cribble/cache/artifacts"))
        let provider = StubProvider(text: "# Summary\n\nA concise description of behavior.")
        let runner = JobRunner(db: db, scheduler: scheduler, artifacts: artifacts, provider: provider, projectID: "p", rootURL: root)

        // Drain the two file summaries first.
        await runner.drain(limit: 10)
        let files = await db.files(projectID: "p")
        let combined = ContentHasher.combine(files.map(\.hash).sorted())

        // Enqueue the aggregates and drain again.
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .buildDependencyDiagram, inputHash: combined, priority: 150))
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .detectArchitectureDrift, inputHash: combined, priority: 160))
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .updateProjectIndex, inputHash: combined, priority: 200))
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .buildArchitectureDiagram, inputHash: combined, priority: 210))
        await runner.drain(limit: 20)

        let produced = await db.artifacts(projectID: "p")
        let types = Set(produced.map(\.type))
        XCTAssertTrue(types.contains(.fileSummary))
        XCTAssertTrue(types.contains(.dependencyDiagram))
        XCTAssertTrue(types.contains(.driftReport))
        XCTAssertTrue(types.contains(.projectIndex))
        XCTAssertTrue(types.contains(.architectureDiagram))

        // Dependency diagram should contain a valid mermaid block.
        if let dep = produced.first(where: { $0.type == .dependencyDiagram }), let content = artifacts.content(for: dep) {
            XCTAssertTrue(content.contains("```mermaid"))
        } else {
            XCTFail("missing dependency diagram content")
        }

        // No jobs left failed.
        let failed = await db.jobs(projectID: "p", status: .failed).count
        XCTAssertEqual(failed, 0)
    }
}
