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
          "trust": {
            "developerName": "Example Team",
            "signingIdentifier": "com.example.cribble.remote-runner",
            "teamIdentifier": "ABCDE12345",
            "sourceURL": "https://example.com/runner/source"
          },
          "permissions": ["network-openai-compatible"]
        }
        """
        try json.data(using: .utf8)?.write(to: url)

        let manifest = try ExtensionManifestLoader.load(from: url)

        #expect(manifest.id == "com.example.cribble.remote-runner")
        #expect(manifest.kind == .intelligenceProvider)
        #expect(manifest.runtime == .declarative)
        #expect(manifest.trust?.developerName == "Example Team")
        #expect(manifest.trust?.signingIdentifier == "com.example.cribble.remote-runner")
        #expect(manifest.trust?.teamIdentifier == "ABCDE12345")
        #expect(manifest.permissions == [.networkOpenAICompatible])
    }

    @Test
    func rejectsUnknownSecretKeysInJSON() throws {
        let url = try writeManifestJSON(
            folderName: "CribbleSecretKeyManifestTests",
            json: """
            {
              "apiVersion": 1,
              "id": "com.example.cribble.secret",
              "name": "Secret",
              "version": "0.1.0",
              "kind": "quick-action",
              "summary": "Attempts to hide a token.",
              "permissions": ["read-current-note"],
              "apiKey": "sk-should-not-live-here"
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(throws: ExtensionManifestError.invalidContribution("Manifest field manifest.apiKey looks like secret material. Store keys and tokens in Keychain, not extension manifests.")) {
            try ExtensionManifestLoader.load(from: url)
        }
    }

    @Test
    func rejectsSecretLikeStringValuesInJSON() throws {
        let url = try writeManifestJSON(
            folderName: "CribbleSecretValueManifestTests",
            json: """
            {
              "apiVersion": 1,
              "id": "com.example.cribble.runner",
              "name": "Runner",
              "version": "0.1.0",
              "kind": "intelligence-provider",
              "summary": "Attempts to put a token in the runner URL.",
              "permissions": ["network-openai-compatible"],
              "intelligenceProviders": [
                {
                  "id": "remote",
                  "title": "Remote",
                  "baseURL": "https://ai.example.com/v1?token=abcdef1234567890",
                  "modelID": "qwen3-32b"
                }
              ]
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(throws: ExtensionManifestError.invalidContribution("Manifest field manifest.intelligenceProviders[0].baseURL looks like it contains a key or token. Store secrets in Keychain, not extension manifests.")) {
            try ExtensionManifestLoader.load(from: url)
        }
    }

    @Test
    func validatesTrustDeclarations() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.trusted",
            name: "Trusted",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Declares future executable trust metadata.",
            trust: CribbleExtensionTrustDeclaration(
                developerName: "Example Team",
                signingIdentifier: "com.example.cribble.trusted",
                teamIdentifier: "ABCDE12345",
                sourceURL: URL(string: "https://example.com/source")!
            )
        )

        try ExtensionManifestLoader.validate(manifest)

        #expect(manifest.trust?.summary == "Example Team • com.example.cribble.trusted • Team ABCDE12345")
    }

    @Test
    func rejectsInvalidTrustDeclarations() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.trust",
            name: "Trust",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Declares invalid trust metadata.",
            trust: CribbleExtensionTrustDeclaration(
                developerName: "Example Team",
                signingIdentifier: "trusted",
                teamIdentifier: "bad-team",
                sourceURL: URL(string: "file:///tmp/source")!
            )
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Trust signingIdentifier must be a reverse-DNS bundle id.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func rejectsRemoteTrustSourceURLWithoutHTTPS() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.trust",
            name: "Trust",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Declares remote trust metadata.",
            trust: CribbleExtensionTrustDeclaration(
                developerName: "Example Team",
                signingIdentifier: "com.example.cribble.trust",
                teamIdentifier: "ABCDE12345",
                sourceURL: URL(string: "http://example.com/source")!
            )
        )

        #expect(throws: ExtensionManifestError.invalidContribution("http://example.com/source must be an https trust sourceURL unless it targets localhost.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func allowsLocalTrustSourceURLOverHTTP() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.trust",
            name: "Trust",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Declares local trust metadata.",
            trust: CribbleExtensionTrustDeclaration(
                developerName: "Example Team",
                signingIdentifier: "com.example.cribble.trust",
                teamIdentifier: "ABCDE12345",
                sourceURL: URL(string: "http://localhost:8080/source")!
            )
        )

        try ExtensionManifestLoader.validate(manifest)
    }

    @Test
    func loadsExplicitDeclarativeRuntime() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.declarative",
            name: "Declarative",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Declares data-only actions.",
            runtime: .declarative,
            permissions: [.readCurrentNote],
            quickActions: [
                CribbleExtensionQuickAction(
                    id: "plain-language",
                    title: "Plain language",
                    icon: "text.alignleft",
                    prompt: "Rewrite the current note in plain language."
                )
            ]
        )

        try ExtensionManifestLoader.validate(manifest)

        #expect(manifest.runtime.summary.contains("does not run extension code"))
        #expect(manifest.isValidForAPIV1Contributions)
    }

    @Test
    func rejectsQuickActionsWithoutCurrentNotePermission() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.actions",
            name: "Actions",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Declares actions without read access.",
            quickActions: [
                CribbleExtensionQuickAction(
                    id: "plain-language",
                    title: "Plain language",
                    icon: "text.alignleft",
                    prompt: "Rewrite the current note in plain language."
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Quick action extensions must request read-current-note.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func rejectsUnsafeQuickActionIDs() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.actions",
            name: "Actions",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Declares unsafe action ids.",
            permissions: [.readCurrentNote],
            quickActions: [
                CribbleExtensionQuickAction(
                    id: "../summarize",
                    title: "Summarize",
                    icon: "text.alignleft",
                    prompt: "Summarize the current note."
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Quick action id ../summarize is not valid.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func rejectsUnsupportedWritePermission() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.writer",
            name: "Writer",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Attempts to request file writes.",
            permissions: [.readCurrentNote, .proposeFileChanges],
            quickActions: [
                CribbleExtensionQuickAction(
                    id: "write-note",
                    title: "Write note",
                    icon: "square.and.pencil",
                    prompt: "Draft a source-note edit."
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("propose-file-changes is not supported by extension API version 1. Use Cribble's preview/review flows instead.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
        #expect(!manifest.isValidForAPIV1Contributions)
    }

    @Test
    func rejectsReservedProjectReadPermission() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.project-reader",
            name: "Project Reader",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Attempts to request project-wide note reads.",
            permissions: [.readCurrentNote, .readProjectNotes],
            quickActions: [
                CribbleExtensionQuickAction(
                    id: "project-summary",
                    title: "Project summary",
                    icon: "folder",
                    prompt: "Summarize the project notes."
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("read-project-notes is reserved for a future consented project-scope API.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
        #expect(!manifest.isValidForAPIV1Contributions)
    }

    @Test
    func rejectsExecutableRuntimeForCurrentAPI() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.executable",
            name: "Executable",
            version: "1.0.0",
            kind: .quickAction,
            summary: "Attempts to run extension code.",
            runtime: .executable,
            entrypoint: "dist/main.js"
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Executable extension runtimes are not supported by API version 1.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
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
    func rejectsProviderProfilesWithoutNetworkPermission() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.vps",
            name: "Team VPS",
            version: "0.1.0",
            kind: .intelligenceProvider,
            summary: "Adds a trusted OpenAI-compatible VPS runner.",
            intelligenceProviders: [
                CribbleExtensionIntelligenceProvider(
                    id: "research-gpu",
                    title: "Research GPU",
                    baseURL: URL(string: "https://ai.example.com/v1")!,
                    modelID: "qwen3-32b",
                    embeddingModelID: nil,
                    trustLabel: "Team-controlled VPS"
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Intelligence provider extensions must request network-openai-compatible.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func rejectsProviderProfilesWithNoteReadPermission() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.vps",
            name: "Team VPS",
            version: "0.1.0",
            kind: .intelligenceProvider,
            summary: "Adds a trusted OpenAI-compatible VPS runner.",
            permissions: [.networkOpenAICompatible, .readProjectNotes],
            intelligenceProviders: [
                CribbleExtensionIntelligenceProvider(
                    id: "research-gpu",
                    title: "Research GPU",
                    baseURL: URL(string: "https://ai.example.com/v1")!,
                    modelID: "qwen3-32b",
                    embeddingModelID: nil,
                    trustLabel: "Team-controlled VPS"
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("read-project-notes is reserved for a future consented project-scope API.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func rejectsRemoteProviderProfilesWithoutHTTPS() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.vps",
            name: "Team VPS",
            version: "0.1.0",
            kind: .intelligenceProvider,
            summary: "Adds a trusted OpenAI-compatible VPS runner.",
            permissions: [.networkOpenAICompatible],
            intelligenceProviders: [
                CribbleExtensionIntelligenceProvider(
                    id: "research-gpu",
                    title: "Research GPU",
                    baseURL: URL(string: "http://ai.example.com/v1")!,
                    modelID: "qwen3-32b",
                    embeddingModelID: nil,
                    trustLabel: "Team-controlled VPS"
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("http://ai.example.com/v1 must be an https provider URL unless it targets localhost.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
    }

    @Test
    func allowsLocalProviderProfilesOverHTTP() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.local",
            name: "Local Runner",
            version: "0.1.0",
            kind: .intelligenceProvider,
            summary: "Adds a local OpenAI-compatible runner.",
            permissions: [.networkOpenAICompatible],
            intelligenceProviders: [
                CribbleExtensionIntelligenceProvider(
                    id: "local",
                    title: "Local Runner",
                    baseURL: URL(string: "http://localhost:11434/v1")!,
                    modelID: "llama3.2",
                    embeddingModelID: nil,
                    trustLabel: "Localhost"
                )
            ]
        )

        try ExtensionManifestLoader.validate(manifest)
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
    func rejectsRendererPermissions() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.renderer",
            name: "Diagram aliases",
            version: "0.1.0",
            kind: .renderer,
            summary: "Maps extra diagram fences to built-in renderers.",
            permissions: [.readCurrentNote],
            renderers: [
                CribbleExtensionRenderer(
                    id: "flowcharts",
                    title: "Flowcharts",
                    languages: ["flowchart"],
                    builtInRenderer: .mermaid
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Renderer extensions cannot request permissions in API version 1.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
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
    func rejectsImporterPermissions() throws {
        let manifest = CribbleExtensionManifest(
            id: "com.example.cribble.importer",
            name: "Research Importers",
            version: "0.1.0",
            kind: .importer,
            summary: "Declares import lanes for future safe conversion.",
            permissions: [.readCurrentNote],
            importers: [
                CribbleExtensionImporter(
                    id: "chat-export",
                    title: "Chat Export",
                    fileExtensions: ["json"],
                    outputFormat: "markdown"
                )
            ]
        )

        #expect(throws: ExtensionManifestError.invalidContribution("Importer extensions cannot request permissions in API version 1.")) {
            try ExtensionManifestLoader.validate(manifest)
        }
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

private func writeManifestJSON(folderName: String, json: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(folderName)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("cribble-extension.json")
    try json.data(using: .utf8)?.write(to: url)
    return url
}
