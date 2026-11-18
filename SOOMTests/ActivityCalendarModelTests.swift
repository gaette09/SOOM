import XCTest
@testable import SOOM

final class ActivityCalendarModelTests: XCTestCase {
    func testMonthGridUsesActualMonthAndWeekdayAlignment() {
        let calendar = calendar(timeZone: "Asia/Seoul", firstWeekday: 1)
        let model = ActivityCalendarModel(referenceDate: date(2026, 9, 15, calendar: calendar), calendar: calendar)
        let dates = model.dayCells.compactMap { $0 }
        XCTAssertEqual(dates.count, 30)
        XCTAssertNil(model.dayCells[0])
        XCTAssertNil(model.dayCells[1]) // September 1, 2026 is Tuesday.
        XCTAssertEqual(calendar.component(.day, from: dates.first!), 1)
        XCTAssertEqual(calendar.component(.day, from: dates.last!), 30)
        XCTAssertTrue(dates.allSatisfy { calendar.component(.month, from: $0) == 9 })
        XCTAssertEqual(model.dayCells.count % 7, 0)
    }

    func testLeapYearFebruaryAndMondayFirstCalendar() {
        let calendar = calendar(timeZone: "UTC", firstWeekday: 2)
        let leap = ActivityCalendarModel(referenceDate: date(2024, 2, 20, calendar: calendar), calendar: calendar)
        let ordinary = ActivityCalendarModel(referenceDate: date(2025, 2, 20, calendar: calendar), calendar: calendar)
        XCTAssertEqual(leap.dayCells.compactMap { $0 }.count, 29)
        XCTAssertEqual(ordinary.dayCells.compactMap { $0 }.count, 28)
        XCTAssertTrue(leap.dayCells.prefix(3).allSatisfy { $0 == nil }) // Thursday under Monday-first.
        XCTAssertNotNil(leap.dayCells[3])
        XCTAssertEqual(leap.weekdaySymbols.first, calendar.veryShortStandaloneWeekdaySymbols[1])
    }

    func testMonthNavigationCrossesYearAndClearsDayFilter() {
        let calendar = calendar(timeZone: "Asia/Seoul")
        var model = ActivityCalendarModel(referenceDate: date(2026, 12, 31, calendar: calendar), calendar: calendar)
        model.selectDate(date(2026, 12, 31, calendar: calendar))
        model.moveMonth(by: 1)
        XCTAssertNil(model.selectedDate)
        XCTAssertEqual(model.displayedMonth, date(2027, 1, 1, calendar: calendar))
        model.moveMonth(by: -1)
        XCTAssertEqual(model.displayedMonth, date(2026, 12, 1, calendar: calendar))
        model.moveMonth(by: 2)
        XCTAssertEqual(model.dayCells.compactMap { $0 }.count, 28)
    }

    func testDaySelectionAndEntireMonthRetainPrivateOrAnalysisExcludedRecords() {
        let calendar = calendar(timeZone: "Asia/Seoul")
        var model = ActivityCalendarModel(referenceDate: date(2026, 9, 15, calendar: calendar), calendar: calendar)
        let first = workout(date(2026, 9, 5, hour: 8, calendar: calendar))
        let excluded = workout(date(2026, 9, 5, hour: 18, calendar: calendar), excluded: true)
        let anotherDay = workout(date(2026, 9, 6, calendar: calendar))
        model.selectDate(date(2026, 9, 5, hour: 12, calendar: calendar))
        XCTAssertEqual(model.selectedDate, date(2026, 9, 5, calendar: calendar))
        XCTAssertEqual(model.visibleWorkouts([first, excluded, anotherDay]).map(\.id), [excluded.id, first.id])
        model.showEntireMonth()
        XCTAssertEqual(model.visibleWorkouts([first, excluded, anotherDay]).map(\.id), [anotherDay.id, excluded.id, first.id])
        XCTAssertTrue(model.visibleWorkouts([excluded]).first!.isExcludedFromAnalysis)
    }

    func testMonthEndIsExclusiveAndOldHistoryHasNo180DayLimit() {
        let calendar = calendar(timeZone: "UTC")
        let model = ActivityCalendarModel(referenceDate: date(2020, 1, 15, calendar: calendar), calendar: calendar)
        let start = workout(date(2020, 1, 1, calendar: calendar))
        let last = workout(date(2020, 2, 1, calendar: calendar).addingTimeInterval(-1))
        let nextMonth = workout(date(2020, 2, 1, calendar: calendar))
        let previousMonth = workout(date(2019, 12, 31, calendar: calendar))
        XCTAssertEqual(model.visibleWorkouts([nextMonth, previousMonth, start, last]).map(\.id), [last.id, start.id])
    }

    func testDayGroupingUsesViewerTimeZoneAndStartDate() {
        let seoul = calendar(timeZone: "Asia/Seoul")
        let utc = calendar(timeZone: "UTC")
        var model = ActivityCalendarModel(referenceDate: date(2026, 9, 1, calendar: seoul), calendar: seoul)
        let localSeptember = workout(date(2026, 8, 31, hour: 16, calendar: utc)) // Sep 1 at 01:00 in Seoul.
        let localAugust = workout(date(2026, 8, 31, hour: 14, calendar: utc))
        model.selectDate(date(2026, 9, 1, calendar: seoul))
        XCTAssertEqual(model.visibleWorkouts([localAugust, localSeptember]).map(\.id), [localSeptember.id])
        XCTAssertEqual(model.workoutCountsByDay([localAugust, localSeptember]), [date(2026, 9, 1, calendar: seoul): 1])
    }

