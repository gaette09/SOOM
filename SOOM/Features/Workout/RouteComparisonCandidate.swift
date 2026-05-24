import Foundation

enum RouteComparisonReason: String, Equatable {
    case similarRoute
    case similarDistance
    case sameWorkoutType
    case recentComparable
}

enum RouteComparisonConfidenceLevel: String, Equatable {
    case low
    case medium
    case high
}

struct RouteComparisonCandidate: Identifiable, Equatable {
    let currentWorkoutId: UUID
    let candidateWorkoutId: UUID
    let similarityScore: Double
    let reason: RouteComparisonReason
    let matchedDistanceMeters: Double?
    let matchedDurationSeconds: TimeInterval?
    let isReverseDirection: Bool
    let confidenceLevel: RouteComparisonConfidenceLevel

    var id: String {
        "\(currentWorkoutId.uuidString)-\(candidateWorkoutId.uuidString)"
    }

    init(
        currentWorkoutId: UUID,
        candidateWorkoutId: UUID,
        similarityScore: Double,
        reason: RouteComparisonReason,
        matchedDistanceMeters: Double? = nil,
        matchedDurationSeconds: TimeInterval? = nil,
        isReverseDirection: Bool = false,
        confidenceLevel: RouteComparisonConfidenceLevel? = nil
    ) {
        self.currentWorkoutId = currentWorkoutId
        self.candidateWorkoutId = candidateWorkoutId
        self.similarityScore = min(1, max(0, similarityScore))
        self.reason = reason
        self.matchedDistanceMeters = matchedDistanceMeters
        self.matchedDurationSeconds = matchedDurationSeconds
        self.isReverseDirection = isReverseDirection
        self.confidenceLevel = confidenceLevel ?? Self.confidenceLevel(for: min(1, max(0, similarityScore)))
    }

    private static func confidenceLevel(for score: Double) -> RouteComparisonConfidenceLevel {
        if score >= 0.86 { return .high }
        if score >= 0.72 { return .medium }
        return .low
    }
}
