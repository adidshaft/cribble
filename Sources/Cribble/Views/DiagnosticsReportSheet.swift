import AppKit
import SwiftUI

struct DiagnosticsReportSheet: View {
    let report: String
    let onCopy: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diagnostic Report")
                        .font(.title2.weight(.semibold))
                    Text("Copy this report when Cribble crashes, gets stuck, or behaves strangely.")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ScrollView {
                Text(report)
                    .font(.custom("Monaco", size: 12))
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
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

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
}
