import Foundation

/// Same independent-DI convention as `RelativeEffortHistoryProviding`/
/// `WorkoutAchievementHistoryProviding` — injected explicitly at each real call site rather than
/// riding on `comparisonWorkouts`/`SimilarWorkoutCandidateProviding` (inconsistently wired across
/// navigation paths, see SOOM_KNOWN_ISSUES.md).
protocol FitnessTrendHistoryProviding {
    /// One entry per calendar day from `date - (windowDays - 1)` through `date` inclusive,
    /// ascending, summing same-day `trainingLoad` and using 0 for rest days.
    func dailyTrainingLoads(upTo date: Date, windowDays: Int) async -> [Double]
}

struct SwiftDataFitnessTrendHistoryProvider: FitnessTrendHistoryProviding {
    private let store: any UnifiedWorkoutStore
    private let mapper = UnifiedWorkoutToRecoveryActivityMapper()

    init(store: any UnifiedWorkoutStore) {
        self.store = store
    }

    func dailyTrainingLoads(upTo date: Date, windowDays: Int) async -> [Double] {
        guard windowDays > 0 else { return [] }
        guard let workouts = try? await store.fetchRecentWorkouts(days: windowDays) else { return [] }

        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: targetDay) else {
            return []
        }

        var loadByDay: [Date: Double] = [:]
        for workout in workouts where !workout.isExcludedFromAnalysis {
            let day = calendar.startOfDay(for: workout.startDate)
            guard day >= windowStart, day <= targetDay else { continue }
            loadByDay[day, default: 0] += mapper.map(workout).trainingLoad
        }

        var dailyLoads: [Double] = []
        var cursor = windowStart
        while cursor <= targetDay {
            dailyLoads.append(loadByDay[cursor] ?? 0)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? targetDay.addingTimeInterval(1)
        }
        return dailyLoads
    }
}
