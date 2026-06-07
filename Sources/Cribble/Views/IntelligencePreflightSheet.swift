import SwiftUI

enum IntelligencePreflightScope: Identifiable {
    case folder
    case allFolders

    var id: String {
        switch self {
        case .folder: "folder"
        case .allFolders: "all-folders"
        }
    }

    var title: String {
        switch self {
        case .folder: "This Folder"
        case .allFolders: "All Open Folders"
        }
    }
}

struct IntelligencePreflightSheet: View {
    let scope: IntelligencePreflightScope
    let roots: [URL]
    let runnerSummary: IntelligencePreflightRunnerSummary
    let performanceMode: PerformanceMode
    let onCancel: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Project Intelligence")
                        .font(.system(size: 18, weight: .semibold))
                    Text(scope.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                preflightRow(
                    icon: "folder",
                    title: "\(roots.count) folder\(roots.count == 1 ? "" : "s")",
                    detail: roots.map(\.lastPathComponent).joined(separator: ", ")
                )
                preflightRow(
                    icon: runnerSummary.icon,
                    title: runnerSummary.title,
                    detail: runnerSummary.detail
                )
                preflightRow(
                    icon: "internaldrive",
                    title: "Disk budget",
                    detail: "Generated artifacts and cache entries follow the Intelligence disk budget in Settings."
                )
                preflightRow(
                    icon: "battery.75",
                    title: "Performance",
                    detail: "\(performanceMode.title): \(performanceMode.subtitle)"
                )
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start", action: onStart)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func preflightRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail.isEmpty ? "No folder selected." : detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct IntelligencePreflightRunnerSummary: Equatable {
    let isRemote: Bool
    let icon: String
    let title: String
    let detail: String

    static func current(
        runnerURL: String?,
        modelID: String,
        onDeviceModelLabel: String,
        extensionProfiles: [ExtensionIntelligenceProviderProfile]
    ) -> IntelligencePreflightRunnerSummary {
        guard let runnerURL,
              let url = URL(string: runnerURL),
              let host = url.host?.lowercased()
        else {
            return IntelligencePreflightRunnerSummary(
                isRemote: false,
                icon: "lock.laptopcomputer",
                title: "Local processing",
                detail: "Cribble scans locally with \(onDeviceModelLabel) and stores its index in its app support cache."
            )
        }

        let profile = ExtensionIntelligenceProviderProfile.matching(
            runnerURL: runnerURL,
            modelID: modelID,
            profiles: extensionProfiles
        )
        let isRemote = !Self.isLoopback(host)
        if isRemote {
            let trust = profile?.trustLabel ?? profile?.sourceName ?? "Custom runner"
            return IntelligencePreflightRunnerSummary(
                isRemote: true,
                icon: "network.badge.shield.half.filled",
                title: "Remote runner selected",
                detail: "Endpoint: \(host). Model: \(modelID). Trust: \(trust). Prompts and note context may leave this Mac."
            )
        }

        let label = profile?.title ?? "Local runner"
        return IntelligencePreflightRunnerSummary(
            isRemote: false,
            icon: "lock.laptopcomputer",
            title: label,
            detail: "Endpoint: \(host). Model: \(modelID). Cribble keeps processing on this Mac or local network endpoint."
        )
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
    }
}

struct ExtensionRunnerConsentSheet: View {
    let profile: ExtensionIntelligenceProviderProfile
    let usesKeychain: Bool
    let onCancel: () -> Void
    let onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Remote Runner")
                        .font(.system(size: 18, weight: .semibold))
                    Text(profile.sourceName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                consentRow(
                    icon: "server.rack",
                    title: profile.title,
                    detail: profile.baseURL.absoluteString
                )
                consentRow(
                    icon: "cpu",
                    title: "Model",
                    detail: profile.modelID
                )
                consentRow(
                    icon: "checkmark.seal",
                    title: "Trust label",
                    detail: profile.trustLabel
                )
                consentRow(
                    icon: "exclamationmark.triangle",
                    title: "Context boundary",
                    detail: "Prompts and note context may leave this Mac when Project Intelligence uses this runner."
                )
                consentRow(
                    icon: usesKeychain ? "key.fill" : "key",
                    title: "API key",
                    detail: usesKeychain ? "Cribble will use the saved Keychain credential for this endpoint." : "No Keychain credential is selected for this endpoint."
                )
                consentRow(
                    icon: "switch.2",
                    title: "Disable path",
                    detail: "Choose a different runner or disable the extension in Settings."
                )
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use Runner", action: onApprove)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private func consentRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
