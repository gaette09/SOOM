import HealthKit
import XCTest
@testable import SOOM

final class WorkoutDetailZoneContextProviderTests: XCTestCase {
    func testAppleHealthKitWorkoutWithExternalIdAttemptsLookupAndCreatesProvider() async {
        let healthKitWorkout = makeHealthKitWorkout()
        let lookupProvider = FakeHealthKitWorkoutLookupProvider(workout: healthKitWorkout)
        let provider = WorkoutDetailZoneContextProvider(
            workoutLookupProvider: lookupProvider,
            makeZoneDataProvider: { FakeWorkoutZoneDataProvider() }
        )

        let context = await provider.context(for: makeUnifiedWorkout(source: .appleHealthKit, externalId: healthKitWorkout.uuid.uuidString))

        XCTAssertEqual(lookupProvider.requestedExternalIDs, [healthKitWorkout.uuid.uuidString])
        XCTAssertEqual(context.healthKitWorkout?.uuid, healthKitWorkout.uuid)
        XCTAssertNotNil(context.zoneDataProvider)
    }

    func testNonHealthKitWorkoutDoesNotAttemptLookup() async {
        let lookupProvider = FakeHealthKitWorkoutLookupProvider(workout: makeHealthKitWorkout())
        let provider = WorkoutDetailZoneContextProvider(workoutLookupProvider: lookupProvider)

        let context = await provider.context(for: makeUnifiedWorkout(source: .garmin, externalId: UUID().uuidString))

        XCTAssertTrue(lookupProvider.requestedExternalIDs.isEmpty)
        XCTAssertNil(context.healthKitWorkout)
        XCTAssertNil(context.zoneDataProvider)
    }

    func testMissingExternalIdKeepsFallbackContext() async {
        let lookupProvider = FakeHealthKitWorkoutLookupProvider(workout: makeHealthKitWorkout())
        let provider = WorkoutDetailZoneContextProvider(workoutLookupProvider: lookupProvider)

        let context = await provider.context(for: makeUnifiedWorkout(source: .appleHealthKit, externalId: nil))

        XCTAssertTrue(lookupProvider.requestedExternalIDs.isEmpty)
        XCTAssertNil(context.healthKitWorkout)
        XCTAssertNil(context.zoneDataProvider)
    }

    func testLookupFailureKeepsFallbackContext() async {
        let lookupProvider = FakeHealthKitWorkoutLookupProvider(workout: nil)
        let provider = WorkoutDetailZoneContextProvider(workoutLookupProvider: lookupProvider)

        let context = await provider.context(for: makeUnifiedWorkout(source: .appleHealthKit, externalId: UUID().uuidString))

        XCTAssertEqual(lookupProvider.requestedExternalIDs.count, 1)
        XCTAssertNil(context.healthKitWorkout)
        XCTAssertNil(context.zoneDataProvider)
    }

    func testContextProviderDoesNotInvokeRecoveryCalculator() async {
        let healthKitWorkout = makeHealthKitWorkout()
        let provider = WorkoutDetailZoneContextProvider(
            workoutLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: healthKitWorkout),
            makeZoneDataProvider: { FakeWorkoutZoneDataProvider() }
        )

        let context = await provider.context(for: makeUnifiedWorkout(source: .appleHealthKit, externalId: healthKitWorkout.uuid.uuidString))

        XCTAssertNotNil(context.zoneDataProvider)
    }

    private func makeUnifiedWorkout(
        source: UnifiedDataSource,
        externalId: String?
    ) -> UnifiedWorkout {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        return UnifiedWorkout(
            id: UUID(),
            externalId: externalId,
            source: source,
            workoutType: .cycling,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: 25_000,
            activeEnergyKcal: 520,
            averageHeartRate: 145,
            maxHeartRate: 171,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 240,
            dataQuality: .partial,
            createdAt: startDate,
            updatedAt: startDate
        )
    }

    private func makeHealthKitWorkout() -> HKWorkout {
        HKWorkout(
            activityType: .cycling,
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_003_600),
            duration: 3_600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        )
    }
}

private final class FakeHealthKitWorkoutLookupProvider: HealthKitWorkoutLookingUp {
    private let workout: HKWorkout?
    private(set) var requestedExternalIDs: [String] = []

    init(workout: HKWorkout?) {
        self.workout = workout
    }

    func lookupWorkout(externalId: String) async -> HKWorkout? {
        requestedExternalIDs.append(externalId)
        return workout
    }
}

private struct FakeWorkoutZoneDataProvider: WorkoutZoneDataProviding {
    func summaries(for workout: HKWorkout, sport: WorkoutSport) async throws -> [WorkoutZoneSummary] {
        []
    }
}
