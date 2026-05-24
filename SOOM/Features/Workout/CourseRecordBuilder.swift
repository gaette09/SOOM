import Foundation

struct CourseRecordBuilder {
    func build(
        current: WorkoutGrowthInput,
        candidateWorkouts: [WorkoutGrowthInput],
        routeCandidates: [RouteComparisonCandidate] = [],
        courseIdentity: CourseIdentity? = nil
    ) -> CourseRecord {
        let candidates = candidateWorkouts
            .filter { $0.id != current.id }
            .filter { $0.workoutType == current.workoutType }
            .filter { $0.startDate <= current.startDate }

        guard !candidates.isEmpty else {
            return .insufficientData
        }

        let courseCandidates = prioritizedCandidates(candidates, routeCandidates: routeCandidates)

        switch current.workoutType {
        case .running, .walking, .hiking:
            return paceRecord(
                current: current,
                candidates: courseCandidates,
                comparisonType: .bestPace,
                metricTitle: "페이스",
                suffix: "/km",
                courseIdentity: courseIdentity
            )
        case .cycling:
            return speedRecord(current: current, candidates: courseCandidates, courseIdentity: courseIdentity)
        case .swimming:
            return paceRecord(
                current: current,
                candidates: courseCandidates,
                comparisonType: .bestPace,
                metricTitle: "100m 페이스",
                suffix: "/100m",
                paceScale: 10,
                courseIdentity: courseIdentity
            )
        case .strength, .yoga, .other:
            return durationRecord(current: current, candidates: courseCandidates, courseIdentity: courseIdentity)
        }
    }

    private func prioritizedCandidates(
        _ candidates: [WorkoutGrowthInput],
        routeCandidates: [RouteComparisonCandidate]
    ) -> [WorkoutGrowthInput] {
        let routeOrder = Dictionary(uniqueKeysWithValues: routeCandidates.enumerated().map { index, candidate in
            (candidate.candidateWorkoutId, index)
        })
        let scopedCandidates = routeOrder.isEmpty ? candidates : candidates.filter { routeOrder[$0.id] != nil }

        return scopedCandidates.sorted { lhs, rhs in
            let lhsRouteIndex = routeOrder[lhs.id]
            let rhsRouteIndex = routeOrder[rhs.id]

            if let lhsRouteIndex, let rhsRouteIndex {
                return lhsRouteIndex < rhsRouteIndex
            }

            if lhsRouteIndex != nil {
                return true
            }

            if rhsRouteIndex != nil {
                return false
            }

            return lhs.startDate > rhs.startDate
        }
    }

    private func paceRecord(
        current: WorkoutGrowthInput,
        candidates: [WorkoutGrowthInput],
        comparisonType: CourseRecordComparisonType,
        metricTitle: String,
        suffix: String,
        paceScale: Double = 1,
        courseIdentity: CourseIdentity?
    ) -> CourseRecord {
        guard let currentPace = paceSeconds(for: current) else {
            return distanceRecord(current: current, candidates: candidates, courseIdentity: courseIdentity)
        }

        let baseline = candidates
            .compactMap { candidate -> (input: WorkoutGrowthInput, pace: Double)? in
                guard let pace = paceSeconds(for: candidate) else { return nil }
                return (candidate, pace)
            }
            .min { $0.pace < $1.pace }

        guard let baseline else {
            return distanceRecord(current: current, candidates: candidates, courseIdentity: courseIdentity)
        }

        let improvementSeconds = baseline.pace - currentPace
        let displayImprovement = improvementSeconds / paceScale
        let bestMetric = CourseRecordMetric(
            title: metricTitle,
            valueText: paceText(currentPace / paceScale, suffix: suffix),
            detailText: improvementSeconds >= 0
            ? "이 코스에서 이전보다 조금 더 가벼운 리듬이었어요."
            : "오늘은 기록보다 코스 리듬을 다시 확인한 운동이에요."
        )
        let previousMetric = CourseRecordMetric(
            title: "이전 기준",
            valueText: paceText(baseline.pace / paceScale, suffix: suffix),
            detailText: "비슷한 코스의 이전 좋은 기록이에요."
        )

        return CourseRecord(
            courseId: courseId(for: current, baseline: baseline.input, courseIdentity: courseIdentity),
            workoutId: current.id,
            comparisonType: improvementSeconds >= 0 ? comparisonType : .stableRhythm,
            bestMetric: bestMetric,
            previousMetric: previousMetric,
            improvementValue: improvementSeconds >= 0 ? "\(Int(displayImprovement.rounded()))초 더 가벼움" : nil,
            achievedAt: current.startDate
        )
    }

