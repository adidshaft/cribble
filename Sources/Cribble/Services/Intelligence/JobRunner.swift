import Foundation

enum JobRunnerError: LocalizedError {
    case providerUnavailable(String)
    case missingInput
    case emptyOutput
    case unsupportedJobType(IntelligenceJobType)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let r): "Intelligence provider unavailable: \(r)"
        case .missingInput: "Job had no usable input file."
        case .emptyOutput: "Model returned empty output."
        case .unsupportedJobType(let t): "No executor for job type \(t.rawValue)."
        }
    }
}

/// Drains the job queue one job at a time, respecting the scheduler's allowed
/// tier and the single-concurrent-SLM-job cap from the design plan (§8.3). The
/// runner is the bridge between deterministic queue state and the (serialized)
/// `IntelligenceProvider`.
///
/// Phase 1 implements the `summarizeFile` executor; other Tier-2/3 executors slot
/// into `execute(_:)` as they land. Tier-1 work (scanning, symbol parsing) is
/// driven directly by `WorkspaceScanner`, not through the queue.
actor JobRunner {
    private let db: IntelligenceDatabase
    private let scheduler: BackgroundScheduler
    private let artifacts: ArtifactStore
    private let provider: IntelligenceProvider?
    private let projectID: String
    private let rootURL: URL
    private let maxInputChars: Int

    init(
        db: IntelligenceDatabase,
        scheduler: BackgroundScheduler,
        artifacts: ArtifactStore,
        provider: IntelligenceProvider?,
        projectID: String,
        rootURL: URL,
        maxInputChars: Int = 12_000
    ) {
        self.db = db
        self.scheduler = scheduler
        self.artifacts = artifacts
        self.provider = provider
        self.projectID = projectID
        self.rootURL = rootURL
        self.maxInputChars = maxInputChars
    }

    /// Runs at most one eligible job. Returns true if a job was executed (whether
    /// it succeeded or failed), false if nothing was eligible to run.
    @discardableResult
    func runNext() async -> Bool {
        let tier = await scheduler.allowedTier()
        guard tier != .none else { return false }
        guard let job = await db.dequeueNextJob(projectID: projectID, maxTier: tier) else { return false }

        // If a model job was dequeued but no usable provider exists, return it to
        // the queue without burning a retry — it'll run once a provider is ready.
        if job.type.requiresProvider {
            let availability = await provider?.checkAvailability()
            guard let availability, availability.isUsable else {
                await db.requeueJob(id: job.id)
                return false
            }
        }

        do {
            let artifactID = try await execute(job)
            await db.completeJob(id: job.id, artifactID: artifactID)
        } catch {
            await db.recordFailure(id: job.id, error: error.localizedDescription)
        }
        return true
    }

    /// Drains up to `limit` jobs, stopping early when nothing is eligible.
    func drain(limit: Int = 100) async {
        var ran = 0
        while ran < limit {
            let didRun = await runNext()
            if !didRun { break }
            ran += 1
        }
    }

    // MARK: - Executors

    /// Executes a job, returning the id of any artifact it produced.
    private func execute(_ job: IntelligenceJob) async throws -> String? {
        switch job.type {
        case .summarizeFile:
            return try await summarizeFile(job)
        default:
            throw JobRunnerError.unsupportedJobType(job.type)
        }
    }

    private func summarizeFile(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        guard let relativePath = job.inputPaths.first else { throw JobRunnerError.missingInput }

        let fileURL = rootURL.appendingPathComponent(relativePath)
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8), !raw.isEmpty else {
            throw JobRunnerError.missingInput
        }
        let input = String(raw.prefix(maxInputChars))

        let messages = [
            EngineMessage(role: .system, content: """
            You are a code analysis assistant for a developer who did not hand-write \
            all of this code and needs to recover its intent. Summarize the file below \
            in concise Markdown: its purpose, key types/functions, notable fallbacks or \
            error handling, and anything surprising. Do not invent file paths or symbols \
            that are not present. Output only the Markdown summary.
            """),
            EngineMessage(role: .user, content: "File: \(relativePath)\n\n```\n\(input)\n```")
        ]
        let output = try await provider.generate(prompt: messages, maxTokens: 512)
        let summary = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw JobRunnerError.emptyOutput }

        // Anchor the whole summary to the source file so every claim is one click
        // from its origin (the trust contract from the research doc §4.2/§5).
        let fileID = await db.file(projectID: projectID, path: relativePath)?.id
        let provenance = ArtifactProvenance(
            artifactID: "",   // filled in by ArtifactStore
            claimAnchor: "summary",
            fileID: fileID, startLine: 1, endLine: nil, symbolID: nil, confidence: nil
        )

        let artifact = try await artifacts.store(
            type: .fileSummary,
            relativePath: "summaries/\(job.inputHash).md",
            title: relativePath,
            content: summary,
            sourceHashes: [job.inputHash],
            provenance: [provenance]
        )
        return artifact.id
    }
}
