import Foundation
import Testing
@testable import Cribble

@MainActor
struct ExtensionRegistryTests {
    @Test
    func scansUserAndProjectExtensions() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        try fixture.writeQuickAction(
            folder: fixture.userExtensions.appendingPathComponent("user-action", isDirectory: true),
            id: "com.example.cribble.user",
            name: "User Action",
            actionID: "summarize-risk",
            actionTitle: "Summarize risk"
        )
        let project = try fixture.projectRoot()
        try fixture.writeQuickAction(
            folder: project.appendingPathComponent(".cribble/extensions/project-action", isDirectory: true),
            id: "com.example.cribble.project",
            name: "Project Action",
            actionID: "extract-decisions",
            actionTitle: "Extract decisions"
        )

        let registry = fixture.makeRegistry()
        registry.reload(projectRoots: [project])

        #expect(registry.installedExtensions.map(\.manifest.id).sorted() == [
            "com.example.cribble.project",
            "com.example.cribble.user"
        ])
        #expect(registry.quickActions.map(\.title).sorted() == [
            "Extract decisions",
            "Summarize risk"
        ])
    }

    @Test
    func installedExtensionReviewSummaryIncludesManifestDetails() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        try fixture.writeQuickAction(
            folder: fixture.userExtensions.appendingPathComponent("review-action", isDirectory: true),
            id: "com.example.cribble.review",
            name: "Review Action",
            actionID: "risk-questions",
            actionTitle: "Risk questions"
        )

        let registry = fixture.makeRegistry()
        guard let installed = registry.installedExtensions.first else {
            Issue.record("Expected installed extension")
            return
        }

        let summary = installed.reviewSummary
        #expect(summary.contains("Name: Review Action"))
        #expect(summary.contains("ID: com.example.cribble.review"))
        #expect(summary.contains("Kind: Quick Action"))
        #expect(summary.contains("Runtime: Declarative"))
        #expect(summary.contains("Permissions: Read Current Note"))
        #expect(summary.contains("Quick actions: Risk questions"))
        #expect(summary.contains("Manifest: \(installed.manifestURL.path)"))
        #expect(summary.contains("Safety contract:"))
        #expect(summary.contains("Read-only first; API v1 is declarative manifest data"))
        #expect(summary.contains("Least reading: prefer Read Current Note"))
        #expect(summary.contains("Least writing: source-note edits must go through explicit preview/review"))
        #expect(summary.contains("Secrets: never put keys or tokens in manifests"))
        #expect(summary.contains("UI: contribution UI must use native SwiftUI"))
        #expect(summary.contains("Contributor guide: docs/extension-contributions.md"))
        #expect(summary.contains("Manifest reference: docs/extensions.md"))
    }

    @Test
    func projectExtensionWinsDuplicateID() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        let duplicateID = "com.example.cribble.duplicate"
        try fixture.writeQuickAction(
            folder: fixture.userExtensions.appendingPathComponent("duplicate-user", isDirectory: true),
            id: duplicateID,
            name: "User Duplicate",
            actionID: "user-action",
            actionTitle: "User action"
        )
        let project = try fixture.projectRoot()
        try fixture.writeQuickAction(
            folder: project.appendingPathComponent(".cribble/extensions/duplicate-project", isDirectory: true),
            id: duplicateID,
            name: "Project Duplicate",
            actionID: "project-action",
            actionTitle: "Project action"
        )

        let registry = fixture.makeRegistry()
        registry.reload(projectRoots: [project])

        #expect(registry.installedExtensions.count == 1)
        #expect(registry.installedExtensions.first?.manifest.name == "Project Duplicate")
        #expect(registry.quickActions.map(\.title) == ["Project action"])
        #expect(registry.loadWarnings.contains { $0.contains("Duplicate extension id \(duplicateID)") })
    }

    @Test
    func disabledExtensionsDoNotContributeActionsOrProviders() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        try fixture.writeQuickAction(
            folder: fixture.userExtensions.appendingPathComponent("disable-me", isDirectory: true),
            id: "com.example.cribble.disabled",
            name: "Disabled",
            actionID: "disabled-action",
            actionTitle: "Disabled action"
        )

        let registry = fixture.makeRegistry()
        guard let installed = registry.installedExtensions.first else {
            Issue.record("Expected installed extension")
            return
        }

        registry.setEnabled(false, for: installed)

        #expect(!registry.isEnabled(installed))
        #expect(registry.quickActions.isEmpty)

        let reloaded = fixture.makeRegistry()
        #expect(reloaded.disabledExtensionIDs == Set(["com.example.cribble.disabled"]))
    }

    @Test
    func rendererAliasesResolveOnlyWhenEnabled() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        try fixture.writeRenderer(
            folder: fixture.userExtensions.appendingPathComponent("renderer", isDirectory: true),
            id: "com.example.cribble.renderer",
            name: "Renderer",
            languages: ["workflow", "flowchart"]
        )

        let registry = fixture.makeRegistry()

        #expect(registry.rendererResolver.resolvedLanguage(for: "workflow") == "mermaid")
        #expect(registry.rendererResolver.resolvedLanguage(for: " FLOWCHART ") == "mermaid")
        #expect(registry.rendererResolver.resolvedLanguage(for: "swift") == "swift")

        guard let installed = registry.installedExtensions.first else {
            Issue.record("Expected installed extension")
            return
        }

        registry.setEnabled(false, for: installed)

        #expect(registry.rendererResolver.resolvedLanguage(for: "workflow") == "workflow")
    }

    @Test
    func importerCapabilitiesComeFromEnabledImporters() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        try fixture.writeImporter(
            folder: fixture.userExtensions.appendingPathComponent("importer", isDirectory: true),
            id: "com.example.cribble.importer",
            name: "Research Importer",
            importerTitle: "Chat Export",
            fileExtensions: ["TXT", "json"]
        )

        let registry = fixture.makeRegistry()

        #expect(registry.importerCapabilities == [
            ExtensionImporterCapability(
                id: "com.example.cribble.importer.chat-export",
                title: "Chat Export",
                fileExtensions: ["json", "txt"],
                outputFormat: "markdown",
                sourceName: "Research Importer"
            )
        ])
        #expect(registry.importerCapabilities.first?.extensionSummary == ".json, .txt")
        let reviewSummary = try #require(registry.importerCapabilities.first?.reviewSummary)
        #expect(reviewSummary.contains("Import lane: Chat Export"))
        #expect(reviewSummary.contains("Accepted files: .json, .txt"))
        #expect(reviewSummary.contains("converter execution is not enabled yet"))
        #expect(reviewSummary.contains("reads, writes, network, secrets, disable behavior"))
        #expect(reviewSummary.contains("Safety contract:"))
        #expect(reviewSummary.contains("Read-only first; API v1 is declarative manifest data"))
        #expect(reviewSummary.contains("Least writing: source-note edits must go through explicit preview/review"))
        #expect(reviewSummary.contains("UI: contribution UI must use native SwiftUI"))

        guard let installed = registry.installedExtensions.first else {
            Issue.record("Expected installed extension")
            return
        }

        registry.setEnabled(false, for: installed)

        #expect(registry.importerCapabilities.isEmpty)
    }

    @Test
    func writesAllExampleTemplates() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        let registry = fixture.makeRegistry()
        for template in ExtensionExampleTemplate.allCases {
            let url = try registry.writeExampleManifest(template: template)
            #expect(url.lastPathComponent == "cribble-extension.json")
            #expect(url.deletingLastPathComponent().lastPathComponent == template.folderName)
        }

        #expect(registry.quickActions.contains { $0.title == "Explain jargon" })
        #expect(registry.intelligenceProviderProfiles.contains { $0.title == "Research GPU" })
        #expect(registry.rendererResolver.resolvedLanguage(for: "workflow") == "mermaid")
        #expect(registry.importerCapabilities.contains { $0.title == "Chat Export" })
    }

    @Test
    func writesProjectExampleTemplateIntoOpenedFolder() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        let project = try fixture.projectRoot()
        let registry = fixture.makeRegistry()
        let url = try registry.writeProjectExampleManifest(template: .renderer, projectRoot: project)

        #expect(url.path.contains(".cribble/extensions/example-renderer-alias/cribble-extension.json"))

        registry.reload(projectRoots: [project])
        let installed = try #require(registry.installedExtensions.first)
        #expect(installed.location.title == project.lastPathComponent)
        #expect(installed.manifest.kind == .renderer)
        #expect(installed.manifest.renderers.first?.languages == ["workflow", "flowchart"])
    }

    @Test
    func writesProjectImporterExampleIntoOpenedFolder() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        let project = try fixture.projectRoot()
        let registry = fixture.makeRegistry()
        let url = try registry.writeProjectExampleManifest(template: .importer, projectRoot: project)

        #expect(url.path.contains(".cribble/extensions/example-import-lane/cribble-extension.json"))

        registry.reload(projectRoots: [project])
        let installed = try #require(registry.installedExtensions.first)
        #expect(installed.location.title == project.lastPathComponent)
        #expect(installed.manifest.kind == .importer)
        #expect(registry.importerCapabilities.first?.title == "Chat Export")
        #expect(registry.importerCapabilities.first?.sourceName == "Example Chat Importers")
    }

    @Test
    func reloadPrunesStaleTrustDecisions() throws {
        let fixture = try ExtensionRegistryFixture()
        defer { fixture.cleanUp() }

        let keptID = "com.example.cribble.trusted"
        try fixture.writeTrustedQuickAction(
            folder: fixture.userExtensions.appendingPathComponent("trusted", isDirectory: true),
            id: keptID,
            name: "Trusted"
        )

        let registry = fixture.makeRegistry()
        guard let installed = registry.installedExtensions.first else {
            Issue.record("Expected installed extension")
            return
        }

        registry.revokeTrust(for: installed)
        #expect(registry.trustDecision(for: installed) == .revoked)

        try FileManager.default.removeItem(at: fixture.userExtensions.appendingPathComponent("trusted", isDirectory: true))
        registry.reload(projectRoots: [])

        let restored = fixture.makeRegistry()
        try fixture.writeTrustedQuickAction(
            folder: fixture.userExtensions.appendingPathComponent("trusted", isDirectory: true),
            id: keptID,
            name: "Trusted"
        )
        restored.reload(projectRoots: [])

        guard let reinstalled = restored.installedExtensions.first else {
            Issue.record("Expected reinstalled extension")
            return
        }
        #expect(restored.trustDecision(for: reinstalled) == nil)
    }

    @Test
    func extensionDashboardSummaryCountsInstalledLanesAndWarnings() {
        let root = URL(fileURLWithPath: "/tmp/CribbleExtensionDashboard")
        let installed = [
            InstalledCribbleExtension(
                manifest: CribbleExtensionManifest(
                    id: "com.example.quick",
                    name: "Quick",
                    version: "1.0.0",
                    kind: .quickAction,
                    summary: "Quick action.",
                    permissions: [.readCurrentNote],
                    quickActions: [
                        CribbleExtensionQuickAction(id: "a", title: "A", icon: "bolt", prompt: "A"),
                        CribbleExtensionQuickAction(id: "b", title: "B", icon: "bolt", prompt: "B")
                    ]
                ),
                manifestURL: root.appendingPathComponent("quick/cribble-extension.json"),
                location: .user
            ),
            InstalledCribbleExtension(
                manifest: CribbleExtensionManifest(
                    id: "com.example.runner",
                    name: "Runner",
                    version: "1.0.0",
                    kind: .intelligenceProvider,
                    summary: "Runner.",
                    permissions: [.networkOpenAICompatible],
                    intelligenceProviders: [
                        CribbleExtensionIntelligenceProvider(
                            id: "gpu",
                            title: "GPU",
                            baseURL: URL(string: "https://runner.example.com/v1")!,
                            modelID: "team-model",
                            embeddingModelID: nil,
                            trustLabel: "Team GPU"
                        )
                    ]
                ),
                manifestURL: root.appendingPathComponent("runner/cribble-extension.json"),
                location: .user
            ),
            InstalledCribbleExtension(
                manifest: CribbleExtensionManifest(
                    id: "com.example.importer",
                    name: "Importer",
                    version: "1.0.0",
                    kind: .importer,
                    summary: "Importer.",
                    importers: [
                        CribbleExtensionImporter(
                            id: "chat",
                            title: "Chat",
                            fileExtensions: ["json"],
                            outputFormat: "markdown"
                        )
                    ]
                ),
                manifestURL: root.appendingPathComponent("importer/cribble-extension.json"),
                location: .user
            )
        ]

        let summary = ExtensionDashboardSummary(
            installed: installed,
            disabledIDs: ["com.example.runner"],
            warningCount: 2
        )

        #expect(summary.installedCount == 3)
        #expect(summary.enabledCount == 2)
        #expect(summary.warningCount == 2)
        #expect(summary.quickActionCount == 2)
        #expect(summary.remoteRunnerCount == 0)
        #expect(summary.rendererCount == 0)
        #expect(summary.importerCount == 1)
        #expect(summary.statusTitle == "2 warnings need review")
        #expect(summary.statusDetail.contains("Check Again reloads manifests"))
        #expect(summary.reviewSummary.contains("Cribble Extension Dashboard"))
        #expect(summary.reviewSummary.contains("Active quick actions: 2"))
        #expect(summary.reviewSummary.contains("Active remote runners: 0"))
        #expect(summary.reviewSummary.contains("Active importers: 1"))
        #expect(summary.reviewSummary.contains("read-only first"))
        #expect(summary.reviewSummary.contains("native SwiftUI"))
        #expect(summary.reviewSummary.contains("Next steps:"))
        #expect(summary.reviewSummary.contains("Fix validation warnings"))
        #expect(summary.reviewSummary.contains("Create Project Example"))
        #expect(summary.reviewSummary.contains("preview/review/cancel"))
        #expect(summary.reviewSummary.contains("Keychain-only secrets"))
        #expect(summary.reviewSummary.contains("Contributor guide: docs/extension-contributions.md"))
        #expect(summary.reviewSummary.contains("Manifest reference: docs/extensions.md"))
        #expect(summary.reviewSummary.contains("Native review routes:"))
        #expect(summary.reviewSummary.contains("Settings > Extensions > Contribution Guide"))
        #expect(summary.reviewSummary.contains("Help > Copy Extension Proposal"))
        #expect(summary.reviewSummary.contains("Help > Copy Import Lane Setup Review"))
        #expect(summary.reviewSummary.contains("Help > Copy Remote Runner Setup Review"))
    }

    @Test
    func extensionStarterRulesSurfaceContributionConstraints() {
        let rules = ExtensionStarterRule.defaults
        let combined = rules.map { "\($0.title) \($0.detail)" }.joined(separator: "\n")

        #expect(rules.map(\.id) == ["read-only", "least-access", "native-mac"])
        #expect(combined.contains("declarative manifests"))
        #expect(combined.contains("current-note reads"))
        #expect(combined.contains("previewed writes"))
        #expect(combined.contains("Keychain-backed secrets"))
        #expect(combined.contains("SwiftUI settings"))
        #expect(combined.contains("SF Symbols"))
    }

    @Test
    func extensionProposalTemplateCopiesIdeaFirstSafetyContract() {
        let template = ExtensionProposalTemplate.markdown

        #expect(template.contains("## Extension idea"))
        #expect(template.contains("## First read-only version"))
        #expect(template.contains("## Data contract"))
        #expect(template.contains("## Native Mac surface"))
        #expect(template.contains("## Later, not first PR"))
        #expect(template.contains("declarative and read-only"))
        #expect(template.contains("least note access"))
        #expect(template.contains("Secrets stay out"))
        #expect(template.contains("native SwiftUI"))
        #expect(template.contains("SF Symbols"))
        #expect(template.contains("Non-native UI needed?"))
        #expect(template.contains("web views"))
        #expect(template.contains("custom chrome"))
        #expect(template.contains("Electron-style panels"))
        #expect(template.contains("removes its contribution cleanly"))
    }

    @Test
    func extensionGuideDocumentsExecutableReadinessGates() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let guideURL = projectRoot.appendingPathComponent("docs/extensions.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)

        #expect(guide.contains("Executable Readiness Gates"))
        #expect(guide.contains("Signed bundle identity"))
        #expect(guide.contains("Process isolation"))
        #expect(guide.contains("Permission broker"))
        #expect(guide.contains("Native consent"))
        #expect(guide.contains("Previewed writes"))
        #expect(guide.contains("Secret handling"))
        #expect(guide.contains("Revocation"))
        #expect(guide.contains("Audit trail"))
        #expect(guide.contains("Native UI"))
        #expect(guide.contains("Until those gates exist in code and tests"))
        #expect(guide.contains("declarative manifests"))
        #expect(guide.contains("Help > Copy Import Lane Setup Review"))
        #expect(guide.contains("File > Import > Copy Review"))
    }

    @Test
    func openSourceExtensionContributionGuideKeepsFirstPRsStrict() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let guideURL = projectRoot.appendingPathComponent("docs/extension-contributions.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)

        #expect(guide.contains("Cribble welcomes extension ideas"))
        #expect(guide.contains("Read-only first"))
        #expect(guide.contains("Least reading"))
        #expect(guide.contains("Least writing"))
        #expect(guide.contains("Hard native SwiftUI condition"))
        #expect(guide.contains("No hidden execution"))
        #expect(guide.contains("No secrets in files"))
        #expect(guide.contains("Clean disable path"))
        #expect(guide.contains("Help > Copy Extension Proposal"))
        #expect(guide.contains("Help > Copy Import Lane Setup Review"))
        #expect(guide.contains("File > Import > Copy Review"))
        #expect(guide.contains("Help > Copy Remote Runner Setup Review"))
        #expect(guide.contains("declarative, inspectable, reversible"))
        #expect(guide.contains("API v1 extensions are declarative"))
        #expect(guide.contains("web views, custom chrome, Electron-style"))
        #expect(guide.contains("signed bundle identity, process isolation"))
    }

    @Test
    func productImprovisationReadinessCheckpointNamesStopConditions() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let checkpointURL = projectRoot.appendingPathComponent("docs/product-improvisation-readiness-checkpoint.md")
        let checkpoint = try String(contentsOf: checkpointURL, encoding: .utf8)

        #expect(checkpoint.contains("Strong Product Signal"))
        #expect(checkpoint.contains("Help > Copy Product Readiness Checkpoint"))
        #expect(checkpoint.contains("Ready To Keep"))
        #expect(checkpoint.contains("Stop Conditions"))
        #expect(checkpoint.contains("Keep Going Only If"))
        #expect(checkpoint.contains("Verification Snapshot"))
        #expect(checkpoint.contains("executable plugin runtime"))
        #expect(checkpoint.contains("hidden extension execution"))
        #expect(checkpoint.contains("source-note writes without preview/review/cancel"))
        #expect(checkpoint.contains("secrets in manifests"))
        #expect(checkpoint.contains("non-native extension UI"))
        #expect(checkpoint.contains("remote intelligence that hides retention"))
        #expect(checkpoint.contains("Settings summaries"))
        #expect(checkpoint.contains("exact contribution, import, and remote-runner review routes"))
        #expect(checkpoint.contains("copied diagnostics or Settings summaries that preserve native review routes"))
        #expect(checkpoint.contains("No executable plugin runtime"))
    }
}

