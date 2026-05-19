import XCTest
@testable import SOOM

final class RecoveryCheckInSignalClassifierTests: XCTestCase {
    private let classifier = RecoveryCheckInSignalClassifier()

    func testHighFatigueClassifiesAsHighFatigue() {
        XCTAssertEqual(classifier.classify(makeCheckIn(fatigue: 4)), .highFatigue)
    }

    func testLowSleepClassifiesAsLowSleep() {
        XCTAssertEqual(classifier.classify(makeCheckIn(sleepQuality: 2)), .lowSleep)
    }

    func testHighSorenessClassifiesAsHighSoreness() {
        XCTAssertEqual(classifier.classify(makeCheckIn(muscleSoreness: 4)), .highSoreness)
    }

    func testLowMoodClassifiesAsLowMood() {
        XCTAssertEqual(classifier.classify(makeCheckIn(mood: 2)), .lowMood)
    }

    func testOverlappingSignalsPreferHighFatigue() {
        let checkIn = makeCheckIn(
            fatigue: 5,
            sleepQuality: 1,
            muscleSoreness: 5,
            mood: 1
        )

        XCTAssertEqual(classifier.classify(checkIn), .highFatigue)
    }

    func testNilCheckInClassifiesAsStable() {
        XCTAssertEqual(classifier.classify(nil), .stable)
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
