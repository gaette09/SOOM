import XCTest
@testable import SOOM

final class DailyReadinessBuilderTests: XCTestCase {
    private let builder = DailyReadinessBuilder()

    func testHighScoreBuildsReadyState() {
        let summary = makeSummary(score: 88, status: "좋음")

        let state = builder.build(from: summary)

        XCTAssertEqual(state.readinessLevel, .ready)
        XCTAssertEqual(state.actionTone, .proceed)
    }

    func testMediumScoreBuildsModerateState() {
        let summary = makeSummary(score: 76, status: "보통")

        let state = builder.build(from: summary)

        XCTAssertEqual(state.readinessLevel, .moderate)
        XCTAssertEqual(state.actionTone, .easeIn)
    }

    func testLowScoreBuildsRecoveryState() {
        let summary = makeSummary(score: 62, status: "주의")

        let state = builder.build(from: summary)

        XCTAssertEqual(state.readinessLevel, .recovery)
        XCTAssertEqual(state.actionTone, .recover)
    }

    func testInsufficientDataBuildsInsufficientDataState() {
        let summary = makeSummary(score: 72, status: "데이터 부족")

        let state = builder.build(from: summary)

        XCTAssertEqual(state.readinessLevel, .insufficientData)
        XCTAssertEqual(state.actionTone, .observe)
    }

    func testBuildDoesNotMutateSummaryScoreStatusOrRecommendation() {
        let summary = makeSummary(
            score: 82,
            status: "좋음",
            recommendation: "오늘은 Z2 라이딩 40분을 추천해요."
        )

        _ = builder.build(from: summary)

        XCTAssertEqual(summary.score, 82)
        XCTAssertEqual(summary.status, "좋음")
        XCTAssertEqual(summary.recommendation, "오늘은 Z2 라이딩 40분을 추천해요.")
    }

    private func makeSummary(
        score: Int,
        status: String,
        recommendation: String = "가벼운 유산소로 몸 상태를 확인해보세요."
    ) -> RecoverySummary {
        RecoverySummary(
            score: score,
            status: status,
            description: "테스트용 회복 설명입니다.",
            recommendation: recommendation,
            trendText: "",
            coachMessage: RecoveryCoachMessage(
                coachName: "SOOM AI 코치",
                subtitle: "테스트",
                message: "테스트용 코칭 메시지입니다."
            ),
            recommendationCard: RecoveryRecommendation(
                title: "오늘의 추천",
                description: "테스트용 추천 설명입니다.",
                actionLabel: "추천 보기",
                icon: SOOMIcon.recovery
            ),
            trends: [],
            insights: [],
            lastUpdated: Date(timeIntervalSince1970: 1_800_000_000),
            dataQuality: .estimated
        )
    }
}
