import XCTest
@testable import SOOM

final class RelativeEffortComparisonBuilderTests: XCTestCase {
    func testHigherThanAverageWhenAboveThreshold() {
        let comparison = RelativeEffortComparisonBuilder.build(todayEffort: 60, recentEfforts: [40, 40])

        XCTAssertNotNil(comparison)
        XCTAssertEqual(comparison?.tier, .higher)
        XCTAssertEqual(comparison?.recentAverageEffort, 40)
    }

    func testLowerThanAverageWhenBelowThreshold() {
        let comparison = RelativeEffortComparisonBuilder.build(todayEffort: 20, recentEfforts: [40, 40])

        XCTAssertEqual(comparison?.tier, .lower)
    }

    func testWithinThresholdIsAverage() {
        let comparison = RelativeEffortComparisonBuilder.build(todayEffort: 42, recentEfforts: [40, 40])

        XCTAssertEqual(comparison?.tier, .average)
    }

    func testExactBoundaryIsInclusive() {
        // +15% of 40 is exactly 46.
        let higher = RelativeEffortComparisonBuilder.build(todayEffort: 46, recentEfforts: [40, 40])
        XCTAssertEqual(higher?.tier, .higher)

        // -15% of 40 is exactly 34.
        let lower = RelativeEffortComparisonBuilder.build(todayEffort: 34, recentEfforts: [40, 40])
        XCTAssertEqual(lower?.tier, .lower)
    }

    func testTooFewRecentActivitiesReturnsNil() {
        XCTAssertNil(RelativeEffortComparisonBuilder.build(todayEffort: 60, recentEfforts: []))
        XCTAssertNil(RelativeEffortComparisonBuilder.build(todayEffort: 60, recentEfforts: [40]))
    }

    func testZeroAverageReturnsNil() {
        XCTAssertNil(RelativeEffortComparisonBuilder.build(todayEffort: 10, recentEfforts: [0, 0]))
    }

    func testMarkerPositionClampsToDisplayRange() {
        let extremeHigh = RelativeEffortComparison(todayEffort: 200, recentAverageEffort: 40, tier: .higher)
        XCTAssertEqual(extremeHigh.markerPosition, 1.0, accuracy: 0.001)

        let extremeLow = RelativeEffortComparison(todayEffort: 5, recentAverageEffort: 40, tier: .lower)
        XCTAssertEqual(extremeLow.markerPosition, 0.0, accuracy: 0.001)

        let exact = RelativeEffortComparison(todayEffort: 40, recentAverageEffort: 40, tier: .average)
        XCTAssertEqual(exact.markerPosition, 0.5, accuracy: 0.001)
    }
}
