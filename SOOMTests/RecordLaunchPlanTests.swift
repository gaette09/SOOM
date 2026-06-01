import XCTest
@testable import SOOM

final class RecordLaunchPlanTests: XCTestCase {
    func testMockPlanStartsWithCyclingWithoutRequestingLocationPermission() {
        let plan = RecordLaunchPlan.mockToday

        XCTAssertEqual(plan.defaultSport, .cycling)
        XCTAssertTrue(plan.usesMapboxWhenConfigured)
        XCTAssertFalse(plan.requiresLocationPermissionOnEntry)
        XCTAssertGreaterThanOrEqual(plan.route.coordinates.count, 2)
    }

    func testSportStartTitlesFollowSelectedSport() {
        XCTAssertEqual(RecordSportMode.cycling.startTitle, "라이딩 시작")
        XCTAssertEqual(RecordSportMode.running.startTitle, "러닝 시작")
        XCTAssertEqual(RecordSportMode.walking.startTitle, "걷기 시작")
    }

    func testRecommendationCopyChangesBySport() {
        let recommendation = RecordLaunchPlan.mockToday.recommendation

        XCTAssertTrue(recommendation.subtitle(for: .cycling).contains("라이딩"))
        XCTAssertTrue(recommendation.subtitle(for: .running).contains("조깅"))
        XCTAssertTrue(recommendation.subtitle(for: .walking).contains("걷기"))
    }

    func testRecordLaunchPlanDoesNotUseRecoveryCalculator() {
        let plan = RecordLaunchPlan.mockToday

        XCTAssertEqual(plan.recommendation.recoveryLabel, "회복 82 · 좋음")
        XCTAssertFalse(plan.route.title.isEmpty)
    }

    func testFallbackWeatherIsUsedWithoutCoordinate() async {
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: nil,
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )

        let snapshot = await RecordWeatherResolver.snapshot(
            for: state,
            service: StubRecordWeatherService(snapshot: .liveClear),
            apiKey: "valid-weather-key"
        )

