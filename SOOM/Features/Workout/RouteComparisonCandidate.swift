import Foundation

enum RouteComparisonReason: String, Equatable {
    case similarRoute
    case similarDistance
    case sameWorkoutType
    case recentComparable
}

struct RouteComparisonCandidate: Identifiable, Equatable {
    let currentWorkoutId: UUID
    let candidateWorkoutId: UUID
    let similarityScore: Double
    let reason: RouteComparisonReason
    let matchedDistanceMeters: Double?
    let matchedDurationSeconds: TimeInterval?

    var id: String {
        "\(currentWorkoutId.uuidString)-\(candidateWorkoutId.uuidString)"
    }

    init(
        currentWorkoutId: UUID,
        candidateWorkoutId: UUID,
        similarityScore: Double,
        reason: RouteComparisonReason,
        matchedDistanceMeters: Double? = nil,
        matchedDurationSeconds: TimeInterval? = nil
    ) {
        self.currentWorkoutId = currentWorkoutId
        self.candidateWorkoutId = candidateWorkoutId
        self.similarityScore = min(1, max(0, similarityScore))
        self.reason = reason
        self.matchedDistanceMeters = matchedDistanceMeters
        self.matchedDurationSeconds = matchedDurationSeconds
    }
}
