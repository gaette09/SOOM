import XCTest
@testable import SOOM

final class RecordWorkoutSessionTests: XCTestCase {
    private let fixedID = UUID(uuidString: "D819768D-FA24-4900-B57B-E7F7B219C2C1")!
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testSportMappingUsesUnifiedWorkoutTypes() {
        XCTAssertEqual(RecordSportMode.cycling.workoutType, UnifiedWorkoutType.cycling)
        XCTAssertEqual(RecordSportMode.running.workoutType, UnifiedWorkoutType.running)
        XCTAssertEqual(RecordSportMode.walking.workoutType, UnifiedWorkoutType.walking)
    }

    func testStartCommandAllowsLocalFirstWithoutLocationPermission() {
        let starter = RecordWorkoutSessionStarter()
        let command = starter.makeStartCommand(
            sport: .running,
            locationState: RecordLocationState.mockCurrent
        )

        XCTAssertEqual(command.sport, .running)
        XCTAssertEqual(command.workoutType, UnifiedWorkoutType.running)
        XCTAssertTrue(command.canStartLocalFirst)
        XCTAssertFalse(command.startsWithRouteCapture)
    }

    func testStartCommandEnablesRouteCaptureWhenAuthorizedCoordinateExists() {
        let coordinate = RecordMapCoordinate(latitude: 37.5301, longitude: 126.9302)
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: coordinate,
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )

        let command = RecordWorkoutSessionStarter().makeStartCommand(
            sport: .cycling,
            locationState: state
        )

