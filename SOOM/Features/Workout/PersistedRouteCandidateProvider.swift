import Foundation

struct PersistedRouteCandidateSet: Equatable {
    let currentRoute: WorkoutRoute?
    let candidateRoutesByWorkoutId: [UUID: WorkoutRoute]
    let currentCourseIdentity: CourseIdentity?

    var candidateRoutes: [WorkoutRoute] {
        Array(candidateRoutesByWorkoutId.values)
    }
}

protocol PersistedRouteCandidateProviding {
    func routes(
        currentWorkoutId: UUID,
        candidateWorkoutIds: [UUID]
    ) async throws -> PersistedRouteCandidateSet
}

struct PersistedRouteCandidateProvider: PersistedRouteCandidateProviding {
    private let store: any WorkoutRoutePersistenceStoring
    private let courseIdentityBuilder: CourseIdentityBuilder

    init(
        store: any WorkoutRoutePersistenceStoring,
        courseIdentityBuilder: CourseIdentityBuilder = CourseIdentityBuilder()
    ) {
        self.store = store
        self.courseIdentityBuilder = courseIdentityBuilder
    }

    func routes(
        currentWorkoutId: UUID,
        candidateWorkoutIds: [UUID]
    ) async throws -> PersistedRouteCandidateSet {
        let currentRoute = try await store.fetchRoute(workoutId: currentWorkoutId)
        let candidateRoutes = try await store.fetchRoutes(workoutIds: candidateWorkoutIds)
        let candidateRoutesByWorkoutId = Dictionary(
            uniqueKeysWithValues: candidateRoutes.map { ($0.workoutId, $0) }
        )

        return PersistedRouteCandidateSet(
            currentRoute: currentRoute,
            candidateRoutesByWorkoutId: candidateRoutesByWorkoutId,
            currentCourseIdentity: currentRoute.flatMap { courseIdentityBuilder.build(from: $0) }
        )
    }
}
