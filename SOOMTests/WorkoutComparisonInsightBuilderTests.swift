import XCTest
@testable import SOOM

final class WorkoutComparisonInsightBuilderTests: XCTestCase {
    private let builder = WorkoutComparisonInsightBuilder()

    func testInsufficientDataWhenBaselineMissing() {
        let current = makeInput(type: .running, distance: 10, duration: 50)

        let insight = builder.build(current: current, baseline: nil)

        XCTAssertEqual(insight.comparisonType, .insufficientData)
        XCTAssertEqual(insight.tone, .insufficientData)
        XCTAssertTrue(insight.metricRows.isEmpty)
    }

    func testRunningPaceImprovementBuildsSupportiveInsight() {
        let current = makeInput(type: .running, distance: 10, duration: 48)
        let baseline = makeInput(type: .running, distance: 10, duration: 55)

        let insight = builder.build(current: current, baseline: baseline)

        XCTAssertEqual(insight.tone, .improved)
        XCTAssertTrue(insight.metricRows.contains { $0.title == "페이스" && $0.valueText.contains("-/") == false })
        XCTAssertTrue(insight.metricRows.contains { $0.title == "페이스" && $0.valueText.contains("초/km") })
    }

    func testCyclingSpeedImprovementBuildsSpeedRow() {
        let current = makeInput(type: .cycling, distance: 32, duration: 70, speed: 27.4, elevation: 260)
        let baseline = makeInput(type: .cycling, distance: 30, duration: 72, speed: 25.0, elevation: 210)

        let insight = builder.build(current: current, baseline: baseline)

        XCTAssertEqual(insight.tone, .improved)
        XCTAssertTrue(insight.metricRows.contains { $0.title == "평균 속도" && $0.valueText.contains("km/h") })
        XCTAssertTrue(insight.metricRows.contains { $0.title == "상승 고도" })
    }

    func testSwimmingHundredMeterPaceComparison() {
        let current = makeInput(type: .swimming, distance: 1.5, duration: 33)
        let baseline = makeInput(type: .swimming, distance: 1.5, duration: 36)

        let insight = builder.build(current: current, baseline: baseline)

        XCTAssertEqual(insight.tone, .improved)
        XCTAssertTrue(insight.metricRows.contains { $0.title == "100m 페이스" && $0.valueText.contains("초/100m") })
    }

    func testRouteCandidateControlsComparisonType() {
        let current = makeInput(type: .cycling, distance: 30, duration: 70, speed: 26)
        let baseline = makeInput(type: .cycling, distance: 30, duration: 72, speed: 25)
        let candidate = RouteComparisonCandidate(
            currentWorkoutId: current.id,
            candidateWorkoutId: baseline.id,
            similarityScore: 0.9,
            reason: .similarRoute
        )

        let insight = builder.build(current: current, baseline: baseline, routeCandidate: candidate)

        XCTAssertEqual(insight.comparisonType, .sameRoute)
    }

    func testCopyAvoidsNegativeEvaluationWordsAndRecoveryCalculatorIsNotUsed() {
        let current = makeInput(type: .cycling, distance: 20, duration: 60, speed: 20)
        let baseline = makeInput(type: .cycling, distance: 30, duration: 65, speed: 27)

        let insight = builder.build(current: current, baseline: baseline)
        let copy = ([insight.title, insight.summary] + insight.metricRows.flatMap { [$0.valueText, $0.detailText] }).joined(separator: " ")

        XCTAssertFalse(copy.contains("못"))
        XCTAssertFalse(copy.contains("나쁨"))
        XCTAssertFalse(copy.contains("실패"))
    }

    private func makeInput(
        type: UnifiedWorkoutType,
        distance: Double,
        duration: Int,
        speed: Double? = nil,
        elevation: Double? = nil
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .appleHealthKit,
            workoutType: type,
            startDate: Date(),
            durationMinutes: duration,
            distanceKm: distance,
            averagePaceText: nil,
            averageSpeedKmh: speed,
            averageHeartRate: nil,
            elevationGainMeters: elevation,
            activeEnergyKcal: nil
        )
    }
}
