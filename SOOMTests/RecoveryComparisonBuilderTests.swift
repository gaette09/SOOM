import XCTest
@testable import SOOM

final class RecoveryComparisonBuilderTests: XCTestCase {
    private let builder = RecoveryComparisonBuilder()

    func testSmallDifferenceBuildsSimilarComparison() {
        let official = makeSummary(score: 82)
        let preview = makeSummary(score: 78)

        let comparison = builder.build(officialSummary: official, previewSummary: preview)

        XCTAssertEqual(comparison.officialScore, 82)
        XCTAssertEqual(comparison.previewScore, 78)
        XCTAssertEqual(comparison.difference, 4)
        XCTAssertEqual(comparison.differenceLevel, .similar)
        XCTAssertTrue(comparison.comparisonMessage.contains("비슷"))
    }

    func testMediumDifferenceBuildsModerateComparison() {
        let official = makeSummary(score: 82)
        let preview = makeSummary(score: 72)

        let comparison = builder.build(officialSummary: official, previewSummary: preview)

        XCTAssertEqual(comparison.difference, 10)
        XCTAssertEqual(comparison.differenceLevel, .moderate)
        XCTAssertTrue(comparison.comparisonMessage.contains("회복 부하"))
        XCTAssertTrue(comparison.recommendation.contains("확인"))
    }

    func testLargeDifferenceBuildsLargeComparison() {
        let official = makeSummary(score: 86)
        let preview = makeSummary(score: 68)

        let comparison = builder.build(officialSummary: official, previewSummary: preview)

        XCTAssertEqual(comparison.difference, 18)
        XCTAssertEqual(comparison.differenceLevel, .large)
        XCTAssertTrue(comparison.comparisonMessage.contains("차이"))
        XCTAssertTrue(comparison.recommendation.contains("반영하기 전"))
    }

    func testComparisonCopyAvoidsNegativeJudgementWords() {
        let comparison = builder.build(
            officialSummary: makeSummary(score: 90),
            previewSummary: makeSummary(score: 62)
        )
        let copy = [
            comparison.comparisonMessage,
            comparison.recommendation,
            comparison.confidenceNote
        ].joined(separator: " ")

        XCTAssertFalse(copy.contains("틀렸"))
        XCTAssertFalse(copy.contains("잘못"))
        XCTAssertFalse(copy.contains("문제"))
    }

    func testOfficialSummaryIsNotMutated() {
        let official = makeSummary(score: 82, recommendation: "공식 추천 유지")
        let preview = makeSummary(score: 70, recommendation: "미리보기 추천")

        let comparison = builder.build(officialSummary: official, previewSummary: preview)

        XCTAssertEqual(comparison.officialScore, official.score)
        XCTAssertEqual(official.recommendation, "공식 추천 유지")
        XCTAssertEqual(preview.recommendation, "미리보기 추천")
    }

    private func makeSummary(score: Int, recommendation: String = "오늘은 가볍게 리듬을 확인해보세요.") -> RecoverySummary {
        RecoverySummary(
            score: score,
            status: score >= 80 ? "좋음" : "주의",
            description: "테스트용 회복 설명",
            recommendation: recommendation,
            trendText: "테스트 흐름",
            coachMessage: RecoveryCoachMessage(
                coachName: "SOOM AI 코치",
                subtitle: "테스트",
                message: "테스트 메시지"
            ),
            recommendationCard: RecoveryRecommendation(
                title: "테스트 추천",
                description: recommendation,
                actionLabel: "확인",
                icon: SOOMIcon.recovery
            ),
            trends: [],
            insights: [],
            lastUpdated: Date(timeIntervalSince1970: 1_778_716_800),
            dataQuality: .estimated
        )
    }
}
