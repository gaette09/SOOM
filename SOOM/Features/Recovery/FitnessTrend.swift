import Foundation

/// PDF's Fitness Increased card (feed-detail-migration-plan.md batch 9): a Strava-CTL-style
/// chronic training load trend, distinct from `RelativeEffortComparison` (single-workout vs
/// recent-average) and `RecoveryCalculator.calculateSummary` (3-day recovery score). This is a
/// 42-day exponentially-weighted rolling average over `RecoveryActivity.trainingLoad`, i.e. the
/// same MVP load estimate `RecoveryCalculator` already uses, just accumulated over a much longer
/// window instead of averaged over the last few days.
struct FitnessTrend: Equatable {
    /// Rounded chronic training load on the viewed date ("Fitness Score 35").
    let score: Int
    /// Change in `score` versus the previous calendar day ("Points +3").
    let pointsDelta: Int
    /// Recent chronic-load values, oldest-first, for the unlabeled mini sparkline.
    let sparkline: [Double]
}

enum FitnessTrendCalculator {
    /// Matches the industry-standard Chronic Training Load window (Strava/TrainingPeaks CTL).
    static let chronicWindowDays = 42
    /// How far back callers should fetch daily loads from: ~3x `chronicWindowDays` so the
    /// recursive average is reasonably converged (>95%) by the target date rather than still
    /// visibly ramping up from the cold-start zero seed.
    static let recommendedHistoryWindowDays = chronicWindowDays * 3

    /// `dailyLoads` must be one entry per calendar day, ascending, with 0 for rest days —
    /// the caller (`FitnessTrendHistoryProviding`) is responsible for bucketing. Cold-starts
    /// the recursive average at 0, same "MVP estimate" spirit as `estimateTrainingLoad`'s
    /// own TODO — it ramps up over the first `chronicWindowDays` rather than assuming
    /// pre-app-history fitness.
    static func chronicLoadSeries(dailyLoads: [Double]) -> [Double] {
        var series: [Double] = []
        series.reserveCapacity(dailyLoads.count)

        var previous = 0.0
        for load in dailyLoads {
            let next = previous + (load - previous) / Double(chronicWindowDays)
            series.append(next)
            previous = next
        }
        return series
    }
}

enum FitnessTrendBuilder {
    /// Same "hide, don't mislead" convention as `RelativeEffortComparisonBuilder` — below this
    /// many training days, the trend is more noise than signal.
    static let minimumTrainingDayCount = 2
    static let sparklineDayCount = 14

    /// `dailyLoadsAscending` covers every calendar day up to and including the viewed date.
    static func build(dailyLoadsAscending: [Double]) -> FitnessTrend? {
        guard dailyLoadsAscending.count >= 2 else { return nil }
        guard dailyLoadsAscending.filter({ $0 > 0 }).count >= minimumTrainingDayCount else { return nil }

        let series = FitnessTrendCalculator.chronicLoadSeries(dailyLoads: dailyLoadsAscending)
        guard let today = series.last else { return nil }
        let yesterday = series[series.count - 2]

        return FitnessTrend(
            score: Int(today.rounded()),
            pointsDelta: Int(today.rounded()) - Int(yesterday.rounded()),
            sparkline: Array(series.suffix(sparklineDayCount))
        )
    }
}
