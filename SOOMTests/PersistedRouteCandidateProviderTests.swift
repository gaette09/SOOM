import XCTest
@testable import SOOM

final class PersistedRouteCandidateProviderTests: XCTestCase {
    func testFetchesCurrentAndCandidateRoutes() async throws {
        let currentId = UUID()
        let candidateId = UUID()
        let currentRoute = makeRoute(workoutId: currentId, distance: 10_000)
        let candidateRoute = makeRoute(workoutId: candidateId, distance: 10_100, offset: 0.0002)
        let store = FakeRoutePersistenceStore(routes: [currentRoute, candidateRoute])
        let provider = PersistedRouteCandidateProvider(store: store)

        let result = try await provider.routes(
            currentWorkoutId: currentId,
            candidateWorkoutIds: [candidateId]
        )

        XCTAssertEqual(result.currentRoute?.workoutId, currentId)
        XCTAssertEqual(result.candidateRoutesByWorkoutId[candidateId]?.workoutId, candidateId)
        XCTAssertNotNil(result.currentCourseIdentity)
    }

    func testMissingRoutesReturnsEmptyCandidateContext() async throws {
        let provider = PersistedRouteCandidateProvider(store: FakeRoutePersistenceStore(routes: []))

        let result = try await provider.routes(
            currentWorkoutId: UUID(),
            candidateWorkoutIds: [UUID()]
        )

        XCTAssertNil(result.currentRoute)
        XCTAssertTrue(result.candidateRoutesByWorkoutId.isEmpty)
        XCTAssertNil(result.currentCourseIdentity)
    }

    func testCandidateRoutesPreserveOnlyExistingRoutes() async throws {
        let existingId = UUID()
        let missingId = UUID()
        let route = makeRoute(workoutId: existingId, distance: 8_000)
        let provider = PersistedRouteCandidateProvider(store: FakeRoutePersistenceStore(routes: [route]))

        let result = try await provider.routes(
            currentWorkoutId: UUID(),
            candidateWorkoutIds: [existingId, missingId]
        )

        XCTAssertEqual(result.candidateRoutesByWorkoutId.keys.sorted { $0.uuidString < $1.uuidString }, [existingId])
    }

    func testProviderDoesNotUseRecoveryCalculator() async throws {
        let currentId = UUID()
        let provider = PersistedRouteCandidateProvider(
            store: FakeRoutePersistenceStore(routes: [makeRoute(workoutId: currentId, distance: 5_000)])
        )

        let result = try await provider.routes(currentWorkoutId: currentId, candidateWorkoutIds: [])

        XCTAssertNotNil(result.currentRoute)
    }

    private func makeRoute(workoutId: UUID, distance: Double, offset: Double = 0) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.5000 + offset, longitude: 127.0000 + offset),
                WorkoutRouteCoordinate(latitude: 37.5050 + offset, longitude: 127.0060 + offset)
            ],
            totalDistanceMeters: distance
        )
    }
}

private final class FakeRoutePersistenceStore: WorkoutRoutePersistenceStoring {
    private let routesByWorkoutId: [UUID: WorkoutRoute]

    init(routes: [WorkoutRoute]) {
        self.routesByWorkoutId = Dictionary(uniqueKeysWithValues: routes.map { ($0.workoutId, $0) })
    }

    func saveRoute(_ route: WorkoutRoute) async throws {}

    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute? {
        routesByWorkoutId[workoutId]
    }

    func fetchRoutes(workoutIds: [UUID]) async throws -> [WorkoutRoute] {
        workoutIds.compactMap { routesByWorkoutId[$0] }
    }

    func deleteRoute(workoutId: UUID) async throws {}
}
