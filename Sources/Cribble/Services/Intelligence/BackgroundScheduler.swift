import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Decides the maximum job tier permitted to run right now, based on machine
/// conditions. Implements the idle-aware policy from the design plan (§8): heavy
/// aggregation only runs when the user is idle, on power, and thermally safe.
///
/// An `actor` so the (cheap) condition probes are serialized and the type is
/// trivially `Sendable`. Idle detection uses `CGEventSource` polling rather than
/// a `CGEventTap`, so it needs no accessibility permission.
actor BackgroundScheduler {
    /// Seconds of no user input after which Tier-3 work is allowed.
    private let idleThreshold: TimeInterval
    /// Normalized 1-minute system load at or above this value means other
    /// processes are busy enough that Intelligence should pause completely.
    private let pauseLoadRatio: Double
    /// Normalized 1-minute system load at or above this value means only cheap,
    /// deterministic work may run.
    private let lightLoadRatio: Double

    /// Test seam: inject machine conditions instead of probing the real system,
    /// so policy is unit-testable without a Mac in a particular thermal state.
    struct Conditions: Sendable, Equatable {
        var userIdleSeconds: TimeInterval
        var thermalState: ProcessInfo.ThermalState
        var isOnBattery: Bool
        var appIsActive: Bool
        var appIsForeground: Bool
        /// 1-minute system load divided by active processor count. This catches
        /// busy-machine cases that are not thermal or memory pressure yet.
        var systemLoadRatio: Double
        /// True when the OS reports memory pressure; halts all intelligence work
        /// so Cribble can't contribute to a low-memory spiral.
        var memoryPressured: Bool

        init(
            userIdleSeconds: TimeInterval,
            thermalState: ProcessInfo.ThermalState,
            isOnBattery: Bool,
            appIsActive: Bool,
            appIsForeground: Bool,
            systemLoadRatio: Double = 0,
            memoryPressured: Bool = false
        ) {
            self.userIdleSeconds = userIdleSeconds
            self.thermalState = thermalState
            self.isOnBattery = isOnBattery
            self.appIsActive = appIsActive
            self.appIsForeground = appIsForeground
            self.systemLoadRatio = systemLoadRatio
            self.memoryPressured = memoryPressured
        }
    }

    enum Reason: String, Sendable, Equatable {
        case memoryPressure
        case thermalPressure
        case highSystemLoad
        case systemBusy
        case lowPower
        case idleWindow
        case waitingForIdle
    }

    struct Decision: Sendable, Equatable {
        var allowedTier: IntelligenceJobTier
        var reason: Reason
        var conditions: Conditions

        var userFacingSummary: String {
            switch reason {
            case .memoryPressure: "Paused for memory"
            case .thermalPressure: "Paused for thermal pressure"
            case .highSystemLoad: "Paused while system is busy"
            case .systemBusy: "Light work only - system busy"
            case .lowPower: "Light work only - low power"
            case .idleWindow: "Idle window - full intelligence"
            case .waitingForIdle: "Waiting for idle"
            }
        }
    }

    private let conditionsProvider: @Sendable () -> Conditions

    init(
        idleThreshold: TimeInterval = 60,
        pauseLoadRatio: Double = 2.0,
        lightLoadRatio: Double = 1.0,
        conditionsProvider: (@Sendable () -> Conditions)? = nil
    ) {
        self.idleThreshold = idleThreshold
        self.pauseLoadRatio = pauseLoadRatio
        self.lightLoadRatio = lightLoadRatio
        self.conditionsProvider = conditionsProvider ?? BackgroundScheduler.defaultConditions
    }

    /// The maximum tier of work allowed under the current conditions.
    func allowedTier() -> IntelligenceJobTier {
        decision().allowedTier
    }

    /// Full resource decision, suitable for UI receipts and engine logging.
    func decision() -> Decision {
        Self.decision(
            for: conditionsProvider(),
            idleThreshold: idleThreshold,
            pauseLoadRatio: pauseLoadRatio,
            lightLoadRatio: lightLoadRatio
        )
    }

    /// Pure decision function, extracted so it can be tested directly against
    /// synthetic `Conditions`.
    static func policy(for c: Conditions, idleThreshold: TimeInterval) -> IntelligenceJobTier {
        decision(for: c, idleThreshold: idleThreshold).allowedTier
    }

    static func decision(
        for c: Conditions,
        idleThreshold: TimeInterval,
        pauseLoadRatio: Double = 2.0,
        lightLoadRatio: Double = 1.0
    ) -> Decision {
        if c.memoryPressured {
            return Decision(allowedTier: .none, reason: .memoryPressure, conditions: c)
        }
        if c.thermalState == .serious || c.thermalState == .critical {
            return Decision(allowedTier: .none, reason: .thermalPressure, conditions: c)
        }
        if c.systemLoadRatio >= pauseLoadRatio {
            return Decision(allowedTier: .none, reason: .highSystemLoad, conditions: c)
        }
        if c.isOnBattery {
            return Decision(allowedTier: .tier1, reason: .lowPower, conditions: c)
        }
        if c.systemLoadRatio >= lightLoadRatio {
            return Decision(allowedTier: .tier1, reason: .systemBusy, conditions: c)
        }
        // The default path is intentionally idle-first: model work and aggregate
        // analysis wait for a real system idle window instead of competing with
        // the user's active writing or other foreground work.
        if c.userIdleSeconds >= idleThreshold {
            return Decision(allowedTier: .tier3, reason: .idleWindow, conditions: c)
        }
        return Decision(allowedTier: .tier1, reason: .waitingForIdle, conditions: c)
    }

    // MARK: - Real system probes

    private static func defaultConditions() -> Conditions {
        // App foreground/active state requires main-actor `NSApplication` access,
        // which this nonisolated probe path can't reach soundly. We default to
        // "active" here; the app injects a `conditionsProvider` that reads NSApp on
        // the main actor for accurate foreground gating.
        Conditions(
            userIdleSeconds: systemIdleSeconds(),
            thermalState: ProcessInfo.processInfo.thermalState,
            isOnBattery: ProcessInfo.processInfo.isLowPowerModeEnabled,
            appIsActive: true,
            appIsForeground: true,
            systemLoadRatio: currentSystemLoadRatio()
        )
    }

    static func currentSystemLoadRatio() -> Double {
        #if canImport(Darwin)
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 1) == 1 else { return 0 }
        let processors = max(1, ProcessInfo.processInfo.activeProcessorCount)
        return max(0, loads[0] / Double(processors))
        #else
        return 0
        #endif
    }

    /// Seconds since the last user input event across the whole system. Returns 0
    /// (treated as "active") when CoreGraphics isn't available.
    private static func systemIdleSeconds() -> TimeInterval {
        #if canImport(CoreGraphics)
        let interval = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .init(rawValue: ~0)! // kCGAnyInputEventType
        )
        return interval.isFinite ? interval : 0
        #else
        return 0
        #endif
    }
}
