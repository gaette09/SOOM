import XCTest
@testable import SOOM

final class RelativeEffortHistoryProviderTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testExcludesTargetWorkoutAndOutOfWindowActivities() async {
        let target = makeWorkout(daysAgo: 0, durationSeconds: 1_800, distanceMeters: 5_000)
        let withinWindow = makeWorkout(daysAgo: 5, durationSeconds: 1_800, distanceMeters: 5_000)
        let outsideWindow = makeWorkout(daysAgo: 30, durationSeconds: 1_800, distanceMeters: 5_000)
        let excludedFromAnalysis = makeWorkout(daysAgo: 3, durationSeconds: 1_800, distanceMeters: 5_000, isExcluded: true)

        let store = FakeRelativeEffortWorkoutStore(
            workouts: [target, withinWindow, outsideWindow, excludedFromAnalysis]
        )
        let provider = SwiftDataRelativeEffortHistoryProvider(store: store)

        let efforts = await provider.recentRelativeEfforts(
            excluding: target.id,
            before: target.startDate,
            lookbackDays: 21
        )

        XCTAssertEqual(efforts.count, 1)
    }

    func testEmptyStoreReturnsEmptyEfforts() async {
        let store = FakeRelativeEffortWorkoutStore(workouts: [])
        let provider = SwiftDataRelativeEffortHistoryProvider(store: store)

        let efforts = await provider.recentRelativeEfforts(
            excluding: UUID(),
            before: baseDate,
            lookbackDays: 21
        )

        XCTAssertTrue(efforts.isEmpty)
    }

    private func makeWorkout(
        daysAgo: Int,
        durationSeconds: TimeInterval,
        distanceMeters: Double?,
        isExcluded: Bool = false
    ) -> UnifiedWorkout {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
        return UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: .appleHealthKit,
            workoutType: .running,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 300,
            averageHeartRate: 140,
            maxHeartRate: 160,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 20,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcluded,
            createdAt: startDate,
            updatedAt: startDate
        )
    }
}

private final class FakeRelativeEffortWorkoutStore: UnifiedWorkoutStore {
    private let workouts: [UnifiedWorkout]

    init(workouts: [UnifiedWorkout]) {
        self.workouts = workouts
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {}
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {}
    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] { workouts }
    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}
    func deleteWorkout(id: UUID) async throws {}
}
