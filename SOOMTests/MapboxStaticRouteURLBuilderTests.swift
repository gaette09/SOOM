import XCTest
@testable import SOOM

final class MapboxStaticRouteURLBuilderTests: XCTestCase {
    func testRouteCoordinatesBuildValidStaticImagesURL() {
        let builder = MapboxStaticRouteURLBuilder(accessToken: "test-token")

        let url = builder.buildURL(for: sampleRoute, width: 320, height: 400)

        let urlString = url?.absoluteString ?? ""
        XCTAssertTrue(urlString.hasPrefix("https://api.mapbox.com/styles/v1/\(SOOMMapboxConfiguration.staticImagesStyleID)/static/geojson("))
        XCTAssertTrue(urlString.contains("LineString"))
        XCTAssertTrue(urlString.contains("320x400@2x"))
        XCTAssertTrue(urlString.contains("padding=64"))
        XCTAssertTrue(urlString.contains("access_token=test-token"))
        XCTAssertTrue(urlString.contains("%237541EE"))
        XCTAssertTrue(urlString.contains("stroke-width"))
    }

    func testCustomStyleAndSizeAreReflected() {
        let builder = MapboxStaticRouteURLBuilder(accessToken: "test-token")

        let url = builder.buildURL(for: sampleRoute, width: 500, height: 625, styleID: "mapbox/light-v11")

        let urlString = url?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("/mapbox/light-v11/static/"))
        XCTAssertTrue(urlString.contains("500x625@2x"))
        XCTAssertTrue(urlString.contains("padding=100"))
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


extension MapboxStaticRouteURLBuilderTests {
    func testLongRouteFitsAPIURLLimitWithoutJoiningPauseSegments() {
        let points = (0..<6000).map { index in
            WorkoutRouteCoordinate(latitude: 37.5 + Double(index) * 0.000001,
                                   longitude: 127 + sin(Double(index) / 300) * 0.01,
                                   segmentIndex: index < 3000 ? 0 : 1)
        }
        let route = WorkoutRoute(workoutId: UUID(), source: .soomLocal, coordinates: points, totalDistanceMeters: 10000)
        let url = MapboxStaticRouteURLBuilder(accessToken: "synthetic-token").buildURL(for: route)
        XCTAssertNotNil(url)
        XCTAssertLessThanOrEqual(url?.absoluteString.utf8.count ?? Int.max, 8192)
        XCTAssertTrue(url?.absoluteString.contains("MultiLineString") == true)
    }

    func testInvalidCoordinatesAndOversizedImagesDoNotMakeARequest() {
        let route = WorkoutRoute(workoutId: UUID(), source: .soomLocal,
            coordinates: [.init(latitude: .nan, longitude: 127), .init(latitude: 37, longitude: 127)], totalDistanceMeters: 10)
        XCTAssertNil(MapboxStaticRouteURLBuilder(accessToken: "synthetic").buildURL(for: route))
        XCTAssertNil(MapboxStaticRouteURLBuilder(accessToken: "synthetic").buildURL(for: sampleRoute, width: 1281))
    }
    func testPauseSegmentsProduceSeparateLinesInsteadOfAnInventedConnector() {
        let route = WorkoutRoute(workoutId: UUID(), source: .soomLocal, coordinates: [
            .init(latitude: 37.5, longitude: 127, segmentIndex: 0),
            .init(latitude: 37.5001, longitude: 127, segmentIndex: 0),
            .init(latitude: 37.6, longitude: 127, segmentIndex: 1),
            .init(latitude: 37.6001, longitude: 127, segmentIndex: 1)
        ], totalDistanceMeters: 22)
        let result = MapboxStaticRouteURLBuilder(accessToken: "test-token").buildURL(for: route)
        XCTAssertTrue(result?.absoluteString.contains("MultiLineString") == true)
        let isolated = WorkoutRoute(workoutId: UUID(), source: .soomLocal, coordinates: [
            .init(latitude: 37.5, longitude: 127, segmentIndex: 0),
            .init(latitude: 37.6, longitude: 127, segmentIndex: 1)
        ], totalDistanceMeters: 0)
        XCTAssertNil(MapboxStaticRouteURLBuilder(accessToken: "test-token").buildURL(for: isolated))
    }
}
