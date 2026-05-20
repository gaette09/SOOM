import Foundation

enum UnifiedWorkoutDuplicateResolutionPolicy: Equatable {
    case keepPrimary
    case preferDuplicate
    case needsReview
    case ignore
}

struct UnifiedWorkoutDuplicateCandidate: Equatable {
    let primaryWorkout: UnifiedWorkout
    let duplicateWorkout: UnifiedWorkout
    let confidence: Double
    let reasons: [String]
    let preferredSource: UnifiedDataSource
    let resolutionPolicy: UnifiedWorkoutDuplicateResolutionPolicy
}
