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

    func testAutoPublicImportMarksOnlyNewHealthKitWorkoutsForPublication() async {
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(result: .success([
                makeWorkout(id: UUID(), type: .running)
            ])), store: store, autoPublishNewWorkouts: true)
        let result = await pipeline.importRecentWorkouts(limit: 10)
        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.importedWorkouts.first?.sharingVisibilityRaw,
                       ImportedWorkoutPublication.pendingVisibility(for:.privatePost))
        XCTAssertEqual(store.savedWorkouts.first?.sharingVisibilityRaw,
                       ImportedWorkoutPublication.pendingVisibility(for:.privatePost))
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

    func testOverlappingHealthKitSourceRetainsItsOwnRoute() async {
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

        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(routeStore.savedRoutes.first?.workoutId, workoutID)
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

    func testAutomaticImportSkipsExistingHealthKitWorkoutWithoutRepublishing() async {
        let store = FakeUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(result: .success([
                makeWorkout(id: UUID(), type: .running)
            ])), store: store, autoPublishNewWorkouts: true)

        let first = await pipeline.importRecentWorkouts()
        let second = await pipeline.importRecentWorkouts()

        XCTAssertEqual(first.savedCount, 1)
        XCTAssertEqual(second.savedCount, 0)
        XCTAssertEqual(second.skippedCount, 1)
        XCTAssertTrue(second.importedWorkouts.isEmpty)
        XCTAssertEqual(store.savedWorkouts.count, 1)
    }

    func testSimilarHealthKitWorkoutRetainsItsRawSourceForReview() async {
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
        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(store.savedWorkouts.count, 2)
        XCTAssertEqual(store.savedWorkouts.first?.source, .soomLocal)
        XCTAssertEqual(store.savedWorkouts.last?.source, .appleHealthKit)
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

    func testExistingWorkoutRepairsLateRouteWithoutNewCardOrLosingOwnerFields() async {
        let id = UUID()
        var existing = makeUnifiedWorkout(id: id, source: .appleHealthKit, type: .running,
            startDate: Date(timeIntervalSince1970: 1_800_000_000), duration: 3_600,
            distance: 10_000, externalId: id.uuidString)
        existing.userTitle = "내 러닝"
        existing.userDescription = "사진과 댓글은 유지"
        existing.sharingVisibilityRaw = "private"
        existing.isBookmarked = true
        existing.preferredWorkoutID = id
        let store = FakeUnifiedWorkoutStore(existingWorkouts: [existing])
        let routes = FakeWorkoutRoutePersistenceStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(result: .success([makeWorkout(id: id, type: .running)])),
            store: store, routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: FakeHealthKitWorkoutRouteFetcher(route: makeRoute(workoutId: id)), routeStore: routes,
            autoPublishNewWorkouts: true)
        let result = await pipeline.importRecentWorkouts()
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.refreshedWorkouts.count, 1)
        XCTAssertEqual(store.savedWorkouts.count, 1)
        XCTAssertEqual(routes.savedRoutes.first?.workoutId, id)
        XCTAssertEqual(store.savedWorkouts.first?.routeMissingReason, WorkoutRouteMissingReason.none)
        XCTAssertEqual(store.savedWorkouts.first?.userTitle, existing.userTitle)
        XCTAssertEqual(store.savedWorkouts.first?.sharingVisibilityRaw, existing.sharingVisibilityRaw)
        XCTAssertEqual(store.savedWorkouts.first?.isBookmarked, true)
        XCTAssertEqual(store.savedWorkouts.first?.preferredWorkoutID, id)
    }

    func testOverlappingRunIsSavedForReviewInsteadOfPublishingSecondCard() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let local = makeUnifiedWorkout(source: .soomLocal, type: .running, startDate: start, duration: 4_380, distance: 11_250)
        let store = FakeUnifiedWorkoutStore(existingWorkouts: [local])
        let pipeline = HealthKitWorkoutImportPipeline(workoutFetcher: FakeHealthKitWorkoutFetcher(result: .success([
            makeWorkout(type: .running, startDate: start.addingTimeInterval(240), duration: 4_140, distance: 10_030)
        ])), store: store, autoPublishNewWorkouts: true)
        let result = await pipeline.importRecentWorkouts()
        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.importedWorkouts.first?.sharingVisibilityRaw, "source_review_pending")
        XCTAssertEqual(store.savedWorkouts.count, 2)
    }

    @MainActor
    func testTelemetryIsStoredAgainstStableImportedIDAndPartialChannelFailureIsReported() async {
        let id = UUID()
        var saved: WorkoutTelemetry?
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let telemetry = WorkoutTelemetry(workoutID: UUID(), source: .appleHealthKit, samples: [
            .init(timestamp: start, heartRateBPM: 140, powerWatts: 220, speedMetersPerSecond: 2.5),
            .init(timestamp: start.addingTimeInterval(5), heartRateBPM: 145, powerWatts: 225)
        ])
        let pipeline = HealthKitWorkoutImportPipeline(workoutFetcher: FakeHealthKitWorkoutFetcher(result: .success([makeWorkout(id: id, type: .running)])),
            store: FakeUnifiedWorkoutStore(), routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            telemetryFetcher: FakeHealthKitTelemetryFetcher(value: .init(telemetry: telemetry, failedChannels: ["stepCount"])),
            saveTelemetry: { saved = $0 })
        let result = await pipeline.importRecentWorkouts()
        XCTAssertEqual(saved?.workoutID, id)
        XCTAssertEqual(saved?.samples.compactMap(\.powerWatts), [220, 225])
        XCTAssertEqual(result.detailWarningCount, 1)
        XCTAssertEqual(result.importedWorkouts.first?.averageHeartRate, 142.5)
        XCTAssertEqual(result.failedCount, 0)
    }

    @MainActor
    func testRealHealthKitQuantitiesMapRunningChannelsWithoutCyclingUnitsOrSummaryGraphs() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let raw = HKWorkout(activityType: .running, start: start, end: start.addingTimeInterval(60),
            duration: 60, totalEnergyBurned: nil, totalDistance: HKQuantity(unit: .meter(), doubleValue: 100), metadata: nil)
        var requested: [HKQuantityTypeIdentifier] = []
        let fetcher = HealthKitWorkoutTelemetryFetcher(sampleProvider: { identifier, workout in
            requested.append(identifier)
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
            let value: Double
            let unit: HKUnit
            switch identifier {
            case .heartRate: value = 140; unit = HKUnit.count().unitDivided(by: .minute())
            case .runningPower: value = 225; unit = .watt()
            case .runningSpeed: value = 2.5; unit = HKUnit.meter().unitDivided(by: .second())
            case .stepCount: value = 80; unit = .count()
            case .distanceWalkingRunning: value = 100; unit = .meter()
            case .activeEnergyBurned: value = 10; unit = .kilocalorie()
            default: return []
            }
            return [HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                start: workout.startDate, end: workout.startDate.addingTimeInterval(30))]
        })
        let result = try await fetcher.fetchTelemetry(for: raw)
        XCTAssertEqual(result.telemetry.samples.compactMap(\.heartRateBPM), [140])
        XCTAssertEqual(result.telemetry.samples.compactMap(\.powerWatts), [225])
        XCTAssertEqual(result.telemetry.samples.compactMap(\.speedMetersPerSecond), [2.5])
        XCTAssertEqual(result.telemetry.intervals.first { $0.kind == .steps }?.value, 80)
        XCTAssertEqual(result.telemetry.intervals.first { $0.kind == .distanceMeters }?.value, 100)
        let derived = WorkoutTelemetryChartBuilder.addingDerivedChannels(to: result.telemetry, route: nil)
        XCTAssertEqual(derived.samples.compactMap(\.cadencePerMinute), [160])
        XCTAssertTrue(requested.contains(.runningPower))
        XCTAssertFalse(requested.contains(.cyclingPower))
        XCTAssertTrue(result.failedChannels.isEmpty)
        XCTAssertTrue(HealthKitManager.readTypes.contains(HKQuantityType.quantityType(forIdentifier: .runningPower)!))
        XCTAssertTrue(HealthKitManager.readTypes.contains(HKQuantityType.quantityType(forIdentifier: .runningSpeed)!))
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

