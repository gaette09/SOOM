import Foundation

struct WeeklyWorkoutProgressBuilder {
    func build(workouts: [Workout], referenceDate: Date? = nil) -> WeeklyWorkoutProgress {
        let samples = workouts.map { workout in
            WeeklyWorkoutSample(
                date: workout.date,
                workoutType: workout.sport == .bike ? .cycling : workout.sport == .swim ? .swimming : .running,
                distanceKm: workout.distanceMeters / 1_000,
                durationMinutes: Int(workout.duration / 60)
            )
        }

        return build(samples: samples, referenceDate: referenceDate)
    }

    func build(inputs: [WorkoutGrowthInput], referenceDate: Date? = nil) -> WeeklyWorkoutProgress {
        let samples = inputs.map { input in
            WeeklyWorkoutSample(
                date: input.startDate,
                workoutType: input.workoutType,
                distanceKm: input.distanceKm ?? 0,
                durationMinutes: input.durationMinutes
            )
        }

        return build(samples: samples, referenceDate: referenceDate)
    }

    private func build(samples: [WeeklyWorkoutSample], referenceDate: Date? = nil) -> WeeklyWorkoutProgress {
        let sortedSamples = samples.sorted { $0.date > $1.date }
        guard let latestDate = referenceDate ?? sortedSamples.first?.date else {
            return insufficientDataProgress(referenceDate: Date())
        }

        let weekStart = startOfSevenDayWindow(containing: latestDate)
        let previousWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let currentWeekSamples = sortedSamples.filter { sample in
            sample.date >= weekStart && sample.date <= latestDate
        }
        let previousWeekSamples = sortedSamples.filter { sample in
            sample.date >= previousWeekStart && sample.date < weekStart
        }

        guard !currentWeekSamples.isEmpty else {
            return insufficientDataProgress(referenceDate: weekStart)
        }

        let currentStats = weeklyStats(for: currentWeekSamples)
        let previousStats = weeklyStats(for: previousWeekSamples)
        let averageText = averagePaceOrSpeedText(for: currentWeekSamples, stats: currentStats)

        if currentWeekSamples.count >= max(previousWeekSamples.count + 1, 3) {
            return WeeklyWorkoutProgress(
                weekStartDate: weekStart,
                workoutCount: currentStats.count,
                totalDistanceKm: currentStats.distanceKm,
                totalDurationMinutes: currentStats.durationMinutes,
                averagePaceOrSpeedText: averageText,
                progressSummary: "이번 주는 운동 리듬이 더 꾸준했어요.",
                motivationText: "기록이 크게 튀지 않아도 자주 움직인 흐름 자체가 좋은 성장 신호예요.",
                trendType: .improving
            )
        }

        if previousStats.distanceKm > 0,
           currentStats.distanceKm >= previousStats.distanceKm * 1.08 {
            return WeeklyWorkoutProgress(
                weekStartDate: weekStart,
                workoutCount: currentStats.count,
                totalDistanceKm: currentStats.distanceKm,
                totalDurationMinutes: currentStats.durationMinutes,
                averagePaceOrSpeedText: averageText,
                progressSummary: "지난주보다 더 멀리 움직였어요.",
                motivationText: "거리 증가는 지구력 기반이 조금씩 쌓이고 있다는 신호예요.",
                trendType: .improving
            )
        }

        if previousStats.durationMinutes > 0,
           Double(currentStats.durationMinutes) >= Double(previousStats.durationMinutes) * 1.08 {
            return WeeklyWorkoutProgress(
                weekStartDate: weekStart,
                workoutCount: currentStats.count,
                totalDistanceKm: currentStats.distanceKm,
                totalDurationMinutes: currentStats.durationMinutes,
                averagePaceOrSpeedText: averageText,
                progressSummary: "움직인 시간이 늘었어요.",
                motivationText: "운동 시간이 늘어난 주에는 회복 리듬도 함께 챙기면 다음 주가 더 안정적이에요.",
                trendType: .improving
            )
        }

        if previousWeekSamples.isEmpty && currentStats.count < 2 {
            return WeeklyWorkoutProgress(
                weekStartDate: weekStart,
                workoutCount: currentStats.count,
                totalDistanceKm: currentStats.distanceKm,
                totalDurationMinutes: currentStats.durationMinutes,
                averagePaceOrSpeedText: averageText,
                progressSummary: "기록이 쌓이면 주간 흐름을 보여드릴게요.",
                motivationText: "이번 운동은 주간 성장 흐름을 만들기 위한 좋은 기준점이에요.",
                trendType: .insufficientData
            )
        }

        if !previousWeekSamples.isEmpty,
           currentStats.count < previousStats.count,
           currentStats.distanceKm < previousStats.distanceKm * 0.85 {
            return WeeklyWorkoutProgress(
                weekStartDate: weekStart,
                workoutCount: currentStats.count,
                totalDistanceKm: currentStats.distanceKm,
                totalDurationMinutes: currentStats.durationMinutes,
                averagePaceOrSpeedText: averageText,
                progressSummary: "이번 주는 조금 가볍게 움직였어요.",
                motivationText: "가벼운 주간도 다음 리듬을 준비하는 과정이 될 수 있어요.",
                trendType: .lighterWeek
            )
        }

        return WeeklyWorkoutProgress(
            weekStartDate: weekStart,
            workoutCount: currentStats.count,
            totalDistanceKm: currentStats.distanceKm,
            totalDurationMinutes: currentStats.durationMinutes,
            averagePaceOrSpeedText: averageText,
            progressSummary: "이번 주 운동 흐름이 안정적으로 이어지고 있어요.",
            motivationText: "큰 변화보다 꾸준히 이어진 기록이 다음 성장을 만드는 기반이에요.",
            trendType: .steady
        )
    }

