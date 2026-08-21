import Foundation

/// Strava's real "Weekly Streak" rule: at least 1 activity per calendar week (Mon-start)
/// keeps the streak alive, counted backward from the current week. The current week
/// having zero activities *so far* does not break a streak from prior weeks — it just
/// isn't counted yet, since the week isn't over.
struct FeedStreakSnapshot: Equatable {
    let weekCount: Int
    let activityCount: Int
}

enum WeeklyStreakCalculator {
    static func calculate(
        workoutDates: [Date],
        referenceDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> FeedStreakSnapshot {
        var cal = calendar
        cal.firstWeekday = 2 // Monday, matching the calendar grid this card is modeled on.

        func weekStart(for date: Date) -> Date {
            let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return cal.date(from: components) ?? date
        }

        var countsByWeekStart: [Date: Int] = [:]
        for date in workoutDates {
            countsByWeekStart[weekStart(for: date), default: 0] += 1
        }

        var cursor = weekStart(for: referenceDate)
        if (countsByWeekStart[cursor] ?? 0) == 0 {
            guard let previousWeek = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else {
                return FeedStreakSnapshot(weekCount: 0, activityCount: 0)
            }
            cursor = previousWeek
        }

        var weekCount = 0
        var activityCount = 0
        while let count = countsByWeekStart[cursor], count > 0 {
            weekCount += 1
            activityCount += count
            guard let previousWeek = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previousWeek
        }

        return FeedStreakSnapshot(weekCount: weekCount, activityCount: activityCount)
    }
}