        XCTAssertTrue(snapshot.isFallback)
        XCTAssertEqual(snapshot.source, "fallback")
    }

    func testFallbackWeatherIsUsedWithoutAPIKey() async {
        let state = authorizedLocationState()

        let snapshot = await RecordWeatherResolver.snapshot(
            for: state,
            service: StubRecordWeatherService(snapshot: .liveClear),
            apiKey: nil
        )

        XCTAssertTrue(snapshot.isFallback)
        XCTAssertEqual(snapshot.source, "fallback")
    }

    func testLiveWeatherCanBeFetchedAfterUserLocationExists() async {
        let state = authorizedLocationState()

        let snapshot = await RecordWeatherResolver.snapshot(
            for: state,
            service: StubRecordWeatherService(snapshot: .liveClear),
            apiKey: "valid-weather-key"
        )

        XCTAssertFalse(snapshot.isFallback)
        XCTAssertEqual(snapshot.temperatureText, "23°")
        XCTAssertEqual(snapshot.conditionText, "맑음")
    }

    func testNetworkFailureFallsBackSafely() async {
        let state = authorizedLocationState()

        let snapshot = await RecordWeatherResolver.snapshot(
            for: state,
            service: FailingRecordWeatherService(),
            apiKey: "valid-weather-key"
        )

        XCTAssertTrue(snapshot.isFallback)
        XCTAssertEqual(snapshot.pillText, "26° · 맑음 · 바람 약함")
    }

    func testWeatherAPIKeyValidationRejectsPlaceholders() {
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey(nil))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey(""))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey("$(WEATHER_API_KEY)"))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey("placeholder"))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey("replace_me"))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey("your_openweather_key"))
        XCTAssertEqual(RecordWeatherServiceFactory.usableAPIKey("live-key"), "live-key")
    }

    func testWeatherRecommendationCopyChangesWithConditions() {
        let recommendation = RecordLaunchPlan.mockToday.recommendation

        XCTAssertTrue(recommendation.compactText(for: .cycling, weather: .liveClear).contains("맑고 바람이 약해요"))
        XCTAssertTrue(recommendation.compactText(for: .cycling, weather: .rainy).contains("비가 오면"))
        XCTAssertTrue(recommendation.compactText(for: .cycling, weather: .windy).contains("바람이 강해요"))
    }

    func testGuidanceRecommendationCopyChangesBySportAndWeather() {
        let recommendation = RecordLaunchPlan.mockToday.recommendation

        XCTAssertTrue(recommendation.guidanceText(for: .cycling, weather: .liveClear).contains("Z2 40분"))
        XCTAssertTrue(recommendation.guidanceText(for: .running, weather: .liveClear).contains("30분 조깅"))
        XCTAssertTrue(recommendation.guidanceText(for: .walking, weather: .liveClear).contains("25분 걷기"))
        XCTAssertTrue(recommendation.guidanceText(for: .cycling, weather: .rainy).contains("비가 오면"))
    }

    func testRecordRightEdgeControlsOrderWeatherRouteThenLocation() {
        XCTAssertEqual(
            RecordLaunchControl.rightEdgeOrder,
            [.weather, .routeRecommendation, .currentLocation]
        )
        XCTAssertEqual(
            RecordLaunchControl.routeRecommendation.iconName,
            "point.topleft.down.curvedto.point.bottomright.up"
        )
        XCTAssertEqual(RecordLaunchControl.currentLocation.iconName, "location.fill")
    }

    func testRecordHeaderLayoutKeepsGuidanceAboveRightControls() {
        let safeTop: CGFloat = 59

        XCTAssertTrue(RecordMapHeaderLayout.usesTopHeaderLayer)
        XCTAssertFalse(RecordMapHeaderLayout.usesMapOverlayGuidanceCard)
        XCTAssertTrue(RecordMapHeaderLayout.usesUnifiedFrameSource)
        XCTAssertEqual(RecordMapHeaderLayout.controlSize, 46)
        XCTAssertGreaterThanOrEqual(RecordMapHeaderLayout.topHeaderInsetBelowSafeArea, 8)
        XCTAssertLessThanOrEqual(RecordMapHeaderLayout.topHeaderInsetBelowSafeArea, 14)
        XCTAssertGreaterThanOrEqual(RecordMapHeaderLayout.guidanceHeight, 76)
        XCTAssertLessThanOrEqual(RecordMapHeaderLayout.guidanceHeight, 82)
        XCTAssertGreaterThanOrEqual(RecordMapHeaderLayout.guidanceHorizontalInset, 34)
        XCTAssertLessThanOrEqual(RecordMapHeaderLayout.guidanceHorizontalInset, 38)
        XCTAssertEqual(RecordMapHeaderLayout.guidanceCornerRadius, 22)
        XCTAssertGreaterThanOrEqual(RecordMapHeaderLayout.maxBodyLineCount, 1)
        XCTAssertLessThanOrEqual(RecordMapHeaderLayout.maxBodyLineCount, 2)
        XCTAssertGreaterThanOrEqual(
            RecordMapHeaderLayout.rightControlsTopY(safeAreaTop: safeTop),
            RecordMapHeaderLayout.guidanceBottomY(safeAreaTop: safeTop) + 10
        )
        XCTAssertLessThanOrEqual(
            RecordMapHeaderLayout.rightControlsTopY(safeAreaTop: safeTop),
            RecordMapHeaderLayout.guidanceBottomY(safeAreaTop: safeTop) + 14
        )
    }

    func testRecordHeaderHardPositionKeepsBannerAboveBackAndControls() {
        let safeTop: CGFloat = 59

        XCTAssertLessThan(
            RecordMapHeaderLayout.guidanceTopY(safeAreaTop: safeTop),
            RecordMapHeaderLayout.backButtonCenterY(safeAreaTop: safeTop)
        )
        XCTAssertLessThan(
            RecordMapHeaderLayout.guidanceBottomY(safeAreaTop: safeTop),
            RecordMapHeaderLayout.backButtonCenterY(safeAreaTop: safeTop)
        )
        XCTAssertGreaterThan(
            RecordMapHeaderLayout.rightControlsTopY(safeAreaTop: safeTop),
            RecordMapHeaderLayout.guidanceBottomY(safeAreaTop: safeTop)
        )
        XCTAssertEqual(RecordMapHeaderLayout.backButtonCenterX, 52)
        XCTAssertEqual(RecordMapHeaderLayout.rightControlCenterTrailingInset, 54)
    }

    func testRecordBackButtonAndRightControlsStayNearCompactHeader() {
        let safeTop: CGFloat = 59
        let bannerBottom = RecordMapHeaderLayout.guidanceBottomY(safeAreaTop: safeTop)

        XCTAssertGreaterThanOrEqual(
            RecordMapHeaderLayout.backButtonCenterY(safeAreaTop: safeTop),
            bannerBottom + 28
        )
        XCTAssertLessThanOrEqual(
            RecordMapHeaderLayout.backButtonCenterY(safeAreaTop: safeTop),
            bannerBottom + 32
        )
        XCTAssertGreaterThanOrEqual(
            RecordMapHeaderLayout.rightControlsTopY(safeAreaTop: safeTop),
            bannerBottom + 10
        )
        XCTAssertLessThanOrEqual(
            RecordMapHeaderLayout.rightControlsTopY(safeAreaTop: safeTop),
            bannerBottom + 14
        )
        XCTAssertEqual(RecordMapHeaderLayout.controlSpacing, 10)
    }

    func testRecordControlsDoNotReserveRemovedRouteStripSpace() {
        let safeTop: CGFloat = 59
        let bannerBottom = RecordMapHeaderLayout.guidanceBottomY(safeAreaTop: safeTop)
        let frames = RecordMapHeaderLayout.frames(
            containerSize: CGSize(width: 393, height: 852),
            safeAreaTop: safeTop
        )

        XCTAssertEqual(
            RecordMapHeaderLayout.rightControlsTopY(safeAreaTop: safeTop),
            bannerBottom + RecordMapHeaderLayout.rightControlsTopSpacingBelowGuidance
        )
        XCTAssertEqual(
            RecordMapHeaderLayout.backButtonCenterY(safeAreaTop: safeTop),
            bannerBottom + RecordMapHeaderLayout.backButtonCenterSpacingBelowGuidance
        )
        XCTAssertEqual(frames.rightControlsTop, RecordMapHeaderLayout.rightControlsTopY(safeAreaTop: safeTop))
        XCTAssertEqual(frames.weatherButtonTop, bannerBottom + 12)
        XCTAssertEqual(frames.backButtonCenter.y, bannerBottom + 30)
        XCTAssertFalse(RecordMapHeaderLayout.showsRouteStripByDefault)
    }

    func testRecordUnifiedHeaderFramesDriveActualControlPositions() {
        let safeTop: CGFloat = 59
        let size = CGSize(width: 393, height: 852)
        let frames = RecordMapHeaderLayout.frames(containerSize: size, safeAreaTop: safeTop)
        let bannerBottom = frames.bannerFrame.maxY

        XCTAssertEqual(frames.bannerFrame.minX, RecordMapHeaderLayout.guidanceHorizontalInset)
        XCTAssertEqual(frames.bannerFrame.width, size.width - RecordMapHeaderLayout.guidanceHorizontalInset * 2)
        XCTAssertGreaterThanOrEqual(frames.weatherButtonTop, bannerBottom + 10)
        XCTAssertLessThanOrEqual(frames.weatherButtonTop, bannerBottom + 14)
        XCTAssertEqual(frames.rightControlsFrame.midX, size.width - RecordMapHeaderLayout.rightControlCenterTrailingInset)
        XCTAssertEqual(frames.rightControlCenters.count, RecordLaunchControl.rightEdgeOrder.count)
        XCTAssertEqual(frames.rightControlCenters.first?.y, frames.weatherButtonTop + RecordMapHeaderLayout.controlSize / 2)
        XCTAssertEqual(
            frames.rightControlCenters.last?.y,
            frames.weatherButtonTop + RecordMapHeaderLayout.controlSize / 2 + CGFloat(2) * (RecordMapHeaderLayout.controlSize + RecordMapHeaderLayout.controlSpacing)
        )
        XCTAssertEqual(frames.backButtonCenter.x, RecordMapHeaderLayout.backButtonCenterX)
        XCTAssertGreaterThanOrEqual(frames.backButtonCenter.y, bannerBottom + 28)
        XCTAssertLessThanOrEqual(frames.backButtonCenter.y, bannerBottom + 32)
    }

    func testRecordRouteRecommendationIsNotAlwaysVisibleAndUsesRightControl() {
        XCTAssertFalse(RecordMapHeaderLayout.showsRouteStripByDefault)
        XCTAssertTrue(RecordMapHeaderLayout.routeRecommendationUsesRightControlOnly)
        XCTAssertEqual(RecordLaunchControl.rightEdgeOrder[1], .routeRecommendation)
        XCTAssertEqual(
            RecordLaunchControl.routeRecommendation.iconName,
            "point.topleft.down.curvedto.point.bottomright.up"
        )
    }

    func testGuidanceBannerIncludesRecommendationCopyWithoutRouteName() {
        let plan = RecordLaunchPlan.mockToday
        let copy = plan.recommendation.guidanceText(for: plan.defaultSport, weather: .liveClear)

        XCTAssertFalse(copy.isEmpty)
        XCTAssertTrue(copy.contains("Z2 40분"))
        XCTAssertFalse(copy.contains(plan.route.title))
    }

    func testRecordHeaderTopHeroPlacementUsesNotificationZoneRatios() {
        let safeTop: CGFloat = 59
        let screenHeight: CGFloat = 852

        XCTAssertLessThanOrEqual(
            RecordMapHeaderLayout.visualTopRatio(safeAreaTop: safeTop, screenHeight: screenHeight),
            RecordMapHeaderLayout.maxVisualTopRatio
        )
        XCTAssertLessThanOrEqual(
            RecordMapHeaderLayout.visualBottomRatio(safeAreaTop: safeTop, screenHeight: screenHeight),
            RecordMapHeaderLayout.maxVisualBottomRatio
        )
        XCTAssertNotEqual(RecordMapHeaderLayout.topHeaderInsetBelowSafeArea, 54)
    }

    func testMapboxOrnamentInsetStaysNearBottom() {
        XCTAssertLessThanOrEqual(RecordMapOrnamentLayout.bottomInset, 16)
        XCTAssertGreaterThanOrEqual(RecordMapOrnamentLayout.bottomInset, 8)
        XCTAssertEqual(RecordMapOrnamentLayout.horizontalInset, 12)
    }

    func testReadyAndBottomGradientAreReducedForMapVisibility() {
        XCTAssertLessThanOrEqual(RecordReadyLaunchVisualLayout.buttonDiameter, 82)
        XCTAssertLessThan(RecordReadyLaunchVisualLayout.buttonDiameter, 88)
        XCTAssertEqual(RecordReadyLaunchVisualLayout.buttonCenterBottomOffset, 54)
        XCTAssertLessThanOrEqual(RecordReadyLaunchVisualLayout.containerHeight, 214)
        XCTAssertLessThanOrEqual(RecordReadyLaunchVisualLayout.defaultShadowOpacity, 0.10)
        XCTAssertLessThanOrEqual(RecordReadyLaunchVisualLayout.defaultShadowRadius, 8)

        XCTAssertLessThanOrEqual(RecordMapBottomFocusGradientLayout.defaultHeight, 130)
        XCTAssertLessThanOrEqual(RecordMapBottomFocusGradientLayout.focusedHeight, 245)
        XCTAssertLessThanOrEqual(RecordMapBottomFocusGradientLayout.defaultBottomOpacity, 0.09)
        XCTAssertLessThanOrEqual(RecordMapBottomFocusGradientLayout.focusedBottomOpacity, 0.30)
    }

    func testReadyTapOrDimmedTapDoesNotStartWorkout() {
        XCTAssertFalse(
            RecordReadyRadialInteraction.shouldStartWorkout(
                isRadialSelectionActive: false,
                hoveredSport: .cycling
            )
        )
        XCTAssertFalse(
            RecordReadyRadialInteraction.shouldStartWorkout(
                isRadialSelectionActive: false,
                hoveredSport: nil
            )
        )
    }

    func testReadyReleaseRequiresHoveredSportAfterLongPress() {
        XCTAssertFalse(
            RecordReadyRadialInteraction.shouldStartWorkout(
                isRadialSelectionActive: true,
                hoveredSport: nil
            )
        )
        XCTAssertTrue(
            RecordReadyRadialInteraction.shouldStartWorkout(
                isRadialSelectionActive: true,
                hoveredSport: .running
            )
        )
    }

    func testWeatherPolicyDoesNotAttemptLiveFetchOnEntryWithoutCoordinate() {
        let state = RecordLocationState.mockCurrent

        XCTAssertFalse(state.shouldRequestPermissionOnEntry)
        XCTAssertFalse(RecordWeatherFetchPolicy.shouldAttemptLiveFetch(locationState: state, apiKey: "valid-weather-key"))
    }

    func testWeatherDetailSnapshotIncludesFallbackDustAndForecastFoundation() {
        let detail = RecordWeatherDetailSnapshot.make(from: .fallbackClear)

        XCTAssertEqual(detail.locationName, "현재 위치 근처")
        XCTAssertEqual(detail.temperatureText, "26°")
        XCTAssertEqual(detail.fineDustText, "보통")
        XCTAssertEqual(detail.ultraFineDustText, "보통")
        XCTAssertFalse(detail.hourlyForecast.isEmpty)
        XCTAssertFalse(detail.dailyForecast.isEmpty)
        XCTAssertTrue(detail.isFallback)
    }

    func testRouteCatalogProvidesMockOptionsWithoutDirectionsBackend() {
        let options = RecordRouteCatalogOption.mockOptions(for: .cycling)

        XCTAssertGreaterThanOrEqual(options.count, 3)
        XCTAssertEqual(options.first?.id, "han-river-recovery")
        XCTAssertTrue(options.allSatisfy { !$0.route.coordinates.isEmpty })
        XCTAssertTrue(options.contains { $0.route.title == "탄천 가벼운 루프" })
    }

    private func authorizedLocationState() -> RecordLocationState {
        RecordLocationState(
            authorization: .authorized,
            coordinate: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )
    }
}