    func testDaylightSavingDayIsNotAssumedToBe24Hours() {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        var model = ActivityCalendarModel(referenceDate: date(2026, 3, 8, calendar: calendar), calendar: calendar)
        model.selectDate(date(2026, 3, 8, calendar: calendar))
        XCTAssertEqual(model.visibleInterval?.duration, 23 * 3_600)
        let before = workout(date(2026, 3, 7, hour: 23, calendar: calendar))
        let morning = workout(date(2026, 3, 8, hour: 1, calendar: calendar))
        let evening = workout(date(2026, 3, 8, hour: 23, calendar: calendar))
        let nextDay = workout(date(2026, 3, 9, calendar: calendar))
        XCTAssertEqual(model.visibleWorkouts([nextDay, before, morning, evening]).map(\.id), [evening.id, morning.id])
        model.showCurrentMonth(referenceDate: date(2026, 11, 1, calendar: calendar))
        model.selectDate(date(2026, 11, 1, calendar: calendar))
        XCTAssertEqual(model.visibleInterval?.duration, 25 * 3_600)
    }

    func testMissingDayAndEmptyMonthAreEmptyWithoutFallbackToLatestRecord() {
        let calendar = calendar(timeZone: "Asia/Seoul")
        var model = ActivityCalendarModel(referenceDate: date(2026, 9, 15, calendar: calendar), calendar: calendar)
        let saved = workout(date(2026, 9, 1, calendar: calendar))
        model.selectDate(date(2026, 9, 2, calendar: calendar))
        XCTAssertTrue(model.visibleWorkouts([saved]).isEmpty)
        model.moveMonth(by: 1)
        XCTAssertTrue(model.visibleWorkouts([saved]).isEmpty)
        XCTAssertTrue(model.workoutCountsByDay([saved]).isEmpty)
        XCTAssertTrue(model.visibleWorkouts([]).isEmpty)
    }

    func testDayCountsAndListUpdateFromNewSavedInputWithoutChangingSelection() {
        let calendar = calendar(timeZone: "Asia/Seoul")
        var model = ActivityCalendarModel(referenceDate: date(2026, 9, 15, calendar: calendar), calendar: calendar)
        let selectedDate = date(2026, 9, 15, calendar: calendar)
        model.selectDate(selectedDate)
        let first = workout(date(2026, 9, 15, hour: 7, calendar: calendar))
        let second = workout(date(2026, 9, 15, hour: 18, calendar: calendar))
        XCTAssertEqual(model.workoutCountsByDay([first])[selectedDate], 1)
        XCTAssertEqual(model.workoutCountsByDay([first, second])[selectedDate], 2)
        XCTAssertEqual(model.visibleWorkouts([first, second]).map(\.id), [second.id, first.id])
        XCTAssertEqual(model.selectedDate, selectedDate)
        XCTAssertEqual(model.visibleWorkouts([second]).map(\.id), [second.id])
    }

    func testDaySummaryUsesEarliestWorkoutRegardlessOfImportOrder() {
        let calendar = calendar(timeZone: "Asia/Seoul")
        let model = ActivityCalendarModel(referenceDate: date(2026, 9, 15, calendar: calendar), calendar: calendar)
        let day = date(2026, 9, 15, calendar: calendar)
        let morningRide = workout(date(2026, 9, 15, hour: 7, calendar: calendar), type: .cycling)
        let eveningRun = workout(date(2026, 9, 15, hour: 18, calendar: calendar), type: .running)
        let nextDaySwim = workout(date(2026, 9, 16, hour: 6, calendar: calendar), type: .swimming)

        let summaries = model.workoutSummariesByDay([eveningRun, nextDaySwim, morningRide])
        XCTAssertEqual(summaries[day], ActivityCalendarDaySummary(firstWorkoutType: .cycling, count: 2))
        XCTAssertEqual(summaries[date(2026, 9, 16, calendar: calendar)],
                       ActivityCalendarDaySummary(firstWorkoutType: .swimming, count: 1))
    }

    func testOutOfMonthSelectionIsIgnoredAndTodayReturnsToCurrentMonth() {
        let calendar = calendar(timeZone: "UTC")
        var model = ActivityCalendarModel(referenceDate: date(2025, 12, 15, calendar: calendar), calendar: calendar)
        model.selectDate(date(2026, 1, 1, calendar: calendar))
        XCTAssertNil(model.selectedDate)
        model.selectDate(date(2025, 12, 15, calendar: calendar))
        model.showCurrentMonth(referenceDate: date(2026, 9, 15, calendar: calendar))
        XCTAssertNil(model.selectedDate)
        XCTAssertEqual(model.displayedMonth, date(2026, 9, 1, calendar: calendar))
    }

    private func calendar(timeZone: String, firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func workout(_ startDate: Date, excluded: Bool = false, type: UnifiedWorkoutType = .running) -> UnifiedWorkout {
        UnifiedWorkout(
            id: UUID(), externalId: nil, source: .manual, workoutType: type,
            startDate: startDate, endDate: startDate.addingTimeInterval(1_800), durationSeconds: 1_800,
            distanceMeters: 5_000, activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .partial,
            isExcludedFromAnalysis: excluded, createdAt: startDate, updatedAt: startDate
        )
    }
}
