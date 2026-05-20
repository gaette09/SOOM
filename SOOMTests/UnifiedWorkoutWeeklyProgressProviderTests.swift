import XCTest
@testable import SOOM

final class UnifiedWorkoutWeeklyProgressProviderTests: XCTestCase {
    func testBuildsWeeklyProgressFromUnifiedWorkoutStore() async throws {
        let store = FakeUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 0, distanceMeters: 10_000, durationSeconds: 3_000),
            makeWorkout(daysAgo: 2, distanceMeters: 5_000, durationSeconds: 1_500),
            makeWorkout(daysAgo: 8, distanceMeters: 7_000, durationSeconds: 2_100)
        ])
        let provider = UnifiedWorkoutWeeklyProgressProvider(store: store, lookbackDays: 30)

        let progress = try await provider.fetchWeeklyProgress(referenceDate: baseDate)

        XCTAssertEqual(progress.workoutCount, 2)
        XCTAssertEqual(progress.totalDistanceKm, 15.0, accuracy: 0.01)
        XCTAssertEqual(progress.totalDurationMinutes, 75)
        XCTAssertEqual(store.requestedDays, 30)
    }

    func testExcludedWorkoutIsRemovedBeforeWeeklyProgressCalculation() async throws {
        let store = FakeUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 0, distanceMeters: 10_000, durationSeconds: 3_000),
            makeWorkout(daysAgo: 1, distanceMeters: 20_000, durationSeconds: 6_000, isExcluded: true)
        ])
        let provider = UnifiedWorkoutWeeklyProgressProvider(store: store)

        let progress = try await provider.fetchWeeklyProgress(referenceDate: baseDate)

        XCTAssertEqual(progress.workoutCount, 1)
        XCTAssertEqual(progress.totalDistanceKm, 10.0, accuracy: 0.01)
    }

    func testLookbackRangeCanUseFourteenDays() async throws {
        let store = FakeUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 0, distanceMeters: 8_000, durationSeconds: 2_400)
        ])
        let provider = UnifiedWorkoutWeeklyProgressProvider(store: store, lookbackDays: 14)

        _ = try await provider.fetchWeeklyProgress(referenceDate: baseDate)

        XCTAssertEqual(store.requestedDays, 14)
    }

    func testEmptyStoreReturnsInsufficientDataProgress() async throws {
        let provider = UnifiedWorkoutWeeklyProgressProvider(store: FakeUnifiedWorkoutStore(workouts: []))

        let progress = try await provider.fetchWeeklyProgress(referenceDate: baseDate)

        XCTAssertEqual(progress.trendType, .insufficientData)
        XCTAssertEqual(progress.workoutCount, 0)
    }

    func testProviderDoesNotUseRecoveryCalculator() async throws {
        let provider = UnifiedWorkoutWeeklyProgressProvider(store: FakeUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 0, distanceMeters: 12_000, durationSeconds: 3_600)
        ]))

        let progress = try await provider.fetchWeeklyProgress(referenceDate: baseDate)

        XCTAssertFalse(progress.progressSummary.isEmpty)
        XCTAssertEqual(progress.trendType, .insufficientData)
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 7)) ?? Date()
    }

    private func makeWorkout(
        daysAgo: Int,
        type: UnifiedWorkoutType = .running,
        distanceMeters: Double?,
        durationSeconds: TimeInterval,
        isExcluded: Bool = false
    ) -> UnifiedWorkout {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
        return UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: .appleHealthKit,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 420,
            averageHeartRate: 148,
            maxHeartRate: 172,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 64,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcluded,
            createdAt: startDate,
            updatedAt: startDate
        )
    }
}

private final class FakeUnifiedWorkoutStore: UnifiedWorkoutStore {
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
