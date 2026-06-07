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

enum CribbleExtensionPermission: String, Codable, CaseIterable, Identifiable {
    case readCurrentNote = "read-current-note"
    case readProjectNotes = "read-project-notes"
    case proposeFileChanges = "propose-file-changes"
    case networkOpenAICompatible = "network-openai-compatible"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readCurrentNote: "Read Current Note"
        case .readProjectNotes: "Read Project Notes"
        case .proposeFileChanges: "Propose File Changes"
        case .networkOpenAICompatible: "Network Runner"
        }
    }
}

struct CribbleExtensionManifest: Codable, Identifiable, Equatable {
    static let supportedAPIVersion = 1

    let apiVersion: Int
    let id: String
    let name: String
    let version: String
    let kind: CribbleExtensionKind
    let summary: String
    let entrypoint: String?
    let homepage: URL?
    let permissions: [CribbleExtensionPermission]
    let quickActions: [CribbleExtensionQuickAction]
    let intelligenceProviders: [CribbleExtensionIntelligenceProvider]

    enum CodingKeys: String, CodingKey {
        case apiVersion
        case id
        case name
        case version
        case kind
        case summary
        case entrypoint
        case homepage
        case permissions
        case quickActions
        case intelligenceProviders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decodeIfPresent(Int.self, forKey: .apiVersion) ?? Self.supportedAPIVersion
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        kind = try container.decode(CribbleExtensionKind.self, forKey: .kind)
        summary = try container.decode(String.self, forKey: .summary)
        entrypoint = try container.decodeIfPresent(String.self, forKey: .entrypoint)
        homepage = try container.decodeIfPresent(URL.self, forKey: .homepage)
        permissions = try container.decodeIfPresent([CribbleExtensionPermission].self, forKey: .permissions) ?? []
        quickActions = try container.decodeIfPresent([CribbleExtensionQuickAction].self, forKey: .quickActions) ?? []
        intelligenceProviders = try container.decodeIfPresent([CribbleExtensionIntelligenceProvider].self, forKey: .intelligenceProviders) ?? []
    }

    init(
        apiVersion: Int = Self.supportedAPIVersion,
        id: String,
        name: String,
        version: String,
        kind: CribbleExtensionKind,
        summary: String,
        entrypoint: String? = nil,
        homepage: URL? = nil,
        permissions: [CribbleExtensionPermission] = [],
        quickActions: [CribbleExtensionQuickAction] = [],
        intelligenceProviders: [CribbleExtensionIntelligenceProvider] = []
    ) {
        self.apiVersion = apiVersion
        self.id = id
        self.name = name
        self.version = version
        self.kind = kind
        self.summary = summary
        self.entrypoint = entrypoint
        self.homepage = homepage
        self.permissions = permissions
        self.quickActions = quickActions
        self.intelligenceProviders = intelligenceProviders
    }
}

struct CribbleExtensionQuickAction: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let prompt: String
}

struct CribbleExtensionIntelligenceProvider: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let baseURL: URL
    let modelID: String
    let embeddingModelID: String?
    let trustLabel: String?
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
    case unsupportedAPIVersion(Int)
    case missingRequiredField(String)
    case invalidID(String)
    case invalidEntrypoint(String)
    case invalidHomepage(String)
    case invalidContribution(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The manifest is not valid JSON."
        case .unsupportedAPIVersion(let version):
            return "Extension API version \(version) is not supported."
        case .missingRequiredField(let field):
            return "The manifest is missing \(field)."
        case .invalidID(let id):
            return "\(id) is not a reverse-DNS extension id."
        case .invalidEntrypoint(let entrypoint):
            return "\(entrypoint) must be a relative path inside the extension folder."
        case .invalidHomepage(let url):
            return "\(url) must be an http or https URL."
        case .invalidContribution(let message):
            return message
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
        if manifest.apiVersion != CribbleExtensionManifest.supportedAPIVersion {
            throw ExtensionManifestError.unsupportedAPIVersion(manifest.apiVersion)
        }
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
        if let homepage = manifest.homepage, !isHTTPURL(homepage) {
            throw ExtensionManifestError.invalidHomepage(homepage.absoluteString)
        }
        try validateQuickActions(manifest.quickActions, manifest: manifest)
        try validateIntelligenceProviders(manifest.intelligenceProviders, manifest: manifest)
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

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func validateQuickActions(
        _ actions: [CribbleExtensionQuickAction],
        manifest: CribbleExtensionManifest
    ) throws {
        guard actions.isEmpty || manifest.kind == .quickAction else {
            throw ExtensionManifestError.invalidContribution("Only quick-action extensions may declare quickActions.")
        }

        var seen: Set<String> = []
        for action in actions {
            if action.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Quick action id is required.")
            }
            if action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Quick action title is required.")
            }
            if action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Quick action prompt is required.")
            }
            if !seen.insert(action.id).inserted {
                throw ExtensionManifestError.invalidContribution("Quick action id \(action.id) is duplicated.")
            }
        }
    }

    private static func validateIntelligenceProviders(
        _ providers: [CribbleExtensionIntelligenceProvider],
        manifest: CribbleExtensionManifest
    ) throws {
        guard providers.isEmpty || manifest.kind == .intelligenceProvider else {
            throw ExtensionManifestError.invalidContribution("Only intelligence-provider extensions may declare intelligenceProviders.")
        }

        var seen: Set<String> = []
        for provider in providers {
            if provider.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Intelligence provider id is required.")
            }
            if provider.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Intelligence provider title is required.")
            }
            if !isHTTPURL(provider.baseURL) {
                throw ExtensionManifestError.invalidContribution("\(provider.baseURL.absoluteString) must be an http or https provider URL.")
            }
            if provider.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Intelligence provider modelID is required.")
            }
            if !seen.insert(provider.id).inserted {
                throw ExtensionManifestError.invalidContribution("Intelligence provider id \(provider.id) is duplicated.")
            }
        }
    }
}
