import SwiftData
import XCTest
@testable import SOOM

final class RecordWorkoutSaveFlowTests: XCTestCase {
    private let fixedID = UUID(uuidString: "7F5400D3-373B-4D78-B399-E49B70E6A52E")!
    private let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let endedAt = Date(timeIntervalSince1970: 1_800_003_600)
    private let now = Date(timeIntervalSince1970: 1_800_004_000)
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    func testStopCreatesFinishSummary() {
        let session = finishedSession(sport: .cycling, startedWithLocation: true)

        let summary = RecordWorkoutSummaryBuilder.makeSummary(from: session)

        XCTAssertEqual(summary?.id, fixedID)
        XCTAssertEqual(summary?.sport, .cycling)
        XCTAssertEqual(summary?.workoutType, .cycling)
        XCTAssertEqual(summary?.startedAt, startedAt)
        XCTAssertEqual(summary?.endedAt, endedAt)
        XCTAssertEqual(summary?.durationSeconds, 3_600)
        XCTAssertFalse(summary?.capturedRoute == true)
        XCTAssertTrue(summary?.isTimeOnly == true)
        XCTAssertEqual(summary?.distanceText, "시간 기록")
        XCTAssertNotEqual(summary?.distanceText, "0km")
    }

    func testStopCreatesSummaryWithDistanceAndRouteWhenCaptured() throws {
        let session = finishedRouteSession(sport: .cycling)

        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(from: session))

