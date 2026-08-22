import HealthKit
import XCTest
@testable import SOOM

final class HealthKitWorkoutImportPipelineTests: XCTestCase {
    func testImportsFetchedHealthKitWorkoutsIntoUnifiedWorkoutStore() async {
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, type: .running),
                    makeWorkout(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, type: .cycling)
                ])
            ),
            store: store,
            mappedAt: { Date(timeIntervalSince1970: 1_800_200_000) }
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)

        XCTAssertEqual(result.fetchedCount, 2)
        XCTAssertEqual(result.savedCount, 2)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.importedWorkouts.map(\.source), [.appleHealthKit, .appleHealthKit])
        XCTAssertEqual(store.savedWorkouts.count, 2)
        XCTAssertEqual(store.savedWorkouts.map(\.workoutType), [.running, .cycling])
    }

    func testImportedHealthKitWorkoutCanBecomeProcessedWorkout() async {
        let workoutID = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(
                        id: workoutID,
                        type: .walking,
                        duration: 1_800,
                        distance: 2_500,
                        averageHeartRate: nil,
                        calories: nil
                    )
                ])
            ),
            store: store,
            mappedAt: { Date(timeIntervalSince1970: 1_800_200_000) }
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)

        XCTAssertEqual(result.savedCount, 1)
        let importedWorkout = result.importedWorkouts[0]
        let processed = ProcessedWorkoutBuilder().make(from: importedWorkout)
        XCTAssertEqual(processed.id, workoutID)
        XCTAssertEqual(processed.externalId, workoutID.uuidString)
        XCTAssertEqual(processed.source, .appleHealthKit)
        XCTAssertEqual(processed.workoutType, .walking)
        XCTAssertEqual(processed.distanceMeters, 2_500)
        XCTAssertEqual(processed.durationSeconds, 1_800)
        XCTAssertEqual(processed.metricAvailability[.distance], .measured)
        XCTAssertEqual(processed.metricAvailability[.duration], .measured)
        XCTAssertEqual(processed.metricAvailability[.calories], .missing)
        XCTAssertEqual(processed.metricAvailability[.averageHeartRate], .missing)
        XCTAssertEqual(processed.display.primaryMetricLabel, "속도")
    }

    func testPersistsWorkoutRoutesWhenRouteDependenciesAreInjected() async {
        let workoutID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let store = FakeUnifiedWorkoutStore()
        let routeStore = FakeWorkoutRoutePersistenceStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: workoutID, type: .cycling)
                ])
            ),
            store: store,
            routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: FakeHealthKitWorkoutRouteFetcher(route: makeRoute(workoutId: workoutID)),
            routeStore: routeStore
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(routeStore.savedRoutes.map(\.workoutId), [workoutID])
    }

    func testFetchedRouteIsAssociatedWithImportedWorkoutBeforeSaving() async {
        let workoutID = UUID(uuidString: "56565656-5656-5656-5656-565656565656")!
        let fetchedRoute = makeRoute(workoutId: UUID())
        let routeStore = FakeWorkoutRoutePersistenceStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: workoutID, type: .cycling, distance: 10_000)
                ])
            ),
            store: FakeUnifiedWorkoutStore(),
            routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: FakeHealthKitWorkoutRouteFetcher(route: fetchedRoute),
            routeStore: routeStore
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(routeStore.savedRoutes.first?.workoutId, workoutID)
        XCTAssertEqual(routeStore.savedRoutes.first?.source, .appleHealthKit)
        XCTAssertEqual(routeStore.savedRoutes.first?.coordinates, fetchedRoute.coordinates)
    }

    func testImportedRouteBackedWorkoutBuildsProcessedWorkoutWithRoute() async throws {
        let workoutID = UUID(uuidString: "57575757-5757-5757-5757-575757575757")!
        let route = makeRoute(workoutId: workoutID, distance: 12_000, elevationGain: 90)
        let routeStore = FakeWorkoutRoutePersistenceStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: workoutID, type: .cycling, distance: nil)
                ])
            ),
            store: FakeUnifiedWorkoutStore(),
            routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: FakeHealthKitWorkoutRouteFetcher(route: route),
            routeStore: routeStore
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)
        let fetchedRoute = try await routeStore.fetchRoute(workoutId: workoutID)
        let storedRoute = try XCTUnwrap(fetchedRoute)
        let processed = ProcessedWorkoutBuilder().make(from: result.importedWorkouts[0], route: storedRoute)

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(processed.source, .appleHealthKit)
        XCTAssertEqual(processed.route?.hasRenderableRoute, true)
        XCTAssertEqual(processed.route?.coordinateCount, 2)
        XCTAssertEqual(processed.distanceMeters, 12_000)
        XCTAssertEqual(processed.elevationGainMeters, 90)
        XCTAssertEqual(processed.metricAvailability[.distance], .derived)
        XCTAssertEqual(processed.metricAvailability[.elevation], .derived)
        XCTAssertEqual(processed.metricAvailability[.route], .measured)
    }

    func testWorkoutWithoutRouteStillImportsSummaryOnly() async {
        let workoutID = UUID(uuidString: "58585858-5858-5858-5858-585858585858")!
        let routeStore = FakeWorkoutRoutePersistenceStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: workoutID, type: .running, distance: 10_000)
                ])
            ),
            store: FakeUnifiedWorkoutStore(),
            routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: FakeHealthKitWorkoutRouteFetcher(route: nil),
            routeStore: routeStore
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)
        let processed = ProcessedWorkoutBuilder().make(from: result.importedWorkouts[0], route: nil)

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
        XCTAssertNil(processed.route)
        XCTAssertFalse(processed.hasRoute)
        XCTAssertEqual(result.importedWorkouts[0].routeMissingReason, .healthKitRouteUnavailable)
        XCTAssertEqual(processed.routeMissingReason, .healthKitRouteUnavailable)
        XCTAssertEqual(processed.distanceMeters, 10_000)
        XCTAssertEqual(processed.metricAvailability[.route], .missing)
    }

    func testRouteFetchFailureDoesNotFailWorkoutImport() async {
        let workoutID = UUID(uuidString: "59595959-5959-5959-5959-595959595959")!
        let routeStore = FakeWorkoutRoutePersistenceStore()
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: workoutID, type: .running, distance: 10_000)
                ])
            ),
            store: store,
            routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: FakeHealthKitWorkoutRouteFetcher(route: nil, error: SampleError.fetchFailed),
            routeStore: routeStore
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.importedWorkouts[0].routeMissingReason, .routeFetchFailed)
        XCTAssertEqual(store.savedWorkouts.first?.routeMissingReason, .routeFetchFailed)
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
    }

    func testRoutePersistenceFailureDoesNotFailWorkoutImport() async {
        let workoutID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let routeStore = FakeWorkoutRoutePersistenceStore(saveError: SampleError.saveFailed)
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: workoutID, type: .running)
                ])
            ),
            store: store,
            routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: FakeHealthKitWorkoutRouteFetcher(route: makeRoute(workoutId: workoutID)),
            routeStore: routeStore
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.importedWorkouts[0].routeMissingReason, .routePersistenceFailed)
        XCTAssertEqual(store.savedWorkouts.first?.routeMissingReason, .routePersistenceFailed)
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
    }

    func testHealthKitRouteLookupMissRecordsExternalSourceRouteNotShared() async {
        let workoutID = UUID(uuidString: "54545454-5454-5454-5454-545454545454")!
        let routeStore = FakeWorkoutRoutePersistenceStore()
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: workoutID, type: .cycling, distance: 12_000)
                ])
            ),
            store: store,
            routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: nil),
            routeFetcher: FakeHealthKitWorkoutRouteFetcher(route: makeRoute(workoutId: workoutID)),
            routeStore: routeStore
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)
        let processed = ProcessedWorkoutBuilder().make(from: result.importedWorkouts[0], route: nil)

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
        XCTAssertEqual(result.importedWorkouts[0].routeMissingReason, .externalSourceRouteNotShared)
        XCTAssertEqual(store.savedWorkouts.first?.routeMissingReason, .externalSourceRouteNotShared)
        XCTAssertEqual(processed.routeMissingReason, .externalSourceRouteNotShared)
        XCTAssertFalse(processed.hasRoute)
    }

    func testDuplicateSkippedHealthKitWorkoutDoesNotPersistRoute() async {
        let workoutID = UUID(uuidString: "60606060-6060-6060-6060-606060606060")!
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let localWorkout = makeUnifiedWorkout(
            source: .soomLocal,
            type: .cycling,
            startDate: startDate,
            duration: 3_600,
            distance: 10_000
        )
        let routeStore = FakeWorkoutRoutePersistenceStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(
                        id: workoutID,
                        type: .cycling,
                        startDate: startDate.addingTimeInterval(60),
                        duration: 3_570,
                        distance: 10_100
                    )
                ])
            ),
            store: FakeUnifiedWorkoutStore(existingWorkouts: [localWorkout]),
            routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: FakeHealthKitWorkoutRouteFetcher(route: makeRoute(workoutId: workoutID)),
            routeStore: routeStore
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)

        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
    }


    func testEmptyFetchReturnsEmptySuccessResult() async {
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(result: .success([])),
            store: store
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.fetchedCount, 0)
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(result.importedWorkouts.isEmpty)
        XCTAssertTrue(store.savedWorkouts.isEmpty)
    }

    func testFetchFailureReturnsSafeFailedResult() async {
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(result: .failure(SampleError.fetchFailed)),
            store: store
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(result.importedWorkouts.isEmpty)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertTrue(store.savedWorkouts.isEmpty)
    }

    func testReimportWithSameExternalIdAndSourceDoesNotIncreaseStoreCount() async {
        let workoutID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(id: workoutID, type: .running, distance: 5_000)
                ])
            ),
            store: store
        )

        _ = await pipeline.importRecentWorkouts()
        _ = await pipeline.importRecentWorkouts()

        XCTAssertEqual(store.savedWorkouts.count, 1)
        XCTAssertEqual(store.savedWorkouts.first?.externalId, workoutID.uuidString)
    }

    func testLocalSoomWorkoutVsSimilarHealthKitWorkoutPrefersLocalAndSkipsImport() async {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let localWorkout = makeUnifiedWorkout(
            source: .soomLocal,
            type: .running,
            startDate: startDate,
            duration: 3_600,
            distance: 10_000
        )
        let store = FakeUnifiedWorkoutStore(existingWorkouts: [localWorkout])
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(
                        type: .running,
                        startDate: startDate.addingTimeInterval(90),
                        duration: 3_540,
                        distance: 10_200
                    )
                ])
            ),
            store: store
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.fetchedCount, 1)
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(store.savedWorkouts.count, 1)
        XCTAssertEqual(store.savedWorkouts.first?.source, .soomLocal)
    }

    func testDifferentTimeHealthKitWorkoutStillImports() async {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let localWorkout = makeUnifiedWorkout(
            source: .soomLocal,
            type: .cycling,
            startDate: startDate,
            duration: 3_600,
            distance: 30_000
        )
        let store = FakeUnifiedWorkoutStore(existingWorkouts: [localWorkout])
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(
                        type: .cycling,
                        startDate: startDate.addingTimeInterval(3_600),
                        duration: 3_600,
                        distance: 30_100
                    )
                ])
            ),
            store: store
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(store.savedWorkouts.count, 2)
        XCTAssertTrue(store.savedWorkouts.contains { $0.source == .appleHealthKit })
    }

    func testSameDayDifferentSportHealthKitWorkoutStillImports() async {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let localWorkout = makeUnifiedWorkout(
            source: .soomLocal,
            type: .running,
            startDate: startDate,
            duration: 3_600,
            distance: 10_000
        )
        let store = FakeUnifiedWorkoutStore(existingWorkouts: [localWorkout])
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(
                        type: .cycling,
                        startDate: startDate.addingTimeInterval(60),
                        duration: 3_600,
                        distance: 10_000
                    )
                ])
            ),
            store: store
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(store.savedWorkouts.count, 2)
        XCTAssertEqual(store.savedWorkouts.last?.workoutType, .cycling)
    }

    func testMissingDistanceDoesNotCauseUnsafeLocalDuplicateSkip() async {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let localWorkout = makeUnifiedWorkout(
            source: .soomLocal,
            type: .walking,
            startDate: startDate,
            duration: 1_800,
            distance: nil
        )
        let store = FakeUnifiedWorkoutStore(existingWorkouts: [localWorkout])
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(
                        type: .walking,
                        startDate: startDate.addingTimeInterval(60),
                        duration: 1_780,
                        distance: nil
                    )
                ])
            ),
            store: store
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(store.savedWorkouts.count, 2)
        XCTAssertTrue(store.savedWorkouts.contains { $0.source == .appleHealthKit })
    }

    func testHealthKitOnlyWorkoutStillImportsAndCanBecomeProcessedWorkout() async {
        let workoutID = UUID(uuidString: "89898989-8989-8989-8989-898989898989")!
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(
                        id: workoutID,
                        type: .cycling,
                        duration: 3_600,
                        distance: 30_000,
                        calories: 640
                    )
                ])
            ),
            store: store
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        let processed = ProcessedWorkoutBuilder().make(from: result.importedWorkouts[0])
        XCTAssertEqual(processed.source, .appleHealthKit)
        XCTAssertEqual(processed.externalId, workoutID.uuidString)
        XCTAssertEqual(processed.workoutType, .cycling)
        XCTAssertEqual(processed.distanceMeters, 30_000)
        XCTAssertEqual(processed.metricAvailability[.distance], .measured)
        XCTAssertEqual(processed.metricAvailability[.calories], .measured)
    }

    func testStoreFailureReturnsFailedSaveResult() async {
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(
                result: .success([
                    makeWorkout(type: .swimming)
                ])
            ),
            store: FakeUnifiedWorkoutStore(saveError: SampleError.saveFailed)
        )

        let result = await pipeline.importRecentWorkouts()

        XCTAssertEqual(result.fetchedCount, 1)
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(result.importedWorkouts.isEmpty)
        XCTAssertFalse(result.message.isEmpty)
    }

    private func makeWorkout(
        id: UUID = UUID(),
        type: HealthKitWorkoutType,
        startDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        duration: TimeInterval = 3_600,
        distance: Double? = 10_000,
        averageHeartRate: Double? = 148,
        calories: Double? = 520
    ) -> HealthKitWorkout {
        HealthKitWorkout(
            id: id,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            duration: duration,
            distance: distance,
            averageHeartRate: averageHeartRate,
            calories: calories
        )
    }

    private func makeUnifiedWorkout(
        id: UUID = UUID(),
        source: UnifiedDataSource,
        type: UnifiedWorkoutType,
        startDate: Date,
        duration: TimeInterval,
        distance: Double?,
        externalId: String? = nil
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: id,
            externalId: externalId,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            durationSeconds: duration,
            distanceMeters: distance,
            activeEnergyKcal: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: distance.map { $0 / duration },
            elevationGainMeters: nil,
            dataQuality: .partial,
            createdAt: startDate,
            updatedAt: startDate
        )
    }
}

