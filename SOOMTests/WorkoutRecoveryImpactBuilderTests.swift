import XCTest
@testable import SOOM

final class WorkoutRecoveryImpactBuilderTests: XCTestCase {
    private let builder = WorkoutRecoveryImpactBuilder()

    func testLongHighIntensityWorkoutBuildsHighImpact() {
        let impact = builder.build(
            input: makeInput(durationMinutes: 95, averageHeartRate: 162)
        )

        XCTAssertEqual(impact.impactLevel, .high)
        XCTAssertTrue(impact.shortMessage.contains("회복"))
        XCTAssertFalse(impact.recommendation.isEmpty)
    }

    func testRecoveryStateWithHardWorkoutBuildsHighImpactWithoutChangingSummary() {
        let summary = makeRecoverySummary(score: 58, status: "회복 우선")

        let impact = builder.build(
            input: makeInput(durationMinutes: 82, averageHeartRate: 158),
            recoverySummary: summary
        )

        XCTAssertEqual(impact.impactLevel, .high)
        XCTAssertEqual(summary.score, 58)
        XCTAssertEqual(summary.status, "회복 우선")
        XCTAssertEqual(summary.recommendation, "가볍게 움직이기")
    }

    func testShortLightWorkoutBuildsRecoveryFriendlyImpact() {
        let impact = builder.build(
            input: makeInput(durationMinutes: 35, averageHeartRate: 128)
        )

        XCTAssertEqual(impact.impactLevel, .recoveryFriendly)
        XCTAssertTrue(impact.shortMessage.contains("가벼운"))
    }

    func testNilInputBuildsInsufficientDataImpact() {
        let impact = builder.build(input: nil)

        XCTAssertEqual(impact.impactLevel, .insufficientData)
        XCTAssertFalse(impact.recommendation.isEmpty)
    }

    func testImpactCopyAvoidsNegativeJudgementWords() {
        let impact = builder.build(
            input: makeInput(durationMinutes: 95, averageHeartRate: 162)
        )
        let copy = [impact.title, impact.shortMessage, impact.recommendation].joined(separator: " ")

        XCTAssertFalse(copy.contains("못"))
        XCTAssertFalse(copy.contains("실패"))
        XCTAssertFalse(copy.contains("나쁨"))
        XCTAssertFalse(copy.contains("위험"))
    }

    private func makeInput(
        durationMinutes: Int,
        averageHeartRate: Double?
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .soomLocal,
            workoutType: .running,
            startDate: baseDate,
            durationMinutes: durationMinutes,
            distanceKm: 10.0,
            averagePaceText: nil,
            averageSpeedKmh: nil,
            averageHeartRate: averageHeartRate,
            elevationGainMeters: 40,
            activeEnergyKcal: 500
        )
    }

    private func makeRecoverySummary(score: Int, status: String) -> RecoverySummary {
        RecoverySummary(
            score: score,
            status: status,
            description: "테스트 회복 설명",
            recommendation: "가볍게 움직이기",
            trendText: "테스트 흐름",
            coachMessage: RecoveryCoachMessage(
                coachName: "SOOM 코치",
                subtitle: "테스트",
                message: "회복 리듬을 확인해보세요."
            ),
            recommendationCard: RecoveryRecommendation(
                title: "가벼운 움직임",
                description: "부담 없는 활동",
                actionLabel: "확인",
                icon: SOOMIcon.recovery
            ),
            trends: [],
            insights: [],
            lastUpdated: baseDate,
            dataQuality: .estimated
        )
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 7)) ?? Date()
    }
}
