import AppKit
import Foundation

@MainActor
final class ExtensionRegistry: ObservableObject {
    @Published private(set) var installedExtensions: [InstalledCribbleExtension] = []
    @Published private(set) var loadWarnings: [String] = []
    @Published var disabledExtensionIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(disabledExtensionIDs), forKey: Keys.disabledExtensionIDs) }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        disabledExtensionIDs = Set(UserDefaults.standard.stringArray(forKey: Keys.disabledExtensionIDs) ?? [])
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

    func reload(projectRoots: [URL]) {
        var loaded: [InstalledCribbleExtension] = []
        var warnings: [String] = []

        scan(folder: Self.userExtensionsFolder, location: .user, into: &loaded, warnings: &warnings)
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
        try? fileManager.createDirectory(at: Self.userExtensionsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([Self.userExtensionsFolder])
    }

    func writeExampleManifest() throws -> URL {
        let exampleFolder = Self.userExtensionsFolder.appendingPathComponent("example-quick-action", isDirectory: true)
        try fileManager.createDirectory(at: exampleFolder, withIntermediateDirectories: true)
        let manifestURL = exampleFolder.appendingPathComponent("cribble-extension.json")
        if !fileManager.fileExists(atPath: manifestURL.path) {
            let example = CribbleExtensionManifest(
                id: "com.example.cribble.quick-action",
                name: "Example Quick Action",
                version: "0.1.0",
                kind: .quickAction,
                summary: "Adds a user-authored action to Cribble's future extension command surface.",
                entrypoint: "main.js",
                homepage: URL(string: "https://example.com/cribble-extension"),
                permissions: [.readCurrentNote]
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

    static var userExtensionsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Cribble/Extensions", isDirectory: true)
    }

    private enum Keys {
        static let disabledExtensionIDs = "extensions.disabledIDs"
    }
}
