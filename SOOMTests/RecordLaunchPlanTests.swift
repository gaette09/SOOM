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

    func testWeatherRetryStateDoesNotBlockRetryAfterFailure() {
        let coordinateKey = "37.5266,126.9271"
        var retryState = RecordWeatherRetryState()

        XCTAssertTrue(retryState.shouldAttemptFetch(for: coordinateKey))
        retryState.markAttempt(for: coordinateKey)
        retryState.markFailure(for: coordinateKey)

        XCTAssertEqual(retryState.lastAttemptCoordinateKey, coordinateKey)
        XCTAssertNil(retryState.lastSuccessfulCoordinateKey)
        XCTAssertTrue(retryState.shouldAttemptFetch(for: coordinateKey))
    }

    func testWeatherRetryStateOnlySkipsAfterSuccessUnlessForced() {
        let coordinateKey = "37.5266,126.9271"
        var retryState = RecordWeatherRetryState()

        retryState.markAttempt(for: coordinateKey)
        retryState.markSuccess(for: coordinateKey)

        XCTAssertEqual(retryState.lastAttemptCoordinateKey, coordinateKey)
        XCTAssertEqual(retryState.lastSuccessfulCoordinateKey, coordinateKey)
        XCTAssertFalse(retryState.shouldAttemptFetch(for: coordinateKey))
        XCTAssertTrue(retryState.shouldAttemptFetch(for: coordinateKey, forceRefresh: true))
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

    func testReadyDefaultVisualUsesStrongerStartButton() {
        XCTAssertGreaterThanOrEqual(RecordReadyLaunchVisualLayout.buttonDiameter, 100)
        XCTAssertLessThanOrEqual(RecordReadyLaunchVisualLayout.buttonDiameter, 104)
        XCTAssertEqual(
            RecordReadyLaunchVisualLayout.interactiveHitDiameter,
            RecordReadyLaunchVisualLayout.buttonDiameter
        )
        XCTAssertLessThanOrEqual(
            RecordReadyLaunchVisualLayout.interactiveHitDiameter,
            RecordReadyLaunchVisualLayout.maxInteractiveHitDiameter
        )
        XCTAssertTrue(RecordReadyLaunchVisualLayout.usesCircleContentShape)
        XCTAssertTrue(RecordReadyLaunchVisualLayout.attachesGestureToButtonOnly)
        XCTAssertFalse(RecordReadyLaunchVisualLayout.containerUsesRectangularContentShape)
        XCTAssertFalse(RecordReadyLaunchVisualLayout.decorativeLayersAllowHitTesting)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.allowsHitTesting)
        XCTAssertGreaterThanOrEqual(
            RecordReadyLaunchVisualLayout.buttonCenterBottomOffset - RecordReadyLaunchVisualLayout.previousButtonCenterBottomOffset,
            20
        )
        XCTAssertLessThanOrEqual(
            RecordReadyLaunchVisualLayout.buttonCenterBottomOffset - RecordReadyLaunchVisualLayout.previousButtonCenterBottomOffset,
            30
        )
        XCTAssertLessThanOrEqual(RecordReadyLaunchVisualLayout.containerHeight, 214)
        XCTAssertTrue(RecordReadyLaunchVisualLayout.usesBlackSurface)
        XCTAssertTrue(RecordReadyLaunchVisualLayout.hidesSportIconInButton)
        XCTAssertTrue(RecordReadyLaunchVisualLayout.hidesReadyText)
        XCTAssertTrue(RecordReadyLaunchVisualLayout.hidesStartHintInButton)
        XCTAssertEqual(RecordReadyLaunchVisualLayout.primaryIconName, "play.fill")
        XCTAssertTrue(RecordReadyLaunchVisualLayout.primaryLabel.isEmpty)
        XCTAssertGreaterThanOrEqual(RecordReadyLaunchVisualLayout.playIconSize, 30)
        XCTAssertLessThanOrEqual(RecordReadyLaunchVisualLayout.playIconSize, 36)
        XCTAssertGreaterThan(RecordReadyLaunchVisualLayout.defaultShadowOpacity, RecordReadyLaunchVisualLayout.focusedShadowOpacity)
    }

    func testReadyButtonHasSubtleBreathingRing() {
        XCTAssertTrue(RecordReadyLaunchVisualLayout.hasBreathingRing)
        XCTAssertEqual(RecordReadyLaunchVisualLayout.ringMinScale, 1.0)
        XCTAssertEqual(RecordReadyLaunchVisualLayout.ringMaxScale, 1.06)
        XCTAssertGreaterThanOrEqual(RecordReadyLaunchVisualLayout.ringMinOpacity, 0.22)
        XCTAssertLessThanOrEqual(RecordReadyLaunchVisualLayout.ringMaxOpacity, 0.38)
        XCTAssertLessThan(RecordReadyLaunchVisualLayout.focusedRingOpacity, RecordReadyLaunchVisualLayout.ringMinOpacity)
        XCTAssertGreaterThanOrEqual(RecordReadyLaunchVisualLayout.ringDuration, 3.0)
        XCTAssertLessThanOrEqual(RecordReadyLaunchVisualLayout.ringDuration, 3.6)
        XCTAssertTrue(RecordReadyLaunchVisualLayout.disablesRingBreathingForReduceMotion)
    }

    func testReadyHitAreaIsLimitedToVisibleButtonCircle() {
        let readyCenter = CGPoint(x: 180, y: 140)
        let radius = RecordReadyLaunchVisualLayout.interactiveHitDiameter / 2

        XCTAssertTrue(
            RecordReadyRadialInteraction.isTouchInsideReadyButton(
                location: readyCenter,
                readyCenter: readyCenter
            )
        )
        XCTAssertTrue(
            RecordReadyRadialInteraction.isTouchInsideReadyButton(
                location: CGPoint(x: readyCenter.x + radius, y: readyCenter.y),
                readyCenter: readyCenter
            )
        )
        XCTAssertFalse(
            RecordReadyRadialInteraction.isTouchInsideReadyButton(
                location: CGPoint(x: readyCenter.x + radius + 1, y: readyCenter.y),
                readyCenter: readyCenter
            )
        )
        XCTAssertFalse(
            RecordReadyRadialInteraction.isTouchInsideReadyButton(
                location: CGPoint(x: readyCenter.x, y: readyCenter.y + radius + 8),
                readyCenter: readyCenter
            )
        )
    }

    func testBottomWaveUsesOversizedRadialBlobWithoutShapeEdge() {
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesLegacyBottomGradient)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesReferenceWaveView)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesBottomBlobWaveView)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.usesRecordBreathingBottomWaveView)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesCustomProgressShape)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesCustomBezierWaveShape)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesCircleOrEllipseGeometry)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.usesRadialBlobFill)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.usesRadialGradientFill)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesEllipticalRadialFade)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesAlphaMaskFade)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.alphaMaskUsesSolidPurpleFill)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.usesOversizedRadialBlob)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.usesDirectRadialBlobGradient)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.clipsToCustomWaveShape)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesCustomShapeClippingEdge)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.visibleShapeEdgeCanReachScreen)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesLinearGradientFill)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesBlurOverlay)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesSolidRectangleLayer)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesLinearGradientBackground)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesRectangularTopEdge)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesTopStrokeOrBorder)
        XCTAssertFalse(RecordBreathingBottomWaveLayout.usesTopShadowOrOverlay)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.waveBottomFullyOpaque)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.waveOutsideTransparent)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.waveHeight, 360)
    }

    func testBottomWaveRadialBlobGeometryAndFadeAreLargeEnough() {
        let screenWidth: CGFloat = 393
        let blobWidth = RecordBreathingBottomWaveLayout.blobWidth(for: screenWidth)
        let blobHeight = RecordBreathingBottomWaveLayout.blobHeight(for: screenWidth)
        let blobFrameHeight = RecordBreathingBottomWaveLayout.blobFrameHeight(for: screenWidth)
        let opacityStops = RecordBreathingBottomWaveLayout.radialBlobOpacityStops

        XCTAssertEqual(opacityStops.count, 5)
        XCTAssertEqual(opacityStops[0].location, 0.00)
        XCTAssertEqual(opacityStops[0].opacity, 1.0)
        XCTAssertEqual(opacityStops[1].location, 0.45)
        XCTAssertEqual(opacityStops[1].opacity, 0.95)
        XCTAssertEqual(opacityStops[2].location, 0.65)
        XCTAssertEqual(opacityStops[2].opacity, 0.55)
        XCTAssertEqual(opacityStops[3].location, 0.82)
        XCTAssertEqual(opacityStops[3].opacity, 0.18)
        XCTAssertEqual(opacityStops[4].location, 1.00)
        XCTAssertEqual(opacityStops[4].opacity, 0.0)
        XCTAssertGreaterThanOrEqual(blobWidth, screenWidth * 2.4)
        XCTAssertGreaterThanOrEqual(blobHeight, 520)
        XCTAssertLessThanOrEqual(RecordBreathingBottomWaveLayout.blobCenterYOffset, 320)
        XCTAssertGreaterThanOrEqual(RecordBreathingBottomWaveLayout.blobCenterYOffset, 250)
        XCTAssertGreaterThan(blobFrameHeight, blobHeight)
        XCTAssertGreaterThan(RecordBreathingBottomWaveLayout.blobEndRadius(for: screenWidth), 0)
    }

    func testBottomWaveBreathesByChangingBlobScaleAndYOffset() {
        XCTAssertEqual(RecordBreathingBottomWaveLayout.inhaleProgress, 0)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.exhaleProgress, 1)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.inhaleOpacity, 0.82)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.exhaleOpacity, 1.0)
        XCTAssertGreaterThan(RecordBreathingBottomWaveLayout.inhaleYOffset, RecordBreathingBottomWaveLayout.previousInhaleYOffset)
        XCTAssertGreaterThan(RecordBreathingBottomWaveLayout.exhaleYOffset, RecordBreathingBottomWaveLayout.previousExhaleYOffset)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.inhaleYOffset, 30)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.exhaleYOffset, 8)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.breathingDuration, 3.2)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.repeatForeverAutoreverses)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.breathingChangesShape)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.breathingLoopsBetweenTwoStates)
        XCTAssertTrue(RecordBreathingBottomWaveLayout.disablesBreathingForReduceMotion)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.blobScaleInhale, 0.98)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.blobScaleExhale, 1.05)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.blobInteractionScale, 0.96)
        XCTAssertNotEqual(
            RecordBreathingBottomWaveLayout.blobScale(progress: 0),
            RecordBreathingBottomWaveLayout.blobScale(progress: 1)
        )
        XCTAssertEqual(RecordBreathingBottomWaveLayout.reducedMotionProgress, 0.5)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.interactionProgress, 0)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.interactionOpacity, 0.45)
        XCTAssertEqual(RecordBreathingBottomWaveLayout.interactionYOffset, 42)
        XCTAssertGreaterThan(
            RecordBreathingBottomWaveLayout.exhaleOpacity,
            RecordBreathingBottomWaveLayout.inhaleOpacity
        )
        XCTAssertLessThan(
            RecordBreathingBottomWaveLayout.exhaleYOffset,
            RecordBreathingBottomWaveLayout.inhaleYOffset
        )
        XCTAssertGreaterThanOrEqual(RecordBreathingBottomWaveLayout.transitionDuration, 0.18)
        XCTAssertLessThanOrEqual(RecordBreathingBottomWaveLayout.transitionDuration, 0.25)
    }

    func testReadyWaveInteractionStateControlsBreathingRecovery() {
        XCTAssertTrue(RecordReadyWaveInteractionState.idle.isIdleBreathingActive)
        XCTAssertTrue(RecordReadyWaveInteractionState.idle.restoresBreathing)
        XCTAssertFalse(RecordReadyWaveInteractionState.idle.weakensWave)

        XCTAssertTrue(RecordReadyWaveInteractionState.revealing.weakensWave)
        XCTAssertFalse(RecordReadyWaveInteractionState.revealing.restoresBreathing)
        XCTAssertTrue(RecordReadyWaveInteractionState.dragging.weakensWave)
        XCTAssertFalse(RecordReadyWaveInteractionState.dragging.restoresBreathing)

        XCTAssertFalse(RecordReadyWaveInteractionState.cancelled.weakensWave)
        XCTAssertTrue(RecordReadyWaveInteractionState.cancelled.restoresBreathing)
        XCTAssertFalse(RecordReadyWaveInteractionState.confirmed.weakensWave)
        XCTAssertTrue(RecordReadyWaveInteractionState.confirmed.restoresBreathing)
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
        XCTAssertFalse(detail.hourlyForecasts.isEmpty)
        XCTAssertFalse(detail.dailyForecasts.isEmpty)
        XCTAssertTrue(detail.isFallback)
    }

    func testWeatherDetailIncludesHourlyDailyAndAirQualityFoundation() {
        let detail = RecordWeatherDetailSnapshot.make(from: .liveClear)

        XCTAssertEqual(detail.conditionIconName, RecordWeatherCondition.clear.iconName)
        XCTAssertGreaterThanOrEqual(detail.hourlyForecasts.count, 4)
        XCTAssertGreaterThanOrEqual(detail.dailyForecasts.count, 3)
        XCTAssertEqual(detail.airQuality.pm10Level, .moderate)
        XCTAssertEqual(detail.airQuality.pm25Level, .moderate)
        XCTAssertEqual(detail.airQuality.fineDustText, "보통")
        XCTAssertEqual(detail.airQuality.ultraFineDustText, "보통")
    }

    func testAirQualityLevelMapsOpenWeatherAQI() {
        XCTAssertEqual(RecordAirQualityLevel(openWeatherAQI: 1), .good)
        XCTAssertEqual(RecordAirQualityLevel(openWeatherAQI: 2), .moderate)
        XCTAssertEqual(RecordAirQualityLevel(openWeatherAQI: 3), .moderate)
        XCTAssertEqual(RecordAirQualityLevel(openWeatherAQI: 4), .bad)
        XCTAssertEqual(RecordAirQualityLevel(openWeatherAQI: 5), .veryBad)
    }

    func testRecordSheetsUseSingleFixedDetentPolicy() {
        XCTAssertTrue(RecordFixedSheetLayout.usesSingleFixedDetent)
        XCTAssertTrue(RecordFixedSheetLayout.usesInternalScrollOnly)
        XCTAssertGreaterThanOrEqual(RecordFixedSheetLayout.weatherHeight, 580)
        XCTAssertLessThanOrEqual(RecordFixedSheetLayout.weatherHeight, 620)
        XCTAssertGreaterThanOrEqual(RecordFixedSheetLayout.routeRecommendationHeight, 460)
        XCTAssertLessThanOrEqual(RecordFixedSheetLayout.routeRecommendationHeight, 520)
        XCTAssertGreaterThanOrEqual(RecordFixedSheetLayout.coachDetailHeight, 380)
        XCTAssertLessThanOrEqual(RecordFixedSheetLayout.coachDetailHeight, 460)
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
