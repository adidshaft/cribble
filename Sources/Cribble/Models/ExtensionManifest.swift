import Foundation

enum CribbleExtensionKind: String, Codable, CaseIterable, Identifiable {
    case quickAction = "quick-action"
    case intelligenceProvider = "intelligence-provider"
    case renderer = "renderer"
    case importer = "importer"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickAction: "Quick Action"
        case .intelligenceProvider: "Intelligence Provider"
        case .renderer: "Renderer"
        case .importer: "Importer"
        }
    }
}

struct CribbleExtensionManifest: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let version: String
    let kind: CribbleExtensionKind
    let summary: String
    let entrypoint: String?
    let homepage: URL?
    let permissions: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case kind
        case summary
        case entrypoint
        case homepage
        case permissions
    }

    init(
        id: String,
        name: String,
        version: String,
        kind: CribbleExtensionKind,
        summary: String,
        entrypoint: String? = nil,
        homepage: URL? = nil,
        permissions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.kind = kind
        self.summary = summary
        self.entrypoint = entrypoint
        self.homepage = homepage
        self.permissions = permissions
    }
}

struct InstalledCribbleExtension: Identifiable, Equatable {
    enum Location: Equatable {
        case user
        case project(URL)

        var title: String {
            switch self {
            case .user: "User"
            case .project(let url): url.lastPathComponent
            }
        }
    }

    let manifest: CribbleExtensionManifest
    let manifestURL: URL
    let location: Location

    var id: String { "\(manifest.id)|\(manifestURL.path)" }
}

enum ExtensionManifestError: LocalizedError, Equatable {
    case unreadable
    case missingRequiredField(String)
    case invalidID(String)
    case invalidEntrypoint(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The manifest is not valid JSON."
        case .missingRequiredField(let field):
            return "The manifest is missing \(field)."
        case .invalidID(let id):
            return "\(id) is not a reverse-DNS extension id."
        case .invalidEntrypoint(let entrypoint):
            return "\(entrypoint) must be a relative path inside the extension folder."
        }
    }
}

enum ExtensionManifestLoader {
    static func load(from url: URL) throws -> CribbleExtensionManifest {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        guard let manifest = try? decoder.decode(CribbleExtensionManifest.self, from: data) else {
            throw ExtensionManifestError.unreadable
        }
        try validate(manifest)
        return manifest
    }

    static func validate(_ manifest: CribbleExtensionManifest) throws {
        if manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExtensionManifestError.missingRequiredField("id")
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExtensionManifestError.missingRequiredField("name")
        }
        if manifest.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExtensionManifestError.missingRequiredField("summary")
        }
        if !isReverseDNS(manifest.id) {
            throw ExtensionManifestError.invalidID(manifest.id)
        }
        if let entrypoint = manifest.entrypoint, !isSafeRelativePath(entrypoint) {
            throw ExtensionManifestError.invalidEntrypoint(entrypoint)
        }
    }

    private static func isReverseDNS(_ id: String) -> Bool {
        let parts = id.split(separator: ".")
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            part.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]*$"#, options: .regularExpression) != nil
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("..")
        else { return false }
        return URL(fileURLWithPath: path).pathComponents.allSatisfy { $0 != ".." }
    }
}
