import Foundation

struct WorkoutRecoveryImpactBuilder {
    func build(
        input: WorkoutGrowthInput?,
        recoverySummary: RecoverySummary? = nil
    ) -> WorkoutRecoveryImpact {
        guard let input else {
            return insufficientDataImpact()
        }

        let duration = input.durationMinutes
        let heartRate = input.averageHeartRate
        let score = recoverySummary?.score
        let status = recoverySummary?.status ?? ""

        if isRecoveryFriendly(duration: duration, heartRate: heartRate) {
            return WorkoutRecoveryImpact(
                impactLevel: .recoveryFriendly,
                title: "회복 리듬에 잘 맞는 움직임",
                shortMessage: "가벼운 회복 활동으로는 좋은 흐름이었어요.",
                recommendation: "다음 세션도 몸이 가볍게 반응하는지 먼저 확인해보세요.",
                icon: SOOMIcon.recovery
            )
        }

        if isHighImpact(duration: duration, heartRate: heartRate, score: score, status: status) {
            return WorkoutRecoveryImpact(
                impactLevel: .high,
                title: "회복 리듬을 조금 더 챙길 운동",
                shortMessage: "오늘 운동은 회복 흐름에 조금 영향을 줄 수 있어요.",
                recommendation: "다음 운동 전에는 수면감과 피로감을 확인하고 강도를 천천히 올려보세요.",
                icon: SOOMIcon.bolt
            )
        }

        if isLightImpact(duration: duration, heartRate: heartRate) {
            return WorkoutRecoveryImpact(
                impactLevel: .light,
                title: "부담이 크지 않은 운동",
                shortMessage: "회복 흐름을 크게 흔들기보다 리듬을 이어가는 쪽에 가까워요.",
                recommendation: "가벼운 스트레칭이나 수분 보충으로 마무리하면 좋아요.",
                icon: SOOMIcon.trendFlat
            )
        }

        return WorkoutRecoveryImpact(
            impactLevel: .moderate,
            title: "적당한 자극이 있는 운동",
            shortMessage: "오늘 운동은 몸에 적당한 자극을 남기는 흐름이에요.",
            recommendation: "다음 운동 전 회복 리듬을 한 번 확인하고 비슷한 강도를 이어가보세요.",
            icon: SOOMIcon.waveform
        )
    }

    func build(
        workout: Workout,
        recoverySummary: RecoverySummary? = nil
    ) -> WorkoutRecoveryImpact {
        build(input: WorkoutGrowthInput(workout: workout), recoverySummary: recoverySummary)
    }

    private func isRecoveryFriendly(duration: Int, heartRate: Double?) -> Bool {
        duration <= 45 && (heartRate ?? 0) > 0 && (heartRate ?? 0) <= 135
    }

    private func isHighImpact(duration: Int, heartRate: Double?, score: Int?, status: String) -> Bool {
        let highDuration = duration >= 75
        let highHeartRate = (heartRate ?? 0) >= 155
        let recoveryStatus = (score ?? 100) <= 69 || status.contains("회복") || status.contains("주의")

        return (highDuration && highHeartRate) || (recoveryStatus && (highDuration || highHeartRate))
    }

    private func isLightImpact(duration: Int, heartRate: Double?) -> Bool {
        duration <= 50 && (heartRate == nil || (heartRate ?? 0) <= 145)
    }

    private func insufficientDataImpact() -> WorkoutRecoveryImpact {
        WorkoutRecoveryImpact(
            impactLevel: .insufficientData,
            title: "회복 영향 해석 준비 중",
            shortMessage: "운동 시간이나 심박 기록이 더 쌓이면 회복 흐름과 연결해 볼 수 있어요.",
            recommendation: "지금은 운동 요약과 최근 컨디션을 함께 확인해보세요.",
            icon: SOOMIcon.checkCircle
        )
    }
}

private extension WorkoutGrowthInput {
    init(workout: Workout) {
        self.init(
            id: workout.id,
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(sport: workout.sport),
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
    init(sport: WorkoutSport) {
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
