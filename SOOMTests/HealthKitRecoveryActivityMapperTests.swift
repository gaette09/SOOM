import XCTest
@testable import SOOM

final class HealthKitRecoveryActivityMapperTests: XCTestCase {
    private let mapper = HealthKitRecoveryActivityMapper()

    func testCyclingWorkoutMapsToRideRecoveryActivity() {
        let workout = makeWorkout(type: .cycling)

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.workoutType.title, RecoveryWorkoutType.ride.title)
    }

    func testRunningWorkoutMapsToRunRecoveryActivity() {
        let workout = makeWorkout(type: .running)

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.workoutType.title, RecoveryWorkoutType.run.title)
    }

    func testWalkingWorkoutMapsToRunAsRecoveryFallback() {
        let workout = makeWorkout(type: .walking)

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.workoutType.title, RecoveryWorkoutType.run.title)
    }

    func testMapsDurationDistanceHeartRateAndCompletedAt() {
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let workout = makeWorkout(
            type: .running,
            endDate: completedAt,
            duration: 3_120,
            distance: 10_400,
            averageHeartRate: 151
        )

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.durationMinutes, 52)
        XCTAssertEqual(activity.distanceKm, 10.4, accuracy: 0.001)
        XCTAssertEqual(activity.averageHeartRate, 151)
        XCTAssertEqual(activity.completedAt, completedAt)
    }

    func testNilAverageHeartRateMapsSafely() {
        let workout = makeWorkout(type: .cycling, averageHeartRate: nil)

        let activity = mapper.map(workout)

        XCTAssertEqual(activity.averageHeartRate, 0)
        XCTAssertGreaterThan(activity.trainingLoad, 0)
        XCTAssertGreaterThan(activity.relativeEffort, 0)
    }

    func testEstimatedTrainingLoadAndRelativeEffortStayInMvpRange() {
        let workout = makeWorkout(
            type: .cycling,
            duration: 7_200,
            averageHeartRate: 172,
            calories: 1_200
        )

        let activity = mapper.map(workout)

        XCTAssertGreaterThanOrEqual(activity.trainingLoad, 5)
        XCTAssertLessThanOrEqual(activity.trainingLoad, 180)
        XCTAssertGreaterThanOrEqual(activity.relativeEffort, 1)
        XCTAssertLessThanOrEqual(activity.relativeEffort, 100)
    }

    private func makeWorkout(
        type: HealthKitWorkoutType,
        endDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        duration: TimeInterval = 3_600,
        distance: Double? = 32_000,
        averageHeartRate: Double? = 142,
        calories: Double? = 620
    ) -> HealthKitWorkout {
        HealthKitWorkout(
            id: UUID(),
            workoutType: type,
            startDate: endDate.addingTimeInterval(-duration),
            endDate: endDate,
            duration: duration,
            distance: distance,
            averageHeartRate: averageHeartRate,
            calories: calories
        )
    }
}
