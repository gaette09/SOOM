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
            fallbackCoordinate: RecordLocationState.fallbackCoordinate,
            locationTimestamp: fixedDate, horizontalAccuracy: 5
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
            fallbackCoordinate: RecordLocationState.fallbackCoordinate,
            locationTimestamp: fixedDate, horizontalAccuracy: 5
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
            fallbackCoordinate: RecordLocationState.fallbackCoordinate,
            locationTimestamp: fixedDate, horizontalAccuracy: 5
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
            fallbackCoordinate: RecordLocationState.fallbackCoordinate,
            locationTimestamp: fixedDate, horizontalAccuracy: 5
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
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "경사도" && $0.value == "--" })
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

        XCTAssertEqual(hud.compactMetrics.map(\.label), ["운동 시간", "현재 속도"])
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

        XCTAssertEqual(hud.compactMetrics.map(\.label), ["운동 시간", "현재 페이스"])
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

        XCTAssertEqual(hud.compactMetrics.map(\.label), ["운동 시간", "현재 속도"])
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
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "경사도" && $0.value == "--" && $0.unit == "%" })
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
            fallbackCoordinate: RecordLocationState.fallbackCoordinate,
            locationTimestamp: fixedDate, horizontalAccuracy: 5
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

        let resumed = paused.resumed(at: fixedDate.addingTimeInterval(50))
        XCTAssertEqual(resumed.state, .active)
        XCTAssertNil(resumed.pausedAt)

        let finished = resumed.finished(at: fixedDate.addingTimeInterval(90))
        XCTAssertEqual(finished.state, .finished)
        XCTAssertEqual(finished.elapsedTime(referenceDate: fixedDate.addingTimeInterval(120)), 55)
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

    func testStationaryGPSWobbleDoesNotAccumulateDistance() {
        var session = RecordWorkoutSessionStarter(dateProvider: { self.fixedDate }).start(sport: .running, locationState: .mockCurrent)
            .recordingLocation(.init(latitude: 37.5, longitude: 127), at: fixedDate, speedMetersPerSecond: 0, horizontalAccuracy: 8)
        for second in 1...300 {
            let wobble = second % 2 == 0 ? 0.00005 : -0.00005
            session = session.recordingLocation(.init(latitude: 37.5 + wobble, longitude: 127),
                at: fixedDate.addingTimeInterval(Double(second)), speedMetersPerSecond: 0.1, horizontalAccuracy: 8)
        }
        XCTAssertEqual(session.accumulatedDistanceMeters, 0, accuracy: 0.01)
    }

    func testIsolatedJumpAndReturnDoNotAddFalseRunningDistance() {
        let origin = RecordMapCoordinate(latitude: 37.5, longitude: 127)
        let session = RecordWorkoutSessionStarter(dateProvider: { self.fixedDate }).start(sport: .running, locationState: .mockCurrent).recordingLocation(origin, at: fixedDate, horizontalAccuracy: 5)
        let jumped = session.recordingLocation(.init(latitude: 37.51, longitude: 127),
            at: fixedDate.addingTimeInterval(2), speedMetersPerSecond: 3, horizontalAccuracy: 5)
        XCTAssertEqual(jumped, session)
        let recovered = jumped.recordingLocation(.init(latitude: 37.50005, longitude: 127),
            at: fixedDate.addingTimeInterval(4), speedMetersPerSecond: 3, horizontalAccuracy: 5)
        XCTAssertLessThan(recovered.accumulatedDistanceMeters, 10)
    }

    func testAccurateGNSSVelocityPreventsZigzagDistanceInflationDuringRun() {
        var session = RecordWorkoutSessionStarter(dateProvider: { self.fixedDate }).start(sport: .running, locationState: .mockCurrent)
            .recordingLocation(.init(latitude: 37.5, longitude: 127), at: fixedDate,
                speedMetersPerSecond: 2.5, horizontalAccuracy: 8, speedAccuracy: 0.1)
        for index in 1...120 {
            let side = index % 2 == 0 ? 0.00005 : -0.00005
            session = session.recordingLocation(.init(latitude: 37.5 + Double(index) * 5 / 111_195, longitude: 127 + side),
                at: fixedDate.addingTimeInterval(Double(index * 2)), speedMetersPerSecond: 2.5,
                horizontalAccuracy: 8, speedAccuracy: 0.1)
        }
        XCTAssertEqual(session.accumulatedDistanceMeters, 600, accuracy: 1)
        let hud = RecordActiveHUDLayout.make(session: session, referenceDate: fixedDate.addingTimeInterval(240))
        XCTAssertTrue(hud.secondaryMetrics.contains { $0.label == "평균 페이스" && $0.value == "6'40\"" })
        XCTAssertEqual(session.capturedRoute?.coordinates.count, 121)
        let summary = RecordWorkoutSummaryBuilder.makeSummary(from: session.finished(at: fixedDate.addingTimeInterval(240)))
        let measured = summary?.measuredTelemetry
        XCTAssertEqual(measured?.samples.last?.distanceMeters ?? 0, 600, accuracy: 1)
        XCTAssertTrue(measured?.samples.allSatisfy { $0.speedMetersPerSecond == 2.5 } == true)
        let plotted = WorkoutTelemetryChartBuilder.addingDerivedChannels(to: measured!, route: summary?.workoutRoute)
        XCTAssertEqual(plotted.samples.last?.distanceMeters ?? 0, 600, accuracy: 1)
        XCTAssertTrue(plotted.samples.allSatisfy { $0.speedMetersPerSecond == 2.5 })
    }

    func testPoorAccuracyAndImpossibleSpeedCannotCorruptDistanceOrMaximumSpeed() {
        let session = RecordWorkoutSessionStarter(dateProvider: { self.fixedDate }).start(sport: .running, locationState: .mockCurrent)
        let poor = session.recordingLocation(.init(latitude: 37.5, longitude: 127), at: fixedDate,
            speedMetersPerSecond: 100, horizontalAccuracy: 45)
        XCTAssertEqual(poor, session)
        let accepted = session.recordingLocation(.init(latitude: 37.5, longitude: 127), at: fixedDate,
            speedMetersPerSecond: 100, horizontalAccuracy: 5)
        XCTAssertNil(accepted.currentSpeedMetersPerSecond)
        XCTAssertNil(accepted.maxSpeedMetersPerSecond)
    }

    func testOldRouteCheckpointWithoutNewMeasurementFieldsStillDecodes() throws {
        let data = Data(#"{"latitude":37.5,"longitude":127,"segmentIndex":0}"#.utf8)
        let coordinate = try JSONDecoder().decode(RecordRouteCoordinate.self, from: data)
        XCTAssertEqual(coordinate.latitude, 37.5)
        XCTAssertNil(coordinate.cumulativeDistanceMeters)
        XCTAssertNil(coordinate.measuredSpeedMetersPerSecond)
        XCTAssertNil(coordinate.altitude)
    }

    private func activeSession(sport: RecordSportMode) -> RecordWorkoutSession {
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
            fallbackCoordinate: RecordLocationState.fallbackCoordinate,
            locationTimestamp: fixedDate, horizontalAccuracy: 5
        )

        return RecordWorkoutSessionStarter(
            idProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        ).start(sport: sport, locationState: state)
    }
}

