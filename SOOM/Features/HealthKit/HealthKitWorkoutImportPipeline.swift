import Foundation

protocol HealthKitWorkoutImporting {
    func importRecentWorkouts(limit: Int) async -> HealthKitWorkoutImportResult
}

final class HealthKitWorkoutImportPipeline: HealthKitWorkoutImporting {
    private let workoutFetcher: any HealthKitWorkoutFetching
    private let mapper: HealthKitWorkoutToUnifiedWorkoutMapper
    private let store: any UnifiedWorkoutStore
    private let mappedAt: () -> Date

    init(
        workoutFetcher: any HealthKitWorkoutFetching = HealthKitWorkoutFetcher(),
        mapper: HealthKitWorkoutToUnifiedWorkoutMapper = HealthKitWorkoutToUnifiedWorkoutMapper(),
        store: any UnifiedWorkoutStore,
        mappedAt: @escaping () -> Date = Date.init
    ) {
        self.workoutFetcher = workoutFetcher
        self.mapper = mapper
        self.store = store
        self.mappedAt = mappedAt
    }

    func importRecentWorkouts(limit: Int = 20) async -> HealthKitWorkoutImportResult {
        let workouts: [HealthKitWorkout]

        do {
            workouts = try await workoutFetcher.fetchRecentWorkouts(limit: max(limit, 1))
        } catch {
            return .failure(
                message: "HealthKit 운동 기록을 가져오지 못했어요. 잠시 후 다시 시도해 주세요."
            )
        }

        let importDate = mappedAt()
        let unifiedWorkouts = workouts.map { mapper.map($0, mappedAt: importDate) }

        guard !unifiedWorkouts.isEmpty else {
            return .success(importedWorkouts: [], fetchedCount: workouts.count)
        }

        do {
            try await store.saveWorkouts(unifiedWorkouts)
            return .success(importedWorkouts: unifiedWorkouts, fetchedCount: workouts.count)
        } catch {
            return .failure(
                fetchedCount: workouts.count,
                failedCount: unifiedWorkouts.count,
                message: "HealthKit 운동 기록을 저장하지 못했어요. 잠시 후 다시 시도해 주세요."
            )
        }
    }
}
