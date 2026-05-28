import SwiftUI

/// The Pathfinder HUD. Given two notes (dragged one onto the other), it shows:
///  1. the shortest wiki-link path between them, if one exists;
///  2. a local embedding "conceptual bridge" of stepping-stone notes;
///  3. an optional, on-demand Claude/Codex explanation of the relationship;
/// and offers to write a wiki link between them via the safe diff preview.
struct PathfinderSheet: View {
    let request: PathfinderRequest

    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var semanticIndex: SemanticSearchIndex
    @Environment(\.dismiss) private var dismiss

    @State private var wikiPath: [URL]?
    @State private var bridge: [SemanticHit] = []
    @State private var computed = false

    @State private var cliExplanation: String?
    @State private var cliError: String?
    @State private var isExplaining = false

    private var sourceTitle: String { library.title(for: request.source) }
    private var targetTitle: String { library.title(for: request.target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    endpoints
                    wikiPathSection
                    bridgeSection
                    explanationSection
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .task {
            guard !computed else { return }
            computed = true
            wikiPath = library.wikiLinkPath(from: request.source, to: request.target)
            bridge = semanticIndex.bridge(from: request.source, to: request.target)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .foregroundStyle(.tint)
            Text("Pathfinder")
                .font(.system(size: 15, design: .rounded))
                .fontWeight(.semibold)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(7)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var endpoints: some View {
        HStack(spacing: 10) {
            noteChip(sourceTitle, system: "doc.text.fill")
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            noteChip(targetTitle, system: "doc.text")
        }
    }

    @ViewBuilder
    private var wikiPathSection: some View {
        sectionHeader("Wiki-link path", system: "link")
        if let wikiPath, wikiPath.count >= 2 {
            if wikiPath.count == 2 {
                Label("These notes are directly linked.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            } else {
                chain(titles: wikiPath.map { library.title(for: $0) }, connector: "link", tint: .primary)
                Text("\(wikiPath.count - 1) hops through your existing links.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No path of existing wiki links connects these notes.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var bridgeSection: some View {
        sectionHeader("Conceptual bridge", system: "sparkles")
        if bridge.isEmpty {
            Text(semanticIndex.isReady
                 ? "No stepping stones needed — these notes relate directly in meaning."
                 : "Semantic index isn’t ready yet.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            chain(
                titles: [sourceTitle] + bridge.map(\.title) + [targetTitle],
                connector: "arrow.right",
                tint: .accentColor
            )
            Text("Bridged locally via on-device embeddings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var explanationSection: some View {
        sectionHeader("Explain the connection", system: "wand.and.stars")

        if let cliExplanation {
            Text(cliExplanation)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }

        if let cliError {
            Text(cliError)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack(spacing: 10) {
            if isExplaining {
                ProgressView().controlSize(.small)
                Text("Reasoning locally with the CLI…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(AIProvider.allCases) { provider in
                        Button(provider.rawValue) { explain(with: provider) }
                    }
                } label: {
                    Label(cliExplanation == nil ? "Explain with Claude / Codex" : "Re-run explanation", systemImage: "sparkle")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Spawn the local Claude or Codex CLI (read-only) to explain how these notes connect")
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                let source = request.source
                let target = request.target
                dismiss()
                // Let the HUD dismiss before the diff sheet takes its place.
                DispatchQueue.main.async {
                    library.presentLinkProposal(from: source, to: target)
                }
            } label: {
                Label("Link these notes", systemImage: "link.badge.plus")
            }
            .cribbleGlassButton(prominent: true)
            .help("Add a [[wiki link]] from \(sourceTitle) to \(targetTitle) (with a diff preview)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    // MARK: - Building blocks

    private func sectionHeader(_ title: String, system: String) -> some View {
        Label(title, systemImage: system)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func noteChip(_ title: String, system: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.05), in: Capsule())
    }

    @ViewBuilder
    private func chain(titles: [String], connector: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 8) {
                    Image(systemName: index == 0 ? "circle.fill" : connector)
                        .font(.system(size: index == 0 ? 7 : 10, weight: .semibold))
                        .foregroundStyle(index == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                        .frame(width: 16)
                    Text(title)
                        .font(.system(size: 12, weight: index == 0 || index == titles.count - 1 ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.leading, 2)
    }

    // MARK: - CLI

    private func explain(with provider: AIProvider) {
        guard let folder = library.rootURL(for: request.source) else {
            cliError = "Open a folder first."
            return
        }
        cliError = nil
        isExplaining = true
        let source = sourceTitle
        let target = targetTitle

        Task {
            defer { isExplaining = false }
            do {
                let text = try await AIService().explainRelationship(
                    provider: provider,
                    sourceTitle: source,
                    targetTitle: target,
                    folderURL: folder
                )
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                cliExplanation = trimmed.isEmpty ? "The CLI returned no explanation." : trimmed
            } catch {
                cliError = error.localizedDescription
            }
        }
    }
}
