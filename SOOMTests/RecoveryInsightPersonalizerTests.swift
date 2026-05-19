import XCTest
@testable import SOOM

final class RecoveryInsightPersonalizerTests: XCTestCase {
    private let personalizer = RecoveryInsightPersonalizer()

    func testHighFatigueAddsFatigueInsightFirst() {
        let summary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(fatigue: 5)

        let personalized = personalizer.personalize(summary: summary, latestCheckIn: checkIn)

        XCTAssertEqual(personalized.insights.first?.title, "피로감이 높게 기록됐어요")
        XCTAssertEqual(personalized.insights.count, summary.insights.count + 1)
    }

    func testLowSleepQualityAddsSleepInsight() {
        let summary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(sleepQuality: 1)

        let personalized = personalizer.personalize(summary: summary, latestCheckIn: checkIn)

        XCTAssertEqual(personalized.insights.first?.title, "수면감이 낮아요")
        XCTAssertEqual(personalized.insights.count, summary.insights.count + 1)
    }

    func testNilCheckInKeepsInsights() {
        let summary = RecoverySummary.mockToday

        let personalized = personalizer.personalize(summary: summary, latestCheckIn: nil)

        XCTAssertEqual(personalized.insights.count, summary.insights.count)
        XCTAssertEqual(personalized.insights.first?.title, summary.insights.first?.title)
    }

    func testPersonalizationKeepsScoreStatusAndRecommendationUnchanged() {
        let summary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(
            fatigue: 5,
            sleepQuality: 1,
            muscleSoreness: 5,
            mood: 1
        )

        let personalized = personalizer.personalize(summary: summary, latestCheckIn: checkIn)

        XCTAssertEqual(personalized.score, summary.score)
        XCTAssertEqual(personalized.status, summary.status)
        XCTAssertEqual(personalized.recommendation, summary.recommendation)
        XCTAssertEqual(personalized.trends.count, summary.trends.count)
    }

    func testOnlyOnePersonalizedInsightIsAdded() {
        let summary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(
            fatigue: 5,
            sleepQuality: 1,
            muscleSoreness: 5,
            mood: 1
        )

        let personalized = personalizer.personalize(summary: summary, latestCheckIn: checkIn)

        XCTAssertEqual(personalized.insights.count, summary.insights.count + 1)
        XCTAssertEqual(personalized.insights.first?.title, "피로감이 높게 기록됐어요")
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
