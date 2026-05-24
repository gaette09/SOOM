import Foundation
import HealthKit

protocol WorkoutSplitDataProviding {
    func insight(for workout: HKWorkout, current: WorkoutGrowthInput) async throws -> WorkoutSplitInsight?
}

struct WorkoutSplitDataProvider: WorkoutSplitDataProviding {
    private let fetcher: HealthKitWorkoutMetricStreamFetching
    private let streamBuilder: WorkoutSplitStreamBuilder
    private let insightBuilder: WorkoutSplitInsightBuilder

    init(
        fetcher: HealthKitWorkoutMetricStreamFetching = HealthKitWorkoutMetricStreamFetcher(),
        streamBuilder: WorkoutSplitStreamBuilder = WorkoutSplitStreamBuilder(),
        insightBuilder: WorkoutSplitInsightBuilder = WorkoutSplitInsightBuilder()
    ) {
        self.fetcher = fetcher
        self.streamBuilder = streamBuilder
        self.insightBuilder = insightBuilder
    }

    func insight(for workout: HKWorkout, current: WorkoutGrowthInput) async throws -> WorkoutSplitInsight? {
        do {
            let samplesByType = try await fetcher.fetchZoneMetricSamples(for: workout)
            let splitMetrics = streamBuilder.build(current: current, samplesByType: samplesByType)

            guard streamBuilder.hasUsefulStreamData(splitMetrics) else {
                return nil
            }

            return insightBuilder.build(current: current, splitMetrics: splitMetrics)
        } catch {
            return nil
        }
    }
}
