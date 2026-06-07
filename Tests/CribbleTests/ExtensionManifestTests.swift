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

    @Test
    func loadsIntelligenceProviderProfiles() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CribbleProviderManifestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("cribble-extension.json")
        let json = """
        {
          "apiVersion": 1,
          "id": "com.example.cribble.vps",
          "name": "Team VPS",
          "version": "0.1.0",
          "kind": "intelligence-provider",
          "summary": "Adds a trusted OpenAI-compatible VPS runner.",
          "permissions": ["network-openai-compatible"],
          "intelligenceProviders": [
            {
              "id": "research-gpu",
              "title": "Research GPU",
              "baseURL": "https://ai.example.com/v1",
              "modelID": "qwen3-32b",
              "embeddingModelID": "text-embedding-3-small",
              "trustLabel": "Team-controlled VPS"
            }
          ]
        }
        """
        try json.data(using: .utf8)?.write(to: url)

        let manifest = try ExtensionManifestLoader.load(from: url)

        #expect(manifest.intelligenceProviders.count == 1)
        #expect(manifest.intelligenceProviders.first?.baseURL.absoluteString == "https://ai.example.com/v1")
        #expect(manifest.intelligenceProviders.first?.modelID == "qwen3-32b")
    }

    @Test
    func rejectsProviderProfilesOnWrongKind() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.actions",
            name: "Actions",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Tries to declare providers from a quick-action extension.",
            intelligenceProviders: [
                CribbleExtensionIntelligenceProvider(
                    id: "wrong-place",
                    title: "Wrong place",
                    baseURL: URL(string: "https://ai.example.com/v1")!,
                    modelID: "qwen3",
                    embeddingModelID: nil,
                    trustLabel: nil
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Only intelligence-provider extensions may declare intelligenceProviders.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func loadsRendererContributions() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.renderer",
            name: "Diagram aliases",
            version: "0.1.0",
            kind: .renderer,
            summary: "Maps extra diagram fences to built-in renderers.",
            renderers: [
                CribbleExtensionRenderer(
                    id: "flowcharts",
                    title: "Flowcharts",
                    languages: ["flowchart", "workflow"],
                    builtInRenderer: .mermaid
                )
            ]
        )

        try ExtensionManifestLoader.validate(manifest)

        #expect(manifest.renderers.first?.builtInRenderer == .mermaid)
        #expect(manifest.renderers.first?.languages == ["flowchart", "workflow"])
    }

    @Test
    func rejectsRenderersOnWrongKind() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.actions",
            name: "Actions",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Tries to declare renderers from a quick-action extension.",
            renderers: [
                CribbleExtensionRenderer(
                    id: "wrong-place",
                    title: "Wrong place",
                    languages: ["diagram"],
                    builtInRenderer: .mermaid
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Only renderer extensions may declare renderers.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func loadsImporterContributions() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.importer",
            name: "Research Importers",
            version: "0.1.0",
            kind: .importer,
            summary: "Declares import lanes for future safe conversion.",
            importers: [
                CribbleExtensionImporter(
                    id: "chat-export",
                    title: "Chat Export",
                    fileExtensions: ["json", "txt"],
                    outputFormat: "markdown"
                )
            ]
        )

        try ExtensionManifestLoader.validate(manifest)

        #expect(manifest.importers.first?.fileExtensions == ["json", "txt"])
        #expect(manifest.importers.first?.outputFormat == "markdown")
    }

    @Test
    func rejectsImportersOnWrongKind() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.renderer",
            name: "Renderer",
            version: "1.0.0",
            kind: .renderer,
            summary: "Tries to declare importers from a renderer extension.",
            importers: [
                CribbleExtensionImporter(
                    id: "wrong-place",
                    title: "Wrong place",
                    fileExtensions: ["json"],
                    outputFormat: "markdown"
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Only importer extensions may declare importers.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }
}
