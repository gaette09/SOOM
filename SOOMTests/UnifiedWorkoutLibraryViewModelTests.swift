import XCTest
@testable import SOOM

@MainActor
final class UnifiedWorkoutLibraryViewModelTests: XCTestCase {
    func testLoadRecentWorkoutsPopulatesWorkouts() async {
        let workouts = [
            makeWorkout(type: .running),
            makeWorkout(type: .cycling)
        ]
        let store = FakeUnifiedWorkoutLibraryStore(workouts: workouts)
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()

        XCTAssertEqual(viewModel.workouts, workouts)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadRecentWorkoutsKeepsEmptyState() async {
        let viewModel = UnifiedWorkoutLibraryViewModel(
            store: FakeUnifiedWorkoutLibraryStore(workouts: [])
        )

        await viewModel.loadRecentWorkouts()

        XCTAssertTrue(viewModel.workouts.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testStoreFailureSetsErrorMessage() async {
        let viewModel = UnifiedWorkoutLibraryViewModel(
            store: FakeUnifiedWorkoutLibraryStore(error: SampleError.fetchFailed)
        )

        await viewModel.loadRecentWorkouts()

        XCTAssertTrue(viewModel.workouts.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testUsesThirtyDaysAsDefaultRecentRange() async {
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()

        XCTAssertEqual(store.requestedDays, 30)
    }

    func testPreservesExcludedFromAnalysisState() async {
        let excludedWorkout = makeWorkout(type: .swimming, isExcludedFromAnalysis: true)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [excludedWorkout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()

        XCTAssertEqual(viewModel.workouts.first?.isExcludedFromAnalysis, true)
    }

    func testToggleExcludedMarksWorkoutExcluded() async {
        let workout = makeWorkout(type: .running)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [workout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()
        await viewModel.toggleExcluded(id: workout.id)

        XCTAssertEqual(store.markedExclusionState[workout.id], true)
        XCTAssertEqual(viewModel.workouts.first?.isExcludedFromAnalysis, true)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testToggleExcludedMarksWorkoutIncluded() async {
        let workout = makeWorkout(type: .cycling, isExcludedFromAnalysis: true)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [workout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()
        await viewModel.toggleExcluded(id: workout.id)

        XCTAssertEqual(store.markedExclusionState[workout.id], false)
        XCTAssertEqual(viewModel.workouts.first?.isExcludedFromAnalysis, false)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testToggleExcludedFailureSetsErrorMessage() async {
        let workout = makeWorkout(type: .running)
        let store = FakeUnifiedWorkoutLibraryStore(
            workouts: [workout],
            markError: SampleError.markFailed
        )
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()
        await viewModel.toggleExcluded(id: workout.id)

        XCTAssertEqual(viewModel.workouts.first?.isExcludedFromAnalysis, false)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testToggleExcludedDoesNotDeleteOrMergeWorkouts() async {
        let workout = makeWorkout(type: .running)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [workout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()
        await viewModel.toggleExcluded(id: workout.id)

        XCTAssertFalse(store.didDeleteWorkout)
        XCTAssertFalse(store.didSaveWorkout)
        XCTAssertFalse(store.didSaveWorkouts)
    }

    private func makeWorkout(
        type: UnifiedWorkoutType,
        isExcludedFromAnalysis: Bool = false
    ) -> UnifiedWorkout {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(45 * 60)

        return UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: .appleHealthKit,
            workoutType: type,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: 45 * 60,
            distanceMeters: 10_000,
            activeEnergyKcal: 500,
            averageHeartRate: 145,
            maxHeartRate: 168,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 70,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcludedFromAnalysis,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private final class FakeUnifiedWorkoutLibraryStore: UnifiedWorkoutStore {
    private var workouts: [UnifiedWorkout]
    private let error: Error?
    private let markError: Error?
    private(set) var requestedDays: Int?
    private(set) var markedExclusionState: [UUID: Bool] = [:]
    private(set) var didDeleteWorkout = false
    private(set) var didSaveWorkout = false
    private(set) var didSaveWorkouts = false

    init(
        workouts: [UnifiedWorkout] = [],
        error: Error? = nil,
        markError: Error? = nil
    ) {
        self.workouts = workouts
        self.error = error
        self.markError = markError
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        didSaveWorkout = true
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        didSaveWorkouts = true
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        requestedDays = days

        if let error {
            throw error
        }

        return workouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {
        if let markError {
            throw markError
        }

        markedExclusionState[id] = isExcluded
    }

    func deleteWorkout(id: UUID) async throws {
        didDeleteWorkout = true
    }
}

private enum SampleError: Error {
    case fetchFailed
    case markFailed
}
