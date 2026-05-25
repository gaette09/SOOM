import Foundation

struct SimilarWorkoutCandidateResult: Equatable {
    let baseline: WorkoutGrowthInput
    let routeCandidate: RouteComparisonCandidate?
    let currentCourseIdentity: CourseIdentity?
    let candidateWorkouts: [WorkoutGrowthInput]
    let routeCandidates: [RouteComparisonCandidate]

    init(
        baseline: WorkoutGrowthInput,
        routeCandidate: RouteComparisonCandidate? = nil,
        currentCourseIdentity: CourseIdentity? = nil,
        candidateWorkouts: [WorkoutGrowthInput] = [],
        routeCandidates: [RouteComparisonCandidate] = []
    ) {
        self.baseline = baseline
        self.routeCandidate = routeCandidate
        self.currentCourseIdentity = currentCourseIdentity
        self.candidateWorkouts = candidateWorkouts
        self.routeCandidates = routeCandidates
    }
}

protocol SimilarWorkoutCandidateProviding {
    func candidates(for current: UnifiedWorkout) async throws -> [WorkoutGrowthInput]
    func bestCandidate(
        for current: UnifiedWorkout,
        currentRoute: WorkoutRoute?,
        candidateRoutesByWorkoutId: [UUID: WorkoutRoute]
    ) async throws -> SimilarWorkoutCandidateResult?
}

struct SimilarWorkoutCandidateProvider: SimilarWorkoutCandidateProviding {
    private let store: any UnifiedWorkoutStore
    private let mapper: UnifiedWorkoutToGrowthInputMapper
    private let routeSimilarityBuilder: RouteSimilarityBuilder
    private let persistedRouteProvider: (any PersistedRouteCandidateProviding)?
    private let recentDays: Int
    private let maxCandidateCount: Int
    private let distanceToleranceRatio: Double

    init(
        store: any UnifiedWorkoutStore,
        mapper: UnifiedWorkoutToGrowthInputMapper = UnifiedWorkoutToGrowthInputMapper(),
        routeSimilarityBuilder: RouteSimilarityBuilder = RouteSimilarityBuilder(),
        persistedRouteProvider: (any PersistedRouteCandidateProviding)? = nil,
        recentDays: Int = 90,
        maxCandidateCount: Int = 20,
        distanceToleranceRatio: Double = 0.15
    ) {
        self.store = store
        self.mapper = mapper
        self.routeSimilarityBuilder = routeSimilarityBuilder
        self.persistedRouteProvider = persistedRouteProvider
        self.recentDays = recentDays
        self.maxCandidateCount = maxCandidateCount
        self.distanceToleranceRatio = distanceToleranceRatio
    }

    func candidates(for current: UnifiedWorkout) async throws -> [WorkoutGrowthInput] {
        let workouts = try await comparableWorkouts(for: current)
        return workouts.map(mapper.map)
    }

    func bestCandidate(
        for current: UnifiedWorkout,
        currentRoute: WorkoutRoute? = nil,
        candidateRoutesByWorkoutId: [UUID: WorkoutRoute] = [:]
    ) async throws -> SimilarWorkoutCandidateResult? {
        let workouts = try await comparableWorkouts(for: current)
        guard !workouts.isEmpty else { return nil }

        let routeContext = await persistedRouteContextIfAvailable(
            currentWorkoutId: current.id,
            candidateWorkoutIds: workouts.map(\.id)
        )
        let resolvedCurrentRoute = currentRoute ?? routeContext?.currentRoute
        let resolvedCandidateRoutesByWorkoutId = candidateRoutesByWorkoutId.merging(
            routeContext?.candidateRoutesByWorkoutId ?? [:]
        ) { explicit, _ in explicit }

        if let currentRoute = resolvedCurrentRoute {
            let candidateRoutes = workouts.compactMap { candidate -> WorkoutRoute? in
                resolvedCandidateRoutesByWorkoutId[candidate.id]
            }
            let routeCandidates = routeSimilarityBuilder.findCandidates(
                current: currentRoute,
                candidates: candidateRoutes
            )
            let routeCandidate = routeCandidates.first

            if let routeCandidate,
               let matchedWorkout = workouts.first(where: { $0.id == routeCandidate.candidateWorkoutId }) {
                return SimilarWorkoutCandidateResult(
                    baseline: mapper.map(matchedWorkout),
                    routeCandidate: routeCandidate,
                    currentCourseIdentity: routeContext?.currentCourseIdentity,
                    candidateWorkouts: orderedInputs(workouts, routeCandidates: routeCandidates),
                    routeCandidates: routeCandidates
                )
            }
        }

        guard let fallback = distanceFallbackCandidate(current: current, candidates: workouts) else {
            return nil
        }

        return SimilarWorkoutCandidateResult(
            baseline: mapper.map(fallback),
            routeCandidate: nil,
            currentCourseIdentity: routeContext?.currentCourseIdentity,
            candidateWorkouts: workouts.map(mapper.map),
            routeCandidates: []
        )
    }

    private func persistedRouteContextIfAvailable(
        currentWorkoutId: UUID,
        candidateWorkoutIds: [UUID]
    ) async -> PersistedRouteCandidateSet? {
        guard let persistedRouteProvider else { return nil }

        do {
            return try await persistedRouteProvider.routes(
                currentWorkoutId: currentWorkoutId,
                candidateWorkoutIds: candidateWorkoutIds
            )
        } catch {
            return nil
        }
    }

    private func comparableWorkouts(for current: UnifiedWorkout) async throws -> [UnifiedWorkout] {
        let workouts = try await store.fetchRecentWorkouts(days: recentDays)
        return Array(
            workouts
                .filter { $0.id != current.id }
                .filter { $0.workoutType == current.workoutType }
                .filter { !$0.isExcludedFromAnalysis }
                .filter { $0.startDate <= current.startDate }
                .sorted { $0.startDate > $1.startDate }
                .prefix(maxCandidateCount)
        )
    }

    private func distanceFallbackCandidate(
        current: UnifiedWorkout,
        candidates: [UnifiedWorkout]
    ) -> UnifiedWorkout? {
        guard let currentDistance = current.distanceMeters,
              currentDistance > 0 else {
            return candidates.first
        }

        let distanceMatched = candidates
            .compactMap { candidate -> (workout: UnifiedWorkout, ratio: Double)? in
                guard let candidateDistance = candidate.distanceMeters,
                      candidateDistance > 0 else {
                    return nil
                }

                let ratio = abs(currentDistance - candidateDistance) / currentDistance
                guard ratio <= distanceToleranceRatio else { return nil }
                return (candidate, ratio)
            }
            .sorted { lhs, rhs in
                if lhs.ratio == rhs.ratio {
                    return lhs.workout.startDate > rhs.workout.startDate
                }
                return lhs.ratio < rhs.ratio
            }

        return distanceMatched.first?.workout ?? candidates.first
    }

    private func orderedInputs(
        _ workouts: [UnifiedWorkout],
        routeCandidates: [RouteComparisonCandidate]
    ) -> [WorkoutGrowthInput] {
        let routeOrder = Dictionary(uniqueKeysWithValues: routeCandidates.enumerated().map { index, candidate in
            (candidate.candidateWorkoutId, index)
        })

        return workouts
            .filter { routeOrder[$0.id] != nil }
            .sorted { lhs, rhs in
                (routeOrder[lhs.id] ?? Int.max) < (routeOrder[rhs.id] ?? Int.max)
            }
            .map(mapper.map)
    }
}
