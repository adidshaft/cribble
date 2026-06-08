import AppKit
import SwiftUI

struct DiffPreviewSheet: View {
    let diff: UnifiedDiff
    let applyError: String?
    let onApply: () -> Void
    let onCancel: () -> Void
    @State private var copiedDiff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.weight(.semibold))

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if diff.isEmpty {
                ContentUnavailableView(
                    "No Suggested Changes",
                    systemImage: "checkmark.circle",
                    description: Text("Cribble did not receive a safe patch to review. Nothing has been written; close this sheet or try again with more focused note context.")
                )
                    .frame(minHeight: 220)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(diff.files) { file in
                            DiffFileView(file: file)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 320)
            }

            if let applyError {
                Label(applyError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .help(cancelHelp)
                Button {
                    copyDiff()
                } label: {
                    Label(copiedDiff ? "Copied Diff" : "Copy Diff", systemImage: copiedDiff ? "checkmark" : "doc.on.doc")
                }
                .disabled(diff.isEmpty)
                .help("Copy the proposed patch for issue, PR, or teammate review before applying")
                Spacer()
                Button(applyTitle, action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(diff.isEmpty)
                    .cribbleGlassButton(prominent: true)
                    .help(applyHelp)
            }
        }
        .padding(22)
        .frame(width: 760, height: 560)
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 18))
    }

    private var isNewFileProposal: Bool {
        !diff.files.isEmpty && diff.files.allSatisfy { $0.oldPath == "/dev/null" }
    }

    private var title: String {
        isNewFileProposal ? "Review New Note" : "Review AI Link Changes"
    }

    private var applyTitle: String {
        isNewFileProposal ? "Create Note" : "Apply Changes"
    }

    private var applyHelp: String {
        isNewFileProposal ? "Create the reviewed Markdown note" : "Apply the reviewed Markdown link changes"
    }

    private var cancelHelp: String {
        isNewFileProposal ? "Discard the proposed note" : "Discard the suggested AI patch"
    }

    private var subtitle: String? {
        if isNewFileProposal, let fileName = diff.files.first?.newPath {
            return diff.files.count == 1 ? "Creates \(fileName)" : "Creates \(diff.files.count) new notes"
        }
        guard diff.files.count > 1 else { return nil }
        return "Updates \(diff.files.count) files"
    }

    private func copyDiff() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UnifiedDiffRenderer.render(diff), forType: .string)
        copiedDiff = true
    }
}

private struct DiffFileView: View {
    let file: DiffFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.newPath)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(file.hunks) { hunk in
                    Text(hunk.header)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)

                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        Text(prefix(for: line) + line.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 1)
                    }
                }
            }
            .padding(10)
            .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func prefix(for line: DiffLine) -> String {
        switch line.kind {
        case .context: "  "
        case .addition: "+ "
        case .removal: "- "
        }
    }

    private func color(for line: DiffLine) -> Color {
        switch line.kind {
        case .context: .primary
        case .addition: .green
        case .removal: .red
        }
    }
}
