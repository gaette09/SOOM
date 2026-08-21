import XCTest
@testable import SOOM

final class FeedStreakCalculatorTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    // Wednesday, 2026-01-21.
    private var referenceDate: Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 1, day: 21).date!
    }

    func testNoWorkoutsProducesZeroStreak() {
        let result = WeeklyStreakCalculator.calculate(workoutDates: [], referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(result.weekCount, 0)
        XCTAssertEqual(result.activityCount, 0)
    }

    func testCurrentWeekActivityCountsAsStreakOfOne() {
        // Monday of the reference week.
        let currentWeekDate = date(2026, 1, 19)
        let result = WeeklyStreakCalculator.calculate(workoutDates: [currentWeekDate], referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(result.weekCount, 1)
        XCTAssertEqual(result.activityCount, 1)
    }

    func testEmptyCurrentWeekDoesNotBreakPriorStreak() {
        // Two consecutive prior weeks have activity; current week (containing referenceDate) has none yet.
        let lastWeek = date(2026, 1, 12)
        let weekBefore = date(2026, 1, 5)
        let result = WeeklyStreakCalculator.calculate(
            workoutDates: [lastWeek, weekBefore],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(result.weekCount, 2)
        XCTAssertEqual(result.activityCount, 2)
    }

    func testGapBreaksStreak() {
        let currentWeek = date(2026, 1, 19)
        // Skip the week of Jan 12, then another activity the week of Jan 5.
        let twoWeeksAgo = date(2026, 1, 5)
        let result = WeeklyStreakCalculator.calculate(
            workoutDates: [currentWeek, twoWeeksAgo],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(result.weekCount, 1)
        XCTAssertEqual(result.activityCount, 1)
    }

    func testMultipleActivitiesInSameWeekSumIntoActivityCount() {
        let mondayThisWeek = date(2026, 1, 19)
        let wednesdayThisWeek = date(2026, 1, 21)
        let result = WeeklyStreakCalculator.calculate(
            workoutDates: [mondayThisWeek, wednesdayThisWeek],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(result.weekCount, 1)
        XCTAssertEqual(result.activityCount, 2)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day).date!
    }
}
