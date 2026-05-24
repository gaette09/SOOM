import XCTest
@testable import SOOM

final class WorkoutSplitStreamBuilderTests: XCTestCase {
    func testBuildsFirstAndSecondHalfMetricsFromCadenceStream() {
        let input = makeInput(durationMinutes: 40)
        let samples: [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]] = [
            .cyclingCadence: [
                makeSample(.cyclingCadence, value: 86, start: 0, end: 1_200),
                makeSample(.cyclingCadence, value: 84, start: 1_200, end: 2_400)
            ],
            .heartRate: [
                makeSample(.heartRate, value: 132, start: 0, end: 1_200),
                makeSample(.heartRate, value: 138, start: 1_200, end: 2_400)
            ]
        ]

        let metrics = WorkoutSplitStreamBuilder().build(current: input, samplesByType: samples)

        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics[0].averageCadence ?? -1, 86, accuracy: 0.1)
        XCTAssertEqual(metrics[1].averageCadence ?? -1, 84, accuracy: 0.1)
        XCTAssertEqual(metrics[0].averageHeartRate ?? -1, 132, accuracy: 0.1)
        XCTAssertEqual(metrics[1].averageHeartRate ?? -1, 138, accuracy: 0.1)
    }

    func testWeightedAverageUsesSampleOverlapWithinSplit() {
        let input = makeInput(durationMinutes: 20)
        let samples: [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]] = [
            .cyclingCadence: [
                makeSample(.cyclingCadence, value: 80, start: 0, end: 300),
                makeSample(.cyclingCadence, value: 100, start: 300, end: 600)
            ]
        ]

        let metrics = WorkoutSplitStreamBuilder().build(current: input, samplesByType: samples)

        XCTAssertEqual(metrics[0].averageCadence ?? -1, 90, accuracy: 0.1)
        XCTAssertNil(metrics[1].averageCadence)
    }

    func testEmptySamplesKeepMetricsButNoUsefulStreamData() {
        let input = makeInput(durationMinutes: 30)

        let metrics = WorkoutSplitStreamBuilder().build(current: input, samplesByType: [:])

        XCTAssertEqual(metrics.count, 2)
        XCTAssertFalse(WorkoutSplitStreamBuilder().hasUsefulStreamData(metrics))
    }

    private func makeInput(durationMinutes: Int) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .appleHealthKit,
            workoutType: .cycling,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: durationMinutes,
            distanceKm: 20,
            averagePaceText: nil,
            averageSpeedKmh: 30,
            averageHeartRate: nil,
            elevationGainMeters: nil,
            activeEnergyKcal: nil
        )
    }

    private func makeSample(
        _ type: HealthKitWorkoutMetricSampleType,
        value: Double,
        start: TimeInterval,
        end: TimeInterval
    ) -> HealthKitWorkoutMetricSample {
        HealthKitWorkoutMetricSample(
            sampleType: type,
            value: value,
            unit: "count/min",
            startDate: Date(timeIntervalSince1970: 1_800_000_000 + start),
            endDate: Date(timeIntervalSince1970: 1_800_000_000 + end)
        )
    }
}
