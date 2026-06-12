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

extension IntelligenceJobType {
    var displayName: String {
        rawValue
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
