import XCTest
@testable import SOOM

@MainActor
final class HealthKitWorkoutPreviewViewModelTests: XCTestCase {
    func testLoadRecentWorkoutsPopulatesWorkouts() async {
        let workouts = [
            makeWorkout(type: .running),
            makeWorkout(type: .cycling)
        ]
        let fetcher = FakePreviewWorkoutFetcher(workouts: workouts)
        let viewModel = HealthKitWorkoutPreviewViewModel(fetcher: fetcher, limit: 5)

        await viewModel.loadRecentWorkouts()

        XCTAssertEqual(viewModel.workouts, workouts)
        XCTAssertEqual(fetcher.requestedLimit, 5)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadRecentWorkoutsKeepsEmptyState() async {
        let viewModel = HealthKitWorkoutPreviewViewModel(
            fetcher: FakePreviewWorkoutFetcher(workouts: [])
        )

        await viewModel.loadRecentWorkouts()

        XCTAssertTrue(viewModel.workouts.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFetchFailureSetsErrorMessage() async {
        let viewModel = HealthKitWorkoutPreviewViewModel(
            fetcher: FakePreviewWorkoutFetcher(error: TestError.fetchFailed)
        )

        await viewModel.loadRecentWorkouts()

        XCTAssertTrue(viewModel.workouts.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testLoadingStateTurnsOffAfterSuccess() async {
        let viewModel = HealthKitWorkoutPreviewViewModel(
            fetcher: FakePreviewWorkoutFetcher(workouts: [makeWorkout(type: .swimming)])
        )

        XCTAssertFalse(viewModel.isLoading)

        await viewModel.loadRecentWorkouts()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.workouts.count, 1)
    }

    private func makeWorkout(type: HealthKitWorkoutType) -> HealthKitWorkout {
        let endDate = Date(timeIntervalSince1970: 1_800_000_000)
        return HealthKitWorkout(
            id: UUID(),
            workoutType: type,
            startDate: endDate.addingTimeInterval(-3_600),
            endDate: endDate,
            duration: 3_600,
            distance: 10_000,
            averageHeartRate: 148,
            calories: 520
        )
    }
}

private final class FakePreviewWorkoutFetcher: HealthKitWorkoutFetching {
    private let workouts: [HealthKitWorkout]
    private let error: Error?
    private(set) var requestedLimit: Int?

    init(workouts: [HealthKitWorkout] = [], error: Error? = nil) {
        self.workouts = workouts
        self.error = error
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] {
        requestedLimit = limit

        if let error {
            throw error
        }

        return workouts
    }
}

private enum TestError: Error {
    case fetchFailed
}

@MainActor
final class SkeletonLoadingLifecycleTests: XCTestCase {
    func testSlowInitialLoadCoalescesAndFinishesEmptyWithoutSkeletonSticking() async {
        let remote = SkeletonControlledFetcher()
        let model = HealthKitWorkoutPreviewViewModel(fetcher: remote)
        let first = Task { await model.loadRecentWorkouts() }
        await remote.waitUntilRequested()
        XCTAssertTrue(model.isLoading); XCTAssertTrue(model.workouts.isEmpty)
        await model.loadRecentWorkouts()
        XCTAssertEqual(remote.calls, 1)
        remote.complete(.success([])); await first.value
        XCTAssertFalse(model.isLoading); XCTAssertTrue(model.workouts.isEmpty); XCTAssertNil(model.errorMessage)
    }
    func testRefreshKeepsContentAndFailureDoesNotClearItThenRetryRecovers() async {
        let remote = SkeletonControlledFetcher()
        let model = HealthKitWorkoutPreviewViewModel(fetcher: remote)
        let row = remote.sample
        let initial = Task { await model.loadRecentWorkouts() }; await remote.waitUntilRequested()
        remote.complete(.success([row])); await initial.value
        let refresh = Task { await model.loadRecentWorkouts() }; await remote.waitUntilRequested()
        XCTAssertEqual(model.workouts, [row]); XCTAssertTrue(model.isLoading)
        remote.complete(.failure(NSError(domain: "Synthetic", code: 1))); await refresh.value
        XCTAssertEqual(model.workouts, [row]); XCTAssertFalse(model.isLoading); XCTAssertNotNil(model.errorMessage)
        let retry = Task { await model.loadRecentWorkouts() }; await remote.waitUntilRequested()
        XCTAssertEqual(model.workouts, [row])
        remote.complete(.success([])); await retry.value
        XCTAssertTrue(model.workouts.isEmpty); XCTAssertNil(model.errorMessage); XCTAssertEqual(remote.calls, 3)
    }
    func testCancellationDropsLateResultClearsLoadingAndAllowsRetry() async {
        let remote = SkeletonControlledFetcher()
        let model = HealthKitWorkoutPreviewViewModel(fetcher: remote)
        let cancelled = Task { await model.loadRecentWorkouts() }; await remote.waitUntilRequested()
        cancelled.cancel(); remote.complete(.success([remote.sample])); await cancelled.value
        XCTAssertFalse(model.isLoading); XCTAssertTrue(model.workouts.isEmpty); XCTAssertNil(model.errorMessage)
        let retry = Task { await model.loadRecentWorkouts() }; await remote.waitUntilRequested()
        remote.complete(.success([remote.sample])); await retry.value
        XCTAssertEqual(model.workouts.count, 1); XCTAssertEqual(remote.calls, 2)
    }
    func testReadingPresentationStateDoesNotFetchAgain() async {
        let remote = SkeletonControlledFetcher()
        let model = HealthKitWorkoutPreviewViewModel(fetcher: remote)
        let task = Task { await model.loadRecentWorkouts() }; await remote.waitUntilRequested()
        remote.complete(.success([remote.sample])); await task.value
        for _ in 0..<100 { _ = model.isLoading; _ = model.workouts; _ = model.errorMessage }
        XCTAssertEqual(remote.calls, 1)
    }
}

private final class SkeletonControlledFetcher: HealthKitWorkoutFetching {
    private let lock=NSLock()
    private var storedCalls=0
    var calls:Int {lock.withLock {storedCalls}}
    private var continuation: CheckedContinuation<[HealthKitWorkout], Error>?
    var sample: HealthKitWorkout {
        HealthKitWorkout(id: UUID(uuidString: "D3000000-0000-4000-8000-000000000099")!, workoutType: .running,
            startDate: Date(timeIntervalSince1970: 1_800_000_000), endDate: Date(timeIntervalSince1970: 1_800_003_600),
            duration: 3600, distance: 10000, averageHeartRate: 148, calories: 520)
    }
    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] {
        return try await withCheckedThrowingContinuation { pending in
            lock.withLock {storedCalls += 1;continuation=pending}
        }
    }
    func waitUntilRequested() async {while !lock.withLock({continuation != nil}) {await Task.yield()}}
    func complete(_ result: Result<[HealthKitWorkout], Error>) {
        let c=lock.withLock {let value=continuation;continuation=nil;return value}
        c?.resume(with:result)
    }
}
