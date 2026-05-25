import Foundation

struct ProgressionIntelligenceBuilder {
    func build(
        workouts: [Workout],
        period: ProgressionPeriod = .rollingFourWeeks,
        referenceDate: Date = Date()
    ) -> ProgressionIntelligence {
        let inputs = workouts.map { workout in
            WorkoutGrowthInput(
                id: workout.id,
                source: .soomLocal,
                workoutType: workout.sport == .bike ? .cycling : workout.sport == .swim ? .swimming : .running,
                startDate: workout.date,
                durationMinutes: max(Int((workout.duration / 60).rounded()), 1),
                distanceKm: workout.distanceMeters / 1_000,
                averagePaceText: nil,
                averageSpeedKmh: nil,
                averageHeartRate: Double(workout.avgHeartRate),
                elevationGainMeters: Double(workout.elevationGain),
                activeEnergyKcal: Double(workout.activeCalories)
            )
        }

        return build(inputs: inputs, period: period, referenceDate: referenceDate)
    }

    func build(
        inputs: [WorkoutGrowthInput],
        period: ProgressionPeriod = .rollingFourWeeks,
        referenceDate: Date = Date()
    ) -> ProgressionIntelligence {
        let windowStart = Calendar.current.date(
            byAdding: .day,
            value: -period.dayCount,
            to: Calendar.current.startOfDay(for: referenceDate)
        ) ?? referenceDate

        let windowInputs = inputs
            .filter { $0.startDate >= windowStart && $0.startDate <= referenceDate }
            .sorted { $0.startDate < $1.startDate }

        guard windowInputs.count >= 3, let workoutType = dominantWorkoutType(in: windowInputs) else {
            return .insufficientData(period: period)
        }

        let sportInputs = windowInputs.filter { $0.workoutType == workoutType }
        let samples = sportInputs.compactMap { sample(for: $0, workoutType: workoutType) }
        guard samples.count >= 3 else {
            return .insufficientData(period: period)
        }

        let midpoint = Calendar.current.date(
            byAdding: .day,
            value: -(period.dayCount / 2),
            to: referenceDate
        ) ?? referenceDate
        let previous = samples.filter { $0.date < midpoint }
        let recent = samples.filter { $0.date >= midpoint }
        guard !recent.isEmpty else {
            return .insufficientData(period: period)
        }

        if previous.count <= 1, recent.count >= 2 {
            return makeIntelligence(
                period: period,
                workoutType: workoutType,
                samples: samples,
                previous: previous,
                recent: recent,
                trendType: .rebuilding,
                summary: "최근 운동 빈도가 다시 살아나고 있어요.",
                insight: "아직 긴 흐름을 단정하기보다는, 다시 움직임을 쌓는 과정으로 보는 게 좋아요."
            )
        }

        guard !previous.isEmpty else {
            return .insufficientData(period: period)
        }

        let previousAverage = average(previous.map(\.metricValue))
        let recentAverage = average(recent.map(\.metricValue))
        guard previousAverage > 0, recentAverage > 0 else {
            return .insufficientData(period: period)
        }

        let improvementRate = metricImprovementRate(
            previousAverage: previousAverage,
            recentAverage: recentAverage,
            lowerIsBetter: samples.first?.lowerIsBetter ?? false
        )
        let stability = coefficientOfVariation(samples.map(\.metricValue))
        let frequencyDrop = recent.count < max(1, previous.count - 1)

        if improvementRate >= 0.04 && !frequencyDrop {
            return makeIntelligence(
                period: period,
                workoutType: workoutType,
                samples: samples,
                previous: previous,
                recent: recent,
                trendType: .improving,
                summary: "최근 흐름에서 움직임의 질이 조금씩 좋아지고 있어요.",
                insight: "페이스나 속도 변화가 완만하게 좋아지는 쪽으로 이어지고 있어요. 지금처럼 리듬을 유지해도 좋아요."
            )
        }

        if improvementRate <= -0.08 || stability > 0.12 || frequencyDrop {
            return makeIntelligence(
                period: period,
                workoutType: workoutType,
                samples: samples,
                previous: previous,
                recent: recent,
                trendType: .fluctuating,
                summary: "최근 흐름에는 가벼운 변화가 섞여 있어요.",
                insight: "운동마다 리듬 차이가 조금 있어요. 기록을 평가하기보다 어떤 날에 흐름이 편했는지 살펴보면 좋아요."
            )
        }

        return makeIntelligence(
            period: period,
            workoutType: workoutType,
            samples: samples,
            previous: previous,
            recent: recent,
            trendType: .stable,
            summary: "최근 운동 리듬이 안정적으로 이어지고 있어요.",
            insight: "큰 변화가 없어도 비슷한 리듬으로 반복된 기록은 장기 성장을 만드는 좋은 기반이에요."
        )
    }

