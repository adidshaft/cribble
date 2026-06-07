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

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        userExtensionsFolder: URL = ExtensionRegistry.defaultUserExtensionsFolder
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.userExtensionsFolder = userExtensionsFolder
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

    func writeExampleManifest() throws -> URL {
        let exampleFolder = userExtensionsFolder.appendingPathComponent("example-quick-action", isDirectory: true)
        try fileManager.createDirectory(at: exampleFolder, withIntermediateDirectories: true)
        let manifestURL = exampleFolder.appendingPathComponent("cribble-extension.json")
        if !fileManager.fileExists(atPath: manifestURL.path) {
            let example = CribbleExtensionManifest(
                id: "com.example.cribble.quick-action",
                name: "Example Quick Action",
                version: "0.1.0",
                kind: .quickAction,
                summary: "Adds a user-authored action to Cribble's future extension command surface.",
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(example).write(to: manifestURL, options: .atomic)
        }
        reload(projectRoots: [])
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
