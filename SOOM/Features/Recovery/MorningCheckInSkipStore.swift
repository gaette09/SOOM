import Foundation

final class MorningCheckInSkipStore {
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let key: String
    private let now: () -> Date

    init(
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        key: String = "soom.morningCheckIn.skippedDate",
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.key = key
        self.now = now
    }

    func markSkippedToday() {
        userDefaults.set(now().timeIntervalSince1970, forKey: key)
    }

    func hasSkippedToday() -> Bool {
        clearTodaySkipIfNeeded()

        guard let skippedDate else {
            return false
        }

        return calendar.isDate(skippedDate, inSameDayAs: now())
    }

    func clearTodaySkipIfNeeded() {
        guard let skippedDate else {
            return
        }

        if !calendar.isDate(skippedDate, inSameDayAs: now()) {
            userDefaults.removeObject(forKey: key)
        }
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }

    private var skippedDate: Date? {
        guard userDefaults.object(forKey: key) != nil else {
            return nil
        }

        return Date(timeIntervalSince1970: userDefaults.double(forKey: key))
    }
}
