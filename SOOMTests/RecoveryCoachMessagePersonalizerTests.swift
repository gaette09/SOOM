import XCTest
@testable import SOOM

final class RecoveryCoachMessagePersonalizerTests: XCTestCase {
    private let personalizer = RecoveryCoachMessagePersonalizer()

    func testHighFatiguePersonalizesCoachMessageTowardRecovery() {
        let summary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(fatigue: 5)

        let personalized = personalizer.personalize(summary: summary, latestCheckIn: checkIn)

        XCTAssertTrue(personalized.coachMessage.message.contains("피로감"))
        XCTAssertTrue(personalized.coachMessage.message.contains("회복"))
        XCTAssertEqual(personalized.score, summary.score)
        XCTAssertEqual(personalized.status, summary.status)
    }

    func testLowSleepQualityPersonalizesCoachMessageTowardLightActivity() {
        let summary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(sleepQuality: 1)

        let personalized = personalizer.personalize(summary: summary, latestCheckIn: checkIn)

        XCTAssertTrue(personalized.coachMessage.message.contains("수면감"))
        XCTAssertTrue(personalized.coachMessage.message.contains("가벼운"))
        XCTAssertEqual(personalized.score, summary.score)
        XCTAssertEqual(personalized.status, summary.status)
    }

    func testNilCheckInKeepsOriginalCoachMessage() {
        let summary = RecoverySummary.mockToday

        let personalized = personalizer.personalize(summary: summary, latestCheckIn: nil)

        XCTAssertEqual(personalized.coachMessage.message, summary.coachMessage.message)
        XCTAssertEqual(personalized.score, summary.score)
        XCTAssertEqual(personalized.status, summary.status)
    }

    func testPersonalizationKeepsScoreAndStatusUnchanged() {
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
