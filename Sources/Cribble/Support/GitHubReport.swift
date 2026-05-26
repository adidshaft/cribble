import AppKit
import Foundation

enum GitHubReport {
    private static let repositoryURL = URL(string: "https://github.com/adidshaft/cribble")!
    private static let maxPrefilledReportLength = 6_000

    static func issueURL(report: String) -> URL {
        var components = URLComponents(
            url: repositoryURL.appendingPathComponent("issues/new"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "title", value: "Cribble report: "),
            URLQueryItem(name: "labels", value: "bug,needs-triage"),
            URLQueryItem(name: "body", value: issueBody(report: report))
        ]
        return components.url!
    }

    static func pullRequestURL(report: String) -> URL {
        var components = URLComponents(
            url: repositoryURL.appendingPathComponent("compare"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "quick_pull", value: "1"),
            URLQueryItem(name: "title", value: "Fix Cribble issue"),
            URLQueryItem(name: "body", value: pullRequestBody(report: report))
        ]
        return components.url!
    }

    static func openIssue(report: String) {
        copy(report: report)
        NSWorkspace.shared.open(issueURL(report: report))
    }

    static func openPullRequest(report: String) {
        copy(report: report)
        NSWorkspace.shared.open(pullRequestURL(report: report))
    }

    private static func issueBody(report: String) -> String {
        """
        Thanks for helping improve Cribble.

        ## What happened?


        ## What did you expect?


        ## Steps to reproduce
        1.
        2.
        3.

        ## Diagnostic report
        The full report has also been copied to your clipboard. If this section looks cut off, paste the clipboard contents here.
        If the report lists a latest macOS crash file, attach that `.crash` or `.ips` file to this issue too.

        \(trimmed(report))
        """
    }

    private static func pullRequestBody(report: String) -> String {
        """
        ## Summary


        ## Testing
        - [ ] Built Cribble locally
        - [ ] Tested the affected flow

        ## Related diagnostic context
        The full diagnostic report has also been copied to your clipboard.

        \(trimmed(report))
        """
    }

    private static func trimmed(_ report: String) -> String {
        guard report.count > maxPrefilledReportLength else { return report }
        let endIndex = report.index(report.startIndex, offsetBy: maxPrefilledReportLength)
        return String(report[..<endIndex]) + "\n\n[Report truncated for URL length. Paste the clipboard contents for the full report.]"
    }

    private static func copy(report: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