    private func speedRecord(
        current: WorkoutGrowthInput,
        candidates: [WorkoutGrowthInput],
        courseIdentity: CourseIdentity?
    ) -> CourseRecord {
        guard let currentSpeed = speedKmh(for: current) else {
            return distanceRecord(current: current, candidates: candidates, courseIdentity: courseIdentity)
        }

        let baseline = candidates
            .compactMap { candidate -> (input: WorkoutGrowthInput, speed: Double)? in
                guard let speed = speedKmh(for: candidate) else { return nil }
                return (candidate, speed)
            }
            .max { $0.speed < $1.speed }

        guard let baseline else {
            return distanceRecord(current: current, candidates: candidates, courseIdentity: courseIdentity)
        }

        let delta = currentSpeed - baseline.speed
        return CourseRecord(
            courseId: courseId(for: current, baseline: baseline.input, courseIdentity: courseIdentity),
            workoutId: current.id,
            comparisonType: delta >= 0 ? .bestSpeed : .stableRhythm,
            bestMetric: CourseRecordMetric(
                title: "평균 속도",
                valueText: "\(String(format: "%.1f", currentSpeed)) km/h",
                detailText: delta >= 0
                ? "비슷한 코스에서 이전보다 조금 더 빠른 흐름이었어요."
                : "오늘은 속도보다 코스 리듬을 차분히 확인한 운동이에요."
            ),
            previousMetric: CourseRecordMetric(
                title: "이전 기준",
                valueText: "\(String(format: "%.1f", baseline.speed)) km/h",
                detailText: "비슷한 코스의 이전 좋은 속도 기록이에요."
            ),
            improvementValue: delta >= 0 ? "+\(String(format: "%.1f", delta)) km/h" : nil,
            achievedAt: current.startDate
        )
    }

    private func durationRecord(
        current: WorkoutGrowthInput,
        candidates: [WorkoutGrowthInput],
        courseIdentity: CourseIdentity?
    ) -> CourseRecord {
        guard let baseline = candidates.sorted(by: { $0.startDate > $1.startDate }).first else {
            return .insufficientData
        }

        let delta = baseline.durationMinutes - current.durationMinutes
        return CourseRecord(
            courseId: courseId(for: current, baseline: baseline, courseIdentity: courseIdentity),
            workoutId: current.id,
            comparisonType: delta >= 0 ? .fastestCompletion : .recentImprovement,
            bestMetric: CourseRecordMetric(
                title: "완료 시간",
                valueText: "\(current.durationMinutes)분",
                detailText: delta >= 0
                ? "비슷한 흐름에서 조금 더 빠르게 마무리했어요."
                : "오늘은 시간보다 꾸준한 움직임을 확인했어요."
            ),
            previousMetric: CourseRecordMetric(
                title: "이전 기준",
                valueText: "\(baseline.durationMinutes)분",
                detailText: "최근 비슷한 운동 기록이에요."
            ),
            improvementValue: delta >= 0 ? "\(delta)분 단축" : nil,
            achievedAt: current.startDate
        )
    }

    private func distanceRecord(
        current: WorkoutGrowthInput,
        candidates: [WorkoutGrowthInput],
        courseIdentity: CourseIdentity?
    ) -> CourseRecord {
        guard let currentDistance = current.distanceKm,
              let baseline = candidates
                .compactMap({ candidate -> (input: WorkoutGrowthInput, distance: Double)? in
                    guard let distance = candidate.distanceKm else { return nil }
                    return (candidate, distance)
                })
                .max(by: { $0.distance < $1.distance }) else {
            return .insufficientData
        }

        let delta = currentDistance - baseline.distance
        return CourseRecord(
            courseId: courseId(for: current, baseline: baseline.input, courseIdentity: courseIdentity),
            workoutId: current.id,
            comparisonType: delta >= 0 ? .longestDistance : .recentImprovement,
            bestMetric: CourseRecordMetric(
                title: "거리",
                valueText: "\(String(format: "%.1f", currentDistance)) km",
                detailText: delta >= 0
                ? "비슷한 흐름에서 이전보다 조금 더 길게 움직였어요."
                : "오늘은 거리보다 리듬을 확인한 운동이에요."
            ),
            previousMetric: CourseRecordMetric(
                title: "이전 기준",
                valueText: "\(String(format: "%.1f", baseline.distance)) km",
                detailText: "비슷한 운동의 이전 거리 기록이에요."
            ),
            improvementValue: delta >= 0 ? "+\(String(format: "%.1f", delta)) km" : nil,
            achievedAt: current.startDate
        )
    }

    private func courseId(for current: WorkoutGrowthInput, baseline: WorkoutGrowthInput, courseIdentity: CourseIdentity?) -> String {
        if let courseIdentity { return courseIdentity.courseId }
        let fallbackDistanceBucket = Int(((current.distanceKm ?? 0) * 1_000 / 250).rounded() * 250)
        return "course-\(current.workoutType.rawValue)-\(fallbackDistanceBucket)-\(baseline.id.uuidString)"
    }

    private func paceSeconds(for input: WorkoutGrowthInput) -> Double? {
        guard let distanceKm = input.distanceKm, distanceKm > 0, input.durationMinutes > 0 else { return nil }
        return Double(input.durationMinutes * 60) / distanceKm
    }

    private func speedKmh(for input: WorkoutGrowthInput) -> Double? {
        if let speed = input.averageSpeedKmh, speed > 0 { return speed }
        guard let distanceKm = input.distanceKm, distanceKm > 0, input.durationMinutes > 0 else { return nil }
        return distanceKm / (Double(input.durationMinutes) / 60)
    }

    private func paceText(_ seconds: Double, suffix: String) -> String {
        let rounded = max(Int(seconds.rounded()), 0)
        return "\(rounded / 60):\(String(format: "%02d", rounded % 60))\(suffix)"
    }
}
