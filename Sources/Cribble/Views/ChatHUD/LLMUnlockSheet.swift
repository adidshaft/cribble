import SwiftUI

/// Shown when a user on the App Store build opens the Local Chat HUD without
/// having purchased the unlock. Never shown on the direct DMG build (which ships
/// unlocked).
struct LLMUnlockSheet: View {
    @ObservedObject var entitlement: LLMEntitlementStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Unlock Local AI")
                    .font(.title2.weight(.semibold))
            }

            Text("Run a private AI assistant fully on your Mac — no cloud, no account. Tag notes with @, ask questions, and get safe, reviewable edits. One-time purchase.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "lock.shield", text: "100% on-device — your notes never leave your Mac")
                FeatureRow(icon: "at", text: "Tag notes with @ to give the model context")
                FeatureRow(icon: "checkmark.seal", text: "Every change is previewed as a diff before it's written")
            }

            if let error = entitlement.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Restore Purchase") {
                    Task { await entitlement.restore() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Not Now") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        await entitlement.purchase()
                        if entitlement.isUnlocked { dismiss() }
                    }
                } label: {
                    if entitlement.purchaseInFlight {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Unlock · \(entitlement.displayPrice)")
                    }
                }
                .controlSize(.large)
                .cribbleGlassButton(prominent: true)
                .disabled(entitlement.purchaseInFlight)
            }
        }
        .padding(24)
        .frame(width: 460)
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
