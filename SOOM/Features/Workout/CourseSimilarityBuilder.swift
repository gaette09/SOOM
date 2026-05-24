import Foundation

struct CourseSimilarityBuilder {
    private let distanceToleranceRatio = 0.12
    private let endpointNearMeters: Double = 350
    private let minimumSimilarityScore = 0.72

    func isSameCourse(current: WorkoutRoute, candidate: WorkoutRoute) -> Bool {
        compare(current: current, candidate: candidate) != nil
    }

    func findCandidates(
        current: WorkoutRoute,
        candidates: [WorkoutRoute]
    ) -> [RouteComparisonCandidate] {
        candidates
            .compactMap { compare(current: current, candidate: $0) }
            .sorted { lhs, rhs in
                if lhs.similarityScore == rhs.similarityScore {
                    return lhs.candidateWorkoutId.uuidString < rhs.candidateWorkoutId.uuidString
                }
                return lhs.similarityScore > rhs.similarityScore
            }
    }

    func compare(
        current: WorkoutRoute,
        candidate: WorkoutRoute
    ) -> RouteComparisonCandidate? {
        guard current.workoutId != candidate.workoutId else { return nil }
        guard current.totalDistanceMeters > 0, candidate.totalDistanceMeters > 0 else { return nil }

        let distanceRatio = abs(current.totalDistanceMeters - candidate.totalDistanceMeters) / current.totalDistanceMeters
        guard distanceRatio <= distanceToleranceRatio else { return nil }

        let boundsOverlap = current.bounds.flatMap { currentBounds in
            candidate.bounds.map { candidateBounds in
                Self.boundsOverlap(currentBounds, candidateBounds)
            }
        } ?? false
        let endpointsNear = Self.endpointsNear(
            current.coordinates,
            candidate.coordinates,
            thresholdMeters: endpointNearMeters
        )

        guard boundsOverlap || endpointsNear else { return nil }

        var score = 0.70 + (1 - distanceRatio / distanceToleranceRatio) * 0.18
        if boundsOverlap { score += 0.06 }
        if endpointsNear { score += 0.06 }

        guard score >= minimumSimilarityScore else { return nil }

        return RouteComparisonCandidate(
            currentWorkoutId: current.workoutId,
            candidateWorkoutId: candidate.workoutId,
            similarityScore: score,
            reason: .similarRoute,
            matchedDistanceMeters: min(current.totalDistanceMeters, candidate.totalDistanceMeters),
            matchedDurationSeconds: nil
        )
    }

    private static func boundsOverlap(_ lhs: WorkoutRouteBounds, _ rhs: WorkoutRouteBounds) -> Bool {
        lhs.minLatitude <= rhs.maxLatitude &&
        lhs.maxLatitude >= rhs.minLatitude &&
        lhs.minLongitude <= rhs.maxLongitude &&
        lhs.maxLongitude >= rhs.minLongitude
    }

    private static func endpointsNear(
        _ lhs: [WorkoutRouteCoordinate],
        _ rhs: [WorkoutRouteCoordinate],
        thresholdMeters: Double
    ) -> Bool {
        guard let lhsStart = lhs.first,
              let lhsEnd = lhs.last,
              let rhsStart = rhs.first,
              let rhsEnd = rhs.last else {
            return false
        }

        let sameDirection = distance(lhsStart, rhsStart) <= thresholdMeters && distance(lhsEnd, rhsEnd) <= thresholdMeters
        let reverseDirection = distance(lhsStart, rhsEnd) <= thresholdMeters && distance(lhsEnd, rhsStart) <= thresholdMeters
        return sameDirection || reverseDirection
    }

    private static func distance(_ lhs: WorkoutRouteCoordinate, _ rhs: WorkoutRouteCoordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let lhsLatitude = lhs.latitude * .pi / 180
        let rhsLatitude = rhs.latitude * .pi / 180
        let deltaLatitude = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLongitude = (rhs.longitude - lhs.longitude) * .pi / 180

        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2) +
        cos(lhsLatitude) * cos(rhsLatitude) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }
}
