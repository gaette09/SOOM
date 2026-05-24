import Foundation

struct WorkoutComparisonInsightBuilder {
    func build(
        current: WorkoutGrowthInput,
        baseline: WorkoutGrowthInput?,
        routeCandidate: RouteComparisonCandidate? = nil
    ) -> WorkoutComparisonInsight {
        guard let baseline else {
            return .insufficientData
        }

        let comparisonType = comparisonType(for: routeCandidate)
        var rows: [WorkoutComparisonMetricRow] = []

        if let distanceRow = distanceRow(current: current, baseline: baseline) {
            rows.append(distanceRow)
        }

        switch current.workoutType {
        case .running, .walking, .hiking:
            if let paceRow = paceRow(current: current, baseline: baseline, title: "페이스") {
                rows.append(paceRow)
            }
        case .cycling:
            if let speedRow = speedRow(current: current, baseline: baseline) {
                rows.append(speedRow)
            }
            if let elevationRow = elevationRow(current: current, baseline: baseline) {
                rows.append(elevationRow)
            }
        case .swimming:
            if let paceRow = pace100mRow(current: current, baseline: baseline) {
                rows.append(paceRow)
            }
        case .strength, .yoga, .other:
            if let durationRow = durationRow(current: current, baseline: baseline) {
                rows.append(durationRow)
            }
        }

        if rows.isEmpty, let durationRow = durationRow(current: current, baseline: baseline) {
            rows.append(durationRow)
        }

        guard !rows.isEmpty else {
            return .insufficientData
        }

        let tone = tone(current: current, baseline: baseline)
        return WorkoutComparisonInsight(
            title: title(for: comparisonType, tone: tone),
            summary: summary(for: current.workoutType, comparisonType: comparisonType, tone: tone),
            metricRows: Array(rows.prefix(4)),
            tone: tone,
            comparisonType: comparisonType
        )
    }

    private func comparisonType(for candidate: RouteComparisonCandidate?) -> WorkoutComparisonType {
        guard let candidate else { return .recentWorkout }

        switch candidate.reason {
        case .similarRoute:
            return .sameRoute
        case .similarDistance, .sameWorkoutType, .recentComparable:
            return .similarDistance
        }
    }

    private func title(for type: WorkoutComparisonType, tone: WorkoutComparisonInsightTone) -> String {
        switch type {
        case .sameRoute:
            return tone == .improved ? "비슷한 코스에서 리듬이 좋아졌어요" : "비슷한 코스 흐름을 비교했어요"
        case .similarDistance:
            return tone == .improved ? "비슷한 거리에서 좋은 변화가 보여요" : "비슷한 거리 기록과 비교했어요"
        case .recentWorkout:
            return tone == .improved ? "최근 같은 종목보다 흐름이 좋아졌어요" : "최근 같은 종목 기록과 비교했어요"
        case .insufficientData:
            return WorkoutComparisonInsight.insufficientData.title
        }
    }

    private func summary(
        for type: UnifiedWorkoutType,
        comparisonType: WorkoutComparisonType,
        tone: WorkoutComparisonInsightTone
    ) -> String {
        switch tone {
        case .improved:
            return "오늘은 이전의 나와 비교했을 때 조금 더 좋은 리듬이 보였어요."
        case .steady:
            return "이전 기록과 비슷한 흐름을 안정적으로 이어갔어요."
        case .lighter:
            return "오늘은 기록보다 컨디션과 리듬을 확인한 운동에 가까워요."
        case .insufficientData:
            return WorkoutComparisonInsight.insufficientData.summary
        }
    }

    private func distanceRow(current: WorkoutGrowthInput, baseline: WorkoutGrowthInput) -> WorkoutComparisonMetricRow? {
        guard let currentDistance = current.distanceKm,
              let baselineDistance = baseline.distanceKm,
              currentDistance > 0,
              baselineDistance > 0 else {
            return nil
        }

        let delta = currentDistance - baselineDistance
        return WorkoutComparisonMetricRow(
            title: "거리",
            valueText: signedDistance(delta),
            detailText: delta >= 0 ? "이전 비슷한 운동보다 조금 더 길게 움직였어요." : "오늘은 거리보다 리듬을 확인한 기록이에요."
        )
    }

    private func durationRow(current: WorkoutGrowthInput, baseline: WorkoutGrowthInput) -> WorkoutComparisonMetricRow? {
        let delta = current.durationMinutes - baseline.durationMinutes
        guard delta != 0 else {
            return WorkoutComparisonMetricRow(
                title: "운동 시간",
                valueText: "비슷함",
                detailText: "이전 기록과 비슷한 시간 동안 리듬을 이어갔어요."
            )
        }

        return WorkoutComparisonMetricRow(
            title: "운동 시간",
            valueText: signedDuration(delta),
            detailText: delta > 0 ? "이전보다 조금 더 오래 움직였어요." : "오늘은 짧고 가볍게 흐름을 확인했어요."
        )
    }

