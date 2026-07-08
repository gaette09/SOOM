import Foundation

protocol HealthKitWorkoutImporting {
    func importRecentWorkouts(limit: Int) async -> HealthKitWorkoutImportResult
}

final class HealthKitWorkoutImportPipeline: HealthKitWorkoutImporting {
    private let localDuplicateLookbackDays = 3_650
    private let startDateTolerance: TimeInterval = 5 * 60
    private let endDateTolerance: TimeInterval = 5 * 60
    private let durationToleranceRatio = 0.05
    private let distanceToleranceRatio = 0.10

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
        var importableWorkouts: [UnifiedWorkout]

        guard !unifiedWorkouts.isEmpty else {
            return .success(importedWorkouts: [], fetchedCount: workouts.count)
        }

        do {
            let existingWorkouts = try await store.fetchRecentWorkouts(days: localDuplicateLookbackDays)
            importableWorkouts = unifiedWorkouts.filter { !hasLocalDuplicate(for: $0, in: existingWorkouts) }

            guard !importableWorkouts.isEmpty else {
                return .success(importedWorkouts: [], fetchedCount: workouts.count)
            }

            try await store.saveWorkouts(importableWorkouts)
            let routeMissingReasons = await persistRoutesIfAvailable(for: importableWorkouts)
            if !routeMissingReasons.isEmpty {
                let routeStatusUpdatedAt = mappedAt()
                importableWorkouts = importableWorkouts.map { workout in
                    guard let reason = routeMissingReasons[workout.id] else {
                        return workout
                    }

                    return workout.withRouteMissingReason(reason, updatedAt: routeStatusUpdatedAt)
                }

                try? await store.saveWorkouts(importableWorkouts)
            }
            return .success(importedWorkouts: importableWorkouts, fetchedCount: workouts.count)
        } catch {
            return .failure(
                fetchedCount: workouts.count,
                failedCount: unifiedWorkouts.count,
                message: "HealthKit 운동 기록을 저장하지 못했어요. 잠시 후 다시 시도해 주세요."
            )
        }
    }


    private func hasLocalDuplicate(for importedWorkout: UnifiedWorkout, in existingWorkouts: [UnifiedWorkout]) -> Bool {
        guard importedWorkout.source == .appleHealthKit else { return false }

        return existingWorkouts.contains { existingWorkout in
            isConservativeLocalDuplicate(existingWorkout, importedWorkout: importedWorkout)
        }
    }

    private func isConservativeLocalDuplicate(
        _ existingWorkout: UnifiedWorkout,
        importedWorkout: UnifiedWorkout
    ) -> Bool {
        guard existingWorkout.source == .soomLocal else { return false }
        guard existingWorkout.workoutType == importedWorkout.workoutType else { return false }
        guard abs(existingWorkout.startDate.timeIntervalSince(importedWorkout.startDate)) <= startDateTolerance else {
            return false
        }
        guard abs(existingWorkout.endDate.timeIntervalSince(importedWorkout.endDate)) <= endDateTolerance else {
            return false
        }
        guard differenceRatio(existingWorkout.durationSeconds, importedWorkout.durationSeconds) <= durationToleranceRatio else {
            return false
        }
        guard
            let existingDistance = positive(existingWorkout.distanceMeters),
            let importedDistance = positive(importedWorkout.distanceMeters)
        else {
            return false
        }

        return differenceRatio(existingDistance, importedDistance) <= distanceToleranceRatio
    }

    private func differenceRatio(_ a: Double, _ b: Double) -> Double {
        let baseline = max(abs(a), abs(b))
        guard baseline > 0 else { return 1 }
        return abs(a - b) / baseline
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func persistRoutesIfAvailable(for workouts: [UnifiedWorkout]) async -> [UUID: WorkoutRouteMissingReason] {
        guard
            let routeLookupProvider,
            let routeFetcher,
            let routeStore
        else {
            return [:]
        }

        var routeMissingReasons: [UUID: WorkoutRouteMissingReason] = [:]

        for workout in workouts where workout.source == .appleHealthKit {
            guard
                let externalId = workout.externalId,
                let healthKitWorkout = await routeLookupProvider.lookupWorkout(externalId: externalId)
            else {
                routeMissingReasons[workout.id] = .externalSourceRouteNotShared
                continue
            }

            let route: WorkoutRoute?
            do {
                route = try await routeFetcher.fetchRoute(for: healthKitWorkout)
            } catch {
                routeMissingReasons[workout.id] = .routeFetchFailed
                continue
            }

            guard let route else {
                routeMissingReasons[workout.id] = .healthKitRouteUnavailable
                continue
            }

            do {
                try await routeStore.saveRoute(route.associated(with: workout))
            } catch {
                routeMissingReasons[workout.id] = .routePersistenceFailed
                continue
            }
        }

        return routeMissingReasons
    }
}

private extension WorkoutRoute {
    func associated(with workout: UnifiedWorkout) -> WorkoutRoute {
        WorkoutRoute(
            id: id,
            workoutId: workout.id,
            source: workout.source,
            coordinates: coordinates,
            totalDistanceMeters: totalDistanceMeters,
            totalElevationGain: totalElevationGain,
            bounds: bounds,
            createdAt: createdAt
        )
    }
}
