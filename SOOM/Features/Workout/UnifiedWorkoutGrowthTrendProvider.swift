import Foundation

struct UnifiedWorkoutGrowthTrendProvider {
    private let store: UnifiedWorkoutStore
    private let selector: UnifiedWorkoutAnalysisInputSelector
    private let builder: FourWeekWorkoutTrendBuilder
    private let lookbackDays: Int

    init(
        store: UnifiedWorkoutStore,
        selector: UnifiedWorkoutAnalysisInputSelector = UnifiedWorkoutAnalysisInputSelector(),
        builder: FourWeekWorkoutTrendBuilder = FourWeekWorkoutTrendBuilder(),
        lookbackDays: Int = 35
    ) {
        self.store = store
        self.selector = selector
        self.builder = builder
        self.lookbackDays = lookbackDays
    }

    func fetchFourWeekTrend(referenceDate: Date = Date()) async throws -> FourWeekWorkoutTrend {
        let workouts = try await store.fetchRecentWorkouts(days: lookbackDays)
        let growthInputs = selector.selectGrowthInputs(from: workouts)
        return builder.build(inputs: growthInputs, referenceDate: referenceDate)
    }
}
