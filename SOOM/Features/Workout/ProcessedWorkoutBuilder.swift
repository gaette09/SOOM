import Foundation

struct ProcessedWorkoutBuilder {
    var calendar: Calendar = .current
    var locale: Locale = Locale(identifier: "ko_KR")

    func make(from workout: UnifiedWorkout, route: WorkoutRoute? = nil, hasHeartRateSeries: Bool = false) -> ProcessedWorkout {
        let processedRoute = route.map(makeRoute)
        let measuredDistance = positive(workout.distanceMeters)
        let routeDistance = processedRoute?.hasRenderableRoute == true
            ? positive(processedRoute?.totalDistanceMeters)
            : nil
        let distanceMeters = measuredDistance ?? routeDistance
        let distanceState: ProcessedWorkoutMetricState = measuredDistance != nil
            ? .measured
            : routeDistance != nil ? .derived : .missing

        let measuredSpeed = positive(workout.averageSpeedMetersPerSecond)
        let derivedSpeed = averageSpeed(distanceMeters: distanceMeters, durationSeconds: workout.durationSeconds)
        let averageSpeed = measuredSpeed ?? derivedSpeed
        let speedState: ProcessedWorkoutMetricState = measuredSpeed != nil
            ? .measured
            : derivedSpeed != nil ? .derived : .missing

        let paceSeconds = averagePaceSeconds(
            workoutType: workout.workoutType,
            distanceMeters: distanceMeters,
            durationSeconds: workout.durationSeconds
        )
        let paceState: ProcessedWorkoutMetricState = supportsPace(workout.workoutType)
            ? paceSeconds != nil ? .derived : .missing
            : .unsupported

        let measuredElevation = positive(workout.elevationGainMeters)
        let routeElevation = processedRoute?.hasRenderableRoute == true
            ? positive(processedRoute?.totalElevationGainMeters)
            : nil
        let elevationGain = measuredElevation ?? routeElevation
        let elevationState: ProcessedWorkoutMetricState = measuredElevation != nil
            ? .measured
            : routeElevation != nil ? .derived : .missing

        var availability = baseAvailability(
            workoutType: workout.workoutType,
            durationSeconds: workout.durationSeconds,
            distanceState: distanceState,
            speedState: speedState,
            paceState: paceState,
            elevationState: elevationState,
            route: processedRoute,
            workout: workout,
            hasHeartRateSeries: hasHeartRateSeries
        )

        let processed = ProcessedWorkout(
            id: workout.id,
            externalId: workout.externalId,
            source: workout.source,
            workoutType: workout.workoutType,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            durationSeconds: max(workout.durationSeconds, 0),
            isExcludedFromAnalysis: workout.isExcludedFromAnalysis,
            dataQuality: workout.dataQuality,
            distanceMeters: distanceMeters,
            averageSpeedMetersPerSecond: averageSpeed,
            averagePaceSecondsPerKilometer: paceSeconds,
            activeEnergyKcal: positive(workout.activeEnergyKcal),
            averageHeartRate: positive(workout.averageHeartRate),
            maxHeartRate: positive(workout.maxHeartRate),
            elevationGainMeters: elevationGain,
            averagePowerWatts: positive(workout.averagePowerWatts),
            averageCadence: positive(workout.averageCadence),
            route: processedRoute,
            routeMissingReason: processedRoute?.hasRenderableRoute == true ? .none : workout.routeMissingReason,
            metricAvailability: availability,
            display: WorkoutDisplaySnapshot.empty
        )

        availability[.duration] = processed.durationSeconds > 0 ? .measured : .missing

        return ProcessedWorkout(
            id: processed.id,
            externalId: processed.externalId,
            source: processed.source,
            workoutType: processed.workoutType,
            startedAt: processed.startedAt,
            endedAt: processed.endedAt,
            durationSeconds: processed.durationSeconds,
            isExcludedFromAnalysis: processed.isExcludedFromAnalysis,
            dataQuality: processed.dataQuality,
            distanceMeters: processed.distanceMeters,
            averageSpeedMetersPerSecond: processed.averageSpeedMetersPerSecond,
            averagePaceSecondsPerKilometer: processed.averagePaceSecondsPerKilometer,
            activeEnergyKcal: processed.activeEnergyKcal,
            averageHeartRate: processed.averageHeartRate,
            maxHeartRate: processed.maxHeartRate,
            elevationGainMeters: processed.elevationGainMeters,
            averagePowerWatts: processed.averagePowerWatts,
            averageCadence: processed.averageCadence,
            route: processed.route,
            routeMissingReason: processed.routeMissingReason,
            metricAvailability: availability,
            display: displaySnapshot(for: processed, availability: availability)
        )
    }

