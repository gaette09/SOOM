import XCTest
@testable import SOOM

final class WorkoutDetailRouteContextProviderTests: XCTestCase {
    func testReturnsPersistedRouteWhenRouteExists() async {
        let workoutId = UUID()
        let route = makeRoute(workoutId: workoutId)
        let provider = WorkoutDetailRouteContextProvider(
            store: FakeWorkoutRoutePersistenceStore(routes: [route])
        )

        let result = await provider.route(for: workoutId)

        XCTAssertEqual(result?.workoutId, workoutId)
        XCTAssertEqual(result?.totalElevationGain, route.totalElevationGain)
    }

    func testReturnsNilWhenRouteDoesNotExist() async {
        let provider = WorkoutDetailRouteContextProvider(
            store: FakeWorkoutRoutePersistenceStore(routes: [])
        )

        let result = await provider.route(for: UUID())

        XCTAssertNil(result)
    }

    func testReturnsNilWhenStoreFails() async {
        let provider = WorkoutDetailRouteContextProvider(
            store: FakeWorkoutRoutePersistenceStore(error: SampleError.storeFailed)
        )

        let result = await provider.route(for: UUID())

        XCTAssertNil(result)
    }

    func testRouteCanDriveClimbInsightOverSummaryElevation() async {
        let workoutId = UUID()
        let input = WorkoutGrowthInput(
            id: workoutId,
            source: .appleHealthKit,
            workoutType: .cycling,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            durationMinutes: 70,
            distanceKm: 30,
            averagePaceText: nil,
            averageSpeedKmh: 25,
            averageHeartRate: nil,
            elevationGainMeters: 20,
            activeEnergyKcal: nil
        )
        let route = makeRoute(
            workoutId: workoutId,
            distance: 30_000,
            elevationGain: 360
        )

        let insight = ClimbInsightBuilder().build(current: input, route: route)

        XCTAssertEqual(insight.climbType, .steadyClimb)
        XCTAssertTrue(insight.metricRows.contains { $0.title == "상승고도" && $0.valueText == "360m" })
    }

    func testDoesNotUseRecoveryCalculator() async {
        let workoutId = UUID()
        let provider = WorkoutDetailRouteContextProvider(
            store: FakeWorkoutRoutePersistenceStore(routes: [makeRoute(workoutId: workoutId)])
        )

        let result = await provider.route(for: workoutId)

        XCTAssertNotNil(result)
    }

    private func makeRoute(
        workoutId: UUID,
        distance: Double = 12_000,
        elevationGain: Double? = 180
    ) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.500, longitude: 127.000, altitude: 20),
                WorkoutRouteCoordinate(latitude: 37.510, longitude: 127.010, altitude: 120)
            ],
            totalDistanceMeters: distance,
            totalElevationGain: elevationGain
        )
    }
}

private enum SampleError: Error {
    case storeFailed
}

private final class FakeWorkoutRoutePersistenceStore: WorkoutRoutePersistenceStoring {
    private let routesByWorkoutId: [UUID: WorkoutRoute]
    private let error: Error?

    init(routes: [WorkoutRoute] = [], error: Error? = nil) {
        self.routesByWorkoutId = Dictionary(uniqueKeysWithValues: routes.map { ($0.workoutId, $0) })
        self.error = error
    }

    func saveRoute(_ route: WorkoutRoute) async throws {}

    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute? {
        if let error { throw error }
        return routesByWorkoutId[workoutId]
    }

    func fetchRoutes(workoutIds: [UUID]) async throws -> [WorkoutRoute] {
        if let error { throw error }
        return workoutIds.compactMap { routesByWorkoutId[$0] }
    }

    func deleteRoute(workoutId: UUID) async throws {}
}
