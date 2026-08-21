import Foundation

/// "이번 운동 vs 최근 3주 평균" comparison for PDF's Relative Effort 3-tier bar
/// (feed-detail-migration-plan.md, Relative Effort batch). Distinct from
/// `RecoveryCalculator.calculateSummary` — that's the whole-app recovery score
/// (recent 3 days load + rest days, aggregated across everything); this is a
/// single-workout comparison against recent history.
struct RelativeEffortComparison: Equatable {
    enum Tier: Equatable {
        case higher
        case average
        case lower
    }

    let todayEffort: Int
    let recentAverageEffort: Int
    let tier: Tier

    /// 0...1 position for the marker dot, mapped from the today/average ratio
    /// clamped to [0.5, 1.5] — a ratio of 1.0 (exactly average) lands at 0.5.
    var markerPosition: Double {
        guard recentAverageEffort > 0 else { return 0.5 }
        let ratio = Double(todayEffort) / Double(recentAverageEffort)
        let clamped = min(max(ratio, 0.5), 1.5)
        return (clamped - 0.5) / 1.0
    }
}

enum RelativeEffortComparisonBuilder {
    /// Below this many recent activities, the comparison is hidden rather than
    /// shown against a misleadingly small sample — same "hide, don't mislead"
    /// convention as WorkoutRecoveryImpactCard/WorkoutZoneSection use elsewhere.
    static let minimumHistoryCount = 2
    private static let bandThreshold = 0.15

    static func build(todayEffort: Int, recentEfforts: [Int]) -> RelativeEffortComparison? {
        guard recentEfforts.count >= minimumHistoryCount else { return nil }

        let average = Double(recentEfforts.reduce(0, +)) / Double(recentEfforts.count)
        guard average > 0 else { return nil }

        let ratio = Double(todayEffort) / average
        let tier: RelativeEffortComparison.Tier
        if ratio >= 1 + bandThreshold {
            tier = .higher
        } else if ratio <= 1 - bandThreshold {
            tier = .lower
        } else {
            tier = .average
        }

        return RelativeEffortComparison(
            todayEffort: todayEffort,
            recentAverageEffort: Int(average.rounded()),
            tier: tier
        )
    }
}
