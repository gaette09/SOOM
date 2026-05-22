import XCTest
@testable import SOOM

final class StaticRoutePreviewBuilderTests: XCTestCase {
    func testRouteBuildsStaticPreviewWithImageURLAndBounds() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )

        let preview = builder.build(route: sampleRoute, workoutType: .running, width: 320, height: 400)

        XCTAssertTrue(preview.routeExists)
        XCTAssertNotNil(preview.imageURL)
        XCTAssertNotNil(preview.bounds)
        XCTAssertEqual(preview.fallbackStyle, .running)
    }

    func testNilRouteReturnsSportFallback() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )

        let preview = builder.build(route: nil, workoutType: .cycling)

        XCTAssertFalse(preview.routeExists)
        XCTAssertNil(preview.imageURL)
        XCTAssertNil(preview.bounds)
        XCTAssertEqual(preview.fallbackStyle, .cycling)
    }

    func testEmptyRouteReturnsFallbackWithoutImageURL() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )
        let route = WorkoutRoute(
            workoutId: UUID(),
            source: .appleHealthKit,
            coordinates: [],
            totalDistanceMeters: 0
        )

        let preview = builder.build(route: route, workoutType: .walking)

        XCTAssertFalse(preview.routeExists)
        XCTAssertNil(preview.imageURL)
        XCTAssertEqual(preview.fallbackStyle, .walking)
    }

    func testRouteWithoutTokenKeepsRouteExistsAndUsesFallbackVisual() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: nil)
        )

        let preview = builder.build(route: sampleRoute, workoutType: .cycling)

        XCTAssertTrue(preview.routeExists)
        XCTAssertNil(preview.imageURL)
        XCTAssertEqual(preview.fallbackStyle, .cycling)
    }

    private var sampleRoute: WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.50, longitude: 127.00),
                WorkoutRouteCoordinate(latitude: 37.55, longitude: 127.05)
            ],
            totalDistanceMeters: 6_200
        )
    }
}
