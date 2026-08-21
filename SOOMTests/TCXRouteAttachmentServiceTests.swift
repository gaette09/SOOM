import XCTest
@testable import SOOM

final class TCXRouteAttachmentServiceTests: XCTestCase {
    private let startDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let now = Date(timeIntervalSince1970: 1_800_010_000)

    func testMatchingTCXAttachesToHealthKitWorkoutAndClearsMissingReason() async throws {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let workoutStore = FakeTCXWorkoutStore(workouts: [workout])
        let routeStore = FakeTCXRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, tcxData: makeTCXData())

        let attachment = try unwrapSuccess(result)
        XCTAssertEqual(attachment.workout.id, workout.id)
        XCTAssertEqual(attachment.workout.routeMissingReason, .none)
        XCTAssertEqual(attachment.route.workoutId, workout.id)
        XCTAssertEqual(attachment.route.source, .appleHealthKit)
        XCTAssertEqual(attachment.route.coordinates.count, 3)
        XCTAssertEqual(attachment.route.totalDistanceMeters, 10_000, accuracy: 0.1)
        XCTAssertEqual(attachment.route.totalElevationGain, 12)
        XCTAssertEqual(attachment.summary.workoutType, .cycling)
        XCTAssertEqual(routeStore.savedRoutes.map(\.workoutId), [workout.id])
        XCTAssertEqual(
            workoutStore.savedWorkouts.last?.routeMissingReason,
            WorkoutRouteMissingReason.none
        )
    }

    func testSportMismatchBlocksAttachment() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let (result, workoutStore, routeStore) = await attach(
            workout: workout,
            tcxData: makeTCXData(sport: "Running")
        )

        XCTAssertEqual(result.failureValue, .incompatibleWorkout(.sport))
        assertNoChanges(workout: workout, workoutStore: workoutStore, routeStore: routeStore)
    }

    func testStartTimeBeyondFiveMinutesBlocksAttachment() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let (result, workoutStore, routeStore) = await attach(
            workout: workout,
            tcxData: makeTCXData(startDate: startDate.addingTimeInterval(301))
        )

        XCTAssertEqual(result.failureValue, .incompatibleWorkout(.startTime))
        assertNoChanges(workout: workout, workoutStore: workoutStore, routeStore: routeStore)
    }

    func testDurationDifferenceBeyondTenPercentBlocksAttachment() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let (result, workoutStore, routeStore) = await attach(
            workout: workout,
            tcxData: makeTCXData(durationSeconds: 3_239)
        )

        XCTAssertEqual(result.failureValue, .incompatibleWorkout(.duration))
        assertNoChanges(workout: workout, workoutStore: workoutStore, routeStore: routeStore)
    }

    func testDistanceDifferenceBeyondFifteenPercentBlocksAttachment() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let (result, workoutStore, routeStore) = await attach(
            workout: workout,
            tcxData: makeTCXData(distanceMeters: 8_499)
        )

        XCTAssertEqual(result.failureValue, .incompatibleWorkout(.distance))
        assertNoChanges(workout: workout, workoutStore: workoutStore, routeStore: routeStore)
    }

    func testCompatibilityThresholdBoundariesAreAccepted() async throws {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let service = makeService(
            workoutStore: FakeTCXWorkoutStore(workouts: [workout]),
            routeStore: FakeTCXRouteStore()
        )

        let result = await service.attachRoute(
            to: workout.id,
            tcxData: makeTCXData(
                startDate: startDate.addingTimeInterval(300),
                durationSeconds: 3_240,
                distanceMeters: 8_500
            )
        )

        _ = try unwrapSuccess(result)
    }

    func testMissingOptionalSummaryAndOtherSportPermitExplicitAttachment() async throws {
        let workout = makeWorkout(routeMissingReason: .externalSourceRouteNotShared)
        let service = makeService(
            workoutStore: FakeTCXWorkoutStore(workouts: [workout]),
            routeStore: FakeTCXRouteStore()
        )

        let result = await service.attachRoute(
            to: workout.id,
            tcxData: makeTCXData(
                sport: "Other",
                includesActivityID: false,
                includesLapSummary: false
            )
        )

        let attachment = try unwrapSuccess(result)
        XCTAssertEqual(attachment.summary.workoutType, .other)
        XCTAssertNil(attachment.summary.startDate)
        XCTAssertNil(attachment.summary.durationSeconds)
        XCTAssertNil(attachment.summary.distanceMeters)
    }

    func testExistingRouteIsNotSilentlyReplaced() async {
        let workout = makeWorkout(routeMissingReason: .none)
        let existingRoute = makeRoute(workoutId: workout.id)
        let routeStore = FakeTCXRouteStore(routes: [existingRoute])
        let service = makeService(
            workoutStore: FakeTCXWorkoutStore(workouts: [workout]),
            routeStore: routeStore
        )

        let result = await service.attachRoute(to: workout.id, tcxData: makeTCXData())

        XCTAssertEqual(result.failureValue, .alreadyHasRoute)
        XCTAssertEqual(routeStore.savedRoutes, [existingRoute])
    }

    func testLocalWorkoutIsRejectedWithoutParsingOrPersistence() async {
        let workout = makeWorkout(
            source: .soomLocal,
            routeMissingReason: .healthKitRouteUnavailable
        )
        let workoutStore = FakeTCXWorkoutStore(workouts: [workout])
        let routeStore = FakeTCXRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, tcxData: Data())

        XCTAssertEqual(result.failureValue, .unsupportedSource(.soomLocal))
        assertNoChanges(workout: workout, workoutStore: workoutStore, routeStore: routeStore)
    }

    func testInvalidTCXDoesNotModifyWorkoutOrPersistRoute() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let (result, workoutStore, routeStore) = await attach(
            workout: workout,
            tcxData: Data()
        )

        XCTAssertEqual(result.failureValue, .invalidTCX(.emptyData))
        assertNoChanges(workout: workout, workoutStore: workoutStore, routeStore: routeStore)
    }

    func testPersistenceFailurePreservesWorkoutSummary() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let workoutStore = FakeTCXWorkoutStore(workouts: [workout])
        let routeStore = FakeTCXRouteStore(saveError: TCXAttachmentSampleError.storeFailed)
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, tcxData: makeTCXData())

        XCTAssertEqual(result.failureValue, .persistenceFailed)
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
        XCTAssertEqual(workoutStore.savedWorkouts, [workout])
    }

    func testWorkoutSaveFailureDoesNotClearOriginalMissingReason() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let workoutStore = FakeTCXWorkoutStore(
            workouts: [workout],
            saveError: TCXAttachmentSampleError.storeFailed
        )
        let routeStore = FakeTCXRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, tcxData: makeTCXData())

        XCTAssertEqual(result.failureValue, .persistenceFailed)
        XCTAssertEqual(routeStore.savedRoutes.map(\.workoutId), [workout.id])
        XCTAssertEqual(workoutStore.savedWorkouts, [workout])
        XCTAssertEqual(
            workoutStore.savedWorkouts[0].routeMissingReason,
            .healthKitRouteUnavailable
        )
    }

    func testProcessedWorkoutBuilderConsumesAttachedRoute() async throws {
        let workout = makeWorkout(
            distanceMeters: nil,
            routeMissingReason: .healthKitRouteUnavailable
        )
        let service = makeService(
            workoutStore: FakeTCXWorkoutStore(workouts: [workout]),
            routeStore: FakeTCXRouteStore()
        )

        let result = await service.attachRoute(
            to: workout.id,
            tcxData: makeTCXData(distanceMeters: nil)
        )
        let attachment = try unwrapSuccess(result)
        let processed = ProcessedWorkoutBuilder().make(
            from: attachment.workout,
            route: attachment.route
        )

        XCTAssertTrue(processed.hasRoute)
        XCTAssertEqual(processed.routeMissingReason, .none)
        XCTAssertEqual(processed.metricAvailability[.route], .measured)
        XCTAssertEqual(processed.metricAvailability[.distance], .derived)
        XCTAssertGreaterThan(processed.distanceMeters ?? 0, 0)
    }

    func testMissingWorkoutReturnsWorkoutNotFound() async {
        let workoutID = UUID()
        let service = makeService(
            workoutStore: FakeTCXWorkoutStore(workouts: []),
            routeStore: FakeTCXRouteStore()
        )

        let result = await service.attachRoute(to: workoutID, tcxData: makeTCXData())

        XCTAssertEqual(result.failureValue, .workoutNotFound(workoutID))
    }

    private func attach(
        workout: UnifiedWorkout,
        tcxData: Data
    ) async -> (
        Result<TCXRouteAttachmentResult, TCXRouteAttachmentError>,
        FakeTCXWorkoutStore,
        FakeTCXRouteStore
    ) {
        let workoutStore = FakeTCXWorkoutStore(workouts: [workout])
        let routeStore = FakeTCXRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)
        let result = await service.attachRoute(to: workout.id, tcxData: tcxData)
        return (result, workoutStore, routeStore)
    }

    private func makeService(
        workoutStore: FakeTCXWorkoutStore,
        routeStore: FakeTCXRouteStore
    ) -> TCXRouteAttachmentService {
        TCXRouteAttachmentService(
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
        UnifiedWorkout(
            id: id,
            externalId: id.uuidString,
            source: source,
            workoutType: .cycling,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 520,
            averageHeartRate: 145,
            maxHeartRate: 172,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 120,
            routeMissingReason: routeMissingReason,
            dataQuality: .partial,
            createdAt: startDate,
            updatedAt: startDate
        )
    }

    private func makeTCXData(
        sport: String = "Biking",
        startDate: Date? = nil,
        durationSeconds: Double? = 3_600,
        distanceMeters: Double? = 10_000,
        includesActivityID: Bool = true,
        includesLapSummary: Bool = true
    ) -> Data {
        let resolvedStartDate = startDate ?? self.startDate
        let start = ISO8601DateFormatter().string(from: resolvedStartDate)
        let activityID = includesActivityID ? "<Id>\(start)</Id>" : ""
        let duration = includesLapSummary
            ? durationSeconds.map { "<TotalTimeSeconds>\($0)</TotalTimeSeconds>" } ?? ""
            : ""
        let distance = includesLapSummary
            ? distanceMeters.map { "<DistanceMeters>\($0)</DistanceMeters>" } ?? ""
            : ""

        return Data(
            """
            <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
              <Activities>
                <Activity Sport="\(sport)">
                  \(activityID)
                  <Lap>
                    \(duration)
                    \(distance)
                    <Track>
                      <Trackpoint>
                        <Position><LatitudeDegrees>37.5000</LatitudeDegrees><LongitudeDegrees>127.0000</LongitudeDegrees></Position>
                        <AltitudeMeters>10</AltitudeMeters>
                      </Trackpoint>
                      <Trackpoint>
                        <Position><LatitudeDegrees>37.5010</LatitudeDegrees><LongitudeDegrees>127.0010</LongitudeDegrees></Position>
                        <AltitudeMeters>22</AltitudeMeters>
                      </Trackpoint>
                      <Trackpoint>
                        <Position><LatitudeDegrees>37.5020</LatitudeDegrees><LongitudeDegrees>127.0020</LongitudeDegrees></Position>
                        <AltitudeMeters>20</AltitudeMeters>
                      </Trackpoint>
                    </Track>
                  </Lap>
                </Activity>
              </Activities>
            </TrainingCenterDatabase>
            """.utf8
        )
    }

    private func makeRoute(workoutId: UUID) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.0, longitude: 127.0),
                WorkoutRouteCoordinate(latitude: 37.1, longitude: 127.1)
            ],
            totalDistanceMeters: 1_000,
            createdAt: now
        )
    }

    private func assertNoChanges(
        workout: UnifiedWorkout,
        workoutStore: FakeTCXWorkoutStore,
        routeStore: FakeTCXRouteStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(workoutStore.savedWorkouts, [workout], file: file, line: line)
        XCTAssertTrue(routeStore.savedRoutes.isEmpty, file: file, line: line)
    }

    private func unwrapSuccess(
        _ result: Result<TCXRouteAttachmentResult, TCXRouteAttachmentError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TCXRouteAttachmentResult {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            XCTFail("Expected success, got \(error)", file: file, line: line)
            throw error
        }
    }
}

private final class FakeTCXWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout]
    private let saveError: Error?

    init(workouts: [UnifiedWorkout], saveError: Error? = nil) {
        self.savedWorkouts = workouts
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

    func fetchByExternalId(
        _ externalId: String,
        source: UnifiedDataSource
    ) async throws -> UnifiedWorkout? {
        savedWorkouts.first {
            $0.externalId == externalId && $0.source == source
        }
    }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}

    func deleteWorkout(id: UUID) async throws {
        savedWorkouts.removeAll { $0.id == id }
    }
}

private final class FakeTCXRouteStore: WorkoutRoutePersistenceStoring {
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
}

private enum TCXAttachmentSampleError: Error {
    case storeFailed
}

private extension Result
where Success == TCXRouteAttachmentResult, Failure == TCXRouteAttachmentError {
    var failureValue: TCXRouteAttachmentError? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
