import XCTest
@testable import SOOM

final class WorkoutComparisonHistoryProviderTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testExcludesTargetWorkoutAndAnalysisExcludedRecords() async {
        let target = makeWorkout(daysAgo: 0, durationSeconds: 1_800, distanceMeters: 5_000)
        let first = makeWorkout(daysAgo: 5, durationSeconds: 1_800, distanceMeters: 5_000)
        let second = makeWorkout(daysAgo: 30, durationSeconds: 1_800, distanceMeters: 5_000)
        let excluded = makeWorkout(daysAgo: 3, durationSeconds: 1_800, distanceMeters: 5_000, isExcluded: true)
        let store = FakeComparisonHistoryWorkoutStore(workouts: [target, first, second, excluded])
        let provider = SwiftDataWorkoutComparisonHistoryProvider(store: store)

        let workouts = await provider.comparisonWorkouts(excluding: target.id)

        XCTAssertEqual(workouts.map(\.id), [first.id, second.id])
    }

    func testMapsUnifiedWorkoutToDetailWorkout() async {
        let workout = makeWorkout(daysAgo: 5, durationSeconds: 3_600, distanceMeters: 25_000, workoutType: .cycling)
        let store = FakeComparisonHistoryWorkoutStore(workouts: [workout])
        let provider = SwiftDataWorkoutComparisonHistoryProvider(store: store)

        let workouts = await provider.comparisonWorkouts(excluding: UUID())

        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.id, workout.id)
        XCTAssertEqual(workouts.first?.date, workout.startDate)
        XCTAssertEqual(workouts.first?.sport, .bike)
        XCTAssertEqual(workouts.first?.distanceMeters, workout.distanceMeters)
    }

    func testFetchFailureReturnsEmpty() async {
        let workout = makeWorkout(daysAgo: 5, durationSeconds: 1_800, distanceMeters: 5_000)
        let store = FakeComparisonHistoryWorkoutStore(workouts: [workout], shouldThrow: true)
        let provider = SwiftDataWorkoutComparisonHistoryProvider(store: store)

        let workouts = await provider.comparisonWorkouts(excluding: UUID())

        XCTAssertTrue(workouts.isEmpty)
    }

    func testDefaultLookbackCoversRecentWorkoutList() async {
        let store = FakeComparisonHistoryWorkoutStore(workouts: [])
        let provider = SwiftDataWorkoutComparisonHistoryProvider(store: store)

        _ = await provider.comparisonWorkouts(excluding: UUID())

        XCTAssertEqual(store.fetchedDays, 180)
    }

    private func makeWorkout(
        daysAgo: Int,
        durationSeconds: TimeInterval,
        distanceMeters: Double?,
        workoutType: UnifiedWorkoutType = .running,
        isExcluded: Bool = false
    ) -> UnifiedWorkout {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
        return UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: .appleHealthKit,
            workoutType: workoutType,
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

private final class FakeComparisonHistoryWorkoutStore: UnifiedWorkoutStore {
    private let workouts: [UnifiedWorkout]
    private let shouldThrow: Bool
    private(set) var fetchedDays: Int?

    init(workouts: [UnifiedWorkout], shouldThrow: Bool = false) {
        self.workouts = workouts
        self.shouldThrow = shouldThrow
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {}
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {}
    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        fetchedDays = days
        if shouldThrow { throw FetchError.failed }
        return workouts
    }
    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}
    func deleteWorkout(id: UUID) async throws {}
    func deleteAllWorkouts() async throws {}

    private enum FetchError: Error {
        case failed
    }
}
