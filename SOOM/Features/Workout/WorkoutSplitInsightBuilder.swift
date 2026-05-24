import Foundation

struct WorkoutSplitInsightBuilder {
    func build(current: WorkoutGrowthInput, splitMetrics: [WorkoutSplitMetric]? = nil) -> WorkoutSplitInsight {
        if let streamInsight = buildStreamInsight(current: current, splitMetrics: splitMetrics ?? []) {
            return streamInsight
        }

        guard current.durationMinutes >= 10,
              let distanceKm = current.distanceKm,
              distanceKm > 0 else {
            return .insufficientData
        }

        switch current.workoutType {
        case .running, .walking, .hiking:
            return buildPaceInsight(
                current: current,
                distanceKm: distanceKm,
                paceSuffix: "/km",
                fatiguePaceSeconds: current.workoutType == .walking ? 900 : 420
            )
        case .cycling:
            return buildCyclingInsight(current: current, distanceKm: distanceKm)
        case .swimming:
            return buildSwimInsight(current: current, distanceKm: distanceKm)
        case .strength, .yoga, .other:
            return buildDurationInsight(current: current)
        }
    }

    private func buildPaceInsight(
        current: WorkoutGrowthInput,
        distanceKm: Double,
        paceSuffix: String,
        fatiguePaceSeconds: Double
    ) -> WorkoutSplitInsight {
        let paceSeconds = Double(current.durationMinutes * 60) / distanceKm
        let isLongSession = current.durationMinutes >= 75
        let isHeavyRhythm = paceSeconds >= fatiguePaceSeconds || (current.averageHeartRate ?? 0) >= 168

        if isLongSession && isHeavyRhythm {
            return WorkoutSplitInsight(
                title: "후반 리듬을 살펴볼 만한 운동이에요",
                summary: "긴 운동이라 마지막 구간의 흐름을 조금 더 부드럽게 가져가면 좋아요.",
                splitType: .fatigueDrop,
                trend: .lighter,
                metricRows: [
                    WorkoutSplitMetricRow(
                        title: "평균 페이스",
                        valueText: formattedPace(paceSeconds, suffix: paceSuffix),
                        detailText: "긴 세션 기준으로 후반 리듬을 가볍게 점검했어요."
                    ),
                    WorkoutSplitMetricRow(
                        title: "후반 흐름",
                        valueText: "완만한 조절",
                        detailText: "다음에는 마지막 구간을 조금 더 차분히 이어가면 좋아요."
                    )
                ]
            )
        }

        return WorkoutSplitInsight(
            title: "운동 리듬이 안정적으로 이어졌어요",
            summary: "전반적인 페이스 흐름이 무리 없이 이어진 운동에 가까워요.",
            splitType: .stablePace,
            trend: .stable,
            metricRows: [
                WorkoutSplitMetricRow(
                    title: "평균 페이스",
                    valueText: formattedPace(paceSeconds, suffix: paceSuffix),
                    detailText: "전체 리듬을 안정적으로 유지했어요."
                ),
                WorkoutSplitMetricRow(
                    title: "후반 흐름",
                    valueText: "안정",
                    detailText: "마지막까지 비슷한 호흡으로 이어가기 좋은 흐름이에요."
                )
            ]
        )
    }

    private func buildCyclingInsight(current: WorkoutGrowthInput, distanceKm: Double) -> WorkoutSplitInsight {
        let speed = current.averageSpeedKmh ?? distanceKm / (Double(current.durationMinutes) / 60)
        let isLongRide = current.durationMinutes >= 120
        let isGentleSpeed = speed < 18

        if isLongRide && isGentleSpeed {
            return WorkoutSplitInsight(
                title: "후반 속도 흐름을 살펴볼 만해요",
                summary: "긴 라이딩에서는 마지막 구간의 회전 리듬을 조금 더 편안하게 가져가면 좋아요.",
                splitType: .fatigueDrop,
                trend: .lighter,
                metricRows: [
                    WorkoutSplitMetricRow(
                        title: "평균 속도",
                        valueText: formattedSpeed(speed),
                        detailText: "긴 거리 기준으로 속도 흐름을 가볍게 점검했어요."
                    ),
                    WorkoutSplitMetricRow(
                        title: "후반 리듬",
                        valueText: "조절",
                        detailText: "초반 힘 배분을 조금 더 부드럽게 가져갈 여지가 있어요."
                    )
                ]
            )
        }

        return WorkoutSplitInsight(
            title: "속도 리듬이 안정적으로 이어졌어요",
            summary: "평균 속도 흐름이 흔들림 없이 유지된 라이딩에 가까워요.",
            splitType: .stableSpeed,
            trend: .stable,
            metricRows: [
                WorkoutSplitMetricRow(
                    title: "평균 속도",
                    valueText: formattedSpeed(speed),
                    detailText: "전체 구간에서 일정한 리듬을 만들기 좋은 흐름이에요."
                ),
                WorkoutSplitMetricRow(
                    title: "후반 흐름",
                    valueText: "안정",
                    detailText: "속도보다 리듬을 유지한 점이 좋은 신호예요."
                )
            ]
        )
    }

