import Foundation

struct UnifiedWorkoutAnalysisInputSelector {
    private let recoveryMapper: UnifiedWorkoutToRecoveryActivityMapper
    private let processedRecoveryMapper: ProcessedWorkoutToRecoveryActivityMapper
    private let growthMapper: UnifiedWorkoutToGrowthInputMapper

    init(
        recoveryMapper: UnifiedWorkoutToRecoveryActivityMapper = UnifiedWorkoutToRecoveryActivityMapper(),
        processedRecoveryMapper: ProcessedWorkoutToRecoveryActivityMapper = ProcessedWorkoutToRecoveryActivityMapper(),
        growthMapper: UnifiedWorkoutToGrowthInputMapper = UnifiedWorkoutToGrowthInputMapper()
    ) {
        self.recoveryMapper = recoveryMapper
        self.processedRecoveryMapper = processedRecoveryMapper
        self.growthMapper = growthMapper
    }

    func selectIncludedWorkouts(_ workouts: [UnifiedWorkout]) -> [UnifiedWorkout] {
        workouts.filter { !$0.isExcludedFromAnalysis }
    }

    func selectRecoveryInputs(from workouts: [UnifiedWorkout]) -> [RecoveryActivity] {
        selectIncludedWorkouts(workouts).map(recoveryMapper.map)
    }

    func selectRecoveryInputs(fromProcessedWorkouts workouts: [ProcessedWorkout]) -> [RecoveryActivity] {
        workouts.filter { !$0.isExcludedFromAnalysis }.map(processedRecoveryMapper.map)
    }

    func selectGrowthInputs(from workouts: [UnifiedWorkout]) -> [WorkoutGrowthInput] {
        selectIncludedWorkouts(workouts).map(growthMapper.map)
    }
}
