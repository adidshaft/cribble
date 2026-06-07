import Foundation

/// App-wide source of truth for the OpenAI-compatible local runner (Ollama,
/// llama.cpp, LM Studio, …). Intelligence, the Chat HUD, Pathfinder, and AI
/// Link Notes all read the same configuration from here, so there is exactly
/// one place to point Cribble at a runner (issue #3).
///
/// Persists under its own keys and migrates the legacy Intelligence-only key
/// (`intelligence.runnerURL`, PR #2) exactly once, tracked by the
/// `localRunner.migrated` sentinel so `clear()` survives relaunch even while
/// the legacy key still exists. The legacy key remains
/// owned by `IntelligenceSettings` as "Intelligence currently uses the runner";
/// this store answers the broader "a runner is configured for the app".
@MainActor
final class LocalRunnerStore: ObservableObject {
    static let shared = LocalRunnerStore()

    /// Base URL string, e.g. `http://127.0.0.1:11434/v1`; nil when unconfigured.
    @Published private(set) var baseURLString: String?
    /// Friendly runner name shown in pickers, e.g. "Ollama".
    @Published private(set) var displayName: String?
    /// Model ids last probed from `GET /v1/models`, for instant picker lists.
    @Published private(set) var cachedModelIDs: [String]
    /// The model chosen when the runner was configured — the default for
    /// features without their own model picker (e.g. AI Link Notes).
    @Published private(set) var defaultModelID: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Keys.baseURL) {
            baseURLString = stored
            displayName = defaults.string(forKey: Keys.displayName)
            cachedModelIDs = defaults.stringArray(forKey: Keys.modelIDs) ?? []
            defaultModelID = defaults.string(forKey: Keys.defaultModelID)
        } else if defaults.bool(forKey: Keys.migrated) == false,
                  let legacy = defaults.string(forKey: Keys.legacyIntelligenceRunnerURL) {
            // One-time migration from the Intelligence-only configuration,
            // guarded by the `Keys.migrated` sentinel so a later `clear()`
            // sticks even while the legacy key still exists.
            let legacyModelID = defaults.string(forKey: Keys.legacyIntelligenceModelID)
            baseURLString = legacy
            displayName = nil
            defaultModelID = legacyModelID
            // Seed the cache with the migrated model so pickers gated on a
            // non-empty cache show the runner section right away.
            cachedModelIDs = legacyModelID.map { [$0] } ?? []
            persist()
        } else {
            baseURLString = nil
            displayName = nil
            cachedModelIDs = []
            defaultModelID = nil
        }
    }

    var baseURL: URL? { baseURLString.flatMap(URL.init(string:)) }
    var isConfigured: Bool { baseURL != nil }

    func configure(baseURLString: String, displayName: String?, modelIDs: [String], defaultModelID: String?) {
        self.baseURLString = baseURLString
        // Normalize "" to nil so the UI never renders "Local runner ()".
        self.displayName = displayName.flatMap { $0.isEmpty ? nil : $0 }
        self.cachedModelIDs = modelIDs
        self.defaultModelID = defaultModelID
        persist()
    }

    func clear() {
        baseURLString = nil
        displayName = nil
        cachedModelIDs = []
        defaultModelID = nil
        persist()
    }

    /// Re-probes `GET /v1/models` and refreshes the cached list. Silent on
    /// failure — the stale cache is still more useful than an empty picker.
    func refreshModels(session: URLSession = .shared) async {
        guard let baseURL else { return }
        guard let models = try? await OpenAICompatibleProvider.availableModelIDs(baseURL: baseURL, session: session) else { return }
        cachedModelIDs = models
        persist()
    }

    private func persist() {
        defaults.set(baseURLString, forKey: Keys.baseURL)
        defaults.set(displayName, forKey: Keys.displayName)
        defaults.set(cachedModelIDs, forKey: Keys.modelIDs)
        defaults.set(defaultModelID, forKey: Keys.defaultModelID)
        // Any persist (configure, clear, or the migration itself) settles the
        // legacy migration — it must never run again.
        defaults.set(true, forKey: Keys.migrated)
    }

    private enum Keys {
        static let baseURL = "localRunner.baseURL"
        static let displayName = "localRunner.displayName"
        static let modelIDs = "localRunner.modelIDs"
        static let defaultModelID = "localRunner.defaultModelID"
        /// One-shot sentinel: once true, the legacy migration never runs again.
        static let migrated = "localRunner.migrated"
        static let legacyIntelligenceRunnerURL = "intelligence.runnerURL"
        static let legacyIntelligenceModelID = "intelligence.modelID"
    }
}
