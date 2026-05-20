import XCTest
@testable import SOOM

final class MorningCheckInStateBuilderTests: XCTestCase {
    func testTodayCheckInBuildsCheckedInToday() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let checkIn = makeCheckIn(date: today.addingTimeInterval(3_600))
        let builder = MorningCheckInStateBuilder(calendar: gregorianCalendar)

        XCTAssertEqual(
            builder.build(latestCheckIn: checkIn, today: today),
            .checkedInToday
        )
    }

    func testYesterdayCheckInBuildsNotCheckedInToday() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = today.addingTimeInterval(-86_400)
        let builder = MorningCheckInStateBuilder(calendar: gregorianCalendar)

        XCTAssertEqual(
            builder.build(latestCheckIn: makeCheckIn(date: yesterday), today: today),
            .notCheckedInToday
        )
    }

    func testNilCheckInBuildsNotCheckedInToday() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let builder = MorningCheckInStateBuilder(calendar: gregorianCalendar)

        XCTAssertEqual(
            builder.build(latestCheckIn: nil, today: today),
            .notCheckedInToday
        )
    }

    func testSkippedTodayBuildsSkippedToday() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let builder = MorningCheckInStateBuilder(calendar: gregorianCalendar)

        XCTAssertEqual(
            builder.build(latestCheckIn: nil, today: today, hasSkippedToday: true),
            .skippedToday
        )
    }

    func testTodayCheckInTakesPriorityOverSkippedToday() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let checkIn = makeCheckIn(date: today.addingTimeInterval(3_600))
        let builder = MorningCheckInStateBuilder(calendar: gregorianCalendar)

        XCTAssertEqual(
            builder.build(latestCheckIn: checkIn, today: today, hasSkippedToday: true),
            .checkedInToday
        )
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func makeCheckIn(date: Date) -> RecoveryCheckIn {
        RecoveryCheckIn(
            date: date,
            fatigueLevel: 3,
            sleepQuality: 4,
            muscleSoreness: 2,
            moodLevel: 4
        )
    }
}