        XCTAssertEqual(command.workoutType, UnifiedWorkoutType.cycling)
        XCTAssertTrue(command.canStartLocalFirst)
        XCTAssertTrue(command.startsWithRouteCapture)
    }

    func testReadyStartCreatesActiveWorkoutSession() {
        let starter = RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        )

        let session = starter.start(
            sport: .walking,
            locationState: RecordLocationState.mockCurrent
        )

        XCTAssertEqual(session.id, fixedID)
        XCTAssertEqual(session.sport, .walking)
        XCTAssertEqual(session.workoutType, UnifiedWorkoutType.walking)
        XCTAssertEqual(session.startedAt, fixedDate)
        XCTAssertEqual(session.state, .active)
        XCTAssertTrue(session.usesLocalFirstStart)
        XCTAssertFalse(session.startedWithLocation)
    }

    func testStartWithAuthorizedLocationSeedsRouteCapture() throws {
        let coordinate = RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271)
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: coordinate,
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )
        let starter = RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        )

        let session = starter.start(sport: .cycling, locationState: state)

        XCTAssertTrue(session.startedWithLocation)
        XCTAssertEqual(session.capturedRoute?.coordinates.count, 1)
        XCTAssertEqual(session.startedCoordinate?.latitude, coordinate.latitude)
        XCTAssertEqual(session.lastCoordinate?.longitude, coordinate.longitude)
        XCTAssertEqual(session.accumulatedDistanceMeters, 0)
    }

    func testDistanceAccumulatesAcrossCoordinatesAndRouteAppends() {
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )
        let starter = RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        )

        let started = starter.start(sport: .running, locationState: state)
        let moved = started
            .recordingLocation(RecordMapCoordinate(latitude: 37.5272, longitude: 126.9280), at: fixedDate.addingTimeInterval(30))
            .recordingLocation(RecordMapCoordinate(latitude: 37.5280, longitude: 126.9290), at: fixedDate.addingTimeInterval(60))

        XCTAssertEqual(moved.capturedRoute?.coordinates.count, 3)
        XCTAssertGreaterThan(moved.accumulatedDistanceMeters, 0)
        XCTAssertEqual(moved.capturedRoute?.distanceMeters, moved.accumulatedDistanceMeters)
    }

    func testSpeedMetricsUpdateAcrossLocationSamples() {
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )
        let starter = RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        )

        let moved = starter.start(sport: .cycling, locationState: state)
            .recordingLocation(
                RecordMapCoordinate(latitude: 37.5272, longitude: 126.9280),
                at: fixedDate.addingTimeInterval(30),
                speedMetersPerSecond: 7
            )
            .recordingLocation(
                RecordMapCoordinate(latitude: 37.5280, longitude: 126.9290),
                at: fixedDate.addingTimeInterval(60),
                speedMetersPerSecond: 9
            )

        XCTAssertEqual(moved.currentSpeedMetersPerSecond, 9)
        XCTAssertEqual(moved.maxSpeedMetersPerSecond, 9)
    }

    func testCyclingHUDUsesSpeedFirstWithCyclingMetrics() {
        let session = activeSession(sport: .cycling)
            .recordingLocation(
                RecordMapCoordinate(latitude: 37.5272, longitude: 126.9280),
                at: fixedDate.addingTimeInterval(30),
                speedMetersPerSecond: 8
            )
        let hud = RecordActiveHUDLayout.make(
            session: session,
            referenceDate: fixedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(hud.primaryMetric.label, "현재 속도")
        XCTAssertEqual(hud.primaryMetric.unit, "km/h")
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "평균 속도" })
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "최대 속도" })
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "케이던스" })
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "경사도" && $0.value == "0" })
    }

    func testActiveHUDDefaultsToCompact() {
        XCTAssertEqual(RecordActiveHUDMode.defaultMode, .compact)
    }

    func testCompactCyclingHUDShowsElapsedAndCurrentSpeedOnly() {
        let session = activeSession(sport: .cycling)
            .recordingLocation(
                RecordMapCoordinate(latitude: 37.5272, longitude: 126.9280),
                at: fixedDate.addingTimeInterval(30),
                speedMetersPerSecond: 8
            )
        let hud = RecordActiveHUDLayout.make(
            session: session,
            referenceDate: fixedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(hud.compactMetrics.map(\.label), ["경과 시간", "현재 속도"])
        XCTAssertEqual(hud.compactMetrics.count, 2)
        XCTAssertEqual(hud.compactMetrics.last?.unit, "km/h")
    }

    func testRunningHUDUsesPaceFirstWithRunningMetrics() {
        let session = activeSession(sport: .running)
            .recordingLocation(
                RecordMapCoordinate(latitude: 37.5272, longitude: 126.9280),
                at: fixedDate.addingTimeInterval(30),
                speedMetersPerSecond: 3.2
            )
        let hud = RecordActiveHUDLayout.make(
            session: session,
            referenceDate: fixedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(hud.primaryMetric.label, "현재 페이스")
        XCTAssertEqual(hud.primaryMetric.unit, "/km")
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "평균 페이스" })
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "현재 속도" })
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "케이던스" && $0.value == "--" })
    }

    func testCompactRunningHUDShowsElapsedAndCurrentPaceOnly() {
        let session = activeSession(sport: .running)
            .recordingLocation(
                RecordMapCoordinate(latitude: 37.5272, longitude: 126.9280),
                at: fixedDate.addingTimeInterval(30),
                speedMetersPerSecond: 3.2
            )
        let hud = RecordActiveHUDLayout.make(
            session: session,
            referenceDate: fixedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(hud.compactMetrics.map(\.label), ["경과 시간", "현재 페이스"])
        XCTAssertEqual(hud.compactMetrics.count, 2)
        XCTAssertEqual(hud.compactMetrics.last?.unit, "/km")
    }

    func testWalkingHUDKeepsSimpleWalkingMetrics() {
        let hud = RecordActiveHUDLayout.make(
            session: activeSession(sport: .walking),
            referenceDate: fixedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(hud.primaryMetric.label, "현재 속도")
        XCTAssertEqual(hud.secondaryMetrics.map(\.label), ["거리", "평균 속도", "현재 고도", "심박수"])
    }

    func testCompactWalkingHUDShowsElapsedAndCurrentSpeedOnly() {
        let hud = RecordActiveHUDLayout.make(
            session: activeSession(sport: .walking),
            referenceDate: fixedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(hud.compactMetrics.map(\.label), ["경과 시간", "현재 속도"])
        XCTAssertEqual(hud.compactMetrics.count, 2)
        XCTAssertEqual(hud.compactMetrics.last?.unit, "km/h")
    }

    func testMissingHUDMetricsUseStablePlaceholders() {
        let hud = RecordActiveHUDLayout.make(
            session: activeSession(sport: .cycling),
            referenceDate: fixedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(hud.primaryMetric.value, "--")
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "심박수" && $0.value == "--" })
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "케이던스" && $0.value == "--" })
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "경사도" && $0.value == "0" && $0.unit == "%" })
    }

    func testCompactHUDMissingPrimaryMetricUsesPlaceholder() {
        let cyclingHUD = RecordActiveHUDLayout.make(
            session: activeSession(sport: .cycling),
            referenceDate: fixedDate.addingTimeInterval(60)
        )
        let runningHUD = RecordActiveHUDLayout.make(
            session: activeSession(sport: .running),
            referenceDate: fixedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(cyclingHUD.compactMetrics.last?.value, "--")
        XCTAssertEqual(runningHUD.compactMetrics.last?.value, "--")
    }

    func testActiveHUDModeExpandCollapseAndSessionBoundaries() {
        let expanded = RecordActiveHUDModeTransition.expand(from: .compact)
        XCTAssertEqual(expanded, .expanded)
        XCTAssertEqual(RecordActiveHUDModeTransition.collapse(from: expanded), .compact)
        XCTAssertEqual(RecordActiveHUDModeTransition.modeAfterPauseResume(expanded), .expanded)
        XCTAssertEqual(RecordActiveHUDModeTransition.modeAfterFinish(expanded), .compact)
    }

    func testActiveHUDLayeringKeepsCompactHUDAboveMapControls() {
        XCTAssertGreaterThan(
            RecordActiveHUDLayerLayout.hudZIndex(for: .compact),
            RecordActiveHUDLayerLayout.rightControlsZIndex
        )
        XCTAssertGreaterThan(
            RecordActiveHUDLayerLayout.hudZIndex(for: .expanded),
            RecordActiveHUDLayerLayout.hudZIndex(for: .compact)
        )
    }

    func testPausedSessionDoesNotAppendRouteCoordinates() {
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )
        let session = RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        )
        .start(sport: .walking, locationState: state)
        .paused(at: fixedDate.addingTimeInterval(10))

        let movedWhilePaused = session.recordingLocation(
            RecordMapCoordinate(latitude: 37.5280, longitude: 126.9290),
            at: fixedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(movedWhilePaused.capturedRoute?.coordinates.count, 1)
        XCTAssertEqual(movedWhilePaused.accumulatedDistanceMeters, 0)
    }

    func testPauseResumeAndFinishKeepSessionLocalOnly() {
        let starter = RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        )
        let session = starter.start(sport: .cycling, locationState: RecordLocationState.mockCurrent)

        let paused = session.paused(at: fixedDate.addingTimeInterval(15))
        XCTAssertEqual(paused.state, .paused)
        XCTAssertEqual(paused.elapsedTime(referenceDate: fixedDate.addingTimeInterval(50)), 15)

        let resumed = paused.resumed()
        XCTAssertEqual(resumed.state, .active)
        XCTAssertNil(resumed.pausedAt)

        let finished = resumed.finished(at: fixedDate.addingTimeInterval(90))
        XCTAssertEqual(finished.state, .finished)
        XCTAssertEqual(finished.elapsedTime(referenceDate: fixedDate.addingTimeInterval(120)), 90)
        XCTAssertTrue(finished.usesLocalFirstStart)
    }

    func testRecordWorkoutSessionDoesNotUseRecoveryCalculator() {
        let session = RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        ).start(sport: .cycling, locationState: RecordLocationState.mockCurrent)

        XCTAssertEqual(session.statusLabel, "기록 중")
        XCTAssertEqual(session.workoutType, UnifiedWorkoutType.cycling)
    }

    private func activeSession(sport: RecordSportMode) -> RecordWorkoutSession {
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )

        return RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        ).start(sport: sport, locationState: state)
    }
}
