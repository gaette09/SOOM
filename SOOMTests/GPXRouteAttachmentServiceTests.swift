import XCTest
@testable import SOOM

final class GPXRouteAttachmentServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_010_000)

    func testAttachesValidGPXToHealthKitImportedNoRouteWorkout() async throws {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let workoutStore = FakeGPXWorkoutStore(workouts: [workout])
        let routeStore = FakeGPXRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, gpxData: validGPXData())

        let attachment = try unwrapSuccess(result)
        XCTAssertEqual(attachment.workout.id, workout.id)
        XCTAssertEqual(attachment.workout.routeMissingReason, .none)
        XCTAssertEqual(attachment.route.workoutId, workout.id)
        XCTAssertEqual(attachment.route.source, .appleHealthKit)
        XCTAssertEqual(attachment.route.coordinates.count, 3)
        XCTAssertGreaterThan(attachment.route.totalDistanceMeters, 0)
        XCTAssertEqual(routeStore.savedRoutes.map(\.workoutId), [workout.id])
        XCTAssertEqual(workoutStore.savedWorkouts.last?.routeMissingReason, WorkoutRouteMissingReason.none)
    }

    func testRouteIsPersistedWithExistingWorkoutId() async throws {
        let workoutID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let workout = makeWorkout(id: workoutID, routeMissingReason: .externalSourceRouteNotShared)
        let routeStore = FakeGPXRouteStore()
        let service = makeService(
            workoutStore: FakeGPXWorkoutStore(workouts: [workout]),
            routeStore: routeStore
        )

        let result = await service.attachRoute(to: workoutID, gpxData: validGPXData())

        _ = try unwrapSuccess(result)
        XCTAssertEqual(routeStore.savedRoutes.first?.workoutId, workoutID)
    }

    func testInvalidGPXDoesNotModifyWorkoutOrPersistRoute() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let workoutStore = FakeGPXWorkoutStore(workouts: [workout])
        let routeStore = FakeGPXRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, gpxData: Data())

        XCTAssertEqual(result.failureValue, .invalidGPX(.emptyData))
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
        XCTAssertEqual(workoutStore.savedWorkouts, [workout])
    }

    func testAlreadyRouteBackedWorkoutIsNotReplacedByDefault() async {
        let workout = makeWorkout(routeMissingReason: .none)
        let existingRoute = makeRoute(workoutId: workout.id, latitudeOffset: 0)
        let routeStore = FakeGPXRouteStore(routes: [existingRoute])
        let service = makeService(
            workoutStore: FakeGPXWorkoutStore(workouts: [workout]),
            routeStore: routeStore
        )

        let result = await service.attachRoute(to: workout.id, gpxData: validGPXData())

        XCTAssertEqual(result.failureValue, .alreadyHasRoute)
        XCTAssertEqual(routeStore.savedRoutes, [existingRoute])
    }

    func testExplicitReplacementCanReplaceExistingRoute() async throws {
        let workout = makeWorkout(routeMissingReason: .none)
        let existingRoute = makeRoute(workoutId: workout.id, latitudeOffset: 0)
        let routeStore = FakeGPXRouteStore(routes: [existingRoute])
        let service = makeService(
            workoutStore: FakeGPXWorkoutStore(workouts: [workout]),
            routeStore: routeStore
        )

        let result = await service.attachRoute(
            to: workout.id,
            gpxData: validGPXData(),
            replacingExistingRoute: true
        )

        let attachment = try unwrapSuccess(result)
        XCTAssertEqual(routeStore.savedRoutes.count, 1)
        XCTAssertEqual(routeStore.savedRoutes[0], attachment.route)
        XCTAssertNotEqual(routeStore.savedRoutes[0].coordinates, existingRoute.coordinates)
    }

    func testPersistenceFailurePreservesWorkoutSummaryAndReportsError() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let workoutStore = FakeGPXWorkoutStore(workouts: [workout])
        let routeStore = FakeGPXRouteStore(saveError: SampleAttachmentError.storeFailed)
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, gpxData: validGPXData())

        XCTAssertEqual(result.failureValue, .persistenceFailed)
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
        XCTAssertEqual(workoutStore.savedWorkouts.count, 1)
        XCTAssertEqual(workoutStore.savedWorkouts[0].id, workout.id)
        XCTAssertEqual(workoutStore.savedWorkouts[0].routeMissingReason, .routePersistenceFailed)
    }

    func testProcessedWorkoutBuilderCanConsumeAttachedRoute() async throws {
        let workout = makeWorkout(distanceMeters: nil, routeMissingReason: .healthKitRouteUnavailable)
        let routeStore = FakeGPXRouteStore()
        let service = makeService(
            workoutStore: FakeGPXWorkoutStore(workouts: [workout]),
            routeStore: routeStore
        )

        let result = await service.attachRoute(to: workout.id, gpxData: validGPXData())
        let attachment = try unwrapSuccess(result)
        let processed = ProcessedWorkoutBuilder().make(from: attachment.workout, route: attachment.route)

        XCTAssertTrue(processed.hasRoute)
        XCTAssertEqual(processed.routeMissingReason, .none)
        XCTAssertEqual(processed.metricAvailability[.route], .measured)
        XCTAssertEqual(processed.metricAvailability[.distance], .derived)
        XCTAssertGreaterThan(processed.distanceMeters ?? 0, 0)
    }

    func testLocalRecordWorkoutIsNotChanged() async {
        let workout = makeWorkout(source: .soomLocal, routeMissingReason: .none)
        let workoutStore = FakeGPXWorkoutStore(workouts: [workout])
        let routeStore = FakeGPXRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, gpxData: validGPXData())

        XCTAssertEqual(result.failureValue, .unsupportedSource(.soomLocal))
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
        XCTAssertEqual(workoutStore.savedWorkouts, [workout])
    }

    func testMissingWorkoutReturnsWorkoutNotFound() async {
        let workoutID = UUID()
        let service = makeService(
            workoutStore: FakeGPXWorkoutStore(workouts: []),
            routeStore: FakeGPXRouteStore()
        )

        let result = await service.attachRoute(to: workoutID, gpxData: validGPXData())

        XCTAssertEqual(result.failureValue, .workoutNotFound(workoutID))
    }

    private func makeService(
        workoutStore: FakeGPXWorkoutStore,
        routeStore: FakeGPXRouteStore
    ) -> GPXRouteAttachmentService {
        GPXRouteAttachmentService(
            workoutStore: workoutStore,
            routeStore: routeStore,
            dateProvider: { self.now }
        )
    }

    private func makeWorkout(
        id: UUID = UUID(),
        source: UnifiedDataSource = .appleHealthKit,
        distanceMeters: Double? = 10_000,
        routeMissingReason: WorkoutRouteMissingReason
    ) -> UnifiedWorkout {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return UnifiedWorkout(
            id: id,
            externalId: id.uuidString,
            source: source,
            workoutType: .cycling,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 520,
            averageHeartRate: nil,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil,
            routeMissingReason: routeMissingReason,
            dataQuality: .partial,
            createdAt: start,
            updatedAt: start
        )
    }

    private func validGPXData() -> Data {
        Data(
            """
            <gpx version="1.1">
              <trk><trkseg>
                <trkpt lat="37.5000" lon="127.0000"><ele>10</ele></trkpt>
                <trkpt lat="37.5010" lon="127.0010"><ele>20</ele></trkpt>
                <trkpt lat="37.5020" lon="127.0020"><ele>18</ele></trkpt>
              </trkseg></trk>
            </gpx>
            """.utf8
        )
    }

    private func makeRoute(workoutId: UUID, latitudeOffset: Double) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.0 + latitudeOffset, longitude: 127.0),
                WorkoutRouteCoordinate(latitude: 37.1 + latitudeOffset, longitude: 127.1)
            ],
            totalDistanceMeters: 1_000,
            createdAt: now
        )
    }

    private func unwrapSuccess(
        _ result: Result<GPXRouteAttachmentResult, GPXRouteAttachmentError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> GPXRouteAttachmentResult {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            XCTFail("Expected success, got \(error)", file: file, line: line)
            throw error
        }
    }
}

private final class FakeGPXWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout]

    init(workouts: [UnifiedWorkout]) {
        self.savedWorkouts = workouts
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        try await saveWorkouts([workout])
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        for workout in workouts {
            if let index = savedWorkouts.firstIndex(where: { $0.id == workout.id }) {
                savedWorkouts[index] = workout
            } else {
                savedWorkouts.append(workout)
            }
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
}

private final class FakeGPXRouteStore: WorkoutRoutePersistenceStoring {
    private(set) var savedRoutes: [WorkoutRoute]
    private let saveError: Error?

    init(routes: [WorkoutRoute] = [], saveError: Error? = nil) {
        self.savedRoutes = routes
        self.saveError = saveError
    }

    func saveRoute(_ route: WorkoutRoute) async throws {
        if let saveError {
            throw saveError
        }

        if let index = savedRoutes.firstIndex(where: { $0.workoutId == route.workoutId }) {
            savedRoutes[index] = route
        } else {
            savedRoutes.append(route)
        }
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

private enum SampleAttachmentError: Error {
    case storeFailed
}

private extension Result where Success == GPXRouteAttachmentResult, Failure == GPXRouteAttachmentError {
    var failureValue: GPXRouteAttachmentError? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
