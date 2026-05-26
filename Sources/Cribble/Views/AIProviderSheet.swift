import SwiftUI

struct AIProviderSheet: View {
    let onSelect: (AIProvider, AIMode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AIMode = .suggestLinks

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AI Link Notes")
                .font(.title2.weight(.semibold))

            Text("Choose what you want a local AI to do. Cribble runs it read-only and shows the unified diff before any file is changed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(AIMode.allCases) { option in
                    Button {
                        mode = option
                    } label: {
                        ModeRow(mode: option, isSelected: mode == option)
                    }
                    .buttonStyle(.plain)
                    .help(option.subtitle)
                }
            }

            Divider()

            Text("Provider")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(AIProvider.allCases) { provider in
                    Button {
                        onSelect(provider, mode)
                    } label: {
                        Label(provider.rawValue, systemImage: provider == .codex ? "terminal" : "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Run \(provider.rawValue) locally for: \(mode.title)")
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .help("Close without running")
            }
        }
        .padding(24)
        .frame(width: 460)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ModeRow: View {
    let mode: AIMode
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSelected ? .white : .blue)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Color.blue : Color.blue.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.custom("Roobert", size: 14))
                    .fontWeight(.semibold)
                Text(mode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.blue.opacity(0.10) : Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
