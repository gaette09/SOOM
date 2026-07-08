import XCTest
@testable import SOOM

final class ProcessedWorkoutBuilderTests: XCTestCase {
    private let builder = ProcessedWorkoutBuilder()

    func testCyclingWorkoutUsesSpeedAsPrimaryMetric() {
        let workout = makeWorkout(
            type: .cycling,
            durationSeconds: 3_600,
            distanceMeters: 30_000,
            activeEnergyKcal: 640,
            averageHeartRate: 142,
            averageSpeedMetersPerSecond: 8.333333
        )

        let processed = builder.make(from: workout)

        XCTAssertEqual(processed.workoutType, .cycling)
        XCTAssertEqual(processed.distanceMeters, 30_000)
        assertMetric(processed, .distance, is: .measured)
        assertMetric(processed, .speed, is: .measured)
        assertMetric(processed, .pace, is: .unsupported)
        XCTAssertEqual(processed.display.primaryMetricLabel, "속도")
        XCTAssertEqual(processed.display.primaryMetricValue, "30.0 km/h")
        XCTAssertEqual(processed.display.paceText, "움직임 준비 중")
    }

    func testRunningWorkoutUsesDerivedPaceAsPrimaryMetric() {
        let workout = makeWorkout(
            type: .running,
            durationSeconds: 3_000,
            distanceMeters: 10_000
        )

        let processed = builder.make(from: workout)

        XCTAssertEqual(processed.workoutType, .running)
        XCTAssertEqual(processed.averagePaceSecondsPerKilometer ?? 0, 300, accuracy: 0.001)
        assertMetric(processed, .pace, is: .derived)
        assertMetric(processed, .speed, is: .unsupported)
        XCTAssertEqual(processed.display.primaryMetricLabel, "페이스")
        XCTAssertEqual(processed.display.primaryMetricValue, "5:00/km")
    }

    func testWalkingWorkoutRemainsWalkingAndUsesSpeed() {
        let workout = makeWorkout(
            type: .walking,
            durationSeconds: 1_800,
            distanceMeters: 2_500
        )

        let processed = builder.make(from: workout)

        XCTAssertEqual(processed.workoutType, .walking)
        XCTAssertEqual(processed.display.sportTitle, "걷기")
        assertMetric(processed, .speed, is: .derived)
        assertMetric(processed, .pace, is: .unsupported)
        XCTAssertEqual(processed.display.primaryMetricLabel, "속도")
        XCTAssertEqual(processed.display.primaryMetricValue, "5.0 km/h")
    }

    func testTimeOnlyWorkoutKeepsDistanceAndMovementMetricsMissing() {
        let workout = makeWorkout(
            type: .running,
            durationSeconds: 1_200,
            distanceMeters: nil,
            activeEnergyKcal: nil,
            averageHeartRate: nil,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil
        )

        let processed = builder.make(from: workout)

        XCTAssertNil(processed.distanceMeters)
        XCTAssertNil(processed.averagePaceSecondsPerKilometer)
        XCTAssertNil(processed.averageSpeedMetersPerSecond)
        assertMetric(processed, .distance, is: .missing)
        assertMetric(processed, .pace, is: .missing)
        XCTAssertEqual(processed.display.distanceText, "거리 준비 중")
        XCTAssertEqual(processed.display.primaryMetricValue, "움직임 준비 중")
    }