    private func weeklyStats(for samples: [WeeklyWorkoutSample]) -> WeeklyStats {
        WeeklyStats(
            count: samples.count,
            distanceKm: samples.reduce(0) { $0 + $1.distanceKm },
            durationMinutes: samples.reduce(0) { $0 + $1.durationMinutes }
        )
    }

    private func averagePaceOrSpeedText(for samples: [WeeklyWorkoutSample], stats: WeeklyStats) -> String {
        guard stats.distanceKm > 0, stats.durationMinutes > 0 else { return "-" }

        let bikeCount = samples.filter { $0.workoutType == .cycling }.count
        let speedFocused = bikeCount > samples.count / 2

        if speedFocused {
            let hours = Double(stats.durationMinutes) / 60
            guard hours > 0 else { return "-" }
            return String(format: "평균 %.1f km/h", stats.distanceKm / hours)
        }

        let paceSeconds = Double(stats.durationMinutes * 60) / stats.distanceKm
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return "평균 \(minutes):\(String(format: "%02d", seconds))/km"
    }

    private func startOfSevenDayWindow(containing date: Date) -> Date {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay
    }

    private func insufficientDataProgress(referenceDate: Date) -> WeeklyWorkoutProgress {
        WeeklyWorkoutProgress(
            weekStartDate: Calendar.current.startOfDay(for: referenceDate),
            workoutCount: 0,
            totalDistanceKm: 0,
            totalDurationMinutes: 0,
            averagePaceOrSpeedText: "-",
            progressSummary: "기록이 쌓이면 주간 흐름을 보여드릴게요.",
            motivationText: "운동 기록이 생기면 이번 주 움직임과 성장 신호를 함께 정리해드릴게요.",
            trendType: .insufficientData
        )
    }
}

private struct WeeklyWorkoutSample {
    let date: Date
    let workoutType: UnifiedWorkoutType
    let distanceKm: Double
    let durationMinutes: Int
}

private struct WeeklyStats {
    let count: Int
    let distanceKm: Double
    let durationMinutes: Int
}
