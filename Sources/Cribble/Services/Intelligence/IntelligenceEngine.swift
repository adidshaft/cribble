import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Top-level coordinator for the intelligence layer and the object the UI binds
/// to. Owns the per-project database, scheduler, job runner, artifact store, and
/// provider; drives the idle scan→enqueue→drain loop; and publishes glanceable
/// state for the sidebar indicator and HUD.
///
/// `@MainActor ObservableObject`: every method runs on the main actor (so
/// `@Published` mutations are safe) and simply `await`s the underlying actors
/// (`IntelligenceDatabase`, `JobRunner`, `BackgroundScheduler`) for the heavy
/// work, which keeps that work off the main thread.
@MainActor
final class IntelligenceEngine: ObservableObject {

    enum Status: Equatable {
        case off
        case ready
        case scanning(done: Int, total: Int)
        case working(String)
        case idle
        case driftDetected(Int)
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var artifacts: [IntelligenceArtifact] = []
    @Published private(set) var pendingJobs = 0
    @Published private(set) var filesIndexed = 0
    @Published private(set) var staleCount = 0
    @Published private(set) var lastActivity: String?
    @Published private(set) var isEnabled = false

    let settings: IntelligenceSettings

    private var projectID: String?
    private var rootURL: URL?
    private var db: IntelligenceDatabase?
    private var scheduler: BackgroundScheduler?
    private var runner: JobRunner?
    private var artifactStore: ArtifactStore?
    private var provider: IntelligenceProvider?
    private let embeddingEngine = EmbeddingEngine()
    private var tickTask: Task<Void, Never>?

    /// How often the idle loop wakes to scan + drain.
    private let tickInterval: Duration = .seconds(20)

    init(settings: IntelligenceSettings) {
        self.settings = settings
    }

    // MARK: - Lifecycle

