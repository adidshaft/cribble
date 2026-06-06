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

struct JobDrainResult: Sendable, Equatable {
    var ranJobs: Int
    var allowedTier: IntelligenceJobTier
    var providerUsable: Bool
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
    private let maxAggregateSummaryChars = 24_000
    private let graphDirectory: URL
    /// Optional headless Mermaid validator (best-effort; see MermaidRenderValidator).
    private let mermaidValidator: (@Sendable (String) async -> Bool)?

    init(
        db: IntelligenceDatabase,
        scheduler: BackgroundScheduler,
        artifacts: ArtifactStore,
        provider: IntelligenceProvider?,
        projectID: String,
        rootURL: URL,
        maxInputChars: Int = 12_000,
        mermaidValidator: (@Sendable (String) async -> Bool)? = nil
    ) {
        self.mermaidValidator = mermaidValidator
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
        let providerUsable = tier >= .tier2 ? await isProviderUsable() : false
        return await runNext(allowedTier: tier, providerUsable: providerUsable)
    }

    @discardableResult
    private func runNext(allowedTier tier: IntelligenceJobTier, providerUsable: Bool) async -> Bool {
        guard tier != .none else { return false }

        // If no model is usable, only pull deterministic jobs. Otherwise a
        // model-needing job at the front of the queue would block model-free
        // diagram/drift jobs behind it until a model arrives.
        guard let job = await db.dequeueNextJob(projectID: projectID, maxTier: tier, deterministicOnly: !providerUsable) else {
            return false
        }

        do {
            let artifactID = try await execute(job)
            await db.completeJob(id: job.id, artifactID: artifactID)
        } catch {
            await db.recordFailure(id: job.id, error: error.localizedDescription)
        }
        return true
    }

    private func isProviderUsable() async -> Bool {
        guard let provider else { return false }
        return await provider.checkAvailability().isUsable
    }

    /// Drains up to `limit` jobs, stopping early when nothing is eligible.
    @discardableResult
    func drain(limit: Int = 100, allowedTier suppliedTier: IntelligenceJobTier? = nil) async -> JobDrainResult {
        let tier: IntelligenceJobTier
        if let suppliedTier {
            tier = suppliedTier
        } else {
            tier = await scheduler.allowedTier()
        }
        guard tier != .none else {
            return JobDrainResult(ranJobs: 0, allowedTier: tier, providerUsable: false)
        }

        // Provider checks can touch model inventory or a local runner. Do it once
        // per drain, and skip it entirely when the current resource policy allows
        // only deterministic Tier-1 work.
        let providerUsable = tier >= .tier2 ? await isProviderUsable() : false
        var ran = 0
        while ran < limit {
            let didRun = await runNext(allowedTier: tier, providerUsable: providerUsable)
            if !didRun { break }
            ran += 1
        }
        return JobDrainResult(ranJobs: ran, allowedTier: tier, providerUsable: providerUsable)
    }

    // MARK: - Executor dispatch

    private func execute(_ job: IntelligenceJob) async throws -> String? {
        switch job.type {
        case .analyzeFile:             return try await analyzeFile(job)
        case .summarizeFile:            return try await summarizeFile(job)
        case .extractFallbackLogic:     return try await fallbackAudit(job)
        case .extractIOBehavior:        return try await ioBehavior(job)
        case .summarizeDiff:            return try await summarizeDiff(job)
        case .summarizeCommit:          return try await summarizeCommit(job)
        case .updateProjectIndex:       return try await updateProjectIndex(job)
        case .buildDependencyDiagram:   return try await buildDependencyDiagram(job)
        case .buildConnectionsGraph:    return try await buildConnectionsGraph(job)
        case .buildArchitectureDiagram: return try await buildArchitectureDiagram(job)
        case .detectArchitectureDrift:  return try await detectArchitectureDrift(job)
        case .discoverConnections:      return try await discoverConnections(job)
        case .detectContradictions:     return try await detectContradictions(job)
        case .buildGlossary:            return try await buildGlossary(job)
        case .buildTimeline:            return try await buildTimeline(job)
        case .scanWorkspace, .detectChangedFiles, .parseCodeSymbols, .extractImports:
            // These are driven directly by WorkspaceScanner, not the queue.
            throw JobRunnerError.unsupportedJobType(job.type)
        }
    }

