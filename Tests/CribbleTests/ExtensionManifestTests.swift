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
            permissions: ["read-current-note"]
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
        #expect(manifest.permissions == ["network-openai-compatible"])
    }
}
