import XCTest
@testable import SOOM

final class StaticRoutePreviewBuilderTests: XCTestCase {
    func testRouteBuildsStaticPreviewWithImageURLAndBoundsWhenMaskingIsDisabled() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )

        let preview = builder.build(
            route: sampleRoute,
            workoutType: .running,
            width: 320,
            height: 400,
            privacyPolicy: .none
        )

        XCTAssertTrue(preview.routeExists)
        XCTAssertNotNil(preview.imageURL)
        XCTAssertNotNil(preview.bounds)
        XCTAssertEqual(preview.fallbackStyle, .running)
    }

    func testDefaultPrivacyPolicyMasksRouteBeforeBuildingPreview() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )

        let preview = builder.build(route: sampleRoute, workoutType: .running)

        XCTAssertTrue(preview.routeExists)
        XCTAssertNotNil(preview.imageURL)
        XCTAssertGreaterThan(preview.bounds?.minLatitude ?? 0, sampleRoute.bounds?.minLatitude ?? 0)
        XCTAssertLessThan(preview.bounds?.maxLatitude ?? 0, sampleRoute.bounds?.maxLatitude ?? 0)
    }

    func testPrivacyMaskingCanMakeShortRouteFallBack() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )
        let route = WorkoutRoute(
            workoutId: UUID(),
            source: .appleHealthKit,
            coordinates: [
                coordinate(atMeters: 0),
                coordinate(atMeters: 100)
            ],
            totalDistanceMeters: 100
        )

        let preview = builder.build(route: route, workoutType: .cycling)

        XCTAssertFalse(preview.routeExists)
        XCTAssertNil(preview.imageURL)
        XCTAssertNil(preview.bounds)
        XCTAssertEqual(preview.fallbackStyle, .cycling)
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
                coordinate(atMeters: 0),
                coordinate(atMeters: 100),
                coordinate(atMeters: 300),
                coordinate(atMeters: 600),
                coordinate(atMeters: 900)
            ],
            totalDistanceMeters: 900
        )
    }

    private func coordinate(atMeters meters: Double) -> WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(
            latitude: 37.50 + meters / 111_000,
            longitude: 127.00
        )
    }
}