        XCTAssertFalse(summary.isTimeOnly)
        XCTAssertTrue(summary.capturedRoute)
        XCTAssertNotNil(summary.routeCapture?.startCoordinate)
        XCTAssertNotNil(summary.routeCapture?.endCoordinate)
        XCTAssertGreaterThan(summary.distanceMeters ?? 0, 0)
        XCTAssertNotNil(summary.workoutRoute)
        XCTAssertEqual(summary.workoutRoute?.coordinates.count, 3)
    }

    func testSummaryIsOnlyCreatedForFinishedSession() {
        let session = RecordWorkoutSession(
            id: fixedID,
            sport: .running,
            workoutType: .running,
            startedAt: startedAt,
            startedWithLocation: false,
            state: .active,
            pausedAt: nil,
            endedAt: nil
        )

        XCTAssertNil(RecordWorkoutSummaryBuilder.makeSummary(from: session))
    }

    func testSaveStoresLocalWorkout() async throws {
        let store = FakeUnifiedWorkoutStore()
        let saver = RecordWorkoutSaver(
            store: store,
            mapper: RecordWorkoutSaveMapper(dateProvider: { self.now })
        )
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .running, startedWithLocation: false)
        ))

        let workout = try await saver.save(summary)

        XCTAssertEqual(workout.id, fixedID)
        XCTAssertEqual(workout.source, .soomLocal)
        XCTAssertEqual(workout.workoutType, .running)
        XCTAssertEqual(workout.startDate, startedAt)
        XCTAssertEqual(workout.endDate, endedAt)
        XCTAssertEqual(workout.durationSeconds, 3_600)
        XCTAssertNil(workout.distanceMeters)
        XCTAssertEqual(workout.dataQuality, .partial)
        XCTAssertEqual(workout.createdAt, now)
        XCTAssertEqual(store.savedWorkouts.count, 1)
    }

    func testSaveFlowPersistsDistanceAndRoute() async throws {
        let store = FakeUnifiedWorkoutStore()
        let routeStore = FakeWorkoutRoutePersistenceStore()
        let saver = RecordWorkoutSaver(
            store: store,
            routeStore: routeStore,
            mapper: RecordWorkoutSaveMapper(dateProvider: { self.now })
        )
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedRouteSession(sport: .running)
        ))

        let workout = try await saver.save(summary)
        let route = try await routeStore.fetchRoute(workoutId: workout.id)

        XCTAssertEqual(workout.id, fixedID)
        XCTAssertEqual(workout.source, .soomLocal)
        XCTAssertGreaterThan(workout.distanceMeters ?? 0, 0)
        XCTAssertGreaterThan(workout.averageSpeedMetersPerSecond ?? 0, 0)
        XCTAssertEqual(workout.dataQuality, .partial)
        XCTAssertNotNil(route)
        XCTAssertEqual(route?.workoutId, workout.id)
        XCTAssertEqual(route?.coordinates.count, 3)
        XCTAssertEqual(try XCTUnwrap(route?.totalDistanceMeters), try XCTUnwrap(summary.distanceMeters), accuracy: 0.001)
    }

    func testSavedWorkoutAppearsInActivityStoreRecentWorkouts() async throws {
        let store = FakeUnifiedWorkoutStore()
        let saver = RecordWorkoutSaver(store: store)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .walking, startedWithLocation: false)
        ))

        let saved = try await saver.save(summary)
        let recent = try await store.fetchRecentWorkouts(days: 30)

        XCTAssertEqual(recent.map(\.id), [saved.id])
        XCTAssertEqual(recent.first?.workoutType, .walking)
    }

    @MainActor
    func testSavedMeasurementStreamUsesCorrectedDistanceAndActualSpeedAltitude() async throws {
        var session = RecordWorkoutSessionStarter(dateProvider: { self.startedAt })
            .start(sport: .running, locationState: .mockCurrent)
        session = session.recordingLocation(.init(latitude: 37.5, longitude: 127), at: startedAt,
            speedMetersPerSecond: 2.5, horizontalAccuracy: 5, speedAccuracy: 0.1, altitude: 30)
        session = session.recordingLocation(.init(latitude: 37.5001, longitude: 127), at: startedAt.addingTimeInterval(4),
            speedMetersPerSecond: 2.5, horizontalAccuracy: 5, speedAccuracy: 0.1, altitude: 31)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(from: session.finished(at: startedAt.addingTimeInterval(4))))
        var savedTelemetry: WorkoutTelemetry?
        let saver = RecordWorkoutSaver(store: FakeUnifiedWorkoutStore(), routeStore: FakeWorkoutRoutePersistenceStore(),
            saveTelemetry: { savedTelemetry = $0 })
        let workout = try await saver.save(summary)
        XCTAssertEqual(savedTelemetry?.workoutID, workout.id)
        XCTAssertEqual(savedTelemetry?.samples.last?.distanceMeters ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(savedTelemetry?.samples.last?.speedMetersPerSecond, 2.5)
        XCTAssertEqual(savedTelemetry?.samples.last?.elevationMeters, 31)
        XCTAssertEqual(summary.workoutRoute?.coordinates.last?.altitude, 31)
        XCTAssertNil(savedTelemetry?.samples.last?.heartRateBPM)
    }

    func testDiscardDoesNotStoreWorkout() async throws {
        let store = FakeUnifiedWorkoutStore()
        _ = RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .cycling, startedWithLocation: false)
        )

        let recent = try await store.fetchRecentWorkouts(days: 30)

        XCTAssertTrue(recent.isEmpty)
        XCTAssertTrue(store.savedWorkouts.isEmpty)
    }

    func testTimeOnlyWorkoutCanBeSavedWithoutLocationPermission() async throws {
        let store = FakeUnifiedWorkoutStore()
        let routeStore = FakeWorkoutRoutePersistenceStore()
        let saver = RecordWorkoutSaver(store: store, routeStore: routeStore)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .running, startedWithLocation: false)
        ))

        let workout = try await saver.save(summary)
        let route = try await routeStore.fetchRoute(workoutId: workout.id)

        XCTAssertFalse(summary.capturedRoute)
        XCTAssertNil(workout.distanceMeters)
        XCTAssertEqual(workout.source, .soomLocal)
        XCTAssertNil(route)
    }

    func testSelectedSportPersistsIntoSavedWorkout() async throws {
        for sport in RecordSportMode.allCases {
            let store = FakeUnifiedWorkoutStore()
            let saver = RecordWorkoutSaver(store: store)
            let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
                from: finishedSession(sport: sport, startedWithLocation: false)
            ))

            let workout = try await saver.save(summary)

            XCTAssertEqual(workout.workoutType, sport.workoutType)
        }
    }

    func testSaveFlowDoesNotRequireHealthKitWriteOrRecoveryCalculation() async throws {
        let store = FakeUnifiedWorkoutStore()
        let saver = RecordWorkoutSaver(store: store)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .cycling, startedWithLocation: false)
        ))

        let workout = try await saver.save(summary)

        XCTAssertEqual(workout.source, .soomLocal)
        XCTAssertEqual(workout.dataQuality, .partial)
        XCTAssertNil(workout.averageHeartRate)
        XCTAssertNil(workout.activeEnergyKcal)
    }

    @MainActor
    func testPersistedRouteBackedRecordSavesBuildProcessedWorkoutsForSupportedSports() async throws {
        for sport in RecordSportMode.allCases {
            let fixture = try makePersistedFixture()
            let saver = RecordWorkoutSaver(
                store: fixture.workoutStore,
                routeStore: fixture.routeStore,
                mapper: RecordWorkoutSaveMapper(dateProvider: { self.now })
            )
            let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
                from: finishedRouteSession(sport: sport)
            ))

            let saved = try await saver.save(summary)
            let storedWorkout = try await fixture.workoutStore.fetchWorkout(id: saved.id)
            let storedRoute = try await fixture.routeStore.fetchRoute(workoutId: saved.id)
            let fetchedWorkout = try XCTUnwrap(storedWorkout)
            let fetchedRoute = try XCTUnwrap(storedRoute)
            let summaryDistance = try XCTUnwrap(summary.distanceMeters)
            let processed = ProcessedWorkoutBuilder().make(from: fetchedWorkout, route: fetchedRoute)
            let processedDistance = try XCTUnwrap(processed.distanceMeters)

            XCTAssertEqual(fetchedWorkout.workoutType, sport.workoutType)
            XCTAssertEqual(processed.workoutType, sport.workoutType)
            XCTAssertEqual(processed.durationSeconds, 3_600)
            XCTAssertEqual(processedDistance, summaryDistance, accuracy: 0.001)
            XCTAssertEqual(fetchedRoute.totalDistanceMeters, summaryDistance, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(processed.route?.totalDistanceMeters), fetchedRoute.totalDistanceMeters, accuracy: 0.001)
            XCTAssertEqual(processed.route?.coordinateCount, 3)
            assertMetric(processed, .distance, is: .measured)
            assertMetric(processed, .route, is: .measured)
            assertMissingRecordSensorMetrics(processed, sport: sport)
            assertPrimaryDisplayMetric(processed, sport: sport)
        }
    }

    @MainActor
    func testPersistedTimeOnlyRecordSaveBuildsProcessedWorkoutWithoutRoute() async throws {
        let fixture = try makePersistedFixture()
        let saver = RecordWorkoutSaver(
            store: fixture.workoutStore,
            routeStore: fixture.routeStore,
            mapper: RecordWorkoutSaveMapper(dateProvider: { self.now })
        )
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .running, startedWithLocation: false)
        ))

        let saved = try await saver.save(summary)
        let storedWorkout = try await fixture.workoutStore.fetchWorkout(id: saved.id)
        let fetchedWorkout = try XCTUnwrap(storedWorkout)
        let fetchedRoute = try await fixture.routeStore.fetchRoute(workoutId: saved.id)
        let processed = ProcessedWorkoutBuilder().make(from: fetchedWorkout, route: fetchedRoute)

        XCTAssertNil(fetchedRoute)
        XCTAssertEqual(processed.source, .soomLocal)
        XCTAssertEqual(processed.workoutType, .running)
        XCTAssertEqual(processed.durationSeconds, 3_600)
        XCTAssertNil(processed.distanceMeters)
        XCTAssertNil(processed.averagePaceSecondsPerKilometer)
        XCTAssertNil(processed.averageSpeedMetersPerSecond)
        assertMetric(processed, .duration, is: .measured)
        assertMetric(processed, .distance, is: .missing)
        assertMetric(processed, .pace, is: .missing)
        assertMetric(processed, .route, is: .missing)
        assertMissingRecordSensorMetrics(processed, sport: .running)
        XCTAssertEqual(processed.display.primaryMetricValue, "움직임 준비 중")
    }

    @MainActor
    func testPersistedLocationDeniedRecordSaveBuildsValidProcessedWorkout() async throws {
        let fixture = try makePersistedFixture()
        let saver = RecordWorkoutSaver(
            store: fixture.workoutStore,
            routeStore: fixture.routeStore,
            mapper: RecordWorkoutSaveMapper(dateProvider: { self.now })
        )
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedLocationDeniedSession(sport: .walking)
        ))

        let saved = try await saver.save(summary)
        let storedWorkout = try await fixture.workoutStore.fetchWorkout(id: saved.id)
        let fetchedWorkout = try XCTUnwrap(storedWorkout)
        let fetchedRoute = try await fixture.routeStore.fetchRoute(workoutId: saved.id)
        let processed = ProcessedWorkoutBuilder().make(from: fetchedWorkout, route: fetchedRoute)

        XCTAssertFalse(summary.capturedRoute)
        XCTAssertNil(fetchedRoute)
        XCTAssertEqual(processed.workoutType, .walking)
        XCTAssertEqual(processed.durationSeconds, 3_600)
        XCTAssertNil(processed.distanceMeters)
        assertMetric(processed, .duration, is: .measured)
        assertMetric(processed, .distance, is: .missing)
        assertMetric(processed, .speed, is: .missing)
        assertMetric(processed, .route, is: .missing)
        assertMissingRecordSensorMetrics(processed, sport: .walking)
        XCTAssertEqual(processed.display.primaryMetricLabel, "속도")
        XCTAssertEqual(processed.display.primaryMetricValue, "움직임 준비 중")
    }

    private func finishedSession(
        sport: RecordSportMode,
        startedWithLocation: Bool
    ) -> RecordWorkoutSession {
        RecordWorkoutSession(
            id: fixedID,
            sport: sport,
            workoutType: sport.workoutType,
            startedAt: startedAt,
            startedWithLocation: startedWithLocation,
            state: .finished,
            pausedAt: nil,
            endedAt: endedAt
        )
    }

    private func finishedRouteSession(sport: RecordSportMode) -> RecordWorkoutSession {
        let starter = RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.startedAt }
        )
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
            fallbackCoordinate: RecordLocationState.fallbackCoordinate,
            locationTimestamp: startedAt, horizontalAccuracy: 5
        )

        return starter.start(sport: sport, locationState: state)
            .recordingLocation(RecordMapCoordinate(latitude: 37.5267, longitude: 126.9272), at: startedAt.addingTimeInterval(10))
            .recordingLocation(RecordMapCoordinate(latitude: 37.5268, longitude: 126.9273), at: startedAt.addingTimeInterval(20))
            .finished(at: endedAt)
    }

    private func finishedLocationDeniedSession(sport: RecordSportMode) -> RecordWorkoutSession {
        let starter = RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.startedAt }
        )
        let state = RecordLocationState(
            authorization: .denied,
            coordinate: nil,
            fallbackCoordinate: RecordLocationState.fallbackCoordinate,
            locationTimestamp: startedAt, horizontalAccuracy: 5
        )

        return starter.start(sport: sport, locationState: state)
            .finished(at: endedAt)
    }

    @MainActor
    private func makePersistedFixture() throws -> (
        workoutStore: SwiftDataUnifiedWorkoutStore,
        routeStore: SwiftDataWorkoutRoutePersistenceStore
    ) {
        let schema = Schema([
            UnifiedWorkoutRecord.self,
            PersistedWorkoutRoute.self
        ])
        let configuration = ModelConfiguration(
            "RecordWorkoutSaverProcessedWorkoutTests-\(UUID().uuidString)",
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
                referenceDate: { self.now }
            ),
            SwiftDataWorkoutRoutePersistenceStore(
                modelContext: container.mainContext,
                referenceDate: { self.now }
            )
        )
    }

    private func assertPrimaryDisplayMetric(
        _ processed: ProcessedWorkout,
        sport: RecordSportMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch sport {
        case .cycling:
            XCTAssertEqual(processed.display.primaryMetricLabel, "속도", file: file, line: line)
            assertMetric(processed, .speed, is: .measured, file: file, line: line)
            assertMetric(processed, .pace, is: .unsupported, file: file, line: line)
            XCTAssertNotEqual(processed.display.primaryMetricValue, "움직임 준비 중", file: file, line: line)
        case .running:
            XCTAssertEqual(processed.display.primaryMetricLabel, "페이스", file: file, line: line)
            assertMetric(processed, .pace, is: .derived, file: file, line: line)
            assertMetric(processed, .speed, is: .unsupported, file: file, line: line)
            XCTAssertNotEqual(processed.display.primaryMetricValue, "움직임 준비 중", file: file, line: line)
        case .walking:
            XCTAssertEqual(processed.display.primaryMetricLabel, "속도", file: file, line: line)
            assertMetric(processed, .speed, is: .measured, file: file, line: line)
            assertMetric(processed, .pace, is: .unsupported, file: file, line: line)
            XCTAssertNotEqual(processed.display.primaryMetricValue, "움직임 준비 중", file: file, line: line)
        }
    }

    private func assertMissingRecordSensorMetrics(
        _ processed: ProcessedWorkout,
        sport: RecordSportMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(processed.averageHeartRate, file: file, line: line)
        XCTAssertNil(processed.maxHeartRate, file: file, line: line)
        XCTAssertNil(processed.activeEnergyKcal, file: file, line: line)
        XCTAssertNil(processed.elevationGainMeters, file: file, line: line)
        assertMetric(processed, .averageHeartRate, is: .missing, file: file, line: line)
        assertMetric(processed, .maxHeartRate, is: .missing, file: file, line: line)
        assertMetric(processed, .calories, is: .missing, file: file, line: line)
        assertMetric(processed, .elevation, is: .missing, file: file, line: line)
        assertMetric(processed, .power, is: sport == .cycling ? .missing : .unsupported, file: file, line: line)
        assertMetric(processed, .cadence, is: .missing, file: file, line: line)
        assertMetric(processed, .splits, is: .missing, file: file, line: line)
        assertMetric(processed, .zones, is: .missing, file: file, line: line)
    }

    private func assertMetric(
        _ workout: ProcessedWorkout,
        _ metric: ProcessedWorkoutMetric,
        is expectedState: ProcessedWorkoutMetricState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(workout.metricAvailability[metric], expectedState, file: file, line: line)
    }

}

