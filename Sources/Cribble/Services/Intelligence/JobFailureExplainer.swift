import Foundation

struct JobFailureExplanation: Equatable {
    let summary: String
    let suggestion: Suggestion

    enum Suggestion: Equatable {
        case retry
        case providerFix
        case skipFile(String)
    }
}

enum JobFailureExplainer {
    static func explain(
        type: IntelligenceJobType,
        errorMessage: String?,
        inputPath: String? = nil
    ) -> JobFailureExplanation {
        let error = (errorMessage ?? "").lowercased()

        if error.contains("output failed validation") || error.contains("validationfailed") {
            return JobFailureExplanation(
                summary: "The model's output didn't pass Cribble's checks.",
                suggestion: .retry
            )
        }

        if error.contains("provider unavailable") || error.contains("providerunavailable") {
            return JobFailureExplanation(
                summary: "The AI engine wasn't reachable.",
                suggestion: .providerFix
            )
        }

        if error.contains("timed out") || error.contains("timeout") || error.contains("bounded") {
            return JobFailureExplanation(
                summary: "This took too long — the file may be very large.",
                suggestion: .retry
            )
        }

        if error.contains("empty output") || error.contains("returned empty") || error.contains("emptyoutput") {
            return JobFailureExplanation(
                summary: "The model returned nothing for this file.",
                suggestion: .retry
            )
        }

        if error.contains("no usable input") || error.contains("missinginput") || error.contains("moved or was deleted") {
            return JobFailureExplanation(
                summary: "The source file moved or was deleted.",
                suggestion: .skipFile(inputPath ?? "the missing source")
            )
        }

        return JobFailureExplanation(
            summary: "\(type.displayName) needs another try.",
            suggestion: .retry
        )
    }
}

enum IntelligenceJobActivity {
    static func describe(_ job: IntelligenceJob) -> String {
        let firstPath = job.inputPaths.first.map(displayName(for:))
        switch job.type {
        case .analyzeFile, .summarizeFile:
            return "Summarizing \(firstPath ?? "file")"
        case .extractFallbackLogic:
            return "Auditing fallbacks in \(firstPath ?? "file")"
        case .extractIOBehavior:
            return "Mapping I/O in \(firstPath ?? "file")"
        case .summarizeDiff:
            return "Summarizing working changes"
        case .summarizeCommit:
            let sha = job.inputPaths.first.map { String($0.prefix(8)) } ?? "commit"
            return "Summarizing commit \(sha)"
        case .updateProjectIndex:
            return "Updating project index"
        case .buildDependencyDiagram:
            return "Building dependency map"
        case .buildConnectionsGraph:
            return "Mapping note connections"
        case .buildArchitectureDiagram:
            return "Drawing architecture"
        case .detectArchitectureDrift:
            return "Checking architecture drift"
        case .discoverConnections:
            return "Finding related notes"
        case .detectContradictions:
            return "Checking for contradictions"
        case .buildGlossary:
            return "Building glossary (\(job.inputPaths.count) documents)"
        case .buildTimeline:
            return "Building timeline"
        case .scanWorkspace:
            return "Scanning workspace"
        case .detectChangedFiles:
            return "Checking changed files"
        case .parseCodeSymbols:
            return "Parsing code symbols"
        case .extractImports:
            return "Extracting imports"
        }
    }

    private static func displayName(for path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

extension IntelligenceJobType {
    var displayName: String {
        rawValue
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
