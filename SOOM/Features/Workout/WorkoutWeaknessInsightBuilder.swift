import Foundation

struct WorkoutWeaknessInsightBuilder {
    func build(current workout: Workout, recentWorkouts: [Workout]) -> WorkoutWeaknessInsight {
        let previousWorkouts = recentWorkouts
            .filter { $0.id != workout.id && $0.date < workout.date }
            .sorted { $0.date > $1.date }

        guard workout.samples.count >= 6 || !previousWorkouts.isEmpty else {
            return noInsight()
        }

        if isRecoveryLoadHigh(workout, previousWorkouts: previousWorkouts) {
            return WorkoutWeaknessInsight(
                title: "회복 흐름을 먼저 챙겨도 좋아요",
                shortInsight: "최근 강도 흐름 위에 오늘 운동 강도도 높게 쌓였어요.",
                suggestion: "다음 운동은 강도보다 가벼운 리듬과 수면 회복을 먼저 확인해보세요.",
                insightType: .recovery,
                icon: SOOMIcon.recovery
            )
        }

        if hasLatePaceDrop(workout) {
            return WorkoutWeaknessInsight(
                title: "후반 리듬이 조금 흔들렸어요",
                shortInsight: "마지막 구간에서 초반보다 페이스 유지가 조금 어려웠어요.",
                suggestion: "초반 강도를 조금만 낮추면 후반까지 더 안정적으로 이어질 수 있어요.",
                insightType: .pacing,
                icon: SOOMIcon.trendDown
            )
        }

        if hasHighHeartRate(workout, previousWorkouts: previousWorkouts) {
            return WorkoutWeaknessInsight(
                title: "심박 흐름을 차분히 볼 만해요",
                shortInsight: "오늘 평균 심박이 최근 같은 종목 흐름보다 조금 높게 나타났어요.",
                suggestion: "다음에는 초반 10분을 더 편하게 열어 심박 상승 폭을 확인해보세요.",
                insightType: .heartRate,
                icon: SOOMIcon.heart
            )
        }

        if hasIrregularWorkoutGaps(previousWorkouts) {
            return WorkoutWeaknessInsight(
                title: "운동 간격이 조금 불규칙했어요",
                shortInsight: "최근 운동 사이 간격이 일정하지 않아 리듬을 잡기 어려울 수 있어요.",
                suggestion: "짧은 세션이라도 비슷한 요일과 시간에 반복하면 흐름을 만들기 쉬워요.",
                insightType: .consistency,
                icon: SOOMIcon.calendarClock
            )
        }

        if hasLateEnduranceDrop(workout) {
            return WorkoutWeaknessInsight(
                title: "지속 리듬을 더 다듬을 수 있어요",
                shortInsight: "후반으로 갈수록 움직임의 여유가 조금 줄어든 흐름이에요.",
                suggestion: "다음에는 목표 페이스보다 편한 강도로 시작해 마지막 구간을 안정적으로 마무리해보세요.",
                insightType: .endurance,
                icon: SOOMIcon.trend
            )
        }

        return WorkoutWeaknessInsight(
            title: "다음에도 이 흐름을 이어가요",
            shortInsight: "오늘 운동에서 크게 흔들린 지점은 보이지 않았어요.",
            suggestion: "같은 조건의 기록을 한두 번 더 쌓으면 개선 포인트를 더 선명하게 볼 수 있어요.",
            insightType: .none,
            icon: SOOMIcon.checkCircle
        )
    }

    private func noInsight() -> WorkoutWeaknessInsight {
        WorkoutWeaknessInsight(
            title: "비교 데이터가 더 쌓이면 좋아요",
            shortInsight: "아직 개선 포인트를 안정적으로 판단하기에는 기록이 조금 더 필요해요.",
            suggestion: "같은 종목 기록을 몇 번 더 쌓으면 페이스와 심박 흐름을 함께 비교할 수 있어요.",
            insightType: .none,
            icon: SOOMIcon.checkCircle
        )
    }

    private func isRecoveryLoadHigh(_ workout: Workout, previousWorkouts: [Workout]) -> Bool {
        let recentEfforts = previousWorkouts.prefix(3).map(\.effort)
        guard !recentEfforts.isEmpty else { return false }
        let recentAverage = Double(recentEfforts.reduce(0, +)) / Double(recentEfforts.count)
        return workout.effort >= 8 && recentAverage >= 7
    }

    private func hasLatePaceDrop(_ workout: Workout) -> Bool {
        guard workout.samples.count >= 6 else { return false }
        let paceChange = lateAveragePace(workout) / max(earlyAveragePace(workout), 1)
        return paceChange >= 1.10
    }

    private func hasLateEnduranceDrop(_ workout: Workout) -> Bool {
        guard workout.samples.count >= 6 else { return false }
        let paceChange = lateAveragePace(workout) / max(earlyAveragePace(workout), 1)
        let heartRateChange = lateAverageHeartRate(workout) - earlyAverageHeartRate(workout)
        return paceChange >= 1.06 && heartRateChange >= 10
    }

    private func hasHighHeartRate(_ workout: Workout, previousWorkouts: [Workout]) -> Bool {
        let sameSport = previousWorkouts.filter { $0.sport == workout.sport }
        let previousAverage = sameSport.isEmpty
            ? Double(workout.avgHeartRate)
            : Double(sameSport.map(\.avgHeartRate).reduce(0, +)) / Double(sameSport.count)

        return workout.avgHeartRate >= 170 || Double(workout.avgHeartRate) >= previousAverage + 12
    }

    private func hasIrregularWorkoutGaps(_ previousWorkouts: [Workout]) -> Bool {
        let dates = previousWorkouts.prefix(4).map(\.date).sorted(by: >)
        guard dates.count >= 3 else { return false }

        let gaps = zip(dates, dates.dropFirst()).map { newer, older in
            Calendar.current.dateComponents([.day], from: older, to: newer).day ?? 0
        }

        guard let minGap = gaps.min(), let maxGap = gaps.max() else { return false }
        return maxGap - minGap >= 4
    }

    private func earlyAveragePace(_ workout: Workout) -> Double {
        average(segmentValues(workout, segment: .early).map(\.paceSeconds))
    }

    private func lateAveragePace(_ workout: Workout) -> Double {
        average(segmentValues(workout, segment: .late).map(\.paceSeconds))
    }

    private func earlyAverageHeartRate(_ workout: Workout) -> Double {
        average(segmentValues(workout, segment: .early).map { Double($0.heartRate) })
    }

    private func lateAverageHeartRate(_ workout: Workout) -> Double {
        average(segmentValues(workout, segment: .late).map { Double($0.heartRate) })
    }

    private enum Segment {
        case early
        case late
    }

    private func segmentValues(_ workout: Workout, segment: Segment) -> [WorkoutSample] {
        let orderedSamples = workout.samples.sorted { $0.minute < $1.minute }
        let segmentSize = max(orderedSamples.count / 3, 1)
        switch segment {
        case .early:
            return Array(orderedSamples.prefix(segmentSize))
        case .late:
            return Array(orderedSamples.suffix(segmentSize))
        }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