    private func buildSwimInsight(current: WorkoutGrowthInput, distanceKm: Double) -> WorkoutSplitInsight {
        let pace100m = Double(current.durationMinutes * 60) / (distanceKm * 10)

        return WorkoutSplitInsight(
            title: "물속 리듬을 차분히 이어갔어요",
            summary: "100m 기준 페이스를 바탕으로 세션 흐름을 가볍게 확인했어요.",
            splitType: .stablePace,
            trend: .stable,
            metricRows: [
                WorkoutSplitMetricRow(
                    title: "100m 페이스",
                    valueText: formattedPace(pace100m, suffix: "/100m"),
                    detailText: "세션 전체의 물속 리듬을 보여주는 기준이에요."
                ),
                WorkoutSplitMetricRow(
                    title: "세션 흐름",
                    valueText: "안정",
                    detailText: "기록이 더 쌓이면 후반 페이스도 함께 비교해볼게요."
                )
            ]
        )
    }

    private func buildDurationInsight(current: WorkoutGrowthInput) -> WorkoutSplitInsight {
        WorkoutSplitInsight(
            title: "운동 흐름을 기록했어요",
            summary: "이 종목은 시간 흐름을 중심으로 세션 리듬을 가볍게 확인합니다.",
            splitType: .stablePace,
            trend: .stable,
            metricRows: [
                WorkoutSplitMetricRow(
                    title: "운동 시간",
                    valueText: "\(current.durationMinutes)분",
                    detailText: "꾸준히 움직인 시간을 기준으로 흐름을 봤어요."
                )
            ]
        )
    }

    private func buildStreamInsight(current: WorkoutGrowthInput, splitMetrics: [WorkoutSplitMetric]) -> WorkoutSplitInsight? {
        guard splitMetrics.count >= 2 else { return nil }
        let orderedMetrics = splitMetrics.sorted { $0.splitIndex < $1.splitIndex }
        guard let first = orderedMetrics.first, let last = orderedMetrics.last else { return nil }

        if let cadenceInsight = buildCadenceStreamInsight(current: current, first: first, last: last) {
            return cadenceInsight
        }
        if let speedInsight = buildSpeedStreamInsight(first: first, last: last) {
            return speedInsight
        }
        if let paceInsight = buildPaceStreamInsight(current: current, first: first, last: last) {
            return paceInsight
        }
        if let heartRateInsight = buildHeartRateStreamInsight(current: current, first: first, last: last) {
            return heartRateInsight
        }
        return nil
    }

    private func buildCadenceStreamInsight(
        current: WorkoutGrowthInput,
        first: WorkoutSplitMetric,
        last: WorkoutSplitMetric
    ) -> WorkoutSplitInsight? {
        guard let firstCadence = first.averageCadence,
              let lastCadence = last.averageCadence,
              firstCadence > 0 else { return nil }

        let ratio = lastCadence / firstCadence
        let rows = [
            WorkoutSplitMetricRow(title: "전반 cadence", valueText: formattedCadence(firstCadence), detailText: "초반 리듬을 보여주는 센서 기준이에요."),
            WorkoutSplitMetricRow(title: "후반 cadence", valueText: formattedCadence(lastCadence), detailText: "마지막 구간의 회전 리듬을 함께 봤어요.")
        ]

        if ratio < 0.90 {
            return WorkoutSplitInsight(
                title: "후반 cadence가 조금 차분해졌어요",
                summary: "센서 흐름 기준으로 마지막 구간의 회전 리듬이 부드럽게 낮아진 운동이에요.",
                splitType: .fatigueDrop,
                trend: .lighter,
                metricRows: rows + [WorkoutSplitMetricRow(title: "리듬 변화", valueText: formattedPercentChange(ratio - 1), detailText: "다음에는 초반 회전 리듬을 조금 더 여유 있게 가져가도 좋아요.")]
            )
        }

        if ratio > 1.05 {
            return WorkoutSplitInsight(
                title: "후반 cadence를 잘 이어갔어요",
                summary: "후반으로 갈수록 회전 리듬이 조금 더 살아난 흐름이에요.",
                splitType: .negativeSplit,
                trend: .improving,
                metricRows: rows + [WorkoutSplitMetricRow(title: "리듬 변화", valueText: formattedPercentChange(ratio - 1), detailText: "마지막 구간까지 움직임의 흐름을 이어간 점이 좋아요.")]
            )
        }

        return WorkoutSplitInsight(
            title: "cadence 리듬이 안정적으로 이어졌어요",
            summary: "전반과 후반의 회전 리듬이 큰 흔들림 없이 유지된 운동이에요.",
            splitType: current.workoutType == .cycling ? .stableSpeed : .stablePace,
            trend: .stable,
            metricRows: rows + [WorkoutSplitMetricRow(title: "리듬 유지", valueText: "안정", detailText: "센서 기준으로 전후반 흐름이 비슷하게 이어졌어요.")]
        )
    }

