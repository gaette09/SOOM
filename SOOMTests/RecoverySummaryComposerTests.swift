import XCTest
@testable import SOOM

final class RecoverySummaryComposerTests: XCTestCase {
    private let composer = RecoverySummaryComposer()

    func testCheckInPersonalizesCoachMessageAndInsights() {
        let baseSummary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(fatigue: 5)

        let composed = composer.compose(
            baseSummary: baseSummary,
            latestCheckIn: checkIn
        )

        XCTAssertTrue(composed.coachMessage.message.contains("피로감"))
        XCTAssertEqual(composed.insights.first?.title, "피로감이 높게 기록됐어요")
        XCTAssertEqual(composed.insights.count, baseSummary.insights.count + 1)
    }

    func testCompositionKeepsScoreStatusRecommendationAndTrendsUnchanged() {
        let baseSummary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(
            fatigue: 5,
            sleepQuality: 1,
            muscleSoreness: 5,
            mood: 1
        )

        let composed = composer.compose(
            baseSummary: baseSummary,
            latestCheckIn: checkIn
        )

        XCTAssertEqual(composed.score, baseSummary.score)
        XCTAssertEqual(composed.status, baseSummary.status)
        XCTAssertEqual(composed.recommendation, baseSummary.recommendation)
        XCTAssertEqual(composed.trends.count, baseSummary.trends.count)
        XCTAssertEqual(composed.trends.first?.title, baseSummary.trends.first?.title)
    }

    func testNilCheckInKeepsBaseSummary() {
        let baseSummary = RecoverySummary.mockToday

        let composed = composer.compose(
            baseSummary: baseSummary,
            latestCheckIn: nil
        )

        XCTAssertEqual(composed.score, baseSummary.score)
        XCTAssertEqual(composed.status, baseSummary.status)
        XCTAssertEqual(composed.recommendation, baseSummary.recommendation)
        XCTAssertEqual(composed.coachMessage.message, baseSummary.coachMessage.message)
        XCTAssertEqual(composed.insights.count, baseSummary.insights.count)
        XCTAssertEqual(composed.insights.first?.title, baseSummary.insights.first?.title)
    }

    private func makeCheckIn(
        fatigue: Int = 2,
        sleepQuality: Int = 4,
        muscleSoreness: Int = 2,
        mood: Int = 4
    ) -> RecoveryCheckIn {
        RecoveryCheckIn(
            date: Date(),
            fatigueLevel: fatigue,
            sleepQuality: sleepQuality,
            muscleSoreness: muscleSoreness,
            moodLevel: mood,
            note: nil
        )
    }
}