    private func makeRoute(_ route: WorkoutRoute) -> ProcessedWorkoutRoute {
        ProcessedWorkoutRoute(
            workoutId: route.workoutId,
            source: route.source,
            coordinates: route.coordinates,
            coordinateCount: route.coordinates.count,
            totalDistanceMeters: route.totalDistanceMeters,
            totalElevationGainMeters: route.totalElevationGain,
            bounds: route.bounds,
            hasRenderableRoute: route.coordinates.count >= 2,
            courseIdentity: nil
        )
    }

    private func baseAvailability(
        workoutType: UnifiedWorkoutType,
        durationSeconds: TimeInterval,
        distanceState: ProcessedWorkoutMetricState,
        speedState: ProcessedWorkoutMetricState,
        paceState: ProcessedWorkoutMetricState,
        elevationState: ProcessedWorkoutMetricState,
        route: ProcessedWorkoutRoute?,
        workout: UnifiedWorkout,
        hasHeartRateSeries: Bool
    ) -> [ProcessedWorkoutMetric: ProcessedWorkoutMetricState] {
        [
            .distance: distanceState,
            .duration: durationSeconds > 0 ? .measured : .missing,
            .pace: paceState,
            .speed: supportsSpeed(workoutType) ? speedState : .unsupported,
            .elevation: elevationState,
            .calories: positive(workout.activeEnergyKcal) != nil ? .measured : .missing,
            .averageHeartRate: positive(workout.averageHeartRate) != nil ? .measured : .missing,
            .maxHeartRate: positive(workout.maxHeartRate) != nil ? .measured : .missing,
            .power: supportsPower(workoutType) ? (positive(workout.averagePowerWatts) != nil ? .measured : .missing) : .unsupported,
            .cadence: supportsCadence(workoutType) ? (positive(workout.averageCadence) != nil ? .measured : .missing) : .unsupported,
            .route: route?.hasRenderableRoute == true ? .measured : .missing,
            .splits: .missing,
            .zones: .missing,
            .speedSeries: hasSeries(route, minimum: 2) { $0.timestamp != nil } ? .measured : .missing,
            .elevationSeries: hasSeries(route, minimum: 2) { $0.altitude != nil } ? .measured : .missing,
            .heartRateSeries: hasHeartRateSeries ? .measured : .missing
        ]
    }

    private func hasSeries(
        _ route: ProcessedWorkoutRoute?,
        minimum: Int,
        where predicate: (WorkoutRouteCoordinate) -> Bool
    ) -> Bool {
        guard let route else { return false }
        return route.coordinates.filter(predicate).count >= minimum
    }

    private func displaySnapshot(
        for workout: ProcessedWorkout,
        availability: [ProcessedWorkoutMetric: ProcessedWorkoutMetricState]
    ) -> WorkoutDisplaySnapshot {
        let primary = primaryMetric(for: workout)

        return WorkoutDisplaySnapshot(
            sportTitle: sportTitle(for: workout.workoutType),
            sportIconName: sportIconName(for: workout.workoutType),
            sourceTitle: sourceTitle(for: workout.source),
            dateText: dateText(for: workout.startedAt),
            timeText: timeText(for: workout.startedAt),
            durationText: durationText(workout.durationSeconds),
            distanceText: distanceText(workout.distanceMeters),
            primaryMetricLabel: primary.label,
            primaryMetricValue: primary.value,
            speedText: speedText(workout.averageSpeedMetersPerSecond),
            paceText: paceText(workout.averagePaceSecondsPerKilometer),
            elevationText: elevationText(workout.elevationGainMeters),
            caloriesText: caloriesText(workout.activeEnergyKcal),
            averageHeartRateText: heartRateText(workout.averageHeartRate),
            maxHeartRateText: heartRateText(workout.maxHeartRate),
            averagePowerText: powerText(workout.averagePowerWatts),
            averageCadenceText: cadenceText(workout.averageCadence),
            dataQualityLabel: dataQualityTitle(for: workout.dataQuality),
            routeBadgeLabel: availability[.route] == .measured ? "경로 저장" : nil
        )
    }

    private func primaryMetric(for workout: ProcessedWorkout) -> (label: String, value: String) {
        switch workout.workoutType {
        case .running, .hiking:
            return ("페이스", paceText(workout.averagePaceSecondsPerKilometer))
        case .cycling, .walking:
            return ("속도", speedText(workout.averageSpeedMetersPerSecond))
        case .swimming:
            return ("거리", distanceText(workout.distanceMeters))
        case .strength, .yoga, .other:
            return ("시간", durationText(workout.durationSeconds))
        }
    }

    private func averageSpeed(distanceMeters: Double?, durationSeconds: TimeInterval) -> Double? {
        guard let distanceMeters, distanceMeters > 0, durationSeconds > 0 else { return nil }
        return distanceMeters / durationSeconds
    }

