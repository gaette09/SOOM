import XCTest
@testable import SOOM

final class HealthKitWorkoutToUnifiedWorkoutMapperTests: XCTestCase {
    private let mapper = HealthKitWorkoutToUnifiedWorkoutMapper()

    func testCyclingWorkoutMapsToUnifiedCyclingWorkout() {
        let workout = makeWorkout(type: .cycling)

        let unifiedWorkout = mapper.map(workout)

        XCTAssertEqual(unifiedWorkout.workoutType, .cycling)
        XCTAssertEqual(unifiedWorkout.source, .appleHealthKit)
    }

    func testRunningWorkoutMapsToUnifiedRunningWorkout() {
        let workout = makeWorkout(type: .running)

        let unifiedWorkout = mapper.map(workout)

        XCTAssertEqual(unifiedWorkout.workoutType, .running)
    }

    func testSwimmingWorkoutMapsToUnifiedSwimmingWorkout() {
        let workout = makeWorkout(type: .swimming)

        let unifiedWorkout = mapper.map(workout)

        XCTAssertEqual(unifiedWorkout.workoutType, .swimming)
    }

    func testMapsDurationDistanceCaloriesAndAverageHeartRate() {
        let mappedAt = Date(timeIntervalSince1970: 1_800_200_000)
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let endDate = startDate.addingTimeInterval(3_600)
        let workout = makeWorkout(
            type: .running,
            startDate: startDate,
            endDate: endDate,
            duration: 3_600,
            distance: 10_000,
            averageHeartRate: 148,
            calories: 640
        )

        let unifiedWorkout = mapper.map(workout, mappedAt: mappedAt)

        XCTAssertEqual(unifiedWorkout.startDate, startDate)
        XCTAssertEqual(unifiedWorkout.endDate, endDate)
        XCTAssertEqual(unifiedWorkout.durationSeconds, 3_600)
        XCTAssertEqual(unifiedWorkout.distanceMeters, 10_000)
        XCTAssertEqual(unifiedWorkout.activeEnergyKcal, 640)
        XCTAssertEqual(unifiedWorkout.averageHeartRate, 148)
        XCTAssertEqual(unifiedWorkout.averageSpeedMetersPerSecond ?? 0, 10_000 / 3_600, accuracy: 0.001)
        XCTAssertEqual(unifiedWorkout.createdAt, mappedAt)
        XCTAssertEqual(unifiedWorkout.updatedAt, mappedAt)
    }

    func testNilOptionalMetricsMapsToPartialQualityWhenSomeSummaryMetricsExist() {
        let workout = makeWorkout(
            type: .cycling,
            distance: 42_000,
            averageHeartRate: nil,
            calories: nil
        )

        let unifiedWorkout = mapper.map(workout)

        XCTAssertNil(unifiedWorkout.averageHeartRate)
        XCTAssertNil(unifiedWorkout.activeEnergyKcal)
        XCTAssertEqual(unifiedWorkout.dataQuality, .partial)
    }

    func testMissingOptionalMetricsMapsToMissingQuality() {
        let workout = makeWorkout(
            type: .walking,
            distance: nil,
            averageHeartRate: nil,
            calories: nil
        )

        let unifiedWorkout = mapper.map(workout)

        XCTAssertEqual(unifiedWorkout.workoutType, .walking)
        XCTAssertEqual(unifiedWorkout.dataQuality, .missing)
        XCTAssertNil(unifiedWorkout.averageSpeedMetersPerSecond)
    }

    func testExternalIdPreservesHealthKitWorkoutIdentifier() {
        let id = UUID()
        let workout = makeWorkout(id: id, type: .running)

        let unifiedWorkout = mapper.map(workout)

        XCTAssertEqual(unifiedWorkout.id, id)
        XCTAssertEqual(unifiedWorkout.externalId, id.uuidString)
    }

    private func makeWorkout(
        id: UUID = UUID(),
        type: HealthKitWorkoutType,
        startDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        endDate: Date? = nil,
        duration: TimeInterval = 3_600,
        distance: Double? = 32_000,
        averageHeartRate: Double? = 142,
        calories: Double? = 620
    ) -> HealthKitWorkout {
        HealthKitWorkout(
            id: id,
            workoutType: type,
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(duration),
            duration: duration,
            distance: distance,
            averageHeartRate: averageHeartRate,
            calories: calories
        )
    }
}
