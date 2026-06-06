import AppKit
import SwiftUI
import Textual

/// The Intelligence HUD: a project-intelligence cockpit (design plan §10). Left
/// column is the live artifact tree + queue; the main area renders the selected
/// artifact (Markdown / embedded Mermaid) via the same `StructuredText` engine
/// the reader and chat use; the footer is a scoped "Ask about this project" bar.
struct IntelligenceHUDView: View {
    @ObservedObject var engine: IntelligenceEngine
    /// Resolves the project to operate on (the active library folder).
    let activeRootURL: () -> URL?
    let onClose: () -> Void
    /// Opens a project-relative source file (from a clicked diagram node).
    var onOpenSource: (String) -> Void = { _ in }
    /// All opened library folders, for the "All folders" scope (#1).
    var allRoots: () -> [URL] = { [] }
    /// Optional bridge from the Chat HUD so this panel can audit exactly what was
    /// sent as context during the latest chat turn.
    var latestContextReceipt: () -> ContextReceipt? = { nil }

    @State private var selectedTab: IntelligenceHUDTab = .feed
    @State private var selectedArtifactID: String?
    @State private var provenance: [ArtifactProvenance] = []
    @State private var askText = ""
    @State private var askAnswer: String?
    @State private var isAsking = false
    @State private var isEnabling = false
    @State private var showModelPicker = false
    @State private var zoomRequest: ZoomOverlayRequest?
    @State private var selectedGraphLens: IntelligenceGraphLens = .visual

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            if engine.isEnabled && !isViewingDifferentFolder {
                if engine.needsModelDownload || engine.modelDownloadFraction != nil {
                    modelBanner
                }
                tabControl
                tabContent
                statusFooter
            } else {
                enablePrompt
            }
        }
        .frame(minWidth: 380, minHeight: 520)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.28), Color.black.opacity(0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
        .overlay(alignment: .topTrailing) {
            if showModelPicker { modelPickerOverlay }
        }
        .overlay {
            if let request = zoomRequest {
                DiagramZoomOverlay(request: request, onClose: { zoomRequest = nil })
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text("Intelligence")
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if engine.isEnabled { scopeControl; modelButton }
            statusPill
            if engine.isEnabled {
                headerIcon("arrow.clockwise", help: "Run now") { Task { await engine.runNow() } }
                headerIcon("trash", help: "Clear cache & rebuild") { Task { await engine.clearCache() } }
            }
            headerIcon("xmark", help: "Close", action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        guard engine.isEnabled else { return activeRootURL()?.lastPathComponent ?? "No folder" }
        // Name comes from the engine's enabled project, not the sidebar selection,
        // so switching folders can't mislabel the active project.
        let name = engine.enabledProjectName ?? "Project"
        return "\(name) · \(engine.filesIndexed) files"
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            switch engine.status {
            case .off: return ("Off", .gray)
            case .ready: return ("Ready", .blue)
            case .scanning: return ("Scanning", .blue)
            case .working(let s): return (s, .orange)
            case .idle: return ("Idle", .green)
            case .driftDetected(let n): return ("Drift ×\(n)", .yellow)
            }
        }()
        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.22), in: Capsule())
            .overlay { Capsule().strokeBorder(color.opacity(0.5), lineWidth: 0.5) }
            .foregroundStyle(color)
    }

    /// Inline scope toggle (#1). Plain buttons (not a Menu) so they work even when
    /// the floating panel isn't the key window — a system Menu popup needs key.
    private var scopeControl: some View {
        HStack(spacing: 0) {
            scopeSegment(title: "Folder", icon: "folder", active: !engine.isAllFolders) {
                if let root = activeRootURL() { Task { await engine.enable(rootURL: root) } }
            }
            scopeSegment(title: "All (\(allRoots().count))", icon: "square.grid.2x2", active: engine.isAllFolders) {
                let roots = allRoots()
                if !roots.isEmpty { Task { await engine.enableAllFolders(roots: roots) } }
            }
        }
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5) }
        .help("Scan just this folder, or all opened folders")
    }

    private func scopeSegment(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(active ? 1 : 0.55))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(active ? Color.accentColor.opacity(0.5) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Inline model button: toggles an in-panel overlay list (not a system Menu),
    /// so it works regardless of key-window state. Freedom to use any local model.
    private var modelButton: some View {
        Button { showModelPicker.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: "cpu").font(.system(size: 9))
                Text(engine.activeModel?.shortName ?? "Model").font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 7))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Choose the model intelligence uses")
    }

    /// In-panel model picker (custom overlay, not NSMenu).
    private var modelPickerOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ON-DEVICE").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 8).padding(.top, 6)
            ForEach(ModelCatalog.localModels) { model in
                modelRow(model, detail: "\(ModelInventory.isDownloaded(model) ? "✓" : "⤓") \(model.approximateSize)")
            }
            Text("CLOUD CLI").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 8).padding(.top, 4)
            ForEach(ModelCatalog.cloudModels) { model in
                modelRow(model, detail: "CLI")
            }
        }
        .padding(.bottom, 6)
        .frame(width: 240)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.top, 44).padding(.trailing, 70)
    }

    private func modelRow(_ model: LocalModel, detail: String) -> some View {
        Button {
            showModelPicker = false
            Task { await engine.setModel(model) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: engine.settings.modelID == model.id ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 9)).foregroundStyle(engine.settings.modelID == model.id ? Color.accentColor : .white.opacity(0.4))
                Text(model.name).font(.system(size: 11))
                Spacer(minLength: 6)
                Text(detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
    }

    private func headerIcon(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Enable prompt

    private var enablePrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text(enablePromptTitle)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(enablePromptDetail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            HStack(spacing: 10) {
                Button {
                    guard let root = activeRootURL() else { return }
                    isEnabling = true
                    Task { await engine.enable(rootURL: root); isEnabling = false }
                } label: {
                    Text(isEnabling ? "Starting…" : "This folder")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(activeRootURL() == nil || isEnabling)

                Button {
                    let roots = allRoots()
                    guard !roots.isEmpty else { return }
                    isEnabling = true
                    Task { await engine.enableAllFolders(roots: roots); isEnabling = false }
                } label: {
                    Text("All folders (\(allRoots().count))")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(allRoots().isEmpty || isEnabling)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var enablePromptTitle: String {
        "Build local intelligence for\n\(activeRootURL()?.lastPathComponent ?? "this folder")?"
    }

    private var enablePromptDetail: String {
        if isViewingDifferentFolder, let enabled = engine.enabledProjectName {
            return "Intelligence is currently showing \(enabled). Start a separate local index for this selected folder, or switch back to \(enabled) in the sidebar."
        }
        return "Cribble scans the folder on-device and keeps a living set of summaries, diagrams, and audits — every claim links back to the source."
    }

    // MARK: - Model download banner

    private var modelBanner: some View {
        HStack(spacing: 10) {
            if let fraction = engine.modelDownloadFraction {
                if fraction <= 0.001 {
                    // 0% can sit a while during connect/metadata — show a spinner
                    // (not a frozen "0%") so it doesn't look stuck.
                    ProgressView().controlSize(.small)
                    Text("Preparing \(engine.activeModel?.name ?? "model")… this can take a moment")
                        .font(.system(size: 11))
                } else {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 160)
                    Text("Downloading \(engine.activeModel?.name ?? "model")… \(Int(fraction * 100))%")
                        .font(.system(size: 11))
                }
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 12))
                Text("Summaries need an on-device model.")
                    .font(.system(size: 11))
                Spacer(minLength: 0)
                Button("Download \(engine.activeModel?.name ?? "model") (\(engine.activeModel?.approximateSize ?? ""))") {
                    Task { await engine.downloadModelIfNeeded() }
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.85), in: Capsule())
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
    }

    // MARK: - Tabs

    private var tabControl: some View {
        Picker("Intelligence section", selection: $selectedTab) {
            ForEach(IntelligenceHUDTab.allCases) { tab in
                Label(tab.rawValue, systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.12))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .feed:
            feedTab
        case .graph:
            graphTab
        case .artifacts:
            artifactsTab
        case .ask:
            askTab
        case .context:
            contextTab
        }
    }

    // MARK: - Feed

    private var feedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    metricTile(title: "Files", value: "\(engine.filesIndexed)", icon: "doc.text.magnifyingglass")
                    metricTile(title: "Artifacts", value: "\(engine.artifacts.count)", icon: "square.stack.3d.up")
                    metricTile(title: "Insights", value: "\(activeResearchInsights.count)", icon: "sparkle.magnifyingglass")
                }

                if engine.staleCount > 0 {
                    Label("\(engine.staleCount) artifacts may be stale", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.9))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }

                if !activeResearchInsights.isEmpty || !suggestedEdges.isEmpty {
                    sectionHeader("RESEARCH")
                    ForEach(Array(activeResearchInsights.prefix(3))) { insight in
                        researchInsightRow(insight)
                    }
                    ForEach(Array(suggestedEdges.prefix(3))) { edge in
                        suggestedEdgeRow(edge)
                    }
                }

                sectionHeader("RECENT")
                if engine.artifacts.isEmpty {
                    emptyState(
                        icon: engine.pendingJobs > 0 ? "hourglass" : "sparkles",
                        title: engine.pendingJobs > 0 ? "Building intelligence..." : "Waiting for artifacts",
                        detail: "Generated summaries, diagrams, and audits will land here as the local engine works."
                    )
                } else {
                    ForEach(Array(engine.artifacts.prefix(6))) { artifact in
                        Button {
                            selectedArtifactID = artifact.id
                            selectedTab = .artifacts
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: artifact.type.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 18)
                                    .foregroundStyle(.white.opacity(0.66))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artifact.title ?? artifact.relativePath)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(artifact.type.rawValue.replacingOccurrences(of: "_", with: " "))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.44))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metricTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 20, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func researchInsightRow(_ insight: ResearchInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: insight.kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(.white.opacity(0.66))
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(insight.kind.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.44))
                }
                Spacer()
                Button {
                    Task { await engine.dismissInsight(insight) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.46))
                .help("Dismiss insight")
            }
            Text(insight.body)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(3)
            if let artifactID = insight.artifactID,
               engine.artifacts.contains(where: { $0.id == artifactID }) {
                Button {
                    selectedArtifactID = artifactID
                    selectedTab = .artifacts
                } label: {
                    Label("Open artifact", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.74))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func suggestedEdgeRow(_ edge: KnowledgeEdge) -> some View {
        let from = nodeTitle(edge.fromNodeID)
        let to = nodeTitle(edge.toNodeID)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(.white.opacity(0.66))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(from) -> \(to)")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(edge.kind.label + confidenceLabel(edge.confidence))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.44))
                }
                Spacer()
                Button {
                    Task { await engine.acceptSuggestedEdge(edge) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green.opacity(0.78))
                .help("Accept suggested relationship")
                Button {
                    Task { await engine.dismissSuggestedEdge(edge) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.46))
                .help("Dismiss suggested relationship")
            }
            if let path = pathForNode(edge.fromNodeID) ?? pathForNode(edge.toNodeID) {
                Button {
                    onOpenSource(path)
                } label: {
                    Label(path, systemImage: "arrow.up.right.square")
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.55))
                .help("Open source")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Graph

    private var graphTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                VStack(alignment: .leading, spacing: 1) {
                    Text(visibleGraphPayload.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(graphSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.46))
                }
                Spacer()
                Picker("Graph lens", selection: $selectedGraphLens) {
                    ForEach(IntelligenceGraphLens.allCases) { lens in
                        Label(lens.rawValue, systemImage: lens.icon).tag(lens)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Text("\(visibleGraphPayload.nodes.count) nodes")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            GraphViewport(payload: visibleGraphPayload, onOpenSource: onOpenSource)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Artifacts (tree + reader)

    private var artifactsTab: some View {
        HStack(spacing: 0) {
            artifactTree
                .frame(width: 190)
            Divider().overlay(Color.white.opacity(0.08))
            artifactReader
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var artifactTree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(groupedArtifacts, id: \.0) { group in
                    Text(group.0.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 8).padding(.horizontal, 10)
                    ForEach(group.1) { artifact in
                        artifactRow(artifact)
                    }
                }
                if engine.pendingJobs > 0 {
                    Text("QUEUE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 10).padding(.horizontal, 10)
                    Label("\(engine.pendingJobs) pending", systemImage: "circle.dotted")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                }
            }
            .padding(.bottom, 12)
        }
        .background(Color.black.opacity(0.15))
    }

    private func artifactRow(_ artifact: IntelligenceArtifact) -> some View {
        let selected = artifact.id == selectedArtifactID
        return Button {
            selectedArtifactID = artifact.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: artifact.type.icon)
                    .font(.system(size: 10))
                    .frame(width: 14)
                Text(artifact.title ?? artifact.relativePath)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if artifact.isPublished {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(.green.opacity(0.7))
                }
            }
            .foregroundStyle(.white.opacity(selected ? 1 : 0.75))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selected ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var artifactReader: some View {
        ScrollView {
            if let artifact = selectedArtifact, let body = engine.content(for: artifact) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(artifact.title ?? artifact.relativePath)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if !artifact.isPublished {
                            Button {
                                Task { await engine.publish(artifact) }
                            } label: {
                                Label("Save to folder", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.1), in: Capsule())
                            .help("Write this into .cribble/intelligence/ in your project folder so it lives alongside your code (otherwise it stays in Cribble's private cache).")
                        } else {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                    ArtifactBodyView(content: body, onOpenSource: onOpenSource, onExpand: { source in
                        zoomRequest = ZoomOverlayRequest(title: artifact.title ?? "Diagram", content: .mermaid(source: source))
                    })
                    if !provenance.isEmpty {
                        provenanceFooter
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    if engine.artifacts.isEmpty {
                        ProgressView().controlSize(.small)
                        Text(engine.pendingJobs > 0
                             ? "Building intelligence… \(engine.pendingJobs) job(s) queued."
                             : "Scanning \(engine.enabledProjectName ?? "project")…")
                        Text("Summaries and diagrams will appear here as they're generated.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    } else {
                        Image(systemName: "sidebar.left").font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
                        Text("Select an artifact from the left")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            }
        }
        .task(id: selectedArtifactID) {
            if let artifact = selectedArtifact {
                provenance = await engine.provenance(for: artifact)
            } else {
                provenance = []
            }
        }
    }

    private var provenanceFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Color.white.opacity(0.08))
            Text("SOURCES")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
            ForEach(Array(provenance.enumerated()), id: \.offset) { _, p in
                Text(provenanceLabel(p))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.top, 6)
    }

    private func provenanceLabel(_ p: ArtifactProvenance) -> String {
        var label = "↳ \(p.claimAnchor)"
        if let start = p.startLine {
            label += " @ line \(start)"
            if let end = p.endLine { label += "–\(end)" }
        }
        return label
    }

    // MARK: - Status footer

    private var statusFooter: some View {
        HStack(spacing: 6) {
            Text("\(engine.filesIndexed) files")
            Text("·")
            Text("\(engine.artifacts.count) artifacts")
            if engine.pendingJobs > 0 {
                Text("·")
                ProgressView().controlSize(.mini).scaleEffect(0.7)
                Text("\(engine.pendingJobs) processing")
            }
            if engine.staleCount > 0 {
                Text("·")
                Text("\(engine.staleCount) stale").foregroundStyle(.orange.opacity(0.8))
            }
            Spacer()
            if let activity = engine.lastActivity {
                Text(activity).lineLimit(1).truncationMode(.tail).foregroundStyle(.white.opacity(0.45))
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 14).padding(.vertical, 5)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Ask

    private var askTab: some View {
        VStack(spacing: 10) {
            if let answer = askAnswer {
                ScrollView {
                    StructuredText(markdown: answer)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            } else {
                emptyState(
                    icon: "questionmark.bubble",
                    title: "Ask about this project",
                    detail: "Answers use the generated intelligence artifacts as context and cite the artifacts they used."
                )
            }
            HStack(spacing: 8) {
                TextField("Ask about this project…", text: $askText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .onSubmit(ask)
                Button(action: ask) {
                    Image(systemName: isAsking ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(askText.isEmpty ? 0.3 : 0.9))
                }
                .buttonStyle(.plain)
                .disabled(askText.isEmpty || isAsking)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ask() {
        let question = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }
        isAsking = true
        Task {
            let answer = await engine.ask(question)
            askAnswer = answer ?? "No answer available — is a model configured?"
            isAsking = false
        }
    }

    // MARK: - Context

    private var contextTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("SCOPE")
                contextRow("Project", value: engine.enabledProjectName ?? activeRootURL()?.lastPathComponent ?? "No folder")
                contextRow("Mode", value: engine.isAllFolders ? "All folders" : "Active folder")
                contextRow("Indexed files", value: "\(engine.filesIndexed)")
                contextRow("Open folders", value: "\(allRoots().count)")
                contextRow("Knowledge nodes", value: "\(engine.knowledgeNodes.count)")
                contextRow("Knowledge edges", value: "\(engine.knowledgeEdges.count)")
                contextRow("Suggested edges", value: "\(suggestedEdges.count)")

                if !allRoots().isEmpty {
                    sectionHeader("FOLDERS")
                    ForEach(allRoots(), id: \.path) { root in
                        Label(root.lastPathComponent, systemImage: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .help(root.path)
                    }
                }

                sectionHeader("ARTIFACT GROUPS")
                ForEach(groupedArtifacts, id: \.0) { group in
                    contextRow(group.0, value: "\(group.1.count)")
                }

                if !provenance.isEmpty {
                    sectionHeader("SELECTED SOURCES")
                    ForEach(Array(provenance.enumerated()), id: \.offset) { _, p in
                        Text(provenanceLabel(p))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                if let receipt = latestContextReceipt(), !receipt.items.isEmpty {
                    sectionHeader("LAST CHAT CONTEXT")
                    ForEach(Array(receipt.items.enumerated()), id: \.offset) { _, item in
                        contextReceiptRow(item)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contextRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.48))
            Spacer()
            Text(value)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .padding(.vertical, 2)
    }

    private func contextReceiptRow(_ item: ContextReceipt.Item) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(item.filename)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(item.status.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(item.status.tint)
            }
            Text("\(item.source.rawValue) · \(item.includedCharacters)/\(item.originalCharacters) chars")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
            if let reason = item.reason {
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.38))
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.32))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Derived

    private var selectedArtifact: IntelligenceArtifact? {
        engine.artifacts.first { $0.id == selectedArtifactID }
    }

    private var isViewingDifferentFolder: Bool {
        guard engine.isEnabled, !engine.isAllFolders,
              let activePath = activeRootURL()?.standardizedFileURL.path,
              let enabledPath = engine.enabledRootPath
        else { return false }
        return activePath != enabledPath
    }

    private var activeResearchInsights: [ResearchInsight] {
        engine.researchInsights
            .filter { $0.status != .dismissed }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var suggestedEdges: [KnowledgeEdge] {
        engine.knowledgeEdges.filter { $0.status == .suggested }
    }

    private func nodeTitle(_ id: String) -> String {
        engine.knowledgeNodes.first { $0.id == id }?.title ?? id
    }

    private func pathForNode(_ id: String) -> String? {
        engine.knowledgeNodes.first { $0.id == id }?.path
    }

    private func confidenceLabel(_ confidence: Double?) -> String {
        guard let confidence else { return "" }
        return " · \(Int((confidence * 100).rounded()))%"
    }

    private var visibleGraphPayload: GraphPayload {
        let filteredEdges = graphEdges(for: selectedGraphLens)
        let filteredNodes = graphNodes(for: filteredEdges)
        let payload = GraphPayload.intelligence(
            projectName: engine.enabledProjectName,
            filesIndexed: engine.filesIndexed,
            knowledgeNodes: filteredNodes,
            knowledgeEdges: filteredEdges,
            artifacts: engine.artifacts,
            content: { engine.content(for: $0) }
        )
        return payload.pruned(maxNodes: selectedGraphLens.maxNodes, maxEdges: selectedGraphLens.maxEdges)
    }

    private var graphSubtitle: String {
        if visibleGraphPayload.isPlaceholder {
            return "Placeholder graph until intelligence builds relationships"
        }
        return selectedGraphLens.subtitle
    }

    private var graphPayload: GraphPayload {
        GraphPayload.intelligence(
            projectName: engine.enabledProjectName,
            filesIndexed: engine.filesIndexed,
            knowledgeNodes: engine.knowledgeNodes,
            knowledgeEdges: engine.knowledgeEdges,
            artifacts: engine.artifacts,
            content: { engine.content(for: $0) }
        )
    }

    private func graphEdges(for lens: IntelligenceGraphLens) -> [KnowledgeEdge] {
        let edges: [KnowledgeEdge]
        switch lens {
        case .visual:
            edges = engine.knowledgeEdges.filter { $0.status != .dismissed }
        case .trust:
            edges = engine.knowledgeEdges.filter { $0.status == .accepted }
        case .research:
            edges = engine.knowledgeEdges.filter { edge in
                edge.status != .dismissed
                    && (edge.status == .suggested
                        || edge.origin == .llmSuggested
                        || edge.kind == .semanticSimilarity
                        || edge.kind == .researchSupports
                        || edge.kind == .researchQuestion)
            }
        }
        return edges.sorted { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status.sortRank < rhs.status.sortRank }
            if lhs.origin != rhs.origin { return lhs.origin.sortRank < rhs.origin.sortRank }
            return (lhs.confidence ?? 0) > (rhs.confidence ?? 0)
        }
    }

    private func graphNodes(for edges: [KnowledgeEdge]) -> [KnowledgeNode] {
        guard !engine.knowledgeNodes.isEmpty else { return [] }
        guard !edges.isEmpty else {
            return Array(engine.knowledgeNodes.prefix(selectedGraphLens.maxNodes))
        }
        let endpointIDs = Set(edges.flatMap { [$0.fromNodeID, $0.toNodeID] })
        let degree = edges.reduce(into: [String: Int]()) { result, edge in
            result[edge.fromNodeID, default: 0] += 1
            result[edge.toNodeID, default: 0] += 1
        }
        return engine.knowledgeNodes
            .filter { endpointIDs.contains($0.id) }
            .sorted { lhs, rhs in
                degree[lhs.id, default: 0] == degree[rhs.id, default: 0]
                    ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                    : degree[lhs.id, default: 0] > degree[rhs.id, default: 0]
            }
    }

    /// Artifacts grouped into display sections, in a stable section order.
    private var groupedArtifacts: [(String, [IntelligenceArtifact])] {
        let order: [(String, [IntelligenceArtifactType])] = [
            ("Overview", [.projectIndex]),
            ("Connections", [.connectionsGraph]),
            ("Architecture", [.architectureDiagram, .dependencyDiagram]),
            ("Changes", [.diffSummary, .commitSummary]),
            ("Audits", [.fallbackAudit, .ioBehavior, .driftReport]),
            ("Research", [.researchInsight]),
            ("Files", [.fileSummary])
        ]
        return order.compactMap { section in
            let items = engine.artifacts.filter { section.1.contains($0.type) }
            return items.isEmpty ? nil : (section.0, items)
        }
    }
}

private enum IntelligenceGraphLens: String, CaseIterable, Identifiable {
    case visual = "Visual"
    case trust = "Trust"
    case research = "Research"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .visual: "circle.hexagongrid"
        case .trust: "checkmark.seal"
        case .research: "sparkle.magnifyingglass"
        }
    }

    var subtitle: String {
        switch self {
        case .visual: "Readable topology across accepted and suggested relationships"
        case .trust: "Accepted relationships only, best for source-grounded navigation"
        case .research: "Suggested and model-discovered relationships for review"
        }
    }

    var maxNodes: Int {
        switch self {
        case .visual: 90
        case .trust: 120
        case .research: 70
        }
    }

    var maxEdges: Int {
        switch self {
        case .visual: 140
        case .trust: 180
        case .research: 100
        }
    }
}

private extension ResearchInsight.Kind {
    var label: String {
        switch self {
        case .digest: "Digest"
        case .suggestedConnection: "Suggested connection"
        case .openQuestion: "Open question"
        case .topicBrief: "Topic brief"
        case .drift: "Drift"
        }
    }

    var icon: String {
        switch self {
        case .digest: "newspaper"
        case .suggestedConnection: "link.badge.plus"
        case .openQuestion: "questionmark.bubble"
        case .topicBrief: "rectangle.stack"
        case .drift: "exclamationmark.triangle"
        }
    }
}

private extension KnowledgeEdge.Kind {
    var label: String {
        switch self {
        case .wikiLink: "Wiki link"
        case .dependency: "Dependency"
        case .semanticSimilarity: "Semantic similarity"
        case .researchSupports: "Research support"
        case .researchQuestion: "Research question"
        }
    }
}

private extension KnowledgeEdge.Status {
    var sortRank: Int {
        switch self {
        case .accepted: 0
        case .suggested: 1
        case .dismissed: 2
        }
    }
}

private extension KnowledgeEdge.Origin {
    var sortRank: Int {
        switch self {
        case .deterministic: 0
        case .userAccepted: 1
        case .llmSuggested: 2
        case .web: 3
        }
    }
}

private extension ContextReceiptStatus {
    var tint: Color {
        switch self {
        case .included: .green.opacity(0.78)
        case .truncated: .yellow.opacity(0.8)
        case .summarized: .blue.opacity(0.82)
        case .omitted: .orange.opacity(0.8)
        case .blockedNeedsSummary, .unavailable: .red.opacity(0.78)
        }
    }
}

private enum IntelligenceHUDTab: String, CaseIterable, Identifiable {
    case feed = "Feed"
    case graph = "Graph"
    case artifacts = "Artifacts"
    case ask = "Ask"
    case context = "Context"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .feed: "list.bullet.rectangle"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .artifacts: "square.stack.3d.up"
        case .ask: "questionmark.bubble"
        case .context: "scope"
        }
    }
}

private extension IntelligenceArtifactType {
    var icon: String {
        switch self {
        case .projectIndex: "doc.text.magnifyingglass"
        case .connectionsGraph: "point.3.filled.connected.trianglepath.dotted"
        case .architectureDiagram, .dependencyDiagram: "point.3.connected.trianglepath.dotted"
        case .diffSummary, .commitSummary: "arrow.triangle.branch"
        case .fallbackAudit: "shield.lefthalf.filled"
        case .ioBehavior: "arrow.left.arrow.right"
        case .driftReport: "exclamationmark.triangle"
        case .fileSummary: "doc.text"
        case .researchInsight: "sparkle.magnifyingglass"
        }
    }
}
