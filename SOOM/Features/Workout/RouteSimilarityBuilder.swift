import Foundation

struct RouteSimilarityBuilder {
    private let distanceToleranceRatio = 0.15
    private let endpointNearMeters: Double = 500
    private let minimumSimilarityScore = 0.65

    func findCandidates(
        current: WorkoutRoute,
        candidates: [WorkoutRoute]
    ) -> [RouteComparisonCandidate] {
        candidates
            .compactMap { compare(current, $0) }
            .sorted { lhs, rhs in
                if lhs.similarityScore == rhs.similarityScore {
                    return lhs.candidateWorkoutId.uuidString < rhs.candidateWorkoutId.uuidString
                }
                return lhs.similarityScore > rhs.similarityScore
            }
    }

    func compare(
        _ current: WorkoutRoute,
        _ candidate: WorkoutRoute
    ) -> RouteComparisonCandidate? {
        guard current.workoutId != candidate.workoutId else { return nil }
        guard current.totalDistanceMeters > 0, candidate.totalDistanceMeters > 0 else { return nil }

        let matchedDistance = min(current.totalDistanceMeters, candidate.totalDistanceMeters)
        let distanceRatio = abs(current.totalDistanceMeters - candidate.totalDistanceMeters) / current.totalDistanceMeters
        guard distanceRatio <= distanceToleranceRatio else { return nil }

        let hasComparableGeometry = !current.coordinates.isEmpty && !candidate.coordinates.isEmpty
        let boundsOverlap = current.bounds.flatMap { currentBounds in
            candidate.bounds.map { candidateBounds in
                Self.boundsOverlap(currentBounds, candidateBounds)
            }
        } ?? false
        let endpointsNear = Self.endpointsNear(current.coordinates, candidate.coordinates, thresholdMeters: endpointNearMeters)

        if hasComparableGeometry && !boundsOverlap && !endpointsNear {
            return nil
        }

        var score = 0.65 + (1 - distanceRatio / distanceToleranceRatio) * 0.20
        if boundsOverlap { score += 0.08 }
        if endpointsNear { score += 0.07 }

        let reason: RouteComparisonReason
        if boundsOverlap || endpointsNear {
            reason = .similarRoute
        } else {
            reason = .similarDistance
        }

        guard score >= minimumSimilarityScore else { return nil }

        return RouteComparisonCandidate(
            currentWorkoutId: current.workoutId,
            candidateWorkoutId: candidate.workoutId,
            similarityScore: score,
            reason: reason,
            matchedDistanceMeters: matchedDistance
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
