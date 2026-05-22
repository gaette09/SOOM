import CoreLocation
import HealthKit
import XCTest
@testable import SOOM

final class HealthKitWorkoutRouteMapperTests: XCTestCase {
    private let mapper = HealthKitWorkoutRouteMapper()

    func testMapsCoordinatesBoundsDistanceAndTimestamps() {
        let workout = makeWorkout(distanceMeters: 1_200)
        let locations = [
            makeLocation(latitude: 37.50, longitude: 127.00, altitude: 12, timestamp: Date(timeIntervalSince1970: 10)),
            makeLocation(latitude: 37.55, longitude: 126.95, altitude: 20, timestamp: Date(timeIntervalSince1970: 20)),
            makeLocation(latitude: 37.53, longitude: 127.02, altitude: 18, timestamp: Date(timeIntervalSince1970: 30))
        ]

        let route = mapper.map(workout: workout, locations: locations, createdAt: Date(timeIntervalSince1970: 40))

        XCTAssertEqual(route?.workoutId, workout.uuid)
        XCTAssertEqual(route?.source, .appleHealthKit)
        XCTAssertEqual(route?.coordinates.count, 3)
        XCTAssertEqual(route?.coordinates.first?.timestamp, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(route?.totalDistanceMeters, 1_200)
        XCTAssertEqual(route?.bounds?.minLatitude, 37.50)
        XCTAssertEqual(route?.bounds?.maxLatitude, 37.55)
        XCTAssertEqual(route?.bounds?.minLongitude, 126.95)
        XCTAssertEqual(route?.bounds?.maxLongitude, 127.02)
    }

    func testEmptyLocationsReturnNil() {
        let route = mapper.map(workout: makeWorkout(), locations: [])

        XCTAssertNil(route)
    }

    func testCalculatesPositiveElevationGainOnly() {
        let locations = [
            makeLocation(latitude: 37.0, longitude: 127.0, altitude: 100),
            makeLocation(latitude: 37.1, longitude: 127.1, altitude: 90),
            makeLocation(latitude: 37.2, longitude: 127.2, altitude: 130),
            makeLocation(latitude: 37.3, longitude: 127.3, altitude: 125)
        ]

        let route = mapper.map(workout: makeWorkout(distanceMeters: nil), locations: locations)

        XCTAssertEqual(route?.totalElevationGain, 40)
        XCTAssertGreaterThan(route?.totalDistanceMeters ?? 0, 0)
    }

    func testNegativeElevationGainIsClampedByRouteModel() {
        let route = WorkoutRoute(
            workoutId: UUID(),
            source: .appleHealthKit,
            coordinates: [],
            totalDistanceMeters: 0,
            totalElevationGain: -10
        )

        XCTAssertEqual(route.totalElevationGain, 0)
    }

    private func makeWorkout(distanceMeters: Double? = 1_000) -> HKWorkout {
        HKWorkout(
            activityType: .cycling,
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_003_600),
            duration: 3_600,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 500),
            totalDistance: distanceMeters.map { HKQuantity(unit: .meter(), doubleValue: $0) },
            metadata: nil
        )
    }

    private func makeLocation(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        altitude: CLLocationDistance,
        timestamp: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }
}
