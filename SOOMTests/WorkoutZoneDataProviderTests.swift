import HealthKit
import XCTest
@testable import SOOM

final class WorkoutZoneDataProviderTests: XCTestCase {
    func testRunningUsesHeartRateStreamSummary() async throws {
        let fetcher = FakeMetricStreamFetcher(result: .success([
            .heartRate: [
                makeSample(.heartRate, value: 118, start: 0, end: 120),
                makeSample(.heartRate, value: 132, start: 120, end: 300)
            ]
        ]))
        let provider = WorkoutZoneDataProvider(fetcher: fetcher, baselineProvider: { .empty })

        let summaries = try await provider.summaries(for: makeWorkout(), sport: .run)

        XCTAssertEqual(summaries.map(\.type), [.heartRate])
        XCTAssertEqual(summaries.first?.dominantZone?.zoneIndex, 2)
        XCTAssertEqual(fetcher.fetchCallCount, 1)
    }

    func testCyclingUsesHeartRateCadenceAndPowerFallback() async throws {
        let fetcher = FakeMetricStreamFetcher(result: .success([
            .heartRate: [
                makeSample(.heartRate, value: 120, start: 0, end: 90),
                makeSample(.heartRate, value: 145, start: 90, end: 240)
            ],
            .cyclingCadence: [
                makeSample(.cyclingCadence, value: 84, start: 0, end: 240)
            ],
            .cyclingPower: [
                makeSample(.cyclingPower, value: 220, start: 0, end: 240)
            ]
        ]))
        let provider = WorkoutZoneDataProvider(fetcher: fetcher, baselineProvider: { .empty })

        let summaries = try await provider.summaries(for: makeWorkout(), sport: .bike)

        XCTAssertEqual(summaries.map(\.type), [.heartRate, .cadence, .power])
        XCTAssertTrue(summaries.first { $0.type == .heartRate }?.isAvailable == true)
        XCTAssertTrue(summaries.first { $0.type == .cadence }?.isAvailable == true)
        XCTAssertFalse(summaries.first { $0.type == .power }?.isAvailable == true)
        XCTAssertTrue(summaries.first { $0.type == .power }?.insightText?.contains("FTP") == true)
    }

    func testCyclingPowerUnavailableFallbackAppearsWhenOtherStreamDataExists() async throws {
        let fetcher = FakeMetricStreamFetcher(result: .success([
            .heartRate: [makeSample(.heartRate, value: 125, start: 0, end: 180)],
            .cyclingCadence: [makeSample(.cyclingCadence, value: 88, start: 0, end: 180)]
        ]))
        let provider = WorkoutZoneDataProvider(fetcher: fetcher, baselineProvider: { .empty })

        let summaries = try await provider.summaries(for: makeWorkout(), sport: .bike)
        let power = summaries.first { $0.type == .power }

        XCTAssertNotNil(power)
        XCTAssertFalse(power?.isAvailable == true)
        XCTAssertTrue(power?.insightText?.contains("파워존") == true || power?.insightText?.contains("FTP") == true)
    }

    func testCyclingUsesSettingsBaselineForPowerZones() async throws {
        let fetcher = FakeMetricStreamFetcher(result: .success([
            .heartRate: [makeSample(.heartRate, value: 145, start: 0, end: 180)],
            .cyclingPower: [
                makeSample(.cyclingPower, value: 120, start: 0, end: 60),
                makeSample(.cyclingPower, value: 240, start: 60, end: 180)
            ]
        ]))
        let provider = WorkoutZoneDataProvider(
            fetcher: fetcher,
            baselineProvider: { PersonalizedZoneBaseline(maxHeartRate: 200, cyclingFTP: 250) }
        )

        let summaries = try await provider.summaries(for: makeWorkout(), sport: .bike)
        let heartRate = summaries.first { $0.type == .heartRate }
        let power = summaries.first { $0.type == .power }

        XCTAssertEqual(heartRate?.baselineDescription, "최대심박 기준")
        XCTAssertEqual(power?.dominantZone?.zoneIndex, 4)
        XCTAssertEqual(power?.baselineDescription, "FTP 기준")
        XCTAssertTrue(power?.isPersonalized == true)
    }

