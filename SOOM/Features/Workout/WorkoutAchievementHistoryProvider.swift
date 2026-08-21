import Foundation

/// Deliberately independent of `comparisonWorkouts`/`SimilarWorkoutCandidateProviding` —
/// same reasoning as `RelativeEffortHistoryProviding` (see that file's doc comment
/// and SOOM_KNOWN_ISSUES.md's "Growth-Comparison Sections Silently Empty..." entry).
/// Injected explicitly at every real call site instead of relying on that path.
protocol WorkoutAchievementHistoryProviding {
    /// Returns best-effort speeds (m/s), keyed by duration in minutes, pooled
    /// across other same-sport workouts in the comparison window.
    func recentBestEfforts(
        excluding workoutId: UUID,
        workoutType: UnifiedWorkoutType,
        before date: Date,
        lookbackMonths: Int
    ) async -> [Int: [Double]]
}

struct SwiftDataWorkoutAchievementHistoryProvider: WorkoutAchievementHistoryProviding {
    private let workoutStore: any UnifiedWorkoutStore
    private let routeStore: any WorkoutRoutePersistenceStoring

    init(workoutStore: any UnifiedWorkoutStore, routeStore: any WorkoutRoutePersistenceStoring) {
        self.workoutStore = workoutStore
        self.routeStore = routeStore
    }

    func recentBestEfforts(
        excluding workoutId: UUID,
        workoutType: UnifiedWorkoutType,
        before date: Date,
        lookbackMonths: Int
    ) async -> [Int: [Double]] {
        let windowStart = Calendar.current.date(byAdding: .month, value: -lookbackMonths, to: date) ?? date
        // Fetched relative to "now", same caveat as RelativeEffortHistoryProvider —
        // wide enough to cover the window even when viewing an older workout.
        let fetchDays = max(lookbackMonths * 31 + 31, 1)

        guard let workouts = try? await workoutStore.fetchRecentWorkouts(days: fetchDays) else { return [:] }

        let candidateIds = workouts
            .filter { $0.id != workoutId }
            .filter { $0.workoutType == workoutType }
            .filter { !$0.isExcludedFromAnalysis }
            .filter { $0.startDate >= windowStart && $0.startDate < date }
            .map(\.id)

        guard !candidateIds.isEmpty, let routes = try? await routeStore.fetchRoutes(workoutIds: candidateIds) else {
            return [:]
        }

        var results: [Int: [Double]] = [:]
        for route in routes {
            for effort in WorkoutSegmentBestEffortFinder.bestEfforts(from: route) {
                results[effort.durationMinutes, default: []].append(effort.averageMetersPerSecond)
            }
        }
        return results
    }
}
