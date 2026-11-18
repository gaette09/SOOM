import XCTest
@testable import SOOM

final class FitnessTrendHistoryProviderTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testBucketsSameDayWorkoutsAndFillsRestDaysWithZero() async {
        // Two separate sessions on one day, not two imported copies of the same session.
        let day0a = makeWorkout(daysAgo: 0, durationSeconds: 1_800, startHour: 8)
        let day0b = makeWorkout(daysAgo: 0, durationSeconds: 1_800, startHour: 18)
        let day2 = makeWorkout(daysAgo: 2, durationSeconds: 1_800)

        let store = FakeFitnessTrendWorkoutStore(workouts: [day0a, day0b, day2])
        let provider = SwiftDataFitnessTrendHistoryProvider(store: store)

        let dailyLoads = await provider.dailyTrainingLoads(upTo: baseDate, windowDays: 3)

        // Ascending: day-2, day-1 (rest), day-0 (two workouts summed).
        XCTAssertEqual(dailyLoads.count, 3)
        XCTAssertGreaterThan(dailyLoads[0], 0)
        XCTAssertEqual(dailyLoads[1], 0)
        XCTAssertEqual(dailyLoads[2], dailyLoads[0] * 2, accuracy: 0.01)
    }

    func testCountsMatchingImportedCopiesOnlyOnce() async {
        let original = makeWorkout(daysAgo: 0, durationSeconds: 1_800)
        let importedCopy = makeWorkout(daysAgo: 0, durationSeconds: 1_800)
        let provider = SwiftDataFitnessTrendHistoryProvider(
            store: FakeFitnessTrendWorkoutStore(workouts: [original, importedCopy]))

        let dailyLoads = await provider.dailyTrainingLoads(upTo: baseDate, windowDays: 1)

        let singleSessionLoad = UnifiedWorkoutToRecoveryActivityMapper().map(original).trainingLoad
        XCTAssertGreaterThan(singleSessionLoad, 0)
        XCTAssertEqual(dailyLoads, [singleSessionLoad])
    }

    func testExcludesWorkoutsMarkedExcludedFromAnalysis() async {
        let excluded = makeWorkout(daysAgo: 0, durationSeconds: 1_800, isExcluded: true)
        let store = FakeFitnessTrendWorkoutStore(workouts: [excluded])
        let provider = SwiftDataFitnessTrendHistoryProvider(store: store)

        let dailyLoads = await provider.dailyTrainingLoads(upTo: baseDate, windowDays: 3)

        XCTAssertEqual(dailyLoads, [0, 0, 0])
    }

    func testExcludesWorkoutsOutsideWindow() async {
        let outsideWindow = makeWorkout(daysAgo: 10, durationSeconds: 1_800)
        let store = FakeFitnessTrendWorkoutStore(workouts: [outsideWindow])
        let provider = SwiftDataFitnessTrendHistoryProvider(store: store)

        let dailyLoads = await provider.dailyTrainingLoads(upTo: baseDate, windowDays: 3)

        XCTAssertEqual(dailyLoads, [0, 0, 0])
    }

    func testEmptyStoreReturnsAllZeroDays() async {
        let store = FakeFitnessTrendWorkoutStore(workouts: [])
        let provider = SwiftDataFitnessTrendHistoryProvider(store: store)

        let dailyLoads = await provider.dailyTrainingLoads(upTo: baseDate, windowDays: 5)

        XCTAssertEqual(dailyLoads, [0, 0, 0, 0, 0])
    }

    private func makeWorkout(
        daysAgo: Int,
        durationSeconds: TimeInterval,
        isExcluded: Bool = false,
        startHour: Int = 8
    ) -> UnifiedWorkout {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
        let startDate = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: day) ?? day
        return UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: .appleHealthKit,
            workoutType: .running,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: 5_000,
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

private final class FakeFitnessTrendWorkoutStore: UnifiedWorkoutStore {
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
    func deleteAllWorkouts() async throws {}
}
