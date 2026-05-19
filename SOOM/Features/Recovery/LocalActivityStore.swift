import Foundation

final class LocalActivityStore: RecoveryActivityStore {
    private let mapper: RecoveryActivityMapper
    private let snapshots: [LocalWorkoutSnapshot]
    private let referenceDate: Date

    init(
        mapper: RecoveryActivityMapper = RecoveryActivityMapper(),
        snapshots: [LocalWorkoutSnapshot]? = nil,
        referenceDate: Date = Date()
    ) {
        self.mapper = mapper
        self.referenceDate = referenceDate
        self.snapshots = snapshots ?? LocalWorkoutSnapshot.mockRecent(referenceDate: referenceDate)
    }

    func fetchRecentActivities(days: Int) async throws -> [RecoveryActivity] {
        await Task.yield()

        guard days > 0 else { return [] }

        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        return snapshots
            .filter { $0.completedAt >= threshold }
            .map(mapper.map)
    }
}
