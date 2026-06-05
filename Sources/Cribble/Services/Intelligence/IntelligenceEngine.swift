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
    /// Download progress (0...1) while fetching the on-device model, else nil.
    @Published private(set) var modelDownloadFraction: Double?

    let settings: IntelligenceSettings

    private var projectID: String?
    private var rootURL: URL?
    /// Folders the current scope scans (one for folder scope, several for all).
    private var scanRoots: [URL] = []
    /// True when the active scope spans all opened folders.
    @Published private(set) var isAllFolders = false
    private var db: IntelligenceDatabase?
    private var scheduler: BackgroundScheduler?
    private var runner: JobRunner?
    private var artifactStore: ArtifactStore?
    private var provider: IntelligenceProvider?
    private let embeddingEngine = EmbeddingEngine()
    private var tickTask: Task<Void, Never>?
    private let fileMonitor = FileChangeMonitor()

    /// Set by FSEvents when the project changes; the loop only re-scans (and
    /// re-hashes files) when this is true, instead of re-hashing the whole tree
    /// every tick. Big I/O saving on large projects.
    private var needsScan = false
    /// Reentrancy guard so a manual `runNow()` can't overlap a loop tick.
    private var isTicking = false
    /// OS memory-pressure monitor. Owns its own DispatchSource in a NON-isolated
    /// type so its event handler can't be inferred `@MainActor` — that inference
    /// made libdispatch trip a Swift executor-isolation assertion and crash the
    /// app whenever memory pressure changed.
    private let memoryMonitor = MemoryPressureMonitor()

    /// How often the idle loop wakes to drain the queue. Scanning happens only on
    /// change (FSEvents), not on every tick.
    private let tickInterval: Duration = .seconds(30)
    /// Upper bound on files Intelligence will manage for one project, so a giant
    /// repo can't enqueue an unbounded amount of work or balloon memory.
    private let maxFilesManaged = 8_000

    init(settings: IntelligenceSettings) {
        self.settings = settings
    }

    // MARK: - Lifecycle

    /// Enables intelligence for `rootURL`: opens the per-project DB, builds the
    /// provider, performs an initial scan, and starts the idle loop.
    func enable(rootURL rawRootURL: URL) async {
        let rootURL = rawRootURL.standardizedFileURL
        let cacheDir = rootURL.appendingPathComponent(".cribble/cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // Self-contained ignore (design plan §4.1): keep the regenerable cache out
        // of git while leaving published `intelligence/` artifacts trackable —
        // without silently editing the user's root .gitignore.
        let dotIgnore = rootURL.appendingPathComponent(".cribble/.gitignore")
        if !FileManager.default.fileExists(atPath: dotIgnore.path) {
            try? "cache/\n".write(to: dotIgnore, atomically: true, encoding: .utf8)
        }
        await start(projectID: rootURL.path, cacheDir: cacheDir, nominalRoot: rootURL,
                    scanRoots: [rootURL], allFolders: false)
    }

    /// Enables a unified intelligence scope across every opened folder (#1).
    func enableAllFolders(roots rawRoots: [URL]) async {
        let roots = rawRoots.map(\.standardizedFileURL)
        guard !roots.isEmpty else { return }
        let base = Self.allFoldersBase()
        let cacheDir = base.appendingPathComponent("cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        await start(projectID: "all-folders", cacheDir: cacheDir, nominalRoot: base,
                    scanRoots: roots, allFolders: true)
    }

    private static func allFoldersBase() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Cribble/IntelligenceAllFolders")
    }

    private func start(projectID: String, cacheDir: URL, nominalRoot: URL, scanRoots: [URL], allFolders: Bool) async {
        await teardown()
        self.projectID = projectID
        self.rootURL = nominalRoot
        self.scanRoots = scanRoots
        self.isAllFolders = allFolders
        settings.setEnabled(true, projectID: projectID)

        guard let database = try? IntelligenceDatabase(path: cacheDir.appendingPathComponent("intelligence.db").path) else {
            status = .off
            return
        }
        await database.resetRunningJobs()

        let scheduler = BackgroundScheduler(conditionsProvider: { [pauseOnBattery = settings.pauseOnBattery, memoryFlag = memoryMonitor.flag] in
            BackgroundScheduler.Conditions(
                userIdleSeconds: Self.systemIdleSeconds(),
                thermalState: ProcessInfo.processInfo.thermalState,
                isOnBattery: pauseOnBattery && ProcessInfo.processInfo.isLowPowerModeEnabled,
                appIsActive: true,
                appIsForeground: true,
                memoryPressured: memoryFlag.value
            )
        })
        let artifactStore = ArtifactStore(db: database, projectID: projectID, cacheDirectory: cacheDir.appendingPathComponent("artifacts"))
        let provider = makeProvider()
        let runner = JobRunner(
            db: database, scheduler: scheduler, artifacts: artifactStore,
            provider: provider, projectID: projectID, rootURL: nominalRoot,
            mermaidValidator: { source in await MermaidRenderValidator.shared.validate(source) }
        )

        self.db = database
        self.scheduler = scheduler
        self.artifactStore = artifactStore
        self.provider = provider
        self.runner = runner
        self.isEnabled = true
        self.status = .ready

        await recoverIfPoisoned(database: database, store: artifactStore, projectID: projectID)
        if !allFolders {
            await DemoSeeder.seedIfDemoNotes(rootURL: nominalRoot, store: artifactStore, db: database, projectID: projectID)
        }
        fileMonitor.start(rootURLs: scanRoots) { [weak self] in
            self?.needsScan = true
        }
        needsScan = true
        await tick(initialScan: true)
        startLoop()
    }

    /// Detects a poisoned cache — artifacts whose stored content is actually a
    /// provider error — and wipes the project's artifacts/jobs so they regenerate
    /// cleanly. Samples up to 60 artifacts to stay cheap.
    private func recoverIfPoisoned(database: IntelligenceDatabase, store: ArtifactStore, projectID: String) async {
        let sample = await database.artifacts(projectID: projectID).prefix(60)
        guard !sample.isEmpty else { return }
        var bad = 0
        for artifact in sample {
            if let content = store.content(for: artifact), OutputValidator.looksLikeError(content) != nil { bad += 1 }
        }
        // If a meaningful fraction look like errors, the whole batch is suspect.
        if Double(bad) / Double(sample.count) >= 0.3 {
            await database.reset(projectID: projectID)
            try? FileManager.default.removeItem(at: store.cacheDirectory)
            lastActivity = "Cleared a misconfigured cache; rebuilding"
        }
    }

    /// Disables intelligence for the current project and stops all work.
    func disable() async {
        if let projectID { settings.setEnabled(false, projectID: projectID) }
        await teardown()
        isEnabled = false
        isAllFolders = false
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
        fileMonitor.stop()
        needsScan = false
        isTicking = false
        db = nil; scheduler = nil; runner = nil; artifactStore = nil; provider = nil
        projectID = nil; rootURL = nil; scanRoots = []
    }

    /// Wipes this project's artifacts, jobs, and cached content, then rebuilds.
    func clearCache() async {
        guard let db, let projectID, let artifactStore else { return }
        await db.reset(projectID: projectID)
        try? FileManager.default.removeItem(at: artifactStore.cacheDirectory)
        try? FileManager.default.removeItem(at: artifactStore.cacheDirectory.deletingLastPathComponent().appendingPathComponent("graph"))
        artifacts = []
        needsScan = true
        await tick(initialScan: true)
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
        guard !isTicking else { return }   // no overlapping ticks
        isTicking = true
        defer { isTicking = false }

        // Honor memory pressure immediately — don't even scan under pressure.
        if memoryMonitor.flag.value {
            status = .working("Paused (low memory)")
            return
        }

        // Re-scan (and re-hash files) only when something actually changed.
        if initialScan || needsScan {
            needsScan = false
            if initialScan { status = .scanning(done: 0, total: 0) }
            let scanner = WorkspaceScanner(db: db, projectID: projectID, roots: scanRoots.isEmpty ? [rootURL] : scanRoots)
            let result = await scanner.scan()
            if result.changed > 0 || result.added > 0 {
                lastActivity = "Indexed \(result.added + result.changed) file(s)"
            }
            if await db.files(projectID: projectID).count > maxFilesManaged {
                lastActivity = "Large project — summarizing within limits"
            }
            await enqueueAggregateJobs()
        }

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
        await db.enqueueJobIfNeeded(IntelligenceJob(projectID: projectID, type: .buildConnectionsGraph, inputHash: combined, priority: 145))
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
        let ranked = await retrieve(for: question)
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
        do {
            let answer = try await provider.generate(prompt: messages, maxTokens: 700)
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "The configured model returned an empty answer. Try a different local model or ask again after the current intelligence queue finishes."
            }
            return answer
        } catch {
            return "Couldn't generate an answer with the configured model: \(error.localizedDescription)"
        }
    }

    /// Retrieves the most relevant artifacts for a question — semantic vector
    /// search when embeddings + an embedding-capable provider are available,
    /// falling back to keyword ranking otherwise.
    private func retrieve(for question: String) async -> [IntelligenceArtifact] {
        guard let db, let projectID, let provider else { return rankArtifacts(for: question) }
        let index = SQLiteVectorIndex(db: db, projectID: projectID)
        if await index.count() > 0,
           let qvec = try? await provider.embed(text: question), !qvec.isEmpty {
            let hits = await index.search(qvec, limit: 6)
            let byID = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.id, $0) })
            let matched = hits.compactMap { byID[$0.id] }
            if !matched.isEmpty { return matched }
        }
        return rankArtifacts(for: question)
    }

    private func rankArtifacts(for question: String) -> [IntelligenceArtifact] {
        // Rank on metadata only (title + path) — never read every artifact's
        // content into memory, which on a large project means thousands of file
        // reads per question. `ask` reads content for just the top handful.
        let terms = Set(question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return artifacts
            .map { artifact -> (IntelligenceArtifact, Int) in
                let hay = ((artifact.title ?? "") + " " + artifact.relativePath + " " + artifact.type.rawValue).lowercased()
                let score = terms.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
                // Always give the project index a small baseline so broad questions
                // still get top-level context.
                return (artifact, score + (artifact.type == .projectIndex ? 1 : 0))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map(\.0)
    }

    // MARK: - Chat HUD context injection

    /// Project-intelligence context to fold into the Chat HUD prompt as "related"
    /// files (design plan Phase 1). Returns the project index plus a few summaries.
    func chatContext() -> [ResolvedFile] {
        // Off unless the user explicitly turned it on in the Chat HUD — otherwise
        // chat answers get polluted by project context the user didn't ask for.
        guard settings.useInChat, isEnabled else { return [] }
        var files: [ResolvedFile] = []
        if let index = artifacts.first(where: { $0.type == .projectIndex }), let content = artifactStore?.content(for: index) {
            files.append(ResolvedFile(filename: "\(enabledProjectName ?? "Project") — Intelligence Index", content: content))
        }
        return files
    }

    // MARK: - Model selection

    /// Switches the on-device model intelligence uses and rebuilds the pipeline.
    func setModel(_ model: LocalModel) async {
        settings.localRunnerBaseURL = nil
        settings.modelID = model.id
        await rebuildRunner()
        await runNow()
    }

    /// Points intelligence at an OpenAI-compatible local runner (Ollama, llama.cpp…).
    func setLocalRunner(baseURL: String, model: String) async {
        settings.localRunnerBaseURL = baseURL
        settings.modelID = model
        await rebuildRunner()
        await runNow()
    }

    private func rebuildRunner() async {
        guard let db, let scheduler, let artifactStore, let rootURL, let projectID else { return }
        let provider = makeProvider()
        self.provider = provider
        self.runner = JobRunner(
            db: db, scheduler: scheduler, artifacts: artifactStore,
            provider: provider, projectID: projectID, rootURL: rootURL,
            mermaidValidator: { source in await MermaidRenderValidator.shared.validate(source) }
        )
    }

    // MARK: - On-device model

    /// Path of the project intelligence is currently enabled for, if any. Lets the
    /// sidebar decide whether opening a folder should switch the active project.
    var enabledRootPath: String? { rootURL?.path }
    /// Display name of the project intelligence is enabled for.
    var enabledProjectName: String? { isAllFolders ? "All folders" : rootURL?.lastPathComponent }

    /// Resolves a stored artifact/source path to a file URL — absolute paths
    /// (all-folders scope) pass through; relative paths join the project root.
    func resolveProjectFile(_ path: String) -> URL? {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return rootURL?.appendingPathComponent(path)
    }

    /// The model intelligence is configured to use, if it's an on-device one.
    var activeModel: LocalModel? { ModelCatalog.model(withID: settings.modelID) }

    /// True when the configured on-device model still needs downloading — so the
    /// HUD can offer a "Download" affordance instead of silently waiting.
    var needsModelDownload: Bool {
        guard settings.localRunnerBaseURL == nil else { return false }
        guard let model = activeModel, model.kind == .localMLX else { return false }
        return !ModelInventory.isDownloaded(model)
    }

    /// Downloads (and warms) the configured on-device model, reporting progress,
    /// then kicks a run so summaries start. No-op for cloud/runner providers or an
    /// already-downloaded model.
    func downloadModelIfNeeded() async {
        guard settings.localRunnerBaseURL == nil else { return }
        guard let model = activeModel, model.kind == .localMLX, !ModelInventory.isDownloaded(model) else { return }
        guard modelDownloadFraction == nil else { return }
        modelDownloadFraction = 0
        let engine = LocalLLM.shared.engine(for: model)
        do {
            try await engine.prepare(model: model) { [weak self] progress in
                Task { @MainActor in self?.modelDownloadFraction = min(progress.fraction, 1) }
            }
            lastActivity = "Model ready"
        } catch {
            lastActivity = "Model download failed: \(error.localizedDescription)"
        }
        modelDownloadFraction = nil
        await runNow()
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

/// A tiny lock-guarded boolean, safe to write from a dispatch queue and read from
/// the scheduler's nonisolated condition probe.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

/// Owns a memory-pressure `DispatchSource` in a NON-`@MainActor` type, so its
/// event handler is plain `@Sendable` and runs on the background queue without
/// tripping a Swift executor-isolation assertion (which previously crashed the
/// app with SIGTRAP whenever memory pressure changed). Exposes the current
/// pressure state via a thread-safe `flag`.
final class MemoryPressureMonitor: @unchecked Sendable {
    let flag = AtomicFlag()
    private let source: DispatchSourceMemoryPressure

    init() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal], queue: .global(qos: .utility)
        )
        let flag = self.flag
        source.setEventHandler { [weak source] in
            guard let data = source?.data else { return }
            flag.value = data.contains(.warning) || data.contains(.critical)
        }
        source.resume()
    }

    deinit { source.cancel() }
}
