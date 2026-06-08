import XCTest
@testable import Cribble

final class DiagnosticsCenterTests: XCTestCase {
    func testIntelligenceSnapshotFormatsRunnerWithoutSecrets() {
        let snapshot = IntelligenceDiagnosticsSnapshot(
            isEnabled: true,
            scope: "all folders",
            statusDescription: "Working (Waiting for idle)",
            modelID: "llama3.2",
            runnerBaseURL: "http://127.0.0.1:11434/v1?token=secret",
            usesKeychainCredential: true,
            performanceMode: "Balanced",
            pendingJobs: 42,
            filesIndexed: 1_200,
            staleArtifacts: 8,
            lastActivity: "Changes queued; waiting for idle",
            resourceDecisionSummary: "Waiting for idle",
            allowedTier: "tier1",
            modelDownloadFraction: nil
        )

        let section = snapshot.formattedReportSection

        XCTAssertTrue(section.contains("OpenAI-compatible runner at http://127.0.0.1:11434"))
        XCTAssertTrue(section.contains("Credential: Keychain"))
        XCTAssertTrue(section.contains("Next action: Keep Cribble open during an idle window so queued intelligence jobs can finish."))
        XCTAssertFalse(section.contains("/v1"))
        XCTAssertFalse(section.contains("token"))
        XCTAssertFalse(section.contains("secret"))
    }

    func testIntelligenceSnapshotRecommendsKeychainForRemoteRunnerWithoutCredential() {
        let snapshot = IntelligenceDiagnosticsSnapshot(
            isEnabled: true,
            scope: "single folder",
            statusDescription: "Ready",
            modelID: "team-model",
            runnerBaseURL: "https://runner.example.com/v1",
            usesKeychainCredential: false,
            performanceMode: "Balanced",
            pendingJobs: 0,
            filesIndexed: 10,
            staleArtifacts: 0,
            lastActivity: nil,
            resourceDecisionSummary: nil,
            allowedTier: nil,
            modelDownloadFraction: nil
        )

        let section = snapshot.formattedReportSection

        XCTAssertTrue(section.contains("Credential: none configured"))
        XCTAssertEqual(snapshot.nextActionSummary, "Use Settings > Project Intelligence > Copy Review or Help > Copy Remote Runner Setup Review, store the remote runner credential in Keychain, or switch back to an on-device model.")
        XCTAssertTrue(section.contains("Next action: Use Settings > Project Intelligence > Copy Review or Help > Copy Remote Runner Setup Review, store the remote runner credential in Keychain, or switch back to an on-device model."))
    }

    func testIntelligenceSnapshotDoesNotRequestKeychainForLocalRunnerWithoutCredential() {
        let snapshot = IntelligenceDiagnosticsSnapshot(
            isEnabled: true,
            scope: "single folder",
            statusDescription: "Ready",
            modelID: "local-model",
            runnerBaseURL: "http://localhost:11434/v1",
            usesKeychainCredential: false,
            performanceMode: "Balanced",
            pendingJobs: 0,
            filesIndexed: 10,
            staleArtifacts: 0,
            lastActivity: nil,
            resourceDecisionSummary: nil,
            allowedTier: nil,
            modelDownloadFraction: nil
        )

        let section = snapshot.formattedReportSection

        XCTAssertTrue(section.contains("Credential: not required for local runner"))
        XCTAssertEqual(snapshot.nextActionSummary, "No intelligence action needed.")
        XCTAssertFalse(section.contains("store the remote runner credential in Keychain"))
    }

