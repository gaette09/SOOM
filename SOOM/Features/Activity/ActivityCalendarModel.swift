import Foundation

struct ActivityCalendarDaySummary: Equatable {
    let firstWorkoutType: UnifiedWorkoutType
    let count: Int
}

/// Calendar boundaries use the viewer's calendar/time zone, never fixed second offsets.
/// Filtering is display-only: excluded/private workouts remain in their owner's library.
struct ActivityCalendarModel {
    let calendar: Calendar
    private(set) var displayedMonth: Date
    private(set) var selectedDate: Date?

    init(referenceDate: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        displayedMonth = calendar.dateInterval(of: .month, for: referenceDate)?.start
            ?? calendar.startOfDay(for: referenceDate)
    }

    var monthInterval: DateInterval? {
        calendar.dateInterval(of: .month, for: displayedMonth)
    }

    var visibleInterval: DateInterval? {
        guard let selectedDate else { return monthInterval }
        return calendar.dateInterval(of: .day, for: selectedDate)
    }

    /// Nil cells align the first/last week without pretending adjacent dates are in this month.
    var dayCells: [Date?] {
        guard let interval = monthInterval,
              let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: leadingCount)
        cells += range.compactMap { day in
            calendar.date(byAdding: .day, value: day - range.lowerBound, to: interval.start)
        }.map { Optional($0) }
        let trailingCount = (7 - cells.count % 7) % 7
        cells += Array<Date?>(repeating: nil, count: trailingCount)
        return cells
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
    }

    mutating func moveMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth),
              let interval = calendar.dateInterval(of: .month, for: next) else { return }
        displayedMonth = interval.start
        selectedDate = nil
    }

    mutating func selectDate(_ date: Date) {
        guard let interval = monthInterval, contains(date, in: interval) else { return }
        selectedDate = calendar.startOfDay(for: date)
    }

    mutating func showEntireMonth() {
        selectedDate = nil
    }

    mutating func showCurrentMonth(referenceDate: Date = Date()) {
        guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else { return }
        displayedMonth = interval.start
        selectedDate = nil
    }

    func visibleWorkouts(_ workouts: [UnifiedWorkout]) -> [UnifiedWorkout] {
        guard let interval = visibleInterval else { return [] }
        return workouts.filter { contains($0.startDate, in: interval) }.sorted {
            if $0.startDate != $1.startDate { return $0.startDate > $1.startDate }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func workoutCountsByDay(_ workouts: [UnifiedWorkout]) -> [Date: Int] {
        workoutSummariesByDay(workouts).mapValues(\.count)
    }

    func workoutSummariesByDay(_ workouts: [UnifiedWorkout]) -> [Date: ActivityCalendarDaySummary] {
        guard let interval = monthInterval else { return [:] }
        let monthWorkouts = workouts.filter { contains($0.startDate, in: interval) }
        let grouped = Dictionary(grouping: monthWorkouts) { calendar.startOfDay(for: $0.startDate) }
        return grouped.mapValues { dayWorkouts in
            let first = dayWorkouts.min {
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.id.uuidString < $1.id.uuidString
            }!
            return ActivityCalendarDaySummary(firstWorkoutType: first.workoutType, count: dayWorkouts.count)
        }
    }

    private func contains(_ date: Date, in interval: DateInterval) -> Bool {
        // DateInterval.contains includes its end; adjacent months must not share a record.
        date >= interval.start && date < interval.end
    }
}
