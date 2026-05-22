import XCTest
@testable import SOOM

final class WorkoutZoneBuilderTests: XCTestCase {
    private let builder = WorkoutZoneBuilder()

    func testBuildSummaryCalculatesZonePercentages() {
        let summary = builder.buildSummary(
            type: .heartRate,
            durations: [
                WorkoutZoneDurationInput(zoneIndex: 1, durationSeconds: 60),
                WorkoutZoneDurationInput(zoneIndex: 2, durationSeconds: 180),
                WorkoutZoneDurationInput(zoneIndex: 3, durationSeconds: 60)
            ]
        )

        XCTAssertEqual(summary.zones.count, 3)
        XCTAssertEqual(summary.zones[0].percentage, 20, accuracy: 0.001)
        XCTAssertEqual(summary.zones[1].percentage, 60, accuracy: 0.001)
        XCTAssertEqual(summary.zones[2].percentage, 20, accuracy: 0.001)
    }

    func testBuildSummaryFindsDominantZone() {
        let summary = builder.buildSummary(
            type: .heartRate,
            durations: [
                WorkoutZoneDurationInput(zoneIndex: 1, durationSeconds: 60),
                WorkoutZoneDurationInput(zoneIndex: 2, durationSeconds: 240),
                WorkoutZoneDurationInput(zoneIndex: 3, durationSeconds: 120)
            ]
        )

        XCTAssertEqual(summary.dominantZone?.zoneIndex, 2)
        XCTAssertTrue(summary.insightText?.contains("Zone 2") == true)
    }

    func testBuildSummaryIgnoresNonPositiveDurations() {
        let summary = builder.buildSummary(
            type: .cadence,
            durations: [
                WorkoutZoneDurationInput(zoneIndex: 1, durationSeconds: 0),
                WorkoutZoneDurationInput(zoneIndex: 2, durationSeconds: -20),
                WorkoutZoneDurationInput(zoneIndex: 3, durationSeconds: 90)
            ]
        )

        XCTAssertEqual(summary.zones.count, 1)
        XCTAssertEqual(summary.zones[0].zoneIndex, 3)
        XCTAssertEqual(summary.zones[0].percentage, 100, accuracy: 0.001)
    }

    func testCopyAvoidsNegativeTone() {
        let summary = builder.buildSummary(
            type: .cadence,
            durations: [WorkoutZoneDurationInput(zoneIndex: 1, durationSeconds: 120)]
        )
        let copy = summary.insightText ?? ""

        XCTAssertFalse(copy.contains("못"))
        XCTAssertFalse(copy.contains("나쁨"))
        XCTAssertFalse(copy.contains("실패"))
        XCTAssertFalse(copy.contains("위험"))
    }

    func testPowerZoneUnavailableCanBeRepresentedSafely() {
        let summary = builder.unavailableSummary(type: .power)

        XCTAssertFalse(summary.isAvailable)
        XCTAssertTrue(summary.zones.isEmpty)
        XCTAssertNil(summary.dominantZone)
        XCTAssertTrue(summary.insightText?.contains("FTP") == true)
    }
}
