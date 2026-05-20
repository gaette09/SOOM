import Foundation

struct HealthKitWorkoutImportResult: Equatable {
    let fetchedCount: Int
    let savedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let importedWorkouts: [UnifiedWorkout]
    let message: String

    static func success(importedWorkouts: [UnifiedWorkout], fetchedCount: Int) -> HealthKitWorkoutImportResult {
        HealthKitWorkoutImportResult(
            fetchedCount: fetchedCount,
            savedCount: importedWorkouts.count,
            skippedCount: max(fetchedCount - importedWorkouts.count, 0),
            failedCount: 0,
            importedWorkouts: importedWorkouts,
            message: importedWorkouts.isEmpty
                ? "가져올 HealthKit 운동 기록이 없어요."
                : "\(importedWorkouts.count)개의 HealthKit 운동 기록을 저장했어요."
        )
    }

    static func failure(fetchedCount: Int = 0, failedCount: Int = 1, message: String) -> HealthKitWorkoutImportResult {
        HealthKitWorkoutImportResult(
            fetchedCount: fetchedCount,
            savedCount: 0,
            skippedCount: 0,
            failedCount: failedCount,
            importedWorkouts: [],
            message: message
        )
    }
}
