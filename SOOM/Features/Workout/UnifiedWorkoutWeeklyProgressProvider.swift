import Foundation

struct UnifiedWorkoutWeeklyProgressProvider {
    private let store: UnifiedWorkoutStore
    private let selector: UnifiedWorkoutAnalysisInputSelector
    private let builder: WeeklyWorkoutProgressBuilder
    private let lookbackDays: Int

    init(
        store: UnifiedWorkoutStore,
        selector: UnifiedWorkoutAnalysisInputSelector = UnifiedWorkoutAnalysisInputSelector(),
        builder: WeeklyWorkoutProgressBuilder = WeeklyWorkoutProgressBuilder(),
        lookbackDays: Int = 30
    ) {
        self.store = store
        self.selector = selector
        self.builder = builder
        self.lookbackDays = lookbackDays
    }

    func fetchWeeklyProgress(referenceDate: Date = Date()) async throws -> WeeklyWorkoutProgress {
        let workouts = try await store.fetchRecentWorkouts(days: lookbackDays)
        let growthInputs = selector.selectGrowthInputs(from: workouts)
        return builder.build(inputs: growthInputs, referenceDate: referenceDate)
    }
}
