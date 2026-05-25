import Foundation

struct ClimbInsightBuilder {
    private let minimumElevationGainMeters: Double
    private let minimumGradePercent: Double

    init(
        minimumElevationGainMeters: Double = 80,
        minimumGradePercent: Double = 2.0
    ) {
        self.minimumElevationGainMeters = minimumElevationGainMeters
        self.minimumGradePercent = minimumGradePercent
    }

    func build(
        current: WorkoutGrowthInput,
        route: WorkoutRoute? = nil,
        splitMetrics: [WorkoutSplitMetric]? = nil
    ) -> ClimbInsight {
        guard isSupportedClimbSport(current.workoutType),
              let elevationGain = elevationGain(for: current, route: route),
              let distanceKm = distanceKm(for: current, route: route),
              elevationGain > 0,
              distanceKm > 0 else {
            return .insufficientData
        }

        let averageGrade = elevationGain / (distanceKm * 1_000) * 100
        guard elevationGain >= minimumElevationGainMeters || averageGrade >= minimumGradePercent else {
            return .insufficientData
        }

        if let splitInsight = buildSplitAwareInsight(
            current: current,
            elevationGain: elevationGain,
            distanceKm: distanceKm,
            averageGrade: averageGrade,
            splitMetrics: splitMetrics ?? []
        ) {
            return splitInsight
        }

        if isElevationControlled(current: current, elevationGain: elevationGain, averageGrade: averageGrade) {
            return ClimbInsight(
                title: "후반 오르막 리듬을 차분히 조절했어요",
                summary: "상승고도가 있는 운동에서 속도보다 호흡과 리듬을 우선한 흐름이에요.",
                climbType: .elevationFatigue,
                metricRows: baseRows(elevationGain: elevationGain, distanceKm: distanceKm, averageGrade: averageGrade) + [
                    ClimbInsightMetricRow(
                        title: "오르막 흐름",
                        valueText: "차분한 조절",
                        detailText: "긴 오르막에서는 후반 리듬을 여유 있게 가져간 기록으로 볼 수 있어요."
                    )
                ],
                trend: .lighter
            )
        }

        if averageGrade >= 4.0 || (elevationGain >= 300 && averageGrade >= 1.0) {
            return ClimbInsight(
                title: "오르막 리듬을 안정적으로 이어갔어요",
                summary: "상승 비중이 있는 코스에서 꾸준한 지형 리듬을 만든 운동이에요.",
                climbType: .steadyClimb,
                metricRows: baseRows(elevationGain: elevationGain, distanceKm: distanceKm, averageGrade: averageGrade),
                trend: .stable
            )
        }

        return ClimbInsight(
            title: "완만한 지형 변화를 잘 지나갔어요",
            summary: "큰 업힐보다는 오르내림이 섞인 코스에서 리듬을 이어간 운동이에요.",
            climbType: .rollingTerrain,
            metricRows: baseRows(elevationGain: elevationGain, distanceKm: distanceKm, averageGrade: averageGrade),
            trend: .stable
        )
    }

    private func buildSplitAwareInsight(
        current: WorkoutGrowthInput,
        elevationGain: Double,
        distanceKm: Double,
        averageGrade: Double,
        splitMetrics: [WorkoutSplitMetric]
    ) -> ClimbInsight? {
        let orderedMetrics = splitMetrics.sorted { $0.splitIndex < $1.splitIndex }
        guard let first = orderedMetrics.first,
              let last = orderedMetrics.last,
              orderedMetrics.count >= 2 else {
            return nil
        }

        if let speedRatio = ratio(first.averageSpeed, last.averageSpeed) {
            if speedRatio >= 0.97 {
                return strongFinishInsight(
                    elevationGain: elevationGain,
                    distanceKm: distanceKm,
                    averageGrade: averageGrade,
                    metricTitle: "후반 속도 유지",
                    metricValue: formattedPercentChange(speedRatio - 1),
                    metricDetail: "오르막이 섞인 흐름에서도 마지막 구간의 속도 리듬을 잘 이어갔어요."
                )
            }

            if speedRatio < 0.88 && elevationGain >= minimumElevationGainMeters {
                return controlledRhythmInsight(
                    elevationGain: elevationGain,
                    distanceKm: distanceKm,
                    averageGrade: averageGrade,
                    metricTitle: "후반 속도 변화",
                    metricValue: formattedPercentChange(speedRatio - 1),
                    metricDetail: "후반에는 속도보다 지형에 맞춘 리듬 조절이 더 크게 보였어요."
                )
            }
        }

        if let cadenceRatio = ratio(first.averageCadence, last.averageCadence) {
            if cadenceRatio >= 0.96 {
                return strongFinishInsight(
                    elevationGain: elevationGain,
                    distanceKm: distanceKm,
                    averageGrade: averageGrade,
                    metricTitle: current.workoutType == .cycling ? "업힐 cadence" : "후반 리듬",
                    metricValue: formattedPercentChange(cadenceRatio - 1),
                    metricDetail: "후반에도 회전 리듬을 안정적으로 가져간 흐름이에요."
                )
            }

            if cadenceRatio < 0.88 {
                return controlledRhythmInsight(
                    elevationGain: elevationGain,
                    distanceKm: distanceKm,
                    averageGrade: averageGrade,
                    metricTitle: current.workoutType == .cycling ? "업힐 cadence" : "후반 리듬",
                    metricValue: formattedPercentChange(cadenceRatio - 1),
                    metricDetail: "후반에는 지형에 맞춰 리듬을 조금 더 차분히 가져갔어요."
                )
            }
        }

        return nil
    }

