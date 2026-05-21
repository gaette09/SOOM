import Foundation

struct UnifiedWorkoutRecoveryPreviewResult {
    let summary: RecoverySummary
    let usedWorkoutCount: Int
}

struct UnifiedWorkoutRecoveryPreviewProvider {
    private let store: any UnifiedWorkoutStore
    private let selector: UnifiedWorkoutAnalysisInputSelector
    private let calculator: RecoveryCalculator
    private let lookbackDays: Int

    init(
        store: any UnifiedWorkoutStore,
        selector: UnifiedWorkoutAnalysisInputSelector = UnifiedWorkoutAnalysisInputSelector(),
        calculator: RecoveryCalculator = RecoveryCalculator(),
        lookbackDays: Int = 30
    ) {
        self.store = store
        self.selector = selector
        self.calculator = calculator
        self.lookbackDays = lookbackDays
    }

    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult {
        let workouts = try await store.fetchRecentWorkouts(days: lookbackDays)
        let recoveryInputs = selector.selectRecoveryInputs(from: workouts)
        let summary = calculator.calculateSummary(from: recoveryInputs)

        return UnifiedWorkoutRecoveryPreviewResult(
            summary: summary,
            usedWorkoutCount: recoveryInputs.count
        )
    }
}
