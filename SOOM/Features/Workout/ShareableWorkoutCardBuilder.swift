import Foundation

struct ShareableWorkoutCardBuilder {
    func build(
        sessionSummary: WorkoutSessionSummary,
        growthSummary: WorkoutGrowthSummary,
        recoveryImpact: WorkoutRecoveryImpact,
        input: WorkoutGrowthInput,
        visibility: ShareableWorkoutVisibility = .privateOnly
    ) -> ShareableWorkoutCardModel {
        ShareableWorkoutCardModel(
            id: input.id,
            workoutType: input.workoutType,
            title: title(for: input.workoutType),
            distanceText: distanceText(from: input),
            durationText: durationText(from: input),
            primaryMessage: sessionSummary.title,
            growthMessage: growthMessage(from: growthSummary),
            recoveryMessage: recoveryMessage(from: recoveryImpact),
            footerText: footerText(for: visibility),
            visibility: visibility
        )
    }

    func build(
        workout: Workout,
        sessionSummary: WorkoutSessionSummary,
        growthSummary: WorkoutGrowthSummary,
        recoveryImpact: WorkoutRecoveryImpact,
        visibility: ShareableWorkoutVisibility = .privateOnly
    ) -> ShareableWorkoutCardModel {
        build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: WorkoutGrowthInput(shareableWorkout: workout),
            visibility: visibility
        )
    }

    private func title(for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .running:
            return "오늘의 러닝"
        case .cycling:
            return "오늘의 라이딩"
        case .swimming:
            return "오늘의 수영"
        case .walking:
            return "오늘의 걷기"
        case .hiking:
            return "오늘의 하이킹"
        case .strength:
            return "오늘의 근력 운동"
        case .yoga:
            return "오늘의 요가"
        case .other:
            return "오늘의 운동"
        }
    }

    private func distanceText(from input: WorkoutGrowthInput) -> String {
        guard let distanceKm = input.distanceKm, distanceKm > 0 else {
            return "거리 기록 없음"
        }

        return String(format: "%.2f km", distanceKm)
    }

    private func durationText(from input: WorkoutGrowthInput) -> String {
        let minutes = max(input.durationMinutes, 0)
        if minutes >= 60 {
            return "\(minutes / 60)시간 \(minutes % 60)분"
        }

        return "\(minutes)분"
    }

    private func growthMessage(from summary: WorkoutGrowthSummary) -> String {
        if summary.improvementType == .none {
            return "오늘 기록은 다음 성장을 위한 기준점이에요."
        }

        return summary.motivationText
    }

    private func recoveryMessage(from impact: WorkoutRecoveryImpact) -> String {
        switch impact.impactLevel {
        case .high:
            return "회복 흐름을 함께 챙기면 다음 운동이 더 안정적일 수 있어요."
        case .recoveryFriendly:
            return "회복 흐름을 생각한 좋은 강도였어요."
        case .light, .moderate:
            return impact.shortMessage
        case .insufficientData:
            return "회복 연결은 기록이 더 쌓이면 더 선명해져요."
        }
    }

    private func footerText(for visibility: ShareableWorkoutVisibility) -> String {
        switch visibility {
        case .privateOnly:
            return "SOOM · 공유 전 미리보기"
        case .followers:
            return "SOOM · 팔로워 공유 예정"
        case .publicFeed:
            return "SOOM · 공개 피드 공유 예정"
        }
    }
}

private extension WorkoutGrowthInput {
    init(shareableWorkout workout: Workout) {
        self.init(
            id: workout.id,
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(shareableSport: workout.sport),
            startDate: workout.date,
            durationMinutes: Int(workout.duration / 60),
            distanceKm: workout.distanceMeters > 0 ? workout.distanceMeters / 1_000 : nil,
            averagePaceText: workout.sport == .run ? workout.formattedPace : nil,
            averageSpeedKmh: workout.duration > 0 ? (workout.distanceMeters / 1_000) / (workout.duration / 3_600) : nil,
            averageHeartRate: nil,
            elevationGainMeters: nil,
            activeEnergyKcal: nil
        )
    }
}

private extension UnifiedWorkoutType {
    init(shareableSport sport: WorkoutSport) {
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
