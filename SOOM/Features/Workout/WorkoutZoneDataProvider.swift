import Foundation
import HealthKit

protocol WorkoutZoneDataProviding {
    func summaries(for workout: HKWorkout, sport: WorkoutSport) async throws -> [WorkoutZoneSummary]
}

struct WorkoutZoneDataProvider: WorkoutZoneDataProviding {
    private let fetcher: HealthKitWorkoutMetricStreamFetching
    private let zoneBuilder: HealthKitMetricZoneBuilder

    init(
        fetcher: HealthKitWorkoutMetricStreamFetching = HealthKitWorkoutMetricStreamFetcher(),
        zoneBuilder: HealthKitMetricZoneBuilder = HealthKitMetricZoneBuilder()
    ) {
        self.fetcher = fetcher
        self.zoneBuilder = zoneBuilder
    }

    func summaries(for workout: HKWorkout, sport: WorkoutSport) async throws -> [WorkoutZoneSummary] {
        do {
            let samplesByType = try await fetcher.fetchZoneMetricSamples(for: workout)
            return makeSummaries(from: samplesByType, sport: sport)
        } catch {
            return []
        }
    }

    func makeSummaries(
        from samplesByType: [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]],
        sport: WorkoutSport
    ) -> [WorkoutZoneSummary] {
        var summaries: [WorkoutZoneSummary] = []
        var hasAvailableStreamSummary = false

        func append(_ summary: WorkoutZoneSummary, includeUnavailable: Bool = false) {
            if summary.isAvailable {
                hasAvailableStreamSummary = true
                summaries.append(summary)
            } else if includeUnavailable {
                summaries.append(summary)
            }
        }

        let heartRate = zoneBuilder.buildHeartRateSummary(from: samplesByType[.heartRate] ?? [])
        append(heartRate, includeUnavailable: WorkoutZoneSection.shouldShowUnavailable(.heartRate, for: sport))

        switch sport {
        case .run:
            let cadence = zoneBuilder.buildCyclingCadenceSummary(from: samplesByType[.cyclingCadence] ?? [])
            append(cadence)
        case .bike, .brick:
            let cadence = zoneBuilder.buildCyclingCadenceSummary(from: samplesByType[.cyclingCadence] ?? [])
            append(cadence)

            let power = zoneBuilder.buildCyclingPowerSummary(from: samplesByType[.cyclingPower] ?? [])
            append(power, includeUnavailable: true)
        case .swim:
            break
        }

        return hasAvailableStreamSummary ? summaries : []
    }
}