    @MainActor
    func testDiagnosticReportIncludesIntelligenceQueueAndResourceGate() {
        let snapshot = IntelligenceDiagnosticsSnapshot(
            isEnabled: true,
            scope: "single folder",
            statusDescription: "Working (Processing)",
            modelID: "gemma-4-flash",
            runnerBaseURL: nil,
            usesKeychainCredential: false,
            performanceMode: "Power",
            pendingJobs: 7,
            filesIndexed: 300,
            staleArtifacts: 2,
            lastActivity: "Indexed 4 file(s)",
            resourceDecisionSummary: "Idle window - full intelligence",
            allowedTier: "tier3",
            modelDownloadFraction: 0.42
        )

        let report = DiagnosticsCenter.shared.makeReport(library: nil, settings: nil, intelligence: snapshot)

        XCTAssertTrue(report.contains("## Health Summary"))
        XCTAssertTrue(report.contains("- Intelligence: enabled, Working (Processing), 7 pending"))
        XCTAssertTrue(report.contains("## Intelligence"))
        XCTAssertTrue(report.contains("Provider: On-device model"))
        XCTAssertTrue(report.contains("Performance mode: Power"))
        XCTAssertTrue(report.contains("Pending jobs: 7"))
        XCTAssertTrue(report.contains("Files indexed: 300"))
        XCTAssertTrue(report.contains("Stale artifacts: 2"))
        XCTAssertTrue(report.contains("Resource gate: Idle window - full intelligence, tier3"))
        XCTAssertTrue(report.contains("Model download: 42%"))
    }

    func testRefreshSnapshotFormatsPerformanceCounters() {
        let snapshot = RefreshDiagnosticsSnapshot(
            date: Date(timeIntervalSince1970: 100),
            duration: 0.125,
            totalDocuments: 42,
            loadedDocuments: 3,
            reusedDocuments: 39,
            skippedFiles: 1,
            failedRoots: 0,
            renderCacheEntriesBefore: 8,
            renderCacheEntriesAfter: 6,
            renderCacheEntriesPruned: 2
        )

        let section = snapshot.formattedReportSection

        XCTAssertTrue(section.contains("Duration: 0.125s"))
        XCTAssertTrue(section.contains("Markdown files: 42"))
        XCTAssertTrue(section.contains("Loaded/new metadata: 3"))
        XCTAssertTrue(section.contains("Reused metadata: 39"))
        XCTAssertTrue(section.contains("Skipped files: 1"))
        XCTAssertTrue(section.contains("Render cache: 6 kept, 2 pruned from 8"))
        XCTAssertEqual(snapshot.compactSummary, "Refreshed 42 files in 0.12s · 39 reused · 3 loaded · 1 skipped")
        XCTAssertEqual(snapshot.cacheSummary, "6 render cache entries kept, 2 pruned")
    }

    func testHealthSummaryFormatsTopLevelStateWithoutSecrets() {
        let refresh = RefreshDiagnosticsSnapshot(
            date: Date(timeIntervalSince1970: 100),
            duration: 0.125,
            totalDocuments: 42,
            loadedDocuments: 3,
            reusedDocuments: 39,
            skippedFiles: 1,
            failedRoots: 0,
            renderCacheEntriesBefore: 8,
            renderCacheEntriesAfter: 6,
            renderCacheEntriesPruned: 2
        )
        let intelligence = IntelligenceDiagnosticsSnapshot(
            isEnabled: true,
            scope: "single folder",
            statusDescription: "Working (Processing)",
            modelID: "team-model",
            runnerBaseURL: "https://runner.example.com/v1?token=secret",
            usesKeychainCredential: true,
            performanceMode: "Balanced",
            pendingJobs: 2,
            filesIndexed: 10,
            staleArtifacts: 1,
            lastActivity: "Indexed",
            resourceDecisionSummary: nil,
            allowedTier: nil,
            modelDownloadFraction: nil
        )
        let extensions = ExtensionDiagnosticsSnapshot(
            installed: [],
            disabledIDs: [],
            warnings: ["bad manifest"]
        )
        let crash = CrashReportFile(
            url: URL(fileURLWithPath: "/tmp/Cribble_2026-06-08.ips"),
            modifiedAt: Date(timeIntervalSince1970: 200),
            size: 2048
        )

        let summary = DiagnosticsHealthSummary(
            selectedDocumentPath: "/tmp/Notes/Daily.md",
            rootCount: 2,
            status: "Ready",
            error: nil,
            refresh: refresh,
            intelligence: intelligence,
            extensions: extensions,
            crashReport: crash
        ).formattedReportSection

        XCTAssertTrue(summary.contains("Selection: Daily.md"))
        XCTAssertTrue(summary.contains("Folders: 2"))
        XCTAssertTrue(summary.contains("Current status: Ready"))
        XCTAssertTrue(summary.contains("Current error: none"))
        XCTAssertTrue(summary.contains("Refresh: Refreshed 42 files in 0.12s"))
        XCTAssertTrue(summary.contains("Intelligence: enabled, Working (Processing), 2 pending"))
        XCTAssertTrue(summary.contains("Extensions: 0/0 enabled, 1 warnings"))
        XCTAssertTrue(summary.contains("Crash report: Cribble_2026-06-08.ips"))
        XCTAssertFalse(summary.contains("token"))
        XCTAssertFalse(summary.contains("secret"))
    }

