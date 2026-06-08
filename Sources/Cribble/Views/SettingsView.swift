import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @EnvironmentObject private var extensionRegistry: ExtensionRegistry
    @State private var extensionStatus: String?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Fonts") {
                FontFamilyPicker(
                    title: "Primary Text",
                    selection: $settings.readerFontName,
                    families: SystemFonts.families
                )
                FontFamilyPicker(
                    title: "Monospace",
                    selection: $settings.monospaceFontName,
                    families: SystemFonts.monospaceFamilies
                )
                Text("Used for document text and code. Choose any font installed on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reading") {
                HStack {
                    Text("Text size")
                    Slider(value: $settings.readerFontScale, in: 0.55...1.3, step: 0.05)
                        .help("Fine-tune reader text size")
                    Text("\(Int(settings.readerFontScale * 100))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Picker("Text size preset", selection: Binding(
                    get: { ReaderFontSizePreset.closest(to: settings.readerFontScale) },
                    set: { settings.setFontSize($0) }
                )) {
                    ForEach(ReaderFontSizePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                Picker("Sort files by", selection: $settings.fileSortMode) {
                    ForEach(FileSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("Show linked file cards", isOn: $settings.showLinkedFileCards)
                    .help("Show a compact linked-files strip above each Markdown document")

                Toggle("Load remote images", isOn: $settings.loadRemoteImages)
                    .help("When off, http(s) images in notes appear as click-to-open links instead of loading automatically — keeping your reading private (no IP leak to remote hosts).")
            }

            Section("External Editor") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default editor")
                        Text(settings.editorApplicationURL?.lastPathComponent ?? "No editor selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose...", action: settings.chooseEditor)
                        .help("Choose the app Cribble uses for external Markdown editing")
                    Button("Clear", action: settings.resetEditor)
                        .disabled(settings.editorApplicationURL == nil)
                        .help("Clear the configured external editor")
                }
            }

            Section("Project Intelligence") {
                Picker("Performance", selection: Binding(
                    get: { intelligence.settings.performanceMode },
                    set: { intelligence.setPerformanceMode($0) }
                )) {
                    ForEach(PerformanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose how much background analysis Cribble may run on this Mac")

                Text(intelligence.settings.performanceMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Pause on battery saver", isOn: Binding(
                    get: { intelligence.settings.pauseOnBattery },
                    set: { intelligence.settings.pauseOnBattery = $0 }
                ))
                    .help("Pause background Project Intelligence when macOS Low Power Mode is active")

                Toggle("Use Project Intelligence in chat", isOn: Binding(
                    get: { intelligence.settings.useInChat },
                    set: { intelligence.settings.useInChat = $0 }
                ))
                    .help("Allow the chat HUD to include the active project's generated intelligence context")

                Stepper(value: Binding(
                    get: { intelligence.settings.diskBudgetMB },
                    set: { intelligence.settings.diskBudgetMB = $0 }
                ), in: 100...5000, step: 100) {
                    HStack {
                        Text("Disk budget")
                        Spacer()
                        Text("\(intelligence.settings.diskBudgetMB) MB")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .help("Limit regenerable .cribble/cache artifacts; oldest artifacts are evicted first")

                HStack(alignment: .top, spacing: 8) {
                    Label(intelligenceRunnerBoundaryTitle, systemImage: intelligence.settings.localRunnerBaseURL == nil ? "macbook" : "network")
                    Spacer(minLength: 8)
                    Button("Remote Guide") {
                        library.openDemoNote(named: "Extensions and Remote Intelligence.md", sortMode: settings.fileSortMode)
                    }
                    .help("Open the guide for trusted VPS or team runners")
                }

                Text(intelligenceRunnerBoundaryDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Extensions") {
                VStack(alignment: .leading, spacing: 10) {
                    ExtensionDashboard(
                        summary: ExtensionDashboardSummary(
                            installed: extensionRegistry.installedExtensions,
                            disabledIDs: extensionRegistry.disabledExtensionIDs,
                            warningCount: extensionRegistry.loadWarnings.count
                        )
                    )

                    ExtensionStarterRulesStrip()

                    HStack {
                        Label("Extension folders", systemImage: "puzzlepiece.extension")
                        Spacer()
                        Button("Reveal", action: revealUserExtensionsFolder)
                            .help("Open Cribble's user extension folder in Finder")
                        Button("Check Again") {
                            validateExtensions()
                        }
                        .help("Reload extension manifests and surface validation warnings")
                        Button("Copy Summary") {
                            copyExtensionDashboardSummary()
                        }
                        .help("Copy installed/enabled extension counts and active contribution lanes")
                        Button("Copy Proposal") {
                            copyExtensionProposalTemplate()
                        }
                        .help("Copy the extension idea template for issues, Discussions, or team review")
                        Button("Open Kit") {
                            library.openDemoNote(named: "Team Extension Kit.md", sortMode: settings.fileSortMode)
                        }
                        .help("Open the DemoNotes guide for team extension design")
                        Button("Contribution Guide") {
                            library.openDemoNote(named: "Extension Contribution Guide.md", sortMode: settings.fileSortMode)
                        }
                        .help("Open the read-only-first contribution guide for extension authors")
                        Button("Remote Guide") {
                            library.openDemoNote(named: "Extensions and Remote Intelligence.md", sortMode: settings.fileSortMode)
                        }
                        .help("Open the guide for remote runners and trusted VPS intelligence")
                        Menu("Create Example") {
                            ForEach(ExtensionExampleTemplate.allCases) { template in
                                Button(template.title) {
                                    createExample(template)
                                }
                            }
                        }
                        .help("Write a starter manifest plus README review checklist")
                        Menu("Create Project Example") {
                            ForEach(ExtensionExampleTemplate.allCases) { template in
                                Button(template.title) {
                                    createProjectExample(template)
                                }
                            }
                        }
                        .disabled(library.activeRootURL == nil)
                        .help("Write a starter manifest plus README review checklist into the current folder's .cribble/extensions directory")
                    }

                    Text("Cribble discovers extension manifests in Application Support and each opened folder's .cribble/extensions directory. API v1 extensions are declarative: manifests are loaded and validated, but extension code is not executed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("New examples include a local README checklist for read-only API v1, least permission, previewed writes, Keychain secrets, native SwiftUI, and review routes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if extensionRegistry.installedExtensions.isEmpty {
                        ExtensionEmptyState(
                            canCreateProjectExample: library.activeRootURL != nil,
                            onCreateQuickAction: { createExample(.quickAction) },
                            onCreateProjectQuickAction: { createProjectExample(.quickAction) },
                            onOpenKit: {
                                library.openDemoNote(named: "Team Extension Kit.md", sortMode: settings.fileSortMode)
                            },
                            onOpenContributionGuide: {
                                library.openDemoNote(named: "Extension Contribution Guide.md", sortMode: settings.fileSortMode)
                            }
                        )
                    } else {
                        VStack(spacing: 8) {
                            ForEach(extensionRegistry.installedExtensions) { installed in
                                ExtensionManifestRow(
                                    extension: installed,
                                    isEnabled: extensionRegistry.isEnabled(installed),
                                    trustDecision: extensionRegistry.trustDecision(for: installed),
                                    onEnabledChange: { enabled in
                                        setExtensionEnabled(enabled, for: installed)
                                    },
                                    onReveal: {
                                        revealExtensionManifest(installed)
                                    },
                                    onCopyReviewSummary: {
                                        copyReviewSummary(for: installed)
                                    },
                                    onRevokeTrust: {
                                        revokeTrust(for: installed)
                                    },
                                    onClearTrust: {
                                        clearTrustDecision(for: installed)
                                    }
                                )
                            }
                        }
                    }

                    if !extensionRegistry.loadWarnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("Validation warnings", systemImage: "exclamationmark.triangle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button {
                                    copyExtensionWarnings()
                                } label: {
                                    Label("Copy Warnings", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Copy extension validation warnings for an issue, PR, or teammate review")
                            }

                            ForEach(extensionRegistry.loadWarnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if !extensionRegistry.importerCapabilities.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Import lanes", systemImage: "square.and.arrow.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(extensionRegistry.importerCapabilities) { capability in
                                HStack(spacing: 8) {
                                    Text(capability.title)
                                        .font(.caption.weight(.medium))
                                    Text(capability.extensionSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 8)
                                    Text("\(capability.outputFormat) • \(capability.sourceName)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(capability.reviewSummary, forType: .string)
                                        extensionStatus = "Copied \(capability.title) import lane details"
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy import lane details for review")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }

                    if let extensionStatus {
                        Text(extensionStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 680)
        .onAppear {
            extensionRegistry.reload(projectRoots: library.rootURLs)
        }
        .onChange(of: library.rootURLs) { _, roots in
            extensionRegistry.reload(projectRoots: roots)
        }
    }

    private var intelligenceRunnerBoundaryTitle: String {
        if let runner = intelligence.settings.localRunnerBaseURL,
           !runner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Remote runner configured"
        }
        return "On-device runner"
    }

    private var intelligenceRunnerBoundaryDetail: String {
        if let runner = intelligence.settings.localRunnerBaseURL,
           !runner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let keychain = intelligence.settings.runnerUsesKeychain(baseURL: runner) ? "Keychain token marker is on." : "No Keychain token marker is set."
            return "\(RemoteRunnerDataBoundary.detail) \(keychain)"
        }
        return "Notes stay on this Mac unless you choose a remote runner or extension profile."
    }

    private func createExample(_ template: ExtensionExampleTemplate) {
        do {
            let url = try extensionRegistry.writeExampleManifest(template: template)
            let folderName = url.deletingLastPathComponent().lastPathComponent
            let success = "Created \(folderName) with README checklist"
            extensionStatus = success
            validateExtensions(successPrefix: success)
        } catch {
            extensionStatus = error.localizedDescription
        }
    }

    private func createProjectExample(_ template: ExtensionExampleTemplate) {
        guard let root = library.activeRootURL else {
            extensionStatus = "Open a folder before creating a project extension example"
            return
        }
        do {
            let url = try extensionRegistry.writeProjectExampleManifest(template: template, projectRoot: root)
            let folderName = url.deletingLastPathComponent().lastPathComponent
            let success = "Created project example \(folderName) with README checklist"
            extensionStatus = success
            validateExtensions(successPrefix: success)
        } catch {
            extensionStatus = error.localizedDescription
        }
    }

    private func validateExtensions(successPrefix: String? = nil) {
        extensionRegistry.reload(projectRoots: library.rootURLs)
        let count = extensionRegistry.installedExtensions.count
        let warningCount = extensionRegistry.loadWarnings.count
        let result = warningCount == 0
            ? "validated \(count) extension\(count == 1 ? "" : "s")"
            : "found \(warningCount) warning\(warningCount == 1 ? "" : "s") across \(count) extension\(count == 1 ? "" : "s")"
        if let successPrefix {
            extensionStatus = "\(successPrefix); \(result)"
        } else {
            extensionStatus = "Extension check \(result)"
        }
    }

    private func revealUserExtensionsFolder() {
        extensionRegistry.revealUserExtensionsFolder()
        extensionStatus = "Revealed user extensions folder"
    }

    private func revealExtensionManifest(_ installed: InstalledCribbleExtension) {
        extensionRegistry.reveal(installed)
        extensionStatus = "Revealed \(installed.manifest.name) manifest"
    }

    private func setExtensionEnabled(_ enabled: Bool, for installed: InstalledCribbleExtension) {
        extensionRegistry.setEnabled(enabled, for: installed)
        extensionStatus = "\(enabled ? "Enabled" : "Disabled") \(installed.manifest.name)"
    }

    private func revokeTrust(for installed: InstalledCribbleExtension) {
        extensionRegistry.revokeTrust(for: installed)
        extensionStatus = "Revoked future consent for \(installed.manifest.name)"
    }

    private func clearTrustDecision(for installed: InstalledCribbleExtension) {
        extensionRegistry.clearTrustDecision(for: installed)
        extensionStatus = "Cleared trust decision for \(installed.manifest.name)"
    }

    private func copyReviewSummary(for installed: InstalledCribbleExtension) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(installed.reviewSummary, forType: .string)
        extensionStatus = "Copied \(installed.manifest.name) extension details"
    }

    private func copyExtensionDashboardSummary() {
        let summary = ExtensionDashboardSummary(
            installed: extensionRegistry.installedExtensions,
            disabledIDs: extensionRegistry.disabledExtensionIDs,
            warningCount: extensionRegistry.loadWarnings.count
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.reviewSummary, forType: .string)
        extensionStatus = "Copied extension dashboard summary"
    }

    private func copyExtensionWarnings() {
        let warnings = extensionRegistry.loadWarnings
        guard !warnings.isEmpty else { return }
        let body = warnings.map { "- \($0)" }.joined(separator: "\n")
        let summary = """
        Cribble extension validation warnings

        \(body)

        Next steps:
        - Open Settings > Extensions, fix the manifest, then use Check Again.
        - Use Settings > Extensions > Contribution Guide for read-only, least-writing, native SwiftUI rules.
        - Share this warning list in an issue, PR, or review thread before broadening permissions.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        extensionStatus = "Copied extension warnings"
    }

    private func copyExtensionProposalTemplate() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ExtensionProposalTemplate.markdown, forType: .string)
        extensionStatus = "Copied extension proposal template"
    }
}

enum ExtensionProposalTemplate {
    static let markdown = """
    ## Extension idea

    Audience:
    Workflow:
    Why Cribble:

    ## First read-only version

    Manifest kind:
    What appears in Cribble:
    What user reviews before anything changes:

    ## Data contract

    Reads:
    Writes:
    Network:
    Secrets:
    Disable behavior:

    ## Native Mac surface

    SwiftUI surface:
    System controls/SF Symbols:
    Settings or command entry point:
    Non-native UI needed? If yes, explain maintainer approval:

    ## Later, not first PR

    What would need executable code:
    What would need project-wide reads:
    What would need source-note writes:

    Safety checklist:
    - First mergeable version is declarative and read-only.
    - Writes use explicit preview/review/cancel.
    - Reads request the least note access that proves the workflow.
    - Secrets stay out of manifests, examples, fixtures, and docs.
    - UI uses native SwiftUI, Settings, sheets, menus, commands, toolbars, focused values, system controls, and SF Symbols.
    - First version does not need web views, custom chrome, Electron-style panels, or non-native UI.
    - Disabling the extension removes its contribution cleanly.
    """
}

struct ExtensionStarterRule: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String

    static let defaults: [ExtensionStarterRule] = [
        ExtensionStarterRule(
            id: "read-only",
            title: "Read-only first",
            detail: "API v1 loads declarative manifests; extension code is not executed.",
            systemImage: "checkmark.shield"
        ),
        ExtensionStarterRule(
            id: "least-access",
            title: "Least access",
            detail: "Prefer current-note reads, previewed writes, and Keychain-backed secrets.",
            systemImage: "lock"
        ),
        ExtensionStarterRule(
            id: "native-mac",
            title: "Native Mac UI",
            detail: "Use SwiftUI settings, sheets, commands, system controls, and SF Symbols.",
            systemImage: "macwindow"
        )
    ]
}

private struct ExtensionStarterRulesStrip: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(ExtensionStarterRule.defaults) { rule in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: rule.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.title)
                            .font(.caption.weight(.semibold))
                        Text(rule.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .help("Starter extension rules: read-only first, least access, and native Mac UI")
    }
}

struct ExtensionDashboardSummary: Equatable {
    let installedCount: Int
    let enabledCount: Int
    let warningCount: Int
    let quickActionCount: Int
    let remoteRunnerCount: Int
    let rendererCount: Int
    let importerCount: Int

    init(
        installed: [InstalledCribbleExtension],
        disabledIDs: Set<String>,
        warningCount: Int
    ) {
        self.installedCount = installed.count
        self.enabledCount = installed.filter { !disabledIDs.contains($0.manifest.id) }.count
        self.warningCount = warningCount
        let enabled = installed.filter { !disabledIDs.contains($0.manifest.id) }
        quickActionCount = enabled.reduce(0) { $0 + $1.manifest.quickActions.count }
        remoteRunnerCount = enabled.reduce(0) { $0 + $1.manifest.intelligenceProviders.count }
        rendererCount = enabled.reduce(0) { $0 + $1.manifest.renderers.count }
        importerCount = enabled.reduce(0) { $0 + $1.manifest.importers.count }
    }

    var statusTitle: String {
        if warningCount > 0 {
            return "\(warningCount) warning\(warningCount == 1 ? "" : "s") need review"
        }
        if installedCount == 0 {
            return "Ready for your first extension"
        }
        if enabledCount == 0 {
            return "All extensions are disabled"
        }
        return "\(enabledCount) enabled extension\(enabledCount == 1 ? "" : "s")"
    }

    var statusDetail: String {
        if warningCount > 0 {
            return "Check Again reloads manifests after you fix validation issues."
        }
        if installedCount == 0 {
            return "Create a read-only quick action or project-local example to start safely."
        }
        return "\(installedCount) installed; API v1 remains declarative and data-only."
    }

    var reviewSummary: String {
        """
        Cribble Extension Dashboard
        Status: \(statusTitle)
        Detail: \(statusDetail)
        Installed: \(installedCount)
        Enabled: \(enabledCount)
        Warnings: \(warningCount)
        Active quick actions: \(quickActionCount)
        Active remote runners: \(remoteRunnerCount)
        Active renderers: \(rendererCount)
        Active importers: \(importerCount)
        Safety contract: API v1 is declarative, read-only first, least-access, and native SwiftUI for user-facing UI.
        Next steps:
        - Fix validation warnings, then use Check Again.
        - Start with Create Project Example for a folder-local, reviewable manifest plus README checklist.
        - Keep the first version read-only; writes should use preview/review/cancel.
        - Remote runners need explicit data-boundary review and Keychain-only secrets.
        Contributor guide: docs/extension-contributions.md
        Manifest reference: docs/extensions.md
        Native review routes:
        - Settings > Extensions > Contribution Guide
        - Help > Copy Extension Proposal
        - Help > Copy Import Lane Setup Review
        - Help > Copy Remote Runner Setup Review
        """
    }
}

private struct ExtensionDashboard: View {
    let summary: ExtensionDashboardSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label(summary.statusTitle, systemImage: summary.warningCount > 0 ? "exclamationmark.triangle" : "checkmark.shield")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(summary.warningCount > 0 ? .orange : .primary)
                Spacer(minLength: 8)
                Text(summary.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 6) {
                ExtensionDashboardMetric(title: "Active Actions", value: summary.quickActionCount, systemImage: "bolt")
                ExtensionDashboardMetric(title: "Active Runners", value: summary.remoteRunnerCount, systemImage: "brain.head.profile")
                ExtensionDashboardMetric(title: "Active Renderers", value: summary.rendererCount, systemImage: "doc.richtext")
                ExtensionDashboardMetric(title: "Active Importers", value: summary.importerCount, systemImage: "square.and.arrow.down")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ExtensionDashboardMetric: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text("\(value)")
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ExtensionEmptyState: View {
    let canCreateProjectExample: Bool
    let onCreateQuickAction: () -> Void
    let onCreateProjectQuickAction: () -> Void
    let onOpenKit: () -> Void
    let onOpenContributionGuide: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ContentUnavailableView(
                "No Extensions Installed",
                systemImage: "puzzlepiece.extension",
                description: Text("Start with a read-only quick action, or create a project-local example that travels with the open folder.")
            )

            HStack(spacing: 8) {
                Button {
                    onCreateQuickAction()
                } label: {
                    Label("Create Quick Action", systemImage: "text.badge.plus")
                }

                Button {
                    onCreateProjectQuickAction()
                } label: {
                    Label("Create Project Example", systemImage: "folder.badge.plus")
                }
                .disabled(!canCreateProjectExample)
                .help(canCreateProjectExample ? "Write a starter quick action into the open folder" : "Open a folder before creating a project-local extension")

                Button {
                    onOpenKit()
                } label: {
                    Label("Open Kit", systemImage: "book.pages")
                }

                Button {
                    onOpenContributionGuide()
                } label: {
                    Label("Contribution Guide", systemImage: "person.crop.circle.badge.plus")
                }
                .help("Open the read-only-first contribution guide before writing a new extension")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct ExtensionManifestRow: View {
    let `extension`: InstalledCribbleExtension
    let isEnabled: Bool
    let trustDecision: ExtensionTrustDecision?
    let onEnabledChange: (Bool) -> Void
    let onReveal: () -> Void
    let onCopyReviewSummary: () -> Void
    let onRevokeTrust: () -> Void
    let onClearTrust: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(`extension`.manifest.name)
                        .font(.body.weight(.medium))
                    Text(`extension`.manifest.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(`extension`.manifest.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(`extension`.manifest.kind.title) • \(`extension`.manifest.runtime.title) • \(`extension`.location.title)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(`extension`.manifest.runtime.summary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let trust = `extension`.manifest.trust {
                    Text("Trust: \(trust.summary)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Future executable consent: \(trustDecisionLabel)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !`extension`.manifest.permissions.isEmpty {
                    Text(`extension`.manifest.permissions.map(\.title).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let contributionSummary {
                    Text(contributionSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button(action: onReveal) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reveal extension manifest in Finder")

                Button(action: onCopyReviewSummary) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy extension details for review")

                Toggle("Enabled", isOn: Binding(
                    get: { isEnabled },
                    set: { enabled in onEnabledChange(enabled) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

                if `extension`.manifest.trust != nil {
                    Menu {
                        Button("Revoke Future Consent", action: onRevokeTrust)
                        Button("Clear Trust Decision", action: onClearTrust)
                            .disabled(trustDecision == nil)
                    } label: {
                        Image(systemName: "checkmark.shield")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Manage stored trust decisions for future executable plugin support")
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var trustDecisionLabel: String {
        switch trustDecision {
        case .approved: "approved, but executable plugins are still blocked"
        case .revoked: "revoked"
        case nil: "not requested"
        }
    }

    private var iconName: String {
        switch `extension`.manifest.kind {
        case .quickAction: "bolt"
        case .intelligenceProvider: "brain.head.profile"
        case .renderer: "doc.richtext"
        case .importer: "square.and.arrow.down"
        }
    }

    private var contributionSummary: String? {
        let manifest = `extension`.manifest
        if !manifest.quickActions.isEmpty {
            return "Actions: " + manifest.quickActions.map(\.title).joined(separator: ", ")
        }
        if !manifest.intelligenceProviders.isEmpty {
            return "Providers: " + manifest.intelligenceProviders.map { "\($0.title) (\($0.modelID))" }.joined(separator: ", ")
        }
        if !manifest.renderers.isEmpty {
            return "Renderers: " + manifest.renderers.map { "\($0.title) [" + $0.languages.joined(separator: ", ") + "]" }.joined(separator: ", ")
        }
        if !manifest.importers.isEmpty {
            return "Importers: " + manifest.importers.map { "\($0.title) [" + $0.fileExtensions.joined(separator: ", ") + "]" }.joined(separator: ", ")
        }
        return nil
    }
}

private struct FontFamilyPicker: View {
    let title: String
    @Binding var selection: String?
    let families: [String]

    var body: some View {
        Picker(title, selection: $selection) {
            Text("System Default").tag(String?.none)
            Divider()
            ForEach(families, id: \.self) { family in
                Text(family).tag(String?.some(family))
            }
        }
    }
}

/// Cached lists of installed font families for the pickers.
private enum SystemFonts {
    static let families: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    static let monospaceFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { family in
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let postScriptName = members.first?.first as? String,
                  let font = NSFont(name: postScriptName, size: 12)
            else { return false }
            return font.isFixedPitch
        }
        .sorted()
}
