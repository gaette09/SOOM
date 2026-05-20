import XCTest
@testable import SOOM

final class MorningCheckInSkipStoreTests: XCTestCase {
    func testMarkSkippedTodayStoresTodaySkip() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeStore(now: { today })

        fixture.store.markSkippedToday()

        XCTAssertTrue(fixture.store.hasSkippedToday())
        fixture.cleanup()
    }

    func testSkipExpiresWhenDateChanges() {
        var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeStore(now: { currentDate })

        fixture.store.markSkippedToday()
        currentDate = currentDate.addingTimeInterval(86_400)

        XCTAssertFalse(fixture.store.hasSkippedToday())
        fixture.cleanup()
    }

    func testClearRemovesStoredSkip() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = makeStore(now: { today })

        fixture.store.markSkippedToday()
        fixture.store.clear()

        XCTAssertFalse(fixture.store.hasSkippedToday())
        fixture.cleanup()
    }

    private func makeStore(
        now: @escaping () -> Date
    ) -> (store: MorningCheckInSkipStore, cleanup: () -> Void) {
        let suiteName = "MorningCheckInSkipStoreTests-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let store = MorningCheckInSkipStore(
            userDefaults: userDefaults,
            calendar: calendar,
            now: now
        )

        return (
            store,
            {
                userDefaults.removePersistentDomain(forName: suiteName)
            }
        )
    }
}