private final class FakeHealthKitWorkoutFetcher: HealthKitWorkoutFetching {
    private let result: Result<[HealthKitWorkout], Error>

    init(result: Result<[HealthKitWorkout], Error>) {
        self.result = result
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] {
        try result.get()
    }
}

private final class FakeHealthKitWorkoutLookupProvider: HealthKitWorkoutLookingUp {
    private let workout: HKWorkout?

    init(workout: HKWorkout?) {
        self.workout = workout
    }

    func lookupWorkout(externalId: String) async -> HKWorkout? {
        workout
    }
}

private final class FakeHealthKitWorkoutRouteFetcher: HealthKitWorkoutRouteFetching {
    private let route: WorkoutRoute?
    private let error: Error?

    init(route: WorkoutRoute?, error: Error? = nil) {
        self.route = route
        self.error = error
    }

    func fetchRoute(for workout: HKWorkout) async throws -> WorkoutRoute? {
        if let error {
            throw error
        }

        return route
    }
}

private final class FakeWorkoutRoutePersistenceStore: WorkoutRoutePersistenceStoring {
    private(set) var savedRoutes: [WorkoutRoute] = []
    private let saveError: Error?

    init(saveError: Error? = nil) {
        self.saveError = saveError
    }

    func saveRoute(_ route: WorkoutRoute) async throws {
        if let saveError {
            throw saveError
        }

        savedRoutes.append(route)
    }

    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute? {
        savedRoutes.first { $0.workoutId == workoutId }
    }

