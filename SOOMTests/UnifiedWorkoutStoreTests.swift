import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class UnifiedWorkoutStoreTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    func testSaveWorkoutThenFetchRecentWorkouts() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let workout = makeWorkout(
            source: .garmin,
            type: .cycling,
            startDate: referenceDate.addingTimeInterval(-86_400)
        )

        try await fixture.store.saveWorkout(workout)
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, workout.id)
        XCTAssertEqual(fetched.first?.source, .garmin)
        XCTAssertEqual(fetched.first?.workoutType, .cycling)
    }

    func testExternalIdAndSourceUpsertsExistingWorkout() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let externalId = "garmin-ride-001"
        let first = makeWorkout(
            id: UUID(),
            externalId: externalId,
            source: .garmin,
            type: .cycling,
            startDate: referenceDate,
            distanceMeters: 40_000
        )
        let updated = makeWorkout(
            id: UUID(),
            externalId: externalId,
            source: .garmin,
            type: .cycling,
            startDate: referenceDate,
            distanceMeters: 42_000
        )

        try await fixture.store.saveWorkout(first)
        try await fixture.store.saveWorkout(updated)
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, updated.id)
        XCTAssertEqual(fetched.first?.distanceMeters, 42_000)
    }

    func testIdBasedUpsertWhenExternalIdIsMissing() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let id = UUID()
        let first = makeWorkout(
            id: id,
            externalId: nil,
            source: .soomLocal,
            type: .running,
            startDate: referenceDate,
            distanceMeters: 5_000
        )
        let updated = makeWorkout(
            id: id,
            externalId: nil,
            source: .soomLocal,
            type: .running,
            startDate: referenceDate,
            distanceMeters: 6_200
        )

        try await fixture.store.saveWorkout(first)
        try await fixture.store.saveWorkout(updated)
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, id)
        XCTAssertEqual(fetched.first?.distanceMeters, 6_200)
    }

    func testFetchByExternalIdAndSourceReturnsMatchingWorkout() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let workout = makeWorkout(
            externalId: "apple-run-001",
            source: .appleHealthKit,
            type: .running,
            startDate: referenceDate
        )

        try await fixture.store.saveWorkout(workout)
        let fetched = try await fixture.store.fetchByExternalId("apple-run-001", source: .appleHealthKit)

        XCTAssertEqual(fetched?.id, workout.id)
        XCTAssertEqual(fetched?.source, .appleHealthKit)
    }

    func testMarkExcludedFromAnalysisUpdatesStoredRecord() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let workout = makeWorkout(startDate: referenceDate)

        try await fixture.store.saveWorkout(workout)
        try await fixture.store.markExcludedFromAnalysis(id: workout.id, isExcluded: true)
        let record = try fetchRecord(id: workout.id, context: fixture.container.mainContext)

        XCTAssertEqual(record?.isExcludedFromAnalysis, true)
    }

    func testDeleteWorkoutRemovesStoredWorkout() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let deleted = makeWorkout(startDate: referenceDate)
        let remaining = makeWorkout(startDate: referenceDate.addingTimeInterval(-86_400))

        try await fixture.store.saveWorkouts([deleted, remaining])
        try await fixture.store.deleteWorkout(id: deleted.id)
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.map(\.id), [remaining.id])
    }

    func testFetchRecentWorkoutsFiltersByDays() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let recent = makeWorkout(startDate: referenceDate.addingTimeInterval(-2 * 86_400))
        let old = makeWorkout(startDate: referenceDate.addingTimeInterval(-10 * 86_400))

        try await fixture.store.saveWorkouts([recent, old])
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.map(\.id), [recent.id])
    }

    func testEnumRawValuesRoundTripThroughPersistence() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let workout = makeWorkout(
            source: .samsungHealth,
            type: .swimming,
            startDate: referenceDate,
            dataQuality: .estimated
        )

        try await fixture.store.saveWorkout(workout)
        let fetched = try await fixture.store.fetchWorkout(id: workout.id)

        XCTAssertEqual(fetched?.source, .samsungHealth)
        XCTAssertEqual(fetched?.workoutType, .swimming)
        XCTAssertEqual(fetched?.dataQuality, .estimated)
    }

    private func makeFixture(referenceDate: Date) throws -> (
        store: SwiftDataUnifiedWorkoutStore,
        container: ModelContainer
    ) {
        let schema = Schema([UnifiedWorkoutRecord.self])
        let configuration = ModelConfiguration(
            "UnifiedWorkoutStoreTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        retainedContainers.append(container)

        return (
            SwiftDataUnifiedWorkoutStore(
                modelContext: container.mainContext,
                referenceDate: { referenceDate }
            ),
            container
        )
    }

    private func fetchRecord(id: UUID, context: ModelContext) throws -> UnifiedWorkoutRecord? {
        let workoutID = id
        var descriptor = FetchDescriptor<UnifiedWorkoutRecord>(
            predicate: #Predicate { record in
                record.id == workoutID
            }
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    private func makeWorkout(
        id: UUID = UUID(),
        externalId: String? = UUID().uuidString,
        source: UnifiedDataSource = .appleHealthKit,
        type: UnifiedWorkoutType = .running,
        startDate: Date,
        durationSeconds: TimeInterval = 3_600,
        distanceMeters: Double? = 10_000,
        dataQuality: UnifiedDataQuality = .partial
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: id,
            externalId: externalId,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 520,
            averageHeartRate: 148,
            maxHeartRate: 174,
            averageSpeedMetersPerSecond: 2.8,
            elevationGainMeters: 72,
            dataQuality: dataQuality,
            createdAt: startDate,
            updatedAt: startDate.addingTimeInterval(durationSeconds)
        )
    }
}
