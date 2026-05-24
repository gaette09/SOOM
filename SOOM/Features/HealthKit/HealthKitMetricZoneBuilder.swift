import Foundation

struct HealthKitMetricZoneBuilder {
    private let zoneBuilder: WorkoutZoneBuilder
    private let fallbackMaxHeartRate: Double

    init(
        zoneBuilder: WorkoutZoneBuilder = WorkoutZoneBuilder(),
        fallbackMaxHeartRate: Double = 190
    ) {
        self.zoneBuilder = zoneBuilder
        self.fallbackMaxHeartRate = fallbackMaxHeartRate
    }

    func buildHeartRateSummary(
        from samples: [HealthKitWorkoutMetricSample],
        maxHeartRate: Double? = nil
    ) -> WorkoutZoneSummary {
        let maximumHeartRate = maxHeartRate ?? fallbackMaxHeartRate
        let durations = aggregateDurations(
            samples: samples.filter { $0.sampleType == .heartRate },
            type: .heartRate
        ) { sample in
            heartRateZoneIndex(value: sample.value, maxHeartRate: maximumHeartRate)
        }

        return zoneBuilder.buildSummary(type: .heartRate, durations: durations)
    }

    func buildCyclingCadenceSummary(
        from samples: [HealthKitWorkoutMetricSample]
    ) -> WorkoutZoneSummary {
        let durations = aggregateDurations(
            samples: samples.filter { $0.sampleType == .cyclingCadence },
            type: .cadence
        ) { sample in
            cyclingCadenceZoneIndex(value: sample.value)
        }

        return zoneBuilder.buildSummary(type: .cadence, durations: durations)
    }

    func buildCyclingPowerSummary(
        from samples: [HealthKitWorkoutMetricSample],
        ftp: Double? = nil
    ) -> WorkoutZoneSummary {
        guard let ftp, ftp > 0 else {
            return zoneBuilder.unavailableSummary(type: .power)
        }

        let durations = aggregateDurations(
            samples: samples.filter { $0.sampleType == .cyclingPower },
            type: .power
        ) { sample in
            cyclingPowerZoneIndex(value: sample.value, ftp: ftp)
        }

        return zoneBuilder.buildSummary(type: .power, durations: durations)
    }

    func buildSummaries(
        from samplesByType: [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]],
        maxHeartRate: Double? = nil,
        ftp: Double? = nil
    ) -> [WorkoutZoneSummary] {
        [
            buildHeartRateSummary(from: samplesByType[.heartRate] ?? [], maxHeartRate: maxHeartRate),
            buildCyclingCadenceSummary(from: samplesByType[.cyclingCadence] ?? []),
            buildCyclingPowerSummary(from: samplesByType[.cyclingPower] ?? [], ftp: ftp)
        ]
    }

    private func aggregateDurations(
        samples: [HealthKitWorkoutMetricSample],
        type: WorkoutZoneType,
        zoneIndex: (HealthKitWorkoutMetricSample) -> Int
    ) -> [WorkoutZoneDurationInput] {
        guard !samples.isEmpty else { return [] }

        var durationsByZone: [Int: TimeInterval] = [:]
        for sample in samples {
            let safeDuration = max(sample.durationSeconds, 1)
            durationsByZone[zoneIndex(sample), default: 0] += safeDuration
        }

        return durationsByZone.keys.sorted().map { index in
            WorkoutZoneDurationInput(
                zoneIndex: index,
                durationSeconds: durationsByZone[index] ?? 0,
                rangeDescription: rangeDescription(type: type, zoneIndex: index)
            )
        }
    }

    private func heartRateZoneIndex(value: Double, maxHeartRate: Double) -> Int {
        guard maxHeartRate > 0 else { return 1 }
        let ratio = value / maxHeartRate

        switch ratio {
        case ..<0.60:
            return 1
        case ..<0.70:
            return 2
        case ..<0.80:
            return 3
        case ..<0.90:
            return 4
        default:
            return 5
        }
    }

    private func cyclingCadenceZoneIndex(value: Double) -> Int {
        switch value {
        case ..<70:
            return 1
        case ...95:
            return 2
        default:
            return 3
        }
    }

    private func cyclingPowerZoneIndex(value: Double, ftp: Double) -> Int {
        let ratio = value / ftp

        switch ratio {
        case ..<0.55:
            return 1
        case ..<0.75:
            return 2
        case ..<0.90:
            return 3
        case ..<1.05:
            return 4
        case ..<1.20:
            return 5
        case ..<1.50:
            return 6
        default:
            return 7
        }
    }

    private func rangeDescription(type: WorkoutZoneType, zoneIndex: Int) -> String? {
        switch (type, zoneIndex) {
        case (.heartRate, 1): return "Z1 가벼운 흐름"
        case (.heartRate, 2): return "Z2 안정 흐름"
        case (.heartRate, 3): return "Z3 템포 흐름"
        case (.heartRate, 4): return "Z4 높은 흐름"
        case (.heartRate, 5): return "Z5 짧은 고강도"
        case (.cadence, 1): return "낮은 리듬"
        case (.cadence, 2): return "안정 리듬"
        case (.cadence, 3): return "빠른 리듬"
        case (.power, 1): return "Z1 회복 파워"
        case (.power, 2): return "Z2 지속 파워"
        case (.power, 3): return "Z3 템포 파워"
        case (.power, 4): return "Z4 임계 파워"
        case (.power, 5): return "Z5 높은 파워"
        case (.power, 6): return "Z6 짧은 고출력"
        case (.power, 7): return "Z7 스프린트"
        default: return nil
        }
    }
}
