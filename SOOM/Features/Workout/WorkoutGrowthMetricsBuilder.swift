import Foundation

struct WorkoutGrowthMetricsBuilder {
    func build(
        current: WorkoutGrowthInput,
        recent: [WorkoutGrowthInput]
    ) -> [WorkoutGrowthMetric] {
        let baseline = recent
            .filter { $0.id != current.id }
            .filter { $0.startDate <= current.startDate }

        guard !baseline.isEmpty else {
            return insufficientDataMetrics(for: current)
        }

        var metrics: [WorkoutGrowthMetric] = []

        metrics.append(distanceMetric(current: current, baseline: baseline))
        metrics.append(durationMetric(current: current, baseline: baseline))

        if usesPace(current.workoutType) {
            metrics.append(paceMetric(current: current, baseline: baseline))
        } else {
            metrics.append(speedMetric(current: current, baseline: baseline))
        }

        if let elevation = elevationMetric(current: current, baseline: baseline) {
            metrics.append(elevation)
        }

        if let heartRateEfficiency = heartRateEfficiencyMetric(current: current, baseline: baseline) {
            metrics.append(heartRateEfficiency)
        }

        if metrics.count < 3 {
            metrics.append(consistencyMetric(current: current, baseline: baseline))
        }

        return Array(metrics.prefix(5))
    }

    private func distanceMetric(
        current: WorkoutGrowthInput,
        baseline: [WorkoutGrowthInput]
    ) -> WorkoutGrowthMetric {
        guard let distance = current.distanceKm,
              let average = average(baseline.compactMap(\.distanceKm)),
              average > 0 else {
            return metric(
                title: "거리",
                value: current.distanceKm.map(formattedDistance) ?? "-",
                comparison: "거리 기록이 더 쌓이면 최근 흐름과 비교할게요.",
                trend: .insufficientData,
                type: .distance
            )
        }

        let delta = distance - average
        let trend = trend(current: distance, average: average, improvedThreshold: 1.05, lighterThreshold: 0.92)
        let comparison: String
        switch trend {
        case .improved:
            comparison = "최근 평균보다 \(formattedDistance(abs(delta))) 더 길게 움직였어요."
        case .lighter:
            comparison = "최근 평균보다 가볍게 움직인 흐름이에요."
        case .steady:
            comparison = "최근 거리 흐름과 비슷하게 이어졌어요."
        case .insufficientData:
            comparison = "거리 기록이 더 쌓이면 최근 흐름과 비교할게요."
        }

        return metric(
            title: "거리",
            value: formattedDistance(distance),
            comparison: comparison,
            trend: trend,
            type: .distance
        )
    }

    private func durationMetric(
        current: WorkoutGrowthInput,
        baseline: [WorkoutGrowthInput]
    ) -> WorkoutGrowthMetric {
        guard let average = average(baseline.map { Double($0.durationMinutes) }),
              average > 0 else {
            return metric(
                title: "운동 시간",
                value: formattedDuration(current.durationMinutes),
                comparison: "운동 시간이 쌓이면 최근 흐름과 비교할게요.",
                trend: .insufficientData,
                type: .duration
            )
        }

        let duration = Double(current.durationMinutes)
        let trend = trend(current: duration, average: average, improvedThreshold: 1.06, lighterThreshold: 0.88)
        let comparison: String
        switch trend {
        case .improved:
            comparison = "최근 평균보다 조금 더 오래 리듬을 이어갔어요."
        case .lighter:
            comparison = "오늘은 시간보다 몸의 리듬을 유지한 운동에 가까워요."
        case .steady:
            comparison = "최근 운동 시간과 안정적으로 이어졌어요."
        case .insufficientData:
            comparison = "운동 시간이 쌓이면 최근 흐름과 비교할게요."
        }

        return metric(
            title: "운동 시간",
            value: formattedDuration(current.durationMinutes),
            comparison: comparison,
            trend: trend,
            type: .duration
        )
    }

