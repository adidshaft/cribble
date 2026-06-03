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

    @State private var selectedArtifactID: String?
    @State private var provenance: [ArtifactProvenance] = []
    @State private var askText = ""
    @State private var askAnswer: String?
    @State private var isAsking = false
    @State private var isEnabling = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            if engine.isEnabled {
                if engine.needsModelDownload || engine.modelDownloadFraction != nil {
                    modelBanner
                }
                content
                askBar
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
        let name = activeRootURL()?.lastPathComponent ?? "No folder"
        guard engine.isEnabled else { return name }
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
            Text("Build local intelligence for\n\(activeRootURL()?.lastPathComponent ?? "this folder")?")
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Cribble scans the folder on-device and keeps a living set of summaries, diagrams, and audits — every claim links back to the source.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                guard let root = activeRootURL() else { return }
                isEnabling = true
                Task { await engine.enable(rootURL: root); isEnabling = false }
            } label: {
                Text(isEnabling ? "Starting…" : "Build Intelligence")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.9), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(activeRootURL() == nil || isEnabling)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Model download banner

    private var modelBanner: some View {
        HStack(spacing: 10) {
            if let fraction = engine.modelDownloadFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 160)
                Text("Downloading \(engine.activeModel?.name ?? "model")… \(Int(fraction * 100))%")
                    .font(.system(size: 11))
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

    // MARK: - Content (tree + reader)

    private var content: some View {
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
                            Button("Publish…") { Task { await engine.publish(artifact) } }
                                .font(.system(size: 10, weight: .semibold))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.white.opacity(0.1), in: Capsule())
                        }
                    }
                    ArtifactBodyView(content: body, onOpenSource: onOpenSource)
                    if !provenance.isEmpty {
                        provenanceFooter
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Select an artifact")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
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

    // MARK: - Ask bar

    private var askBar: some View {
        VStack(spacing: 6) {
            if let answer = askAnswer {
                ScrollView {
                    StructuredText(markdown: answer)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxHeight: 160)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
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
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
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

    // MARK: - Derived

    private var selectedArtifact: IntelligenceArtifact? {
        engine.artifacts.first { $0.id == selectedArtifactID }
    }

    /// Artifacts grouped into display sections, in a stable section order.
    private var groupedArtifacts: [(String, [IntelligenceArtifact])] {
        let order: [(String, [IntelligenceArtifactType])] = [
            ("Overview", [.projectIndex]),
            ("Architecture", [.architectureDiagram, .dependencyDiagram]),
            ("Changes", [.diffSummary, .commitSummary]),
            ("Audits", [.fallbackAudit, .ioBehavior, .driftReport]),
            ("Files", [.fileSummary])
        ]
        return order.compactMap { section in
            let items = engine.artifacts.filter { section.1.contains($0.type) }
            return items.isEmpty ? nil : (section.0, items)
        }
    }
}

private extension IntelligenceArtifactType {
    var icon: String {
        switch self {
        case .projectIndex: "doc.text.magnifyingglass"
        case .architectureDiagram, .dependencyDiagram: "point.3.connected.trianglepath.dotted"
        case .diffSummary, .commitSummary: "arrow.triangle.branch"
        case .fallbackAudit: "shield.lefthalf.filled"
        case .ioBehavior: "arrow.left.arrow.right"
        case .driftReport: "exclamationmark.triangle"
        case .fileSummary: "doc.text"
        }
    }
}
