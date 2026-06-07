import Foundation
import Testing
@testable import Cribble

struct ExtensionManifestTests {
    @Test
    func validatesReverseDNSManifest() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.action",
            name: "Clip Summary",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Summarizes the selected note.",
            entrypoint: "dist/main.js",
            permissions: [.readCurrentNote]
        )

        try ExtensionManifestLoader.validate(manifest)
    }

    @Test
    func rejectsUnsafeEntrypoints() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.action",
            name: "Unsafe",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Attempts to escape the extension directory.",
            entrypoint: "../main.js"
        )

        #expect(throws: ExtensionManifestError.invalidEntrypoint("../main.js")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func loadsManifestFromJSON() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CribbleExtensionManifestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("cribble-extension.json")
        let json = """
        {
          "apiVersion": 1,
          "id": "com.example.cribble.remote-runner",
          "name": "Remote Runner",
          "version": "0.2.0",
          "kind": "intelligence-provider",
          "summary": "Connects Cribble to an OpenAI-compatible runner on a trusted host.",
          "entrypoint": "runner.json",
          "permissions": ["network-openai-compatible"]
        }
        """
        try json.data(using: .utf8)?.write(to: url)

        let manifest = try ExtensionManifestLoader.load(from: url)

        #expect(manifest.id == "com.example.cribble.remote-runner")
        #expect(manifest.kind == .intelligenceProvider)
        #expect(manifest.permissions == [.networkOpenAICompatible])
    }

    @Test
    func loadsQuickActionContributions() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CribbleQuickActionManifestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("cribble-extension.json")
        let json = """
        {
          "apiVersion": 1,
          "id": "com.example.cribble.actions",
          "name": "Research Actions",
          "version": "0.1.0",
          "kind": "quick-action",
          "summary": "Adds research-oriented chat prompts.",
          "permissions": ["read-current-note"],
          "quickActions": [
            {
              "id": "extract-claims",
              "title": "Extract claims",
              "icon": "checklist",
              "prompt": "Extract the factual claims from the current note."
            }
          ]
        }
        """
        try json.data(using: .utf8)?.write(to: url)

        let manifest = try ExtensionManifestLoader.load(from: url)

        #expect(manifest.quickActions.count == 1)
        #expect(manifest.quickActions.first?.id == "extract-claims")
        #expect(manifest.quickActions.first?.prompt.contains("factual claims") == true)
    }

    @Test
    func rejectsQuickActionsOnWrongKind() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.renderer",
            name: "Renderer",
            version: "1.0.0",
            kind: .renderer,
            summary: "Tries to declare chat actions from a renderer.",
            quickActions: [
                CribbleExtensionQuickAction(
                    id: "wrong-place",
                    title: "Wrong place",
                    icon: "xmark",
                    prompt: "This should not be allowed."
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Only quick-action extensions may declare quickActions.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func rejectsUnsupportedAPIVersion() throws {
        let manifest = CribbleExtensionManifest(
            apiVersion: 99,
            id: "com.example.cribble.future",
            name: "Future",
            version: "9.0.0",
            kind: .renderer,
            summary: "Uses a future extension API."
        )

        #expect(throws: ExtensionManifestError.unsupportedAPIVersion(99)) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func rejectsNonHTTPHomepage() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.homepage",
            name: "Homepage",
            version: "1.0.0",
            kind: .importer,
            summary: "Has an unsafe homepage scheme.",
            homepage: URL(string: "file:///tmp/readme")!
        )

        #expect(throws: ExtensionManifestError.invalidHomepage("file:///tmp/readme")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }
}
