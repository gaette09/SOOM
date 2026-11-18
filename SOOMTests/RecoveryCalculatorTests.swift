import XCTest
@testable import SOOM

final class RecoveryCalculatorTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testEmptyActivitiesReturnsDataInsufficientSummary() {
        let summary = makeCalculator().calculateSummary(from: [])

        XCTAssertEqual(summary.score, 72)
        XCTAssertFalse(summary.hasCalculatedScore)
        XCTAssertEqual(summary.statusLabel, "회복 · 데이터 부족")
        XCTAssertEqual(summary.status, "데이터 부족")
        XCTAssertEqual(summary.dataQuality.label, RecoveryDataQuality.estimated.label)
        XCTAssertFalse(summary.recommendation.isEmpty)
    }

    func testHighTrainingLoadLowersScoreAndRecommendsRecovery() {
        let highLoadWeekActivities = (0..<7).map {
            makeActivity(
                daysAgo: $0,
                load: 125,
                effort: 110,
                avgHR: 166
            )
        }

        let summary = makeCalculator().calculateSummary(from: highLoadWeekActivities)

        XCTAssertLessThan(summary.score, 68)
        XCTAssertTrue(summary.hasCalculatedScore)
        let guidanceText = "\(summary.recommendation) \(summary.coachMessage.message)"
        XCTAssertTrue(
            guidanceText.contains("회복") ||
            guidanceText.contains("강도") ||
            guidanceText.contains("휴식") ||
            guidanceText.contains("가볍게")
        )
    }

    func testModerateLoadWithRestKeepsScoreStable() {
        let activities = [
            makeActivity(daysAgo: 6, load: 38, effort: 24, avgHR: 132),
            makeActivity(daysAgo: 4, load: 46, effort: 30, avgHR: 136),
            makeActivity(daysAgo: 2, load: 52, effort: 34, avgHR: 138)
        ]

        let summary = makeCalculator().calculateSummary(from: activities)

        XCTAssertGreaterThanOrEqual(summary.score, 75)
        XCTAssertTrue(summary.hasCalculatedScore)
        XCTAssertEqual(summary.statusLabel, "회복 \(summary.score) · \(summary.status)")
        XCTAssertTrue(["좋음", "보통"].contains(summary.status))
    }

    func testScoreIsClampedToLowerBound() {
        let activities = [
            makeActivity(daysAgo: 2, load: 900, effort: 500, avgHR: 185),
            makeActivity(daysAgo: 1, load: 950, effort: 520, avgHR: 188),
            makeActivity(daysAgo: 0, load: 980, effort: 540, avgHR: 190)
        ]

        let summary = makeCalculator().calculateSummary(from: activities)

        XCTAssertGreaterThanOrEqual(summary.score, 45)
    }

    func testScoreIsClampedToUpperBound() {
        let activities = [
            makeActivity(daysAgo: 6, load: 1, effort: 1, avgHR: 110)
        ]

        let summary = makeCalculator().calculateSummary(from: activities)

        XCTAssertLessThanOrEqual(summary.score, 95)
    }

    func testTrendsAndInsightsAreGeneratedForActivities() {
        let summary = makeCalculator().calculateSummary(from: [
            makeActivity(daysAgo: 6, load: 40, effort: 24, avgHR: 132),
            makeActivity(daysAgo: 3, load: 58, effort: 36, avgHR: 140),
            makeActivity(daysAgo: 1, load: 74, effort: 42, avgHR: 146)
        ])

        XCTAssertFalse(summary.trends.isEmpty)
        XCTAssertFalse(summary.insights.isEmpty)
    }

    private func makeCalculator() -> RecoveryCalculator {
        RecoveryCalculator(referenceDate: referenceDate)
    }

    private func makeActivity(
        daysAgo: Int,
        load: Int,
        effort: Int,
        avgHR: Int
    ) -> RecoveryActivity {
        RecoveryActivity(
            workoutType: .run,
            durationMinutes: 45,
            distanceKm: 8.0,
            averageHeartRate: avgHR,
            relativeEffort: effort,
            trainingLoad: Double(load),
            completedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: referenceDate) ?? referenceDate
        )
    }
}

extension RecoveryCalculatorTests {
    func testOlderThirtyDayHistoryAndFutureSessionsDoNotChangeSevenDayCalculation() {
        let current = [makeActivity(daysAgo: 1, load: 45, effort: 30, avgHR: 150)]
        let other = (8...14).map { makeActivity(daysAgo: $0, load: 900, effort: 300, avgHR: 180) }
            + [makeActivity(daysAgo: -1, load: 900, effort: 300, avgHR: 180)]
        let expected = makeCalculator().calculateSummary(from: current)
        let result = makeCalculator().calculateSummary(from: current + other)
        XCTAssertEqual(result.score, expected.score)
        XCTAssertEqual(result.trends.first?.currentValue, expected.trends.first?.currentValue)
        XCTAssertFalse(result.insights.contains { $0.title == "휴식일 부족" })
        XCTAssertFalse(makeCalculator().calculateSummary(from: other).hasCalculatedScore)
    }

    func testSevenDayWindowUsesCalendarDayBoundaryAndCountsOnlyToday() {
        let today = Calendar.current.startOfDay(for: referenceDate)
        let firstDay = Calendar.current.date(byAdding: .day, value: -6, to: today)!
        func at(_ date: Date) -> RecoveryActivity {
            RecoveryActivity(workoutType: .run, durationMinutes: 20, distanceKm: 3, averageHeartRate: 140, relativeEffort: 20, trainingLoad: 30, completedAt: date)
        }
        let inputs = [at(firstDay), at(firstDay.addingTimeInterval(-1)), at(today), at(referenceDate)]
        let calculator = makeCalculator()
        XCTAssertEqual(calculator.activitiesInCalculationWindow(from: inputs).count, 3)
        let summary = calculator.calculateSummary(from: inputs)
        XCTAssertEqual(summary.activityCountToday, 2)
        XCTAssertEqual(summary.trends.first?.currentValue, "90")
    }

    func testMissingHeartRatesNeverBecomeZeroMeasurementsOrLowerAnObservedAverage() {
        let summary = makeCalculator().calculateSummary(from: [
            makeActivity(daysAgo: 0, load: 30, effort: 20, avgHR: 150),
            makeActivity(daysAgo: 1, load: 30, effort: 20, avgHR: 0)
        ])
        let heartRate = summary.trends.first { $0.title == "평균 심박" }
        XCTAssertEqual(heartRate?.currentValue, "150")
        XCTAssertEqual(heartRate?.values, [150])
        let missing = makeCalculator().calculateSummary(from: [makeActivity(daysAgo: 0, load: 30, effort: 20, avgHR: 0)])
        XCTAssertEqual(missing.trends.first { $0.title == "평균 심박" }?.currentValue, "-")
        XCTAssertEqual(missing.trends.first { $0.title == "평균 심박" }?.values, [])
        XCTAssertTrue(missing.hasCalculatedScore, "Time-only workouts remain valid calculation input")
    }

    func testNoRecentHeartRateDoesNotClaimADecreaseToZero() {
        let summary = makeCalculator().calculateSummary(from: [
            makeActivity(daysAgo: 6, load: 30, effort: 20, avgHR: 150),
            makeActivity(daysAgo: 0, load: 30, effort: 20, avgHR: 0)
        ])
        XCTAssertEqual(summary.trends.first { $0.title == "평균 심박" }?.changeText, "최근 심박 기록 부족")
    }
}