private struct StubRecordWeatherService: RecordWeatherService {
    let snapshot: RecordWeatherSnapshot

    func fetchWeather(latitude: Double, longitude: Double) async throws -> RecordWeatherSnapshot {
        snapshot
    }
}

private struct FailingRecordWeatherService: RecordWeatherService {
    func fetchWeather(latitude: Double, longitude: Double) async throws -> RecordWeatherSnapshot {
        throw URLError(.cannotConnectToHost)
    }
}

private extension RecordWeatherSnapshot {
    static let liveClear = RecordWeatherSnapshot(
        temperatureCelsius: 23,
        condition: .clear,
        wind: RecordWeatherWind(speedMps: 1.8),
        observedAt: Date(timeIntervalSince1970: 1_750_001_000),
        source: "test-live",
        isFallback: false
    )

    static let rainy = RecordWeatherSnapshot(
        temperatureCelsius: 18,
        condition: .rain,
        wind: RecordWeatherWind(speedMps: 3.2),
        observedAt: Date(timeIntervalSince1970: 1_750_001_000),
        source: "test-live",
        isFallback: false
    )

    static let windy = RecordWeatherSnapshot(
        temperatureCelsius: 21,
        condition: .clear,
        wind: RecordWeatherWind(speedMps: 7.2),
        observedAt: Date(timeIntervalSince1970: 1_750_001_000),
        source: "test-live",
        isFallback: false
    )
}
