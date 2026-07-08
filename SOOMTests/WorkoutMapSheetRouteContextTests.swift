import XCTest
@testable import SOOM

final class WorkoutMapSheetRouteContextTests: XCTestCase {
    func testHealthKitImportedRouteOverrideDrivesMapSheetRouteWhenLegacyWorkoutHasNoRoute() {
        let workoutID = UUID(uuidString: "81818181-8181-8181-8181-818181818181")!
        let workout = makeWorkout(id: workoutID, route: [])
        let importedRoute = makeRoute(workoutId: workoutID, source: .appleHealthKit)

        let route = WorkoutMapSheetRouteContext.route(for: workout, override: importedRoute)

        XCTAssertEqual(route?.workoutId, workoutID)
        XCTAssertEqual(route?.source, .appleHealthKit)
        XCTAssertEqual(route?.coordinates, importedRoute.coordinates)
        XCTAssertEqual(route?.totalDistanceMeters, importedRoute.totalDistanceMeters)
    }

    func testNoRouteWorkoutKeepsMapSheetFallbackRouteNil() {
        let workout = makeWorkout(route: [])

        let route = WorkoutMapSheetRouteContext.route(for: workout, override: nil)
        let coordinates = WorkoutMapSheetRouteContext.coordinates(for: workout, override: nil)

        XCTAssertNil(route)
        XCTAssertTrue(coordinates.isEmpty)
    }

    func testRecordRouteBackedWorkoutStillUsesLegacyWorkoutRouteWithoutOverride() {
        let workoutID = UUID(uuidString: "82828282-8282-8282-8282-828282828282")!
        let workout = makeWorkout(
            id: workoutID,
            distanceMeters: 8_400,
            elevationGain: 120,
            route: [
                RoutePoint(latitude: 37.500, longitude: 127.000),
                RoutePoint(latitude: 37.510, longitude: 127.010)
            ]
        )

        let route = WorkoutMapSheetRouteContext.route(for: workout, override: nil)

        XCTAssertEqual(route?.workoutId, workoutID)
        XCTAssertEqual(route?.source, .soomLocal)
        XCTAssertEqual(route?.coordinates.count, 2)
        XCTAssertEqual(route?.totalDistanceMeters, 8_400)
        XCTAssertEqual(route?.totalElevationGain, 120)
    }

    func testInvalidRouteOverrideFallsBackToRecordRouteWhenAvailable() {
        let workout = makeWorkout(
            route: [
                RoutePoint(latitude: 37.500, longitude: 127.000),
                RoutePoint(latitude: 37.510, longitude: 127.010)
            ]
        )
        let invalidOverride = WorkoutRoute(
            workoutId: workout.id,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.520, longitude: 127.020)
            ],
            totalDistanceMeters: 0
        )

        let route = WorkoutMapSheetRouteContext.route(for: workout, override: invalidOverride)

        XCTAssertEqual(route?.source, .soomLocal)
        XCTAssertEqual(route?.coordinates.count, 2)
    }

    private func makeWorkout(
        id: UUID = UUID(),
        distanceMeters: Double = 10_000,
        elevationGain: Int = 0,
        route: [RoutePoint]
    ) -> Workout {
        Workout(
            id: id,
            sport: .bike,
            title: "Apple Health 사이클",
            date: Date(timeIntervalSince1970: 1_800_000_000),
            distanceMeters: distanceMeters,
            duration: 3_600,
            activeCalories: 500,
            avgHeartRate: 0,
            maxHeartRate: 0,
            avgPower: nil,
            elevationGain: elevationGain,
            cadence: nil,
            effort: 2,
            source: "Apple Health",
            route: route,
            splits: [],
            samples: [],
            zones: [],
            achievements: [],
            aiSummary: ""
        )
    }

    private func makeRoute(
        workoutId: UUID,
        source: UnifiedDataSource
    ) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workoutId,
            source: source,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.500, longitude: 127.000),
                WorkoutRouteCoordinate(latitude: 37.510, longitude: 127.010)
            ],
            totalDistanceMeters: 10_000,
            totalElevationGain: 180
        )
    }
}
