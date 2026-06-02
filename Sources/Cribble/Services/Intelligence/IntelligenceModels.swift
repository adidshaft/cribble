import Foundation

// Core value types for the Cribble Intelligence engine. These are deliberately
// free of any SQLite, MLX, or SwiftUI types so the whole engine compiles and is
// unit-testable without a database connection or a loaded model — mirroring how
// `LocalChatEngine` keeps MLX out of the protocol surface.

/// What kind of work a job performs. The raw value is the stable string stored
/// in the `jobs.job_type` column; do not rename without a migration.
enum IntelligenceJobType: String, Codable, Sendable, CaseIterable {
    // Tier 1 — deterministic, no model needed.
    case scanWorkspace = "scan_workspace"
    case detectChangedFiles = "detect_changed_files"
    case parseCodeSymbols = "parse_code_symbols"
    case extractImports = "extract_imports"

    // Tier 2 — small, single-input model calls.
    case summarizeFile = "summarize_file"
    case summarizeDiff = "summarize_diff"
    case summarizeCommit = "summarize_commit"
    case extractFallbackLogic = "extract_fallback_logic"

    // Tier 3 — multi-input aggregation, idle only.
    case buildDependencyDiagram = "build_dependency_diagram"
    case buildArchitectureDiagram = "build_architecture_diagram"
    case updateProjectIndex = "update_project_index"
    case detectArchitectureDrift = "detect_architecture_drift"

    /// The scheduling tier this job belongs to. Drives idle-awareness gating in
    /// `BackgroundScheduler`.
    var tier: IntelligenceJobTier {
        switch self {
        case .scanWorkspace, .detectChangedFiles, .parseCodeSymbols, .extractImports:
            return .tier1
        case .summarizeFile, .summarizeDiff, .summarizeCommit, .extractFallbackLogic:
            return .tier2
        case .buildDependencyDiagram, .buildArchitectureDiagram, .updateProjectIndex, .detectArchitectureDrift:
            return .tier3
        }
    }

    /// Whether running this job type requires a loaded intelligence provider
    /// (a model). Tier 1 jobs are pure code and run even with no model present.
    var requiresProvider: Bool { tier != .tier1 }
}

/// Scheduling tier. Higher tiers are heavier and gated more aggressively.
/// `Comparable` so callers can write `job.tier <= scheduler.allowedTier`.
enum IntelligenceJobTier: Int, Codable, Sendable, Comparable {
    case none = 0   // nothing may run (e.g. thermal pressure)
    case tier1 = 1  // deterministic, always allowed
    case tier2 = 2  // small model calls, foreground allowed
    case tier3 = 3  // aggregation, idle only

    static func < (lhs: IntelligenceJobTier, rhs: IntelligenceJobTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Lifecycle state of a job in the queue. Raw value stored in `jobs.status`.
enum IntelligenceJobStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

/// The category of a generated artifact. Raw value stored in
/// `artifacts.artifact_type`.
enum IntelligenceArtifactType: String, Codable, Sendable {
    case fileSummary = "file_summary"
    case diffSummary = "diff_summary"
    case commitSummary = "commit_summary"
    case projectIndex = "project_index"
    case dependencyDiagram = "dependency_diagram"
    case architectureDiagram = "architecture_diagram"
    case fallbackAudit = "fallback_audit"
    case driftReport = "drift_report"
}

/// A unit of work as stored in / loaded from the queue.
struct IntelligenceJob: Identifiable, Sendable, Equatable {
    let id: String
    let projectID: String
    let type: IntelligenceJobType
    /// Hash of all inputs; a new job with a matching `inputHash` for the same
    /// type is skipped (already done / in flight).
    let inputHash: String
    /// JSON-encodable list of project-relative input paths.
    let inputPaths: [String]
    var status: IntelligenceJobStatus
    /// Lower = higher priority.
    var priority: Int
    var attemptCount: Int
    let maxAttempts: Int
    var modelID: String?
    var errorMessage: String?
    var outputArtifactID: String?
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        projectID: String,
        type: IntelligenceJobType,
        inputHash: String,
        inputPaths: [String] = [],
        status: IntelligenceJobStatus = .pending,
        priority: Int = 100,
        attemptCount: Int = 0,
        maxAttempts: Int = 3,
        modelID: String? = nil,
        errorMessage: String? = nil,
        outputArtifactID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.type = type
        self.inputHash = inputHash
        self.inputPaths = inputPaths
        self.status = status
        self.priority = priority
        self.attemptCount = attemptCount
        self.maxAttempts = maxAttempts
        self.modelID = modelID
        self.errorMessage = errorMessage
        self.outputArtifactID = outputArtifactID
        self.createdAt = createdAt
    }
}

/// A tracked source file as recorded in the `files` table.
struct IntelligenceFile: Identifiable, Sendable, Equatable {
    let id: Int64
    let projectID: String
    /// Path relative to the project root.
    let path: String
    let hash: String
    let sizeBytes: Int
    let language: String?
}

/// A generated artifact record (metadata; content lives on disk / in `content`).
struct IntelligenceArtifact: Identifiable, Sendable, Equatable {
    let id: String
    let projectID: String
    let type: IntelligenceArtifactType
    /// Path within `.cribble/intelligence/`.
    let relativePath: String
    let title: String?
    let contentHash: String
    /// Input file hashes that produced this artifact (for staleness checks).
    let sourceHashes: [String]
    var isPublished: Bool
}

/// Links a span of an artifact back to the exact source range that justifies it.
/// This is the backbone of the "every claim is verifiable in one click" trust
/// contract from the intelligence research doc (§5): no rendered claim should
/// exist without a `file:line` anchor behind it.
struct ArtifactProvenance: Sendable, Equatable {
    let artifactID: String
    /// Where in the artifact the claim sits (heading slug or character offset).
    let claimAnchor: String
    let fileID: Int64?
    let startLine: Int?
    let endLine: Int?
    let symbolID: Int64?
    /// Model- or validator-derived confidence in `0...1`, when known.
    let confidence: Double?
}
