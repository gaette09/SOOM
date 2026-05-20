import XCTest
@testable import SOOM

final class UnifiedWorkoutGrowthTrendProviderTests: XCTestCase {
    func testBuildsFourWeekTrendFromUnifiedWorkoutStore() async throws {
        let store = FakeTrendUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 21, distanceMeters: 4_000, durationSeconds: 1_500),
            makeWorkout(daysAgo: 14, distanceMeters: 5_000, durationSeconds: 1_800),
            makeWorkout(daysAgo: 7, distanceMeters: 7_000, durationSeconds: 2_400),
            makeWorkout(daysAgo: 0, distanceMeters: 9_000, durationSeconds: 3_000)
        ])
        let provider = UnifiedWorkoutGrowthTrendProvider(store: store, lookbackDays: 35)

        let trend = try await provider.fetchFourWeekTrend(referenceDate: baseDate)

        XCTAssertEqual(trend.weeks.count, 4)
        XCTAssertEqual(trend.trendType, .improving)
        XCTAssertEqual(store.requestedDays, 35)
    }

    func testExcludedWorkoutIsRemovedBeforeTrendCalculation() async throws {
        let store = FakeTrendUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 7, distanceMeters: 6_000, durationSeconds: 2_000),
            makeWorkout(daysAgo: 0, distanceMeters: 20_000, durationSeconds: 6_000, isExcluded: true)
        ])
        let provider = UnifiedWorkoutGrowthTrendProvider(store: store)

        let trend = try await provider.fetchFourWeekTrend(referenceDate: baseDate)

        XCTAssertEqual(trend.weeks.reduce(0) { $0 + $1.workoutCount }, 1)
        XCTAssertEqual(trend.weeks.reduce(0) { $0 + $1.totalDistanceKm }, 6.0, accuracy: 0.01)
    }

    func testEmptyStoreReturnsInsufficientDataTrend() async throws {
        let provider = UnifiedWorkoutGrowthTrendProvider(store: FakeTrendUnifiedWorkoutStore(workouts: []))

        let trend = try await provider.fetchFourWeekTrend(referenceDate: baseDate)

        XCTAssertEqual(trend.trendType, .insufficientData)
    }

    func testProviderDoesNotUseRecoveryCalculator() async throws {
        let provider = UnifiedWorkoutGrowthTrendProvider(store: FakeTrendUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 7, distanceMeters: 5_000, durationSeconds: 1_800),
            makeWorkout(daysAgo: 0, distanceMeters: 7_000, durationSeconds: 2_400)
        ]))

        let trend = try await provider.fetchFourWeekTrend(referenceDate: baseDate)

        XCTAssertFalse(trend.summaryText.isEmpty)
        XCTAssertNotEqual(trend.trendType, .insufficientData)
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

private final class FakeTrendUnifiedWorkoutStore: UnifiedWorkoutStore {
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
