import XCTest
@testable import Cribble

final class DiagnosticsCenterTests: XCTestCase {
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
