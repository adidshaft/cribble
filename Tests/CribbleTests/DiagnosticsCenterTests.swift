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
        XCTAssertFalse(section.contains("/v1"))
        XCTAssertFalse(section.contains("token"))
        XCTAssertFalse(section.contains("secret"))
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
