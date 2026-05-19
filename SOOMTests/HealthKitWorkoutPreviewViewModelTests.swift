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
