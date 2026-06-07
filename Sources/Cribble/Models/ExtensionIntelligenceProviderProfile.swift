import Foundation

enum RemoteRunnerDataBoundary {
    static let detail = "Prompts, note excerpts, generated summaries, and embedding requests may leave this Mac for the selected runner."
}

enum RemoteRunnerSetupReview {
    static let markdown = """
    # Remote Runner Setup Review

    Runner name:
    Endpoint:
    Model:
    Embeddings:
    Trust label:

    Context boundary:
    \(RemoteRunnerDataBoundary.detail)

    API key:
    Store credentials in Keychain. Do not put secrets in manifests, notes, examples, fixtures, or docs.

    Approval checklist:
    - Endpoint is controlled by the user, team, or trusted vendor.
    - Retention policy, logging, and access controls are understood before use.
    - Requested note context is appropriate for this runner.
    - Secrets stay out of manifests and notes; use Keychain only.
    - Disable path is understood before approval.

    Disable/revoke:
    Choose a different runner, clear the API key, or disable/remove the contributing extension in Settings.
    """
}

enum DecisionLogTemplate {
    static let markdown = """
    ## YYYY-MM-DD - Decision title

    Status: proposed | accepted | reversed
    Owner:

    Context:

    Decision:

    Evidence:
    - [[Research Review]]
    - [[Tasks and Intelligence]]

    Follow-up:
    - [ ] Add task
    - [ ] Review in Project Intelligence

    Review boundary:
    - What did Cribble read?
    - What may leave this Mac?
    - What can be disabled or reverted?
    """
}

struct ExtensionIntelligenceProviderProfile: Identifiable, Equatable {
    let id: String
    let title: String
    let baseURL: URL
    let modelID: String
    let embeddingModelID: String?
    let trustLabel: String
    let sourceName: String

    var isLoopback: Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasSuffix(".localhost")
    }

    var privacyLabel: String {
        isLoopback ? "Local runner" : "Remote runner"
    }

    var consentKey: String {
        [
            id,
            sourceName,
            baseURL.absoluteString,
            modelID
        ]
        .joined(separator: "|")
        .lowercased()
    }

    var handoffSummary: String {
        var lines = [
            "Runner: \(title)",
            "Endpoint: \(baseURL.absoluteString)",
            "Model: \(modelID)",
            "Trust label: \(trustLabel)",
            "Source extension: \(sourceName)",
            "Context boundary: \(isLoopback ? "stays on this Mac/local network endpoint" : RemoteRunnerDataBoundary.detail)",
            "API key: enter in the Intelligence HUD; store in Keychain when needed",
            "Approval checklist:",
            "- Endpoint is controlled by the user, team, or trusted vendor.",
            "- Secrets stay out of manifests and notes; use Keychain only.",
            "- Requested context is appropriate for this runner.",
            "- Disable path is understood before approval.",
            "Disable/revoke: disable the extension in Settings or choose a different runner"
        ]
        if let embeddingModelID, !embeddingModelID.isEmpty {
            lines.insert("Embeddings: \(embeddingModelID)", after: "Model: \(modelID)")
        }
        return lines.joined(separator: "\n")
    }

    func consentReviewSummary(usesKeychain: Bool) -> String {
        [
            "Remote runner review",
            "Runner: \(title)",
            "Endpoint: \(baseURL.absoluteString)",
            "Model: \(modelID)",
            embeddingModelID.map { "Embeddings: \($0)" },
            "Trust label: \(trustLabel)",
            "Source extension: \(sourceName)",
            "Context boundary: \(RemoteRunnerDataBoundary.detail)",
            "API key: \(usesKeychain ? "saved in Keychain for this endpoint" : "not selected in Keychain for this endpoint")",
            "Approval checklist:",
            "- Endpoint is controlled by the user, team, or trusted vendor.",
            "- Secrets stay out of manifests and notes; use Keychain only.",
            "- Requested context is appropriate for this runner.",
            "- Disable path is understood before approval.",
            "Disable/revoke: disable the extension in Settings or choose a different runner"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

struct ExtensionRunnerConsentStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "intelligence.extensionRunnerConsents") {
        self.defaults = defaults
        self.key = key
    }

    func hasApproved(_ profile: ExtensionIntelligenceProviderProfile) -> Bool {
        guard !profile.isLoopback else { return true }
        return Set(defaults.stringArray(forKey: key) ?? []).contains(profile.consentKey)
    }

    func approve(_ profile: ExtensionIntelligenceProviderProfile) {
        var approved = Set(defaults.stringArray(forKey: key) ?? [])
        approved.insert(profile.consentKey)
        defaults.set(Array(approved).sorted(), forKey: key)
    }

    func requiredApprovalProfile(
        runnerURL: String?,
        modelID: String,
        profiles: [ExtensionIntelligenceProviderProfile]
    ) -> ExtensionIntelligenceProviderProfile? {
        guard let profile = ExtensionIntelligenceProviderProfile.matching(
            runnerURL: runnerURL,
            modelID: modelID,
            profiles: profiles
        ), !hasApproved(profile) else {
            return nil
        }
        return profile
    }
}

extension ExtensionIntelligenceProviderProfile {
    static func matching(
        runnerURL: String?,
        modelID: String,
        profiles: [ExtensionIntelligenceProviderProfile]
    ) -> ExtensionIntelligenceProviderProfile? {
        guard let runnerURL else { return nil }
        let trimmedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return profiles.first {
            $0.baseURL.absoluteString == runnerURL
                && $0.modelID.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedModel
        }
    }
}

private extension Array where Element == String {
    mutating func insert(_ newElement: String, after marker: String) {
        guard let index = firstIndex(of: marker) else {
            append(newElement)
            return
        }
        insert(newElement, at: self.index(after: index))
    }
}
