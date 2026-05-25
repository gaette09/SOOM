import Foundation

protocol WorkoutDetailRouteContextProviding {
    func route(for workoutId: UUID) async -> WorkoutRoute?
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
}