    private func paceMetric(
        current: WorkoutGrowthInput,
        baseline: [WorkoutGrowthInput]
    ) -> WorkoutGrowthMetric {
        guard let currentPace = paceSeconds(for: current),
              let averagePace = average(baseline.compactMap(paceSeconds)),
              averagePace > 0 else {
            return metric(
                title: "페이스",
                value: current.averagePaceText ?? "-",
                comparison: "페이스를 비교하려면 거리와 시간이 더 필요해요.",
                trend: .insufficientData,
                type: .pace
            )
        }

        let trend: WorkoutGrowthMetricTrend
        if currentPace <= averagePace * 0.97 {
            trend = .improved
        } else if currentPace >= averagePace * 1.08 {
            trend = .lighter
        } else {
            trend = .steady
        }

        let comparison: String
        switch trend {
        case .improved:
            comparison = "최근 평균보다 페이스 흐름이 조금 더 가벼웠어요."
        case .lighter:
            comparison = "오늘은 빠른 기록보다 리듬 유지에 가까운 운동이에요."
        case .steady:
            comparison = "최근 페이스 흐름과 비슷하게 안정적이에요."
        case .insufficientData:
            comparison = "페이스를 비교하려면 거리와 시간이 더 필요해요."
        }

        return metric(
            title: "페이스",
            value: formattedPace(currentPace),
            comparison: comparison,
            trend: trend,
            type: .pace
        )
    }

    private func speedMetric(
        current: WorkoutGrowthInput,
        baseline: [WorkoutGrowthInput]
    ) -> WorkoutGrowthMetric {
        guard let speed = speedKmh(for: current),
              let averageSpeed = average(baseline.compactMap(speedKmh)),
              averageSpeed > 0 else {
            return metric(
                title: "평균 속도",
                value: current.averageSpeedKmh.map(formattedSpeed) ?? "-",
                comparison: "속도 흐름을 보려면 거리와 시간이 더 필요해요.",
                trend: .insufficientData,
                type: .speed
            )
        }

        let trend = trend(current: speed, average: averageSpeed, improvedThreshold: 1.03, lighterThreshold: 0.94)
        let comparison: String
        switch trend {
        case .improved:
            comparison = "평균 속도가 최근 흐름보다 조금 더 안정적이었어요."
        case .lighter:
            comparison = "오늘은 속도보다 편안한 리듬을 만든 운동이에요."
        case .steady:
            comparison = "최근 평균 속도와 비슷한 흐름이에요."
        case .insufficientData:
            comparison = "속도 흐름을 보려면 거리와 시간이 더 필요해요."
        }

        return metric(
            title: "평균 속도",
            value: formattedSpeed(speed),
            comparison: comparison,
            trend: trend,
            type: .speed
        )
    }

    private func elevationMetric(
        current: WorkoutGrowthInput,
        baseline: [WorkoutGrowthInput]
    ) -> WorkoutGrowthMetric? {
        guard let elevation = current.elevationGainMeters,
              elevation > 0,
              let averageElevation = average(baseline.compactMap(\.elevationGainMeters)),
              averageElevation > 0 else {
            return nil
        }

        let trend = trend(current: elevation, average: averageElevation, improvedThreshold: 1.10, lighterThreshold: 0.80)
        let comparison: String
        switch trend {
        case .improved:
            comparison = "최근 평균보다 오르막 자극이 조금 더 있었어요."
        case .lighter:
            comparison = "오늘은 고도 부담이 비교적 가벼운 흐름이에요."
        case .steady:
            comparison = "최근 고도 흐름과 비슷하게 이어졌어요."
        case .insufficientData:
            comparison = "상승 고도 기록이 더 쌓이면 비교할게요."
        }

        return metric(
            title: "상승 고도",
            value: "\(Int(elevation.rounded())) m",
            comparison: comparison,
            trend: trend,
            type: .elevation
        )
    }

    private func heartRateEfficiencyMetric(
        current: WorkoutGrowthInput,
        baseline: [WorkoutGrowthInput]
    ) -> WorkoutGrowthMetric? {
        guard let currentEfficiency = heartRateEfficiency(for: current),
              let averageEfficiency = average(baseline.compactMap(heartRateEfficiency)),
              averageEfficiency > 0 else {
            return nil
        }

        let trend = trend(
            current: currentEfficiency,
            average: averageEfficiency,
            improvedThreshold: 1.04,
            lighterThreshold: 0.92
        )
        let comparison: String
        switch trend {
        case .improved:
            comparison = "비슷한 심박에서 움직임 효율이 조금 더 좋아 보였어요."
        case .lighter:
            comparison = "오늘은 효율보다 몸의 리듬을 확인한 운동에 가까워요."
        case .steady:
            comparison = "심박 대비 움직임 흐름이 최근과 비슷해요."
        case .insufficientData:
            comparison = "심박과 거리 기록이 더 쌓이면 비교할게요."
        }

        return metric(
            title: "심박 효율",
            value: String(format: "%.2f km/bpm", currentEfficiency),
            comparison: comparison,
            trend: trend,
            type: .heartRateEfficiency
        )
    }

