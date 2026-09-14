import Foundation

/// Supplies real stored history for `WorkoutDeepDetailView.comparisonWorkouts`
/// (growthMetrics/growthSummary/weaknessInsight). Sport selection and
/// "before this workout" date filtering are deliberately left to the growth
/// builders themselves — they already do it — so this only removes the
/// current workout and analysis-excluded records.
protocol WorkoutComparisonHistoryProviding {
    func comparisonWorkouts(excluding workoutId: UUID) async -> [Workout]
}

struct SwiftDataWorkoutComparisonHistoryProvider: WorkoutComparisonHistoryProviding {
    private let store: any UnifiedWorkoutStore
    /// Fetched relative to "now", not the viewed workout's date, and the builders
    /// apply no window of their own — so this must cover everything Activity's
    /// "최근 운동" list can surface (`loadSavedWorkouts` fetches 180 days).
    private let lookbackDays: Int

    init(store: any UnifiedWorkoutStore, lookbackDays: Int = 180) {
        self.store = store
        self.lookbackDays = lookbackDays
    }

    func comparisonWorkouts(excluding workoutId: UUID) async -> [Workout] {
        let workouts: [UnifiedWorkout]
        do {
            workouts = try await store.fetchRecentWorkouts(days: lookbackDays)
        } catch {
            // Falls back to [] silently for the user (same as "no history yet"), but
            // logs so a real fetch failure is distinguishable from genuinely empty history.
            print("[WorkoutComparisonHistoryProvider] fetchRecentWorkouts failed: \(error)")
            return []
        }

        return workouts
            .filter { $0.id != workoutId }
            .filter { !$0.isExcludedFromAnalysis }
            .map { Workout(unifiedWorkout: $0) }
    }
}