    private func paceRow(current: WorkoutGrowthInput, baseline: WorkoutGrowthInput, title: String) -> WorkoutComparisonMetricRow? {
        guard let currentPace = paceSeconds(for: current),
              let baselinePace = paceSeconds(for: baseline) else {
            return nil
        }

        let delta = baselinePace - currentPace
        return WorkoutComparisonMetricRow(
            title: title,
            valueText: signedPace(delta, suffix: "/km"),
            detailText: delta >= 0 ? "페이스가 이전보다 조금 더 가볍게 이어졌어요." : "오늘은 빠른 페이스보다 안정적인 움직임을 확인했어요."
        )
    }

    private func pace100mRow(current: WorkoutGrowthInput, baseline: WorkoutGrowthInput) -> WorkoutComparisonMetricRow? {
        guard let currentPace = paceSeconds(for: current),
              let baselinePace = paceSeconds(for: baseline) else {
            return nil
        }

        let delta = (baselinePace - currentPace) / 10
        return WorkoutComparisonMetricRow(
            title: "100m 페이스",
            valueText: signedPace(delta, suffix: "/100m"),
            detailText: delta >= 0 ? "100m 리듬이 이전보다 조금 더 가벼웠어요." : "오늘은 물속 리듬을 차분히 확인한 세션이에요."
        )
    }

    private func speedRow(current: WorkoutGrowthInput, baseline: WorkoutGrowthInput) -> WorkoutComparisonMetricRow? {
        guard let currentSpeed = speedKmh(for: current),
              let baselineSpeed = speedKmh(for: baseline) else {
            return nil
        }

        let delta = currentSpeed - baselineSpeed
        return WorkoutComparisonMetricRow(
            title: "평균 속도",
            valueText: signedSpeed(delta),
            detailText: delta >= 0 ? "평균 속도가 이전보다 조금 더 안정적이었어요." : "오늘은 속도보다 편안한 리듬을 만든 운동이에요."
        )
    }

    private func elevationRow(current: WorkoutGrowthInput, baseline: WorkoutGrowthInput) -> WorkoutComparisonMetricRow? {
        guard let currentElevation = current.elevationGainMeters,
              let baselineElevation = baseline.elevationGainMeters,
              currentElevation > 0 || baselineElevation > 0 else {
            return nil
        }

        let delta = currentElevation - baselineElevation
        return WorkoutComparisonMetricRow(
            title: "상승 고도",
            valueText: signedMeters(delta),
            detailText: delta >= 0 ? "오르막 자극이 이전보다 조금 더 있었어요." : "오늘은 고도 부담이 비교적 가벼운 흐름이에요."
        )
    }

    private func tone(current: WorkoutGrowthInput, baseline: WorkoutGrowthInput) -> WorkoutComparisonInsightTone {
        switch current.workoutType {
        case .running, .walking, .hiking, .swimming:
            guard let currentPace = paceSeconds(for: current), let baselinePace = paceSeconds(for: baseline) else {
                return distanceTone(current: current, baseline: baseline)
            }
            if currentPace <= baselinePace * 0.97 { return .improved }
            if currentPace >= baselinePace * 1.08 { return .lighter }
            return .steady
        case .cycling:
            guard let currentSpeed = speedKmh(for: current), let baselineSpeed = speedKmh(for: baseline) else {
                return distanceTone(current: current, baseline: baseline)
            }
            if currentSpeed >= baselineSpeed * 1.03 { return .improved }
            if currentSpeed <= baselineSpeed * 0.94 { return .lighter }
            return .steady
        case .strength, .yoga, .other:
            return distanceTone(current: current, baseline: baseline)
        }
    }

    private func distanceTone(current: WorkoutGrowthInput, baseline: WorkoutGrowthInput) -> WorkoutComparisonInsightTone {
        guard let currentDistance = current.distanceKm,
              let baselineDistance = baseline.distanceKm,
              baselineDistance > 0 else {
            return .steady
        }

        if currentDistance >= baselineDistance * 1.05 { return .improved }
        if currentDistance <= baselineDistance * 0.90 { return .lighter }
        return .steady
    }

    private func paceSeconds(for input: WorkoutGrowthInput) -> Double? {
        guard let distanceKm = input.distanceKm, distanceKm > 0, input.durationMinutes > 0 else { return nil }
        return Double(input.durationMinutes * 60) / distanceKm
    }

    private func speedKmh(for input: WorkoutGrowthInput) -> Double? {
        if let speed = input.averageSpeedKmh, speed > 0 { return speed }
        guard let distance = input.distanceKm, distance > 0, input.durationMinutes > 0 else { return nil }
        return distance / (Double(input.durationMinutes) / 60)
    }

    private func signedDistance(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", abs(value))) km"
    }

    private func signedDuration(_ minutes: Int) -> String {
        let sign = minutes >= 0 ? "+" : "-"
        return "\(sign)\(abs(minutes))분"
    }

    private func signedSpeed(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", abs(value))) km/h"
    }

    private func signedMeters(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(Int(abs(value).rounded())) m"
    }

    private func signedPace(_ seconds: Double, suffix: String) -> String {
        let sign = seconds >= 0 ? "-" : "+"
        let absolute = abs(Int(seconds.rounded()))
        return "\(sign)\(absolute)초\(suffix)"
    }
}
