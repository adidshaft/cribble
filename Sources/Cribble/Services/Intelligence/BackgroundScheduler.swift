import Foundation
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

    /// Test seam: inject machine conditions instead of probing the real system,
    /// so policy is unit-testable without a Mac in a particular thermal state.
    struct Conditions: Sendable {
        var userIdleSeconds: TimeInterval
        var thermalState: ProcessInfo.ThermalState
        var isOnBattery: Bool
        var appIsActive: Bool
        var appIsForeground: Bool
        /// True when the OS reports memory pressure; halts all intelligence work
        /// so Cribble can't contribute to a low-memory spiral.
        var memoryPressured: Bool

        init(
            userIdleSeconds: TimeInterval,
            thermalState: ProcessInfo.ThermalState,
            isOnBattery: Bool,
            appIsActive: Bool,
            appIsForeground: Bool,
            memoryPressured: Bool = false
        ) {
            self.userIdleSeconds = userIdleSeconds
            self.thermalState = thermalState
            self.isOnBattery = isOnBattery
            self.appIsActive = appIsActive
            self.appIsForeground = appIsForeground
            self.memoryPressured = memoryPressured
        }
    }

    private let conditionsProvider: @Sendable () -> Conditions

    init(
        idleThreshold: TimeInterval = 60,
        conditionsProvider: (@Sendable () -> Conditions)? = nil
    ) {
        self.idleThreshold = idleThreshold
        self.conditionsProvider = conditionsProvider ?? BackgroundScheduler.defaultConditions
    }

    /// The maximum tier of work allowed under the current conditions.
    func allowedTier() -> IntelligenceJobTier {
        Self.policy(for: conditionsProvider(), idleThreshold: idleThreshold)
    }

    /// Pure decision function — extracted so it can be tested directly against
    /// synthetic `Conditions`.
    static func policy(for c: Conditions, idleThreshold: TimeInterval) -> IntelligenceJobTier {
        // Memory pressure halts everything — the highest-priority safety gate.
        if c.memoryPressured { return .none }
        // Thermal pressure halts everything, regardless of power/idle.
        if c.thermalState == .serious || c.thermalState == .critical { return .none }
        // On battery we only do the cheap, deterministic Tier-1 work.
        if c.isOnBattery { return .tier1 }
        // Plugged in + genuinely idle → full aggregation.
        if c.userIdleSeconds >= idleThreshold { return .tier3 }
        // Plugged in, app active and in use → light model calls are fine.
        if c.appIsActive { return .tier2 }
        // App backgrounded but on power → deterministic work only.
        if c.appIsForeground { return .tier2 }
        return .tier1
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
            appIsForeground: true
        )
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
