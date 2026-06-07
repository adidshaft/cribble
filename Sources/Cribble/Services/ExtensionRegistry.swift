import AppKit
import Foundation

@MainActor
final class ExtensionRegistry: ObservableObject {
    @Published private(set) var installedExtensions: [InstalledCribbleExtension] = []
    @Published private(set) var loadWarnings: [String] = []
    @Published var disabledExtensionIDs: Set<String> {
        didSet { defaults.set(Array(disabledExtensionIDs), forKey: Keys.disabledExtensionIDs) }
    }

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let userExtensionsFolder: URL
    private let trustDecisionStore: ExtensionTrustDecisionStore

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        userExtensionsFolder: URL = ExtensionRegistry.defaultUserExtensionsFolder,
        trustDecisionStore: ExtensionTrustDecisionStore? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.userExtensionsFolder = userExtensionsFolder
        self.trustDecisionStore = trustDecisionStore ?? ExtensionTrustDecisionStore(defaults: defaults)
        disabledExtensionIDs = Set(defaults.stringArray(forKey: Keys.disabledExtensionIDs) ?? [])
        reload(projectRoots: [])
    }

    func isEnabled(_ installed: InstalledCribbleExtension) -> Bool {
        !disabledExtensionIDs.contains(installed.manifest.id)
    }

    func setEnabled(_ enabled: Bool, for installed: InstalledCribbleExtension) {
        if enabled {
            disabledExtensionIDs.remove(installed.manifest.id)
        } else {
            disabledExtensionIDs.insert(installed.manifest.id)
        }
    }

    func trustDecision(for installed: InstalledCribbleExtension) -> ExtensionTrustDecision? {
        trustDecisionStore.decision(for: installed.manifest)
    }

    func revokeTrust(for installed: InstalledCribbleExtension) {
        trustDecisionStore.revoke(installed.manifest)
    }

    func clearTrustDecision(for installed: InstalledCribbleExtension) {
        trustDecisionStore.clearDecision(for: installed.manifest)
    }

    var quickActions: [QuickAction] {
        installedExtensions
            .filter { isEnabled($0) && $0.manifest.kind == .quickAction }
            .flatMap { installed in
                installed.manifest.quickActions.map { contribution in
                    QuickAction(
                        id: "\(installed.manifest.id).\(contribution.id)",
                        title: contribution.title,
                        icon: contribution.icon,
                        prompt: contribution.prompt,
                        source: .extension(installed.manifest.name)
                    )
                }
            }
    }

    var intelligenceProviderProfiles: [ExtensionIntelligenceProviderProfile] {
        installedExtensions
            .filter { isEnabled($0) && $0.manifest.kind == .intelligenceProvider }
            .flatMap { installed in
                installed.manifest.intelligenceProviders.map { provider in
                    ExtensionIntelligenceProviderProfile(
                        id: "\(installed.manifest.id).\(provider.id)",
                        title: provider.title,
                        baseURL: provider.baseURL,
                        modelID: provider.modelID,
                        embeddingModelID: provider.embeddingModelID,
                        trustLabel: provider.trustLabel ?? installed.manifest.name,
                        sourceName: installed.manifest.name
                    )
                }
            }
    }

    var rendererResolver: ExtensionRendererResolver {
        ExtensionRendererResolver(
            renderers: installedExtensions
                .filter { isEnabled($0) && $0.manifest.kind == .renderer }
                .flatMap(\.manifest.renderers)
        )
    }

    var importerCapabilities: [ExtensionImporterCapability] {
        installedExtensions
            .filter { isEnabled($0) && $0.manifest.kind == .importer }
            .flatMap { installed in
                installed.manifest.importers.map { importer in
                    ExtensionImporterCapability(
                        id: "\(installed.manifest.id).\(importer.id)",
                        title: importer.title,
                        fileExtensions: importer.fileExtensions.map { $0.lowercased() }.sorted(),
                        outputFormat: importer.outputFormat,
                        sourceName: installed.manifest.name
                    )
                }
            }
            .sorted {
                if $0.title == $1.title {
                    return $0.sourceName.localizedCaseInsensitiveCompare($1.sourceName) == .orderedAscending
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    func reload(projectRoots: [URL]) {
        var loaded: [InstalledCribbleExtension] = []
        var warnings: [String] = []

        scan(folder: userExtensionsFolder, location: .user, into: &loaded, warnings: &warnings)
        for root in projectRoots {
            let folder = root.appendingPathComponent(".cribble/extensions", isDirectory: true)
            scan(folder: folder, location: .project(root), into: &loaded, warnings: &warnings)
        }

        let deduped = deduplicate(loaded, warnings: &warnings)
        installedExtensions = deduped.sorted {
            if $0.manifest.kind.title == $1.manifest.kind.title {
                return $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending
            }
            return $0.manifest.kind.title < $1.manifest.kind.title
        }
        trustDecisionStore.prune(toInstalledManifests: installedExtensions.map(\.manifest))
        loadWarnings = warnings
    }

    private func deduplicate(
        _ extensions: [InstalledCribbleExtension],
        warnings: inout [String]
    ) -> [InstalledCribbleExtension] {
        var byID: [String: InstalledCribbleExtension] = [:]
        for installed in extensions {
            if let existing = byID[installed.manifest.id] {
                if shouldPrefer(installed, over: existing) {
                    byID[installed.manifest.id] = installed
                }
                warnings.append("Duplicate extension id \(installed.manifest.id); using \(byID[installed.manifest.id]?.location.title ?? existing.location.title).")
            } else {
                byID[installed.manifest.id] = installed
            }
        }
        return Array(byID.values)
    }

    private func shouldPrefer(_ candidate: InstalledCribbleExtension, over existing: InstalledCribbleExtension) -> Bool {
        switch (candidate.location, existing.location) {
        case (.project, .user): true
        case (.user, .project): false
        default:
            candidate.manifestURL.path.localizedCaseInsensitiveCompare(existing.manifestURL.path) == .orderedAscending
        }
    }

    func revealUserExtensionsFolder() {
        try? fileManager.createDirectory(at: userExtensionsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([userExtensionsFolder])
    }

    func reveal(_ installed: InstalledCribbleExtension) {
        NSWorkspace.shared.activateFileViewerSelecting([installed.manifestURL])
    }

    func writeExampleManifest(template: ExtensionExampleTemplate = .quickAction) throws -> URL {
        let exampleFolder = userExtensionsFolder.appendingPathComponent(template.folderName, isDirectory: true)
        let manifestURL = try writeExampleManifest(template: template, to: exampleFolder)
        reload(projectRoots: [])
        return manifestURL
    }

    func writeProjectExampleManifest(template: ExtensionExampleTemplate, projectRoot: URL) throws -> URL {
        let exampleFolder = projectRoot.standardizedFileURL
            .appendingPathComponent(".cribble/extensions", isDirectory: true)
            .appendingPathComponent(template.folderName, isDirectory: true)
        return try writeExampleManifest(template: template, to: exampleFolder)
    }

    private func writeExampleManifest(template: ExtensionExampleTemplate, to exampleFolder: URL) throws -> URL {
        try fileManager.createDirectory(at: exampleFolder, withIntermediateDirectories: true)
        let manifestURL = exampleFolder.appendingPathComponent("cribble-extension.json")
        if !fileManager.fileExists(atPath: manifestURL.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(template.manifest).write(to: manifestURL, options: .atomic)
        }
        return manifestURL
    }

    private func scan(
        folder: URL,
        location: InstalledCribbleExtension.Location,
        into loaded: inout [InstalledCribbleExtension],
        warnings: inout [String]
    ) {
        guard let children = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for child in children {
            let manifestURL = child.appendingPathComponent("cribble-extension.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let manifest = try ExtensionManifestLoader.load(from: manifestURL)
                loaded.append(InstalledCribbleExtension(manifest: manifest, manifestURL: manifestURL, location: location))
            } catch {
                warnings.append("\(child.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    static var defaultUserExtensionsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Cribble/Extensions", isDirectory: true)
    }

    static var userExtensionsFolder: URL { defaultUserExtensionsFolder }

    private enum Keys {
        static let disabledExtensionIDs = "extensions.disabledIDs"
    }
}

enum ExtensionExampleTemplate: String, CaseIterable, Identifiable {
    case quickAction
    case intelligenceProvider
    case renderer
    case importer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickAction: "Quick Action"
        case .intelligenceProvider: "Remote Runner"
        case .renderer: "Renderer Alias"
        case .importer: "Import Lane"
        }
    }

    var folderName: String {
        switch self {
        case .quickAction: "example-quick-action"
        case .intelligenceProvider: "example-remote-runner"
        case .renderer: "example-renderer-alias"
        case .importer: "example-import-lane"
        }
    }

    var manifest: CribbleExtensionManifest {
        switch self {
        case .quickAction:
            return CribbleExtensionManifest(
                id: "com.example.cribble.quick-action",
                name: "Example Quick Action",
                version: "0.1.0",
                kind: .quickAction,
                summary: "Adds a user-authored action to Cribble's chat command surface.",
                runtime: .declarative,
                homepage: URL(string: "https://example.com/cribble-extension"),
                permissions: [.readCurrentNote],
                quickActions: [
                    CribbleExtensionQuickAction(
                        id: "explain-jargon",
                        title: "Explain jargon",
                        icon: "text.magnifyingglass",
                        prompt: "Explain the specialized terms in the current note in plain language."
                    )
                ]
            )
        case .intelligenceProvider:
            return CribbleExtensionManifest(
                id: "com.example.cribble.team-runner",
                name: "Example Team Runner",
                version: "0.1.0",
                kind: .intelligenceProvider,
                summary: "Adds a trusted OpenAI-compatible runner preset.",
                runtime: .declarative,
                homepage: URL(string: "https://example.com/cribble-runner"),
                trust: CribbleExtensionTrustDeclaration(
                    developerName: "Example Team",
                    signingIdentifier: "com.example.cribble.team-runner",
                    teamIdentifier: "ABCDE12345",
                    sourceURL: URL(string: "https://example.com/cribble-runner/source")
                ),
                permissions: [.networkOpenAICompatible],
                intelligenceProviders: [
                    CribbleExtensionIntelligenceProvider(
                        id: "research-gpu",
                        title: "Research GPU",
                        baseURL: URL(string: "https://ai.example.com/v1")!,
                        modelID: "qwen3-32b",
                        embeddingModelID: "text-embedding-3-small",
                        trustLabel: "Team-controlled VPS"
                    )
                ]
            )
        case .renderer:
            return CribbleExtensionManifest(
                id: "com.example.cribble.diagram-aliases",
                name: "Example Diagram Aliases",
                version: "0.1.0",
                kind: .renderer,
                summary: "Maps team diagram fence names to built-in renderers.",
                runtime: .declarative,
                renderers: [
                    CribbleExtensionRenderer(
                        id: "workflow-diagrams",
                        title: "Workflow Diagrams",
                        languages: ["workflow", "flowchart"],
                        builtInRenderer: .mermaid
                    )
                ]
            )
        case .importer:
            return CribbleExtensionManifest(
                id: "com.example.cribble.chat-importers",
                name: "Example Chat Importers",
                version: "0.1.0",
                kind: .importer,
                summary: "Declares chat export files Cribble could convert later.",
                runtime: .declarative,
                importers: [
                    CribbleExtensionImporter(
                        id: "chat-export",
                        title: "Chat Export",
                        fileExtensions: ["json", "txt"],
                        outputFormat: "markdown"
                    )
                ]
            )
        }
    }
}

struct ExtensionImporterCapability: Identifiable, Equatable {
    let id: String
    let title: String
    let fileExtensions: [String]
    let outputFormat: String
    let sourceName: String

    var extensionSummary: String {
        fileExtensions.map { ".\($0)" }.joined(separator: ", ")
    }
}

struct ExtensionRendererResolver: Equatable {
    static let empty = ExtensionRendererResolver(renderers: [])

    private let aliases: [String: CribbleExtensionRenderer.BuiltInRenderer]

    init(renderers: [CribbleExtensionRenderer]) {
        var aliases: [String: CribbleExtensionRenderer.BuiltInRenderer] = [:]
        for renderer in renderers {
            for language in renderer.languages {
                aliases[Self.normalize(language)] = renderer.builtInRenderer
            }
        }
        self.aliases = aliases
    }

    func resolvedLanguage(for language: String?) -> String? {
        guard let language else { return nil }
        let normalized = Self.normalize(language)
        guard !normalized.isEmpty else { return nil }
        return aliases[normalized]?.rawValue ?? normalized
    }

    func resolves(_ language: String?, to renderer: CribbleExtensionRenderer.BuiltInRenderer) -> Bool {
        guard let language else { return false }
        return aliases[Self.normalize(language)] == renderer
    }

    private static func normalize(_ language: String) -> String {
        language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
