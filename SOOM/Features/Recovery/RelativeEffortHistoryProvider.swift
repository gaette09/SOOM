import Foundation

/// Deliberately independent of `comparisonWorkouts`/`SimilarWorkoutCandidateProviding` —
/// those are inconsistently wired across navigation paths (RootTabView's "최근 운동"
/// list never sets either one, so growth-comparison sections are silently empty there;
/// see SOOM_KNOWN_ISSUES.md). This provider is injected explicitly at every real call
/// site instead, same DI convention as `WorkoutDetailRouteContextProviding`.
protocol RelativeEffortHistoryProviding {
    func recentRelativeEfforts(excluding workoutId: UUID, before date: Date, lookbackDays: Int) async -> [Int]
}

struct SwiftDataRelativeEffortHistoryProvider: RelativeEffortHistoryProviding {
    private let store: any UnifiedWorkoutStore
    private let mapper = UnifiedWorkoutToRecoveryActivityMapper()
    /// Wide enough to cover the 21-day comparison window even when it's fetched
    /// relative to "now" rather than the viewed workout's own date.
    private let fetchWindowDays = 90

    init(store: any UnifiedWorkoutStore) {
        self.store = store
    }

    func recentRelativeEfforts(excluding workoutId: UUID, before date: Date, lookbackDays: Int) async -> [Int] {
        guard let workouts = try? await store.fetchRecentWorkouts(days: fetchWindowDays) else { return [] }
        let windowStart = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: date) ?? date

        return workouts
            .filter { $0.id != workoutId }
            .filter { !$0.isExcludedFromAnalysis }
            .filter { $0.startDate >= windowStart && $0.startDate < date }
            .map { mapper.map($0).relativeEffort }
    }
}
