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
}
