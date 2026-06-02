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

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Keys.enabledProjects) ?? []
        enabledProjectIDs = Set(stored)
        modelID = UserDefaults.standard.string(forKey: Keys.modelID) ?? ModelCatalog.defaultModel.id
        localRunnerBaseURL = UserDefaults.standard.string(forKey: Keys.runnerURL)
        pauseOnBattery = UserDefaults.standard.object(forKey: Keys.pauseOnBattery) as? Bool ?? true
        autoPublish = UserDefaults.standard.object(forKey: Keys.autoPublish) as? Bool ?? false
        diskBudgetMB = UserDefaults.standard.object(forKey: Keys.diskBudgetMB) as? Int ?? 500
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
    }
}