extension RecordWorkoutSessionTests {
    func testMultiplePausesExcludeTimeAndPausedFinishKeepsActiveDuration() {
        let start = RecordWorkoutSessionStarter(idProvider: { self.fixedID }, dateProvider: { self.fixedDate })
            .start(sport: .running, locationState: .mockCurrent)
        let session = start.paused(at: fixedDate.addingTimeInterval(600))
            .resumed(at: fixedDate.addingTimeInterval(1_200))
            .paused(at: fixedDate.addingTimeInterval(1_800))
            .resumed(at: fixedDate.addingTimeInterval(2_400))
            .paused(at: fixedDate.addingTimeInterval(3_000))
            .finished(at: fixedDate.addingTimeInterval(3_600))
        XCTAssertEqual(session.elapsedTime(referenceDate: fixedDate.addingTimeInterval(4_000)), 1_800)
        XCTAssertEqual(session.wallClockElapsedTime(referenceDate: fixedDate), 3_600)
        XCTAssertEqual(RecordWorkoutSummaryBuilder.makeSummary(from: session)?.durationSeconds, 1_800)
    }

    func testResumeDoesNotCountMovementDuringPauseAndPreservesSegments() throws {
        let start = RecordWorkoutSessionStarter(dateProvider: { self.fixedDate }).start(sport: .running, locationState: .mockCurrent)
            .recordingLocation(.init(latitude: 37.5, longitude: 127), at: fixedDate)
            .recordingLocation(.init(latitude: 37.5001, longitude: 127), at: fixedDate.addingTimeInterval(10))
        let beforePause = start.accumulatedDistanceMeters
        let resumed = start.paused(at: fixedDate.addingTimeInterval(20)).resumed(at: fixedDate.addingTimeInterval(600))
        let rejectedOldFix = resumed.recordingLocation(.init(latitude: 37.6, longitude: 127), at: fixedDate.addingTimeInterval(300))
        XCTAssertEqual(rejectedOldFix.accumulatedDistanceMeters, beforePause)
        let moved = resumed.recordingLocation(.init(latitude: 37.6, longitude: 127), at: fixedDate.addingTimeInterval(601))
        XCTAssertEqual(moved.accumulatedDistanceMeters, beforePause, accuracy: 0.01)
        let final = moved.recordingLocation(.init(latitude: 37.6001, longitude: 127), at: fixedDate.addingTimeInterval(611))
        XCTAssertEqual(final.accumulatedDistanceMeters, beforePause * 2, accuracy: 0.1)
        let route = try XCTUnwrap(final.capturedRoute?.workoutRoute(workoutId: final.id, createdAt: fixedDate))
        XCTAssertEqual(route.coordinateSegments.map(\.count), [2, 2])
    }

