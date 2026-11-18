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

    func testDistanceRoundedToZeroUsesNeutralCopy() {
        let baseline = makeInput(type: .running, distance: 10, duration: 50)

        for delta in [0, 0.04, -0.04] {
            let current = makeInput(type: .running, distance: 10 + delta, duration: 50)
            assertNeutralRow(
                current: current, baseline: baseline, title: "거리",
                detail: "이전 기록과 비슷한 거리를 움직였어요."
            )
        }
    }

    func testPaceRoundedToZeroUsesNeutralCopy() {
        let baseline = makeInput(type: .running, distance: 10, duration: 50)

        for delta in [0, 0.4, -0.4] {
            let current = makeInput(type: .running, distance: 3000 / (300 - delta), duration: 50)
            assertNeutralRow(
                current: current, baseline: baseline, title: "페이스",
                detail: "이전 기록과 비슷한 페이스를 유지했어요."
            )
        }
    }

    func testSwimmingPaceRoundedToZeroPerHundredMetersUsesNeutralCopy() {
        let baseline = makeInput(type: .swimming, distance: 1.5, duration: 30)

        for delta in [0, 0.4, -0.4] {
            let current = makeInput(type: .swimming, distance: 1800 / (1200 - delta * 10), duration: 30)
            assertNeutralRow(
                current: current, baseline: baseline, title: "100m 페이스",
                detail: "이전 기록과 비슷한 100m 리듬을 이어갔어요."
            )
        }
    }

    func testSpeedRoundedToZeroUsesNeutralCopy() {
        let baseline = makeInput(type: .cycling, distance: 25, duration: 60, speed: 25)

        for delta in [0, 0.04, -0.04] {
            let current = makeInput(type: .cycling, distance: 25, duration: 60, speed: 25 + delta)
            assertNeutralRow(
                current: current, baseline: baseline, title: "평균 속도",
                detail: "이전 기록과 비슷한 평균 속도로 움직였어요."
            )
        }
    }

    func testElevationRoundedToZeroUsesNeutralCopy() {
        let baseline = makeInput(type: .cycling, distance: 25, duration: 60, elevation: 200)

        for delta in [0, 0.4, -0.4] {
            let current = makeInput(type: .cycling, distance: 25, duration: 60, elevation: 200 + delta)
            assertNeutralRow(
                current: current, baseline: baseline, title: "상승 고도",
                detail: "이전 기록과 비슷한 상승 고도를 기록했어요."
            )
        }
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

    private func assertNeutralRow(
        current: WorkoutGrowthInput,
        baseline: WorkoutGrowthInput,
        title: String,
        detail: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let insight = builder.build(current: current, baseline: baseline)
        let row = insight.metricRows.first { $0.title == title }

        XCTAssertEqual(row?.valueText, "비슷함", file: file, line: line)
        XCTAssertEqual(row?.detailText, detail, file: file, line: line)
        XCTAssertEqual(insight.tone, .steady, file: file, line: line)
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
