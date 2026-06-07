import Foundation

/// How aggressively Cribble's background intelligence may use the machine.
/// Surfaced in Settings and auto-suggested from the Mac's specs so an 8GB Air
/// and a 128GB Studio both behave appropriately.
enum PerformanceMode: String, CaseIterable, Identifiable, Sendable {
    /// Minimal footprint: deterministic work only in the background; model and
    /// aggregate analysis run only when the user explicitly asks ("Run now").
    case light
    /// The default: idle/thermal/battery-gated background work.
    case balanced
    /// For capable Macs: shorter idle wait, higher load tolerance, larger batches.
    case power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .balanced: "Balanced"
        case .power: "Power"
        }
    }

    var subtitle: String {
        switch self {
        case .light: "Lowest footprint. Intelligence runs only when you ask."
        case .balanced: "Recommended. Background work waits for idle moments."
        case .power: "Uses more of a capable Mac for faster, fuller analysis."
        }
    }

    // MARK: - Scheduler tuning

    /// Seconds of user inactivity before heavy (Tier-3) work is allowed.
    var idleThreshold: TimeInterval {
        switch self {
        case .light: 150
        case .balanced: 60
        case .power: 20
        }
    }

    /// System-load ratio at/above which all intelligence pauses.
    var pauseLoadRatio: Double {
        switch self {
        case .light: 1.2
        case .balanced: 2.0
        case .power: 3.0
        }
    }

    /// System-load ratio at/above which only deterministic work runs.
    var lightLoadRatio: Double {
        switch self {
        case .light: 0.6
        case .balanced: 1.0
        case .power: 1.6
        }
    }

    /// How many jobs the engine drains per idle tick.
    var drainLimit: Int {
        switch self {
        case .light: 3
        case .balanced: 6
        case .power: 12
        }
    }

    /// Whether model/aggregate work may run automatically in the background.
    /// In Light mode it doesn't — the user triggers it with "Run now".
    var allowsBackgroundModelWork: Bool {
        self != .light
    }

    // MARK: - Auto-selection

    /// The mode recommended for this machine, based on memory and core count.
    static func recommended(
        memoryGB: Int = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824),
        cores: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> PerformanceMode {
        if memoryGB <= 8 || cores <= 4 { return .light }
        if memoryGB >= 32 && cores >= 10 { return .power }
        return .balanced
    }
}
