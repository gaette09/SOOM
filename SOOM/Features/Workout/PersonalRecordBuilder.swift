import Foundation

struct PersonalRecordBuilder {
    func build(workouts: [Workout], referenceDate: Date = Date()) -> [PersonalRecord] {
        let inputs = workouts.map { workout in
            WorkoutGrowthInput(
                id: workout.id,
                source: .soomLocal,
                workoutType: workout.sport == .bike ? .cycling : workout.sport == .swim ? .swimming : .running,
                startDate: workout.date,
                durationMinutes: max(Int((workout.duration / 60).rounded()), 1),
                distanceKm: workout.distanceMeters / 1_000,
                averagePaceText: nil,
                averageSpeedKmh: nil,
                averageHeartRate: Double(workout.avgHeartRate),
                elevationGainMeters: Double(workout.elevationGain),
                activeEnergyKcal: Double(workout.activeCalories)
            )
        }

        return build(inputs: inputs, referenceDate: referenceDate)
    }

    func build(inputs: [WorkoutGrowthInput], referenceDate: Date = Date()) -> [PersonalRecord] {
        let recentInputs = inputs
            .filter { $0.startDate <= referenceDate }
            .sorted { $0.startDate > $1.startDate }

        guard !recentInputs.isEmpty else { return [] }

        var records: [PersonalRecord] = []

        if let distanceRecord = longestDistance(from: recentInputs) {
            records.append(distanceRecord)
        }

        if let paceRecord = bestPace(from: recentInputs) {
            records.append(paceRecord)
        } else if let speedRecord = bestAverageSpeed(from: recentInputs) {
            records.append(speedRecord)
        }

        if let durationRecord = longestDuration(from: recentInputs) {
            records.append(durationRecord)
        }

        if let elevationRecord = mostElevation(from: recentInputs) {
            records.append(elevationRecord)
        }

        if let consistencyRecord = weeklyConsistency(from: recentInputs, referenceDate: referenceDate) {
            records.append(consistencyRecord)
        }

        return Array(records.prefix(3))
    }

    private func longestDistance(from inputs: [WorkoutGrowthInput]) -> PersonalRecord? {
        guard let input = inputs
            .filter({ ($0.distanceKm ?? 0) > 0 })
            .max(by: { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }),
            let distance = input.distanceKm else {
            return nil
        }

        return PersonalRecord(
            workoutType: input.workoutType,
            metricType: .longestDistance,
            value: formattedDistance(distance),
            achievedAt: input.startDate,
            comparisonText: "최근 기록 중 가장 긴 거리예요.",
            motivationText: "조금씩 움직인 거리가 길어지고 있다는 좋은 신호예요."
        )
    }

    private func longestDuration(from inputs: [WorkoutGrowthInput]) -> PersonalRecord? {
        guard let input = inputs.max(by: { $0.durationMinutes < $1.durationMinutes }),
              input.durationMinutes > 0 else {
            return nil
        }

        return PersonalRecord(
            workoutType: input.workoutType,
            metricType: .longestDuration,
            value: formattedDuration(input.durationMinutes),
            achievedAt: input.startDate,
            comparisonText: "최근 기록 중 가장 오래 움직였어요.",
            motivationText: "오래 움직인 날은 지구력 기반을 쌓는 데 의미 있는 기록이에요."
        )
    }

    private func bestPace(from inputs: [WorkoutGrowthInput]) -> PersonalRecord? {
        let paceInputs = inputs.compactMap { input -> (WorkoutGrowthInput, Double)? in
            guard usesPace(input.workoutType),
                  let distance = input.distanceKm,
                  distance > 0,
                  input.durationMinutes > 0 else {
                return nil
            }

            return (input, Double(input.durationMinutes * 60) / distance)
        }

        guard let best = paceInputs.min(by: { $0.1 < $1.1 }) else { return nil }

        return PersonalRecord(
            workoutType: best.0.workoutType,
            metricType: .bestPace,
            value: formattedPace(secondsPerKm: best.1),
            achievedAt: best.0.startDate,
            comparisonText: "최근 기록 중 페이스가 가장 안정적이었어요.",
            motivationText: "빠른 기록보다 일정한 리듬을 만든 점이 좋은 성장 신호예요."
        )
    }

    private func bestAverageSpeed(from inputs: [WorkoutGrowthInput]) -> PersonalRecord? {
        let speedInputs = inputs.compactMap { input -> (WorkoutGrowthInput, Double)? in
            let speed = input.averageSpeedKmh ?? calculatedSpeed(for: input)
            guard let speed, speed > 0 else { return nil }
            return (input, speed)
        }

        guard let best = speedInputs.max(by: { $0.1 < $1.1 }) else { return nil }

        return PersonalRecord(
            workoutType: best.0.workoutType,
            metricType: .bestAverageSpeed,
            value: String(format: "%.1f km/h", best.1),
            achievedAt: best.0.startDate,
            comparisonText: "최근 기록 중 평균 속도가 가장 좋았어요.",
            motivationText: "속도보다 리듬을 유지한 흐름이 더 좋은 기반이 될 수 있어요."
        )
    }

    private func mostElevation(from inputs: [WorkoutGrowthInput]) -> PersonalRecord? {
        guard let input = inputs
            .filter({ ($0.elevationGainMeters ?? 0) > 0 })
            .max(by: { ($0.elevationGainMeters ?? 0) < ($1.elevationGainMeters ?? 0) }),
            let elevation = input.elevationGainMeters,
            elevation >= 50 else {
            return nil
        }

        return PersonalRecord(
            workoutType: input.workoutType,
            metricType: .mostElevation,
            value: "\(Int(elevation.rounded())) m",
            achievedAt: input.startDate,
            comparisonText: "최근 기록 중 오르막이 가장 많았어요.",
            motivationText: "고도 변화가 있는 운동은 같은 거리라도 더 탄탄한 자극이 될 수 있어요."
        )
    }

    private func weeklyConsistency(
        from inputs: [WorkoutGrowthInput],
        referenceDate: Date
    ) -> PersonalRecord? {
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        let currentWeekInputs = inputs.filter { $0.startDate >= weekStart && $0.startDate <= referenceDate }

        guard currentWeekInputs.count >= 3,
              let latest = currentWeekInputs.sorted(by: { $0.startDate > $1.startDate }).first else {
            return nil
        }

        return PersonalRecord(
            workoutType: latest.workoutType,
            metricType: .weeklyConsistency,
            value: "\(currentWeekInputs.count)회",
            achievedAt: latest.startDate,
            comparisonText: "이번 주 운동 리듬이 꾸준하게 이어졌어요.",
            motivationText: "기록 경신만큼 중요한 건 반복되는 루틴이에요."
        )
    }

    private func usesPace(_ type: UnifiedWorkoutType) -> Bool {
        switch type {
        case .running, .walking, .hiking:
            return true
        case .cycling, .swimming, .strength, .yoga, .other:
            return false
        }
    }

    private func calculatedSpeed(for input: WorkoutGrowthInput) -> Double? {
        guard let distance = input.distanceKm, input.durationMinutes > 0 else { return nil }
        return distance / (Double(input.durationMinutes) / 60)
    }

    private func formattedDistance(_ distance: Double) -> String {
        String(format: "%.1f km", distance)
    }

    private func formattedDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60)시간 \(minutes % 60)분"
        }
        return "\(minutes)분"
    }

    private func formattedPace(secondsPerKm: Double) -> String {
        let rounded = Int(secondsPerKm.rounded())
        return "\(rounded / 60):\(String(format: "%02d", rounded % 60))/km"
    }
}
