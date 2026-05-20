import XCTest
@testable import SOOM

final class HealthKitWorkoutImportPipelineTests: XCTestCase {
    func testImportsFetchedHealthKitWorkoutsIntoUnifiedWorkoutStore() async {
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, type: .running),
                    makeWorkout(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, type: .cycling)
                ])
            ),
            store: store,
            mappedAt: { Date(timeIntervalSince1970: 1_800_200_000) }
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)

        XCTAssertEqual(result.fetchedCount, 2)
        XCTAssertEqual(result.savedCount, 2)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.importedWorkouts.map(\.source), [.appleHealthKit, .appleHealthKit])
        XCTAssertEqual(store.savedWorkouts.count, 2)
        XCTAssertEqual(store.savedWorkouts.map(\.workoutType), [.running, .cycling])
    }

    func testEmptyFetchReturnsEmptySuccessResult() async {
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(result: .success([])),
            store: store
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.fetchedCount, 0)
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(result.importedWorkouts.isEmpty)
        XCTAssertTrue(store.savedWorkouts.isEmpty)
    }

    func testFetchFailureReturnsSafeFailedResult() async {
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(result: .failure(SampleError.fetchFailed)),
            store: store
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(result.importedWorkouts.isEmpty)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertTrue(store.savedWorkouts.isEmpty)
    }

    func testReimportWithSameExternalIdAndSourceDoesNotIncreaseStoreCount() async {
        let workoutID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: workoutID, type: .running, distance: 5_000)
                ])
            ),
            store: store
        )

        _ = await pipeline.importRecentWorkouts()
        _ = await pipeline.importRecentWorkouts()

        XCTAssertEqual(store.savedWorkouts.count, 1)
        XCTAssertEqual(store.savedWorkouts.first?.externalId, workoutID.uuidString)
    }

    func testStoreFailureReturnsFailedSaveResult() async {
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(type: .swimming)
                ])
            ),
            store: FakeUnifiedWorkoutStore(saveError: SampleError.saveFailed)
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.fetchedCount, 1)
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(result.importedWorkouts.isEmpty)
        XCTAssertFalse(result.message.isEmpty)
    }

    private func makeWorkout(
        id: UUID = UUID(),
        type: HealthKitWorkoutType,
        startDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        duration: TimeInterval = 3_600,
        distance: Double? = 10_000,
        averageHeartRate: Double? = 148,
        calories: Double? = 520
    ) -> HealthKitWorkout {
        HealthKitWorkout(
            id: id,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            duration: duration,
            distance: distance,
            averageHeartRate: averageHeartRate,
            calories: calories
        )
    }
}

private final class FakeHealthKitWorkoutFetcher: HealthKitWorkoutFetching {
    private let result: Result<[HealthKitWorkout], Error>

    init(result: Result<[HealthKitWorkout], Error>) {
        self.result = result
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] {
        try result.get()
    }
}

private final class FakeUnifiedWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout] = []
    private let saveError: Error?

    init(saveError: Error? = nil) {
        self.saveError = saveError
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        try await saveWorkouts([workout])
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        if let saveError {
            throw saveError
        }

        for workout in workouts {
            upsert(workout)
        }
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        savedWorkouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.id == id }
    }

    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.externalId == externalId && $0.source == source }
    }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}

    func deleteWorkout(id: UUID) async throws {
        savedWorkouts.removeAll { $0.id == id }
    }

    private func upsert(_ workout: UnifiedWorkout) {
        if let externalId = workout.externalId,
           let index = savedWorkouts.firstIndex(where: { $0.externalId == externalId && $0.source == workout.source }) {
            savedWorkouts[index] = workout
        } else if let index = savedWorkouts.firstIndex(where: { $0.id == workout.id }) {
            savedWorkouts[index] = workout
        } else {
            savedWorkouts.append(workout)
        }
    }
}

private enum SampleError: Error {
    case fetchFailed
    case saveFailed
}
