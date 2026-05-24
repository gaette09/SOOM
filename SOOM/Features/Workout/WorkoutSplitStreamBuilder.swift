import Foundation

struct WorkoutSplitStreamBuilder {
    func build(
        current: WorkoutGrowthInput,
        samplesByType: [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]],
        splitCount: Int = 2
    ) -> [WorkoutSplitMetric] {
        let safeSplitCount = max(splitCount, 2)
        let durationSeconds = TimeInterval(max(current.durationMinutes, 0) * 60)
        guard durationSeconds > 0 else { return [] }

        let startDate = current.startDate
        let splitDuration = durationSeconds / Double(safeSplitCount)
        let totalDistanceMeters = current.distanceKm.map { $0 * 1_000 }

        return (0..<safeSplitCount).map { index in
            let splitStart = startDate.addingTimeInterval(Double(index) * splitDuration)
            let splitEnd = index == safeSplitCount - 1
                ? startDate.addingTimeInterval(durationSeconds)
                : splitStart.addingTimeInterval(splitDuration)
            let splitDistance = totalDistanceMeters.map { $0 / Double(safeSplitCount) }
            let splitAverageSpeed = current.averageSpeedKmh
            let splitAveragePace = splitDistance.flatMap { distanceMeters -> TimeInterval? in
                guard distanceMeters > 0 else { return nil }
                return splitDuration / (distanceMeters / 1_000)
            }

            return WorkoutSplitMetric(
                splitIndex: index,
                startTime: splitStart,
                endTime: splitEnd,
                averagePace: splitAveragePace,
                averageSpeed: splitAverageSpeed,
                averageCadence: weightedAverage(samplesByType[.cyclingCadence] ?? [], from: splitStart, to: splitEnd),
                averageHeartRate: weightedAverage(samplesByType[.heartRate] ?? [], from: splitStart, to: splitEnd),
                averagePower: weightedAverage(samplesByType[.cyclingPower] ?? [], from: splitStart, to: splitEnd),
                distanceMeters: splitDistance
            )
        }
    }

    func hasUsefulStreamData(_ metrics: [WorkoutSplitMetric]) -> Bool {
        metrics.contains { metric in
            metric.averageCadence != nil || metric.averageHeartRate != nil || metric.averagePower != nil
        }
    }

    private func weightedAverage(
        _ samples: [HealthKitWorkoutMetricSample],
        from splitStart: Date,
        to splitEnd: Date
    ) -> Double? {
        var weightedValue = 0.0
        var totalDuration = 0.0

        for sample in samples {
            let overlapStart = max(sample.startDate, splitStart)
            let overlapEnd = min(sample.endDate, splitEnd)
            let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)

            guard overlapDuration > 0 else { continue }
            weightedValue += sample.value * overlapDuration
            totalDuration += overlapDuration
        }

        guard totalDuration > 0 else { return nil }
        return weightedValue / totalDuration
    }
}