    func fetchRoutes(workoutIds: [UUID]) async throws -> [WorkoutRoute] {
        savedRoutes.filter { workoutIds.contains($0.workoutId) }
    }

    func deleteRoute(workoutId: UUID) async throws {
        savedRoutes.removeAll { $0.workoutId == workoutId }
    }

    func deleteAllRoutes() async throws {
        savedRoutes.removeAll()
    }
}

private func makeHKWorkout() -> HKWorkout {
    HKWorkout(
        activityType: .cycling,
        start: Date(timeIntervalSince1970: 1_800_000_000),
        end: Date(timeIntervalSince1970: 1_800_003_600),
        duration: 3_600,
        totalEnergyBurned: nil,
        totalDistance: HKQuantity(unit: .meter(), doubleValue: 10_000),
        metadata: nil
    )
}

private func makeRoute(
    workoutId: UUID,
    distance: Double = 10_000,
    elevationGain: Double? = 80
) -> WorkoutRoute {
    WorkoutRoute(
        workoutId: workoutId,
        source: .appleHealthKit,
        coordinates: [
            WorkoutRouteCoordinate(latitude: 37.500, longitude: 127.000),
            WorkoutRouteCoordinate(latitude: 37.505, longitude: 127.005)
        ],
        totalDistanceMeters: distance,
        totalElevationGain: elevationGain,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

private final class FakeUnifiedWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout] = []
    private let saveError: Error?

    init(existingWorkouts: [UnifiedWorkout] = [], saveError: Error? = nil) {
        self.savedWorkouts = existingWorkouts
        self.saveError = saveError
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        try await saveWorkouts([workout])
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        if let saveError {
            throw saveError
        }

        for workout in workouts {
            upsert(workout)
        }
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        savedWorkouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.id == id }
    }

    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.externalId == externalId && $0.source == source }
    }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}

    func deleteWorkout(id: UUID) async throws {
        savedWorkouts.removeAll { $0.id == id }
    }

    func deleteAllWorkouts() async throws {
        savedWorkouts.removeAll()
    }

    private func upsert(_ workout: UnifiedWorkout) {
        if let externalId = workout.externalId,
           let index = savedWorkouts.firstIndex(where: { $0.externalId == externalId && $0.source == workout.source }) {
            savedWorkouts[index] = workout
        } else if let index = savedWorkouts.firstIndex(where: { $0.id == workout.id }) {
            savedWorkouts[index] = workout
        } else {
            savedWorkouts.append(workout)
        }
    }
}

private enum SampleError: Error {
    case fetchFailed
    case saveFailed
}
