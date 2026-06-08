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

enum CribbleExtensionRuntime: String, Codable, CaseIterable, Identifiable {
    case declarative
    case executable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .declarative: "Declarative"
        case .executable: "Executable"
        }
    }

    var summary: String {
        switch self {
        case .declarative: "Manifest data only; Cribble does not run extension code."
        case .executable: "Would require explicit trust before Cribble can run extension code."
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
    let runtime: CribbleExtensionRuntime
    let entrypoint: String?
    let homepage: URL?
    let trust: CribbleExtensionTrustDeclaration?
    let permissions: [CribbleExtensionPermission]
    let quickActions: [CribbleExtensionQuickAction]
    let intelligenceProviders: [CribbleExtensionIntelligenceProvider]
    let renderers: [CribbleExtensionRenderer]
    let importers: [CribbleExtensionImporter]

    enum CodingKeys: String, CodingKey {
        case apiVersion
        case id
        case name
        case version
        case kind
        case summary
        case runtime
        case entrypoint
        case homepage
        case trust
        case permissions
        case quickActions
        case intelligenceProviders
        case renderers
        case importers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decodeIfPresent(Int.self, forKey: .apiVersion) ?? Self.supportedAPIVersion
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        kind = try container.decode(CribbleExtensionKind.self, forKey: .kind)
        summary = try container.decode(String.self, forKey: .summary)
        runtime = try container.decodeIfPresent(CribbleExtensionRuntime.self, forKey: .runtime) ?? .declarative
        entrypoint = try container.decodeIfPresent(String.self, forKey: .entrypoint)
        homepage = try container.decodeIfPresent(URL.self, forKey: .homepage)
        trust = try container.decodeIfPresent(CribbleExtensionTrustDeclaration.self, forKey: .trust)
        permissions = try container.decodeIfPresent([CribbleExtensionPermission].self, forKey: .permissions) ?? []
        quickActions = try container.decodeIfPresent([CribbleExtensionQuickAction].self, forKey: .quickActions) ?? []
        intelligenceProviders = try container.decodeIfPresent([CribbleExtensionIntelligenceProvider].self, forKey: .intelligenceProviders) ?? []
        renderers = try container.decodeIfPresent([CribbleExtensionRenderer].self, forKey: .renderers) ?? []
        importers = try container.decodeIfPresent([CribbleExtensionImporter].self, forKey: .importers) ?? []
    }

    init(
        apiVersion: Int = Self.supportedAPIVersion,
        id: String,
        name: String,
        version: String,
        kind: CribbleExtensionKind,
        summary: String,
        runtime: CribbleExtensionRuntime = .declarative,
        entrypoint: String? = nil,
        homepage: URL? = nil,
        trust: CribbleExtensionTrustDeclaration? = nil,
        permissions: [CribbleExtensionPermission] = [],
        quickActions: [CribbleExtensionQuickAction] = [],
        intelligenceProviders: [CribbleExtensionIntelligenceProvider] = [],
        renderers: [CribbleExtensionRenderer] = [],
        importers: [CribbleExtensionImporter] = []
    ) {
        self.apiVersion = apiVersion
        self.id = id
        self.name = name
        self.version = version
        self.kind = kind
        self.summary = summary
        self.runtime = runtime
        self.entrypoint = entrypoint
        self.homepage = homepage
        self.trust = trust
        self.permissions = permissions
        self.quickActions = quickActions
        self.intelligenceProviders = intelligenceProviders
        self.renderers = renderers
        self.importers = importers
    }

    var isValidForAPIV1Contributions: Bool {
        (try? ExtensionManifestLoader.validate(self)) != nil
    }
}

struct CribbleExtensionTrustDeclaration: Codable, Equatable {
    let developerName: String
    let signingIdentifier: String
    let teamIdentifier: String?
    let sourceURL: URL?

    var summary: String {
        if let teamIdentifier, !teamIdentifier.isEmpty {
            return "\(developerName) • \(signingIdentifier) • Team \(teamIdentifier)"
        }
        return "\(developerName) • \(signingIdentifier)"
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

struct CribbleExtensionRenderer: Codable, Identifiable, Equatable {
    enum BuiltInRenderer: String, Codable {
        case mermaid
        case graphviz
        case chart
        case math
        case markdown
    }

    let id: String
    let title: String
    let languages: [String]
    let builtInRenderer: BuiltInRenderer
}

struct CribbleExtensionImporter: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let fileExtensions: [String]
    let outputFormat: String
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

    var reviewSummary: String {
        var lines = [
            "Cribble Extension",
            "Name: \(manifest.name)",
            "ID: \(manifest.id)",
            "Version: \(manifest.version)",
            "Kind: \(manifest.kind.title)",
            "Runtime: \(manifest.runtime.title)",
            "Location: \(location.title)",
            "Manifest: \(manifestURL.path)",
            "Summary: \(manifest.summary)"
        ]

        if !manifest.permissions.isEmpty {
            lines.append("Permissions: \(manifest.permissions.map(\.title).joined(separator: ", "))")
        }

        if let trust = manifest.trust {
            lines.append("Trust: \(trust.summary)")
            if let sourceURL = trust.sourceURL {
                lines.append("Source: \(sourceURL.absoluteString)")
            }
        }

        if !manifest.quickActions.isEmpty {
            lines.append("Quick actions: \(manifest.quickActions.map(\.title).joined(separator: ", "))")
        }
        if !manifest.intelligenceProviders.isEmpty {
            lines.append("Providers: \(manifest.intelligenceProviders.map { "\($0.title) (\($0.modelID))" }.joined(separator: ", "))")
        }
        if !manifest.renderers.isEmpty {
            lines.append("Renderers: \(manifest.renderers.map { "\($0.title) [\($0.languages.joined(separator: ", "))]" }.joined(separator: ", "))")
        }
        if !manifest.importers.isEmpty {
            lines.append("Importers: \(manifest.importers.map { "\($0.title) [\($0.fileExtensions.joined(separator: ", "))]" }.joined(separator: ", "))")
        }

        lines.append(contentsOf: ExtensionReviewChecklist.manifestSummaryLines)

        return lines.joined(separator: "\n")
    }
}

enum ExtensionReviewChecklist {
    static let contributionGuidePath = "docs/extension-contributions.md"
    static let manifestReferencePath = "docs/extensions.md"

    static let manifestSummaryLines = [
        "Safety contract:",
        "- Read-only first; API v1 is declarative manifest data and does not run extension code.",
        "- Least reading: prefer Read Current Note; justify project-wide reads.",
        "- Least writing: source-note edits must go through explicit preview/review, and first versions should avoid note writes.",
        "- Network: remote runners must be explicit OpenAI-compatible endpoints with user-visible trust labels.",
        "- Secrets: never put keys or tokens in manifests, fixtures, docs, or extension folders; use Keychain-backed app flows.",
        "- Disable behavior: turning the extension off must remove its commands, renderers, import lanes, or provider profiles.",
        "- UI: contribution UI must use native SwiftUI, Settings, sheets, menus, commands, toolbars, and system symbols.",
        "Contributor guide: \(contributionGuidePath)",
        "Manifest reference: \(manifestReferencePath)"
    ]
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
        try validateNoSecretMaterial(in: data)
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
        try validateTrust(manifest.trust)
        if manifest.runtime == .executable {
            throw ExtensionManifestError.invalidContribution("Executable extension runtimes are not supported by API version \(CribbleExtensionManifest.supportedAPIVersion).")
        }
        try validatePermissions(manifest.permissions, manifest: manifest)
        try validateQuickActions(manifest.quickActions, manifest: manifest)
        try validateIntelligenceProviders(manifest.intelligenceProviders, manifest: manifest)
        try validateRenderers(manifest.renderers, manifest: manifest)
        try validateImporters(manifest.importers, manifest: manifest)
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

    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasSuffix(".localhost")
    }

    private static func isSecureProviderURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        if scheme == "http", isLoopbackHost(url.host) { return true }
        return false
    }

    private static func validatePermissions(
        _ permissions: [CribbleExtensionPermission],
        manifest: CribbleExtensionManifest
    ) throws {
        if permissions.contains(.proposeFileChanges) {
            throw ExtensionManifestError.invalidContribution("propose-file-changes is not supported by extension API version \(CribbleExtensionManifest.supportedAPIVersion). Use Cribble's preview/review flows instead.")
        }
        if permissions.contains(.readProjectNotes) {
            throw ExtensionManifestError.invalidContribution("read-project-notes is reserved for a future consented project-scope API.")
        }

        let permissionSet = Set(permissions)
        switch manifest.kind {
        case .quickAction:
            if !manifest.quickActions.isEmpty,
               !permissionSet.contains(.readCurrentNote) {
                throw ExtensionManifestError.invalidContribution("Quick action extensions must request read-current-note.")
            }
            if permissions.contains(where: { $0 != .readCurrentNote }) {
                throw ExtensionManifestError.invalidContribution("Quick action extensions may only request read-current-note in API version \(CribbleExtensionManifest.supportedAPIVersion).")
            }
            if permissionSet.contains(.networkOpenAICompatible) {
                throw ExtensionManifestError.invalidContribution("Quick action extensions cannot request network-openai-compatible.")
            }
        case .intelligenceProvider:
            if !manifest.intelligenceProviders.isEmpty,
               !permissionSet.contains(.networkOpenAICompatible) {
                throw ExtensionManifestError.invalidContribution("Intelligence provider extensions must request network-openai-compatible.")
            }
            if permissionSet.contains(.readCurrentNote) || permissionSet.contains(.readProjectNotes) {
                throw ExtensionManifestError.invalidContribution("Intelligence provider extensions cannot request note-read permissions in API version \(CribbleExtensionManifest.supportedAPIVersion).")
            }
        case .renderer:
            if !permissions.isEmpty {
                throw ExtensionManifestError.invalidContribution("Renderer extensions cannot request permissions in API version \(CribbleExtensionManifest.supportedAPIVersion).")
            }
        case .importer:
            if !permissions.isEmpty {
                throw ExtensionManifestError.invalidContribution("Importer extensions cannot request permissions in API version \(CribbleExtensionManifest.supportedAPIVersion).")
            }
        }
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
            try validateContributionID(action.id, label: "Quick action", seen: &seen)
            if action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Quick action title is required.")
            }
            if action.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Quick action icon is required.")
            }
            if !isSafeToken(action.icon) {
                throw ExtensionManifestError.invalidContribution("Quick action icon \(action.icon) is not valid.")
            }
            if action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Quick action prompt is required.")
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
            if !isSecureProviderURL(provider.baseURL) {
                throw ExtensionManifestError.invalidContribution("\(provider.baseURL.absoluteString) must be an https provider URL unless it targets localhost.")
            }
            if provider.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Intelligence provider modelID is required.")
            }
            if !seen.insert(provider.id).inserted {
                throw ExtensionManifestError.invalidContribution("Intelligence provider id \(provider.id) is duplicated.")
            }
        }
    }

    private static func validateRenderers(
        _ renderers: [CribbleExtensionRenderer],
        manifest: CribbleExtensionManifest
    ) throws {
        guard renderers.isEmpty || manifest.kind == .renderer else {
            throw ExtensionManifestError.invalidContribution("Only renderer extensions may declare renderers.")
        }

        var seen: Set<String> = []
        for renderer in renderers {
            try validateContributionID(renderer.id, label: "Renderer", seen: &seen)
            if renderer.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Renderer title is required.")
            }
            if renderer.languages.isEmpty {
                throw ExtensionManifestError.invalidContribution("Renderer languages are required.")
            }
            for language in renderer.languages where !isSafeToken(language) {
                throw ExtensionManifestError.invalidContribution("Renderer language \(language) is not valid.")
            }
        }
    }

    private static func validateImporters(
        _ importers: [CribbleExtensionImporter],
        manifest: CribbleExtensionManifest
    ) throws {
        guard importers.isEmpty || manifest.kind == .importer else {
            throw ExtensionManifestError.invalidContribution("Only importer extensions may declare importers.")
        }

        var seen: Set<String> = []
        for importer in importers {
            try validateContributionID(importer.id, label: "Importer", seen: &seen)
            if importer.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Importer title is required.")
            }
            if importer.fileExtensions.isEmpty {
                throw ExtensionManifestError.invalidContribution("Importer fileExtensions are required.")
            }
            for ext in importer.fileExtensions where !isBareFileExtension(ext) {
                throw ExtensionManifestError.invalidContribution("Importer file extension \(ext) must be a bare extension like json, without dots or paths.")
            }
            if importer.outputFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtensionManifestError.invalidContribution("Importer outputFormat is required.")
            }
        }
    }

    private static func validateTrust(_ trust: CribbleExtensionTrustDeclaration?) throws {
        guard let trust else { return }
        if trust.developerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExtensionManifestError.invalidContribution("Trust developerName is required.")
        }
        if !isReverseDNS(trust.signingIdentifier) {
            throw ExtensionManifestError.invalidContribution("Trust signingIdentifier must be a reverse-DNS bundle id.")
        }
        if let teamIdentifier = trust.teamIdentifier,
           teamIdentifier.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) == nil {
            throw ExtensionManifestError.invalidContribution("Trust teamIdentifier must be a 10-character Apple Team ID.")
        }
        if let sourceURL = trust.sourceURL, !isSecureProviderURL(sourceURL) {
            throw ExtensionManifestError.invalidContribution("\(sourceURL.absoluteString) must be an https trust sourceURL unless it targets localhost.")
        }
    }

    private static func validateContributionID(_ id: String, label: String, seen: inout Set<String>) throws {
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExtensionManifestError.invalidContribution("\(label) id is required.")
        }
        if !isSafeToken(id) {
            throw ExtensionManifestError.invalidContribution("\(label) id \(id) is not valid.")
        }
        if !seen.insert(id).inserted {
            throw ExtensionManifestError.invalidContribution("\(label) id \(id) is duplicated.")
        }
    }

    private static func isSafeToken(_ token: String) -> Bool {
        token.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    private static func isBareFileExtension(_ ext: String) -> Bool {
        ext.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func validateNoSecretMaterial(in data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ExtensionManifestError.unreadable
        }
        try scanForSecretMaterial(object, path: "manifest")
    }

    private static func scanForSecretMaterial(_ value: Any, path: String) throws {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                if isSecretLikeKey(key) {
                    throw ExtensionManifestError.invalidContribution("Manifest field \(path).\(key) looks like secret material. Store keys and tokens in Keychain, not extension manifests.")
                }
                try scanForSecretMaterial(nestedValue, path: "\(path).\(key)")
            }
        } else if let array = value as? [Any] {
            for (index, item) in array.enumerated() {
                try scanForSecretMaterial(item, path: "\(path)[\(index)]")
            }
        } else if let string = value as? String, containsSecretLikeValue(string) {
            throw ExtensionManifestError.invalidContribution("Manifest field \(path) looks like it contains a key or token. Store secrets in Keychain, not extension manifests.")
        }
    }

    private static func isSecretLikeKey(_ key: String) -> Bool {
        let normalized = key
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let blocked = [
            "apikey",
            "accesstoken",
            "authorization",
            "bearertoken",
            "clientsecret",
            "password",
            "privatekey",
            "secret",
            "token"
        ]
        return blocked.contains { normalized.contains($0) }
    }

    private static func containsSecretLikeValue(_ value: String) -> Bool {
        let patterns = [
            #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{12,}"#,
            #"(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|token|password|secret)=\S{8,}"#,
            #"\bsk-[A-Za-z0-9_-]{12,}"#
        ]
        return patterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