private final class FakeUnifiedWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout] = []
    var shouldFail = false

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        if shouldFail { throw RecordingStorageFailure.expected }
        savedWorkouts.removeAll { $0.id == workout.id }
        savedWorkouts.append(workout)
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        for workout in workouts {
            try await saveWorkout(workout)
        }
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        guard days > 0 else { return [] }
        return savedWorkouts.sorted { $0.startDate > $1.startDate }
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

private final class FakeWorkoutRoutePersistenceStore: WorkoutRoutePersistenceStoring {
    private var routesByWorkoutId: [UUID: WorkoutRoute] = [:]
    var shouldFail = false

    func saveRoute(_ route: WorkoutRoute) async throws {
        if shouldFail { throw RecordingStorageFailure.expected }
        routesByWorkoutId[route.workoutId] = route
    }

    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute? {
        routesByWorkoutId[workoutId]
    }

    func fetchRoutes(workoutIds: [UUID]) async throws -> [WorkoutRoute] {
        workoutIds.compactMap { routesByWorkoutId[$0] }
    }

    func deleteRoute(workoutId: UUID) async throws {
        routesByWorkoutId.removeValue(forKey: workoutId)
    }

    func deleteAllRoutes() async throws {
        routesByWorkoutId.removeAll()
    }
}

