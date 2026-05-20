import Foundation

struct WorkoutSessionSummaryBuilder {
    func build(
        growthSummary: WorkoutGrowthSummary?,
        weaknessInsight: WorkoutWeaknessInsight?,
        recoveryImpact: WorkoutRecoveryImpact?,
        input: WorkoutGrowthInput? = nil
    ) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            title: title(growthSummary: growthSummary, recoveryImpact: recoveryImpact),
            summaryText: summaryText(for: input),
            highlightText: highlightText(from: growthSummary),
            improvementText: improvementText(from: weaknessInsight),
            recoveryText: recoveryText(from: recoveryImpact),
            closingMotivation: closingMotivation(
                growthSummary: growthSummary,
                weaknessInsight: weaknessInsight,
                recoveryImpact: recoveryImpact
            ),
            icon: growthSummary?.improvementType.icon ?? recoveryImpact?.icon ?? SOOMIcon.sparkles
        )
    }

    func build(
        workout: Workout,
        growthSummary: WorkoutGrowthSummary,
        weaknessInsight: WorkoutWeaknessInsight,
        recoveryImpact: WorkoutRecoveryImpact
    ) -> WorkoutSessionSummary {
        build(
            growthSummary: growthSummary,
            weaknessInsight: weaknessInsight,
            recoveryImpact: recoveryImpact,
            input: WorkoutGrowthInput(sessionWorkout: workout)
        )
    }

    private func title(
        growthSummary: WorkoutGrowthSummary?,
        recoveryImpact: WorkoutRecoveryImpact?
    ) -> String {
        if recoveryImpact?.impactLevel == .high {
            return "오늘 운동은 회복 리듬까지 챙길 기록이에요"
        }

        if growthSummary?.improvementType == WorkoutGrowthImprovementType.none {
            return "오늘 운동은 성장 기준점을 만든 기록이에요"
        }

        if growthSummary == nil && recoveryImpact == nil {
            return "오늘 운동 흐름을 정리하고 있어요"
        }

        return "오늘 운동은 리듬을 잘 이어간 기록이에요"
    }

    private func summaryText(for input: WorkoutGrowthInput?) -> String {
        guard let input else {
            return "운동 기록이 더 쌓이면 성장과 회복 흐름을 함께 정리할 수 있어요."
        }

        let duration = "\(input.durationMinutes)분"
        if let distanceKm = input.distanceKm, distanceKm > 0 {
            return "오늘은 \(String(format: "%.1f km", distanceKm)) · \(duration) 동안 움직이며 현재 루틴의 기준을 쌓았어요."
        }

        return "오늘은 \(duration) 동안 움직이며 현재 루틴의 기준을 쌓았어요."
    }

    private func highlightText(from summary: WorkoutGrowthSummary?) -> String {
        summary?.shortSummary ?? "오늘 기록은 다음 비교를 위한 기준점이에요."
    }

    private func improvementText(from insight: WorkoutWeaknessInsight?) -> String {
        guard let insight, insight.insightType != .none else {
            return "크게 흔들린 지점은 적고, 같은 조건의 기록을 더 쌓아보면 좋아요."
        }

        return insight.shortInsight
    }

    private func recoveryText(from impact: WorkoutRecoveryImpact?) -> String {
        impact?.shortMessage ?? "회복 흐름과의 연결은 기록이 더 쌓이면 선명해져요."
    }

    private func closingMotivation(
        growthSummary: WorkoutGrowthSummary?,
        weaknessInsight: WorkoutWeaknessInsight?,
        recoveryImpact: WorkoutRecoveryImpact?
    ) -> String {
        if let weaknessInsight, weaknessInsight.insightType != .none {
            return weaknessInsight.suggestion
        }

        if let recoveryImpact, recoveryImpact.impactLevel != .insufficientData {
            return recoveryImpact.recommendation
        }

        return growthSummary?.motivationText ?? "다음 운동도 오늘 기록을 기준으로 가볍게 이어가보세요."
    }
}

private extension WorkoutGrowthInput {
    init(sessionWorkout workout: Workout) {
        self.init(
            id: workout.id,
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(sessionSport: workout.sport),
            startDate: workout.date,
            durationMinutes: Int(workout.duration / 60),
            distanceKm: workout.distanceMeters > 0 ? workout.distanceMeters / 1_000 : nil,
            averagePaceText: workout.sport == .run ? workout.formattedPace : nil,
            averageSpeedKmh: workout.duration > 0 ? (workout.distanceMeters / 1_000) / (workout.duration / 3_600) : nil,
            averageHeartRate: Double(workout.avgHeartRate),
            elevationGainMeters: Double(workout.elevationGain),
            activeEnergyKcal: Double(workout.activeCalories)
        )
    }
}

private extension UnifiedWorkoutType {
    init(sessionSport sport: WorkoutSport) {
        switch sport {
        case .swim:
            self = .swimming
        case .bike, .brick:
            self = .cycling
        case .run:
            self = .running
        }
    }
}
