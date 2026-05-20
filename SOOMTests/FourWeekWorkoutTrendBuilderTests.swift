import XCTest
@testable import SOOM

final class FourWeekWorkoutTrendBuilderTests: XCTestCase {
    func testBuildGroupsInputsIntoFourWeeks() {
        let builder = FourWeekWorkoutTrendBuilder()
        let inputs = [
            makeInput(daysAgo: 0, distanceKm: 8, durationMinutes: 40),
            makeInput(daysAgo: 7, distanceKm: 6, durationMinutes: 32),
            makeInput(daysAgo: 14, distanceKm: 5, durationMinutes: 28),
            makeInput(daysAgo: 21, distanceKm: 4, durationMinutes: 24)
        ]

        let trend = builder.build(inputs: inputs, referenceDate: baseDate)

        XCTAssertEqual(trend.weeks.count, 4)
        XCTAssertEqual(trend.weeks.map(\.workoutCount), [1, 1, 1, 1])
        XCTAssertEqual(trend.weeks.reduce(0) { $0 + $1.totalDistanceKm }, 23, accuracy: 0.01)
    }

    func testIncreasingDistanceAndDurationBuildsImprovingTrend() {
        let trend = FourWeekWorkoutTrendBuilder().build(
            inputs: [
                makeInput(daysAgo: 21, distanceKm: 4, durationMinutes: 24),
                makeInput(daysAgo: 14, distanceKm: 5, durationMinutes: 30),
                makeInput(daysAgo: 7, distanceKm: 7, durationMinutes: 38),
                makeInput(daysAgo: 0, distanceKm: 9, durationMinutes: 48)
            ],
            referenceDate: baseDate
        )

        XCTAssertEqual(trend.trendType, .improving)
        XCTAssertFalse(trend.summaryText.isEmpty)
        XCTAssertFalse(trend.motivationText.isEmpty)
    }

    func testSimilarWeeksBuildSteadyTrend() {
        let trend = FourWeekWorkoutTrendBuilder().build(
            inputs: [
                makeInput(daysAgo: 21, distanceKm: 6, durationMinutes: 35),
                makeInput(daysAgo: 14, distanceKm: 6.2, durationMinutes: 36),
                makeInput(daysAgo: 7, distanceKm: 5.8, durationMinutes: 34),
                makeInput(daysAgo: 0, distanceKm: 6.1, durationMinutes: 35)
            ],
            referenceDate: baseDate
        )

        XCTAssertEqual(trend.trendType, .steady)
    }

    func testRecentWeekLowerThanPreviousWeeksBuildsLighterTrend() {
        let trend = FourWeekWorkoutTrendBuilder().build(
            inputs: [
                makeInput(daysAgo: 21, distanceKm: 10, durationMinutes: 55),
                makeInput(daysAgo: 14, distanceKm: 11, durationMinutes: 60),
                makeInput(daysAgo: 7, distanceKm: 10, durationMinutes: 54),
                makeInput(daysAgo: 0, distanceKm: 2, durationMinutes: 12)
            ],
            referenceDate: baseDate
        )

        XCTAssertEqual(trend.trendType, .lighter)
    }

    func testInsufficientDataWhenFewerThanTwoWeeksHaveWorkouts() {
        let trend = FourWeekWorkoutTrendBuilder().build(
            inputs: [
                makeInput(daysAgo: 0, distanceKm: 7, durationMinutes: 36)
            ],
            referenceDate: baseDate
        )

        XCTAssertEqual(trend.trendType, .insufficientData)
    }

    func testFourWeekTrendUsesWorkoutGrowthOnlyWithoutRecoveryScore() {
        let trend = FourWeekWorkoutTrendBuilder().build(
            inputs: [
                makeInput(daysAgo: 7, distanceKm: 5, durationMinutes: 30),
                makeInput(daysAgo: 0, distanceKm: 7, durationMinutes: 38)
            ],
            referenceDate: baseDate
        )

        XCTAssertFalse(trend.summaryText.isEmpty)
        XCTAssertNotEqual(trend.trendType, .insufficientData)
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 7)) ?? Date()
    }

    private func makeInput(
        daysAgo: Int,
        distanceKm: Double,
        durationMinutes: Int
    ) -> WorkoutGrowthInput {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
        return WorkoutGrowthInput(
            id: UUID(),
            source: .appleHealthKit,
            workoutType: .running,
            startDate: date,
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            averagePaceText: nil,
            averageSpeedKmh: nil,
            averageHeartRate: nil,
            elevationGainMeters: nil,
            activeEnergyKcal: nil
        )
    }
}
