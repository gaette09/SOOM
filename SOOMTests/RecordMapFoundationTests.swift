import CoreLocation
import XCTest
@testable import SOOM

final class RecordMapFoundationTests: XCTestCase {
    func testRecordMapUsesMapboxWhenTokenAndRouteAreAvailable() {
        let view = RecordMapView(
            sport: .cycling,
            route: RecordLaunchPlan.mockToday.route,
            accessTokenAvailable: true
        )

        XCTAssertTrue(view.shouldRenderMapbox)
    }

    func testRecordMapFallsBackWhenTokenIsMissing() {
        let view = RecordMapView(
            sport: .cycling,
            route: RecordLaunchPlan.mockToday.route,
            accessTokenAvailable: false
        )

        XCTAssertFalse(view.shouldRenderMapbox)
    }

    func testRecordMapFallsBackWhenRouteHasInsufficientCoordinates() {
        let route = RecordRouteRecommendation(
            title: "짧은 코스",
            distanceText: "0.4 km",
            durationText: "5분",
            reason: "테스트 route",
            coordinates: [RecordMapCoordinate(latitude: 37.52, longitude: 126.92)]
        )

        let view = RecordMapView(
            sport: .running,
            route: route,
            accessTokenAvailable: true
        )

        XCTAssertFalse(view.shouldRenderMapbox)
    }

    func testCameraStateUsesRouteCenterAndZoomEstimate() {
        let coordinates = [
            RecordMapCoordinate(latitude: 37.5200, longitude: 126.9200),
            RecordMapCoordinate(latitude: 37.5400, longitude: 126.9400)
        ]

        let state = RecordMapCameraState(routeCoordinates: coordinates)

        XCTAssertEqual(state.center.latitude, 37.5300, accuracy: 0.0001)
        XCTAssertEqual(state.center.longitude, 126.9300, accuracy: 0.0001)
        XCTAssertEqual(state.zoom, 12.9)
    }

    func testCameraStateFallsBackWithoutRouteCoordinates() {
        let state = RecordMapCameraState(routeCoordinates: [])

        XCTAssertEqual(state, .fallback)
    }

    func testLocationStateDoesNotRequestPermissionOnEntry() {
        XCTAssertFalse(RecordLocationState.mockCurrent.shouldRequestPermissionOnEntry)
    }

    func testLocationStateUsesFallbackWhenPermissionOrCoordinateIsMissing() {
        let fallback = RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271)
        let denied = RecordLocationState(
            authorization: .denied,
            coordinate: nil,
            fallbackCoordinate: fallback
        )

        XCTAssertFalse(denied.canShowUserLocation)
        XCTAssertEqual(denied.displayCoordinate, fallback)
    }

    func testLocationStateCanShowAuthorizedCoordinate() {
        let coordinate = RecordMapCoordinate(latitude: 37.5301, longitude: 126.9302)
        let fallback = RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271)
        let authorized = RecordLocationState(
            authorization: .authorized,
            coordinate: coordinate,
            fallbackCoordinate: fallback
        )

        XCTAssertTrue(authorized.canShowUserLocation)
        XCTAssertEqual(authorized.displayCoordinate, coordinate)
    }

    func testAuthorizationStatusMapping() {
        XCTAssertEqual(RecordLocationAuthorizationState(.authorizedWhenInUse), .authorized)
        XCTAssertEqual(RecordLocationAuthorizationState(.denied), .denied)
        XCTAssertEqual(RecordLocationAuthorizationState(.notDetermined), .notDetermined)
    }
}
