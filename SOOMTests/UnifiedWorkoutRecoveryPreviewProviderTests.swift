import XCTest
@testable import SOOM

final class UnifiedWorkoutRecoveryPreviewProviderTests: XCTestCase {
    func testBuildsRecoverySummaryFromUnifiedWorkoutStore() async throws {
        let store = FakeRecoveryPreviewWorkoutStore(workouts: [
            makeWorkout(daysAgo: 0, durationSeconds: 3_000, distanceMeters: 10_000, averageHeartRate: 150),
            makeWorkout(daysAgo: 2, durationSeconds: 2_400, distanceMeters: 7_000, averageHeartRate: 142)
        ])
        let provider = UnifiedWorkoutRecoveryPreviewProvider(
            store: store,
            calculator: RecoveryCalculator(referenceDate: baseDate),
            lookbackDays: 30
        )

        let result = try await provider.fetchPreviewSummary()

        XCTAssertEqual(result.usedWorkoutCount, 2)
        XCTAssertNotEqual(result.summary.status, "데이터 부족")
        XCTAssertEqual(result.summary.dataQuality, .estimated)
        XCTAssertEqual(store.requestedDays, 30)
    }

    func testExcludedWorkoutIsRemovedBeforeRecoveryCalculation() async throws {
        let store = FakeRecoveryPreviewWorkoutStore(workouts: [
            makeWorkout(daysAgo: 0, durationSeconds: 3_000, distanceMeters: 10_000, averageHeartRate: 150),
            makeWorkout(daysAgo: 1, durationSeconds: 7_200, distanceMeters: 40_000, averageHeartRate: 168, isExcluded: true)
        ])
        let provider = UnifiedWorkoutRecoveryPreviewProvider(
            store: store,
            calculator: RecoveryCalculator(referenceDate: baseDate)
        )

        let result = try await provider.fetchPreviewSummary()

        XCTAssertEqual(result.usedWorkoutCount, 1)
        XCTAssertFalse(result.summary.trends.first?.values.contains(180) ?? false)
    }

    func testEmptyStoreReturnsInsufficientDataSummary() async throws {
        let provider = UnifiedWorkoutRecoveryPreviewProvider(
            store: FakeRecoveryPreviewWorkoutStore(workouts: []),
            calculator: RecoveryCalculator(referenceDate: baseDate)
        )

        let result = try await provider.fetchPreviewSummary()

        XCTAssertEqual(result.usedWorkoutCount, 0)
        XCTAssertEqual(result.summary.score, 72)
        XCTAssertEqual(result.summary.status, "데이터 부족")
        XCTAssertFalse(result.summary.recommendation.isEmpty)
    }

    func testDuplicateLikeWorkoutsAreNotDeduplicatedAutomatically() async throws {
        let first = makeWorkout(daysAgo: 0, externalId: "garmin-ride", source: .garmin, durationSeconds: 3_600, distanceMeters: 28_000)
        let second = makeWorkout(daysAgo: 0, externalId: "healthkit-ride", source: .appleHealthKit, durationSeconds: 3_620, distanceMeters: 28_100)
        let provider = UnifiedWorkoutRecoveryPreviewProvider(
            store: FakeRecoveryPreviewWorkoutStore(workouts: [first, second]),
            calculator: RecoveryCalculator(referenceDate: baseDate)
        )

        let result = try await provider.fetchPreviewSummary()

        XCTAssertEqual(result.usedWorkoutCount, 2)
        XCTAssertNotEqual(result.summary.status, "데이터 부족")
    }

    func testRecoveryCalculatorFormulaOutputIsNotChangedByPreviewProvider() async throws {
        let workouts = [
            makeWorkout(daysAgo: 0, durationSeconds: 3_000, distanceMeters: 10_000, averageHeartRate: 150),
            makeWorkout(daysAgo: 2, durationSeconds: 2_400, distanceMeters: 7_000, averageHeartRate: 142)
        ]
        let selector = UnifiedWorkoutAnalysisInputSelector()
        let calculator = RecoveryCalculator(referenceDate: baseDate)
        let expected = calculator.calculateSummary(from: selector.selectRecoveryInputs(from: workouts))
        let provider = UnifiedWorkoutRecoveryPreviewProvider(
            store: FakeRecoveryPreviewWorkoutStore(workouts: workouts),
            selector: selector,
            calculator: calculator
        )

        let result = try await provider.fetchPreviewSummary()

        XCTAssertEqual(result.summary.score, expected.score)
        XCTAssertEqual(result.summary.status, expected.status)
        XCTAssertEqual(result.summary.recommendation, expected.recommendation)
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 21, hour: 7)) ?? Date()
    }

    private func makeWorkout(
        daysAgo: Int,
        externalId: String = UUID().uuidString,
        source: UnifiedDataSource = .appleHealthKit,
        type: UnifiedWorkoutType = .running,
        durationSeconds: TimeInterval,
        distanceMeters: Double?,
        averageHeartRate: Double = 148,
        isExcluded: Bool = false
    ) -> UnifiedWorkout {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
        return UnifiedWorkout(
            id: UUID(),
            externalId: externalId,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 420,
            averageHeartRate: averageHeartRate,
            maxHeartRate: averageHeartRate + 22,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 64,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcluded,
            createdAt: startDate,
            updatedAt: startDate
        )
    }
}

private final class FakeRecoveryPreviewWorkoutStore: UnifiedWorkoutStore {
    private let workouts: [UnifiedWorkout]
    private(set) var requestedDays: Int?

    init(workouts: [UnifiedWorkout]) {
        self.workouts = workouts
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {}
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {}

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        requestedDays = days
        return workouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func deleteWorkout(id: UUID) async throws {}
}
