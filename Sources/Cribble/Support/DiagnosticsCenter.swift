import AppKit
import Foundation

@MainActor
final class DiagnosticsCenter: ObservableObject {
    static let shared = DiagnosticsCenter()

    @Published private(set) var events: [DiagnosticEvent] = []
    @Published private(set) var previousSessionDidNotCloseCleanly = false

    private let defaults = UserDefaults.standard
    private let maxEvents = 80

    private init() {
        events = loadEvents()
    }

    func markLaunch() {
        if defaults.bool(forKey: Keys.sessionActive) && launchedRecently() {
            // Only warn when the previous session looks like it was still
            // alive recently. Normal shutdowns (system restart, force quit
            // during sleep, etc.) often skip applicationWillTerminate even
            // though nothing crashed, so a stale flag from days ago is a
            // false positive — don't pester the user about it.
            previousSessionDidNotCloseCleanly = true
            record(
                level: .error,
                message: "Previous Cribble session did not close cleanly. This may indicate a crash or force quit."
            )
        }

        defaults.set(true, forKey: Keys.sessionActive)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastLaunchTime)
    }

    private func launchedRecently() -> Bool {
        // Treat any session whose last heartbeat was within ~6 hours as
        // recent. Anything older is almost certainly a normal shutdown that
        // didn't run applicationWillTerminate, not a crash.
        let last = defaults.double(forKey: Keys.lastLaunchTime)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < 6 * 60 * 60
    }

    func acknowledgePreviousSessionIssue() {
        previousSessionDidNotCloseCleanly = false
    }

    func markCleanTermination() {
        defaults.set(false, forKey: Keys.sessionActive)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastCleanTerminationTime)
    }

    func record(level: DiagnosticLevel, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        events.append(DiagnosticEvent(date: Date(), level: level, message: trimmed))
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        persistEvents()
    }

    func makeReport(library: MarkdownLibraryStore?, settings: AppSettings?) -> String {
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let selectedPath = library?.selectedDocument?.url.path ?? "none"
        let rootPaths = library?.rootURLs.map(\.path).joined(separator: "\n") ?? "none"
        let status = library?.statusMessage ?? "none"
        let error = library?.errorMessage ?? "none"
        let sortMode = settings?.fileSortMode.rawValue ?? "unknown"
        let fontScale = settings.map { String(format: "%.2f", $0.readerFontScale) } ?? "unknown"

        let eventLines = events.isEmpty
            ? "No recorded diagnostic events."
            : events.map { "- \($0.formatted)" }.joined(separator: "\n")

        return """
        # Cribble Diagnostic Report

        Generated: \(Self.timestamp(Date()))

        ## App
        - Version: \(appVersion)
        - Build: \(build)
        - Bundle: \(bundle.bundlePath)
        - Process: \(ProcessInfo.processInfo.processName) (\(ProcessInfo.processInfo.processIdentifier))

        ## System
        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Host: \(Host.current().localizedName ?? "unknown")

        ## Current State
        - Selected document: \(selectedPath)
        - Status: \(status)
        - Error: \(error)
        - Sort mode: \(sortMode)
        - Reader font scale: \(fontScale)

        ## Imported Folders
        \(rootPaths)

        ## Recent Events
        \(eventLines)
        """
    }

    func copyReport(library: MarkdownLibraryStore?, settings: AppSettings?) {
        let report = makeReport(library: library, settings: settings)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        record(level: .info, message: "Diagnostic report copied to clipboard.")
    }

    private func persistEvents() {
        let payload = events.map(DiagnosticEventPayload.init(event:))
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Keys.events)
    }

    private func loadEvents() -> [DiagnosticEvent] {
        guard let data = defaults.data(forKey: Keys.events),
              let payload = try? JSONDecoder().decode([DiagnosticEventPayload].self, from: data)
        else {
            return []
        }
        return payload.map(\.event)
    }

    private static func timestamp(_ date: Date) -> String {
        diagnosticTimestamp(date)
    }

    private enum Keys {
        static let events = "diagnosticEvents"
        static let sessionActive = "diagnosticSessionActive"
        static let lastLaunchTime = "diagnosticLastLaunchTime"
        static let lastCleanTerminationTime = "diagnosticLastCleanTerminationTime"
    }
}

enum DiagnosticLevel: String, Codable {
    case info
    case warning
    case error
}

struct DiagnosticEvent: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let level: DiagnosticLevel
    let message: String

    var formatted: String {
        "\(diagnosticTimestamp(date)) [\(level.rawValue.uppercased())] \(message)"
    }
}

private struct DiagnosticEventPayload: Codable {
    let date: Date
    let level: DiagnosticLevel
    let message: String

    init(event: DiagnosticEvent) {
        date = event.date
        level = event.level
        message = event.message
    }

    var event: DiagnosticEvent {
        DiagnosticEvent(date: date, level: level, message: message)
    }
}

private func diagnosticTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
