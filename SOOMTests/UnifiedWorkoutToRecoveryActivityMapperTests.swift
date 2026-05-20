import XCTest
@testable import SOOM

final class UnifiedWorkoutToRecoveryActivityMapperTests: XCTestCase {
    private let mapper = UnifiedWorkoutToRecoveryActivityMapper()

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

    private func makeWorkout(
        source: UnifiedDataSource = .appleHealthKit,
        type: UnifiedWorkoutType,
        endDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        durationSeconds: TimeInterval = 3_600,
        distanceMeters: Double? = 32_000,
        averageHeartRate: Double? = 142,
        activeEnergyKcal: Double? = 620
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
            createdAt: endDate,
            updatedAt: endDate
        )
    }
}