private struct FakeHealthKitTelemetryFetcher: HealthKitWorkoutTelemetryFetching {
    let value: HealthKitWorkoutTelemetryResult
    func fetchTelemetry(for workout: HKWorkout) async throws -> HealthKitWorkoutTelemetryResult { value }
}

@MainActor
final class HealthKitMissingDetailTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func raw(_ type: HKWorkoutActivityType = .running, events: [HKWorkoutEvent]? = nil,
                     length: Double? = nil, energy: Double? = nil) -> HKWorkout {
        HKWorkout(activityType: type, start: start, end: start.addingTimeInterval(120),
            workoutEvents: events, totalEnergyBurned: energy.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) },
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 1000),
            metadata: length.map { [HKMetadataKeyLapLength: HKQuantity(unit: .meter(), doubleValue: $0), HKMetadataKeySwimmingLocationType: NSNumber(value: HKWorkoutSwimmingLocationType.pool.rawValue)] })
    }
    private func sample(_ identifier: HKQuantityTypeIdentifier = .heartRate, device: String = "watch-a",
                        from: Double = 10, to: Double = 11) -> HKQuantitySample {
        HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: identifier)!,
            quantity: HKQuantity(unit: identifier == .heartRate ? HKUnit.count().unitDivided(by: .minute()) : .meter(), doubleValue: identifier == .heartRate ? 142 : 500),
            start: start.addingTimeInterval(from), end: start.addingTimeInterval(to),
            device: HKDevice(name: "Synthetic Watch", manufacturer: "Fixture", model: "Watch", hardwareVersion: nil,
                firmwareVersion: nil, softwareVersion: nil, localIdentifier: device, udiDeviceIdentifier: nil), metadata: nil)
    }
    private func unified(_ workout: HKWorkout) -> UnifiedWorkout {
        HealthKitWorkoutToUnifiedWorkoutMapper().map(HealthKitWorkout(workout: workout), mappedAt: start)
    }
    func testNikePatternUnlinkedWatchHeartRateUsesExactTimeFallbackOnlyForHeartRate() async throws {
        var scopes: [(HKQuantityTypeIdentifier, HealthKitSampleQueryScope)] = []
        let reading = sample()
        let fetcher = HealthKitWorkoutTelemetryFetcher(queryProvider: { identifier, _, scope in
            scopes.append((identifier, scope))
            return identifier == .heartRate && scope == .timeWindow ? [reading] : []
        })
        let result = try await fetcher.fetchTelemetry(for: raw())
        XCTAssertEqual(result.telemetry.samples.compactMap(\.heartRateBPM), [142])
        XCTAssertTrue(result.telemetry.intervals.isEmpty)
        XCTAssertFalse(scopes.contains { $0.0 != .heartRate && $0.1 == .timeWindow })
    }
    func testAppleWatchLinkedHeartRateDoesNotRunFallbackQueries() async throws {
        var heartScopes: [HealthKitSampleQueryScope] = []
        let reading = sample()
        let fetcher = HealthKitWorkoutTelemetryFetcher(queryProvider: { identifier, _, scope in
            guard identifier == .heartRate else { return [] }
            heartScopes.append(scope)
            return [reading]
        })
        let result = try await fetcher.fetchTelemetry(for: raw())
        XCTAssertEqual(heartScopes, [.associated])
        XCTAssertEqual(result.telemetry.samples.compactMap(\.heartRateBPM), [142])
    }
    func testHeartRateFallbackRejectsAmbiguousDevicesAndOutsideWorkout() {
        XCTAssertTrue(HealthKitWorkoutTelemetryFetcher.unambiguousHeartRate([sample(device: "a"), sample(device: "b")], workout: raw()).isEmpty)
        XCTAssertTrue(HealthKitWorkoutTelemetryFetcher.unambiguousHeartRate([sample(from: -1, to: 1), sample(from: 119, to: 121)], workout: raw()).isEmpty)
        XCTAssertEqual(HealthKitWorkoutTelemetryFetcher.unambiguousHeartRate([sample(), sample(from: 50, to: 51)], workout: raw()).count, 2)
    }
    func testChannelFailurePreservesOtherDataAndCancellationIsNotEmptySuccess() async throws {
        let reading = sample()
        let fetcher = HealthKitWorkoutTelemetryFetcher(queryProvider: { identifier, _, _ in
            if identifier == .distanceWalkingRunning { throw NSError(domain: "fixture", code: 1) }
            return identifier == .heartRate ? [reading] : []
        })
        let result = try await fetcher.fetchTelemetry(for: raw())
        XCTAssertEqual(result.telemetry.samples.compactMap(\.heartRateBPM), [142])
        XCTAssertEqual(result.failedChannels, [HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue])
        let cancelled = HealthKitWorkoutTelemetryFetcher(queryProvider: { _, _, _ in throw CancellationError() })
        do { _ = try await cancelled.fetchTelemetry(for: raw()); XCTFail("Cancellation must propagate") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
    }
    private func event(_ type: HKWorkoutEventType, _ offset: Double, _ seconds: Double) -> HKWorkoutEvent {
        HKWorkoutEvent(type: type, dateInterval: DateInterval(start: start.addingTimeInterval(offset), duration: seconds), metadata: nil)
    }
    func testSwimmingOriginalLapsDistanceTimeAndLegacyCaloriesArePreserved() async throws {
        let workout = raw(.swimming, events: [event(.lap, 0, 30), event(.lap, 35, 40)], length: 25, energy: 88)
        let fetcher = HealthKitWorkoutTelemetryFetcher(sampleProvider: { _, _ in [] })
        let details = try await fetcher.fetchTelemetry(for: workout)
        XCTAssertEqual(details.telemetry.splits.map(\.durationSeconds), [30, 40])
        XCTAssertEqual(details.telemetry.splits.map(\.distanceMeters), [25, 25])
        XCTAssertEqual(details.telemetry.splits.map(\.label), ["랩 1", "랩 2"])
        let updated = unified(raw(.swimming)).withHealthKitDetails(workout, telemetry: details.telemetry)
        XCTAssertEqual(updated.activeEnergyKcal, 88)
        let display = WorkoutSplitDisplay(type: .swimming, preferredUnit: .metric, showsLapDuration: true)
        XCTAssertEqual(display.text(distance: nil, seconds: 30), "0:30")
        XCTAssertEqual(display.distanceText(25), "25 m")
        XCTAssertEqual(display.unit, "")
    }
    func testSwimmingDoesNotInventLengthsForTimestampEventsOrMissingMetadata() {
        XCTAssertTrue(HealthKitWorkoutTelemetryFetcher.swimmingSplits(raw(.swimming, events: [event(.lap, 30, 0)], length: 25)).isEmpty)
        let missing = HealthKitWorkoutTelemetryFetcher.swimmingSplits(raw(.swimming, events: [event(.lap, 0, 30)]))
        XCTAssertEqual(missing.count, 1)
        XCTAssertNil(missing.first?.distanceMeters)
        let segment = HealthKitWorkoutTelemetryFetcher.swimmingSplits(raw(.swimming, events: [event(.segment, 0, 60)], length: 25))
        XCTAssertEqual(segment.first?.label, "구간 1")
        XCTAssertNil(segment.first?.distanceMeters)
    }
    func testSwimmingOverlapsAndSegmentDuplicatesAreRejected() {
        XCTAssertTrue(HealthKitWorkoutTelemetryFetcher.swimmingSplits(raw(.swimming, events: [event(.lap, 0, 40), event(.lap, 30, 40)])).isEmpty)
        let laps = HealthKitWorkoutTelemetryFetcher.swimmingSplits(raw(.swimming, events: [event(.lap, 0, 30), event(.segment, 0, 90)], length: 25))
        XCTAssertEqual(laps.count, 1)
        XCTAssertEqual(laps.first?.label, "랩 1")
    }
    func testSwimmingDistanceSeriesCannotBecomeSyntheticKilometreLaps() {
        let telemetry = WorkoutTelemetry(workoutID: UUID(), source: .appleHealthKit, samples: [
            .init(timestamp: start, distanceMeters: 0), .init(timestamp: start.addingTimeInterval(60), distanceMeters: 1000)])
        XCTAssertTrue(WorkoutTelemetryChartBuilder.derivedSplits(telemetry, workoutType: .swimming).isEmpty)
        XCTAssertEqual(WorkoutTelemetryChartBuilder.derivedSplits(telemetry, workoutType: .running).count, 1)
    }
    func testCacheCoalescesConcurrentReadsAndReentryWithoutNewQueries() async throws {
        let cache = HealthKitDetailReadCache()
        let key = HealthKitDetailReadCache.Key(scope: "fixture", workoutID: UUID(), externalID: UUID().uuidString, revision: start, needsRoute: false)
        var calls = 0
        let loader: @MainActor () async throws -> HealthKitDetailReadResult = { calls += 1; await Task.yield(); return .init() }
        async let first = cache.read(key: key, loader: loader)
        async let second = cache.read(key: key, loader: loader)
        _ = try await (first, second)
        _ = try await cache.read(key: key, loader: loader)
        XCTAssertEqual(calls, 1)
        _ = try await cache.read(key: key, force: true, loader: loader)
        XCTAssertEqual(calls, 2)
    }
    func testEmptyCacheExpiresAndRevisionOrAccountChangeReadsAgain() async throws {
        var time = start
        let cache = HealthKitDetailReadCache(now: { time })
        let id = UUID(); let external = UUID().uuidString
        func key(_ scope: String = "a", _ revision: Date? = nil) -> HealthKitDetailReadCache.Key {
            .init(scope: scope, workoutID: id, externalID: external, revision: revision ?? start, needsRoute: true)
        }
        var calls = 0
        let loader: @MainActor () async throws -> HealthKitDetailReadResult = { calls += 1; return .init() }
        _ = try await cache.read(key: key(), loader: loader)
        _ = try await cache.read(key: key(), loader: loader)
        XCTAssertEqual(calls, 1)
        time = time.addingTimeInterval(31)
        _ = try await cache.read(key: key(), loader: loader)
        _ = try await cache.read(key: key("a", time), loader: loader)
        _ = try await cache.read(key: key("b"), loader: loader)
        XCTAssertEqual(calls, 4)
    }
    func testCancelledCacheLoadIsNotCachedAndDoesNotErasePersistedData() async throws {
        let cache = HealthKitDetailReadCache()
        let key = HealthKitDetailReadCache.Key(scope: "a", workoutID: UUID(), externalID: UUID().uuidString, revision: start, needsRoute: false)
        do { _ = try await cache.read(key: key) { throw CancellationError() }; XCTFail("must throw") }
        catch is CancellationError {} catch { XCTFail("wrong error") }
        var calls = 0
        _ = try await cache.read(key: key) { calls += 1; return .init() }
        XCTAssertEqual(calls, 1)
        let saved = WorkoutTelemetry(workoutID: key.workoutID, source: .appleHealthKit, samples: [.init(timestamp: start, heartRateBPM: 140)])
        let merged = saved.merging(WorkoutTelemetry(workoutID: key.workoutID, source: .appleHealthKit))
        XCTAssertEqual(merged.samples.compactMap(\.heartRateBPM), [140])
    }
    func testHeartSummaryRemainsVisibleWithoutInventingSeriesOrZones() {
        let workout = raw()
        let measured = WorkoutTelemetry(workoutID: workout.uuid, source: .appleHealthKit,
            samples: [.init(timestamp: start.addingTimeInterval(10), heartRateBPM: 142)])
        let model = unified(workout).withHealthKitDetails(workout, telemetry: measured)
        let empty = WorkoutTelemetry(workoutID: model.id, source: .appleHealthKit)
        XCTAssertEqual(empty.displaySummaryMetrics(for: model).first { $0.key == "averageHeartRate" }?.value, 142)
        XCTAssertTrue(empty.samples.isEmpty)
        XCTAssertTrue(empty.heartRateZones.isEmpty)
        XCTAssertTrue(measured.displaySummaryMetrics(for: model).isEmpty)
        XCTAssertTrue(empty.displaySummaryMetrics(for: unified(workout)).isEmpty)
    }
    func testPhoneRecordedWorkoutCanUseOneWatchSensorAndPreserveDisplayRevision() {
        let phone = HKDevice(name: "Fixture phone", manufacturer: "Fixture", model: "Phone", hardwareVersion: nil,
            firmwareVersion: nil, softwareVersion: nil, localIdentifier: "phone", udiDeviceIdentifier: nil)
        let workout = HKWorkout(activityType: .running, start: start, end: start.addingTimeInterval(120),
            workoutEvents: nil, totalEnergyBurned: nil, totalDistance: nil, device: phone, metadata: nil)
        XCTAssertEqual(HealthKitWorkoutTelemetryFetcher.unambiguousHeartRate([sample()], workout: workout).count, 1)
        let model = unified(workout)
        let telemetry = WorkoutTelemetry(workoutID: model.id, source: .appleHealthKit,
            samples: [.init(timestamp: start.addingTimeInterval(10), heartRateBPM: 142)])
        let first = model.withHealthKitDetails(workout, telemetry: telemetry, updatedAt: model.updatedAt)
        let next = model.withHealthKitDetails(workout, telemetry: telemetry, updatedAt: model.updatedAt)
        XCTAssertEqual(first, next)
        XCTAssertEqual(first.updatedAt, model.updatedAt)
        XCTAssertEqual(first.averageHeartRate, 142)
    }
    func testMissingDetailPolicyDoesNotDependOnRecentThreeDayWindow() {
        let workout = unified(raw(.swimming))
        XCTAssertTrue(HealthKitDetailReadCache.needsMeasurements(workout, telemetry: nil))
        let other = UnifiedWorkout(id: UUID(), externalId: nil, source: .manual, workoutType: .swimming,
            startDate: start, endDate: start.addingTimeInterval(120), durationSeconds: 120,
            distanceMeters: nil, activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: workout.dataQuality,
            createdAt: start, updatedAt: start)
        XCTAssertFalse(HealthKitDetailReadCache.needsMeasurements(other, telemetry: nil))
    }
}


private struct CancelledHealthTelemetryFixture: HealthKitWorkoutTelemetryFetching {
    func fetchTelemetry(for workout: HKWorkout) async throws -> HealthKitWorkoutTelemetryResult { throw CancellationError() }
}
extension HealthKitWorkoutImportPipelineTests {
    @MainActor
    func testCancelledTelemetryImportDoesNotContinueToDetailSave() async {
        let store = FakeUnifiedWorkoutStore()
        var detailSaves = 0
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: FakeHealthKitWorkoutFetcher(result: .success([makeWorkout(type: .running)])),
            store: store, routeLookupProvider: FakeHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            telemetryFetcher: CancelledHealthTelemetryFixture(), saveTelemetry: { _ in detailSaves += 1 })
        _ = await pipeline.importRecentWorkouts(limit: 1)
        XCTAssertEqual(detailSaves, 0)
        XCTAssertEqual(store.savedWorkouts.count, 1, "Only the initial identity save may precede cancellation; no post-cancellation writes")
    }
}
