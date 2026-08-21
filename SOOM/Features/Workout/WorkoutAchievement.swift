import Foundation

struct WorkoutAchievement: Identifiable, Equatable {
    let id = UUID()
    let durationMinutes: Int
    /// 1-based — 1 means fastest of the comparison pool (today included).
    let rank: Int
    let coordinate: WorkoutRouteCoordinate
    let valueText: String
    let isPaceBased: Bool

    var pinLabel: String {
        let rankText = rank == 1 ? "최고" : "\(rank)위"
        let metricLabel = isPaceBased ? "페이스" : "속도"
        return "\(durationMinutes)분 구간 \(rankText) \(metricLabel)"
    }

    var bannerComparisonText: String {
        if rank == 1 {
            return "최근 \(WorkoutAchievementConfig.lookbackMonths)개월 중 가장 빠른 \(durationMinutes)분 구간이에요."
        }
        return "최근 \(WorkoutAchievementConfig.lookbackMonths)개월 중 \(durationMinutes)분 구간에서 \(rank)번째로 빠른 기록이에요."
    }

    var bannerMotivationText: String {
        rank == 1 ? "꾸준히 쌓아온 리듬이 만든 결과예요." : "좋은 흐름이 이어지고 있다는 신호예요."
    }
}

enum WorkoutAchievementBuilder {
    /// `historicalEffortsByDuration`: durationMinutes -> best-effort speeds (m/s)
    /// from other same-sport workouts in the comparison window. Ranking excludes
    /// today's own effort from that list (it's added in separately) to avoid any
    /// self-comparison ambiguity.
    static func build(
        todayEfforts: [WorkoutBestEffort],
        historicalEffortsByDuration: [Int: [Double]],
        workoutType: UnifiedWorkoutType
    ) -> [WorkoutAchievement] {
        let candidates: [WorkoutAchievement] = todayEfforts.compactMap { effort in
            let historical = historicalEffortsByDuration[effort.durationMinutes] ?? []
            guard historical.count >= WorkoutAchievementConfig.minimumHistoryCount else { return nil }

            let rank = historical.filter { $0 > effort.averageMetersPerSecond }.count + 1
            guard rank <= WorkoutAchievementConfig.topRankThreshold else { return nil }

            return WorkoutAchievement(
                durationMinutes: effort.durationMinutes,
                rank: rank,
                coordinate: effort.routeCoordinate,
                valueText: formattedValue(effort.averageMetersPerSecond, workoutType: workoutType),
                isPaceBased: usesPace(workoutType)
            )
        }

        return Array(
            candidates
                .sorted { $0.rank < $1.rank }
                .prefix(WorkoutAchievementConfig.maximumMarkers)
        )
    }

    /// Matches `ActivityDetailSummaryMetrics.movementMetricLabel`'s existing
    /// pace-vs-speed grouping (running/hiking = pace, everything else = speed) —
    /// not `PersonalRecordBuilder.usesPace`'s slightly different grouping, since
    /// that one governs this exact detail screen's other fields.
    private static func usesPace(_ workoutType: UnifiedWorkoutType) -> Bool {
        switch workoutType {
        case .running, .hiking:
            return true
        default:
            return false
        }
    }

    private static func formattedValue(_ metersPerSecond: Double, workoutType: UnifiedWorkoutType) -> String {
        guard metersPerSecond > 0 else { return "—" }

        if usesPace(workoutType) {
            let secondsPerKm = 1_000 / metersPerSecond
            let rounded = Int(secondsPerKm.rounded())
            return "\(rounded / 60):\(String(format: "%02d", rounded % 60))/km"
        }
        return String(format: "%.1f km/h", metersPerSecond * 3.6)
    }
}