    // MARK: - Model executors

    private func analyzeFile(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        guard let path = job.inputPaths.first, let source = readSource(path) else { throw JobRunnerError.missingInput }
        let language = await db.file(projectID: projectID, path: path)?.language
        let output = try await provider.generate(
            prompt: Prompts.fileAnalysisBundle(path: path, language: language, source: source),
            maxTokens: 1200
        )
        let bundle = parseFileAnalysisBundle(output)
        let summary = try await validatedMarkdown(bundle.summary)
        let fallback = try await validatedMarkdown(bundle.fallbacks)
        let io = try await validatedMarkdown(bundle.ioBehavior)

        let summaryID = try await storeSummary(summary, type: .fileSummary, path: path, inputHash: job.inputHash)
        _ = try await storeSummary(fallback, type: .fallbackAudit, path: path, inputHash: job.inputHash, pathPrefix: "audits")
        _ = try await storeSummary(io, type: .ioBehavior, path: path, inputHash: job.inputHash, pathPrefix: "behavior")
        await upsertFileNode(path: path, inputHash: job.inputHash)
        return summaryID
    }

    private func summarizeFile(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        guard let path = job.inputPaths.first, let source = readSource(path) else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(prompt: Prompts.fileSummary(path: path, source: source), maxTokens: 512)
        let summary = try await validatedMarkdown(output)
        let artifactID = try await storeSummary(summary, type: .fileSummary, path: path, inputHash: job.inputHash)
        await upsertFileNode(path: path, inputHash: job.inputHash)
        return artifactID
    }

    private func fallbackAudit(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        guard let path = job.inputPaths.first, let source = readSource(path) else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(prompt: Prompts.fallbackAudit(path: path, source: source), maxTokens: 512)
        let audit = try await validatedMarkdown(output)
        return try await storeSummary(audit, type: .fallbackAudit, path: path, inputHash: job.inputHash, pathPrefix: "audits")
    }

    private func ioBehavior(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        guard let path = job.inputPaths.first, let source = readSource(path) else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(prompt: Prompts.ioBehavior(path: path, source: source), maxTokens: 512)
        let behavior = try await validatedMarkdown(output)
        return try await storeSummary(behavior, type: .ioBehavior, path: path, inputHash: job.inputHash, pathPrefix: "behavior")
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
        let summaries = await aggregateSummaryInputs()
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
        await persistEmbedding(artifactID: artifact.id, text: index)
        return artifact.id
    }

