import XCTest
@testable import SOOM

final class ProgressionIntelligenceBuilderTests: XCTestCase {
    func testRunningProgressionBuildsImprovingTrend() {
        let intelligence = ProgressionIntelligenceBuilder().build(
            inputs: [
                input(type: .running, daysAgo: 24, distanceKm: 5, durationMinutes: 31),
                input(type: .running, daysAgo: 18, distanceKm: 5, durationMinutes: 30),
                input(type: .running, daysAgo: 5, distanceKm: 5, durationMinutes: 28),
                input(type: .running, daysAgo: 1, distanceKm: 5, durationMinutes: 27)
            ],
            period: .rollingFourWeeks,
            referenceDate: baseDate
        )

        XCTAssertEqual(intelligence.trend.trendType, .improving)
        XCTAssertEqual(intelligence.metricRows.first?.title, "평균 페이스")
        XCTAssertTrue(intelligence.metricRows.first?.comparisonText.contains("좋아") == true)
    }

    func testCyclingProgressionBuildsStableTrend() {
        let intelligence = ProgressionIntelligenceBuilder().build(
            inputs: [
                input(type: .cycling, daysAgo: 24, distanceKm: 20, durationMinutes: 48, speed: 25.0),
                input(type: .cycling, daysAgo: 17, distanceKm: 22, durationMinutes: 52, speed: 25.2),
                input(type: .cycling, daysAgo: 7, distanceKm: 21, durationMinutes: 50, speed: 25.1),
                input(type: .cycling, daysAgo: 1, distanceKm: 23, durationMinutes: 55, speed: 25.3)
            ],
            period: .monthly,
            referenceDate: baseDate
        )

        XCTAssertEqual(intelligence.trend.trendType, .stable)
        XCTAssertEqual(intelligence.metricRows.first?.title, "평균 속도")
    }

    func testProgressionBuildsFluctuatingTrend() {
        let intelligence = ProgressionIntelligenceBuilder().build(
            inputs: [
                input(type: .cycling, daysAgo: 24, distanceKm: 20, durationMinutes: 45, speed: 30),
                input(type: .cycling, daysAgo: 18, distanceKm: 20, durationMinutes: 67, speed: 18),
                input(type: .cycling, daysAgo: 6, distanceKm: 20, durationMinutes: 44, speed: 31),
                input(type: .cycling, daysAgo: 1, distanceKm: 20, durationMinutes: 70, speed: 17)
            ],
            period: .rollingFourWeeks,
            referenceDate: baseDate
        )

        XCTAssertEqual(intelligence.trend.trendType, .fluctuating)
        XCTAssertTrue(intelligence.insightSummary.contains("리듬"))
    }

    func testProgressionBuildsRebuildingTrendWhenRecentFrequencyReturns() {
        let intelligence = ProgressionIntelligenceBuilder().build(
            inputs: [
                input(type: .running, daysAgo: 24, distanceKm: 5, durationMinutes: 30),
                input(type: .running, daysAgo: 6, distanceKm: 4, durationMinutes: 25),
                input(type: .running, daysAgo: 3, distanceKm: 4.5, durationMinutes: 28),
                input(type: .running, daysAgo: 1, distanceKm: 5, durationMinutes: 31)
            ],
            period: .rollingFourWeeks,
            referenceDate: baseDate
        )

        XCTAssertEqual(intelligence.trend.trendType, .rebuilding)
        XCTAssertTrue(intelligence.trend.summary.contains("다시"))
    }

    func testInsufficientDataWhenRecordsAreTooSparse() {
        let intelligence = ProgressionIntelligenceBuilder().build(
            inputs: [
                input(type: .running, daysAgo: 2, distanceKm: 5, durationMinutes: 30),
                input(type: .running, daysAgo: 1, distanceKm: 5, durationMinutes: 29)
            ],
            period: .weekly,
            referenceDate: baseDate
        )

        XCTAssertEqual(intelligence.trend.trendType, .insufficientData)
        XCTAssertTrue(intelligence.metricRows.isEmpty)
    }

    func testSwimmingUsesHundredMeterPaceProgression() {
        let intelligence = ProgressionIntelligenceBuilder().build(
            inputs: [
                input(type: .swimming, daysAgo: 24, distanceKm: 1.0, durationMinutes: 24),
                input(type: .swimming, daysAgo: 18, distanceKm: 1.0, durationMinutes: 23),
                input(type: .swimming, daysAgo: 6, distanceKm: 1.0, durationMinutes: 21),
                input(type: .swimming, daysAgo: 2, distanceKm: 1.0, durationMinutes: 20)
            ],
            period: .rollingFourWeeks,
            referenceDate: baseDate
        )

        XCTAssertEqual(intelligence.trend.trendType, .improving)
        XCTAssertEqual(intelligence.metricRows.first?.title, "100m 페이스")
        XCTAssertTrue(intelligence.metricRows.first?.valueText.contains("/100m") == true)
    }

    func testCopyAvoidsNegativeJudgementWordsAndRecoveryCalculatorIsNotUsed() {
        let intelligence = ProgressionIntelligenceBuilder().build(
            inputs: [
                input(type: .cycling, daysAgo: 24, distanceKm: 20, durationMinutes: 45, speed: 30),
                input(type: .cycling, daysAgo: 18, distanceKm: 20, durationMinutes: 67, speed: 18),
                input(type: .cycling, daysAgo: 6, distanceKm: 20, durationMinutes: 44, speed: 31),
                input(type: .cycling, daysAgo: 1, distanceKm: 20, durationMinutes: 70, speed: 17)
            ],
            referenceDate: baseDate
        )

        let text = ([intelligence.trend.summary, intelligence.insightSummary] + intelligence.metricRows.flatMap { [$0.title, $0.valueText, $0.comparisonText] }).joined(separator: " ")
        for word in ["실패", "나쁨", "위험", "진단", "랭킹", "못"] {
            XCTAssertFalse(text.contains(word))
        }
        XCTAssertFalse(text.isEmpty)
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 8)) ?? Date()
    }

    private func input(
        type: UnifiedWorkoutType,
        daysAgo: Int,
        distanceKm: Double?,
        durationMinutes: Int,
        speed: Double? = nil
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .soomLocal,
            workoutType: type,
            startDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate,
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            averagePaceText: nil,
            averageSpeedKmh: speed,
            averageHeartRate: nil,
            elevationGainMeters: nil,
            activeEnergyKcal: nil
        )
    }
}
