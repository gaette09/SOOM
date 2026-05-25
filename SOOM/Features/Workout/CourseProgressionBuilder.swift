import Foundation

struct CourseProgressionBuilder {
    func build(
        current: WorkoutGrowthInput,
        candidateWorkouts: [WorkoutGrowthInput],
        routeCandidates: [RouteComparisonCandidate] = [],
        courseIdentity: CourseIdentity? = nil
    ) -> CourseProgressionTimeline {
        let candidates = comparableCandidates(
            current: current,
            candidateWorkouts: candidateWorkouts,
            routeCandidates: routeCandidates
        )

        let inputs = (candidates + [current])
            .filter { metricValue(for: $0) != nil }
            .sorted { $0.startDate < $1.startDate }

        guard inputs.count >= 2 else {
            return .insufficientData
        }

        let routeScoreByWorkoutId = Dictionary(
            uniqueKeysWithValues: routeCandidates.map { ($0.candidateWorkoutId, $0.similarityScore) }
        )
        let metric = comparisonMetric(for: current.workoutType)
        let points = inputs.enumerated().compactMap { index, input -> CourseProgressionPoint? in
            guard let value = metricValue(for: input) else { return nil }
            let previousValue = index > 0 ? metricValue(for: inputs[index - 1]) : nil
            return CourseProgressionPoint(
                workoutId: input.id,
                recordedAt: input.startDate,
                comparisonMetric: metric,
                metricValue: value,
                trend: previousValue.map { pointTrend(current: value, previous: $0, metric: metric) },
                routeSimilarityScore: input.id == current.id ? nil : routeScoreByWorkoutId[input.id]
            )
        }

        guard points.count >= 2 else {
            return .insufficientData
        }

        let direction = timelineDirection(points: points, metric: metric)
        return CourseProgressionTimeline(
            courseId: courseId(for: current, courseIdentity: courseIdentity),
            points: points,
            summary: summary(direction: direction, workoutType: current.workoutType),
            direction: direction
        )
    }

    private func comparableCandidates(
        current: WorkoutGrowthInput,
        candidateWorkouts: [WorkoutGrowthInput],
        routeCandidates: [RouteComparisonCandidate]
    ) -> [WorkoutGrowthInput] {
        let baseCandidates = candidateWorkouts
            .filter { $0.id != current.id }
            .filter { $0.workoutType == current.workoutType }
            .filter { $0.startDate <= current.startDate }

        guard !routeCandidates.isEmpty else {
            return baseCandidates
        }

        let routeOrder = Dictionary(uniqueKeysWithValues: routeCandidates.enumerated().map { index, candidate in
            (candidate.candidateWorkoutId, index)
        })

        let routeMatched = baseCandidates.filter { routeOrder[$0.id] != nil }
        return routeMatched.isEmpty ? baseCandidates : routeMatched
    }

    private func comparisonMetric(for type: UnifiedWorkoutType) -> CourseProgressionComparisonMetric {
        switch type {
        case .running, .walking, .hiking:
            return .pace
        case .cycling:
            return .averageSpeed
        case .swimming:
            return .pace
        case .strength, .yoga, .other:
            return .completionTime
        }
    }

    private func metricValue(for input: WorkoutGrowthInput) -> Double? {
        switch input.workoutType {
        case .running, .walking, .hiking, .swimming:
            return paceSeconds(for: input)
        case .cycling:
            return speedKmh(for: input)
        case .strength, .yoga, .other:
            return input.durationMinutes > 0 ? Double(input.durationMinutes) : nil
        }
    }

    private func pointTrend(
        current: Double,
        previous: Double,
        metric: CourseProgressionComparisonMetric
    ) -> CourseProgressionPointTrend {
        let lowerIsBetter = metric == .pace || metric == .completionTime
        let ratio = previous == 0 ? 0 : (current - previous) / abs(previous)

        if abs(ratio) <= 0.03 {
            return .stable
        }

        if lowerIsBetter {
            return ratio < 0 ? .improved : .lighter
        }

        return ratio > 0 ? .improved : .lighter
    }

    private func timelineDirection(
        points: [CourseProgressionPoint],
        metric: CourseProgressionComparisonMetric
    ) -> CourseProgressionDirection {
        guard let first = points.first?.metricValue,
              let last = points.last?.metricValue,
              points.count >= 3 else {
            return .stable
        }

        let lowerIsBetter = metric == .pace || metric == .completionTime
        let totalChange = first == 0 ? 0 : (last - first) / abs(first)
        let improved = lowerIsBetter ? totalChange <= -0.04 : totalChange >= 0.04
        let lighter = lowerIsBetter ? totalChange >= 0.07 : totalChange <= -0.07
        let trendChanges = points.compactMap(\.trend)
        let hasMixedSignals = trendChanges.contains(.improved) && trendChanges.contains(.lighter)

        if improved {
            return hasMixedSignals ? .fluctuating : .improving
        }

        if lighter {
            return .fluctuating
        }

        return hasMixedSignals ? .fluctuating : .stable
    }

    private func summary(direction: CourseProgressionDirection, workoutType: UnifiedWorkoutType) -> String {
        switch direction {
        case .improving:
            return "비슷한 코스에서 시간이 지나며 리듬이 조금씩 좋아지고 있어요."
        case .stable:
            return "비슷한 코스에서 안정적인 흐름을 꾸준히 이어가고 있어요."
        case .fluctuating:
            return "최근 기록마다 흐름이 조금 달라요. 컨디션과 코스 리듬을 함께 살펴보면 좋아요."
        case .insufficientData:
            return CourseProgressionTimeline.insufficientData.summary
        }
    }

    private func courseId(for current: WorkoutGrowthInput, courseIdentity: CourseIdentity?) -> String {
        if let courseIdentity { return courseIdentity.courseId }
        let distanceBucket = Int((((current.distanceKm ?? 0) * 1_000) / 250).rounded() * 250)
        return "progression-\(current.workoutType.rawValue)-\(distanceBucket)"
    }

    private func paceSeconds(for input: WorkoutGrowthInput) -> Double? {
        guard let distanceKm = input.distanceKm, distanceKm > 0, input.durationMinutes > 0 else {
            return nil
        }
        return Double(input.durationMinutes * 60) / distanceKm
    }

    private func speedKmh(for input: WorkoutGrowthInput) -> Double? {
        if let speed = input.averageSpeedKmh, speed > 0 {
            return speed
        }

        guard let distanceKm = input.distanceKm, distanceKm > 0, input.durationMinutes > 0 else {
            return nil
        }

        return distanceKm / (Double(input.durationMinutes) / 60)
    }
}
