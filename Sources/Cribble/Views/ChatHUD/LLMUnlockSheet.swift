import SwiftUI

/// Shown when a user on the App Store build opens the Local Chat HUD without
/// having purchased the unlock. Never shown on the direct DMG build (which ships
/// unlocked).
struct LLMUnlockSheet: View {
    @ObservedObject var entitlement: LLMEntitlementStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .center, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, height: 56)
                    .background(.primary.opacity(0.06), in: Circle())

                VStack(spacing: 6) {
                    Text("Unlock Local AI")
                        .font(.system(size: 22, weight: .bold))

                    Text("Run a private AI assistant fully on your Mac — no cloud, no account. Tag notes with @, ask questions, and get safe, reviewable edits.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

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

            HStack(spacing: 12) {
                Button {
                    Task { await entitlement.restore() }
                } label: {
                    Label("Restore Purchase", systemImage: "arrow.clockwise")
                }
                .controlSize(.regular)
                .help("Restore an existing App Store purchase")

                Spacer()

                Button("Not Now") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)

                Button {
                    Task {
                        await entitlement.purchase()
                        if entitlement.isUnlocked { dismiss() }
                    }
                } label: {
                    HStack {
                        if entitlement.purchaseInFlight {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Unlock · \(entitlement.displayPrice)")
                        }
                    }
                }
                .cribbleGlassButton(prominent: true)
                .disabled(entitlement.purchaseInFlight)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 460)
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.primary.opacity(0.05), lineWidth: 0.5)
        }
    }
}
