import XCTest
@testable import Cribble

final class PerformanceModeTests: XCTestCase {
    func testRecommendedFromSpecs() {
        XCTAssertEqual(PerformanceMode.recommended(memoryGB: 8, cores: 8), .light)
        XCTAssertEqual(PerformanceMode.recommended(memoryGB: 16, cores: 8), .balanced)
        XCTAssertEqual(PerformanceMode.recommended(memoryGB: 64, cores: 12), .power)
        // Low core count forces light even with lots of RAM.
        XCTAssertEqual(PerformanceMode.recommended(memoryGB: 64, cores: 4), .light)
    }

    func testTuningOrdering() {
        // Light waits longer, tolerates less load, drains fewer than Power.
        XCTAssertGreaterThan(PerformanceMode.light.idleThreshold, PerformanceMode.power.idleThreshold)
        XCTAssertLessThan(PerformanceMode.light.pauseLoadRatio, PerformanceMode.power.pauseLoadRatio)
        XCTAssertLessThan(PerformanceMode.light.drainLimit, PerformanceMode.power.drainLimit)
        XCTAssertEqual(PerformanceMode.balanced.drainLimit, 6)
    }

    func testLightDisallowsBackgroundModelWork() {
        XCTAssertFalse(PerformanceMode.light.allowsBackgroundModelWork)
        XCTAssertTrue(PerformanceMode.balanced.allowsBackgroundModelWork)
        XCTAssertTrue(PerformanceMode.power.allowsBackgroundModelWork)
    }
}
