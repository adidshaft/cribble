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
    let usesRemoteRunner: Bool
    let modelLabel: String
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
                    icon: usesRemoteRunner ? "network.badge.shield.half.filled" : "lock.laptopcomputer",
                    title: usesRemoteRunner ? "Remote runner selected" : "Local processing",
                    detail: usesRemoteRunner
                        ? "Prompts and note context may leave this Mac for \(modelLabel). Use only trusted endpoints."
                        : "Cribble scans locally and stores its index in its app support cache."
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
