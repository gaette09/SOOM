import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class WorkoutRegionResolverTests: XCTestCase {
    func testPointUsesMaskedInteriorAndRoundsToHundredthDegree() {
        let route = makeRoute()
        let interior = RoutePrivacyMasker().mask(route: route).coordinates
        let middle = interior[interior.count / 2]
        let point = WorkoutRegionQueryPoint.make(route: route)
        XCTAssertEqual(point?.latitude, (middle.latitude * 100).rounded() / 100)
        XCTAssertEqual(point?.longitude, (middle.longitude * 100).rounded() / 100)
        XCTAssertNotEqual(point?.latitude, route.coordinates.first?.latitude)
        XCTAssertNotEqual(point?.latitude, route.coordinates.last?.latitude)
    }

    func testInvalidAndFullyMaskedRoutesHaveNoLookupPoint() {
        let id = UUID()
        let invalid = WorkoutRoute(workoutId: id, source: .soomLocal,
            coordinates: [.init(latitude: .nan, longitude: 127), .init(latitude: 37, longitude: 127)], totalDistanceMeters: 100)
        let short = WorkoutRoute(workoutId: id, source: .soomLocal,
            coordinates: [.init(latitude: 37, longitude: 127), .init(latitude: 37.00001, longitude: 127)], totalDistanceMeters: 1)
        XCTAssertNil(WorkoutRegionQueryPoint.make(route: invalid))
        XCTAssertNil(WorkoutRegionQueryPoint.make(route: short))
    }

    func testPlacemarkIncludesCityDistrictButOmitsNeighborhood() {
        XCTAssertEqual(WorkoutRegionPlacemark(locality: "용인시", administrativeArea: "경기도", subLocality: "수지구").displayName,
                       "경기도 용인시 수지구")
        XCTAssertEqual(WorkoutRegionPlacemark(locality: "서울특별시", administrativeArea: "서울특별시", subLocality: "잠실동").displayName,
                       "서울특별시")
        XCTAssertNil(WorkoutRegionPlacemark(locality: " \n", subLocality: "잠실동").displayName)
    }

    func testRepeatedPointUsesAccountScopedCache() async {
        let geocoder = StubGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let first = await resolver.resolve(route: makeRoute(), scopeID: "A", isCurrent: { true })
        let repeatValue = await resolver.resolve(route: makeRoute(), scopeID: "A", isCurrent: { true })
        let other = await resolver.resolve(route: makeRoute(), scopeID: "B", isCurrent: { true })
        XCTAssertEqual(first, "서울특별시")
        XCTAssertEqual(repeatValue, first)
        XCTAssertEqual(other, first)
        XCTAssertEqual(geocoder.points.count, 2)
    }

    func testFailureBackoffExpiresAndCanRetry() async {
        let geocoder = StubGeocoder()
        geocoder.value = nil
        let clock = Clock()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0, failureBackoff: 900, now: { clock.date })
        let first = await resolver.resolve(route: makeRoute(), scopeID: "A", isCurrent: { true })
        geocoder.value = .init(locality: "서울특별시")
        let duringBackoff = await resolver.resolve(route: makeRoute(), scopeID: "A", isCurrent: { true })
        clock.date.addTimeInterval(901)
        let afterBackoff = await resolver.resolve(route: makeRoute(), scopeID: "A", isCurrent: { true })
        XCTAssertNil(first)
        XCTAssertNil(duringBackoff)
        XCTAssertEqual(afterBackoff, "서울특별시")
        XCTAssertEqual(geocoder.points.count, 2)
    }

    func testDifferentPointsAreSerializedAndThrottled() async {
        let geocoder = StubGeocoder()
        let clock = Clock()
        var waits: [TimeInterval] = []
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 60, now: { clock.date }, sleep: {
            waits.append($0)
            clock.date.addTimeInterval($0)
        })
        _ = await resolver.resolve(route: makeRoute(), scopeID: "A", isCurrent: { true })
        _ = await resolver.resolve(route: makeRoute(latitude: 38.12123), scopeID: "A", isCurrent: { true })
        XCTAssertEqual(waits, [60])
        XCTAssertEqual(geocoder.points.count, 2)
        XCTAssertEqual(geocoder.maximumConcurrentCalls, 1)
    }

    func testConcurrentSamePointJoinsSingleLookup() async {
        let geocoder = SuspendedGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let route = makeRoute()
        let first = Task { await resolver.resolve(route: route, scopeID: "A", isCurrent: { true }) }
        await fulfillment(of: [geocoder.started], timeout: 2)
        let second = Task { await resolver.resolve(route: route, scopeID: "A", isCurrent: { true }) }
        for _ in 0..<10 { await Task.yield() }
        geocoder.complete(.init(locality: "서울특별시"))
        let firstValue = await first.value
        let secondValue = await second.value
        XCTAssertEqual(firstValue, secondValue)
        XCTAssertEqual(firstValue, "서울특별시")
        XCTAssertEqual(geocoder.points.count, 1)
    }

    func testCancelledLookupReturnsNilAndCancelsProvider() async {
        let geocoder = SuspendedGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let route = makeRoute()
        let request = Task { await resolver.resolve(route: route, scopeID: "A", isCurrent: { true }) }
        await fulfillment(of: [geocoder.started], timeout: 2)
        request.cancel()
        let value = await request.value
        XCTAssertNil(value)
        XCTAssertEqual(geocoder.cancelCount, 1)
    }

    func testChangedAccountDropsLateResultAndDoesNotCacheIt() async {
        let geocoder = SuspendedGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let state = ScopeState()
        let route = makeRoute()
        let request = Task { await resolver.resolve(route: route, scopeID: "A", isCurrent: { state.isCurrent }) }
        await fulfillment(of: [geocoder.started], timeout: 2)
        state.isCurrent = false
        geocoder.complete(.init(locality: "서울특별시"))
        let value = await request.value
        XCTAssertNil(value)
        state.isCurrent = true
        geocoder.immediateValue = .init(locality: "용인시")
        let fresh = await resolver.resolve(route: route, scopeID: "A", isCurrent: { state.isCurrent })
        XCTAssertEqual(fresh, "용인시")
        XCTAssertEqual(geocoder.points.count, 2)
    }

    func testCancellingOneJoinedCardKeepsOtherCardLookupAlive() async {
        let geocoder = SuspendedGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let route = makeRoute()
        let first = Task { await resolver.resolve(route: route, scopeID: "A", isCurrent: { true }) }
        await fulfillment(of: [geocoder.started], timeout: 2)
        let second = Task { await resolver.resolve(route: route, scopeID: "A", isCurrent: { true }) }
        for _ in 0..<10 { await Task.yield() }
        first.cancel()
        let firstValue = await first.value
        XCTAssertNil(firstValue)
        XCTAssertEqual(geocoder.cancelCount, 0)
        geocoder.complete(.init(locality: "서울특별시"))
        let secondValue = await second.value
        XCTAssertEqual(secondValue, "서울특별시")
        XCTAssertEqual(geocoder.points.count, 1)
    }

    func testEnrichmentPersistsRegionAndAccountOutboxOnly() async throws {
        let fixture = try makeFixture()
        let geocoder = StubGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let result = await WorkoutRegionEnricher.resolveAndPersist(workoutID: fixture.record.id, context: fixture.context,
            scopeID: fixture.owner.uuidString, isCurrent: { true }, resolver: resolver)
        XCTAssertEqual(result, "서울특별시")
        XCTAssertEqual(fixture.record.locationName, result)
        let outbox = try fixture.context.fetch(FetchDescriptor<HealthCloudOutboxRecord>())
        XCTAssertEqual(outbox.count, 1)
        XCTAssertEqual(outbox.first?.kind, HealthCloudKind.workout.rawValue)
        let payload = try XCTUnwrap(outbox.first?.payload)
        XCTAssertEqual(try HealthCloudPayload.decode(payload).workout?.locationName, result)
        XCTAssertNil(fixture.record.sharingVisibilityRaw)
    }

    func testManualRegionSkipsLookupAndRemainsUnchanged() async throws {
        let fixture = try makeFixture()
        fixture.record.locationName = "내가 입력한 지역"
        try fixture.context.save()
        let geocoder = StubGeocoder()
        let result = await WorkoutRegionEnricher.resolveAndPersist(workoutID: fixture.record.id, context: fixture.context,
            scopeID: fixture.owner.uuidString, isCurrent: { true }, resolver: WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0))
        XCTAssertEqual(result, "내가 입력한 지역")
        XCTAssertEqual(geocoder.points.count, 0)
    }

    func testWrongAccountScopeCannotReadOrEnrichWorkout() async throws {
        let fixture = try makeFixture()
        fixture.record.locationName = "A의 기존 지역"
        let geocoder = StubGeocoder()
        let result = await WorkoutRegionEnricher.resolveAndPersist(workoutID: fixture.record.id, context: fixture.context,
            scopeID: UUID().uuidString, isCurrent: { true }, resolver: WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0))
        XCTAssertNil(result)
        XCTAssertEqual(geocoder.points.count, 0)
        XCTAssertEqual(fixture.record.locationName, "A의 기존 지역")
    }

    func testRetiredAccountStopsBeforeLookup() async throws {
        let fixture = try makeFixture()
        HealthCloudJournal.retire(fixture.container)
        let geocoder = StubGeocoder()
        let result = await WorkoutRegionEnricher.resolveAndPersist(workoutID: fixture.record.id, context: fixture.context,
            scopeID: fixture.owner.uuidString, isCurrent: { true }, resolver: WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0))
        XCTAssertNil(result)
        XCTAssertEqual(geocoder.points.count, 0)
        XCTAssertNil(fixture.record.locationName)
    }

    func testManualEditDuringLookupWins() async throws {
        let fixture = try makeFixture()
        let geocoder = SuspendedGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let id = fixture.record.id
        let request = Task { await WorkoutRegionEnricher.resolveAndPersist(workoutID: id, context: fixture.context,
            scopeID: fixture.owner.uuidString, isCurrent: { true }, resolver: resolver) }
        await fulfillment(of: [geocoder.started], timeout: 2)
        fixture.record.locationName = "직접 수정한 지역"
        try fixture.context.save()
        geocoder.complete(.init(locality: "서울특별시"))
        let result = await request.value
        XCTAssertEqual(result, "직접 수정한 지역")
        XCTAssertEqual(fixture.record.locationName, result)
    }

    func testAccountChangePreventsLatePersist() async throws {
        let fixture = try makeFixture()
        let geocoder = SuspendedGeocoder()
        let state = ScopeState()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let id = fixture.record.id
        let request = Task { await WorkoutRegionEnricher.resolveAndPersist(workoutID: id, context: fixture.context,
            scopeID: fixture.owner.uuidString, isCurrent: { state.isCurrent }, resolver: resolver) }
        await fulfillment(of: [geocoder.started], timeout: 2)
        state.isCurrent = false
        geocoder.complete(.init(locality: "서울특별시"))
        let result = await request.value
        XCTAssertNil(result)
        XCTAssertNil(fixture.record.locationName)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<HealthCloudOutboxRecord>()).isEmpty)
    }

    func testDeletedWorkoutIsNotResurrectedByLateLookup() async throws {
        let fixture = try makeFixture()
        let geocoder = SuspendedGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let id = fixture.record.id
        let request = Task { await WorkoutRegionEnricher.resolveAndPersist(workoutID: id, context: fixture.context,
            scopeID: fixture.owner.uuidString, isCurrent: { true }, resolver: resolver) }
        await fulfillment(of: [geocoder.started], timeout: 2)
        fixture.context.delete(fixture.record)
        try fixture.context.save()
        geocoder.complete(.init(locality: "서울특별시"))
        let result = await request.value
        XCTAssertNil(result)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).isEmpty)
    }

    func testChangedRouteDiscardsOldRegion() async throws {
        let fixture = try makeFixture()
        let geocoder = SuspendedGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let id = fixture.record.id
        let request = Task { await WorkoutRegionEnricher.resolveAndPersist(workoutID: id, context: fixture.context,
            scopeID: fixture.owner.uuidString, isCurrent: { true }, resolver: resolver) }
        await fulfillment(of: [geocoder.started], timeout: 2)
        WorkoutRouteMapper().update(fixture.route, with: makeRoute(id: id, latitude: 38.12123), updatedAt: Date())
        try fixture.context.save()
        geocoder.complete(.init(locality: "서울특별시"))
        let result = await request.value
        XCTAssertNil(result)
        XCTAssertNil(fixture.record.locationName)
    }

    func testChangedRouteWithSameCoarsePointDiscardsOldRegion() async throws {
        let fixture = try makeFixture()
        let geocoder = SuspendedGeocoder()
        let resolver = WorkoutRegionResolver(geocoder: geocoder, minimumInterval: 0)
        let id = fixture.record.id
        let originalPoint = WorkoutRegionQueryPoint.make(route: WorkoutRouteMapper().makeRoute(from: fixture.route))
        let request = Task { await WorkoutRegionEnricher.resolveAndPersist(workoutID: id, context: fixture.context,
            scopeID: fixture.owner.uuidString, isCurrent: { true }, resolver: resolver) }
        await fulfillment(of: [geocoder.started], timeout: 2)
        let editedRoute = makeRoute(id: id, latitude: 37.12133)
        XCTAssertEqual(WorkoutRegionQueryPoint.make(route: editedRoute), originalPoint)
        WorkoutRouteMapper().update(fixture.route, with: editedRoute, updatedAt: Date())
        try fixture.context.save()
        geocoder.complete(.init(locality: "서울특별시"))
        let result = await request.value
        XCTAssertNil(result)
        XCTAssertNil(fixture.record.locationName)
    }

    private func makeRoute(id: UUID = UUID(), latitude: Double = 37.12123) -> WorkoutRoute {
        WorkoutRoute(workoutId: id, source: .soomLocal,
            coordinates: (0..<21).map { .init(latitude: latitude + Double($0) * 0.001, longitude: 127.12345) },
            totalDistanceMeters: 2200)
    }

    private func makeFixture() throws -> (container: ModelContainer, context: ModelContext, owner: UUID,
                                          record: UnifiedWorkoutRecord, route: PersistedWorkoutRoute) {
        let schema = HealthAccountStorageController.schema
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let owner = UUID()
        HealthCloudJournal.register(container, userID: owner)
        let record = UnifiedWorkoutRecord(sourceRaw: UnifiedDataSource.soomLocal.rawValue,
            workoutTypeRaw: UnifiedWorkoutType.running.rawValue, startDate: Date(), endDate: Date(),
            durationSeconds: 600, dataQualityRaw: UnifiedDataQuality.complete.rawValue)
        let route = WorkoutRouteMapper().makeRecord(from: makeRoute(id: record.id))
        container.mainContext.insert(record)
        container.mainContext.insert(route)
        try container.mainContext.save()
        return (container, container.mainContext, owner, record, route)
    }

    private final class Clock { var date = Date(timeIntervalSince1970: 1_800_000_000) }
    private final class ScopeState { var isCurrent = true }

    private final class StubGeocoder: WorkoutRegionGeocoding {
        var value: WorkoutRegionPlacemark? = .init(locality: "서울특별시")
        var points: [WorkoutRegionQueryPoint] = []
        var concurrentCalls = 0
        var maximumConcurrentCalls = 0
        func placemark(for point: WorkoutRegionQueryPoint) async throws -> WorkoutRegionPlacemark? {
            concurrentCalls += 1
            maximumConcurrentCalls = max(maximumConcurrentCalls, concurrentCalls)
            defer { concurrentCalls -= 1 }
            points.append(point)
            await Task.yield()
            return value
        }
        func cancel() {}
    }

    private final class SuspendedGeocoder: WorkoutRegionGeocoding {
        let started = XCTestExpectation(description: "geocoder started")
        var points: [WorkoutRegionQueryPoint] = []
        var cancelCount = 0
        var immediateValue: WorkoutRegionPlacemark?
        private var continuation: CheckedContinuation<WorkoutRegionPlacemark?, Never>?
        func placemark(for point: WorkoutRegionQueryPoint) async throws -> WorkoutRegionPlacemark? {
            points.append(point)
            if let immediateValue { return immediateValue }
            return await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        func complete(_ value: WorkoutRegionPlacemark?) {
            continuation?.resume(returning: value)
            continuation = nil
        }
        func cancel() { cancelCount += 1; complete(nil) }
    }
}
