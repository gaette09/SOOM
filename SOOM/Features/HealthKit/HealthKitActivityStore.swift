import Foundation

final class HealthKitActivityStore: RecoveryActivityStore {
    private let workoutFetcher: any HealthKitWorkoutFetching
    private let mapper: HealthKitRecoveryActivityMapper
    private let calendar: Calendar
    private let now: () -> Date

    init(
        workoutFetcher: any HealthKitWorkoutFetching = HealthKitWorkoutFetcher(),
        mapper: HealthKitRecoveryActivityMapper = HealthKitRecoveryActivityMapper(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.workoutFetcher = workoutFetcher
        self.mapper = mapper
        self.calendar = calendar
        self.now = now
    }

    func fetchRecentActivities(days: Int) async throws -> [RecoveryActivity] {
        guard days > 0 else { return [] }

        let fetchLimit = max(days * 4, 20)
        let threshold = calendar.date(byAdding: .day, value: -days, to: now()) ?? now()

        do {
            let workouts = try await workoutFetcher.fetchRecentWorkouts(limit: fetchLimit)
            return workouts
                .filter { $0.endDate >= threshold }
                .map(mapper.map)
        } catch {
            return []
        }
    }
}
