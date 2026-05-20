import Foundation

struct FourWeekWorkoutTrendBuilder {
    func build(workouts: [Workout], referenceDate: Date = Date()) -> FourWeekWorkoutTrend {
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

    func build(inputs: [WorkoutGrowthInput], referenceDate: Date = Date()) -> FourWeekWorkoutTrend {
        let weeks = fourWeekWindows(endingAt: referenceDate).map { window in
            let weekInputs = inputs.filter { input in
                input.startDate >= window.start && input.startDate < window.end
            }

            return WeeklyWorkoutTrendPoint(
                weekStartDate: window.start,
                workoutCount: weekInputs.count,
                totalDistanceKm: weekInputs.reduce(0) { $0 + ($1.distanceKm ?? 0) },
                totalDurationMinutes: weekInputs.reduce(0) { $0 + $1.durationMinutes }
            )
        }

        let nonEmptyWeeks = weeks.filter { $0.workoutCount > 0 }
        guard nonEmptyWeeks.count >= 2 else {
            return FourWeekWorkoutTrend(
                weeks: weeks,
                trendType: .insufficientData,
                summaryText: "기록이 쌓이면 4주 성장 흐름을 보여드릴게요.",
                motivationText: "이번 운동은 장기 흐름을 만들기 위한 좋은 기준점이에요."
            )
        }

        let latestWeek = weeks.last ?? nonEmptyWeeks.last!
        let previousWeeks = weeks.dropLast().filter { $0.workoutCount > 0 }
        let latestScore = activityScore(for: latestWeek)
        let previousAverage = previousWeeks.map(activityScore).average

        if previousAverage > 0, latestScore < previousAverage * 0.82 {
            return FourWeekWorkoutTrend(
                weeks: weeks,
                trendType: .lighter,
                summaryText: "최근 주는 이전 흐름보다 조금 가볍게 움직였어요.",
                motivationText: "가벼운 주간도 다음 리듬을 준비하는 과정이 될 수 있어요."
            )
        }

        if isGraduallyImproving(nonEmptyWeeks) || (previousAverage > 0 && latestScore >= previousAverage * 1.12) {
            return FourWeekWorkoutTrend(
                weeks: weeks,
                trendType: .improving,
                summaryText: "최근 4주 동안 움직임이 조금씩 커지고 있어요.",
                motivationText: "거리와 시간이 천천히 쌓이는 흐름은 좋은 성장 신호예요."
            )
        }

        return FourWeekWorkoutTrend(
            weeks: weeks,
            trendType: .steady,
            summaryText: "최근 4주 운동 리듬이 안정적으로 이어지고 있어요.",
            motivationText: "큰 변화가 없어도 꾸준히 이어진 기록은 다음 성장을 만드는 기반이에요."
        )
    }

    private func fourWeekWindows(endingAt referenceDate: Date) -> [WeekWindow] {
        let calendar = Calendar.current
        let latestStart = startOfSevenDayWindow(containing: referenceDate)

        return (0..<4).reversed().map { offset in
            let start = calendar.date(byAdding: .day, value: -(offset * 7), to: latestStart) ?? latestStart
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? referenceDate
            return WeekWindow(start: start, end: end)
        }
    }

    private func startOfSevenDayWindow(containing date: Date) -> Date {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay
    }

    private func activityScore(for point: WeeklyWorkoutTrendPoint) -> Double {
        point.totalDistanceKm + (Double(point.totalDurationMinutes) / 60 * 5) + (Double(point.workoutCount) * 3)
    }

    private func isGraduallyImproving(_ weeks: [WeeklyWorkoutTrendPoint]) -> Bool {
        guard weeks.count >= 3 else { return false }

        let scores = weeks.map(activityScore)
        guard let first = scores.first, let last = scores.last, first > 0 else { return false }
        let hasMostlyIncreasingSteps = zip(scores, scores.dropFirst()).filter { previous, next in
            next >= previous * 0.95
        }.count >= scores.count - 1

        return hasMostlyIncreasingSteps && last >= first * 1.15
    }
}

private struct WeekWindow {
    let start: Date
    let end: Date
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
