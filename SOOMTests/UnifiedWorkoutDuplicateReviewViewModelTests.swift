import XCTest
@testable import SOOM

@MainActor
final class UnifiedWorkoutDuplicateReviewViewModelTests: XCTestCase {
    func testLoadCreatesDuplicateCandidates() async {
        let startDate = Date()
        let workouts = [
            makeWorkout(source: .garmin, startDate: startDate, externalId: "garmin-ride"),
            makeWorkout(source: .appleHealthKit, startDate: startDate.addingTimeInterval(120), externalId: "health-ride")
        ]
        let store = FakeUnifiedWorkoutDuplicateReviewStore(workouts: workouts)
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(store: store)

        await viewModel.loadDuplicateCandidates()

        XCTAssertEqual(viewModel.candidates.count, 1)
        XCTAssertEqual(viewModel.candidates.first?.preferredSource, .garmin)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadKeepsEmptyStateWhenThereAreNoDuplicates() async {
        let startDate = Date()
        let workouts = [
            makeWorkout(type: .running, source: .appleHealthKit, startDate: startDate, distanceMeters: 10_000),
            makeWorkout(type: .cycling, source: .garmin, startDate: startDate.addingTimeInterval(3_600), distanceMeters: 42_000)
        ]
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(
            store: FakeUnifiedWorkoutDuplicateReviewStore(workouts: workouts)
        )

        await viewModel.loadDuplicateCandidates()

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testStoreFailureSetsErrorMessage() async {
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(
            store: FakeUnifiedWorkoutDuplicateReviewStore(error: SampleError.fetchFailed)
        )

        await viewModel.loadDuplicateCandidates()

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testUsesThirtyDaysAsDefaultRecentRange() async {
        let store = FakeUnifiedWorkoutDuplicateReviewStore(workouts: [])
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(store: store)

        await viewModel.loadDuplicateCandidates()

        XCTAssertEqual(store.requestedDays, 30)
    }

    func testLoadDoesNotDeleteMergeOrMarkWorkouts() async {
        let startDate = Date()
        let workouts = [
            makeWorkout(source: .garmin, startDate: startDate, externalId: "garmin-ride"),
            makeWorkout(source: .appleHealthKit, startDate: startDate.addingTimeInterval(60), externalId: "health-ride")
        ]
        let store = FakeUnifiedWorkoutDuplicateReviewStore(workouts: workouts)
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(store: store)

        await viewModel.loadDuplicateCandidates()

        XCTAssertEqual(viewModel.candidates.count, 1)
        XCTAssertFalse(store.didMarkExcludedFromAnalysis)
        XCTAssertFalse(store.didDeleteWorkout)
        XCTAssertFalse(store.didSaveWorkout)
    }

    private func makeWorkout(
        type: UnifiedWorkoutType = .cycling,
        source: UnifiedDataSource,
        startDate: Date,
        externalId: String = UUID().uuidString,
        distanceMeters: Double = 41_700
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: UUID(),
            externalId: externalId,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(90 * 60),
            durationSeconds: 90 * 60,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 720,
            averageHeartRate: 148,
            maxHeartRate: 172,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 77,
            dataQuality: .partial,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private final class FakeUnifiedWorkoutDuplicateReviewStore: UnifiedWorkoutStore {
    private let workouts: [UnifiedWorkout]
    private let error: Error?
    private(set) var requestedDays: Int?
    private(set) var didMarkExcludedFromAnalysis = false
    private(set) var didDeleteWorkout = false
    private(set) var didSaveWorkout = false

    init(
        workouts: [UnifiedWorkout] = [],
        error: Error? = nil
    ) {
        self.workouts = workouts
        self.error = error
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        didSaveWorkout = true
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        didSaveWorkout = true
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
        didMarkExcludedFromAnalysis = true
    }

    func deleteWorkout(id: UUID) async throws {
        didDeleteWorkout = true
    }
}

private enum SampleError: Error {
    case fetchFailed
}
