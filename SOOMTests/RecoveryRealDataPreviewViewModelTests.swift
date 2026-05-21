import XCTest
@testable import SOOM

@MainActor
final class RecoveryRealDataPreviewViewModelTests: XCTestCase {
    func testLoadPublishesSummaryAndUsedWorkoutCount() async {
        let viewModel = RecoveryRealDataPreviewViewModel(
            provider: UnifiedWorkoutRecoveryPreviewProvider(
                store: FakeRealDataPreviewWorkoutStore(workouts: [makeWorkout(daysAgo: 0)]),
                calculator: RecoveryCalculator(referenceDate: baseDate)
            )
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.usedWorkoutCount, 1)
        XCTAssertNotNil(viewModel.summary)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testEmptyDataPublishesInsufficientDataWithoutError() async {
        let viewModel = RecoveryRealDataPreviewViewModel(
            provider: UnifiedWorkoutRecoveryPreviewProvider(
                store: FakeRealDataPreviewWorkoutStore(workouts: []),
                calculator: RecoveryCalculator(referenceDate: baseDate)
            )
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.usedWorkoutCount, 0)
        XCTAssertEqual(viewModel.summary?.status, "데이터 부족")
        XCTAssertTrue(viewModel.hasInsufficientWorkoutData)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testProviderFailureSetsErrorMessage() async {
        let viewModel = RecoveryRealDataPreviewViewModel(
            provider: UnifiedWorkoutRecoveryPreviewProvider(
                store: FakeRealDataPreviewWorkoutStore(workouts: [], error: PreviewError.failed)
            )
        )

        await viewModel.load()

        XCTAssertNil(viewModel.summary)
        XCTAssertEqual(viewModel.usedWorkoutCount, 0)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testExcludedWorkoutDoesNotContributeToUsedCountOrSummary() async {
        let viewModel = RecoveryRealDataPreviewViewModel(
            provider: UnifiedWorkoutRecoveryPreviewProvider(
                store: FakeRealDataPreviewWorkoutStore(workouts: [
                    makeWorkout(daysAgo: 0, isExcluded: true)
                ]),
                calculator: RecoveryCalculator(referenceDate: baseDate)
            )
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.usedWorkoutCount, 0)
        XCTAssertEqual(viewModel.summary?.status, "데이터 부족")
    }


    func testLoadPublishesComparisonWhenOfficialProviderIsAvailable() async {
        let officialSummary = RecoverySummary.mockToday
        let viewModel = RecoveryRealDataPreviewViewModel(
            provider: UnifiedWorkoutRecoveryPreviewProvider(
                store: FakeRealDataPreviewWorkoutStore(workouts: [makeWorkout(daysAgo: 0)]),
                calculator: RecoveryCalculator(referenceDate: baseDate)
            ),
            officialProvider: FakeOfficialRecoveryDataProvider(summary: officialSummary)
        )

        await viewModel.load()

        XCTAssertNotNil(viewModel.comparison)
        XCTAssertEqual(viewModel.comparison?.officialScore, officialSummary.score)
        XCTAssertEqual(viewModel.comparison?.previewScore, viewModel.summary?.score)
        XCTAssertNil(viewModel.errorMessage)
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 21, hour: 7)) ?? Date()
    }

    private func makeWorkout(daysAgo: Int, isExcluded: Bool = false) -> UnifiedWorkout {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
        return UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: .appleHealthKit,
            workoutType: .cycling,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: 28_000,
            activeEnergyKcal: 520,
            averageHeartRate: 146,
            maxHeartRate: 171,
            averageSpeedMetersPerSecond: 7.7,
            elevationGainMeters: 88,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcluded,
            createdAt: startDate,
            updatedAt: startDate
        )
    }
}

private enum PreviewError: Error {
    case failed
}

private final class FakeRealDataPreviewWorkoutStore: UnifiedWorkoutStore {
    private let workouts: [UnifiedWorkout]
    private let error: Error?

    init(workouts: [UnifiedWorkout], error: Error? = nil) {
        self.workouts = workouts
        self.error = error
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {}
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {}

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        if let error { throw error }
        return workouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func deleteWorkout(id: UUID) async throws {}
}

private struct FakeOfficialRecoveryDataProvider: RecoveryDataProvider {
    let summary: RecoverySummary

    func fetchRecoverySummary() async throws -> RecoverySummary {
        summary
    }
}
