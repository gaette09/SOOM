import XCTest
@testable import SOOM

final class UnifiedWorkoutToGrowthInputMapperTests: XCTestCase {
    private let mapper = UnifiedWorkoutToGrowthInputMapper()

    func testRunningDistanceAndDurationBuildsPaceText() {
        let workout = makeWorkout(
            type: .running,
            durationSeconds: 3_000,
            distanceMeters: 10_000
        )

        let input = mapper.map(workout)

        XCTAssertEqual(input.workoutType, .running)
        XCTAssertEqual(input.distanceKm ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(input.durationMinutes, 50)
        XCTAssertEqual(input.averagePaceText, "5:00/km")
    }

    func testCyclingSpeedConvertsToKilometersPerHour() {
        let workout = makeWorkout(
            type: .cycling,
            averageSpeedMetersPerSecond: 8.333333
        )

        let input = mapper.map(workout)

        XCTAssertEqual(input.workoutType, .cycling)
        XCTAssertEqual(input.averageSpeedKmh ?? 0, 30, accuracy: 0.01)
        XCTAssertNil(input.averagePaceText)
    }

    func testSourceIsPreservedAcrossAppleGarminAndSamsung() {
        let apple = mapper.map(makeWorkout(source: .appleHealthKit, type: .running))
        let garmin = mapper.map(makeWorkout(source: .garmin, type: .running))
        let samsung = mapper.map(makeWorkout(source: .samsungHealth, type: .running))

        XCTAssertEqual(apple.source, .appleHealthKit)
        XCTAssertEqual(garmin.source, .garmin)
        XCTAssertEqual(samsung.source, .samsungHealth)
    }

    func testNilDistanceAndSpeedMapSafely() {
        let workout = makeWorkout(
            type: .running,
            distanceMeters: nil,
            averageSpeedMetersPerSecond: nil
        )

        let input = mapper.map(workout)

        XCTAssertNil(input.distanceKm)
        XCTAssertNil(input.averagePaceText)
        XCTAssertNil(input.averageSpeedKmh)
    }

    func testDurationMinutesUsesRoundedMinutesWithMinimumOneMinute() {
        let workout = makeWorkout(durationSeconds: 20)

        let input = mapper.map(workout)

        XCTAssertEqual(input.durationMinutes, 1)
    }

    func testMapperDoesNotDependOnRecoveryScore() {
        let workout = makeWorkout(
            type: .hiking,
            durationSeconds: 4_200,
            distanceMeters: 7_000,
            activeEnergyKcal: 520,
            averageHeartRate: 136,
            elevationGainMeters: 220
        )

        let input = mapper.map(workout)

        XCTAssertEqual(input.workoutType, UnifiedWorkoutType.hiking)
        XCTAssertEqual(input.averagePaceText, "10:00/km")
        XCTAssertEqual(input.averageHeartRate, 136)
        XCTAssertEqual(input.elevationGainMeters, 220)
        XCTAssertEqual(input.activeEnergyKcal, 520)
    }

    private func makeWorkout(
        id: UUID = UUID(),
        source: UnifiedDataSource = .appleHealthKit,
        type: UnifiedWorkoutType = .running,
        startDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        durationSeconds: TimeInterval = 3_600,
        distanceMeters: Double? = 10_000,
        activeEnergyKcal: Double? = 600,
        averageHeartRate: Double? = 145,
        averageSpeedMetersPerSecond: Double? = nil,
        elevationGainMeters: Double? = nil
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: id,
            externalId: id.uuidString,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: activeEnergyKcal,
            averageHeartRate: averageHeartRate,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: averageSpeedMetersPerSecond,
            elevationGainMeters: elevationGainMeters,
            dataQuality: .partial,
            createdAt: startDate,
            updatedAt: startDate
        )
    }
}