    func testExtensionSnapshotFormatsInstalledLanesAndWarnings() {
        let root = URL(fileURLWithPath: "/tmp/CribbleDiagnosticsExtensions")
        let installed = [
            InstalledCribbleExtension(
                manifest: CribbleExtensionManifest(
                    id: "com.example.quick",
                    name: "Quick Review",
                    version: "1.0.0",
                    kind: .quickAction,
                    summary: "Review action.",
                    permissions: [.readCurrentNote],
                    quickActions: [
                        CribbleExtensionQuickAction(
                            id: "summarize",
                            title: "Summarize",
                            icon: "bolt",
                            prompt: "Summarize."
                        )
                    ]
                ),
                manifestURL: root.appendingPathComponent("quick/cribble-extension.json"),
                location: .user
            ),
            InstalledCribbleExtension(
                manifest: CribbleExtensionManifest(
                    id: "com.example.runner",
                    name: "Team Runner",
                    version: "1.0.0",
                    kind: .intelligenceProvider,
                    summary: "Remote runner.",
                    permissions: [.networkOpenAICompatible],
                    intelligenceProviders: [
                        CribbleExtensionIntelligenceProvider(
                            id: "gpu",
                            title: "GPU Runner",
                            baseURL: URL(string: "https://runner.example.com/v1")!,
                            modelID: "team-large",
                            embeddingModelID: nil,
                            trustLabel: "Team"
                        )
                    ]
                ),
                manifestURL: root.appendingPathComponent("runner/cribble-extension.json"),
                location: .project(root)
            )
        ]

        let snapshot = ExtensionDiagnosticsSnapshot(
            installed: installed,
            disabledIDs: ["com.example.runner"],
            warnings: ["bad-extension: The manifest is not valid JSON."]
        )
        let section = snapshot.formattedReportSection

        XCTAssertEqual(snapshot.nextActionSummary, "Open Settings > Extensions, use Copy Warnings, fix manifest warnings, then run Check Again; use Contribution Guide if the manifest is new.")
        XCTAssertTrue(section.contains("Installed: 2"))
        XCTAssertTrue(section.contains("Enabled: 1"))
        XCTAssertTrue(section.contains("Warnings: 1"))
        XCTAssertTrue(section.contains("Installed contributions: 1 quick actions, 1 remote runners, 0 renderers, 0 importers"))
        XCTAssertTrue(section.contains("Active contributions: 1 quick actions, 0 remote runners, 0 renderers, 0 importers"))
        XCTAssertTrue(section.contains("Next action: Open Settings > Extensions, use Copy Warnings, fix manifest warnings, then run Check Again; use Contribution Guide if the manifest is new."))
        XCTAssertTrue(section.contains("Contribution guide: Settings > Extensions > Contribution Guide or Help > Open Extension Contribution Guide"))
        XCTAssertTrue(section.contains("Proposal review: Settings > Extensions > Copy Proposal or Help > Copy Extension Proposal"))
        XCTAssertTrue(section.contains("Warning handoff: Settings > Extensions > Copy Warnings"))
        XCTAssertTrue(section.contains("Import lane review: Settings > Extensions > Import lanes > Copy Review or Help > Copy Import Lane Setup Review"))
        XCTAssertTrue(section.contains("Remote runner review: Settings > Project Intelligence > Copy Review or Help > Copy Remote Runner Setup Review"))
        XCTAssertTrue(section.contains("bad-extension: The manifest is not valid JSON."))
        XCTAssertTrue(section.contains("Quick Review (com.example.quick): Quick Action, User, enabled"))
        XCTAssertTrue(section.contains("Permissions: Read Current Note"))
        XCTAssertTrue(section.contains("Contributions: Summarize"))
        XCTAssertTrue(section.contains("Team Runner (com.example.runner): Intelligence Provider, CribbleDiagnosticsExtensions, disabled"))
        XCTAssertTrue(section.contains("Contributions: GPU Runner (team-large)"))
    }

