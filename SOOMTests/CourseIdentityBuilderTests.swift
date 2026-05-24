import XCTest
@testable import SOOM

final class CourseIdentityBuilderTests: XCTestCase {
    private let builder = CourseIdentityBuilder()

    func testStableIdentityUsesNormalizedRouteSignals() {
        let route = makeRoute(
            distance: 10_120,
            coordinates: [
                coordinate(37.5001, 127.0001),
                coordinate(37.5102, 127.0102),
                coordinate(37.5203, 127.0203)
            ]
        )

        let identity = builder.build(from: route)

        XCTAssertNotNil(identity)
        XCTAssertEqual(identity?.identityVersion, 1)
        XCTAssertEqual(identity?.source, .generated)
        XCTAssertEqual(identity?.estimatedDistance, 10_000)
        XCTAssertTrue(identity?.courseId.hasPrefix("course-v1") == true)
    }

    func testReverseDirectionKeepsSameCourseIdentity() {
        let coordinates = [
            coordinate(37.5000, 127.0000),
            coordinate(37.5100, 127.0100),
            coordinate(37.5200, 127.0200)
        ]
        let forward = makeRoute(distance: 10_000, coordinates: coordinates)
        let reverse = makeRoute(distance: 10_000, coordinates: Array(coordinates.reversed()))

        let forwardIdentity = builder.build(from: forward)
        let reverseIdentity = builder.build(from: reverse)

        XCTAssertEqual(forwardIdentity?.courseId, reverseIdentity?.courseId)
        XCTAssertNotEqual(forwardIdentity?.estimatedDirection, reverseIdentity?.estimatedDirection)
    }

    func testIdentityReturnsNilForRouteWithoutUsableDistance() {
        let route = makeRoute(distance: 0, coordinates: [coordinate(37.5, 127.0)])

        XCTAssertNil(builder.build(from: route))
    }

    private func makeRoute(
        distance: Double,
        coordinates: [WorkoutRouteCoordinate]
    ) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(),
            source: .appleHealthKit,
            coordinates: coordinates,
            totalDistanceMeters: distance,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func coordinate(_ latitude: Double, _ longitude: Double) -> WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(latitude: latitude, longitude: longitude)
    }
}
