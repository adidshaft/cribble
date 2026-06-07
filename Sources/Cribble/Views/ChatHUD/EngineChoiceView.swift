import SwiftUI

/// First-run engine chooser shown over the empty state the first time the Chat
/// HUD opens. Cribble is local-first, so the on-device option is presented first
/// and recommended; cloud CLI providers are offered for users who prefer them or
/// whose build can't run MLX.
struct EngineChoiceView: View {
    @ObservedObject var viewModel: ChatHUDViewModel

    private var onDevice: LocalModel? { ModelCatalog.recommendedOnDevice }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Choose how Cribble AI runs")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("You can switch anytime from the model menu.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            VStack(spacing: 10) {
                if let onDevice {
                    EngineOptionCard(
                        title: "On your Mac",
                        subtitle: ModelCatalog.isOnDeviceAvailable
                            ? "Private — nothing leaves your device. Downloads \(onDevice.name) (\(onDevice.approximateSize)) the first time."
                            : "Not available in this build of Cribble.",
                        boundary: onDevice.dataBoundaryLabel,
                        systemImage: "desktopcomputer",
                        badge: "Recommended",
                        isEnabled: ModelCatalog.isOnDeviceAvailable
                    ) {
                        viewModel.chooseEngine(onDevice)
                    }
                }

                ForEach(ModelCatalog.cloudModels) { model in
                    EngineOptionCard(
                        title: "\(model.name) (cloud)",
                        subtitle: model.blurb,
                        boundary: model.dataBoundaryLabel,
                        systemImage: "cloud",
                        badge: nil,
                        isEnabled: true
                    ) {
                        viewModel.chooseEngine(model)
                    }
                }
            }
            .frame(maxWidth: 280)
        }
        .padding(20)
    }
}

private struct EngineOptionCard: View {
    let title: String
    let subtitle: String
    let boundary: String
    let systemImage: String
    let badge: String?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.85), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(boundary, systemImage: "lock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.4))
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .cribbleGlassCapsuleButton()
        .pointingHandOnHover()
    }
}
