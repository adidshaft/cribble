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
    /// OpenAI-compatible runner profiles contributed by enabled extensions.
    var extensionProviderProfiles: () -> [ExtensionIntelligenceProviderProfile] = { [] }

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
    @State private var showLocalRunnerConfig = false
    @State private var localRunnerName = OpenAICompatibleProvider.knownLocalEndpoints.first?.name ?? "Local Runner"
    @State private var localRunnerBaseURL = OpenAICompatibleProvider.knownLocalEndpoints.first?.url.absoluteString ?? ""
    @State private var localRunnerModelID = ""
    @State private var localRunnerModelIDs: [String] = []
    @State private var localRunnerStatus: LocalRunnerProbeStatus?
    @State private var isProbingLocalRunner = false
    @State private var localRunnerRequiresProbe = true
    @State private var localRunnerAPIKey = ""
    @State private var localRunnerUsesKeychain = false
    @State private var selectedExtensionProviderProfile: ExtensionIntelligenceProviderProfile?
    @State private var pendingExtensionRunnerConsent: ExtensionIntelligenceProviderProfile?
    @State private var pendingPreflightScope: IntelligencePreflightScope?
    private let extensionRunnerConsentStore = ExtensionRunnerConsentStore()

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
        .cribbleInteractiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cribbleGlassContainer()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if showModelPicker { modelPickerOverlay }
        }
        .sheet(item: $pendingPreflightScope) { scope in
            IntelligencePreflightSheet(
                scope: scope,
                roots: roots(for: scope),
                runnerSummary: preflightRunnerSummary,
                performanceMode: engine.settings.performanceMode,
                onCancel: { pendingPreflightScope = nil },
                onStart: {
                    pendingPreflightScope = nil
                    startIntelligence(scope)
                }
            )
        }
        .sheet(item: $pendingExtensionRunnerConsent) { profile in
            ExtensionRunnerConsentSheet(
                profile: profile,
                usesKeychain: localRunnerUsesKeychain,
                onCancel: { pendingExtensionRunnerConsent = nil },
                onApprove: {
                    extensionRunnerConsentStore.approve(profile)
                    pendingExtensionRunnerConsent = nil
                    Task { await applyLocalRunner() }
                }
            )
        }
        .overlay {
            if let request = zoomRequest {
                DiagramZoomOverlay(request: request, onClose: { zoomRequest = nil })
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
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
            headerControlCluster
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var headerControlCluster: some View {
        headerControlContent
    }

    private var headerControlContent: some View {
        HStack(spacing: 8) {
            if engine.isEnabled {
                scopeControl
                modelButton
            }
            statusPill
            if engine.isEnabled {
                headerIcon("arrow.clockwise", help: "Run now") { Task { await engine.runNow() } }
                headerIcon("trash", help: "Clear cache & rebuild") { Task { await engine.clearCache() } }
            }
            headerIcon("xmark", help: "Close", action: onClose)
        }
        .cribbleGlassContainer()
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
            case .working(let s): return (engine.currentJobDescription ?? s, .orange)
            case .idle: return ("Idle", .green)
            case .driftDetected(let n): return ("Drift ×\(n)", .yellow)
            }
        }()
        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    /// Inline scope toggle (#1). Plain buttons (not a Menu) so they work even when
    /// the floating panel isn't the key window — a system Menu popup needs key.
    private var scopeControl: some View {
        HStack(spacing: 4) {
            scopeSegment(title: "Folder", icon: "folder", active: !engine.isAllFolders) {
                if let root = activeRootURL() { Task { await engine.enable(rootURL: root) } }
            }
            scopeSegment(title: "All (\(allRoots().count))", icon: "square.grid.2x2", active: engine.isAllFolders) {
                let roots = allRoots()
                if !roots.isEmpty { Task { await engine.enableAllFolders(roots: roots) } }
            }
        }
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
        }
        .cribbleGlassCapsuleButton(prominent: active)
    }

    /// Inline model button: toggles an in-panel overlay list (not a system Menu),
    /// so it works regardless of key-window state. Freedom to use any local model.
    private var modelButton: some View {
        Button { showModelPicker.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: "cpu").font(.system(size: 9))
                Text(activeModelLabel).font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 7))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 8).padding(.vertical, 3)
        }
        .cribbleGlassCapsuleButton()
        .help("Choose the model intelligence uses")
    }

    /// In-panel model picker (custom overlay, not NSMenu).
    private var modelPickerOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ON-DEVICE").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 8).padding(.top, 6)
            ForEach(ModelCatalog.localModels) { model in
                modelRow(model, detail: "\(ModelInventory.isDownloaded(model) ? "✓" : "⤓") \(model.approximateSize)")
            }
            Text("LOCAL RUNNER").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 8).padding(.top, 4)
            ForEach(OpenAICompatibleProvider.knownLocalEndpoints, id: \.name) { endpoint in
                localRunnerRow(name: endpoint.name, url: endpoint.url)
            }
            let profiles = extensionProviderProfiles()
            if !profiles.isEmpty {
                Text("EXTENSIONS").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 8).padding(.top, 4)
                ForEach(profiles) { profile in
                    extensionProviderRow(profile)
                }
            }
            Button {
                configureLocalRunner(name: "Custom", baseURL: localRunnerBaseURL.isEmpty ? "http://127.0.0.1:11434/v1" : localRunnerBaseURL)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCustomLocalRunnerSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 9))
                        .foregroundStyle(isCustomLocalRunnerSelected ? Color.accentColor : .white.opacity(0.4))
                    Text("Custom...").font(.system(size: 11))
                    Spacer(minLength: 6)
                    Text("OpenAI-compatible").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
            if showLocalRunnerConfig {
                localRunnerConfig
            }
            Text("CLOUD CLI").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 8).padding(.top, 4)
            ForEach(ModelCatalog.cloudModels) { model in
                modelRow(model, detail: "CLI")
            }
            Divider().padding(.vertical, 3)
            Text("PERFORMANCE").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 8)
            ForEach(PerformanceMode.allCases) { mode in
                performanceModeRow(mode)
            }
        }
        .padding(.bottom, 6)
        .frame(width: 320)
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 14), strokeOpacity: 0.10)
        .padding(.top, 44).padding(.trailing, 70)
    }

    private func performanceModeRow(_ mode: PerformanceMode) -> some View {
        Button {
            engine.setPerformanceMode(mode)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: engine.settings.performanceMode == mode ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(engine.settings.performanceMode == mode ? Color.accentColor : .white.opacity(0.4))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title).font(.system(size: 11))
                    Text(mode.subtitle).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
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

    private func localRunnerRow(name: String, url: URL) -> some View {
        Button {
            configureLocalRunner(name: name, baseURL: url.absoluteString)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelectedRunner(url.absoluteString) ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelectedRunner(url.absoluteString) ? Color.accentColor : .white.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 11))
                    Text(url.absoluteString).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "network")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
    }

    private func extensionProviderRow(_ profile: ExtensionIntelligenceProviderProfile) -> some View {
        Button {
            configureExtensionProvider(profile)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelectedRunner(profile.baseURL.absoluteString) ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelectedRunner(profile.baseURL.absoluteString) ? Color.accentColor : .white.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.title).font(.system(size: 11))
                    Text("\(profile.modelID) · \(profile.privacyLabel)")
                        .font(.system(size: 9))
                        .foregroundStyle(profile.isLoopback ? .white.opacity(0.45) : Color.orange.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: profile.isLoopback ? "network" : "exclamationmark.triangle")
                    .font(.system(size: 9))
                    .foregroundStyle(profile.isLoopback ? .white.opacity(0.45) : Color.orange.opacity(0.85))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
        .help(profile.isLoopback ? "Uses \(profile.trustLabel)" : RemoteRunnerDataBoundary.detail)
    }

    private var localRunnerConfig: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(localRunnerName)
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                if isProbingLocalRunner {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                }
            }
            TextField("Base URL", text: $localRunnerBaseURL)
                .font(.system(size: 10))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            if localRunnerModelIDs.isEmpty {
                TextField("Model ID", text: $localRunnerModelID)
                    .font(.system(size: 10))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Menu {
                    ForEach(localRunnerModelIDs, id: \.self) { modelID in
                        Button(modelID) { localRunnerModelID = modelID }
                    }
                } label: {
                    HStack {
                        Text(localRunnerModelID.isEmpty ? "Choose model" : localRunnerModelID)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)
                .cribbleGlassCapsuleButton()
            }
            if let localRunnerStatus {
                Text(localRunnerStatus.message)
                    .font(.system(size: 9))
                    .foregroundStyle(localRunnerStatus.isError ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                    .lineLimit(2)
            }
            if let selectedExtensionProviderProfile {
                ExtensionRunnerHandoffStrip(
                    profile: selectedExtensionProviderProfile,
                    onCopy: { copyRunnerHandoff(selectedExtensionProviderProfile) }
                )
            } else if let remoteRunnerHandoff {
                CustomRunnerHandoffStrip(
                    handoff: remoteRunnerHandoff,
                    onCopy: { copyCustomRunnerHandoff(remoteRunnerHandoff) }
                )
            }
            SecureField("API key (optional)", text: $localRunnerAPIKey)
                .font(.system(size: 10))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            Toggle("Store API key in Keychain", isOn: $localRunnerUsesKeychain)
                .font(.system(size: 10))
                .toggleStyle(.checkbox)
                .foregroundStyle(.white.opacity(0.72))
            if let warning = localRunnerPrivacyWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Test") {
                    Task { _ = await probeLocalRunner() }
                }
                .disabled(isProbingLocalRunner)
                .cribbleGlassCapsuleButton()
                Button("Use") {
                    Task { await useLocalRunner() }
                }
                .disabled(!canUseLocalRunner || isProbingLocalRunner)
                .cribbleGlassCapsuleButton(prominent: true)
                Spacer()
            }
            .font(.system(size: 10, weight: .semibold))
            .cribbleGlassContainer()
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func configureLocalRunner(name: String, baseURL: String) {
        localRunnerName = name
        localRunnerBaseURL = baseURL
        localRunnerModelID = ""
        localRunnerStatus = nil
        localRunnerModelIDs = []
        localRunnerRequiresProbe = true
        localRunnerAPIKey = ""
        localRunnerUsesKeychain = engine.settings.runnerUsesKeychain(baseURL: baseURL)
        selectedExtensionProviderProfile = nil
        showLocalRunnerConfig = true
        Task { _ = await probeLocalRunner() }
    }

    private func configureExtensionProvider(_ profile: ExtensionIntelligenceProviderProfile) {
        localRunnerName = profile.title
        localRunnerBaseURL = profile.baseURL.absoluteString
        localRunnerModelID = profile.modelID
        localRunnerModelIDs = [profile.modelID]
        localRunnerStatus = .ready(profile.isLoopback ? "Extension profile from \(profile.sourceName)." : "Remote profile from \(profile.sourceName).")
        localRunnerRequiresProbe = false
        localRunnerAPIKey = ""
        localRunnerUsesKeychain = engine.settings.runnerUsesKeychain(baseURL: profile.baseURL.absoluteString)
        selectedExtensionProviderProfile = profile
        showLocalRunnerConfig = true
    }

    private func copyRunnerHandoff(_ profile: ExtensionIntelligenceProviderProfile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(profile.handoffSummary, forType: .string)
        localRunnerStatus = .ready("Copied runner handoff details.")
    }

    private func copyCustomRunnerHandoff(_ handoff: CustomRunnerHandoff) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(handoff.summary, forType: .string)
        localRunnerStatus = .ready("Copied custom runner checklist.")
    }

    @MainActor
    @discardableResult
    private func probeLocalRunner() async -> Bool {
        let trimmedURL = localRunnerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
            localRunnerStatus = .failed("Enter a valid base URL.")
            return false
        }

        isProbingLocalRunner = true
        defer { isProbingLocalRunner = false }
        do {
            let models = try await OpenAICompatibleProvider.availableModelIDs(baseURL: url)
            localRunnerModelIDs = models
            if localRunnerModelID.isEmpty || !models.contains(localRunnerModelID) {
                localRunnerModelID = models.first ?? ""
            }
            if models.isEmpty {
                localRunnerStatus = .ready("Runner is reachable. Enter a model ID.")
            } else {
                localRunnerStatus = .ready("Found \(models.count) model(s).")
            }
            return true
        } catch {
            localRunnerStatus = .failed(error.localizedDescription)
            return false
        }
    }

    @MainActor
    private func useLocalRunner() async {
        if localRunnerRequiresProbe {
            guard await probeLocalRunner() else { return }
        }
        let modelID = localRunnerModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else {
            localRunnerStatus = .failed("Enter a model ID.")
            return
        }
        if let profile = selectedExtensionProviderProfile,
           !extensionRunnerConsentStore.hasApproved(profile) {
            pendingExtensionRunnerConsent = profile
            return
        }
        await applyLocalRunner()
    }

    @MainActor
    private func applyLocalRunner() async {
        let modelID = localRunnerModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = localRunnerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        showModelPicker = false
        do {
            try await engine.setLocalRunner(
                baseURL: baseURL,
                model: modelID,
                apiKey: localRunnerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : localRunnerAPIKey,
                usesKeychain: localRunnerUsesKeychain
            )
            localRunnerAPIKey = ""
        } catch {
            showModelPicker = true
            localRunnerStatus = .failed(error.localizedDescription)
        }
    }

    private func headerIcon(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
        }
        .cribbleGlassIconButton(size: 30)
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
                    pendingPreflightScope = .folder
                } label: {
                    Text(isEnabling ? "Starting…" : "This folder")
                        .font(.system(size: 12, weight: .semibold))
                }
                .cribbleGlassCapsuleButton(prominent: true)
                .disabled(activeRootURL() == nil || isEnabling)

                Button {
                    pendingPreflightScope = .allFolders
                } label: {
                    Text("All folders (\(allRoots().count))")
                        .font(.system(size: 12, weight: .semibold))
                }
                .cribbleGlassCapsuleButton()
                .disabled(allRoots().isEmpty || isEnabling)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func startIntelligence(_ scope: IntelligencePreflightScope) {
        switch scope {
        case .folder:
            guard let root = activeRootURL() else { return }
            isEnabling = true
            Task { await engine.enable(rootURL: root); isEnabling = false }
        case .allFolders:
            let roots = allRoots()
            guard !roots.isEmpty else { return }
            isEnabling = true
            Task { await engine.enableAllFolders(roots: roots); isEnabling = false }
        }
    }

    private func roots(for scope: IntelligencePreflightScope) -> [URL] {
        switch scope {
        case .folder:
            activeRootURL().map { [$0] } ?? []
        case .allFolders:
            allRoots()
        }
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
                .cribbleGlassCapsuleButton(prominent: true)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14).padding(.vertical, 8)
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

    // MARK: - Project Pulse (health + progress)

    /// Count of per-document summaries produced so far.
    private var analyzedCount: Int {
        min(engine.filesIndexed, Set(visibleFileSummaries.flatMap(\.sourceHashes)).count)
    }

    /// Analysis progress in 0...1 (summaries / indexed files).
    private var analysisProgress: Double {
        guard engine.filesIndexed > 0 else { return 0 }
        return min(1, Double(analyzedCount) / Double(engine.filesIndexed))
    }

    private func hasArtifact(_ type: IntelligenceArtifactType) -> Bool {
        engine.artifacts.contains { $0.type == type }
    }

    /// A glanceable health + progress card rolling up signals the engine already
    /// produces. Domain-agnostic, so it reads the same for code or prose vaults.
    private var projectPulseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Project Pulse", systemImage: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if engine.pendingJobs > 0 {
                    Text(pendingJobsLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Analyzed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(analyzedCount) / \(engine.filesIndexed)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                ProgressView(value: analysisProgress)
                    .tint(.accentColor)
            }

            HStack(spacing: 8) {
                pulseChip(
                    icon: hasArtifact(.contradictionReport) ? "exclamationmark.bubble.fill" : "checkmark.seal",
                    text: hasArtifact(.contradictionReport) ? "Contradictions flagged" : "No conflicts found",
                    tint: hasArtifact(.contradictionReport) ? .orange : .green
                )
                if hasArtifact(.glossary) {
                    pulseChip(icon: "character.book.closed", text: "Glossary", tint: .white.opacity(0.6))
                }
                if hasArtifact(.timeline) {
                    pulseChip(icon: "calendar.day.timeline.left", text: "Timeline", tint: .white.opacity(0.6))
                }
            }

            if engine.staleCount > 0 {
                pulseChip(icon: "clock.arrow.circlepath", text: "\(engine.staleCount) may be stale", tint: .yellow)
            }
            if !engine.failedJobs.isEmpty {
                pulseChip(icon: "exclamationmark.triangle.fill", text: "\(engine.failedJobs.count) need attention", tint: .orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func pulseChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private var pendingJobsLabel: String {
        if let description = engine.currentJobDescription {
            return "\(engine.pendingJobs) queued · \(description)"
        }
        return "\(engine.pendingJobs) queued"
    }

    private var feedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if case .unavailable = engine.providerHealth {
                    providerHealthBanner
                }

                projectPulseCard

                if !engine.failedJobs.isEmpty {
                    needsAttentionSection
                }

                HStack(spacing: 10) {
                    metricTile(title: "Files", value: "\(engine.filesIndexed)", icon: "doc.text.magnifyingglass")
                    metricTile(title: "Artifacts", value: "\(visibleArtifacts.count)", icon: "square.stack.3d.up")
                    metricTile(title: "Insights", value: "\(activeResearchInsights.count)", icon: "doc.text.magnifyingglass")
                }

                if let decision = engine.resourceDecision {
                    resourceDecisionRow(decision)
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
                if visibleArtifacts.isEmpty {
                    emptyState(
                        icon: engine.pendingJobs > 0 ? "hourglass" : "tray",
                        title: engine.pendingJobs > 0 ? "Building intelligence..." : "Waiting for artifacts",
                        detail: "Generated summaries, diagrams, and audits will land here as the local engine works."
                    )
                } else {
                    ForEach(Array(visibleArtifacts.prefix(6))) { artifact in
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
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var providerHealthBanner: some View {
        let payload = providerHealthPayload
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(.orange.opacity(0.92))
            VStack(alignment: .leading, spacing: 2) {
                Text(payload.reason)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                if let detail = payload.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                performProviderFix(payload.fix)
            } label: {
                Label(payload.actionTitle, systemImage: payload.actionIcon)
                    .font(.system(size: 10, weight: .semibold))
            }
            .cribbleGlassCapsuleButton(prominent: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.5)
        }
    }

    private var providerHealthPayload: (reason: String, detail: String?, actionTitle: String, actionIcon: String, fix: ProviderFix) {
        guard case .unavailable(let reason, let fix) = engine.providerHealth else {
            return ("Provider ready", nil, "Done", "checkmark", .openModelPicker)
        }
        switch fix {
        case .downloadModel(let model):
            return (reason, model.approximateSize, "Download", "arrow.down.circle", fix)
        case .openModelPicker:
            return (reason, nil, "Choose model", "cpu", fix)
        case .startLocalRunner(let name, let url):
            return (reason, url, "Configure \(name)", "network", fix)
        case .authenticateCLI(_, let command):
            return (reason, command, "Copy command", "doc.on.doc", fix)
        }
    }

    private func performProviderFix(_ fix: ProviderFix) {
        switch fix {
        case .downloadModel:
            Task { await engine.downloadModelIfNeeded() }
        case .openModelPicker:
            showModelPicker = true
        case .startLocalRunner(let name, let url):
            configureLocalRunner(name: name, baseURL: url)
        case .authenticateCLI(_, let command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    private var needsAttentionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("NEEDS ATTENTION")
                Spacer()
                Button {
                    Task { await engine.retryAllFailed() }
                } label: {
                    Label("Retry all", systemImage: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .cribbleGlassCapsuleButton()
                .foregroundStyle(.white.opacity(0.74))
            }

            ForEach(Array(engine.failedJobs.prefix(8))) { job in
                failedJobRow(job)
            }

            if engine.failedJobs.count > 8 {
                Text("…and \(engine.failedJobs.count - 8) more")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
                    .padding(.horizontal, 2)
            }
        }
    }

    private func failedJobRow(_ job: IntelligenceJob) -> some View {
        let source = job.inputPaths.first.map(Self.displayName(forJobPath:)) ?? job.type.displayName
        let explanation = JobFailureExplainer.explain(
            type: job.type,
            errorMessage: job.errorMessage,
            inputPath: job.inputPaths.first
        )
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon(for: job.type))
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(.orange.opacity(0.88))
            VStack(alignment: .leading, spacing: 3) {
                Text(source)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(explanation.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button {
                Task { await engine.retryFailedJob(id: job.id) }
            } label: {
                Text("Retry")
                    .font(.system(size: 10, weight: .semibold))
            }
            .cribbleGlassCapsuleButton(prominent: explanation.suggestion == .providerFix)
            Button {
                Task { await engine.dismissFailedJob(id: job.id) }
            } label: {
                Text("Dismiss")
                    .font(.system(size: 10, weight: .semibold))
            }
            .cribbleGlassCapsuleButton()
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func icon(for type: IntelligenceJobType) -> String {
        switch type {
        case .analyzeFile, .summarizeFile:
            return IntelligenceArtifactType.fileSummary.icon
        case .extractFallbackLogic:
            return IntelligenceArtifactType.fallbackAudit.icon
        case .extractIOBehavior:
            return IntelligenceArtifactType.ioBehavior.icon
        case .summarizeDiff:
            return IntelligenceArtifactType.diffSummary.icon
        case .summarizeCommit:
            return IntelligenceArtifactType.commitSummary.icon
        case .updateProjectIndex:
            return IntelligenceArtifactType.projectIndex.icon
        case .buildDependencyDiagram:
            return IntelligenceArtifactType.dependencyDiagram.icon
        case .buildConnectionsGraph:
            return IntelligenceArtifactType.connectionsGraph.icon
        case .buildArchitectureDiagram:
            return IntelligenceArtifactType.architectureDiagram.icon
        case .detectArchitectureDrift:
            return IntelligenceArtifactType.driftReport.icon
        case .detectContradictions:
            return IntelligenceArtifactType.contradictionReport.icon
        case .buildGlossary:
            return IntelligenceArtifactType.glossary.icon
        case .buildTimeline:
            return IntelligenceArtifactType.timeline.icon
        case .discoverConnections:
            return IntelligenceArtifactType.researchInsight.icon
        case .scanWorkspace, .detectChangedFiles, .parseCodeSymbols, .extractImports:
            return "gearshape"
        }
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
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func resourceDecisionRow(_ decision: BackgroundScheduler.Decision) -> some View {
        HStack(spacing: 10) {
            Image(systemName: resourceIcon(for: decision))
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(resourceColor(for: decision).opacity(0.95))
            VStack(alignment: .leading, spacing: 2) {
                Text(decision.userFacingSummary)
                    .font(.system(size: 12, weight: .semibold))
                Text(resourceDetail(for: decision))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(resourceColor(for: decision).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(resourceColor(for: decision).opacity(0.18), lineWidth: 0.5)
        }
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
                }
                .cribbleGlassIconButton(size: 26)
                .foregroundStyle(.white.opacity(0.46))
                .help("Dismiss insight")
            }
            Text(insight.body)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(3)
            if let artifactID = insight.artifactID,
               visibleArtifacts.contains(where: { $0.id == artifactID }) {
                Button {
                    selectedArtifactID = artifactID
                    selectedTab = .artifacts
                } label: {
                    Label("Open artifact", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                }
                .cribbleGlassCapsuleButton()
                .foregroundStyle(.white.opacity(0.74))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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
                }
                .cribbleGlassIconButton(size: 26)
                .foregroundStyle(.green.opacity(0.78))
                .help("Accept suggested relationship")
                Button {
                    Task { await engine.dismissSuggestedEdge(edge) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .cribbleGlassIconButton(size: 26)
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
                .cribbleGlassCapsuleButton()
                .foregroundStyle(.white.opacity(0.55))
                .help("Open source")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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
            .background(selected ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
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
                        Button {
                            copyArtifactMarkdown(artifact, body: body)
                        } label: {
                            Label("Copy Markdown", systemImage: "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .cribbleGlassCapsuleButton()
                        .help("Copy this generated artifact as Markdown for issues, PRs, or notes.")

                        if !artifact.isPublished {
                            Button {
                                Task { await engine.publish(artifact) }
                            } label: {
                                Label("Save to folder", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .cribbleGlassCapsuleButton()
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
                    if visibleArtifacts.isEmpty {
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
            Text("\(visibleArtifacts.count) artifacts")
            if engine.pendingJobs > 0 {
                Text("·")
                ProgressView().controlSize(.mini).scaleEffect(0.7)
                Text("\(engine.pendingJobs) processing")
            }
            if engine.staleCount > 0 {
                Text("·")
                Text("\(engine.staleCount) stale").foregroundStyle(.orange.opacity(0.8))
            }
            if let decision = engine.resourceDecision {
                Text("·")
                Text(decision.userFacingSummary)
                    .foregroundStyle(resourceColor(for: decision).opacity(0.8))
            }
            Spacer()
            if let activity = engine.lastActivity {
                Text(activity).lineLimit(1).truncationMode(.tail).foregroundStyle(.white.opacity(0.45))
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 14).padding(.vertical, 5)
    }

    // MARK: - Ask

    private var askTab: some View {
        VStack(spacing: 10) {
            if let answer = askAnswer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Project Answer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Button {
                            copyAskAnswer(answer)
                        } label: {
                            Label("Copy Answer", systemImage: "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .cribbleGlassCapsuleButton()
                        .help("Copy this answer with the question for notes, issues, or team review.")
                    }

                    ScrollView {
                        StructuredText(markdown: answer)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                VStack(spacing: 12) {
                    emptyState(
                        icon: "questionmark.bubble",
                        title: "Ask about this project",
                        detail: "Answers use the generated intelligence artifacts as context and cite the artifacts they used."
                    )
                    askSuggestionChips
                }
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(askText.isEmpty ? 0.3 : 0.9))
                }
                .cribbleGlassIconButton(prominent: !askText.isEmpty, size: 34)
                .disabled(askText.isEmpty || isAsking)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyAskAnswer(_ answer: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(IntelligenceAskHandoff.markdown(question: askText, answer: answer), forType: .string)
    }

    private var askSuggestionChips: some View {
        let questions = suggestedAskQuestions
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(questions.prefix(3)), id: \.self) { question in
                    askSuggestionChip(question)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(questions.dropFirst(3)), id: \.self) { question in
                    askSuggestionChip(question)
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private func askSuggestionChip(_ question: String) -> some View {
        Button {
            submitSuggestedAsk(question)
        } label: {
            Text(question)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.82))
        .pointingHandOnHover()
        .disabled(isAsking)
    }

    private var suggestedAskQuestions: [String] {
        IntelligenceAskSuggestionBuilder.questions(
            hasProjectMap: hasArtifact(.architectureDiagram) || hasArtifact(.dependencyDiagram) || !engine.knowledgeNodes.isEmpty,
            hasGlossary: hasArtifact(.glossary),
            hasTimeline: hasArtifact(.timeline),
            hasResearchFollowups: !activeResearchInsights.isEmpty || hasArtifact(.contradictionReport),
            usesRemoteRunner: usesRemoteRunner
        )
    }

    private func submitSuggestedAsk(_ question: String) {
        askText = question
        ask(question: question)
    }

    private func ask() {
        let question = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        ask(question: question)
    }

    private func ask(question: String) {
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

                if let decision = engine.resourceDecision {
                    sectionHeader("RESOURCE POLICY")
                    contextRow("Current gate", value: decision.userFacingSummary)
                    contextRow("Allowed work", value: allowedWorkLabel(decision.allowedTier))
                    contextRow("User idle", value: "\(Int(decision.conditions.userIdleSeconds))s")
                    contextRow("System load", value: String(format: "%.2fx", decision.conditions.systemLoadRatio))
                }

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

    private func resourceIcon(for decision: BackgroundScheduler.Decision) -> String {
        switch decision.reason {
        case .memoryPressure: "memorychip"
        case .thermalPressure: "thermometer.high"
        case .highSystemLoad, .systemBusy: "cpu"
        case .lowPower: "battery.25"
        case .idleWindow: "moon.zzz"
        case .waitingForIdle: "hourglass"
        }
    }

    private func resourceColor(for decision: BackgroundScheduler.Decision) -> Color {
        switch decision.allowedTier {
        case .none: .red
        case .tier1: .orange
        case .tier2: .yellow
        case .tier3: .green
        }
    }

    private func resourceDetail(for decision: BackgroundScheduler.Decision) -> String {
        "\(allowedWorkLabel(decision.allowedTier)) | idle \(Int(decision.conditions.userIdleSeconds))s | load \(String(format: "%.2fx", decision.conditions.systemLoadRatio))"
    }

    private func allowedWorkLabel(_ tier: IntelligenceJobTier) -> String {
        switch tier {
        case .none: "No background work"
        case .tier1: "Deterministic only"
        case .tier2: "Light model work"
        case .tier3: "Full local intelligence"
        }
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

    private func copyArtifactMarkdown(_ artifact: IntelligenceArtifact, body: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(IntelligenceArtifactHandoff.markdown(for: artifact, body: body), forType: .string)
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

    private var visibleArtifacts: [IntelligenceArtifact] {
        let artifacts = engine.hasCodeFiles
            ? engine.artifacts
            : engine.artifacts.filter { !Self.codeOnlyArtifactTypes.contains($0.type) }
        return Self.deduplicatingFileSummaries(artifacts)
    }

    private var visibleFileSummaries: [IntelligenceArtifact] {
        visibleArtifacts.filter { $0.type == .fileSummary }
    }

    private static let codeOnlyArtifactTypes: Set<IntelligenceArtifactType> = [
        .architectureDiagram,
        .dependencyDiagram,
        .fallbackAudit,
        .ioBehavior,
        .driftReport
    ]

    private static func deduplicatingFileSummaries(_ artifacts: [IntelligenceArtifact]) -> [IntelligenceArtifact] {
        var seenSummaryTitles: Set<String> = []
        return artifacts.filter { artifact in
            guard artifact.type == .fileSummary else { return true }
            let key = artifact.title ?? artifact.relativePath
            return seenSummaryTitles.insert(key).inserted
        }
    }

    private static func displayName(forJobPath path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private var selectedArtifact: IntelligenceArtifact? {
        visibleArtifacts.first { $0.id == selectedArtifactID }
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
            artifacts: visibleArtifacts,
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
            artifacts: visibleArtifacts,
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

    private var activeModelLabel: String {
        if let runnerURL = engine.settings.localRunnerBaseURL {
            if let known = runnerName(for: runnerURL) {
                return known
            }
            return "Runner"
        }
        return engine.activeModel?.shortName ?? "Model"
    }

    private var preflightRunnerSummary: IntelligencePreflightRunnerSummary {
        IntelligencePreflightRunnerSummary.current(
            runnerURL: engine.settings.localRunnerBaseURL,
            modelID: engine.settings.modelID,
            onDeviceModelLabel: engine.activeModel?.shortName ?? "Model",
            extensionProfiles: extensionProviderProfiles()
        )
    }

    private var canUseLocalRunner: Bool {
        URL(string: localRunnerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && !localRunnerModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var localRunnerPrivacyWarning: String? {
        guard let url = URL(string: localRunnerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased()
        else { return nil }
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
        return isLoopback ? nil : RemoteRunnerDataBoundary.detail
    }

    private var remoteRunnerHandoff: CustomRunnerHandoff? {
        guard let url = URL(string: localRunnerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased()
        else { return nil }
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
        guard !isLoopback else { return nil }
        return CustomRunnerHandoff(
            name: localRunnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Runner" : localRunnerName,
            baseURL: url,
            modelID: localRunnerModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var usesRemoteRunner: Bool {
        guard let runnerURL = engine.settings.localRunnerBaseURL,
              let url = URL(string: runnerURL),
              let host = url.host?.lowercased()
        else { return false }
        return !(host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost"))
    }

    private var isCustomLocalRunnerSelected: Bool {
        guard let baseURL = engine.settings.localRunnerBaseURL else { return false }
        return runnerName(for: baseURL) == nil
    }

    private func isSelectedRunner(_ baseURL: String) -> Bool {
        engine.settings.localRunnerBaseURL == baseURL
    }

    private func runnerName(for baseURL: String) -> String? {
        OpenAICompatibleProvider.knownLocalEndpoints.first { $0.url.absoluteString == baseURL }?.name
    }

    /// Artifacts grouped into display sections, in a stable section order.
    private var groupedArtifacts: [(String, [IntelligenceArtifact])] {
        let order: [(String, [IntelligenceArtifactType])] = [
            ("Overview", [.projectIndex]),
            ("Insights", [.contradictionReport, .glossary, .timeline]),
            ("Connections", [.connectionsGraph]),
            ("Architecture", [.architectureDiagram, .dependencyDiagram]),
            ("Changes", [.diffSummary, .commitSummary]),
            ("Audits", [.fallbackAudit, .ioBehavior, .driftReport]),
            ("Research", [.researchInsight]),
            ("Files", [.fileSummary])
        ]
        return order.compactMap { section in
            if !engine.hasCodeFiles, section.0 == "Architecture" || section.0 == "Audits" {
                return nil
            }
            let items = visibleArtifacts.filter { section.1.contains($0.type) }
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
        case .research: "doc.text.magnifyingglass"
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

enum IntelligenceArtifactHandoff {
    static func markdown(for artifact: IntelligenceArtifact, body: String) -> String {
        let title = artifact.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = title?.isEmpty == false ? title! : artifact.relativePath
        let type = artifact.type.rawValue.replacingOccurrences(of: "_", with: " ")
        let saved = artifact.isPublished ? "saved to .cribble/intelligence" : "not saved to project folder"

        return """
        # \(heading)

        - Type: \(type)
        - Path: \(artifact.relativePath)
        - Status: \(saved)

        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }
}

enum IntelligenceAskHandoff {
    static func markdown(question: String, answer: String) -> String {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let questionLine = trimmedQuestion.isEmpty ? "Project Intelligence question" : trimmedQuestion

        return """
        # Project Intelligence Answer

        **Question:** \(questionLine)

        \(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        """
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

private struct LocalRunnerProbeStatus: Equatable {
    let message: String
    let isError: Bool

    static func ready(_ message: String) -> LocalRunnerProbeStatus {
        LocalRunnerProbeStatus(message: message, isError: false)
    }

    static func failed(_ message: String) -> LocalRunnerProbeStatus {
        LocalRunnerProbeStatus(message: message, isError: true)
    }
}

private struct CustomRunnerHandoff: Equatable {
    let name: String
    let baseURL: URL
    let modelID: String

    var hostLabel: String {
        baseURL.host ?? baseURL.absoluteString
    }

    var summary: String {
        [
            "Runner: \(name)",
            "Endpoint: \(baseURL.absoluteString)",
            "Model: \(modelID.isEmpty ? "enter before use" : modelID)",
            "Trust label: Custom remote runner",
            "Context boundary: \(RemoteRunnerDataBoundary.detail)",
            "API key: enter in the Intelligence HUD; store in Keychain when needed",
            "Approval checklist:",
            "- Endpoint is controlled by the user, team, or trusted vendor.",
            "- Secrets stay out of manifests and notes; use Keychain only.",
            "- Requested context is appropriate for this runner.",
            "- Disable path is understood before approval.",
            "Review: confirm retention policy, logging, and access controls before use",
            "Disable/revoke: choose a different runner, clear the API key, or remove the endpoint"
        ].joined(separator: "\n")
    }
}

private struct CustomRunnerHandoffStrip: View {
    let handoff: CustomRunnerHandoff
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.9))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Custom remote runner")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Text("\(handoff.name) · \(handoff.hostLabel)")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                onCopy()
            } label: {
                Label("Copy Review", systemImage: "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Copy custom runner checklist")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Custom remote runner handoff: \(handoff.name), \(handoff.hostLabel)")
    }
}

private struct ExtensionRunnerHandoffStrip: View {
    let profile: ExtensionIntelligenceProviderProfile
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: profile.isLoopback ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(profile.isLoopback ? Color.green.opacity(0.9) : Color.orange.opacity(0.9))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.trustLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Text("\(profile.sourceName) · \(profile.baseURL.host ?? profile.baseURL.absoluteString)")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                onCopy()
            } label: {
                Label("Copy Review", systemImage: "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Copy runner handoff details")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Runner handoff: \(profile.trustLabel), \(profile.sourceName)")
    }
}

enum IntelligenceAskSuggestionBuilder {
    static func questions(
        hasProjectMap: Bool,
        hasGlossary: Bool,
        hasTimeline: Bool,
        hasResearchFollowups: Bool,
        usesRemoteRunner: Bool
    ) -> [String] {
        var questions = [
            "What changed recently?",
            "What should I read first?",
            "Where are the riskiest notes?"
        ]

        if usesRemoteRunner {
            questions.append("What context leaves my Mac?")
        }
        if hasProjectMap {
            questions.append("Explain the project map")
        }
        if hasGlossary {
            questions.append("Define the important terms")
        }
        if hasTimeline {
            questions.append("Summarize the timeline")
        }
        if hasResearchFollowups {
            questions.append("Which claims need follow-up?")
        }

        return Array(questions.prefix(6))
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
        case .researchInsight: "doc.text.magnifyingglass"
        case .contradictionReport: "exclamationmark.bubble"
        case .glossary: "character.book.closed"
        case .timeline: "calendar.day.timeline.left"
        }
    }
}
