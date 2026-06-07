import Foundation

enum ExtensionTrustDecision: String, Codable, Equatable {
    case approved
    case revoked
}

struct ExtensionTrustDecisionRecord: Codable, Equatable {
    let extensionID: String
    let signingIdentifier: String
    let teamIdentifier: String?
    let decision: ExtensionTrustDecision
    let decidedAt: Date

    var key: String {
        Self.key(extensionID: extensionID, signingIdentifier: signingIdentifier, teamIdentifier: teamIdentifier)
    }

    static func key(extensionID: String, signingIdentifier: String, teamIdentifier: String?) -> String {
        [
            extensionID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            signingIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            teamIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "-"
        ].joined(separator: "|")
    }
}

/// Stores future executable-plugin trust decisions without enabling executable
/// plugins. API v1 remains declarative-only; this gives Settings a safe place to
/// revoke or clear consent before any code-running surface is introduced.
final class ExtensionTrustDecisionStore {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = "extensions.trustDecisions") {
        self.defaults = defaults
        self.key = key
    }

    func decision(for manifest: CribbleExtensionManifest) -> ExtensionTrustDecision? {
        guard let trust = manifest.trust else { return nil }
        return recordsByKey()[recordKey(for: manifest, trust: trust)]?.decision
    }

    func approve(_ manifest: CribbleExtensionManifest, at date: Date = Date()) {
        set(.approved, for: manifest, at: date)
    }

    func revoke(_ manifest: CribbleExtensionManifest, at date: Date = Date()) {
        set(.revoked, for: manifest, at: date)
    }

    func clearDecision(for manifest: CribbleExtensionManifest) {
        guard let trust = manifest.trust else { return }
        var records = recordsByKey()
        records.removeValue(forKey: recordKey(for: manifest, trust: trust))
        save(Array(records.values))
    }

    func prune(toInstalledManifests manifests: [CribbleExtensionManifest]) {
        let validKeys = Set(manifests.compactMap { manifest -> String? in
            guard let trust = manifest.trust else { return nil }
            return recordKey(for: manifest, trust: trust)
        })
        let records = recordsByKey().filter { key, _ in validKeys.contains(key) }
        save(Array(records.values))
    }

    private func set(_ decision: ExtensionTrustDecision, for manifest: CribbleExtensionManifest, at date: Date) {
        guard let trust = manifest.trust else { return }
        var records = recordsByKey()
        let record = ExtensionTrustDecisionRecord(
            extensionID: manifest.id,
            signingIdentifier: trust.signingIdentifier,
            teamIdentifier: trust.teamIdentifier,
            decision: decision,
            decidedAt: date
        )
        records[record.key] = record
        save(Array(records.values))
    }

    private func recordKey(for manifest: CribbleExtensionManifest, trust: CribbleExtensionTrustDeclaration) -> String {
        ExtensionTrustDecisionRecord.key(
            extensionID: manifest.id,
            signingIdentifier: trust.signingIdentifier,
            teamIdentifier: trust.teamIdentifier
        )
    }

    private func recordsByKey() -> [String: ExtensionTrustDecisionRecord] {
        load().reduce(into: [:]) { partial, record in
            partial[record.key] = record
        }
    }

    private func load() -> [ExtensionTrustDecisionRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? decoder.decode([ExtensionTrustDecisionRecord].self, from: data)
        else { return [] }
        return records
    }

    private func save(_ records: [ExtensionTrustDecisionRecord]) {
        guard let data = try? encoder.encode(records.sorted { $0.key < $1.key }) else { return }
        defaults.set(data, forKey: key)
    }
}