    private func makeIntelligence(
        period: ProgressionPeriod,
        workoutType: UnifiedWorkoutType,
        samples: [ProgressionSample],
        previous: [ProgressionSample],
        recent: [ProgressionSample],
        trendType: ProgressionTrendType,
        summary: String,
        insight: String
    ) -> ProgressionIntelligence {
        let recentAverage = average(recent.map(\.metricValue))
        let previousAverage = previous.isEmpty ? nil : average(previous.map(\.metricValue))
        let stability = coefficientOfVariation(samples.map(\.metricValue))
        let confidence = min(1, Double(samples.count) / 8)

        return ProgressionIntelligence(
            period: period,
            trend: ProgressionTrend(
                trendType: trendType,
                summary: summary,
                confidence: confidence
            ),
            metricRows: [
                ProgressionIntelligenceMetricRow(
                    title: primaryMetricTitle(for: workoutType),
                    valueText: formattedMetric(recentAverage, for: workoutType),
                    comparisonText: comparisonText(previousAverage: previousAverage, recentAverage: recentAverage, lowerIsBetter: samples.first?.lowerIsBetter ?? false)
                ),
                ProgressionIntelligenceMetricRow(
                    title: "운동 빈도",
                    valueText: "\(samples.count)회",
                    comparisonText: "\(period.title) 동안 쌓인 기록이에요."
                ),
                ProgressionIntelligenceMetricRow(
                    title: "리듬 안정성",
                    valueText: stability < 0.08 ? "안정적" : "변화 있음",
                    comparisonText: stability < 0.08 ? "운동마다 흐름이 비슷하게 이어졌어요." : "운동마다 컨디션과 코스 차이가 조금 있었어요."
                )
            ],
            insightSummary: insight
        )
    }

    private func sample(for input: WorkoutGrowthInput, workoutType: UnifiedWorkoutType) -> ProgressionSample? {
        guard let distanceKm = input.distanceKm, distanceKm > 0, input.durationMinutes > 0 else {
            return nil
        }

        switch workoutType {
        case .running, .walking, .hiking:
            let paceSeconds = Double(input.durationMinutes * 60) / distanceKm
            return ProgressionSample(date: input.startDate, metricValue: paceSeconds, lowerIsBetter: true)
        case .cycling:
            let speed = input.averageSpeedKmh ?? distanceKm / (Double(input.durationMinutes) / 60)
            guard speed > 0 else { return nil }
            return ProgressionSample(date: input.startDate, metricValue: speed, lowerIsBetter: false)
        case .swimming:
            let pace100m = (Double(input.durationMinutes * 60) / distanceKm) / 10
            return ProgressionSample(date: input.startDate, metricValue: pace100m, lowerIsBetter: true)
        case .strength, .yoga, .other:
            return nil
        }
    }

    private func dominantWorkoutType(in inputs: [WorkoutGrowthInput]) -> UnifiedWorkoutType? {
        let supportedTypes: [UnifiedWorkoutType] = [.running, .cycling, .swimming, .walking, .hiking]
        return supportedTypes.max { lhs, rhs in
            inputs.filter { $0.workoutType == lhs }.count < inputs.filter { $0.workoutType == rhs }.count
        }.flatMap { type in
            inputs.contains { $0.workoutType == type } ? type : nil
        }
    }

    private func metricImprovementRate(previousAverage: Double, recentAverage: Double, lowerIsBetter: Bool) -> Double {
        if lowerIsBetter {
            return (previousAverage - recentAverage) / previousAverage
        }
        return (recentAverage - previousAverage) / previousAverage
    }

    private func comparisonText(previousAverage: Double?, recentAverage: Double, lowerIsBetter: Bool) -> String {
        guard let previousAverage, previousAverage > 0 else {
            return "비교 기준이 더 쌓이면 변화 폭도 함께 보여드릴게요."
        }

        let improvement = metricImprovementRate(previousAverage: previousAverage, recentAverage: recentAverage, lowerIsBetter: lowerIsBetter)
        if improvement >= 0.04 {
            return "이전 흐름보다 조금 더 좋아졌어요."
        }
        if improvement <= -0.08 {
            return "최근에는 조금 가볍게 이어진 흐름이에요."
        }
        return "이전 흐름과 비슷하게 안정적이에요."
    }

    private func primaryMetricTitle(for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .running, .walking, .hiking:
            return "평균 페이스"
        case .cycling:
            return "평균 속도"
        case .swimming:
            return "100m 페이스"
        case .strength, .yoga, .other:
            return "운동 흐름"
        }
    }

    private func formattedMetric(_ value: Double, for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .running, .walking, .hiking:
            return formattedPace(seconds: value, suffix: "/km")
        case .cycling:
            return String(format: "%.1f km/h", value)
        case .swimming:
            return formattedPace(seconds: value, suffix: "/100m")
        case .strength, .yoga, .other:
            return "-"
        }
    }

    private func formattedPace(seconds: Double, suffix: String) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))\(suffix)"
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func coefficientOfVariation(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = average(values)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        return sqrt(variance) / mean
    }
}

private struct ProgressionSample {
    let date: Date
    let metricValue: Double
    let lowerIsBetter: Bool
}
