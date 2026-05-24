import XCTest
@testable import SOOM

final class WorkoutSplitInsightBuilderTests: XCTestCase {
    func testStablePaceBuildsStablePaceInsight() {
        let input = makeInput(
            type: .running,
            durationMinutes: 45,
            distanceKm: 10,
            averageHeartRate: 142
        )

        let insight = WorkoutSplitInsightBuilder().build(current: input)

        XCTAssertEqual(insight.splitType, .stablePace)
        XCTAssertEqual(insight.trend, .stable)
        XCTAssertTrue(insight.metricRows.contains { $0.title == "평균 페이스" })
    }

    func testLongHeavyRunBuildsFatigueDropWithoutNegativeTone() {
        let input = makeInput(
            type: .running,
            durationMinutes: 95,
            distanceKm: 12,
            averageHeartRate: 170
        )

        let insight = WorkoutSplitInsightBuilder().build(current: input)

        XCTAssertEqual(insight.splitType, .fatigueDrop)
        XCTAssertEqual(insight.trend, .lighter)
        assertNoNegativeTone(in: insight)
    }

    func testCyclingStableSpeedBuildsStableSpeedInsight() {
        let input = makeInput(
            type: .cycling,
            durationMinutes: 90,
            distanceKm: 45,
            averageSpeedKmh: 30
        )

        let insight = WorkoutSplitInsightBuilder().build(current: input)

        XCTAssertEqual(insight.splitType, .stableSpeed)
        XCTAssertTrue(insight.metricRows.contains { $0.valueText == "30.0 km/h" })
    }

    func testInsufficientDataWhenDistanceIsMissing() {
        let input = makeInput(
            type: .running,
            durationMinutes: 40,
            distanceKm: nil
        )

        let insight = WorkoutSplitInsightBuilder().build(current: input)

        XCTAssertEqual(insight.splitType, .insufficientData)
        XCTAssertEqual(insight.trend, .insufficientData)
        XCTAssertTrue(insight.metricRows.isEmpty)
    }

    func testSwimmingUsesHundredMeterPaceFlow() {
        let input = makeInput(
            type: .swimming,
            durationMinutes: 30,
            distanceKm: 1.5
        )

        let insight = WorkoutSplitInsightBuilder().build(current: input)

        XCTAssertEqual(insight.splitType, .stablePace)
        XCTAssertTrue(insight.metricRows.contains { $0.title == "100m 페이스" })
    }

    func testBuilderDoesNotUseRecoveryCalculator() {
        let input = makeInput(
            type: .cycling,
            durationMinutes: 60,
            distanceKm: 30,
            averageSpeedKmh: 30
        )

        let insight = WorkoutSplitInsightBuilder().build(current: input)

        XCTAssertNotEqual(insight.splitType, .insufficientData)
    }

    private func makeInput(
        type: UnifiedWorkoutType,
        durationMinutes: Int,
        distanceKm: Double?,
        averageSpeedKmh: Double? = nil,
        averageHeartRate: Double? = nil
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .soomLocal,
            workoutType: type,
            startDate: Date(),
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            averagePaceText: nil,
            averageSpeedKmh: averageSpeedKmh,
            averageHeartRate: averageHeartRate,
            elevationGainMeters: nil,
            activeEnergyKcal: nil
        )
    }

    private func assertNoNegativeTone(in insight: WorkoutSplitInsight) {
        let text = ([insight.title, insight.summary] + insight.metricRows.flatMap { [$0.title, $0.valueText, $0.detailText] }).joined(separator: " ")
        ["못", "실패", "나쁨", "잘못", "위험"].forEach { word in
            XCTAssertFalse(text.contains(word), "Unexpected negative tone: \(word)")
        }
    }
}
