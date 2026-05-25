import Foundation

struct UnifiedWorkoutProgressionIntelligenceProvider {
    private let store: UnifiedWorkoutStore
    private let selector: UnifiedWorkoutAnalysisInputSelector
    private let builder: ProgressionIntelligenceBuilder
    private let period: ProgressionPeriod
    private let lookbackDays: Int

    init(
        store: UnifiedWorkoutStore,
        selector: UnifiedWorkoutAnalysisInputSelector = UnifiedWorkoutAnalysisInputSelector(),
        builder: ProgressionIntelligenceBuilder = ProgressionIntelligenceBuilder(),
        period: ProgressionPeriod = .rollingFourWeeks,
        lookbackDays: Int? = nil
    ) {
        self.store = store
        self.selector = selector
        self.builder = builder
        self.period = period
        self.lookbackDays = lookbackDays ?? period.dayCount + 7
    }

    func fetchProgressionIntelligence(referenceDate: Date = Date()) async throws -> ProgressionIntelligence {
        let workouts = try await store.fetchRecentWorkouts(days: lookbackDays)
        let growthInputs = selector.selectGrowthInputs(from: workouts)
        return builder.build(inputs: growthInputs, period: period, referenceDate: referenceDate)
    }
}