    private func averagePaceSeconds(
        workoutType: UnifiedWorkoutType,
        distanceMeters: Double?,
        durationSeconds: TimeInterval
    ) -> Double? {
        guard supportsPace(workoutType), let distanceMeters, distanceMeters > 0, durationSeconds > 0 else {
            return nil
        }

        return durationSeconds / (distanceMeters / 1_000)
    }

    private func supportsPace(_ workoutType: UnifiedWorkoutType) -> Bool {
        switch workoutType {
        case .running, .hiking:
            return true
        case .cycling, .walking, .swimming, .strength, .yoga, .other:
            return false
        }
    }

    private func supportsSpeed(_ workoutType: UnifiedWorkoutType) -> Bool {
        switch workoutType {
        case .cycling, .walking:
            return true
        case .running, .hiking, .swimming, .strength, .yoga, .other:
            return false
        }
    }

    private func supportsPower(_ workoutType: UnifiedWorkoutType) -> Bool {
        workoutType == .cycling
    }

    private func supportsCadence(_ workoutType: UnifiedWorkoutType) -> Bool {
        switch workoutType {
        case .cycling, .running, .walking, .hiking:
            return true
        case .swimming, .strength, .yoga, .other:
            return false
        }
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func distanceText(_ meters: Double?) -> String {
        guard let meters else { return "거리 준비 중" }
        return String(format: "%.2f km", meters / 1_000)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int((seconds / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }
        return "\(minutes)분"
    }

    private func speedText(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond else { return "움직임 준비 중" }
        return String(format: "%.1f km/h", metersPerSecond * 3.6)
    }

    private func paceText(_ secondsPerKilometer: Double?) -> String {
        guard let secondsPerKilometer else { return "움직임 준비 중" }
        let rounded = Int(secondsPerKilometer.rounded())
        return String(format: "%d:%02d/km", rounded / 60, rounded % 60)
    }

    private func elevationText(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        return "\(Int(meters.rounded()))m"
    }

    private func caloriesText(_ kcal: Double?) -> String {
        guard let kcal else { return "—" }
        return "\(Int(kcal.rounded()))kcal"
    }

    private func heartRateText(_ bpm: Double?) -> String {
        guard let bpm else { return "—" }
        return "\(Int(bpm.rounded()))bpm"
    }

    private func powerText(_ watts: Double?) -> String? {
        guard let watts else { return nil }
        return "\(Int(watts.rounded()))W"
    }

    private func cadenceText(_ rpm: Double?) -> String? {
        guard let rpm else { return nil }
        return "\(Int(rpm.rounded()))rpm"
    }

    private func dateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

    private func timeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: date)
    }

    private func sportTitle(for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .running:
            return "러닝"
        case .cycling:
            return "사이클"
        case .walking:
            return "걷기"
        case .swimming:
            return "수영"
        case .hiking:
            return "하이킹"
        case .strength:
            return "근력 운동"
        case .yoga:
            return "요가"
        case .other:
            return "운동"
        }
    }

    private func sportIconName(for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .running:
            return "figure.run"
        case .cycling:
            return "bicycle"
        case .walking:
            return "figure.walk"
        case .swimming:
            return "figure.pool.swim"
        case .hiking:
            return "figure.hiking"
        case .strength:
            return "dumbbell.fill"
        case .yoga:
            return "figure.yoga"
        case .other:
            return "figure.mixed.cardio"
        }
    }

    private func sourceTitle(for source: UnifiedDataSource) -> String {
        switch source {
        case .appleHealthKit:
            return "Apple Health"
        case .garmin:
            return "Garmin"
        case .strava:
            return "Strava"
        case .samsungHealth:
            return "Samsung Health"
        case .healthConnect:
            return "Health Connect"
        case .soomLocal:
            return "SOOM"
        case .manual:
            return "직접 입력"
        case .unknown:
            return "알 수 없음"
        }
    }

    private func dataQualityTitle(for quality: UnifiedDataQuality) -> String {
        switch quality {
        case .complete:
            return "완전"
        case .partial:
            return "부분"
        case .estimated:
            return "추정"
        case .missing:
            return "부족"
        case .unknown:
            return "알 수 없음"
        }
    }
}

private extension WorkoutDisplaySnapshot {
    static let empty = WorkoutDisplaySnapshot(
        sportTitle: "",
        sportIconName: "",
        sourceTitle: "",
        dateText: "",
        timeText: "",
        durationText: "",
        distanceText: "",
        primaryMetricLabel: "",
        primaryMetricValue: "",
        speedText: "",
        paceText: "",
        elevationText: "",
        caloriesText: "",
        averageHeartRateText: "",
        maxHeartRateText: "",
        averagePowerText: nil,
        averageCadenceText: nil,
        dataQualityLabel: "",
        routeBadgeLabel: nil
    )
}
