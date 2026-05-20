import Foundation

struct MorningCheckInStateBuilder {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func build(
        latestCheckIn: RecoveryCheckIn?,
        today: Date = Date(),
        hasSkippedToday: Bool = false
    ) -> MorningCheckInState {
        if let latestCheckIn, calendar.isDate(latestCheckIn.date, inSameDayAs: today) {
            return .checkedInToday
        }

        if hasSkippedToday {
            return .skippedToday
        }

        return .notCheckedInToday
    }
}
