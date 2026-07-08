import XCTest
@testable import SOOM

final class UnifiedWorkoutToRecoveryActivityMapperTests: XCTestCase {
    private let mapper = UnifiedWorkoutToRecoveryActivityMapper()
    private let processedMapper = ProcessedWorkoutToRecoveryActivityMapper()
    private let processedBuilder = ProcessedWorkoutBuilder()

    func testRunningWorkoutMapsToRunRecoveryActivity() {
        let workout = makeWorkout(type: .running)

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.workoutType.title, RecoveryWorkoutType.run.title)
    }

    func testCyclingWorkoutMapsToRideRecoveryActivity() {
        let workout = makeWorkout(type: .cycling)

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.workoutType.title, RecoveryWorkoutType.ride.title)
    }

    func testSwimmingWorkoutMapsToSwimRecoveryActivity() {
        let workout = makeWorkout(type: .swimming)

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.workoutType.title, RecoveryWorkoutType.swim.title)
    }

    func testWalkingAndHikingFallbackToRunRecoveryActivity() {
        let walking = makeWorkout(type: .walking)
        let hiking = makeWorkout(type: .hiking)

        XCTAssertEqual(mapper.map(walking).workoutType.title, RecoveryWorkoutType.run.title)
        XCTAssertEqual(mapper.map(hiking).workoutType.title, RecoveryWorkoutType.run.title)
    }

    func testMapsDurationDistanceHeartRateAndCompletedAt() {
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let workout = makeWorkout(
            type: .running,
            endDate: completedAt,
            durationSeconds: 3_120,
            distanceMeters: 10_400,
            averageHeartRate: 151
        )

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.durationMinutes, 52)
        XCTAssertEqual(activity.distanceKm, 10.4, accuracy: 0.001)
        XCTAssertEqual(activity.averageHeartRate, 151)
        XCTAssertEqual(activity.completedAt, completedAt)
    }

    func testNilHeartRateMapsSafely() {
        let workout = makeWorkout(type: .cycling, averageHeartRate: nil)

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.averageHeartRate, 0)
        XCTAssertGreaterThan(activity.trainingLoad, 0)
        XCTAssertGreaterThan(activity.relativeEffort, 0)
    }

    func testEstimatedTrainingLoadAndRelativeEffortStayInMvpRange() {
        let workout = makeWorkout(
            type: .cycling,
            durationSeconds: 7_200,
            averageHeartRate: 172,
            activeEnergyKcal: 1_200
        )

        let activity = mapper.map(workout)

        XCTAssertGreaterThanOrEqual(activity.trainingLoad, 5)
        XCTAssertLessThanOrEqual(activity.trainingLoad, 180)
        XCTAssertGreaterThanOrEqual(activity.relativeEffort, 1)
        XCTAssertLessThanOrEqual(activity.relativeEffort, 100)
    }

    func testDifferentSourcesMapToSameRecoveryActivityShape() {
        let apple = makeWorkout(source: .appleHealthKit, type: .running)
        let garmin = makeWorkout(source: .garmin, type: .running)
        let samsung = makeWorkout(source: .samsungHealth, type: .running)

        let appleActivity = mapper.map(apple)
        let garminActivity = mapper.map(garmin)
        let samsungActivity = mapper.map(samsung)

        XCTAssertEqual(appleActivity.workoutType.title, RecoveryWorkoutType.run.title)
        XCTAssertEqual(garminActivity.workoutType.title, RecoveryWorkoutType.run.title)
        XCTAssertEqual(samsungActivity.workoutType.title, RecoveryWorkoutType.run.title)
        XCTAssertEqual(appleActivity.durationMinutes, garminActivity.durationMinutes)
        XCTAssertEqual(garminActivity.durationMinutes, samsungActivity.durationMinutes)
    }

    func testProcessedCyclingWorkoutMatchesUnifiedRecoveryActivityInput() {
        assertProcessedParity(for: makeWorkout(type: .cycling))
    }

    func testProcessedRunningWorkoutMatchesUnifiedRecoveryActivityInput() {
        assertProcessedParity(for: makeWorkout(type: .running))
    }

    func testProcessedWalkingWorkoutMatchesUnifiedRecoveryActivityInput() {
        assertProcessedParity(for: makeWorkout(type: .walking))
    }

    func testProcessedTimeOnlyWorkoutMatchesUnifiedRecoveryActivityInput() {
        assertProcessedParity(for: makeWorkout(
            type: .running,
            durationSeconds: 1_500,
            distanceMeters: nil,
            averageHeartRate: nil,
            activeEnergyKcal: nil
        ))
    }

    func testProcessedMissingHeartRateMatchesUnifiedRecoveryActivityInput() {
        assertProcessedParity(for: makeWorkout(
            type: .cycling,
            averageHeartRate: nil
        ))
    }

    func testProcessedRouteBackedWorkoutMatchesUnifiedInputWhenSourceDistanceExists() {
        let workout = makeWorkout(type: .running, distanceMeters: 8_200)
        let route = makeRoute(for: workout, totalDistanceMeters: 8_200)

        assertProcessedParity(for: workout, route: route)
    }

    func testProcessedRouteDistanceCanFillMissingSourceDistance() {
        let workout = makeWorkout(type: .cycling, distanceMeters: nil)
        let route = makeRoute(for: workout, totalDistanceMeters: 12_400)

        let processed = processedBuilder.make(from: workout, route: route)
        let unifiedActivity = mapper.map(workout)
        let activity = processedMapper.map(processed)

        XCTAssertEqual(activity.distanceKm, 12.4, accuracy: 0.001)
        XCTAssertEqual(activity.durationMinutes, unifiedActivity.durationMinutes)
        XCTAssertEqual(activity.averageHeartRate, unifiedActivity.averageHeartRate)
        XCTAssertEqual(activity.relativeEffort, unifiedActivity.relativeEffort)
        XCTAssertEqual(activity.trainingLoad, unifiedActivity.trainingLoad, accuracy: 0.001)
    }

    func testSelectorCanMapProcessedRecoveryInputsWithoutMigratingUnifiedPath() {
        let selector = UnifiedWorkoutAnalysisInputSelector()
        let included = processedBuilder.make(from: makeWorkout(type: .running))
        let excluded = processedBuilder.make(from: makeWorkout(type: .cycling, isExcluded: true))

        let inputs = selector.selectRecoveryInputs(fromProcessedWorkouts: [included, excluded])

        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs.first?.workoutType.title, RecoveryWorkoutType.run.title)
    }

    func testProcessedPathMatchesUnifiedPathForMixedRecentRecoveryInputs() {
        let workouts = makeMixedRecentWorkouts()
        let selector = UnifiedWorkoutAnalysisInputSelector()

        let unifiedActivities = selector.selectRecoveryInputs(from: workouts)
        let processedActivities = selector.selectRecoveryInputs(
            fromProcessedWorkouts: workouts.map { processedBuilder.make(from: $0) }
        )

        assertRecoveryActivities(processedActivities, match: unifiedActivities)
    }

    func testProcessedPathMatchesUnifiedPathForEmptyRecoveryInputs() {
        let selector = UnifiedWorkoutAnalysisInputSelector()

        let unifiedActivities = selector.selectRecoveryInputs(from: [])
        let processedActivities = selector.selectRecoveryInputs(fromProcessedWorkouts: [])

        assertRecoveryActivities(processedActivities, match: unifiedActivities)
    }

    func testRecoverySummaryMatchesForProcessedMixedRecentInputs() {
        let workouts = makeMixedRecentWorkouts()
        let selector = UnifiedWorkoutAnalysisInputSelector()
        let calculator = RecoveryCalculator(referenceDate: Date(timeIntervalSince1970: 1_800_000_000))
        let unifiedActivities = selector.selectRecoveryInputs(from: workouts)
        let processedActivities = selector.selectRecoveryInputs(
            fromProcessedWorkouts: workouts.map { processedBuilder.make(from: $0) }
        )

        let unifiedSummary = calculator.calculateSummary(from: unifiedActivities)
        let processedSummary = calculator.calculateSummary(from: processedActivities)

        assertRecoverySummaries(processedSummary, match: unifiedSummary)
    }

    func testRecoverySummaryMatchesForProcessedRouteBackedInputWithSourceDistance() {
        let workout = makeWorkout(type: .running, distanceMeters: 8_200)
        let route = makeRoute(for: workout, totalDistanceMeters: 8_200)
        let selector = UnifiedWorkoutAnalysisInputSelector()
        let calculator = RecoveryCalculator(referenceDate: Date(timeIntervalSince1970: 1_800_000_000))
        let unifiedActivities = selector.selectRecoveryInputs(from: [workout])
        let processedActivities = selector.selectRecoveryInputs(
            fromProcessedWorkouts: [processedBuilder.make(from: workout, route: route)]
        )

        assertRecoveryActivities(processedActivities, match: unifiedActivities)
        assertRecoverySummaries(
            calculator.calculateSummary(from: processedActivities),
            match: calculator.calculateSummary(from: unifiedActivities)
        )
    }

    func testRouteDerivedDistanceIsTheOnlyAcceptedProcessedPathDifference() {
        let workout = makeWorkout(type: .cycling, distanceMeters: nil)
        let route = makeRoute(for: workout, totalDistanceMeters: 12_400)
        let selector = UnifiedWorkoutAnalysisInputSelector()
        let calculator = RecoveryCalculator(referenceDate: Date(timeIntervalSince1970: 1_800_000_000))
        let unifiedActivities = selector.selectRecoveryInputs(from: [workout])
        let processedActivities = selector.selectRecoveryInputs(
            fromProcessedWorkouts: [processedBuilder.make(from: workout, route: route)]
        )

        XCTAssertEqual(unifiedActivities.count, 1)
        XCTAssertEqual(processedActivities.count, 1)
        XCTAssertEqual(unifiedActivities[0].distanceKm, 0, accuracy: 0.001)
        XCTAssertEqual(processedActivities[0].distanceKm, 12.4, accuracy: 0.001)
        assertRecoveryActivities(
            processedActivities,
            match: unifiedActivities,
            allowDistanceDifference: true
        )
        assertRecoverySummaries(
            calculator.calculateSummary(from: processedActivities),
            match: calculator.calculateSummary(from: unifiedActivities)
        )
    }

    private func makeWorkout(
        source: UnifiedDataSource = .appleHealthKit,
        type: UnifiedWorkoutType,
        endDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        durationSeconds: TimeInterval = 3_600,
        distanceMeters: Double? = 32_000,
        averageHeartRate: Double? = 142,
        activeEnergyKcal: Double? = 620,
        isExcluded: Bool = false
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: source,
            workoutType: type,
            startDate: endDate.addingTimeInterval(-durationSeconds),
            endDate: endDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: activeEnergyKcal,
            averageHeartRate: averageHeartRate,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcluded,
            createdAt: endDate,
            updatedAt: endDate
        )
    }

    private func makeMixedRecentWorkouts() -> [UnifiedWorkout] {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

        return [
            makeWorkout(
                type: .running,
                endDate: referenceDate,
                durationSeconds: 3_000,
                distanceMeters: 10_000,
                averageHeartRate: 150,
                activeEnergyKcal: 480
            ),
            makeWorkout(
                type: .cycling,
                endDate: referenceDate.addingTimeInterval(-1 * 24 * 60 * 60),
                durationSeconds: 4_200,
                distanceMeters: 32_000,
                averageHeartRate: 142,
                activeEnergyKcal: 700
            ),
            makeWorkout(
                type: .walking,
                endDate: referenceDate.addingTimeInterval(-3 * 24 * 60 * 60),
                durationSeconds: 2_100,
                distanceMeters: 2_800,
                averageHeartRate: nil,
                activeEnergyKcal: 180
            ),
            makeWorkout(
                type: .running,
                endDate: referenceDate.addingTimeInterval(-5 * 24 * 60 * 60),
                durationSeconds: 1_800,
                distanceMeters: nil,
                averageHeartRate: nil,
                activeEnergyKcal: nil
            ),
            makeWorkout(
                type: .cycling,
                endDate: referenceDate.addingTimeInterval(-2 * 24 * 60 * 60),
                durationSeconds: 7_200,
                distanceMeters: 60_000,
                averageHeartRate: 172,
                activeEnergyKcal: 1_200,
                isExcluded: true
            )
        ]
    }

    private func makeRoute(
        for workout: UnifiedWorkout,
        totalDistanceMeters: Double,
        totalElevationGain: Double = 42
    ) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workout.id,
            source: workout.source,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, altitude: 10),
                WorkoutRouteCoordinate(latitude: 37.52, longitude: 127.02, altitude: 52)
            ],
            totalDistanceMeters: totalDistanceMeters,
            totalElevationGain: totalElevationGain
        )
    }

    private func assertProcessedParity(
        for workout: UnifiedWorkout,
        route: WorkoutRoute? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let unifiedActivity = mapper.map(workout)
        let processed = processedBuilder.make(from: workout, route: route)
        let processedActivity = processedMapper.map(processed)

        XCTAssertEqual(processedActivity.workoutType.title, unifiedActivity.workoutType.title, file: file, line: line)
        XCTAssertEqual(processedActivity.durationMinutes, unifiedActivity.durationMinutes, file: file, line: line)
        XCTAssertEqual(processedActivity.distanceKm, unifiedActivity.distanceKm, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(processedActivity.averageHeartRate, unifiedActivity.averageHeartRate, file: file, line: line)
        XCTAssertEqual(processedActivity.relativeEffort, unifiedActivity.relativeEffort, file: file, line: line)
        XCTAssertEqual(processedActivity.trainingLoad, unifiedActivity.trainingLoad, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(processedActivity.completedAt, unifiedActivity.completedAt, file: file, line: line)
    }

    private func assertRecoveryActivities(
        _ actual: [RecoveryActivity],
        match expected: [RecoveryActivity],
        allowDistanceDifference: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualActivity, expectedActivity) in zip(actual, expected) {
            XCTAssertEqual(actualActivity.workoutType.title, expectedActivity.workoutType.title, file: file, line: line)
            XCTAssertEqual(actualActivity.durationMinutes, expectedActivity.durationMinutes, file: file, line: line)
            if !allowDistanceDifference {
                XCTAssertEqual(actualActivity.distanceKm, expectedActivity.distanceKm, accuracy: 0.001, file: file, line: line)
            }
            XCTAssertEqual(actualActivity.averageHeartRate, expectedActivity.averageHeartRate, file: file, line: line)
            XCTAssertEqual(actualActivity.relativeEffort, expectedActivity.relativeEffort, file: file, line: line)
            XCTAssertEqual(actualActivity.trainingLoad, expectedActivity.trainingLoad, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(actualActivity.completedAt, expectedActivity.completedAt, file: file, line: line)
        }
    }

    private func assertRecoverySummaries(
        _ actual: RecoverySummary,
        match expected: RecoverySummary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.score, expected.score, file: file, line: line)
        XCTAssertEqual(actual.status, expected.status, file: file, line: line)
        XCTAssertEqual(actual.description, expected.description, file: file, line: line)
        XCTAssertEqual(actual.recommendation, expected.recommendation, file: file, line: line)
        XCTAssertEqual(actual.trendText, expected.trendText, file: file, line: line)
        XCTAssertEqual(actual.coachMessage.coachName, expected.coachMessage.coachName, file: file, line: line)
        XCTAssertEqual(actual.coachMessage.subtitle, expected.coachMessage.subtitle, file: file, line: line)
        XCTAssertEqual(actual.coachMessage.message, expected.coachMessage.message, file: file, line: line)
        XCTAssertEqual(actual.recommendationCard.title, expected.recommendationCard.title, file: file, line: line)
        XCTAssertEqual(actual.recommendationCard.description, expected.recommendationCard.description, file: file, line: line)
        XCTAssertEqual(actual.recommendationCard.actionLabel, expected.recommendationCard.actionLabel, file: file, line: line)
        XCTAssertEqual(actual.recommendationCard.icon, expected.recommendationCard.icon, file: file, line: line)
        XCTAssertEqual(actual.trends.count, expected.trends.count, file: file, line: line)
        for (actualTrend, expectedTrend) in zip(actual.trends, expected.trends) {
            XCTAssertEqual(actualTrend.title, expectedTrend.title, file: file, line: line)
            XCTAssertEqual(actualTrend.currentValue, expectedTrend.currentValue, file: file, line: line)
            XCTAssertEqual(actualTrend.unit, expectedTrend.unit, file: file, line: line)
            XCTAssertEqual(actualTrend.changeText, expectedTrend.changeText, file: file, line: line)
            XCTAssertEqual(actualTrend.direction, expectedTrend.direction, file: file, line: line)
            XCTAssertEqual(actualTrend.values, expectedTrend.values, file: file, line: line)
        }
        XCTAssertEqual(actual.insights.count, expected.insights.count, file: file, line: line)
        for (actualInsight, expectedInsight) in zip(actual.insights, expected.insights) {
            XCTAssertEqual(actualInsight.title, expectedInsight.title, file: file, line: line)
            XCTAssertEqual(actualInsight.message, expectedInsight.message, file: file, line: line)
            XCTAssertEqual(actualInsight.icon, expectedInsight.icon, file: file, line: line)
            XCTAssertEqual(actualInsight.tone, expectedInsight.tone, file: file, line: line)
        }
        XCTAssertEqual(actual.lastUpdated, expected.lastUpdated, file: file, line: line)
        XCTAssertEqual(actual.dataQuality.label, expected.dataQuality.label, file: file, line: line)
    }
}
