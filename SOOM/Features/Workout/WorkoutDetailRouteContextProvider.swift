import Foundation

protocol WorkoutDetailRouteContextProviding {
    func route(for workoutId: UUID) async -> WorkoutRoute?
    func route(for workout: UnifiedWorkout) async -> WorkoutRoute?
}

struct WorkoutDetailRouteContextProvider: WorkoutDetailRouteContextProviding {
    private let store: any WorkoutRoutePersistenceStoring

    init(store: any WorkoutRoutePersistenceStoring) {
        self.store = store
    }

    func route(for workoutId: UUID) async -> WorkoutRoute? {
        do {
            return try await store.fetchRoute(workoutId: workoutId)
        } catch {
            return nil
        }
    }

    func route(for workout: UnifiedWorkout) async -> WorkoutRoute? {
        if let route = await route(for: workout.id) {
            return route
        }

        guard
            workout.source == .appleHealthKit,
            let externalId = workout.externalId,
            let externalUUID = UUID(uuidString: externalId),
            externalUUID != workout.id
        else {
            return nil
        }

        return await route(for: externalUUID)
    }
}
