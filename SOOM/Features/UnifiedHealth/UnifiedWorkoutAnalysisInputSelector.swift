import Foundation

struct UnifiedWorkoutAnalysisInputSelector {
    private let recoveryMapper: UnifiedWorkoutToRecoveryActivityMapper
    private let growthMapper: UnifiedWorkoutToGrowthInputMapper

    init(
        recoveryMapper: UnifiedWorkoutToRecoveryActivityMapper = UnifiedWorkoutToRecoveryActivityMapper(),
        growthMapper: UnifiedWorkoutToGrowthInputMapper = UnifiedWorkoutToGrowthInputMapper()
    ) {
        self.recoveryMapper = recoveryMapper
        self.growthMapper = growthMapper
    }

    func selectIncludedWorkouts(_ workouts: [UnifiedWorkout]) -> [UnifiedWorkout] {
        workouts.filter { !$0.isExcludedFromAnalysis }
    }

    func selectRecoveryInputs(from workouts: [UnifiedWorkout]) -> [RecoveryActivity] {
        selectIncludedWorkouts(workouts).map(recoveryMapper.map)
    }

    func selectGrowthInputs(from workouts: [UnifiedWorkout]) -> [WorkoutGrowthInput] {
        selectIncludedWorkouts(workouts).map(growthMapper.map)
    }
}