    func testExtensionSnapshotSuggestsReviewForDisabledExtensions() {
        let root = URL(fileURLWithPath: "/tmp/CribbleDiagnosticsDisabled")
        let installed = [
            InstalledCribbleExtension(
                manifest: CribbleExtensionManifest(
                    id: "com.example.quick",
                    name: "Quick Review",
                    version: "1.0.0",
                    kind: .quickAction,
                    summary: "Review action.",
                    permissions: [.readCurrentNote],
                    quickActions: [
                        CribbleExtensionQuickAction(
                            id: "summarize",
                            title: "Summarize",
                            icon: "bolt",
                            prompt: "Summarize."
                        )
                    ]
                ),
                manifestURL: root.appendingPathComponent("quick/cribble-extension.json"),
                location: .user
            )
        ]

        let snapshot = ExtensionDiagnosticsSnapshot(
            installed: installed,
            disabledIDs: ["com.example.quick"],
            warnings: []
        )

        XCTAssertEqual(snapshot.nextActionSummary, "Enable a reviewed extension, copy its proposal/review details, or leave all extensions disabled.")
        XCTAssertTrue(snapshot.formattedReportSection.contains("Next action: Enable a reviewed extension, copy its proposal/review details, or leave all extensions disabled."))
    }

    @MainActor
    func testDiagnosticReportIncludesExtensionSnapshot() {
        let snapshot = ExtensionDiagnosticsSnapshot(installed: [], disabledIDs: [], warnings: [])
        let report = DiagnosticsCenter.shared.makeReport(
            library: nil,
            settings: nil,
            extensions: snapshot
        )

        XCTAssertTrue(report.contains("## Extensions"))
        XCTAssertTrue(report.contains("Installed: 0"))
        XCTAssertTrue(report.contains("Next action: Open Settings > Extensions, read Contribution Guide, then create a read-only project example."))
        XCTAssertTrue(report.contains("Contribution guide: Settings > Extensions > Contribution Guide or Help > Open Extension Contribution Guide"))
        XCTAssertTrue(report.contains("Proposal review: Settings > Extensions > Copy Proposal or Help > Copy Extension Proposal"))
        XCTAssertTrue(report.contains("No extension manifests are installed."))
    }

    func testCrashReportFinderPrefersNewestCribbleReport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CribbleCrashReports-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let oldCrash = directory.appendingPathComponent("Cribble_2026-05-25.crash")
        let newestCrash = directory.appendingPathComponent("Cribble_2026-05-26.ips")
        let otherCrash = directory.appendingPathComponent("OtherApp_2026-05-26.crash")

        try "old".write(to: oldCrash, atomically: true, encoding: .utf8)
        try "newest".write(to: newestCrash, atomically: true, encoding: .utf8)
        try "other".write(to: otherCrash, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: oldCrash.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newestCrash.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 300)],
            ofItemAtPath: otherCrash.path
        )

        let reports = DiagnosticsCenter.crashReports(in: directory)
        XCTAssertEqual(reports.map { $0.url.lastPathComponent }.sorted(), [
            "Cribble_2026-05-25.crash",
            "Cribble_2026-05-26.ips"
        ])
        XCTAssertEqual(
            reports.max { $0.modifiedAt < $1.modifiedAt }?.url.standardizedFileURL,
            newestCrash.standardizedFileURL
        )
    }
}
