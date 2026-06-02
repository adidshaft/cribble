import Foundation

enum JobRunnerError: LocalizedError {
    case providerUnavailable(String)
    case missingInput
    case emptyOutput
    case validationFailed([String])
    case unsupportedJobType(IntelligenceJobType)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let r): "Intelligence provider unavailable: \(r)"
        case .missingInput: "Job had no usable input."
        case .emptyOutput: "Model returned empty output."
        case .validationFailed(let issues): "Output failed validation: \(issues.joined(separator: "; "))"
        case .unsupportedJobType(let t): "No executor for job type \(t.rawValue)."
        }
    }
}

/// Drains the job queue one job at a time, respecting the scheduler's allowed
/// tier and the single-concurrent-SLM-job cap (design plan §8.3). Bridges
/// deterministic queue state and the (serialized) `IntelligenceProvider`.
///
/// Houses every executor: Phase-1 file summaries + project index, Phase-2 diff/
/// commit summaries + dependency/architecture diagrams, Phase-3 fallback audits +
/// architecture drift. Deterministic jobs (diagrams, drift) run with no model;
/// model jobs are gated by `requiresProvider`.
actor JobRunner {
    private let db: IntelligenceDatabase
    private let scheduler: BackgroundScheduler
    private let artifacts: ArtifactStore
    private let provider: IntelligenceProvider?
    private let git: GitInspector
    private let projectID: String
    private let projectName: String
    private let rootURL: URL
    private let maxInputChars: Int
    private let graphDirectory: URL

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
        self.git = GitInspector(rootURL: rootURL)
        self.projectID = projectID
        self.projectName = rootURL.lastPathComponent
        self.rootURL = rootURL
        self.maxInputChars = maxInputChars
        self.graphDirectory = artifacts.cacheDirectory.deletingLastPathComponent().appendingPathComponent("graph")
    }

    /// Runs at most one eligible job. Returns true if a job was executed.
    @discardableResult
    func runNext() async -> Bool {
        let tier = await scheduler.allowedTier()
        guard tier != .none else { return false }
        guard let job = await db.dequeueNextJob(projectID: projectID, maxTier: tier) else { return false }

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

    // MARK: - Executor dispatch

    private func execute(_ job: IntelligenceJob) async throws -> String? {
        switch job.type {
        case .summarizeFile:            return try await summarizeFile(job)
        case .extractFallbackLogic:     return try await fallbackAudit(job)
        case .summarizeDiff:            return try await summarizeDiff(job)
        case .summarizeCommit:          return try await summarizeCommit(job)
        case .updateProjectIndex:       return try await updateProjectIndex(job)
        case .buildDependencyDiagram:   return try await buildDependencyDiagram(job)
        case .buildArchitectureDiagram: return try await buildArchitectureDiagram(job)
        case .detectArchitectureDrift:  return try await detectArchitectureDrift(job)
        case .scanWorkspace, .detectChangedFiles, .parseCodeSymbols, .extractImports:
            // These are driven directly by WorkspaceScanner, not the queue.
            throw JobRunnerError.unsupportedJobType(job.type)
        }
    }

    // MARK: - Model executors

    private func summarizeFile(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        guard let path = job.inputPaths.first, let source = readSource(path) else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(prompt: Prompts.fileSummary(path: path, source: source), maxTokens: 512)
        let summary = try await validatedMarkdown(output)
        return try await storeSummary(summary, type: .fileSummary, path: path, inputHash: job.inputHash)
    }

    private func fallbackAudit(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        guard let path = job.inputPaths.first, let source = readSource(path) else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(prompt: Prompts.fallbackAudit(path: path, source: source), maxTokens: 512)
        let audit = try await validatedMarkdown(output)
        return try await storeSummary(audit, type: .fallbackAudit, path: path, inputHash: job.inputHash, pathPrefix: "audits")
    }

    private func summarizeDiff(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        guard let diff = await git.workingTreeDiff(), !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JobRunnerError.missingInput
        }
        let output = try await provider.generate(prompt: Prompts.diffSummary(diff: String(diff.prefix(maxInputChars))), maxTokens: 768)
        let summary = try await validatedMarkdown(output)
        let artifact = try await artifacts.store(
            type: .diffSummary, relativePath: "changes/working-tree-diff.md",
            title: "Working tree changes", content: summary, sourceHashes: [job.inputHash]
        )
        return artifact.id
    }

    private func summarizeCommit(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        guard let sha = job.inputPaths.first, let diff = await git.diff(forCommit: sha) else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(
            prompt: Prompts.commitSummary(subject: sha, diff: String(diff.prefix(maxInputChars))),
            maxTokens: 512
        )
        let summary = try await validatedMarkdown(output)
        let short = String(sha.prefix(8))
        let artifact = try await artifacts.store(
            type: .commitSummary, relativePath: "changes/commits/\(short).md",
            title: "Commit \(short)", content: summary, sourceHashes: [job.inputHash]
        )
        await db.markCommitSummarized(projectID: projectID, sha: sha)
        return artifact.id
    }

    private func updateProjectIndex(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        let summaryArtifacts = await db.artifacts(projectID: projectID, type: .fileSummary)
        let summaries: [(path: String, summary: String)] = summaryArtifacts.compactMap { artifact in
            guard let content = artifacts.content(for: artifact) else { return nil }
            return (artifact.title ?? artifact.relativePath, content)
        }
        guard !summaries.isEmpty else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(
            prompt: Prompts.projectIndex(projectName: projectName, summaries: summaries),
            maxTokens: 1200
        )
        let index = try await validatedMarkdown(output)
        let artifact = try await artifacts.store(
            type: .projectIndex, relativePath: "project-index.md",
            title: "\(projectName) — Project Index", content: index, sourceHashes: [job.inputHash]
        )
        return artifact.id
    }

    private func buildArchitectureDiagram(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        let graph = DependencyGraph.build(from: await db.allSymbols(projectID: projectID))
        let mermaid = graph.mermaid()
        let summaryArtifacts = await db.artifacts(projectID: projectID, type: .fileSummary)
        let summaries: [(path: String, summary: String)] = summaryArtifacts.compactMap { artifact in
            guard let content = artifacts.content(for: artifact) else { return nil }
            return (artifact.title ?? artifact.relativePath, content)
        }
        let output = try await provider.generate(
            prompt: Prompts.architectureNarration(graphMermaid: mermaid, summaries: summaries),
            maxTokens: 1200
        )
        let narration = try await validatedMarkdown(output)
        // Artifact embeds the validated diagram + the narration so it renders as
        // one document in the HUD.
        let content = "\(narration)\n\n```mermaid\n\(mermaid)\n```\n"
        let artifact = try await artifacts.store(
            type: .architectureDiagram, relativePath: "architecture/system-overview.md",
            title: "Architecture", content: content, sourceHashes: [job.inputHash]
        )
        return artifact.id
    }

    // MARK: - Deterministic executors (no model)

    private func buildDependencyDiagram(_ job: IntelligenceJob) async throws -> String? {
        let graph = DependencyGraph.build(from: await db.allSymbols(projectID: projectID))
        let mermaid = graph.mermaid()
        let validation = OutputValidator.validateMermaid(mermaid)
        guard validation.isValid else { throw JobRunnerError.validationFailed(validation.issues) }
        try persistBaselineEdges(graph.edges)
        let content = "# Dependency Map\n\nGenerated from static symbol analysis.\n\n```mermaid\n\(mermaid)\n```\n"
        let artifact = try await artifacts.store(
            type: .dependencyDiagram, relativePath: "architecture/dependency-map.md",
            title: "Dependency Map", content: content, sourceHashes: [job.inputHash]
        )
        return artifact.id
    }

    private func detectArchitectureDrift(_ job: IntelligenceJob) async throws -> String? {
        let current = DependencyGraph.build(from: await db.allSymbols(projectID: projectID))
        let baseline = loadBaselineEdges()
        let drifts = current.drift(comparedToDocumented: baseline)
        try persistBaselineEdges(current.edges)   // new baseline for next time

        let body: String
        if drifts.isEmpty {
            body = "# Architecture Drift\n\nNo drift detected — the code structure matches the last recorded baseline."
        } else {
            let lines = drifts.map { drift -> String in
                let arrow = "`\(drift.edge.from)` →(\(drift.edge.label)) `\(drift.edge.to)`"
                switch drift.kind {
                case .missingInCode:    return "- **Removed since baseline:** \(arrow)"
                case .missingInDiagram: return "- **New since baseline:** \(arrow)"
                }
            }
            body = "# Architecture Drift\n\n\(drifts.count) change(s) since the last baseline:\n\n" + lines.joined(separator: "\n")
        }
        let artifact = try await artifacts.store(
            type: .driftReport, relativePath: "audits/drift-report.md",
            title: "Architecture Drift", content: body, sourceHashes: [job.inputHash]
        )
        return artifact.id
    }

    // MARK: - Helpers

    private func readSource(_ relativePath: String) -> String? {
        let url = rootURL.appendingPathComponent(relativePath)
        guard let raw = try? String(contentsOf: url, encoding: .utf8), !raw.isEmpty else { return nil }
        return String(raw.prefix(maxInputChars))
    }

    /// Trims, checks non-empty, and cross-references any paths against known files.
    private func validatedMarkdown(_ output: String) async throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JobRunnerError.emptyOutput }
        let known = Set(await db.files(projectID: projectID).map(\.path))
        let result = OutputValidator.validateMarkdown(trimmed, knownPaths: known)
        guard result.isValid else { throw JobRunnerError.validationFailed(result.issues) }
        return trimmed
    }

    private func storeSummary(
        _ content: String, type: IntelligenceArtifactType, path: String,
        inputHash: String, pathPrefix: String = "summaries"
    ) async throws -> String? {
        let fileID = await db.file(projectID: projectID, path: path)?.id
        let provenance = ArtifactProvenance(
            artifactID: "", claimAnchor: "summary",
            fileID: fileID, startLine: 1, endLine: nil, symbolID: nil, confidence: nil
        )
        let artifact = try await artifacts.store(
            type: type, relativePath: "\(pathPrefix)/\(inputHash).md",
            title: path, content: content, sourceHashes: [inputHash], provenance: [provenance]
        )
        return artifact.id
    }

    private func baselineURL() -> URL {
        graphDirectory.appendingPathComponent("baseline-edges.json")
    }

    private func persistBaselineEdges(_ edges: [DependencyGraph.Edge]) throws {
        try FileManager.default.createDirectory(at: graphDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(edges)
        try data.write(to: baselineURL(), options: .atomic)
    }

    private func loadBaselineEdges() -> [DependencyGraph.Edge] {
        guard let data = try? Data(contentsOf: baselineURL()),
              let edges = try? JSONDecoder().decode([DependencyGraph.Edge].self, from: data) else { return [] }
        return edges
    }
}
