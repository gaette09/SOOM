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
        let startDate = Date(timeIntervalSince1970: 1_800_010_000)
        let workout = makeWorkout(
            type: .running,
            startDate: startDate,
            duration: 3_000,
            distance: 10_000,
            averageHeartRate: nil,
            calories: 520
        )

        let unifiedWorkout = mapper.map(workout)

        XCTAssertEqual(unifiedWorkout.workoutType, .running)
        XCTAssertEqual(unifiedWorkout.startDate, startDate)
        XCTAssertEqual(unifiedWorkout.endDate, startDate.addingTimeInterval(3_000))
        XCTAssertEqual(unifiedWorkout.durationSeconds, 3_000)
        XCTAssertEqual(unifiedWorkout.distanceMeters, 10_000)
        XCTAssertEqual(unifiedWorkout.activeEnergyKcal, 520)
        XCTAssertNil(unifiedWorkout.averageHeartRate)
        XCTAssertEqual(unifiedWorkout.averageSpeedMetersPerSecond ?? 0, 10_000 / 3_000, accuracy: 0.001)
    }

    func testWalkingWorkoutMapsToUnifiedWalkingWorkout() {
        let startDate = Date(timeIntervalSince1970: 1_800_020_000)
        let workout = makeWorkout(
            type: .walking,
            startDate: startDate,
            duration: 1_800,
            distance: 2_400,
            averageHeartRate: nil,
            calories: 160
        )

        let unifiedWorkout = mapper.map(workout)

        XCTAssertEqual(unifiedWorkout.workoutType, .walking)
        XCTAssertEqual(unifiedWorkout.startDate, startDate)
        XCTAssertEqual(unifiedWorkout.endDate, startDate.addingTimeInterval(1_800))
        XCTAssertEqual(unifiedWorkout.durationSeconds, 1_800)
        XCTAssertEqual(unifiedWorkout.distanceMeters, 2_400)
        XCTAssertEqual(unifiedWorkout.activeEnergyKcal, 160)
        XCTAssertEqual(unifiedWorkout.averageSpeedMetersPerSecond ?? 0, 2_400 / 1_800, accuracy: 0.001)
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

    func testZeroOptionalSummaryMetricsAreTreatedAsMissing() {
        let workout = makeWorkout(
            type: .cycling,
            distance: 0,
            averageHeartRate: 0,
            calories: 0
        )

        let unifiedWorkout = mapper.map(workout)

        XCTAssertNil(unifiedWorkout.distanceMeters)
        XCTAssertNil(unifiedWorkout.averageHeartRate)
        XCTAssertNil(unifiedWorkout.activeEnergyKcal)
        XCTAssertNil(unifiedWorkout.averageSpeedMetersPerSecond)
        XCTAssertEqual(unifiedWorkout.dataQuality, .missing)
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

    func testImportedHealthKitWorkoutIsCompatibleWithProcessedWorkoutBuilder() {
        let workout = makeWorkout(
            type: .cycling,
            duration: 3_600,
            distance: 30_000,
            averageHeartRate: nil,
            calories: 640
        )

        let unifiedWorkout = mapper.map(workout)
        let processed = ProcessedWorkoutBuilder().make(from: unifiedWorkout)

        XCTAssertEqual(processed.source, .appleHealthKit)
        XCTAssertEqual(processed.externalId, workout.id.uuidString)
        XCTAssertEqual(processed.workoutType, .cycling)
        XCTAssertEqual(processed.distanceMeters, 30_000)
        XCTAssertEqual(processed.activeEnergyKcal, 640)
        XCTAssertNil(processed.averageHeartRate)
        XCTAssertEqual(processed.display.primaryMetricLabel, "속도")
        XCTAssertEqual(processed.display.primaryMetricValue, "30.0 km/h")
        XCTAssertEqual(processed.metricAvailability[.distance], .measured)
        XCTAssertEqual(processed.metricAvailability[.calories], .measured)
        XCTAssertEqual(processed.metricAvailability[.averageHeartRate], .missing)
        XCTAssertEqual(processed.metricAvailability[.cadence], .missing)
        XCTAssertEqual(processed.metricAvailability[.power], .missing)
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
