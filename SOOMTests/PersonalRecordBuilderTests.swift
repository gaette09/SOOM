import XCTest
@testable import SOOM

final class PersonalRecordBuilderTests: XCTestCase {
    func testBuildCreatesLongestDistanceRecord() {
        let records = PersonalRecordBuilder().build(
            inputs: [
                makeInput(daysAgo: 2, distanceKm: 6, durationMinutes: 34),
                makeInput(daysAgo: 0, distanceKm: 12, durationMinutes: 68)
            ],
            referenceDate: baseDate
        )

        XCTAssertEqual(records.first?.metricType, .longestDistance)
        XCTAssertEqual(records.first?.value, "12.0 km")
        XCTAssertFalse(records.first?.motivationText.isEmpty ?? true)
    }

    func testBuildCreatesBestPaceRecordForRunningInputs() {
        let records = PersonalRecordBuilder().build(
            inputs: [
                makeInput(daysAgo: 3, distanceKm: 5, durationMinutes: 30),
                makeInput(daysAgo: 0, distanceKm: 5, durationMinutes: 24)
            ],
            referenceDate: baseDate
        )

        XCTAssertTrue(records.contains { record in
            record.metricType == .bestPace && record.value == "4:48/km"
        })
    }

    func testBuildCreatesBestAverageSpeedForCyclingInputs() {
        let records = PersonalRecordBuilder().build(
            inputs: [
                makeInput(daysAgo: 3, type: .cycling, distanceKm: 20, durationMinutes: 60, speed: 20),
                makeInput(daysAgo: 0, type: .cycling, distanceKm: 30, durationMinutes: 60, speed: 30)
            ],
            referenceDate: baseDate
        )

        XCTAssertTrue(records.contains { record in
            record.metricType == .bestAverageSpeed && record.value == "30.0 km/h"
        })
    }

    func testEmptyInputsReturnNoRecords() {
        let records = PersonalRecordBuilder().build(inputs: [], referenceDate: baseDate)

        XCTAssertTrue(records.isEmpty)
    }

    func testPersonalRecordsUseWorkoutGrowthOnlyWithoutRecoveryScore() {
        let records = PersonalRecordBuilder().build(
            inputs: [
                makeInput(daysAgo: 7, distanceKm: 5, durationMinutes: 30),
                makeInput(daysAgo: 0, distanceKm: 7, durationMinutes: 38)
            ],
            referenceDate: baseDate
        )

        XCTAssertFalse(records.isEmpty)
        XCTAssertFalse(records.map(\.motivationText).joined().contains("회복 점수"))
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 7)) ?? Date()
    }

    private func makeInput(
        daysAgo: Int,
        type: UnifiedWorkoutType = .running,
        distanceKm: Double,
        durationMinutes: Int,
        speed: Double? = nil,
        elevation: Double? = 20
    ) -> WorkoutGrowthInput {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
        return WorkoutGrowthInput(
            id: UUID(),
            source: .appleHealthKit,
            workoutType: type,
            startDate: date,
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            averagePaceText: nil,
            averageSpeedKmh: speed,
            averageHeartRate: nil,
            elevationGainMeters: elevation,
            activeEnergyKcal: nil
        )
    }
}
