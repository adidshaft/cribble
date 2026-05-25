import SwiftUI

struct AIProviderSheet: View {
    let onSelect: (AIProvider) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AI Link Notes")
                .font(.title2.weight(.semibold))

            Text("Choose a local terminal AI. Cribble asks it for a read-only unified diff and shows a preview before any file changes are applied.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ForEach(AIProvider.allCases) { provider in
                    Button {
                        onSelect(provider)
                    } label: {
                        Label(provider.rawValue, systemImage: provider == .codex ? "terminal" : "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