    private func buildArchitectureDiagram(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        let graph = DependencyGraph.build(from: await db.allSymbols(projectID: projectID))
        let mermaid = graph.mermaid()
        let summaries = await aggregateSummaryInputs()
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

    private func discoverConnections(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        let summaries = await aggregateSummaryInputs()
        guard summaries.count >= 2 else { throw JobRunnerError.missingInput }

        let output = try await provider.generate(
            prompt: Prompts.connectionResearch(summaries: summaries),
            maxTokens: 1200
        )
        let body = try await validatedMarkdown(output)
        let artifact = try await artifacts.store(
            type: .researchInsight,
            relativePath: "research/suggested-connections.md",
            title: "Suggested Connections",
            content: body,
            sourceHashes: [job.inputHash]
        )
        await persistEmbedding(artifactID: artifact.id, text: body)
        await db.upsertResearchInsight(ResearchInsight(
            id: ContentHasher.hash("\(projectID)\u{1}suggested-connections\u{1}\(job.inputHash)"),
            projectID: projectID,
            title: "Suggested Connections",
            body: body,
            kind: .suggestedConnection,
            status: .new,
            artifactID: artifact.id,
            sourceHashes: [job.inputHash],
            createdAt: Date()
        ))
        await persistSuggestedConnectionEdges(markdown: body, evidenceArtifactID: artifact.id, sourceHashes: [job.inputHash])
        return artifact.id
    }

    // MARK: - Deterministic executors (no model)

    private func buildDependencyDiagram(_ job: IntelligenceJob) async throws -> String? {
        let graph = DependencyGraph.build(from: await db.allSymbols(projectID: projectID))
        try persistBaselineEdges(graph.edges)
        await persistKnowledgeGraph(graph: graph, kind: .dependency, origin: .deterministic, status: .accepted, sourceHashes: [job.inputHash])
        let content: String
        if graph.nodes.isEmpty {
            // No parsed symbols (e.g. a non-Swift project — Phase 1 only parses
            // Swift). Skip the empty diagram; record a plain note.
            content = "# Dependency Map\n\nNo code dependencies detected yet. (Symbol-level analysis currently covers Swift; other languages get file summaries.)"
        } else {
            let mermaid = graph.mermaid(clickable: true)
            let validation = OutputValidator.validateMermaid(mermaid)
            guard validation.isValid else { throw JobRunnerError.validationFailed(validation.issues) }
            // Headless render check (best-effort, timeout-bounded): only rejects on
            // a definitive parse failure; infra problems fall through as valid.
            if let mermaidValidator, await mermaidValidator(mermaid) == false {
                throw JobRunnerError.validationFailed(["mermaid failed headless render"])
            }
            content = "# Dependency Map\n\nGenerated from static symbol analysis.\n\n```mermaid\n\(mermaid)\n```\n"
        }
        let artifact = try await artifacts.store(
            type: .dependencyDiagram, relativePath: "architecture/dependency-map.md",
            title: "Dependency Map", content: content, sourceHashes: [job.inputHash]
        )
        return artifact.id
    }

    private func buildConnectionsGraph(_ job: IntelligenceJob) async throws -> String? {
        let mdFiles = await db.files(projectID: projectID)
            .filter { $0.language == SourceLanguage.markdown.rawValue }
            .map { (path: $0.path, url: resolve($0.path)) }
        let graph = NoteConnectionsGraph.build(markdownFiles: mdFiles)
        await persistKnowledgeGraph(graph: graph, kind: .wikiLink, origin: .deterministic, status: .accepted, sourceHashes: [job.inputHash])
        let content: String
        if graph.edges.isEmpty {
            content = "# Connections\n\nNo `[[wiki links]]` between notes found yet. Add links like `[[Another Note]]` to see them connected here."
        } else {
            let mermaid = graph.mermaid(maxNodes: 60, clickable: true)
            if let mermaidValidator, await mermaidValidator(mermaid) == false {
                throw JobRunnerError.validationFailed(["mermaid failed headless render"])
            }
            content = "# Connections\n\nHow your notes link to each other (\(graph.edges.count) links).\n\n```mermaid\n\(mermaid)\n```\n"
        }
        let artifact = try await artifacts.store(
            type: .connectionsGraph, relativePath: "connections/note-graph.md",
            title: "Connections", content: content, sourceHashes: [job.inputHash]
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

    /// Resolves a stored path: absolute (multi-folder scope) or relative to root.
    private func resolve(_ path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : rootURL.appendingPathComponent(path)
    }

    private func readSource(_ relativePath: String) -> String? {
        let url = resolve(relativePath)
        guard let raw = try? String(contentsOf: url, encoding: .utf8), !raw.isEmpty else { return nil }
        return String(raw.prefix(maxInputChars))
    }

    private func detectContradictions(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        let summaries = await aggregateSummaryInputs()
        guard summaries.count >= 2 else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(
            prompt: Prompts.contradictionReport(documents: summaries),
            maxTokens: 1200
        )
        let body = try await validatedMarkdown(output)
        let artifact = try await artifacts.store(
            type: .contradictionReport, relativePath: "insights/contradictions.md",
            title: "Contradiction Report", content: body, sourceHashes: [job.inputHash]
        )
        await persistEmbedding(artifactID: artifact.id, text: body)
        return artifact.id
    }

    private func buildGlossary(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        let summaries = await aggregateSummaryInputs()
        guard summaries.count >= 2 else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(
            prompt: Prompts.glossary(documents: summaries),
            maxTokens: 1400
        )
        let body = try await validatedMarkdown(output)
        let artifact = try await artifacts.store(
            type: .glossary, relativePath: "insights/glossary.md",
            title: "Glossary", content: body, sourceHashes: [job.inputHash]
        )
        await persistEmbedding(artifactID: artifact.id, text: body)
        return artifact.id
    }

    private func buildTimeline(_ job: IntelligenceJob) async throws -> String? {
        guard let provider else { throw JobRunnerError.providerUnavailable("none configured") }
        let summaries = await aggregateSummaryInputs()
        guard summaries.count >= 2 else { throw JobRunnerError.missingInput }
        let output = try await provider.generate(
            prompt: Prompts.timeline(documents: summaries),
            maxTokens: 1200
        )
        let body = try await validatedMarkdown(output)
        let artifact = try await artifacts.store(
            type: .timeline, relativePath: "insights/timeline.md",
            title: "Timeline", content: body, sourceHashes: [job.inputHash]
        )
        await persistEmbedding(artifactID: artifact.id, text: body)
        return artifact.id
    }

    private func aggregateSummaryInputs() async -> [(path: String, summary: String)] {
        let summaryArtifacts = await db.artifacts(projectID: projectID, type: .fileSummary)
        let currentSourceHashes = Set((await db.files(projectID: projectID)).map(\.hash))
        var summaries: [(path: String, summary: String)] = []
        var seenPaths: Set<String> = []
        var remainingChars = maxAggregateSummaryChars

        for artifact in summaryArtifacts.prefix(IntelligenceAggregateSignatures.maxSummaryInputs) where remainingChars > 0 {
            guard !Set(artifact.sourceHashes).isDisjoint(with: currentSourceHashes) else { continue }
            let path = artifact.title ?? artifact.relativePath
            guard seenPaths.insert(path).inserted else { continue }
            guard let content = artifacts.content(for: artifact), !content.isEmpty else { continue }
            let clipped = String(content.prefix(remainingChars))
            summaries.append((path, clipped))
            remainingChars -= clipped.count
        }

        return summaries
    }

    /// Trims, checks non-empty, and cross-references any paths against known files.
    private func validatedMarkdown(_ output: String) async throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JobRunnerError.emptyOutput }
        // Never store an error message as an artifact (e.g. an unauthenticated
        // CLI's "API Error: 401"). Fail the job instead so it retries / surfaces.
        if let reason = OutputValidator.looksLikeError(trimmed) {
            throw JobRunnerError.validationFailed([reason])
        }
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
        await persistEmbedding(artifactID: artifact.id, text: "\(path)\n\(content)")
        return artifact.id
    }

    private struct FileAnalysisBundle {
        var summary: String
        var fallbacks: String
        var ioBehavior: String
    }

    /// Small local parser for the structured Markdown bundle. It accepts ideal
    /// sectioned output, but degrades old/plain provider responses into a summary
    /// so retries are not wasted on formatting alone.
    private func parseFileAnalysisBundle(_ output: String) -> FileAnalysisBundle {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = markdownSections(trimmed)
        let summary = sections["summary"] ?? trimmed
        let fallbacks = sections["fallbacks"] ?? sections["fallback"] ?? "No explicit fallbacks found."
        let io = sections["i/o behavior"] ?? sections["io behavior"] ?? sections["i/o"] ?? sections["io"] ?? "No external I/O found."
        return FileAnalysisBundle(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            fallbacks: fallbacks.trimmingCharacters(in: .whitespacesAndNewlines),
            ioBehavior: io.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func markdownSections(_ markdown: String) -> [String: String] {
        var result: [String: [String]] = [:]
        var current: String?
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                let heading = String(line.dropFirst(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                current = heading
                result[heading, default: []] = []
            } else if let current {
                result[current, default: []].append(line)
            }
        }
        return result.mapValues { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func upsertFileNode(path: String, inputHash: String) async {
        await db.upsertKnowledgeNode(KnowledgeNode(
            id: nodeID(path),
            projectID: projectID,
            kind: .file,
            title: (path as NSString).lastPathComponent,
            path: path,
            artifactID: nil
        ))
    }

    private func persistKnowledgeGraph(
        graph: DependencyGraph,
        kind: KnowledgeEdge.Kind,
        origin: KnowledgeEdge.Origin,
        status: KnowledgeEdge.Status,
        sourceHashes: [String]
    ) async {
        for (id, label) in graph.nodes {
            await db.upsertKnowledgeNode(KnowledgeNode(
                id: nodeID(id),
                projectID: projectID,
                kind: id.hasPrefix("module:") ? .module : .file,
                title: label,
                path: id.hasPrefix("module:") ? nil : id,
                artifactID: nil
            ))
        }
        for edge in graph.edges {
            let from = nodeID(edge.from)
            let to = nodeID(edge.to)
            let edgeID = ContentHasher.hash("\(projectID)\u{1}\(kind.rawValue)\u{1}\(from)\u{1}\(to)\u{1}\(edge.label)")
            await db.upsertKnowledgeEdge(KnowledgeEdge(
                id: edgeID,
                projectID: projectID,
                fromNodeID: from,
                toNodeID: to,
                kind: kind,
                origin: origin,
                status: status,
                confidence: origin == .deterministic ? 1 : nil,
                evidenceArtifactID: nil,
                sourceHashes: sourceHashes
            ))
        }
    }

    private func nodeID(_ raw: String) -> String {
        ContentHasher.hash("\(projectID)\u{1}\(raw)")
    }

    private func persistSuggestedConnectionEdges(markdown: String, evidenceArtifactID: String, sourceHashes: [String]) async {
        let knownPaths = Set(await db.files(projectID: projectID).map(\.path))
        guard let regex = try? NSRegularExpression(pattern: #"`([^`]+)`\s*=>\s*`([^`]+)`"#) else { return }
        let ns = markdown as NSString
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            let from = ns.substring(with: match.range(at: 1))
            let to = ns.substring(with: match.range(at: 2))
            guard knownPaths.contains(from), knownPaths.contains(to), from != to else { continue }
            await upsertFileNode(path: from, inputHash: sourceHashes.first ?? "")
            await upsertFileNode(path: to, inputHash: sourceHashes.first ?? "")
            let edgeID = ContentHasher.hash("\(projectID)\u{1}suggested\u{1}\(from)\u{1}\(to)")
            await db.upsertKnowledgeEdge(KnowledgeEdge(
                id: edgeID,
                projectID: projectID,
                fromNodeID: nodeID(from),
                toNodeID: nodeID(to),
                kind: .semanticSimilarity,
                origin: .llmSuggested,
                status: .suggested,
                confidence: 0.7,
                evidenceArtifactID: evidenceArtifactID,
                sourceHashes: sourceHashes
            ))
        }
    }

    /// Best-effort embedding for semantic retrieval. Silent no-op if the provider
    /// has no embedding capability.
    private func persistEmbedding(artifactID: String, text: String) async {
        guard let vector = try? await provider?.embed(text: text), !vector.isEmpty else { return }
        await db.upsertEmbedding(artifactID: artifactID, projectID: projectID, vector: vector)
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
