import AppKit
import Foundation

@MainActor
final class DiagnosticsCenter: ObservableObject {
    static let shared = DiagnosticsCenter()

    @Published private(set) var events: [DiagnosticEvent] = []
    @Published private(set) var previousSessionDidNotCloseCleanly = false
    @Published private(set) var latestCrashReport: CrashReportFile?
    @Published private(set) var latestRefreshSnapshot: RefreshDiagnosticsSnapshot?

    private let defaults = UserDefaults.standard
    private let maxEvents = 80
    private let maxCrashReportCharacters = 24_000

    private init() {
        events = loadEvents()
        latestCrashReport = Self.findLatestCrashReport()
    }

    func markLaunch() {
        latestCrashReport = Self.findLatestCrashReport()

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

            if let latestCrashReport {
                record(
                    level: .error,
                    message: "Latest macOS crash report: \(latestCrashReport.url.path)"
                )
            }
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

    func recordRefreshSnapshot(_ snapshot: RefreshDiagnosticsSnapshot) {
        latestRefreshSnapshot = snapshot
    }

    func makeReport(
        library: MarkdownLibraryStore?,
        settings: AppSettings?,
        intelligence: IntelligenceDiagnosticsSnapshot? = nil,
        extensions: ExtensionDiagnosticsSnapshot? = nil
    ) -> String {
        latestCrashReport = Self.findLatestCrashReport()

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
        let refreshSection = latestRefreshSnapshot?.formattedReportSection ?? "No refresh performance snapshot recorded."
        let intelligenceSection = intelligence?.formattedReportSection ?? "No intelligence diagnostics snapshot recorded."
        let extensionSection = extensions?.formattedReportSection ?? "No extension diagnostics snapshot recorded."

        let crashReportSection = latestCrashReportSection()

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

        ## Latest Refresh
        \(refreshSection)

        ## Intelligence
        \(intelligenceSection)

        ## Extensions
        \(extensionSection)

        ## Recent Events
        \(eventLines)

        \(crashReportSection)
        """
    }

    func copyReport(
        library: MarkdownLibraryStore?,
        settings: AppSettings?,
        intelligence: IntelligenceDiagnosticsSnapshot? = nil,
        extensions: ExtensionDiagnosticsSnapshot? = nil
    ) {
        let report = makeReport(library: library, settings: settings, intelligence: intelligence, extensions: extensions)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        record(level: .info, message: "Diagnostic report copied to clipboard.")
    }

    @discardableResult
    func copyLatestCrashReport() -> Bool {
        latestCrashReport = Self.findLatestCrashReport()
        guard let latestCrashReport,
              let content = try? String(contentsOf: latestCrashReport.url, encoding: .utf8)
        else {
            return false
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        record(level: .info, message: "Latest macOS crash report copied to clipboard.")
        return true
    }

    @discardableResult
    func revealLatestCrashReportInFinder() -> Bool {
        latestCrashReport = Self.findLatestCrashReport()
        guard let latestCrashReport else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([latestCrashReport.url])
        record(level: .info, message: "Revealed latest macOS crash report in Finder.")
        return true
    }

    private func latestCrashReportSection() -> String {
        guard let latestCrashReport else {
            return """
            ## Latest macOS Crash Report
            No Cribble crash report was found in ~/Library/Logs/DiagnosticReports.
            """
        }

        let content = (try? String(contentsOf: latestCrashReport.url, encoding: .utf8)) ?? ""
        let excerpt: String
        if content.isEmpty {
            excerpt = "[Crash report exists, but Cribble could not read its text content.]"
        } else if content.count > maxCrashReportCharacters {
            let endIndex = content.index(content.startIndex, offsetBy: maxCrashReportCharacters)
            excerpt = String(content[..<endIndex]) + "\n\n[Crash report truncated in diagnostic report. Use Reveal Crash File to send the full file.]"
        } else {
            excerpt = content
        }

        return """
        ## Latest macOS Crash Report
        - File: \(latestCrashReport.url.lastPathComponent)
        - Path: \(latestCrashReport.url.path)
        - Modified: \(Self.timestamp(latestCrashReport.modifiedAt))
        - Size: \(latestCrashReport.formattedSize)

        ```text
        \(excerpt)
        ```
        """
    }

    nonisolated static func findLatestCrashReport(
        processName: String = "Cribble",
        fileManager: FileManager = .default
    ) -> CrashReportFile? {
        crashReportDirectories(fileManager: fileManager)
            .flatMap { crashReports(in: $0, processName: processName, fileManager: fileManager) }
            .max { $0.modifiedAt < $1.modifiedAt }
    }

    nonisolated static func crashReports(
        in directory: URL,
        processName: String = "Cribble",
        fileManager: FileManager = .default
    ) -> [CrashReportFile] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(processName),
                  url.pathExtension == "crash" || url.pathExtension == "ips"
            else {
                return nil
            }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile != false else { return nil }

            return CrashReportFile(
                url: url,
                modifiedAt: values?.contentModificationDate ?? Date.distantPast,
                size: values?.fileSize ?? 0
            )
        }
    }

    private nonisolated static func crashReportDirectories(fileManager: FileManager) -> [URL] {
        var directories: [URL] = []

        if let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            directories.append(library.appendingPathComponent("Logs/DiagnosticReports", isDirectory: true))
        }

        directories.append(URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true))
        return directories
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

    fileprivate static func timestamp(_ date: Date) -> String {
        diagnosticTimestamp(date)
    }

    private enum Keys {
        static let events = "diagnosticEvents"
        static let sessionActive = "diagnosticSessionActive"
        static let lastLaunchTime = "diagnosticLastLaunchTime"
        static let lastCleanTerminationTime = "diagnosticLastCleanTerminationTime"
    }
}

struct CrashReportFile: Equatable {
    let url: URL
    let modifiedAt: Date
    let size: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
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

struct ExtensionDiagnosticsSnapshot: Equatable {
    struct Entry: Equatable {
        let name: String
        let id: String
        let kind: String
        let location: String
        let enabled: Bool
        let permissions: [String]
        let contributionSummary: String
    }

    let installedCount: Int
    let enabledCount: Int
    let warningCount: Int
    let quickActionCount: Int
    let remoteRunnerCount: Int
    let rendererCount: Int
    let importerCount: Int
    let warnings: [String]
    let entries: [Entry]

    init(
        installed: [InstalledCribbleExtension],
        disabledIDs: Set<String>,
        warnings: [String]
    ) {
        installedCount = installed.count
        enabledCount = installed.filter { !disabledIDs.contains($0.manifest.id) }.count
        warningCount = warnings.count
        quickActionCount = installed.reduce(0) { $0 + $1.manifest.quickActions.count }
        remoteRunnerCount = installed.reduce(0) { $0 + $1.manifest.intelligenceProviders.count }
        rendererCount = installed.reduce(0) { $0 + $1.manifest.renderers.count }
        importerCount = installed.reduce(0) { $0 + $1.manifest.importers.count }
        self.warnings = warnings
        entries = installed.map { installed in
            let manifest = installed.manifest
            return Entry(
                name: manifest.name,
                id: manifest.id,
                kind: manifest.kind.title,
                location: installed.location.title,
                enabled: !disabledIDs.contains(manifest.id),
                permissions: manifest.permissions.map(\.title),
                contributionSummary: Self.contributionSummary(for: manifest)
            )
        }
    }

    var formattedReportSection: String {
        var lines = [
            "- Installed: \(installedCount)",
            "- Enabled: \(enabledCount)",
            "- Warnings: \(warningCount)",
            "- Contributions: \(quickActionCount) quick actions, \(remoteRunnerCount) remote runners, \(rendererCount) renderers, \(importerCount) importers"
        ]

        if !warnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            lines.append(contentsOf: warnings.map { "- \($0)" })
        }

        if entries.isEmpty {
            lines.append("")
            lines.append("No extension manifests are installed.")
        } else {
            lines.append("")
            lines.append("Installed manifests:")
            for entry in entries {
                lines.append("- \(entry.name) (\(entry.id)): \(entry.kind), \(entry.location), \(entry.enabled ? "enabled" : "disabled")")
                if !entry.permissions.isEmpty {
                    lines.append("  Permissions: \(entry.permissions.joined(separator: ", "))")
                }
                if !entry.contributionSummary.isEmpty {
                    lines.append("  Contributions: \(entry.contributionSummary)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func contributionSummary(for manifest: CribbleExtensionManifest) -> String {
        switch manifest.kind {
        case .quickAction:
            return manifest.quickActions.map(\.title).joined(separator: ", ")
        case .intelligenceProvider:
            return manifest.intelligenceProviders.map { "\($0.title) (\($0.modelID))" }.joined(separator: ", ")
        case .renderer:
            return manifest.renderers.map { "\($0.title) [\($0.languages.joined(separator: ", "))]" }.joined(separator: ", ")
        case .importer:
            return manifest.importers.map { "\($0.title) [\($0.fileExtensions.joined(separator: ", "))]" }.joined(separator: ", ")
        }
    }
}

struct RefreshDiagnosticsSnapshot: Equatable {
    let date: Date
    let duration: TimeInterval
    let totalDocuments: Int
    let loadedDocuments: Int
    let reusedDocuments: Int
    let skippedFiles: Int
    let failedRoots: Int
    let renderCacheEntriesBefore: Int
    let renderCacheEntriesAfter: Int
    let renderCacheEntriesPruned: Int

    var formattedReportSection: String {
        """
        - Time: \(diagnosticTimestamp(date))
        - Duration: \(String(format: "%.3fs", duration))
        - Markdown files: \(totalDocuments)
        - Loaded/new metadata: \(loadedDocuments)
        - Reused metadata: \(reusedDocuments)
        - Skipped files: \(skippedFiles)
        - Failed roots: \(failedRoots)
        - Render cache: \(renderCacheEntriesAfter) kept, \(renderCacheEntriesPruned) pruned from \(renderCacheEntriesBefore)
        """
    }

    var compactSummary: String {
        let durationText = String(format: "%.2fs", duration)
        let skippedSuffix = skippedFiles > 0 ? " · \(skippedFiles) skipped" : ""
        let failedSuffix = failedRoots > 0 ? " · \(failedRoots) root\(failedRoots == 1 ? "" : "s") failed" : ""
        return "Refreshed \(totalDocuments) files in \(durationText) · \(reusedDocuments) reused · \(loadedDocuments) loaded\(skippedSuffix)\(failedSuffix)"
    }

    var cacheSummary: String {
        "\(renderCacheEntriesAfter) render cache entries kept, \(renderCacheEntriesPruned) pruned"
    }
}

struct IntelligenceDiagnosticsSnapshot: Equatable {
    let isEnabled: Bool
    let scope: String
    let statusDescription: String
    let modelID: String
    let runnerBaseURL: String?
    let usesKeychainCredential: Bool
    let performanceMode: String
    let pendingJobs: Int
    let filesIndexed: Int
    let staleArtifacts: Int
    let lastActivity: String?
    let resourceDecisionSummary: String?
    let allowedTier: String?
    let modelDownloadFraction: Double?

    var formattedReportSection: String {
        """
        - Enabled: \(isEnabled ? "true" : "false")
        - Scope: \(scope)
        - Provider: \(providerDescription)
        - Credential: \(credentialDescription)
        - Model: \(modelID)
        - Performance mode: \(performanceMode)
        - Status: \(statusDescription)
        - Pending jobs: \(pendingJobs)
        - Files indexed: \(filesIndexed)
        - Stale artifacts: \(staleArtifacts)
        - Last activity: \(lastActivity ?? "none")
        - Resource gate: \(resourceGateDescription)
        - Model download: \(modelDownloadDescription)
        """
    }

    private var providerDescription: String {
        guard let runnerBaseURL, !runnerBaseURL.isEmpty else {
            return "On-device model"
        }
        return "OpenAI-compatible runner at \(Self.redactedRunnerURL(runnerBaseURL))"
    }

    private var credentialDescription: String {
        runnerBaseURL == nil ? "none" : (usesKeychainCredential ? "Keychain" : "none configured")
    }

    private var resourceGateDescription: String {
        let summary = resourceDecisionSummary ?? "No scheduler decision"
        guard let allowedTier else { return summary }
        return "\(summary), \(allowedTier)"
    }

    private var modelDownloadDescription: String {
        guard let modelDownloadFraction else { return "none" }
        return "\(Int((modelDownloadFraction * 100).rounded()))%"
    }

    nonisolated static func redactedRunnerURL(_ raw: String) -> String {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme,
              let host = components.host
        else {
            return "invalid-url"
        }
        var redacted = "\(scheme)://\(host)"
        if let port = components.port {
            redacted += ":\(port)"
        }
        return redacted
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
