import Foundation

struct UnifiedWorkoutPersonalRecordProvider {
    private let store: UnifiedWorkoutStore
    private let selector: UnifiedWorkoutAnalysisInputSelector
    private let builder: PersonalRecordBuilder
    private let lookbackDays: Int

    init(
        store: UnifiedWorkoutStore,
        selector: UnifiedWorkoutAnalysisInputSelector = UnifiedWorkoutAnalysisInputSelector(),
        builder: PersonalRecordBuilder = PersonalRecordBuilder(),
        lookbackDays: Int = 35
    ) {
        self.store = store
        self.selector = selector
        self.builder = builder
        self.lookbackDays = lookbackDays
    }

    func fetchPersonalRecords(referenceDate: Date = Date()) async throws -> [PersonalRecord] {
        let workouts = try await store.fetchRecentWorkouts(days: lookbackDays)
        let growthInputs = selector.selectGrowthInputs(from: workouts)
        return builder.build(inputs: growthInputs, referenceDate: referenceDate)
    }
}