    private func strongFinishInsight(
        elevationGain: Double,
        distanceKm: Double,
        averageGrade: Double,
        metricTitle: String,
        metricValue: String,
        metricDetail: String
    ) -> ClimbInsight {
        ClimbInsight(
            title: "오르막 후반 리듬이 잘 이어졌어요",
            summary: "상승 구간이 있는 운동에서도 마지막 흐름을 안정적으로 유지한 기록이에요.",
            climbType: .strongFinish,
            metricRows: baseRows(elevationGain: elevationGain, distanceKm: distanceKm, averageGrade: averageGrade) + [
                ClimbInsightMetricRow(title: metricTitle, valueText: metricValue, detailText: metricDetail)
            ],
            trend: .improving
        )
    }

    private func controlledRhythmInsight(
        elevationGain: Double,
        distanceKm: Double,
        averageGrade: Double,
        metricTitle: String,
        metricValue: String,
        metricDetail: String
    ) -> ClimbInsight {
        ClimbInsight(
            title: "오르막 후반 리듬을 조절했어요",
            summary: "후반에는 지형에 맞춰 속도보다 안정적인 움직임을 우선한 흐름이에요.",
            climbType: .elevationFatigue,
            metricRows: baseRows(elevationGain: elevationGain, distanceKm: distanceKm, averageGrade: averageGrade) + [
                ClimbInsightMetricRow(title: metricTitle, valueText: metricValue, detailText: metricDetail)
            ],
            trend: .lighter
        )
    }

    private func isSupportedClimbSport(_ type: UnifiedWorkoutType) -> Bool {
        switch type {
        case .cycling, .hiking:
            return true
        case .running, .walking, .swimming, .strength, .yoga, .other:
            return false
        }
    }

    private func elevationGain(for input: WorkoutGrowthInput, route: WorkoutRoute?) -> Double? {
        route?.totalElevationGain ?? input.elevationGainMeters
    }

    private func distanceKm(for input: WorkoutGrowthInput, route: WorkoutRoute?) -> Double? {
        if let route, route.totalDistanceMeters > 0 {
            return route.totalDistanceMeters / 1_000
        }
        return input.distanceKm
    }

    private func isElevationControlled(
        current: WorkoutGrowthInput,
        elevationGain: Double,
        averageGrade: Double
    ) -> Bool {
        guard current.durationMinutes >= 120 || elevationGain >= 500 else {
            return false
        }

        if current.workoutType == .cycling,
           let speed = current.averageSpeedKmh {
            return speed < 16 || averageGrade >= 6
        }

        return averageGrade >= 6
    }

    private func ratio(_ first: Double?, _ last: Double?) -> Double? {
        guard let first, let last, first > 0 else {
            return nil
        }
        return last / first
    }

    private func baseRows(
        elevationGain: Double,
        distanceKm: Double,
        averageGrade: Double
    ) -> [ClimbInsightMetricRow] {
        [
            ClimbInsightMetricRow(
                title: "상승고도",
                valueText: "\(Int(elevationGain.rounded()))m",
                detailText: "오늘 코스에서 누적된 오르막 흐름이에요."
            ),
            ClimbInsightMetricRow(
                title: "평균 경사",
                valueText: "\(String(format: "%.1f", averageGrade))%",
                detailText: "거리 대비 상승 비중을 가볍게 본 기준이에요."
            )
        ]
    }

    private func formattedPercentChange(_ change: Double) -> String {
        let percent = Int((change * 100).rounded())
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }
}