private struct ExtensionRegistryFixture {
    let root: URL
    let userExtensions: URL
    let defaults: UserDefaults
    let suiteName: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CribbleExtensionRegistryTests-\(UUID().uuidString)", isDirectory: true)
        userExtensions = root.appendingPathComponent("UserExtensions", isDirectory: true)
        try FileManager.default.createDirectory(at: userExtensions, withIntermediateDirectories: true)
        suiteName = "CribbleExtensionRegistryTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.defaults = defaults
        defaults.removePersistentDomain(forName: suiteName)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func makeRegistry() -> ExtensionRegistry {
        ExtensionRegistry(defaults: defaults, userExtensionsFolder: userExtensions)
    }

    func projectRoot() throws -> URL {
        let url = root.appendingPathComponent("Project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func writeQuickAction(
        folder: URL,
        id: String,
        name: String,
        actionID: String,
        actionTitle: String
    ) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = CribbleExtensionManifest(
            id: id,
            name: name,
            version: "0.1.0",
            kind: .quickAction,
            summary: "Test extension.",
            permissions: [.readCurrentNote],
            quickActions: [
                CribbleExtensionQuickAction(
                    id: actionID,
                    title: actionTitle,
                    icon: "bolt",
                    prompt: "Run \(actionTitle)."
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: folder.appendingPathComponent("cribble-extension.json"),
            options: .atomic
        )
    }

    func writeTrustedQuickAction(
        folder: URL,
        id: String,
        name: String
    ) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = CribbleExtensionManifest(
            id: id,
            name: name,
            version: "0.1.0",
            kind: .quickAction,
            summary: "Test trusted extension.",
            trust: CribbleExtensionTrustDeclaration(
                developerName: "Example Team",
                signingIdentifier: "\(id).signed",
                teamIdentifier: "ABCDE12345",
                sourceURL: URL(string: "https://example.com/source")!
            ),
            permissions: [.readCurrentNote],
            quickActions: [
                CribbleExtensionQuickAction(
                    id: "trusted-action",
                    title: "Trusted action",
                    icon: "bolt",
                    prompt: "Run trusted action."
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: folder.appendingPathComponent("cribble-extension.json"),
            options: .atomic
        )
    }

    func writeRenderer(
        folder: URL,
        id: String,
        name: String,
        languages: [String]
    ) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = CribbleExtensionManifest(
            id: id,
            name: name,
            version: "0.1.0",
            kind: .renderer,
            summary: "Test renderer.",
            renderers: [
                CribbleExtensionRenderer(
                    id: "diagram-aliases",
                    title: "Diagram Aliases",
                    languages: languages,
                    builtInRenderer: .mermaid
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: folder.appendingPathComponent("cribble-extension.json"),
            options: .atomic
        )
    }

    func writeImporter(
        folder: URL,
        id: String,
        name: String,
        importerTitle: String,
        fileExtensions: [String]
    ) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = CribbleExtensionManifest(
            id: id,
            name: name,
            version: "0.1.0",
            kind: .importer,
            summary: "Test importer.",
            importers: [
                CribbleExtensionImporter(
                    id: "chat-export",
                    title: importerTitle,
                    fileExtensions: fileExtensions,
                    outputFormat: "markdown"
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: folder.appendingPathComponent("cribble-extension.json"),
            options: .atomic
        )
    }
}
