import SwiftUI

/// Shown when a user on the App Store build opens the Local Chat HUD without
/// having purchased the unlock. Never shown on the direct DMG build (which ships
/// unlocked).
struct LLMUnlockSheet: View {
    @ObservedObject var entitlement: LLMEntitlementStore
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchaseHovered = false
    @State private var isNotNowHovered = false
    @State private var isRestoreHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Centered Header
            VStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 56, height: 56)
                        .blur(radius: 8)

                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.4), radius: 6)
                }

                VStack(spacing: 6) {
                    Text("Unlock Local AI")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Run a private AI assistant fully on your Mac — no cloud, no account. Tag notes with @, ask questions, and get safe, reviewable edits.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            // Features Card Section
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

            // Footer Actions
            HStack(spacing: 12) {
                Button {
                    Task { await entitlement.restore() }
                } label: {
                    Text("Restore Purchase")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(isRestoreHovered ? 0.9 : 0.5))
                        .underline(isRestoreHovered)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isRestoreHovered = hovering
                }
                .pointingHandOnHover()

                Spacer()

                Button("Not Now") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(isNotNowHovered ? 0.9 : 0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(isNotNowHovered ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                    }
                    .onHover { hovering in
                        isNotNowHovered = hovering
                    }
                    .pointingHandOnHover()

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
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(height: 32)
                    .padding(.horizontal, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: Color.blue.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(entitlement.purchaseInFlight)
                .scaleEffect(isPurchaseHovered ? 1.03 : 1.0)
                .onHover { hovering in
                    isPurchaseHovered = hovering
                }
                .pointingHandOnHover()
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 460)
        .background(
            RadialGradient(
                colors: [Color.blue.opacity(0.12), Color.clear],
                center: .top,
                startRadius: 0,
                endRadius: 320
            )
        )
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 18))
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
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
        }
    }
}
