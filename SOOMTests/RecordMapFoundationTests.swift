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

    func testRecordMapAllowsBaseMapWhenRouteHasInsufficientCoordinates() {
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

        XCTAssertTrue(view.shouldRenderMapbox)
        XCTAssertNil(view.fallbackReason)
    }

    func testRecordMapAllowsBaseMapWithoutRouteCoordinates() {
        let route = RecordRouteRecommendation(
            title: "경로 없음",
            distanceText: "0 km",
            durationText: "0분",
            reason: "base map only",
            coordinates: []
        )

        let view = RecordMapView(
            sport: .walking,
            route: route,
            accessTokenAvailable: true
        )

        XCTAssertTrue(view.shouldRenderMapbox)
    }

    func testRecordMapReportsFallbackReasonWhenTokenIsMissing() {
        let view = RecordMapView(
            sport: .cycling,
            route: RecordLaunchPlan.mockToday.route,
            accessTokenAvailable: false
        )

        XCTAssertEqual(view.fallbackReason, "missing-or-unusable-mapbox-token")
    }

    func testMapboxAccessTokenRejectsUnusableValues() {
        XCTAssertFalse(MapboxAccessTokenAvailability.isUsableToken(nil))
        XCTAssertFalse(MapboxAccessTokenAvailability.isUsableToken(""))
        XCTAssertFalse(MapboxAccessTokenAvailability.isUsableToken("   "))
        XCTAssertFalse(MapboxAccessTokenAvailability.isUsableToken("$(MBX_ACCESS_TOKEN)"))
        XCTAssertFalse(MapboxAccessTokenAvailability.isUsableToken("placeholder"))
        XCTAssertFalse(MapboxAccessTokenAvailability.isUsableToken("replace_me"))
        XCTAssertFalse(MapboxAccessTokenAvailability.isUsableToken("your_mapbox_token"))
    }

    func testMapboxAccessTokenAcceptsPlausiblePublicToken() {
        XCTAssertTrue(MapboxAccessTokenAvailability.isUsableToken("pk.test-token-for-unit-tests"))
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

    func testLaunchCameraUsesCloseScaleTargetForRecordEntry() {
        let state = RecordMapCameraState.launch(
            currentCoordinate: nil,
            routeCoordinates: RecordLaunchPlan.mockToday.route.coordinates
        )

        XCTAssertEqual(RecordMapCameraState.launchScaleTargetMeters, 100)
        XCTAssertEqual(state.zoom, RecordMapCameraState.launchZoom)
        XCTAssertGreaterThanOrEqual(state.zoom, 15.0)
        XCTAssertLessThanOrEqual(state.zoom, 16.4)
    }

    func testLaunchCameraPrefersCurrentLocationWhenAvailable() {
        let current = RecordMapCoordinate(latitude: 37.5312, longitude: 126.9321)
        let state = RecordMapCameraState.launch(
            currentCoordinate: current,
            routeCoordinates: RecordLaunchPlan.mockToday.route.coordinates
        )

        XCTAssertEqual(state.center, current)
        XCTAssertEqual(state.zoom, RecordMapCameraState.launchZoom)
    }

    func testLocationStateDoesNotRequestPermissionOnEntry() {
        XCTAssertFalse(RecordLocationState.mockCurrent.shouldRequestPermissionOnEntry)
    }

    func testLocationButtonRequestsPermissionOnlyWhenUserTapsInNotDeterminedState() {
        let state = RecordLocationState.mockCurrent

        XCTAssertFalse(state.shouldRequestPermissionOnEntry)
        XCTAssertEqual(state.locationButtonAction, .requestPermission)
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
        XCTAssertEqual(denied.locationButtonAction, .keepFallback)
        XCTAssertNil(denied.recenterTarget)
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
        XCTAssertEqual(authorized.locationButtonAction, .updateCurrentLocation)
        XCTAssertEqual(authorized.recenterTarget, coordinate)
    }

    func testAuthorizationStatusMapping() {
        XCTAssertEqual(RecordLocationAuthorizationState(.authorizedWhenInUse), .authorized)
        XCTAssertEqual(RecordLocationAuthorizationState(.denied), .denied)
        XCTAssertEqual(RecordLocationAuthorizationState(.notDetermined), .notDetermined)
    }

    func testMockHanRiverRouteLooksLikeNaturalRiverPath() {
        let route = RecordLaunchPlan.mockToday.route
        let longitudes = route.coordinates.map(\.longitude)
        let longitudeSteps = zip(longitudes, longitudes.dropFirst()).map { $1 - $0 }

        XCTAssertEqual(route.distanceText, "9.2 km")
        XCTAssertGreaterThanOrEqual(route.coordinates.count, 8)
        XCTAssertTrue(longitudeSteps.allSatisfy { $0 > 0 })
        XCTAssertLessThan((route.coordinates.map(\.latitude).max() ?? 0) - (route.coordinates.map(\.latitude).min() ?? 0), 0.004)
    }

    func testReadyRadialSportAnglesStayInUpperSemicircle() {
        for angle in RecordReadyRadialLayout.sportAngles.values {
            XCTAssertTrue(RecordReadyRadialLayout.isUpperSemicircle(angleDegrees: angle))
        }
    }

    func testReadyRadialItemsAppearAboveReadyCenter() {
        let readyCenter = CGPoint(x: 180, y: 220)
        let items = RecordReadyRadialLayout.items(center: readyCenter)

        XCTAssertEqual(items.count, RecordSportMode.allCases.count)
        XCTAssertTrue(items.allSatisfy { RecordReadyRadialLayout.isAboveReadyCenter(item: $0, readyCenter: readyCenter) })
    }

    func testReadyTouchDownRevealsIconsFromReadyCenter() {
        let readyCenter = CGPoint(x: 180, y: 220)
        let items = RecordReadyRadialLayout.items(center: readyCenter)

        XCTAssertEqual(RecordReadyRadialLayout.touchRevealMinimumDistance, 0)
        XCTAssertEqual(RecordReadyRadialLayout.sportIconInitialScale, 0.30)
        XCTAssertEqual(RecordReadyRadialLayout.sportIconFinalScale, 1.0)
        XCTAssertEqual(RecordReadyRadialLayout.displayCenter(for: items[0], readyCenter: readyCenter, isRevealed: false), readyCenter)
        XCTAssertEqual(RecordReadyRadialLayout.displayCenter(for: items[0], readyCenter: readyCenter, isRevealed: true), items[0].center)
    }

    func testReadySportIconRevealUsesStaggerAndHoverScale() {
        XCTAssertEqual(RecordReadyRadialLayout.revealDelays[.cycling], 0.00)
        XCTAssertEqual(RecordReadyRadialLayout.revealDelays[.running], 0.05)
        XCTAssertEqual(RecordReadyRadialLayout.revealDelays[.walking], 0.10)
        XCTAssertGreaterThanOrEqual(RecordReadyRadialLayout.hoveredScale, 1.12)
        XCTAssertLessThanOrEqual(RecordReadyRadialLayout.hoveredScale, 1.16)
    }

    func testReadyRadialHoverSelectionUsesUpperSportTargets() {
        let readyCenter = CGPoint(x: 180, y: 220)
        let items = RecordReadyRadialLayout.items(center: readyCenter)

        for item in items {
            XCTAssertEqual(
                RecordReadyRadialLayout.hoveredSport(at: item.center, readyCenter: readyCenter),
                item.sport
            )
        }
    }

    func testReadyRadialInteractionHapticEvents() {
        XCTAssertEqual(RecordReadyRadialInteraction.begin(), [.longPressStarted, .menuRevealed])
        XCTAssertEqual(RecordReadyRadialInteraction.hoverEvents(previous: .cycling, next: .running), [.hoverChanged])
        XCTAssertEqual(RecordReadyRadialInteraction.hoverEvents(previous: .cycling, next: .cycling), [])
        XCTAssertEqual(RecordReadyRadialInteraction.release(hoveredSport: .walking), [.releaseConfirmed])
        XCTAssertEqual(RecordReadyRadialInteraction.release(hoveredSport: nil), [.releaseCancelled])
    }

    func testCurrentLocationPulseOnlyRunsForActualLocationWhenMotionAllowed() {
        XCTAssertTrue(
            RecordCurrentLocationMarkerStyle.isPulseEnabled(
                canShowUserLocation: true,
                reduceMotionEnabled: false
            )
        )
        XCTAssertFalse(
            RecordCurrentLocationMarkerStyle.isPulseEnabled(
                canShowUserLocation: false,
                reduceMotionEnabled: false
            )
        )
        XCTAssertFalse(
            RecordCurrentLocationMarkerStyle.isPulseEnabled(
                canShowUserLocation: true,
                reduceMotionEnabled: true
            )
        )
    }

    func testCurrentLocationPulseExpandsAndFades() {
        XCTAssertGreaterThanOrEqual(RecordCurrentLocationMarkerStyle.dotRadius * 2, 16)
        XCTAssertLessThanOrEqual(RecordCurrentLocationMarkerStyle.dotRadius * 2, 18)
        XCTAssertGreaterThanOrEqual(RecordCurrentLocationMarkerStyle.staticHaloRadius * 2, 26)
        XCTAssertLessThanOrEqual(RecordCurrentLocationMarkerStyle.staticHaloRadius * 2, 30)
        XCTAssertLessThanOrEqual(RecordCurrentLocationMarkerStyle.pulseEndRadius * 2, 52)
        XCTAssertLessThanOrEqual(RecordCurrentLocationMarkerStyle.pulseStartOpacity, 0.14)
        XCTAssertEqual(
            RecordCurrentLocationMarkerStyle.pulseRadius(progress: 0),
            RecordCurrentLocationMarkerStyle.pulseStartRadius
        )
        XCTAssertEqual(
            RecordCurrentLocationMarkerStyle.pulseRadius(progress: 1),
            RecordCurrentLocationMarkerStyle.pulseEndRadius
        )
        XCTAssertGreaterThan(
            RecordCurrentLocationMarkerStyle.pulseOpacity(progress: 0),
            RecordCurrentLocationMarkerStyle.pulseOpacity(progress: 1)
        )
        XCTAssertEqual(RecordCurrentLocationMarkerStyle.pulseOpacity(progress: 1), 0)
    }

    func testCurrentLocationMarkerIsCenterAnchored() {
        XCTAssertEqual(RecordCurrentLocationMarkerStyle.anchorOffset.width, 0)
        XCTAssertEqual(RecordCurrentLocationMarkerStyle.anchorOffset.height, 0)
        XCTAssertEqual(
            RecordCurrentLocationMarkerStyle.pulseRadius(progress: 0.5),
            RecordCurrentLocationMarkerStyle.pulseStartRadius
                + (RecordCurrentLocationMarkerStyle.pulseEndRadius - RecordCurrentLocationMarkerStyle.pulseStartRadius) * 0.5
        )
    }
}
