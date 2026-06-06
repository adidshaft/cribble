import XCTest
@testable import Cribble

final class TaskExporterTests: XCTestCase {
    func testAllDayRangeEndsAfterStartOnNextDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 7,
            hour: 15,
            minute: 30
        ).date)

        let range = TaskExporter.allDayRange(for: date, calendar: calendar)

        XCTAssertEqual(calendar.component(.hour, from: range.start), 0)
        XCTAssertEqual(calendar.component(.minute, from: range.start), 0)
        XCTAssertEqual(calendar.dateComponents([.day], from: range.start, to: range.end).day, 1)
        XCTAssertGreaterThan(range.end, range.start)
    }
}