    private func consistencyMetric(
        current: WorkoutGrowthInput,
        baseline: [WorkoutGrowthInput]
    ) -> WorkoutGrowthMetric {
        let recentCount = baseline.filter {
            Calendar.current.dateComponents([.day], from: $0.startDate, to: current.startDate).day.map { $0 <= 7 } ?? false
        }.count

        return metric(
            title: "꾸준함",
            value: "\(recentCount + 1)회",
            comparison: "최근 기록과 함께 이번 운동도 성장 흐름에 더해졌어요.",
            trend: recentCount >= 2 ? .steady : .insufficientData,
            type: .consistency
        )
    }

    private func insufficientDataMetrics(for current: WorkoutGrowthInput) -> [WorkoutGrowthMetric] {
        [
            metric(
                title: "거리",
                value: current.distanceKm.map(formattedDistance) ?? "-",
                comparison: "비교할 최근 운동이 쌓이면 거리 변화를 보여드릴게요.",
                trend: .insufficientData,
                type: .distance
            ),
            metric(
                title: "운동 시간",
                value: formattedDuration(current.durationMinutes),
                comparison: "오늘 기록은 다음 성장 비교의 기준점이 돼요.",
                trend: .insufficientData,
                type: .duration
            ),
            metric(
                title: usesPace(current.workoutType) ? "페이스" : "평균 속도",
                value: usesPace(current.workoutType)
                    ? current.averagePaceText ?? "-"
                    : current.averageSpeedKmh.map(formattedSpeed) ?? "-",
                comparison: "기록이 더 쌓이면 리듬 변화를 함께 정리할게요.",
                trend: .insufficientData,
                type: usesPace(current.workoutType) ? .pace : .speed
            )
        ]
    }

    private func metric(
        title: String,
        value: String,
        comparison: String,
        trend: WorkoutGrowthMetricTrend,
        type: WorkoutGrowthMetricType
    ) -> WorkoutGrowthMetric {
        WorkoutGrowthMetric(
            title: title,
            valueText: value,
            comparisonText: comparison,
            trend: trend,
            metricType: type
        )
    }

    private func trend(
        current: Double,
        average: Double,
        improvedThreshold: Double,
        lighterThreshold: Double
    ) -> WorkoutGrowthMetricTrend {
        if current >= average * improvedThreshold {
            return .improved
        }

        if current <= average * lighterThreshold {
            return .lighter
        }

        return .steady
    }

    private func paceSeconds(for input: WorkoutGrowthInput) -> Double? {
        guard let distanceKm = input.distanceKm,
              distanceKm > 0,
              input.durationMinutes > 0 else {
            return nil
        }

        return Double(input.durationMinutes * 60) / distanceKm
    }

    private func speedKmh(for input: WorkoutGrowthInput) -> Double? {
        if let speed = input.averageSpeedKmh, speed > 0 {
            return speed
        }

        guard let distance = input.distanceKm,
              distance > 0,
              input.durationMinutes > 0 else {
            return nil
        }

        return distance / (Double(input.durationMinutes) / 60)
    }

    private func heartRateEfficiency(for input: WorkoutGrowthInput) -> Double? {
        guard let speed = speedKmh(for: input),
              let heartRate = input.averageHeartRate,
              heartRate > 0 else {
            return nil
        }

        return speed / heartRate
    }

    private func usesPace(_ type: UnifiedWorkoutType) -> Bool {
        switch type {
        case .running, .walking, .hiking:
            return true
        case .cycling, .swimming, .strength, .yoga, .other:
            return false
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func formattedDistance(_ distance: Double) -> String {
        String(format: "%.1f km", distance)
    }

    private func formattedDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60)시간 \(minutes % 60)분"
        }

        return "\(minutes)분"
    }

    private func formattedPace(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds.rounded()) % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))/km"
    }

    private func formattedSpeed(_ speed: Double) -> String {
        String(format: "%.1f km/h", speed)
    }
}
