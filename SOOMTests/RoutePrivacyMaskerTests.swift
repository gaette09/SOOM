import XCTest
@testable import SOOM

final class RoutePrivacyMaskerTests: XCTestCase {
    private let masker = RoutePrivacyMasker()

    func testStartMaskingRemovesCoordinatesNearStart() {
        let masked = masker.mask(
            route: sampleRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .startOnly, distanceMeters: 200)
        )

        XCTAssertEqual(masked.coordinates.first?.latitude, coordinate(atMeters: 300).latitude)
        XCTAssertEqual(masked.coordinates.count, 3)
    }

    func testEndMaskingRemovesCoordinatesNearEnd() {
        let masked = masker.mask(
            route: sampleRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .endOnly, distanceMeters: 200)
        )

        XCTAssertEqual(masked.coordinates.last?.latitude, coordinate(atMeters: 600).latitude)
        XCTAssertEqual(masked.coordinates.count, 4)
    }

    func testStartAndEndMaskingRemovesBothEnds() {
        let masked = masker.mask(
            route: sampleRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .startAndEnd, distanceMeters: 200)
        )

        XCTAssertEqual(masked.coordinates.map(\.latitude), [
            coordinate(atMeters: 300).latitude,
            coordinate(atMeters: 600).latitude
        ])
    }

    func testNonePolicyReturnsSameCoordinates() {
        let route = sampleRoute

        let masked = masker.mask(route: route, policy: .none)

        XCTAssertEqual(masked.coordinates, route.coordinates)
        XCTAssertEqual(masked.bounds, route.bounds)
    }

    func testShortRouteFallsBackToEmptyDerivedRoute() {
        let masked = masker.mask(
            route: shortRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .startAndEnd, distanceMeters: 200)
        )

        XCTAssertTrue(masked.coordinates.isEmpty)
        XCTAssertNil(masked.bounds)
        XCTAssertEqual(masked.totalDistanceMeters, 0)
    }

    func testOriginalRouteIsNotMutated() {
        let route = sampleRoute
        let originalCoordinates = route.coordinates

        _ = masker.mask(
            route: route,
            policy: RoutePrivacyMaskingPolicy(mode: .startAndEnd, distanceMeters: 200)
        )

        XCTAssertEqual(route.coordinates, originalCoordinates)
    }

    func testMaskedRouteBoundsAreRecalculated() {
        let masked = masker.mask(
            route: sampleRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .startAndEnd, distanceMeters: 200)
        )

        XCTAssertEqual(masked.bounds?.minLatitude, coordinate(atMeters: 300).latitude)
        XCTAssertEqual(masked.bounds?.maxLatitude, coordinate(atMeters: 600).latitude)
    }

    private var sampleRoute: WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            source: .appleHealthKit,
            coordinates: [
                coordinate(atMeters: 0),
                coordinate(atMeters: 100),
                coordinate(atMeters: 300),
                coordinate(atMeters: 600),
                coordinate(atMeters: 800)
            ],
            totalDistanceMeters: 800
        )
    }

    private var shortRoute: WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(),
            source: .appleHealthKit,
            coordinates: [
                coordinate(atMeters: 0),
                coordinate(atMeters: 100)
            ],
            totalDistanceMeters: 100
        )
    }

    private func coordinate(atMeters meters: Double) -> WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(
            latitude: 37.0 + meters / 111_000,
            longitude: 127.0
        )
    }
}
