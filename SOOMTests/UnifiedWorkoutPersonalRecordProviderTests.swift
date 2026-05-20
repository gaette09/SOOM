import XCTest
@testable import SOOM

final class UnifiedWorkoutPersonalRecordProviderTests: XCTestCase {
    func testBuildsPersonalRecordsFromUnifiedWorkoutStore() async throws {
        let store = FakePersonalRecordUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 2, distanceMeters: 6_000, durationSeconds: 1_900),
            makeWorkout(daysAgo: 0, distanceMeters: 14_000, durationSeconds: 4_200)
        ])
        let provider = UnifiedWorkoutPersonalRecordProvider(store: store, lookbackDays: 35)

        let records = try await provider.fetchPersonalRecords(referenceDate: baseDate)

        XCTAssertEqual(records.first?.metricType, .longestDistance)
        XCTAssertEqual(records.first?.value, "14.0 km")
        XCTAssertEqual(store.requestedDays, 35)
    }

    func testExcludedWorkoutIsRemovedBeforeRecordCalculation() async throws {
        let store = FakePersonalRecordUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 1, distanceMeters: 8_000, durationSeconds: 2_400),
            makeWorkout(daysAgo: 0, distanceMeters: 30_000, durationSeconds: 7_200, isExcluded: true)
        ])
        let provider = UnifiedWorkoutPersonalRecordProvider(store: store)

        let records = try await provider.fetchPersonalRecords(referenceDate: baseDate)

        XCTAssertEqual(records.first?.metricType, .longestDistance)
        XCTAssertEqual(records.first?.value, "8.0 km")
    }

    func testEmptyStoreReturnsNoRecords() async throws {
        let provider = UnifiedWorkoutPersonalRecordProvider(store: FakePersonalRecordUnifiedWorkoutStore(workouts: []))

        let records = try await provider.fetchPersonalRecords(referenceDate: baseDate)

        XCTAssertTrue(records.isEmpty)
    }

    func testProviderDoesNotUseRecoveryCalculator() async throws {
        let provider = UnifiedWorkoutPersonalRecordProvider(store: FakePersonalRecordUnifiedWorkoutStore(workouts: [
            makeWorkout(daysAgo: 7, distanceMeters: 5_000, durationSeconds: 1_800),
            makeWorkout(daysAgo: 0, distanceMeters: 7_000, durationSeconds: 2_400)
        ]))

        let records = try await provider.fetchPersonalRecords(referenceDate: baseDate)

        XCTAssertFalse(records.isEmpty)
        XCTAssertFalse(records.map(\.comparisonText).joined().contains("회복 점수"))
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

private final class FakePersonalRecordUnifiedWorkoutStore: UnifiedWorkoutStore {
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
