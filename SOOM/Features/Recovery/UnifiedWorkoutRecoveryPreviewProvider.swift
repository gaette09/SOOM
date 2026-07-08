import Foundation

struct UnifiedWorkoutRecoveryPreviewResult {
    let summary: RecoverySummary
    let usedWorkoutCount: Int
}

struct UnifiedWorkoutRecoveryPreviewProvider {
    private let store: any UnifiedWorkoutStore
    private let selector: UnifiedWorkoutAnalysisInputSelector
    private let processedWorkoutBuilder: ProcessedWorkoutBuilder
    private let calculator: RecoveryCalculator
    private let lookbackDays: Int

    init(
        store: any UnifiedWorkoutStore,
        selector: UnifiedWorkoutAnalysisInputSelector = UnifiedWorkoutAnalysisInputSelector(),
        processedWorkoutBuilder: ProcessedWorkoutBuilder = ProcessedWorkoutBuilder(),
        calculator: RecoveryCalculator = RecoveryCalculator(),
        lookbackDays: Int = 30
    ) {
        self.store = store
        self.selector = selector
        self.processedWorkoutBuilder = processedWorkoutBuilder
        self.calculator = calculator
        self.lookbackDays = lookbackDays
    }

    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult {
        let workouts = try await store.fetchRecentWorkouts(days: lookbackDays)
        let processedWorkouts = workouts.map { processedWorkoutBuilder.make(from: $0) }
        let recoveryInputs = selector.selectRecoveryInputs(fromProcessedWorkouts: processedWorkouts)
        let summary = calculator.calculateSummary(from: recoveryInputs)

        return UnifiedWorkoutRecoveryPreviewResult(
            summary: summary,
            usedWorkoutCount: recoveryInputs.count
        )
    }
}