    func testCheckpointRelaunchRestoresPausedWithoutCountingOfflineInterval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("account-a/active-workout.json")
        let firstStore = RecordWorkoutCheckpointStore(fileURL: path)
        let active = RecordWorkoutSessionStarter(dateProvider: { self.fixedDate }).start(sport: .cycling, locationState: .mockCurrent)
            .recordingLocation(.init(latitude: 37.5, longitude: 127), at: fixedDate)
            .recordingLocation(.init(latitude: 37.5001, longitude: 127), at: fixedDate.addingTimeInterval(10))
        try firstStore.save(active, at: fixedDate.addingTimeInterval(20))
        let recovered = try XCTUnwrap(RecordWorkoutCheckpointStore(fileURL: path).load())
        XCTAssertEqual(recovered.state, .paused)
        XCTAssertEqual(recovered.capturedRoute, active.capturedRoute)
        XCTAssertEqual(recovered.elapsedTime(referenceDate: fixedDate.addingTimeInterval(600)), 20)
        let finished = recovered.resumed(at: fixedDate.addingTimeInterval(600)).finished(at: fixedDate.addingTimeInterval(610))
        XCTAssertEqual(finished.elapsedTime(referenceDate: fixedDate), 30)
        XCTAssertNil(try RecordWorkoutCheckpointStore(fileURL: directory.appendingPathComponent("account-b/active-workout.json")).load())
        try firstStore.clear()
        XCTAssertNil(try firstStore.load())
    }

    func testFinishedCheckpointKeepsExactSummaryAndCorruptionIsNotDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("active-workout.json")
        let store = RecordWorkoutCheckpointStore(fileURL: path)
        let finished = RecordWorkoutSessionStarter(dateProvider: { self.fixedDate }).start(sport: .walking, locationState: .mockCurrent).finished(at: fixedDate.addingTimeInterval(600))
        try store.save(finished, at: fixedDate.addingTimeInterval(610))
        XCTAssertEqual(try store.load(), finished)
        let invalid = Data("invalid".utf8)
        try invalid.write(to: path)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: path), invalid)
    }
}


extension RecordWorkoutSessionTests {
    func testDeletedAccountCheckpointCannotBeRecreatedByLateDepartureSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID()
        let accountDirectory = directory.appendingPathComponent(owner.uuidString.lowercased())
        let path = accountDirectory.appendingPathComponent("active-workout.json")
        let store = RecordWorkoutCheckpointStore(fileURL: path)
        let active = RecordWorkoutSessionStarter(dateProvider: { self.fixedDate })
            .start(sport: .running, locationState: .mockCurrent)
        try store.save(active, at: fixedDate.addingTimeInterval(20))

        // Server deletion is confirmed, then cleanup removes the checkpoint.
        // The still-retained view's departure callback runs afterward.
        AccountDeletionWriteFence.shared.retire(owner)
        try store.clear()
        try FileManager.default.removeItem(at: accountDirectory)
        let paused = active.paused(at: fixedDate.addingTimeInterval(30))
        XCTAssertThrowsError(try store.save(paused, at: fixedDate.addingTimeInterval(30))) { error in
            XCTAssertEqual(error as? RecordWorkoutCheckpointError, .accountDeleted)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountDirectory.path))
        XCTAssertNil(try store.load())
    }

    func testNormalAccountSwitchAndGuestCheckpointRemainResumableWhenAnotherAccountIsRetired() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ownerA = UUID()
        let retiredOwnerB = UUID()
        let pathA = directory.appendingPathComponent(ownerA.uuidString.lowercased() + "/active-workout.json")
        let guestPath = directory.appendingPathComponent("guest/active-workout.json")
        let storeA = RecordWorkoutCheckpointStore(fileURL: pathA, isAccountRetired: { $0 == retiredOwnerB })
        let guestStore = RecordWorkoutCheckpointStore(fileURL: guestPath, isAccountRetired: { _ in
            XCTFail("Guest storage must not be treated as a remote account")
            return true
        })
        let paused = RecordWorkoutSessionStarter(dateProvider: { self.fixedDate })
            .start(sport: .cycling, locationState: .mockCurrent)
            .paused(at: fixedDate.addingTimeInterval(30))

        // An A → B switch must still save A's paused workout to A's path.
        try storeA.save(paused, at: fixedDate.addingTimeInterval(30))
        try guestStore.save(paused, at: fixedDate.addingTimeInterval(30))
        XCTAssertEqual(try storeA.load(), paused)
        XCTAssertEqual(try guestStore.load(), paused)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            directory.appendingPathComponent(retiredOwnerB.uuidString.lowercased()).path))
    }
}
