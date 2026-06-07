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
