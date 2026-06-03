import Foundation

/// Persisted preferences for the intelligence layer. Mirrors `AppSettings`'
/// UserDefaults-backed pattern. Per-project enablement is keyed by the project's
/// stable id (its root path), so opening a folder remembers whether intelligence
/// was turned on for it.
@MainActor
final class IntelligenceSettings: ObservableObject {
    /// Project ids (root paths) the user has enabled intelligence for.
    @Published var enabledProjectIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledProjectIDs), forKey: Keys.enabledProjects) }
    }

    /// Model id (matches `LocalModel.id`) used for intelligence jobs, or a
    /// `local-runner` sentinel for an OpenAI-compatible endpoint.
    @Published var modelID: String {
        didSet { UserDefaults.standard.set(modelID, forKey: Keys.modelID) }
    }

    /// When set, intelligence uses an OpenAI-compatible runner at this base URL
    /// instead of an on-device model.
    @Published var localRunnerBaseURL: String? {
        didSet { UserDefaults.standard.set(localRunnerBaseURL, forKey: Keys.runnerURL) }
    }

    @Published var pauseOnBattery: Bool {
        didSet { UserDefaults.standard.set(pauseOnBattery, forKey: Keys.pauseOnBattery) }
    }

    /// When true, generated artifacts are written to `.cribble/intelligence/`
    /// without a diff-preview confirmation. Off by default (preview-first).
    @Published var autoPublish: Bool {
        didSet { UserDefaults.standard.set(autoPublish, forKey: Keys.autoPublish) }
    }

    /// Disk budget for `.cribble/cache/` in megabytes; oldest virtual artifacts
    /// are evicted (LRU) when exceeded.
    @Published var diskBudgetMB: Int {
        didSet { UserDefaults.standard.set(diskBudgetMB, forKey: Keys.diskBudgetMB) }
    }

    /// When on, the Chat HUD folds the active project's intelligence into its
    /// answers. Off by default so chat never gets polluted by project context the
    /// user didn't ask for.
    @Published var useInChat: Bool {
        didSet { UserDefaults.standard.set(useInChat, forKey: Keys.useInChat) }
    }

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Keys.enabledProjects) ?? []
        enabledProjectIDs = Set(stored)
        // Intelligence runs hundreds of background jobs, so it must NOT default to
        // a cloud CLI provider (rate limits, cost, and — as seen in testing — the
        // CLI's auth-error text getting stored as artifacts). Prefer an on-device
        // model; if none is downloaded yet, deterministic jobs still run and model
        // jobs simply wait. Migrate the old cloud default to the local default.
        // Prefer, in order: a stored on-device choice → any already-downloaded
        // local model (so we don't nag to download when one is present) → the
        // local default.
        let firstDownloaded = ModelCatalog.localModels.first(where: ModelInventory.isDownloaded)?.id
        let onDeviceDefault = firstDownloaded ?? ModelCatalog.localModels.first?.id ?? ModelCatalog.defaultModel.id
        let storedModel = UserDefaults.standard.string(forKey: Keys.modelID)
        if let storedModel, let model = ModelCatalog.model(withID: storedModel), !model.kind.isCloud {
            modelID = storedModel
        } else {
            modelID = onDeviceDefault
        }
        localRunnerBaseURL = UserDefaults.standard.string(forKey: Keys.runnerURL)
        pauseOnBattery = UserDefaults.standard.object(forKey: Keys.pauseOnBattery) as? Bool ?? true
        autoPublish = UserDefaults.standard.object(forKey: Keys.autoPublish) as? Bool ?? false
        diskBudgetMB = UserDefaults.standard.object(forKey: Keys.diskBudgetMB) as? Int ?? 500
        useInChat = UserDefaults.standard.object(forKey: Keys.useInChat) as? Bool ?? false
    }

    func isEnabled(projectID: String) -> Bool { enabledProjectIDs.contains(projectID) }

    func setEnabled(_ enabled: Bool, projectID: String) {
        if enabled { enabledProjectIDs.insert(projectID) }
        else { enabledProjectIDs.remove(projectID) }
    }

    private enum Keys {
        static let enabledProjects = "intelligence.enabledProjects"
        static let modelID = "intelligence.modelID"
        static let runnerURL = "intelligence.runnerURL"
        static let pauseOnBattery = "intelligence.pauseOnBattery"
        static let autoPublish = "intelligence.autoPublish"
        static let diskBudgetMB = "intelligence.diskBudgetMB"
        static let useInChat = "intelligence.useInChat"
    }
}
