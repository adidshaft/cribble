import Foundation

/// Stable input signatures for aggregate Intelligence jobs. These intentionally
/// track the data a job actually reads, not every file in the project, so no-op
/// ticks and unrelated edits do not keep waking aggregate model work.
enum IntelligenceAggregateSignatures {
    static let maxSummaryInputs = 80

    static func allFiles(_ files: [IntelligenceFile]) -> String {
        hashEntries("files", files.map { file in
            "\(file.path)\u{1}\(file.hash)\u{1}\(file.language ?? "")"
        })
    }

    static func markdownFiles(_ files: [IntelligenceFile]) -> String {
        hashEntries("markdown-files", files
            .filter { $0.language == SourceLanguage.markdown.rawValue }
            .map { "\($0.path)\u{1}\($0.hash)" })
    }

    static func symbols(_ symbols: [SymbolRecord]) -> String {
        hashEntries("symbols", symbols.map { symbol in
            [
                symbol.filePath,
                symbol.name,
                symbol.kind,
                symbol.startLine.map(String.init) ?? "",
                symbol.endLine.map(String.init) ?? "",
                symbol.signature ?? ""
            ].joined(separator: "\u{1}")
        })
    }

    static func summaries(_ artifacts: [IntelligenceArtifact]) -> String? {
        let entries = artifacts
            .filter { $0.type == .fileSummary }
            .sorted { lhs, rhs in
                if lhs.relativePath == rhs.relativePath {
                    return (lhs.title ?? "") < (rhs.title ?? "")
                }
                return lhs.relativePath < rhs.relativePath
            }
            .prefix(maxSummaryInputs)
            .map { artifact in
                [
                    artifact.relativePath,
                    artifact.title ?? "",
                    artifact.contentHash,
                    artifact.sourceHashes.joined(separator: "\u{2}")
                ].joined(separator: "\u{1}")
            }
        guard !entries.isEmpty else { return nil }
        return hashEntries("summaries", Array(entries))
    }

    static func connectionsGraph(markdownSignature: String) -> String {
        ContentHasher.combine(["connections-graph", markdownSignature])
    }

    static func dependencyDiagram(symbolSignature: String) -> String {
        ContentHasher.combine(["dependency-diagram", symbolSignature])
    }

    static func architectureDrift(symbolSignature: String) -> String {
        ContentHasher.combine(["architecture-drift", symbolSignature])
    }

    static func projectIndex(summarySignature: String) -> String {
        ContentHasher.combine(["project-index", summarySignature])
    }

    static func architectureDiagram(symbolSignature: String, summarySignature: String) -> String {
        ContentHasher.combine(["architecture-diagram", symbolSignature, summarySignature])
    }

    static func discoveredConnections(summarySignature: String) -> String {
        ContentHasher.combine(["discover-connections", summarySignature])
    }

    static func gitProbe(filesSignature: String, gitMarkerSignature: String) -> String {
        ContentHasher.combine(["git-probe", filesSignature, gitMarkerSignature])
    }

    static func contradictions(summarySignature: String) -> String {
        ContentHasher.combine(["contradictions", summarySignature])
    }

    static func glossary(summarySignature: String) -> String {
        ContentHasher.combine(["glossary", summarySignature])
    }

    static func timeline(summarySignature: String) -> String {
        ContentHasher.combine(["timeline", summarySignature])
    }

    private static func hashEntries(_ namespace: String, _ entries: [String]) -> String {
        ContentHasher.combine([namespace] + entries.map(ContentHasher.hash))
    }
}
