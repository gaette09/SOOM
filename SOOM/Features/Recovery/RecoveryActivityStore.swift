import Foundation

protocol RecoveryActivityStore {
    func fetchRecentActivities(days: Int) async throws -> [RecoveryActivity]
}

struct MockRecoveryActivityStore: RecoveryActivityStore {
    private let referenceDate: Date
    private let activities: [RecoveryActivity]

    init(referenceDate: Date = Date(), activities: [RecoveryActivity]? = nil) {
        self.referenceDate = referenceDate
        self.activities = activities ?? RecoveryActivity.mockWeek(referenceDate: referenceDate)
    }

    func fetchRecentActivities(days: Int) async throws -> [RecoveryActivity] {
        await Task.yield()

        guard days > 0 else { return [] }

        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        return activities.filter { $0.completedAt >= threshold }
    }
}