    func testRouteBackedWorkoutIncludesRenderableRouteAndDerivedFallbacks() {
        let id = UUID()
        let workout = makeWorkout(
            id: id,
            type: .cycling,
            durationSeconds: 2_000,
            distanceMeters: nil,
            elevationGainMeters: nil
        )
        let route = WorkoutRoute(
            workoutId: id,
            source: .soomLocal,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, altitude: 10),
                WorkoutRouteCoordinate(latitude: 37.6, longitude: 127.1, altitude: 55)
            ],
            totalDistanceMeters: 12_000,
            totalElevationGain: 45
        )

        let processed = builder.make(from: workout, route: route)

        XCTAssertEqual(processed.route?.hasRenderableRoute, true)
        XCTAssertEqual(processed.route?.coordinateCount, 2)
        XCTAssertEqual(processed.distanceMeters, 12_000)
        XCTAssertEqual(processed.elevationGainMeters, 45)
        assertMetric(processed, .route, is: .measured)
        assertMetric(processed, .distance, is: .derived)
        assertMetric(processed, .elevation, is: .derived)
        XCTAssertEqual(processed.display.routeBadgeLabel, "경로 저장")
    }

    func testMissingHeartRatePowerCadenceElevationAndCaloriesAreExplicit() {
        let workout = makeWorkout(
            type: .cycling,
            activeEnergyKcal: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            elevationGainMeters: nil
        )

        let processed = builder.make(from: workout)

        assertMetric(processed, .averageHeartRate, is: .missing)
        assertMetric(processed, .maxHeartRate, is: .missing)
        assertMetric(processed, .calories, is: .missing)
        assertMetric(processed, .elevation, is: .missing)
        assertMetric(processed, .power, is: .missing)
        assertMetric(processed, .cadence, is: .missing)
        XCTAssertEqual(processed.display.averageHeartRateText, "—")
        XCTAssertEqual(processed.display.caloriesText, "—")
        XCTAssertEqual(processed.display.elevationText, "—")
    }

    func testIncompleteDataDoesNotCrashAndKeepsSafePlaceholders() {
        let workout = makeWorkout(
            type: .other,
            durationSeconds: 0,
            distanceMeters: -10,
            activeEnergyKcal: -20,
            averageHeartRate: -1,
            maxHeartRate: -2,
            averageSpeedMetersPerSecond: -3,
            elevationGainMeters: -4
        )
        let route = WorkoutRoute(
            workoutId: workout.id,
            source: .unknown,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0)
            ],
            totalDistanceMeters: -10,
            totalElevationGain: -5
        )

        let processed = builder.make(from: workout, route: route)

        XCTAssertNil(processed.distanceMeters)
        XCTAssertNil(processed.averageSpeedMetersPerSecond)
        XCTAssertNil(processed.activeEnergyKcal)
        XCTAssertNil(processed.averageHeartRate)
        XCTAssertEqual(processed.route?.hasRenderableRoute, false)
        assertMetric(processed, .route, is: .missing)
        XCTAssertEqual(processed.display.durationText, "0분")
        XCTAssertEqual(processed.display.distanceText, "거리 준비 중")
    }

    func testRecordSavedCyclingRouteBackedWorkoutUsesSpeedAndMissingSensorStates() {
        let workout = makeRecordSavedWorkout(type: .cycling, distanceMeters: 30_000)
        let route = makeRecordRoute(for: workout, totalDistanceMeters: 30_000)

        let processed = builder.make(from: workout, route: route)

        XCTAssertEqual(processed.source, .soomLocal)
        XCTAssertEqual(processed.workoutType, .cycling)
        XCTAssertEqual(processed.durationSeconds, 3_600)
        XCTAssertEqual(processed.distanceMeters, 30_000)
        XCTAssertEqual(processed.averageSpeedMetersPerSecond ?? 0, 30_000 / 3_600, accuracy: 0.001)
        XCTAssertEqual(processed.route?.hasRenderableRoute, true)
        XCTAssertEqual(processed.route?.totalDistanceMeters, 30_000)
        assertMetric(processed, .distance, is: .measured)
        assertMetric(processed, .speed, is: .measured)
        assertMetric(processed, .pace, is: .unsupported)
        assertRecordMissingSensorMetrics(processed, cadence: .missing, power: .missing)
        XCTAssertEqual(processed.display.primaryMetricLabel, "속도")
        XCTAssertEqual(processed.display.primaryMetricValue, "30.0 km/h")
    }

    func testRecordSavedRunningRouteBackedWorkoutDerivesPace() {
        let workout = makeRecordSavedWorkout(type: .running, durationSeconds: 3_000, distanceMeters: 10_000)
        let route = makeRecordRoute(for: workout, totalDistanceMeters: 10_000)

        let processed = builder.make(from: workout, route: route)

        XCTAssertEqual(processed.workoutType, .running)
        XCTAssertEqual(processed.durationSeconds, 3_000)
        XCTAssertEqual(processed.distanceMeters, 10_000)
        XCTAssertEqual(processed.averagePaceSecondsPerKilometer ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(processed.route?.coordinateCount, 3)
        assertMetric(processed, .distance, is: .measured)
        assertMetric(processed, .pace, is: .derived)
        assertMetric(processed, .speed, is: .unsupported)
        assertRecordMissingSensorMetrics(processed, cadence: .missing, power: .unsupported)
        XCTAssertEqual(processed.display.primaryMetricLabel, "페이스")
        XCTAssertEqual(processed.display.primaryMetricValue, "5:00/km")
    }

    func testRecordSavedWalkingRouteBackedWorkoutUsesSpeed() {
        let workout = makeRecordSavedWorkout(type: .walking, durationSeconds: 1_800, distanceMeters: 2_500)
        let route = makeRecordRoute(for: workout, totalDistanceMeters: 2_500)

        let processed = builder.make(from: workout, route: route)

        XCTAssertEqual(processed.workoutType, .walking)
        XCTAssertEqual(processed.durationSeconds, 1_800)
        XCTAssertEqual(processed.distanceMeters, 2_500)
        XCTAssertEqual(processed.averageSpeedMetersPerSecond ?? 0, 2_500 / 1_800, accuracy: 0.001)
        assertMetric(processed, .distance, is: .measured)
        assertMetric(processed, .speed, is: .measured)
        assertMetric(processed, .pace, is: .unsupported)
        assertRecordMissingSensorMetrics(processed, cadence: .missing, power: .unsupported)
        XCTAssertEqual(processed.display.primaryMetricLabel, "속도")
        XCTAssertEqual(processed.display.primaryMetricValue, "5.0 km/h")
    }

    func testRecordSavedTimeOnlyWorkoutRemainsValidWithoutRoute() {
        let workout = makeRecordSavedWorkout(
            type: .running,
            durationSeconds: 1_800,
            distanceMeters: nil,
            averageSpeedMetersPerSecond: nil
        )

        let processed = builder.make(from: workout)

        XCTAssertEqual(processed.source, .soomLocal)
        XCTAssertEqual(processed.durationSeconds, 1_800)
        XCTAssertNil(processed.distanceMeters)
        XCTAssertNil(processed.averagePaceSecondsPerKilometer)
        XCTAssertNil(processed.averageSpeedMetersPerSecond)
        XCTAssertNil(processed.route)
        assertMetric(processed, .duration, is: .measured)
        assertMetric(processed, .distance, is: .missing)
        assertMetric(processed, .pace, is: .missing)
        assertMetric(processed, .route, is: .missing)
        assertRecordMissingSensorMetrics(processed, cadence: .missing, power: .unsupported)
        XCTAssertEqual(processed.display.distanceText, "거리 준비 중")
        XCTAssertEqual(processed.display.primaryMetricValue, "움직임 준비 중")
    }

    func testRecordSavedLocationDeniedWorkoutRemainsTimeOnlyAndValid() {
        let workout = makeRecordSavedWorkout(
            type: .walking,
            durationSeconds: 1_200,
            distanceMeters: nil,
            averageSpeedMetersPerSecond: nil
        )

        let processed = builder.make(from: workout, route: nil)

        XCTAssertEqual(processed.workoutType, .walking)
        XCTAssertEqual(processed.durationSeconds, 1_200)
        XCTAssertNil(processed.distanceMeters)
        assertMetric(processed, .duration, is: .measured)
        assertMetric(processed, .distance, is: .missing)
        assertMetric(processed, .speed, is: .missing)
        assertMetric(processed, .route, is: .missing)
        XCTAssertEqual(processed.display.primaryMetricLabel, "속도")
        XCTAssertEqual(processed.display.primaryMetricValue, "움직임 준비 중")
    }

    func testRecordSavedWorkoutWithMissingDistanceUsesRenderableRouteDistance() {
        let workout = makeRecordSavedWorkout(
            type: .cycling,
            durationSeconds: 2_400,
            distanceMeters: nil,
            averageSpeedMetersPerSecond: nil
        )
        let route = makeRecordRoute(for: workout, totalDistanceMeters: 12_000)

        let processed = builder.make(from: workout, route: route)

        XCTAssertEqual(processed.distanceMeters, 12_000)
        XCTAssertEqual(processed.averageSpeedMetersPerSecond ?? 0, 12_000 / 2_400, accuracy: 0.001)
        assertMetric(processed, .distance, is: .derived)
        assertMetric(processed, .speed, is: .derived)
        assertMetric(processed, .route, is: .measured)
        XCTAssertEqual(processed.display.distanceText, "12.00 km")
        XCTAssertEqual(processed.display.primaryMetricValue, "18.0 km/h")
    }

    func testRecordSavedWorkoutWithDistancePrefersWorkoutDistanceOverRouteDistance() {
        let workout = makeRecordSavedWorkout(type: .running, durationSeconds: 3_000, distanceMeters: 10_000)
        let route = makeRecordRoute(for: workout, totalDistanceMeters: 10_200)

        let processed = builder.make(from: workout, route: route)

        XCTAssertEqual(processed.distanceMeters, 10_000)
        XCTAssertEqual(processed.route?.totalDistanceMeters, 10_200)
        XCTAssertEqual(processed.averagePaceSecondsPerKilometer ?? 0, 300, accuracy: 0.001)
        assertMetric(processed, .distance, is: .measured)
        assertMetric(processed, .pace, is: .derived)
        assertMetric(processed, .route, is: .measured)
    }

    private func makeWorkout(
        id: UUID = UUID(),
        source: UnifiedDataSource = .soomLocal,
        type: UnifiedWorkoutType = .running,
        startDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        durationSeconds: TimeInterval = 3_600,
        distanceMeters: Double? = 10_000,
        activeEnergyKcal: Double? = 500,
        averageHeartRate: Double? = 140,
        maxHeartRate: Double? = 170,
        averageSpeedMetersPerSecond: Double? = nil,
        elevationGainMeters: Double? = 80,
        dataQuality: UnifiedDataQuality = .partial
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: id,
            externalId: nil,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(max(durationSeconds, 0)),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: activeEnergyKcal,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            averageSpeedMetersPerSecond: averageSpeedMetersPerSecond,
            elevationGainMeters: elevationGainMeters,
            dataQuality: dataQuality,
            createdAt: startDate,
            updatedAt: startDate
        )
    }

    private func makeRecordSavedWorkout(
        id: UUID = UUID(),
        type: UnifiedWorkoutType,
        startDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        durationSeconds: TimeInterval = 3_600,
        distanceMeters: Double?,
        averageSpeedMetersPerSecond: Double? = nil
    ) -> UnifiedWorkout {
        let speed = averageSpeedMetersPerSecond ?? averageSpeed(
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds
        )

        return UnifiedWorkout(
            id: id,
            externalId: nil,
            source: .soomLocal,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(max(durationSeconds, 0)),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: speed,
            elevationGainMeters: nil,
            dataQuality: .partial,
            createdAt: startDate,
            updatedAt: startDate
        )
    }

    private func makeRecordRoute(
        for workout: UnifiedWorkout,
        totalDistanceMeters: Double
    ) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workout.id,
            source: .soomLocal,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.5266, longitude: 126.9271, timestamp: workout.startDate),
                WorkoutRouteCoordinate(latitude: 37.5272, longitude: 126.9280, timestamp: workout.startDate.addingTimeInterval(900)),
                WorkoutRouteCoordinate(latitude: 37.5280, longitude: 126.9290, timestamp: workout.startDate.addingTimeInterval(1_800))
            ],
            totalDistanceMeters: totalDistanceMeters,
            totalElevationGain: nil,
            createdAt: workout.startDate
        )
    }

    private func averageSpeed(distanceMeters: Double?, durationSeconds: TimeInterval) -> Double? {
        guard let distanceMeters, distanceMeters > 0, durationSeconds > 0 else { return nil }
        return distanceMeters / durationSeconds
    }

    private func assertMetric(
        _ workout: ProcessedWorkout,
        _ metric: ProcessedWorkoutMetric,
        is expectedState: ProcessedWorkoutMetricState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(workout.metricAvailability[metric], expectedState, file: file, line: line)
    }

    private func assertRecordMissingSensorMetrics(
        _ workout: ProcessedWorkout,
        cadence cadenceState: ProcessedWorkoutMetricState,
        power powerState: ProcessedWorkoutMetricState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(workout.averageHeartRate, file: file, line: line)
        XCTAssertNil(workout.maxHeartRate, file: file, line: line)
        XCTAssertNil(workout.activeEnergyKcal, file: file, line: line)
        XCTAssertNil(workout.elevationGainMeters, file: file, line: line)
        assertMetric(workout, .averageHeartRate, is: .missing, file: file, line: line)
        assertMetric(workout, .maxHeartRate, is: .missing, file: file, line: line)
        assertMetric(workout, .calories, is: .missing, file: file, line: line)
        assertMetric(workout, .elevation, is: .missing, file: file, line: line)
        assertMetric(workout, .cadence, is: cadenceState, file: file, line: line)
        assertMetric(workout, .power, is: powerState, file: file, line: line)
        assertMetric(workout, .splits, is: .missing, file: file, line: line)
        assertMetric(workout, .zones, is: .missing, file: file, line: line)
        XCTAssertEqual(workout.display.averageHeartRateText, "—", file: file, line: line)
        XCTAssertEqual(workout.display.maxHeartRateText, "—", file: file, line: line)
        XCTAssertEqual(workout.display.caloriesText, "—", file: file, line: line)
        XCTAssertEqual(workout.display.elevationText, "—", file: file, line: line)
    }
}