extension RecordWorkoutSaveFlowTests {
    func testRouteFailureReportsAlreadySavedWorkoutAndRetryUsesSameIdentity() async throws {
        let workouts = FakeUnifiedWorkoutStore()
        let routes = FakeWorkoutRoutePersistenceStore()
        routes.shouldFail = true
        let saver = RecordWorkoutSaver(store: workouts, routeStore: routes)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(from: finishedRouteSession(sport: .running)))
        do {
            _ = try await saver.save(summary)
            XCTFail("Route failure must not be reported as a complete save")
        } catch RecordWorkoutSaveError.routeNotSaved(let saved, _) {
            XCTAssertEqual(saved.id, summary.id)
            XCTAssertEqual(workouts.savedWorkouts.count, 1)
            XCTAssertEqual(saved.durationSeconds, summary.durationSeconds)
        }
        let missingRoute = try await routes.fetchRoute(workoutId: summary.id)
        XCTAssertNil(missingRoute)
        routes.shouldFail = false
        let retry = try await saver.save(summary)
        let savedRoute = try await routes.fetchRoute(workoutId: summary.id)
        XCTAssertEqual(workouts.savedWorkouts.count, 1)
        XCTAssertEqual(retry.id, summary.id)
        XCTAssertNotNil(savedRoute)
    }

    func testMissingRouteStoreCannotClaimFullRouteSave() async throws {
        let workouts = FakeUnifiedWorkoutStore()
        let saver = RecordWorkoutSaver(store: workouts)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(from: finishedRouteSession(sport: .cycling)))
        do {
            _ = try await saver.save(summary)
            XCTFail("Captured route requires a route store")
        } catch RecordWorkoutSaveError.routeNotSaved(let workout, let underlying) {
            XCTAssertEqual(workout.id, summary.id)
            XCTAssertNil(underlying)
        }
        XCTAssertEqual(workouts.savedWorkouts.count, 1)
    }

    func testWorkoutFailureDoesNotWriteAnOrphanRoute() async throws {
        let workouts = FakeUnifiedWorkoutStore()
        workouts.shouldFail = true
        let routes = FakeWorkoutRoutePersistenceStore()
        let saver = RecordWorkoutSaver(store: workouts, routeStore: routes)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(from: finishedRouteSession(sport: .walking)))
        do {
            _ = try await saver.save(summary)
            XCTFail("Expected workout storage failure")
        } catch RecordingStorageFailure.expected {}
        let route = try await routes.fetchRoute(workoutId: summary.id)
        XCTAssertNil(route)
        XCTAssertTrue(workouts.savedWorkouts.isEmpty)
    }
}

private enum RecordingStorageFailure: Error { case expected }
