import Foundation

struct WorkoutGrowthSummaryBuilder {
    func build(current workout: Workout, recentWorkouts: [Workout]) -> WorkoutGrowthSummary {
        let previousWorkouts = recentWorkouts
            .filter { $0.id != workout.id && $0.date < workout.date }
            .sorted { $0.date > $1.date }

        guard !previousWorkouts.isEmpty else {
            return noComparisonSummary(for: workout)
        }

        let sameSportPrevious = previousWorkouts.first { $0.sport == workout.sport }
        let sameWeekWorkouts = recentWorkouts.filter { isSameWeek($0.date, workout.date) }

        if let previous = sameSportPrevious,
           workout.distanceMeters >= previous.distanceMeters * 1.08 {
            return WorkoutGrowthSummary(
                workoutId: workout.id,
                title: "더 오래 움직였어요",
                shortSummary: "오늘은 같은 종목의 최근 기록보다 지구력 흐름이 좋아졌어요.",
                improvementType: .endurance,
                comparisonText: "\(formattedDistance(workout.distanceMeters)) · 이전 \(formattedDistance(previous.distanceMeters))",
                motivationText: "지난 기록보다 더 오래 움직인 건 좋은 성장 신호예요.",
                insight: "다음에는 같은 리듬을 유지하면서 회복 여유를 확인해보세요."
            )
        }

        if let previous = sameSportPrevious,
           paceSeconds(for: workout) <= paceSeconds(for: previous) * 0.97 {
            return WorkoutGrowthSummary(
                workoutId: workout.id,
                title: "페이스 흐름이 좋아졌어요",
                shortSummary: "비슷한 운동보다 평균 페이스가 조금 더 안정적이었어요.",
                improvementType: .pace,
                comparisonText: "\(workout.formattedPace) · 이전 \(previous.formattedPace)",
                motivationText: "기록보다 중요한 건 흔들림이 줄어드는 흐름이에요.",
                insight: "다음 운동도 초반을 차분하게 시작하면 후반 리듬을 더 잘 지킬 수 있어요."
            )
        }

        if sameWeekWorkouts.count >= 3 {
            return WorkoutGrowthSummary(
                workoutId: workout.id,
                title: "이번 주 꾸준함이 좋아요",
                shortSummary: "최근 운동 빈도가 안정적으로 이어지고 있어요.",
                improvementType: .consistency,
                comparisonText: "이번 주 \(sameWeekWorkouts.count)회 운동",
                motivationText: "오늘은 기록보다 꾸준함이 더 좋은 신호예요.",
                insight: "다음 운동은 강도를 올리기보다 같은 리듬을 이어가는 쪽이 좋아요."
            )
        }

        if hasStableLateHeartRate(workout) {
            return WorkoutGrowthSummary(
                workoutId: workout.id,
                title: "후반 리듬이 안정적이에요",
                shortSummary: "운동 후반에도 심박 흐름이 크게 흔들리지 않았어요.",
                improvementType: .recovery,
                comparisonText: "후반 심박 상승 폭 안정",
                motivationText: "무리하지 않고 리듬을 지킨 점이 좋은 신호예요.",
                insight: "다음 세션에서도 마지막 구간을 억지로 밀기보다 안정적으로 마무리해보세요."
            )
        }

        return WorkoutGrowthSummary(
            workoutId: workout.id,
            title: "운동 흐름을 확인했어요",
            shortSummary: "오늘 운동은 현재 루틴을 이해하는 기준점이 됩니다.",
            improvementType: .effort,
            comparisonText: "\(workout.formattedDistance) · \(workout.formattedDuration)",
            motivationText: "성장은 큰 변화보다 반복해서 쌓이는 기록에서 시작돼요.",
            insight: "다음에는 같은 조건에서 페이스와 심박 흐름을 다시 비교해보세요."
        )
    }

    private func noComparisonSummary(for workout: Workout) -> WorkoutGrowthSummary {
        WorkoutGrowthSummary(
            workoutId: workout.id,
            title: "성장 기준점을 만들었어요",
            shortSummary: "비교할 최근 기록이 아직 부족해 오늘 운동을 기준 기록으로 저장해요.",
            improvementType: .none,
            comparisonText: "\(workout.formattedDistance) · \(workout.formattedDuration)",
            motivationText: "기록이 쌓이면 좋아진 점을 더 선명하게 보여줄 수 있어요.",
            insight: nil
        )
    }

    private func paceSeconds(for workout: Workout) -> Double {
        guard workout.distanceMeters > 0 else { return .greatestFiniteMagnitude }
        return workout.duration / (workout.distanceMeters / 1_000)
    }

    private func formattedDistance(_ meters: Double) -> String {
        String(format: "%.1f km", meters / 1_000)
    }

    private func isSameWeek(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, equalTo: rhs, toGranularity: .weekOfYear)
    }

    private func hasStableLateHeartRate(_ workout: Workout) -> Bool {
        guard workout.samples.count >= 6 else { return false }
        let orderedSamples = workout.samples.sorted { $0.minute < $1.minute }
        let segmentSize = max(orderedSamples.count / 3, 1)
        let firstSegment = orderedSamples.prefix(segmentSize)
        let lastSegment = orderedSamples.suffix(segmentSize)
        let firstAverage = averageHeartRate(firstSegment.map(\.heartRate))
        let lastAverage = averageHeartRate(lastSegment.map(\.heartRate))

        return lastAverage - firstAverage <= 8
    }

    private func averageHeartRate(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}
