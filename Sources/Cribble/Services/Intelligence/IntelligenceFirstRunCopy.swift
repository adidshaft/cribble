import Foundation

struct IntelligenceEmptyStateCopy: Equatable {
    let icon: String
    let title: String
    let detail: String
}

enum IntelligenceFirstRunCopy {
    static func artifactEmptyState(
        status: IntelligenceEngine.Status,
        filesIndexed: Int,
        analyzedCount: Int,
        pendingJobs: Int,
        providerHealth: ProviderHealth,
        projectName: String?
    ) -> IntelligenceEmptyStateCopy {
        if case .scanning = status {
            return IntelligenceEmptyStateCopy(
                icon: "doc.text.magnifyingglass",
                title: "Reading your folder — \(filesIndexed) files so far",
                detail: "Cribble is finding notes and source files it can turn into local intelligence."
            )
        }

        if case .unavailable(let reason, _) = providerHealth {
            return IntelligenceEmptyStateCopy(
                icon: "exclamationmark.triangle",
                title: "AI engine needs attention",
                detail: reason
            )
        }

        if filesIndexed > 0, pendingJobs > 0 {
            return IntelligenceEmptyStateCopy(
                icon: "hourglass",
                title: "Analyzing \(min(analyzedCount, filesIndexed)) of \(filesIndexed) files",
                detail: "Deterministic maps can appear first while model-backed summaries fill in."
            )
        }

        return IntelligenceEmptyStateCopy(
            icon: "tray",
            title: "Waiting for artifacts",
            detail: "Summaries and diagrams will appear here as \(projectName ?? "this project") is indexed."
        )
    }
}
