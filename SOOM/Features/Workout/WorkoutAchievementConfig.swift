import Foundation

/// Single place to tune the map-achievement-marker batch (feed-detail-migration-plan.md
/// batch 7) — adjust here, nothing else needs to change.
enum WorkoutAchievementConfig {
    /// PDF's markers say "Lifetime" — SOOM compares against a rolling window instead
    /// (no lifetime-ranking store exists, and recomputing over truly all history on
    /// every detail-screen view isn't worth building until proven necessary).
    static let lookbackMonths = 3
    /// Below this many same-sport comparison workouts, ranking would be against a
    /// misleadingly small sample — hide markers entirely rather than show a
    /// technically-true-but-meaningless "1st place out of 1" badge.
    static let minimumHistoryCount = 2
    /// Only top-3 finishes count as an "achievement" worth marking.
    static let topRankThreshold = 3
    /// At most this many markers shown per workout, even if more duration windows
    /// qualify — matches the PDF reference example's marker count.
    static let maximumMarkers = 2
}