    func testEmptySamplesReturnEmptyToKeepFallbackFlow() async throws {
        let fetcher = FakeMetricStreamFetcher(result: .success([:]))
        let provider = WorkoutZoneDataProvider(fetcher: fetcher, baselineProvider: { .empty })

        let summaries = try await provider.summaries(for: makeWorkout(), sport: .bike)

        XCTAssertTrue(summaries.isEmpty)
    }

    func testFetchFailureRemainsAnErrorInsteadOfMissingMeasurements() async throws {
        let fetcher = FakeMetricStreamFetcher(result: .failure(TestError.fetchFailed))
        let provider = WorkoutZoneDataProvider(fetcher: fetcher, baselineProvider: { .empty })

        do {
            _ = try await provider.summaries(for: makeWorkout(), sport: .bike)
            XCTFail("A failed query must not become an empty success")
        } catch { XCTAssertTrue(error is TestError) }
    }

    func testProviderDoesNotInvokeRecoveryCalculator() async throws {
        let fetcher = FakeMetricStreamFetcher(result: .success([
            .heartRate: [makeSample(.heartRate, value: 130, start: 0, end: 120)]
        ]))
        let provider = WorkoutZoneDataProvider(fetcher: fetcher, baselineProvider: { .empty })

        let summaries = try await provider.summaries(for: makeWorkout(), sport: .run)

        XCTAssertEqual(summaries.map(\.type), [.heartRate])
    }

    private func makeWorkout() -> HKWorkout {
        HKWorkout(
            activityType: .cycling,
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_003_600),
            duration: 3_600,
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
            unit: type == .cyclingPower ? "watt" : "count/min",
            startDate: Date(timeIntervalSince1970: 1_800_000_000 + start),
            endDate: Date(timeIntervalSince1970: 1_800_000_000 + end)
        )
    }
}

private enum TestError: Error {
    case fetchFailed
}

private final class FakeMetricStreamFetcher: HealthKitWorkoutMetricStreamFetching {
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

extension WorkoutZoneDataProviderTests {
    func testOptionalStreamFailureDoesNotDiscardAlreadyFetchedHeartRate() async throws {
        let heart = makeSample(.heartRate, value: 130, start: 0, end: 120)
        let result = try await HealthKitWorkoutMetricStreamFetcher.collectZoneMetrics { type in
            if type == .heartRate { return [heart] }
            throw TestError.fetchFailed
        }
        XCTAssertEqual(result[.heartRate], [heart]); XCTAssertNil(result[.cyclingCadence]); XCTAssertNil(result[.cyclingPower])
        let summaries = WorkoutZoneDataProvider(baselineProvider: { .empty }).makeSummaries(from: result, sport: .run)
        XCTAssertEqual(summaries.first?.zones.first(where: { $0.zoneIndex == 2 })?.durationSeconds, 120)
    }
    func testAllStreamFailuresStillThrowAndCancellationStopsBatch() async {
        do {
            _ = try await HealthKitWorkoutMetricStreamFetcher.collectZoneMetrics { _ in throw TestError.fetchFailed }
            XCTFail("All failures must not appear as a successful empty query")
        } catch {}
        var calls = 0
        do {
            _ = try await HealthKitWorkoutMetricStreamFetcher.collectZoneMetrics { _ in calls += 1; throw CancellationError() }
            XCTFail("Cancellation must propagate")
        } catch is CancellationError { XCTAssertEqual(calls, 1) }
        catch { XCTFail("Unexpected error") }
    }
}

extension WorkoutZoneDataProviderTests {
    func testCancellationIsNotAnEmptySuccessfulRead() async {
        let fetcher = FakeMetricStreamFetcher(result: .failure(CancellationError()))
        do {
            _ = try await WorkoutZoneDataProvider(fetcher: fetcher).summaries(for: makeWorkout(), sport: .swim)
            XCTFail("Cancellation must reach the detail lifecycle")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
