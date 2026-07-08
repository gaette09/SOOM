import Foundation

struct ShareableWorkoutCardBuilder {
    private let staticRoutePreviewBuilder: StaticRoutePreviewBuilder

    init(staticRoutePreviewBuilder: StaticRoutePreviewBuilder = StaticRoutePreviewBuilder()) {
        self.staticRoutePreviewBuilder = staticRoutePreviewBuilder
    }

    func build(
        sessionSummary: WorkoutSessionSummary,
        growthSummary: WorkoutGrowthSummary,
        recoveryImpact: WorkoutRecoveryImpact,
        input: WorkoutGrowthInput,
        visibility: ShareableWorkoutVisibility = .privateOnly,
        staticRoutePreview: StaticRoutePreview? = nil
    ) -> ShareableWorkoutCardModel {
        build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            processedWorkout: ProcessedWorkoutBuilder().make(from: unifiedWorkout(from: input)),
            visibility: visibility,
            staticRoutePreview: staticRoutePreview
        )
    }

    func build(
        sessionSummary: WorkoutSessionSummary,
        growthSummary: WorkoutGrowthSummary,
        recoveryImpact: WorkoutRecoveryImpact,
        processedWorkout: ProcessedWorkout,
        visibility: ShareableWorkoutVisibility = .privateOnly,
        staticRoutePreview: StaticRoutePreview? = nil
    ) -> ShareableWorkoutCardModel {
        let display = processedWorkout.display
        return ShareableWorkoutCardModel(
            id: processedWorkout.id,
            workoutType: processedWorkout.workoutType,
            title: title(for: processedWorkout.workoutType),
            distanceText: display.distanceText,
            durationText: display.durationText,
            averagePaceText: primaryMovementText(from: processedWorkout),
            elevationGainText: optionalMetricText(display.elevationText),
            averageHeartRateText: optionalMetricText(display.averageHeartRateText),
            activeEnergyText: optionalMetricText(display.caloriesText),
            primaryMessage: sessionSummary.title,
            growthMessage: growthMessage(from: growthSummary),
            recoveryMessage: recoveryMessage(from: recoveryImpact),
            footerText: footerText(for: visibility),
            visibility: visibility,
            staticRoutePreview: staticRoutePreview
        )
    }

    func build(
        sessionSummary: WorkoutSessionSummary,
        growthSummary: WorkoutGrowthSummary,
        recoveryImpact: WorkoutRecoveryImpact,
        input: WorkoutGrowthInput,
        route: WorkoutRoute?,
        visibility: ShareableWorkoutVisibility = .privateOnly,
        routePrivacyPolicy: RoutePrivacyMaskingPolicy = .defaultShare
    ) -> ShareableWorkoutCardModel {
        let preview = route.map {
            staticRoutePreviewBuilder.build(
                route: $0,
                workoutType: input.workoutType,
                privacyPolicy: routePrivacyPolicy
            )
        }
        let processedWorkout = ProcessedWorkoutBuilder().make(
            from: unifiedWorkout(from: input),
            route: route
        )

        return build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            processedWorkout: processedWorkout,
            visibility: visibility,
            staticRoutePreview: preview
        )
    }

    func build(
        workout: Workout,
        sessionSummary: WorkoutSessionSummary,
        growthSummary: WorkoutGrowthSummary,
        recoveryImpact: WorkoutRecoveryImpact,
        route: WorkoutRoute?,
        visibility: ShareableWorkoutVisibility = .privateOnly
    ) -> ShareableWorkoutCardModel {
        let routePreview = route.map {
            staticRoutePreviewBuilder.build(
                route: $0,
                workoutType: UnifiedWorkoutType(shareableSport: workout.sport),
                privacyPolicy: .defaultShare
            )
        }

        let processedWorkout = ProcessedWorkoutBuilder().make(from: unifiedWorkout(from: workout), route: route)

        return build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            processedWorkout: processedWorkout,
            visibility: visibility,
            staticRoutePreview: routePreview
        )
    }

    func build(
        workout: Workout,
        sessionSummary: WorkoutSessionSummary,
        growthSummary: WorkoutGrowthSummary,
        recoveryImpact: WorkoutRecoveryImpact,
        visibility: ShareableWorkoutVisibility = .privateOnly,
        staticRoutePreview: StaticRoutePreview? = nil
    ) -> ShareableWorkoutCardModel {
        build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            processedWorkout: ProcessedWorkoutBuilder().make(from: unifiedWorkout(from: workout)),
            visibility: visibility,
            staticRoutePreview: staticRoutePreview ?? makeStaticRoutePreview(for: workout)
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

    private func primaryMovementText(from processedWorkout: ProcessedWorkout) -> String? {
        switch processedWorkout.workoutType {
        case .running, .hiking:
            return processedWorkout.display.paceText
        case .cycling, .walking:
            return processedWorkout.display.speedText
        case .swimming, .strength, .yoga, .other:
            return nil
        }
    }

    private func optionalMetricText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != "—" else {
            return nil
        }
        return trimmed
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

    private func makeStaticRoutePreview(for workout: Workout) -> StaticRoutePreview? {
        guard workout.route.count >= 2 else { return nil }

        let route = WorkoutRoute(
            workoutId: workout.id,
            source: .soomLocal,
            coordinates: workout.route.map {
                WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            totalDistanceMeters: workout.distanceMeters,
            totalElevationGain: workout.elevationGain > 0 ? Double(workout.elevationGain) : nil
        )

        return staticRoutePreviewBuilder.build(
            route: route,
            workoutType: UnifiedWorkoutType(shareableSport: workout.sport),
            privacyPolicy: .defaultShare
        )
    }

    private func unifiedWorkout(from input: WorkoutGrowthInput) -> UnifiedWorkout {
        let durationSeconds = TimeInterval(max(input.durationMinutes, 0) * 60)
        return UnifiedWorkout(
            id: input.id,
            externalId: nil,
            source: input.source,
            workoutType: input.workoutType,
            startDate: input.startDate,
            endDate: input.startDate.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: input.distanceKm.map { $0 * 1_000 },
            activeEnergyKcal: input.activeEnergyKcal,
            averageHeartRate: input.averageHeartRate,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: input.averageSpeedKmh.map { $0 / 3.6 },
            elevationGainMeters: input.elevationGainMeters,
            dataQuality: .partial,
            createdAt: input.startDate,
            updatedAt: input.startDate
        )
    }

    private func unifiedWorkout(from workout: Workout) -> UnifiedWorkout {
        UnifiedWorkout(
            id: workout.id,
            externalId: "share-card-\(workout.id.uuidString)",
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(shareableSport: workout.sport),
            startDate: workout.date,
            endDate: workout.date.addingTimeInterval(workout.duration),
            durationSeconds: workout.duration,
            distanceMeters: workout.distanceMeters > 0 ? workout.distanceMeters : nil,
            activeEnergyKcal: workout.activeCalories > 0 ? Double(workout.activeCalories) : nil,
            averageHeartRate: workout.avgHeartRate > 0 ? Double(workout.avgHeartRate) : nil,
            maxHeartRate: workout.maxHeartRate > 0 ? Double(workout.maxHeartRate) : nil,
            averageSpeedMetersPerSecond: workout.duration > 0 && workout.distanceMeters > 0 ? workout.distanceMeters / workout.duration : nil,
            elevationGainMeters: workout.elevationGain > 0 ? Double(workout.elevationGain) : nil,
            dataQuality: .partial,
            createdAt: workout.date,
            updatedAt: workout.date
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
