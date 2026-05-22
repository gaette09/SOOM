import Foundation

protocol WorkoutRouteStore {
    func saveRoute(_ route: WorkoutRoute) async throws
    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute?
}

actor InMemoryWorkoutRouteStore: WorkoutRouteStore {
    private var routesByWorkoutId: [UUID: WorkoutRoute] = [:]

    func saveRoute(_ route: WorkoutRoute) async throws {
        routesByWorkoutId[route.workoutId] = route
    }

    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute? {
        routesByWorkoutId[workoutId]
    }
}
