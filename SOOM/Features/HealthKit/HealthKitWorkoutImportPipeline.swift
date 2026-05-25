import Foundation

protocol HealthKitWorkoutImporting {
    func importRecentWorkouts(limit: Int) async -> HealthKitWorkoutImportResult
}

final class HealthKitWorkoutImportPipeline: HealthKitWorkoutImporting {
    private let workoutFetcher: any HealthKitWorkoutFetching
    private let mapper: HealthKitWorkoutToUnifiedWorkoutMapper
    private let store: any UnifiedWorkoutStore
    private let routeLookupProvider: (any HealthKitWorkoutLookingUp)?
    private let routeFetcher: (any HealthKitWorkoutRouteFetching)?
    private let routeStore: (any WorkoutRoutePersistenceStoring)?
    private let mappedAt: () -> Date

    init(
        workoutFetcher: any HealthKitWorkoutFetching = HealthKitWorkoutFetcher(),
        mapper: HealthKitWorkoutToUnifiedWorkoutMapper = HealthKitWorkoutToUnifiedWorkoutMapper(),
        store: any UnifiedWorkoutStore,
        routeLookupProvider: (any HealthKitWorkoutLookingUp)? = nil,
        routeFetcher: (any HealthKitWorkoutRouteFetching)? = nil,
        routeStore: (any WorkoutRoutePersistenceStoring)? = nil,
        mappedAt: @escaping () -> Date = Date.init
    ) {
        self.workoutFetcher = workoutFetcher
        self.mapper = mapper
        self.store = store
        self.routeLookupProvider = routeLookupProvider
        self.routeFetcher = routeFetcher
        self.routeStore = routeStore
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
            await persistRoutesIfAvailable(for: unifiedWorkouts)
            return .success(importedWorkouts: unifiedWorkouts, fetchedCount: workouts.count)
        } catch {
            return .failure(
                fetchedCount: workouts.count,
                failedCount: unifiedWorkouts.count,
                message: "HealthKit 운동 기록을 저장하지 못했어요. 잠시 후 다시 시도해 주세요."
            )
        }
    }


    private func persistRoutesIfAvailable(for workouts: [UnifiedWorkout]) async {
        guard
            let routeLookupProvider,
            let routeFetcher,
            let routeStore
        else {
            return
        }

        for workout in workouts where workout.source == .appleHealthKit {
            guard
                let externalId = workout.externalId,
                let healthKitWorkout = await routeLookupProvider.lookupWorkout(externalId: externalId)
            else {
                continue
            }

            do {
                guard let route = try await routeFetcher.fetchRoute(for: healthKitWorkout) else {
                    continue
                }

                try await routeStore.saveRoute(route)
            } catch {
                continue
            }
        }
    }
}
