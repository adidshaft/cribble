import XCTest
@testable import Cribble

/// Canned provider so job execution is testable without a model.
private final class MockIntelligenceProvider: IntelligenceProvider {
    let displayName = "Mock"
    let response: String
    let availability: ProviderAvailability

    init(response: String, availability: ProviderAvailability = .available) {
        self.response = response
        self.availability = availability
    }

    func checkAvailability() async -> ProviderAvailability { availability }
    func generate(prompt: [EngineMessage], schema: JSONSchemaHint?, maxTokens: Int) async throws -> String { response }
    func embed(text: String) async throws -> [Float]? { nil }
}

final class IntelligenceEngineTests: XCTestCase {

    // MARK: - ContentHasher

    func testHasherIsDeterministicAndSensitive() {
        XCTAssertEqual(ContentHasher.hash("hello"), ContentHasher.hash("hello"))
        XCTAssertNotEqual(ContentHasher.hash("hello"), ContentHasher.hash("hello "))
        XCTAssertEqual(ContentHasher.hash("hello").count, 16)
    }

    func testHasherCombineIsOrderSensitive() {
        XCTAssertNotEqual(
            ContentHasher.combine(["a", "b"]),
            ContentHasher.combine(["b", "a"])
        )
    }

    // MARK: - SwiftSymbolExtractor

    func testSymbolExtractionFindsTypesFunctionsImports() {
        let source = """
        import Foundation
        import SQLite3

        public final class Engine {
            func start() {
                print("go")
            }

            class func shared() -> Engine { Engine() }
        }

        struct Config {}

        protocol Runnable {
            func run()
        }

        extension Engine {
            func stop() {}
        }
        """
        let symbols = SwiftSymbolExtractor.extract(from: source)
        let names = Set(symbols.map(\.name))

        XCTAssertTrue(names.contains("Foundation"))
        XCTAssertTrue(names.contains("Engine"))
        XCTAssertTrue(names.contains("Config"))
        XCTAssertTrue(names.contains("Runnable"))
        XCTAssertTrue(names.contains("start"))
        // `class func shared` is a function, not a type named "func".
        XCTAssertTrue(symbols.contains { $0.name == "shared" && $0.kind == .function })
        XCTAssertTrue(symbols.contains { $0.name == "Engine" && $0.kind == .type })
        XCTAssertTrue(symbols.contains { $0.name == "Engine" && $0.kind == .extensionDecl })
        XCTAssertTrue(symbols.contains { $0.name == "Runnable" && $0.kind == .protocolType })
        XCTAssertFalse(names.contains("func"))
    }

    // MARK: - IntelligenceDatabase

    func testMigrationsApplyAndAreIdempotent() async throws {
        // Opening twice against the same on-disk file must not re-run migrations.
        let path = NSTemporaryDirectory() + "cribble-intel-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try IntelligenceDatabase(path: path)
        // Second open should succeed (migrations skipped, no duplicate-table error).
        let db = try IntelligenceDatabase(path: path)
        let id = await db.upsertFile(projectID: "p", path: "a.swift", hash: "h1", sizeBytes: 10, language: "swift")
        XCTAssertGreaterThan(id, 0)
    }

    func testUpsertFileTracksHashChange() async throws {
        let db = try IntelligenceDatabase(path: ":memory:")
        let id1 = await db.upsertFile(projectID: "p", path: "a.swift", hash: "h1", sizeBytes: 10, language: "swift")
        let id2 = await db.upsertFile(projectID: "p", path: "a.swift", hash: "h2", sizeBytes: 12, language: "swift")
        XCTAssertEqual(id1, id2, "Upsert should update the same row")
        let file = await db.file(projectID: "p", path: "a.swift")
        XCTAssertEqual(file?.hash, "h2")
        let count = await db.files(projectID: "p").count
        XCTAssertEqual(count, 1)
    }

