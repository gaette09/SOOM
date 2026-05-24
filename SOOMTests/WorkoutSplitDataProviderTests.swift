import HealthKit
import XCTest
@testable import SOOM

final class WorkoutSplitDataProviderTests: XCTestCase {
    func testProviderBuildsInsightFromHealthKitStreamSamples() async throws {
        let fetcher = FakeSplitMetricStreamFetcher(result: .success([
            .cyclingCadence: [
                makeSample(.cyclingCadence, value: 88, start: 0, end: 1_200),
                makeSample(.cyclingCadence, value: 87, start: 1_200, end: 2_400)
            ]
        ]))
        let provider = WorkoutSplitDataProvider(fetcher: fetcher)

        let insight = try await provider.insight(for: makeWorkout(), current: makeInput())

        XCTAssertEqual(insight?.splitType, .stableSpeed)
        XCTAssertTrue(insight?.metricRows.contains { $0.title.contains("cadence") } == true)
        XCTAssertEqual(fetcher.fetchCallCount, 1)
    }

    func testEmptySamplesReturnNilToKeepHeuristicFallback() async throws {
        let provider = WorkoutSplitDataProvider(
            fetcher: FakeSplitMetricStreamFetcher(result: .success([:]))
        )

        let insight = try await provider.insight(for: makeWorkout(), current: makeInput())

        XCTAssertNil(insight)
    }

    func testFetchFailureReturnsNilSafely() async throws {
        let provider = WorkoutSplitDataProvider(
            fetcher: FakeSplitMetricStreamFetcher(result: .failure(TestSplitError.fetchFailed))
        )

        let insight = try await provider.insight(for: makeWorkout(), current: makeInput())

        XCTAssertNil(insight)
    }

    private func makeInput() -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .appleHealthKit,
            workoutType: .cycling,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: 40,
            distanceKm: 24,
            averagePaceText: nil,
            averageSpeedKmh: 36,
            averageHeartRate: nil,
            elevationGainMeters: nil,
            activeEnergyKcal: nil
        )
    }

    private func makeWorkout() -> HKWorkout {
        HKWorkout(
            activityType: .cycling,
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_002_400),
            duration: 2_400,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
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

private enum TestSplitError: Error {
    case fetchFailed
}

private final class FakeSplitMetricStreamFetcher: HealthKitWorkoutMetricStreamFetching {
    private let result: Result<[HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]], Error>
    private(set) var fetchCallCount = 0

    init(result: Result<[HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]], Error>) {
        self.result = result
    }

    func fetchMetricSamples(
        for workout: HKWorkout,
        sampleType: HealthKitWorkoutMetricSampleType
    ) async throws -> [HealthKitWorkoutMetricSample] {
        switch result {
        case .success(let samplesByType):
            return samplesByType[sampleType] ?? []
        case .failure(let error):
            throw error
        }
    }

    func fetchZoneMetricSamples(
        for workout: HKWorkout
    ) async throws -> [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]] {
        fetchCallCount += 1
        switch result {
        case .success(let samplesByType):
            return samplesByType
        case .failure(let error):
            throw error
        }
    }
}
