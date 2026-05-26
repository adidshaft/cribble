import SwiftUI

struct DiffPreviewSheet: View {
    let diff: UnifiedDiff
    let applyError: String?
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Review AI Link Changes")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            if diff.isEmpty {
                ContentUnavailableView("No Suggested Changes", systemImage: "checkmark.circle")
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
                    .cribbleGlass(in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .help("Discard the suggested AI patch")
                Spacer()
                Button("Apply Changes", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(diff.isEmpty)
                    .cribbleGlassButton(prominent: true)
                    .help("Apply the reviewed Markdown link changes")
            }
        }
        .padding(22)
        .frame(width: 760, height: 560)
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct DiffFileView: View {
    let file: DiffFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.newPath)
                .font(.custom("Roobert", size: 14).weight(.semibold))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(file.hunks) { hunk in
                    Text(hunk.header)
                        .font(.custom("Monaco", size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)

                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        Text(prefix(for: line) + line.text)
                            .font(.custom("Monaco", size: 12))
                            .foregroundStyle(color(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 1)
                    }
                }
            }
            .padding(10)
            .cribbleGlass(in: RoundedRectangle(cornerRadius: 8))
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
