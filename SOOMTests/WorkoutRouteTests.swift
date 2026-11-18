import CoreLocation
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

    func testPlaybackFinishFlagAppearsOnlyAfterArrival() {
        XCTAssertTrue(WorkoutRoutePlayback.showsFinishMarker(progress: nil))
        XCTAssertFalse(WorkoutRoutePlayback.showsFinishMarker(progress: 0))
        XCTAssertFalse(WorkoutRoutePlayback.showsFinishMarker(progress: 0.5))
        XCTAssertFalse(WorkoutRoutePlayback.showsFinishMarker(progress: 0.999))
        XCTAssertTrue(WorkoutRoutePlayback.showsFinishMarker(progress: 1))
    }

    func testPlaybackRevealsDistanceWithoutJoiningSeparateRouteSegments() {
        let first = [CLLocationCoordinate2D(latitude: 37, longitude: 127),
                     CLLocationCoordinate2D(latitude: 37, longitude: 127.01)]
        let second = [CLLocationCoordinate2D(latitude: 37, longitude: 128),
                      CLLocationCoordinate2D(latitude: 37, longitude: 128.01)]
        let start = WorkoutRoutePlayback.frame(segments: [first, second], progress: 0)
        XCTAssertTrue(start.segments.isEmpty)
        XCTAssertEqual(start.position?.longitude, 127)

        let midway = WorkoutRoutePlayback.frame(segments: [first, second], progress: 0.75)
        XCTAssertEqual(midway.segments.count, 2)
        XCTAssertEqual(midway.segments[0].last?.longitude, 127.01)
        XCTAssertEqual(midway.segments[1].first?.longitude, 128)
        XCTAssertEqual(midway.position?.longitude ?? 0, 128.005, accuracy: 0.0001)

        let end = WorkoutRoutePlayback.frame(segments: [first, second], progress: 1)
        XCTAssertEqual(end.position?.longitude, 128.01)
        XCTAssertEqual(end.segments.map(\.count), [2, 2])
    }
}
