import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class WorkoutRoutePersistenceStoreTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    func testSaveAndFetchRoute() async throws {
        let fixture = try makeFixture()
        let route = makeRoute(source: .appleHealthKit)

        try await fixture.store.saveRoute(route)
        let fetched = try await fixture.store.fetchRoute(workoutId: route.workoutId)

        XCTAssertEqual(fetched?.workoutId, route.workoutId)
        XCTAssertEqual(fetched?.source, .appleHealthKit)
        XCTAssertEqual(fetched?.coordinates.count, 2)
        XCTAssertEqual(fetched?.bounds, route.bounds)
    }

    func testSaveRouteUpsertsByWorkoutId() async throws {
        let fixture = try makeFixture()
        let workoutId = UUID()
        let first = makeRoute(workoutId: workoutId, distance: 1_000)
        let updated = makeRoute(workoutId: workoutId, distance: 1_800, elevationGain: 32)

        try await fixture.store.saveRoute(first)
        try await fixture.store.saveRoute(updated)
        let fetched = try await fixture.store.fetchRoute(workoutId: workoutId)
        let records = try fixture.container.mainContext.fetch(FetchDescriptor<PersistedWorkoutRoute>())

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(fetched?.totalDistanceMeters, 1_800)
        XCTAssertEqual(fetched?.totalElevationGain, 32)
    }

    func testFetchRoutesReturnsRequestedRoutesInInputOrder() async throws {
        let fixture = try makeFixture()
        let first = makeRoute(distance: 1_000)
        let second = makeRoute(distance: 2_000)
        let missingId = UUID()

        try await fixture.store.saveRoute(second)
        try await fixture.store.saveRoute(first)
        let fetched = try await fixture.store.fetchRoutes(workoutIds: [first.workoutId, missingId, second.workoutId])

        XCTAssertEqual(fetched.map(\.workoutId), [first.workoutId, second.workoutId])
    }

    func testDeleteRouteRemovesStoredRoute() async throws {
        let fixture = try makeFixture()
        let route = makeRoute()

        try await fixture.store.saveRoute(route)
        try await fixture.store.deleteRoute(workoutId: route.workoutId)
        let fetched = try await fixture.store.fetchRoute(workoutId: route.workoutId)

        XCTAssertNil(fetched)
    }

    func testEmptyRouteIsStoredSafely() async throws {
        let fixture = try makeFixture()
        let route = WorkoutRoute(
            workoutId: UUID(),
            source: .manual,
            coordinates: [],
            totalDistanceMeters: 0,
            totalElevationGain: nil,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        try await fixture.store.saveRoute(route)
        let fetched = try await fixture.store.fetchRoute(workoutId: route.workoutId)

        XCTAssertTrue(fetched?.coordinates.isEmpty == true)
        XCTAssertNil(fetched?.bounds)
        XCTAssertEqual(fetched?.source, .manual)
    }

    func testDoesNotUseRecoveryCalculator() async throws {
        let fixture = try makeFixture()

        try await fixture.store.saveRoute(makeRoute())
        let fetched = try await fixture.store.fetchRoutes(workoutIds: [])

        XCTAssertTrue(fetched.isEmpty)
    }

    private func makeFixture() throws -> (
        store: SwiftDataWorkoutRoutePersistenceStore,
        container: ModelContainer
    ) {
        let schema = Schema([PersistedWorkoutRoute.self])
        let configuration = ModelConfiguration(
            "WorkoutRoutePersistenceStoreTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        retainedContainers.append(container)

        return (
            SwiftDataWorkoutRoutePersistenceStore(
                modelContext: container.mainContext,
                referenceDate: { Date(timeIntervalSince1970: 2_000) }
            ),
            container
        )
    }

    private func makeRoute(
        workoutId: UUID = UUID(),
        source: UnifiedDataSource = .soomLocal,
        distance: Double = 1_200,
        elevationGain: Double? = 18
    ) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workoutId,
            source: source,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.500, longitude: 127.000, altitude: 12),
                WorkoutRouteCoordinate(latitude: 37.506, longitude: 127.006, altitude: 30)
            ],
            totalDistanceMeters: distance,
            totalElevationGain: elevationGain,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
