import XCTest
@testable import SOOM

final class WorkoutSessionSummaryBuilderTests: XCTestCase {
    private let builder = WorkoutSessionSummaryBuilder()

    func testBuildCombinesGrowthWeaknessAndRecoveryImpact() {
        let summary = builder.build(
            growthSummary: growthSummary,
            weaknessInsight: weaknessInsight,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        XCTAssertTrue(summary.highlightText.contains("지구력"))
        XCTAssertEqual(summary.improvementText, weaknessInsight.shortInsight)
        XCTAssertEqual(summary.recoveryText, recoveryImpact.shortMessage)
        XCTAssertEqual(summary.closingMotivation, weaknessInsight.suggestion)
        XCTAssertFalse(summary.title.isEmpty)
    }

    func testBuildHandlesInsufficientDataSafely() {
        let summary = builder.build(
            growthSummary: nil,
            weaknessInsight: nil,
            recoveryImpact: nil,
            input: nil
        )

        XCTAssertFalse(summary.title.isEmpty)
        XCTAssertFalse(summary.summaryText.isEmpty)
        XCTAssertFalse(summary.highlightText.isEmpty)
        XCTAssertFalse(summary.improvementText.isEmpty)
        XCTAssertFalse(summary.recoveryText.isEmpty)
        XCTAssertFalse(summary.closingMotivation.isEmpty)
    }

    func testSummaryCopyAvoidsNegativeJudgementWords() {
        let summary = builder.build(
            growthSummary: growthSummary,
            weaknessInsight: weaknessInsight,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )
        let copy = [
            summary.title,
            summary.summaryText,
            summary.highlightText,
            summary.improvementText,
            summary.recoveryText,
            summary.closingMotivation
        ].joined(separator: " ")

        ["못", "실패", "나쁨", "위험"].forEach { word in
            XCTAssertFalse(copy.contains(word), "Session summary should keep a coaching tone without '\(word)'.")
        }
    }

    func testBuildDoesNotMutateExistingInterpretationResults() {
        let originalGrowth = growthSummary
        let originalWeakness = weaknessInsight
        let originalImpact = recoveryImpact

        _ = builder.build(
            growthSummary: originalGrowth,
            weaknessInsight: originalWeakness,
            recoveryImpact: originalImpact,
            input: growthInput
        )

        XCTAssertEqual(originalGrowth, growthSummary)
        XCTAssertEqual(originalWeakness, weaknessInsight)
        XCTAssertEqual(originalImpact, recoveryImpact)
    }

    func testHighRecoveryImpactUsesRecoveryAwareTitleWithoutChangingImpact() {
        let highImpact = WorkoutRecoveryImpact(
            impactLevel: .high,
            title: "회복 리듬을 조금 더 챙길 운동",
            shortMessage: "오늘 운동은 회복 흐름에 조금 영향을 줄 수 있어요.",
            recommendation: "다음 운동 전에는 수면감과 피로감을 확인하고 강도를 천천히 올려보세요.",
            icon: SOOMIcon.bolt
        )

        let summary = builder.build(
            growthSummary: growthSummary,
            weaknessInsight: nil,
            recoveryImpact: highImpact,
            input: growthInput
        )

        XCTAssertTrue(summary.title.contains("회복"))
        XCTAssertEqual(highImpact.impactLevel, .high)
        XCTAssertEqual(highImpact.recommendation, "다음 운동 전에는 수면감과 피로감을 확인하고 강도를 천천히 올려보세요.")
    }

    private var growthSummary: WorkoutGrowthSummary {
        WorkoutGrowthSummary(
            workoutId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "더 오래 움직였어요",
            shortSummary: "오늘은 같은 종목의 최근 기록보다 지구력 흐름이 좋아졌어요.",
            improvementType: .endurance,
            comparisonText: "10.4 km · 이전 8.8 km",
            motivationText: "지난 기록보다 더 오래 움직인 건 좋은 성장 신호예요.",
            insight: "다음에는 같은 리듬을 유지하면서 회복 여유를 확인해보세요."
        )
    }

    private var weaknessInsight: WorkoutWeaknessInsight {
        WorkoutWeaknessInsight(
            title: "후반 리듬을 더 부드럽게",
            shortInsight: "후반 리듬이 조금 흔들렸어요.",
            suggestion: "초반 강도를 조금만 낮추면 더 안정적일 수 있어요.",
            insightType: .pacing,
            icon: SOOMIcon.trendDown
        )
    }

    private var recoveryImpact: WorkoutRecoveryImpact {
        WorkoutRecoveryImpact(
            impactLevel: .moderate,
            title: "적당한 자극이 있는 운동",
            shortMessage: "오늘 운동은 몸에 적당한 자극을 남기는 흐름이에요.",
            recommendation: "다음 운동 전 회복 리듬을 한 번 확인하고 비슷한 강도를 이어가보세요.",
            icon: SOOMIcon.waveform
        )
    }

    private var growthInput: WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            source: .soomLocal,
            workoutType: .running,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: 52,
            distanceKm: 10.4,
            averagePaceText: "5:00/km",
            averageSpeedKmh: nil,
            averageHeartRate: 151,
            elevationGainMeters: 78,
            activeEnergyKcal: 676
        )
    }
}