    /// Enables intelligence for `rootURL`: opens the per-project DB, builds the
    /// provider, performs an initial scan, and starts the idle loop.
    func enable(rootURL: URL) async {
        await teardown()
        let projectID = rootURL.path
        self.projectID = projectID
        self.rootURL = rootURL
        settings.setEnabled(true, projectID: projectID)

        let cacheDir = rootURL.appendingPathComponent(".cribble/cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // Self-contained ignore (design plan §4.1): keep the regenerable cache out
        // of git while leaving published `intelligence/` artifacts trackable —
        // without silently editing the user's root .gitignore.
        let dotIgnore = rootURL.appendingPathComponent(".cribble/.gitignore")
        if !FileManager.default.fileExists(atPath: dotIgnore.path) {
            try? "cache/\n".write(to: dotIgnore, atomically: true, encoding: .utf8)
        }
        guard let database = try? IntelligenceDatabase(path: cacheDir.appendingPathComponent("intelligence.db").path) else {
            status = .off
            return
        }
        await database.resetRunningJobs()

        let scheduler = BackgroundScheduler(conditionsProvider: { [pauseOnBattery = settings.pauseOnBattery] in
            BackgroundScheduler.Conditions(
                userIdleSeconds: Self.systemIdleSeconds(),
                thermalState: ProcessInfo.processInfo.thermalState,
                isOnBattery: pauseOnBattery && ProcessInfo.processInfo.isLowPowerModeEnabled,
                appIsActive: true,
                appIsForeground: true
            )
        })
        let artifactStore = ArtifactStore(db: database, projectID: projectID, cacheDirectory: cacheDir.appendingPathComponent("artifacts"))
        let provider = makeProvider()
        let runner = JobRunner(
            db: database, scheduler: scheduler, artifacts: artifactStore,
            provider: provider, projectID: projectID, rootURL: rootURL
        )

        self.db = database
        self.scheduler = scheduler
        self.artifactStore = artifactStore
        self.provider = provider
        self.runner = runner
        self.isEnabled = true
        self.status = .ready

        await tick(initialScan: true)
        startLoop()
    }

    /// Disables intelligence for the current project and stops all work.
    func disable() async {
        if let projectID { settings.setEnabled(false, projectID: projectID) }
        await teardown()
        isEnabled = false
        status = .off
        artifacts = []
        pendingJobs = 0
        filesIndexed = 0
        staleCount = 0
    }

    /// Re-enables intelligence for a project on app launch if the user had it on.
    func restoreIfEnabled(rootURL: URL) async {
        if settings.isEnabled(projectID: rootURL.path) {
            await enable(rootURL: rootURL)
        }
    }

    private func teardown() async {
        tickTask?.cancel()
        tickTask = nil
        db = nil; scheduler = nil; runner = nil; artifactStore = nil; provider = nil
        projectID = nil; rootURL = nil
    }

    // MARK: - Idle loop

    private func startLoop() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.tickInterval)
                if Task.isCancelled { break }
                await self.tick(initialScan: false)
            }
        }
    }

    /// One iteration: scan for changes, enqueue follow-up + aggregate jobs, drain
    /// the queue within the allowed tier, enforce the disk budget, refresh state.
    func tick(initialScan: Bool) async {
        guard let db, let rootURL, let projectID, let runner else { return }

        if initialScan { status = .scanning(done: 0, total: 0) }
        let scanner = WorkspaceScanner(db: db, projectID: projectID, rootURL: rootURL)
        let result = await scanner.scan()
        if result.changed > 0 || result.added > 0 {
            lastActivity = "Indexed \(result.added + result.changed) file(s)"
        }

        await enqueueAggregateJobs()
        status = .working("Processing")
        await runner.drain(limit: 6)   // bounded per tick so the loop stays responsive
        await enforceDiskBudget()
        await refreshState()
    }

    func runNow() async {
        await tick(initialScan: false)
    }

    // MARK: - Aggregate scheduling

    private func enqueueAggregateJobs() async {
        guard let db, let projectID, let rootURL else { return }
        let files = await db.files(projectID: projectID)
        guard !files.isEmpty else { return }
        let combined = ContentHasher.combine(files.map(\.hash).sorted())

        // Deterministic, model-free jobs run first; model aggregations get a
        // higher priority number so file summaries (priority 100) drain first.
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: projectID, type: .buildDependencyDiagram, inputHash: combined, priority: 150))
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: projectID, type: .detectArchitectureDrift, inputHash: combined, priority: 160))
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: projectID, type: .updateProjectIndex, inputHash: combined, priority: 200))
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: projectID, type: .buildArchitectureDiagram, inputHash: combined, priority: 210))

        // Git intelligence (graceful no-op if not a repo / git unavailable).
        let git = GitInspector(rootURL: rootURL)
        if await git.isRepository() {
            if let diff = await git.workingTreeDiff(), !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await db.enqueueJobIfNeeded(IntelligenceJob(projectID: projectID, type: .summarizeDiff, inputHash: ContentHasher.hash(diff), priority: 120))
            }
            for commit in await git.recentCommits(limit: 10) {
                let isNew = await db.recordCommitIfNeeded(projectID: projectID, sha: commit.sha, message: commit.subject, author: commit.author, timestamp: commit.date)
                if isNew {
                    await db.enqueueJobIfNeeded(IntelligenceJob(projectID: projectID, type: .summarizeCommit, inputHash: commit.sha, inputPaths: [commit.sha], priority: 130))
                }
            }
        }
    }

    // MARK: - State

    private func refreshState() async {
        guard let db, let projectID else { return }
        artifacts = await db.artifacts(projectID: projectID)
        pendingJobs = await db.pendingJobCount(projectID: projectID)
        filesIndexed = await db.files(projectID: projectID).count
        staleCount = await db.staleArtifactCount(projectID: projectID)

        let driftReports = artifacts.filter { $0.type == .driftReport }
        if let drift = driftReports.first, let content = artifactStore?.content(for: drift),
           content.range(of: "No drift detected") == nil {
            // Count drift bullet lines as a rough signal.
            let count = content.split(separator: "\n").filter { $0.hasPrefix("- ") }.count
            status = count > 0 ? .driftDetected(count) : (pendingJobs > 0 ? .working("Processing") : .idle)
        } else {
            status = pendingJobs > 0 ? .working("\(pendingJobs) queued") : .idle
        }
    }

    func content(for artifact: IntelligenceArtifact) -> String? {
        artifactStore?.content(for: artifact)
    }

    func provenance(for artifact: IntelligenceArtifact) async -> [ArtifactProvenance] {
        await db?.provenance(artifactID: artifact.id) ?? []
    }

    // MARK: - Publishing (virtual → .cribble/intelligence/)

    /// Builds an addition-only `UnifiedDiff` that writes the artifact's content
    /// into `.cribble/intelligence/<relativePath>`, for the existing diff-preview
    /// → apply flow (design plan §4.3). Returns nil if the content is missing.
    func publishDiff(for artifact: IntelligenceArtifact) -> UnifiedDiff? {
        guard let content = artifactStore?.content(for: artifact) else { return nil }
        let target = ".cribble/intelligence/\(artifact.relativePath)"
        let additions = content.components(separatedBy: "\n").map { DiffLine(kind: .addition, text: $0) }
        let hunk = DiffHunk(header: "@@ -0,0 +1,\(additions.count) @@", lines: additions)
        let file = DiffFile(oldPath: "/dev/null", newPath: target, hunks: [hunk])
        return UnifiedDiff(files: [file])
    }

    /// Applies an artifact to the project folder and marks it published.
    func publish(_ artifact: IntelligenceArtifact) async {
        guard let rootURL, let diff = publishDiff(for: artifact) else { return }
        do {
            try DiffApplier().apply(diff, rootURL: rootURL)
            await db?.markArtifactPublished(id: artifact.id)
            await refreshState()
        } catch {
            lastActivity = "Publish failed: \(error.localizedDescription)"
        }
    }

    func publishAll() async {
        for artifact in artifacts where !artifact.isPublished {
            await publish(artifact)
        }
    }

    // MARK: - Disk budget (LRU eviction)

    private func enforceDiskBudget() async {
        guard let artifactStore, let db, let projectID else { return }
        let budgetBytes = settings.diskBudgetMB * 1024 * 1024
        var used = directorySize(artifactStore.cacheDirectory)
        guard used > budgetBytes else { return }
        for id in await db.artifactIDsOldestFirst(projectID: projectID) {
            let fileURL = artifactStore.cacheDirectory.appendingPathComponent("\(id).md")
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at: fileURL)
            await db.deleteArtifact(id: id)
            used -= size
            if used <= budgetBytes { break }
        }
    }

    private func directorySize(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    // MARK: - Ask about this project

    /// Answers a scoped question using retrieved artifact context. Ranks
    /// artifacts by simple keyword overlap (Phase 1), assembles a bounded prompt,
    /// and generates with the configured provider. Returns nil if no provider.
    func ask(_ question: String) async -> String? {
        guard let provider else { return nil }
        let ranked = rankArtifacts(for: question)
        var context: [String] = []
        var budget = 8_000
        for artifact in ranked {
            guard let content = artifactStore?.content(for: artifact) else { continue }
            let snippet = String(content.prefix(min(budget, 2_000)))
            context.append("## \(artifact.title ?? artifact.relativePath)\n\(snippet)")
            budget -= snippet.count
            if budget <= 0 { break }
        }
        let messages = [
            EngineMessage(role: .system, content: """
            You answer questions about a software project using ONLY the generated intelligence \
            below. Never invent files or symbols. Cite the artifact titles you used. If the answer \
            isn't in the context, say so.

            \(context.joined(separator: "\n\n"))
            """),
            EngineMessage(role: .user, content: question)
        ]
        return try? await provider.generate(prompt: messages, maxTokens: 700)
    }

    private func rankArtifacts(for question: String) -> [IntelligenceArtifact] {
        let terms = Set(question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return artifacts
            .map { artifact -> (IntelligenceArtifact, Int) in
                let hay = ((artifact.title ?? "") + " " + (artifactStore?.content(for: artifact) ?? "")).lowercased()
                let score = terms.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
                return (artifact, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map(\.0)
    }

    // MARK: - Chat HUD context injection

    /// Project-intelligence context to fold into the Chat HUD prompt as "related"
    /// files (design plan Phase 1). Returns the project index plus a few summaries.
    func chatContext() -> [ResolvedFile] {
        var files: [ResolvedFile] = []
        if let index = artifacts.first(where: { $0.type == .projectIndex }), let content = artifactStore?.content(for: index) {
            files.append(ResolvedFile(filename: "Project Index", content: content))
        }
        return files
    }

    // MARK: - Provider construction

    private func makeProvider() -> IntelligenceProvider? {
        if let urlString = settings.localRunnerBaseURL, let url = URL(string: urlString) {
            return OpenAICompatibleProvider(baseURL: url, model: settings.modelID, embedModel: nil)
        }
        guard let model = ModelCatalog.model(withID: settings.modelID) else { return nil }
        let engine = LocalLLM.shared.engine(for: model)
        return LocalEngineIntelligenceProvider(engine: engine, model: model, embeddingEngine: embeddingEngine)
    }

    // MARK: - Idle probe

    nonisolated private static func systemIdleSeconds() -> TimeInterval {
        #if canImport(CoreGraphics)
        let interval = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .init(rawValue: ~0)!)
        return interval.isFinite ? interval : 0
        #else
        return 0
        #endif
    }
}
