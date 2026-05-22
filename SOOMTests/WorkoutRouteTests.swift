import XCTest
@testable import SOOM

final class WorkoutRouteTests: XCTestCase {
    func testRouteCoordinateAndBoundsAreCreated() {
        let workoutId = UUID()
        let coordinates = [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, altitude: 30),
            WorkoutRouteCoordinate(latitude: 37.7, longitude: 126.8, altitude: 80)
        ]

        let route = WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: coordinates,
            totalDistanceMeters: 12_300,
            totalElevationGain: 220
        )

        XCTAssertEqual(route.workoutId, workoutId)
        XCTAssertEqual(route.coordinates.count, 2)
        XCTAssertEqual(route.totalDistanceMeters, 12_300)
        XCTAssertEqual(route.totalElevationGain, 220)
        XCTAssertEqual(route.bounds?.minLatitude, 37.5)
        XCTAssertEqual(route.bounds?.maxLatitude, 37.7)
        XCTAssertEqual(route.bounds?.minLongitude, 126.8)
        XCTAssertEqual(route.bounds?.maxLongitude, 127.0)
    }

    func testRouteClampsNegativeDistanceAndElevation() {
        let route = WorkoutRoute(
            workoutId: UUID(),
            source: .soomLocal,
            coordinates: [],
            totalDistanceMeters: -10,
            totalElevationGain: -20
        )

        XCTAssertEqual(route.totalDistanceMeters, 0)
        XCTAssertEqual(route.totalElevationGain, 0)
        XCTAssertNil(route.bounds)
    }
}