    func testEnqueueDeduplicatesByInputHash() async throws {
        let db = try IntelligenceDatabase(path: ":memory:")
        let job = IntelligenceJob(projectID: "p", type: .summarizeFile, inputHash: "h1", inputPaths: ["a.swift"])
        let first = await db.enqueueJobIfNeeded(job)
        XCTAssertTrue(first)
        // Same project/type/hash → skipped.
        let dup = IntelligenceJob(projectID: "p", type: .summarizeFile, inputHash: "h1", inputPaths: ["a.swift"])
        let second = await db.enqueueJobIfNeeded(dup)
        XCTAssertFalse(second)
        let pending = await db.pendingJobCount(projectID: "p")
        XCTAssertEqual(pending, 1)
    }

    func testDequeueRespectsTierGating() async throws {
        let db = try IntelligenceDatabase(path: ":memory:")
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .summarizeFile, inputHash: "h1", priority: 10))
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .updateProjectIndex, inputHash: "h2", priority: 5))

        // Tier 1 only → neither tier-2 nor tier-3 job is eligible.
        let none = await db.dequeueNextJob(projectID: "p", maxTier: .tier1)
        XCTAssertNil(none)

        // Tier 2 → only the summarizeFile (tier-2) job, despite lower priority on index.
        let t2 = await db.dequeueNextJob(projectID: "p", maxTier: .tier2)
        XCTAssertEqual(t2?.type, .summarizeFile)
        XCTAssertEqual(t2?.status, .running)
    }

    func testFailureRetriesThenMarksFailed() async throws {
        let db = try IntelligenceDatabase(path: ":memory:")
        let job = IntelligenceJob(projectID: "p", type: .summarizeFile, inputHash: "h1", maxAttempts: 2)
        await db.enqueueJobIfNeeded(job)

        _ = await db.dequeueNextJob(projectID: "p", maxTier: .tier2)
        await db.recordFailure(id: job.id, error: "boom")
        // attempt 1 < max 2 → back to pending.
        let pendingAfter1 = await db.jobs(projectID: "p", status: .pending).count
        XCTAssertEqual(pendingAfter1, 1)

        _ = await db.dequeueNextJob(projectID: "p", maxTier: .tier2)
        await db.recordFailure(id: job.id, error: "boom again")
        // attempt 2 == max → failed.
        let failed = await db.jobs(projectID: "p", status: .failed).count
        let pendingAfter2 = await db.jobs(projectID: "p", status: .pending).count
        XCTAssertEqual(failed, 1)
        XCTAssertEqual(pendingAfter2, 0)
    }

    func testResetRunningJobsRequeues() async throws {
        let db = try IntelligenceDatabase(path: ":memory:")
        let job = IntelligenceJob(projectID: "p", type: .summarizeFile, inputHash: "h1")
        await db.enqueueJobIfNeeded(job)
        _ = await db.dequeueNextJob(projectID: "p", maxTier: .tier2)
        let running = await db.jobs(projectID: "p", status: .running).count
        XCTAssertEqual(running, 1)
        await db.resetRunningJobs()
        let pending = await db.jobs(projectID: "p", status: .pending).count
        XCTAssertEqual(pending, 1)
    }

    func testArtifactStaleOnSourceHashChange() async throws {
        let db = try IntelligenceDatabase(path: ":memory:")
        let artifact = IntelligenceArtifact(
            id: "art1", projectID: "p", type: .fileSummary,
            relativePath: "summaries/h1.md", title: "a.swift",
            contentHash: "c1", sourceHashes: ["h1"], isPublished: false
        )
        await db.insertArtifact(artifact)
        let stale0 = await db.staleArtifactCount(projectID: "p")
        XCTAssertEqual(stale0, 0)
        await db.markArtifactsStale(projectID: "p", containingSourceHash: "h1")
        let stale1 = await db.staleArtifactCount(projectID: "p")
        XCTAssertEqual(stale1, 1)
        // Re-insert clears stale; an unrelated hash should not flip it.
        await db.insertArtifact(artifact)
        await db.markArtifactsStale(projectID: "p", containingSourceHash: "other")
        let stale2 = await db.staleArtifactCount(projectID: "p")
        XCTAssertEqual(stale2, 0)
    }

    func testProvenanceRoundTrips() async throws {
        let db = try IntelligenceDatabase(path: ":memory:")
        // A real file row must exist: the FK on artifact_provenance.file_id is
        // enforced (PRAGMA foreign_keys=ON), so a dangling id would be rejected.
        let fileID = await db.upsertFile(projectID: "p", path: "a.swift", hash: "h1", sizeBytes: 10, language: "swift")
        await db.insertArtifact(IntelligenceArtifact(
            id: "art1", projectID: "p", type: .fileSummary,
            relativePath: "summaries/h1.md", title: nil,
            contentHash: "c1", sourceHashes: ["h1"], isPublished: false
        ))
        await db.insertProvenance(ArtifactProvenance(
            artifactID: "art1", claimAnchor: "summary",
            fileID: fileID, startLine: 1, endLine: 40, symbolID: nil, confidence: 0.9
        ))
        let rows = await db.provenance(artifactID: "art1")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.startLine, 1)
        XCTAssertEqual(rows.first?.endLine, 40)
        XCTAssertEqual(rows.first?.confidence, 0.9)
    }

    // MARK: - BackgroundScheduler policy

    func testSchedulerPolicy() {
        func make(idle: TimeInterval, thermal: ProcessInfo.ThermalState, battery: Bool, active: Bool) -> BackgroundScheduler.Conditions {
            .init(userIdleSeconds: idle, thermalState: thermal, isOnBattery: battery, appIsActive: active, appIsForeground: active)
        }
        let threshold: TimeInterval = 60

        // Thermal pressure halts everything.
        XCTAssertEqual(BackgroundScheduler.policy(for: make(idle: 999, thermal: .serious, battery: false, active: false), idleThreshold: threshold), .none)
        // On battery → tier 1 only.
        XCTAssertEqual(BackgroundScheduler.policy(for: make(idle: 999, thermal: .nominal, battery: true, active: false), idleThreshold: threshold), .tier1)
        // Plugged + idle → tier 3.
        XCTAssertEqual(BackgroundScheduler.policy(for: make(idle: 120, thermal: .nominal, battery: false, active: false), idleThreshold: threshold), .tier3)
        // Plugged + active, not idle → tier 2.
        XCTAssertEqual(BackgroundScheduler.policy(for: make(idle: 5, thermal: .nominal, battery: false, active: true), idleThreshold: threshold), .tier2)
    }

    // MARK: - WorkspaceScanner

    func testScannerDetectsAddChangeRemove() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let swiftFile = root.appendingPathComponent("Engine.swift")
        let noteFile = root.appendingPathComponent("Notes.md")
        try "struct Engine { func go() {} }".write(to: swiftFile, atomically: true, encoding: .utf8)
        try "# Notes".write(to: noteFile, atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        let scanner = WorkspaceScanner(db: db, projectID: "p", rootURL: root)

        let first = await scanner.scan()
        XCTAssertEqual(first.added, 2)
        XCTAssertEqual(first.changed, 0)
        XCTAssertEqual(first.jobsEnqueued, 2)
        // Swift symbols parsed deterministically (no model).
        let fileID = await db.file(projectID: "p", path: "Engine.swift")?.id
        XCTAssertNotNil(fileID)
        let symbolCount = await db.symbolCount(fileID: fileID!)
        XCTAssertGreaterThan(symbolCount, 0)

        // No-op rescan.
        let second = await scanner.scan()
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.changed, 0)

        // Change one file.
        try "struct Engine { func go() {} func stop() {} }".write(to: swiftFile, atomically: true, encoding: .utf8)
        let third = await scanner.scan()
        XCTAssertEqual(third.changed, 1)

        // Remove one file.
        try FileManager.default.removeItem(at: noteFile)
        let fourth = await scanner.scan()
        XCTAssertEqual(fourth.removed, 1)
        let remaining = await db.files(projectID: "p").count
        XCTAssertEqual(remaining, 1)
    }

    func testScannerMultiRootUsesAbsolutePaths() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-multi-\(UUID().uuidString)")
        let rootA = base.appendingPathComponent("A"); let rootB = base.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try "# A".write(to: rootA.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "# B".write(to: rootB.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        let result = await WorkspaceScanner(db: db, projectID: "all", roots: [rootA, rootB]).scan()
        XCTAssertEqual(result.added, 2)
        let paths = Set(await db.files(projectID: "all").map(\.path))
        // Multi-root → absolute paths so they stay unique and resolvable.
        XCTAssertTrue(paths.allSatisfy { $0.hasPrefix("/") })
        XCTAssertTrue(paths.contains(rootA.appendingPathComponent("a.md").standardizedFileURL.path))
    }

    // MARK: - JobRunner end to end

    func testRunnerSummarizesFileAndAnchorsProvenance() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cribble-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let swiftFile = root.appendingPathComponent("Engine.swift")
        try "struct Engine { func go() {} }".write(to: swiftFile, atomically: true, encoding: .utf8)

        let db = try IntelligenceDatabase(path: ":memory:")
        let scanner = WorkspaceScanner(db: db, projectID: "p", rootURL: root)
        _ = await scanner.scan()

        // Force tier-3 so any job is eligible regardless of host machine state.
        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let cache = root.appendingPathComponent(".cribble/cache/artifacts")
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: cache)
        let provider = MockIntelligenceProvider(response: "# Engine\nDefines the Engine type with one method.")
        let runner = JobRunner(db: db, scheduler: scheduler, artifacts: artifacts, provider: provider, projectID: "p", rootURL: root)

        let ran = await runner.runNext()
        XCTAssertTrue(ran)

        let produced = await db.artifacts(projectID: "p")
        XCTAssertEqual(produced.count, 1)
        XCTAssertEqual(produced.first?.type, .fileSummary)
        XCTAssertEqual(produced.first?.title, "Engine.swift")
        // Content persisted to cache and readable back.
        let content = artifacts.content(for: produced.first!)
        XCTAssertEqual(content, "# Engine\nDefines the Engine type with one method.")
        // Provenance anchors the summary to the source file.
        let prov = await db.provenance(artifactID: produced.first!.id)
        XCTAssertEqual(prov.first?.claimAnchor, "summary")
        XCTAssertNotNil(prov.first?.fileID)
        // Job marked completed.
        let completed = await db.jobs(projectID: "p", status: .completed).count
        XCTAssertEqual(completed, 1)
    }

    func testRunnerRequeuesWhenProviderUnavailable() async throws {
        let db = try IntelligenceDatabase(path: ":memory:")
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: "p", type: .summarizeFile, inputHash: "h1", inputPaths: ["a.swift"]))
        let scheduler = BackgroundScheduler(conditionsProvider: {
            .init(userIdleSeconds: 9999, thermalState: .nominal, isOnBattery: false, appIsActive: false, appIsForeground: false)
        })
        let artifacts = ArtifactStore(db: db, projectID: "p", cacheDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
        let provider = MockIntelligenceProvider(response: "x", availability: .unavailable(reason: "Model not downloaded"))
        let runner = JobRunner(db: db, scheduler: scheduler, artifacts: artifacts, provider: provider, projectID: "p", rootURL: URL(fileURLWithPath: "/tmp"))

        let ran = await runner.runNext()
        XCTAssertFalse(ran, "Should not run a model job without a usable provider")
        // Returned to pending without burning an attempt.
        let pending = await db.jobs(projectID: "p", status: .pending)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.attemptCount, 0)
    }
}