    private func buildSpeedStreamInsight(first: WorkoutSplitMetric, last: WorkoutSplitMetric) -> WorkoutSplitInsight? {
        guard let firstSpeed = first.averageSpeed,
              let lastSpeed = last.averageSpeed,
              firstSpeed > 0 else { return nil }

        let ratio = lastSpeed / firstSpeed
        let rows = [
            WorkoutSplitMetricRow(title: "전반 속도", valueText: formattedSpeed(firstSpeed), detailText: "앞 구간의 평균 흐름이에요."),
            WorkoutSplitMetricRow(title: "후반 속도", valueText: formattedSpeed(lastSpeed), detailText: "마지막 구간의 평균 흐름이에요.")
        ]

        if ratio < 0.92 {
            return WorkoutSplitInsight(title: "후반 속도 흐름이 조금 차분해졌어요", summary: "후반에는 속도보다 리듬을 조절한 운동에 가까워요.", splitType: .fatigueDrop, trend: .lighter, metricRows: rows)
        }
        if ratio > 1.03 {
            return WorkoutSplitInsight(title: "후반 속도 흐름이 좋아졌어요", summary: "마지막 구간까지 속도 리듬을 조금 더 끌어올린 운동이에요.", splitType: .negativeSplit, trend: .improving, metricRows: rows)
        }
        return WorkoutSplitInsight(title: "속도 리듬이 안정적으로 이어졌어요", summary: "전반과 후반의 속도 흐름이 비슷하게 유지됐어요.", splitType: .stableSpeed, trend: .stable, metricRows: rows)
    }

    private func buildPaceStreamInsight(
        current: WorkoutGrowthInput,
        first: WorkoutSplitMetric,
        last: WorkoutSplitMetric
    ) -> WorkoutSplitInsight? {
        guard let firstPace = first.averagePace,
              let lastPace = last.averagePace,
              firstPace > 0 else { return nil }

        let ratio = lastPace / firstPace
        let suffix = current.workoutType == .swimming ? "/100m" : "/km"
        let rows = [
            WorkoutSplitMetricRow(title: "전반 pace", valueText: formattedPace(firstPace, suffix: suffix), detailText: "앞 구간의 페이스 흐름이에요."),
            WorkoutSplitMetricRow(title: "후반 pace", valueText: formattedPace(lastPace, suffix: suffix), detailText: "마지막 구간의 페이스 흐름이에요.")
        ]

        if ratio > 1.08 {
            return WorkoutSplitInsight(title: "후반 pace가 조금 느긋해졌어요", summary: "마지막 구간에서는 페이스보다 리듬을 조절한 흐름이에요.", splitType: .fatigueDrop, trend: .lighter, metricRows: rows)
        }
        if ratio < 0.97 {
            return WorkoutSplitInsight(title: "후반 pace 흐름이 좋아졌어요", summary: "마지막 구간으로 갈수록 페이스 리듬을 조금 더 잘 이어갔어요.", splitType: .negativeSplit, trend: .improving, metricRows: rows)
        }
        return WorkoutSplitInsight(title: "pace 흐름이 안정적으로 이어졌어요", summary: "전반과 후반의 페이스가 큰 흔들림 없이 이어진 운동이에요.", splitType: .stablePace, trend: .stable, metricRows: rows)
    }

    private func buildHeartRateStreamInsight(
        current: WorkoutGrowthInput,
        first: WorkoutSplitMetric,
        last: WorkoutSplitMetric
    ) -> WorkoutSplitInsight? {
        guard let firstHeartRate = first.averageHeartRate,
              let lastHeartRate = last.averageHeartRate,
              firstHeartRate > 0 else { return nil }

        let drift = lastHeartRate - firstHeartRate
        guard abs(drift) < 8 else { return nil }

        return WorkoutSplitInsight(
            title: "심박 흐름이 안정적으로 이어졌어요",
            summary: "전반과 후반의 심박 흐름이 비슷하게 유지된 운동이에요.",
            splitType: current.workoutType == .cycling ? .stableSpeed : .stablePace,
            trend: .stable,
            metricRows: [
                WorkoutSplitMetricRow(title: "전반 심박", valueText: formattedHeartRate(firstHeartRate), detailText: "앞 구간의 평균 심박이에요."),
                WorkoutSplitMetricRow(title: "후반 심박", valueText: formattedHeartRate(lastHeartRate), detailText: "마지막 구간의 평균 심박이에요.")
            ]
        )
    }

    private func formattedSpeed(_ speed: Double) -> String {
        "\(String(format: "%.1f", speed)) km/h"
    }

    private func formattedPace(_ seconds: Double, suffix: String) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))\(suffix)"
    }

    private func formattedCadence(_ cadence: Double) -> String {
        "\(Int(cadence.rounded())) rpm"
    }

    private func formattedHeartRate(_ heartRate: Double) -> String {
        "\(Int(heartRate.rounded())) bpm"
    }

    private func formattedPercentChange(_ change: Double) -> String {
        let percent = Int((change * 100).rounded())
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }
}
