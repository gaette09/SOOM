import XCTest
@testable import SOOM

final class MapboxStaticRouteURLBuilderTests: XCTestCase {
    func testRouteCoordinatesBuildValidStaticImagesURL() {
        let builder = MapboxStaticRouteURLBuilder(accessToken: "test-token")

        let url = builder.buildURL(for: sampleRoute, width: 320, height: 400)

        let urlString = url?.absoluteString ?? ""
        XCTAssertTrue(urlString.hasPrefix("https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/geojson("))
        XCTAssertTrue(urlString.contains("LineString"))
        XCTAssertTrue(urlString.contains("320x400@2x"))
        XCTAssertTrue(urlString.contains("access_token=test-token"))
    }

    func testCustomStyleAndSizeAreReflected() {
        let builder = MapboxStaticRouteURLBuilder(accessToken: "test-token")

        let url = builder.buildURL(for: sampleRoute, width: 500, height: 625, styleID: "mapbox/light-v11")

        let urlString = url?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("/mapbox/light-v11/static/"))
        XCTAssertTrue(urlString.contains("500x625@2x"))
    }

    func testMissingTokenDoesNotBuildURL() {
        let builder = MapboxStaticRouteURLBuilder(accessToken: nil)

        let url = builder.buildURL(for: sampleRoute)

        XCTAssertNil(url)
    }

    func testSingleCoordinateDoesNotBuildMapboxURL() {
        let builder = MapboxStaticRouteURLBuilder(accessToken: "test-token")
        let route = WorkoutRoute(
            workoutId: UUID(),
            source: .appleHealthKit,
            coordinates: [WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0)],
            totalDistanceMeters: 0
        )

        let url = builder.buildURL(for: route)

        XCTAssertNil(url)
    }

    func testBuilderDoesNotHardcodeProductionToken() {
        let builder = MapboxStaticRouteURLBuilder(accessToken: "test-token")

        let urlString = builder.buildURL(for: sampleRoute)?.absoluteString ?? ""

        XCTAssertFalse(urlString.contains("pk."))
        XCTAssertFalse(urlString.contains("sk."))
    }

    private var sampleRoute: WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.501, longitude: 127.001),
                WorkoutRouteCoordinate(latitude: 37.511, longitude: 127.011),
                WorkoutRouteCoordinate(latitude: 37.521, longitude: 127.021)
            ],
            totalDistanceMeters: 2_400
        )
    }
}
