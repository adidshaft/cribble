import AppKit
import SwiftUI

struct DiagnosticsReportSheet: View {
    let report: String
    let crashReport: CrashReportFile?
    let onCopy: () -> Void
    let onCopyCrashReport: () -> Bool
    let onRevealCrashReport: () -> Bool
    let onReportIssue: () -> Void
    let onOpenPullRequest: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false
    @State private var didCopyCrashReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diagnostic Report")
                        .font(.title2.weight(.semibold))
                    Text(crashReportStatus)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ScrollView {
                Text(report)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .cribbleGlass(in: RoundedRectangle(cornerRadius: 10))

            HStack {
                if didCopy {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if didCopyCrashReport {
                    Label("Crash report copied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    onOpenPullRequest()
                } label: {
                    Label("Open PR", systemImage: "arrow.triangle.pull")
                }
                .help("Open GitHub's pull request flow and copy this report")

                Button {
                    if onRevealCrashReport() {
                        didCopy = false
                    }
                } label: {
                    Label("Reveal Crash File", systemImage: "doc.badge.magnifyingglass")
                }
                .disabled(crashReport == nil)
                .help("Reveal the latest Cribble .crash or .ips file in Finder")

                Button {
                    didCopyCrashReport = onCopyCrashReport()
                    didCopy = false
                } label: {
                    Label("Copy Crash File", systemImage: "doc.text")
                }
                .disabled(crashReport == nil)
                .help("Copy the full latest Cribble crash report to the clipboard")

                Button {
                    onReportIssue()
                } label: {
                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                }
                .help("Open a prefilled GitHub issue and copy this report")

                Button {
                    onCopy()
                    didCopy = true
                } label: {
                    Label("Copy Report", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .cribbleGlassButton(prominent: true)
                .help("Copy the diagnostic report to the clipboard")
            }
        }
        .padding(22)
        .frame(width: 760, height: 560)
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 18))
    }

    private var crashReportStatus: String {
        guard let crashReport else {
            return "Copy this report when Cribble crashes, gets stuck, or behaves strangely."
        }

        return "Latest crash file found: \(crashReport.url.lastPathComponent). Reveal it and send it with the report."
    }
}
