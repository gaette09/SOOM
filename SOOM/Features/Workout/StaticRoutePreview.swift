import Foundation

enum StaticRouteFallbackStyle: String, Equatable {
    case running
    case cycling
    case swimming
    case walking
    case generic

    init(workoutType: UnifiedWorkoutType) {
        switch workoutType {
        case .running:
            self = .running
        case .cycling:
            self = .cycling
        case .swimming:
            self = .swimming
        case .walking, .hiking:
            self = .walking
        case .strength, .yoga, .other:
            self = .generic
        }
    }
}

struct StaticRoutePreview: Equatable {
    let imageURL: URL?
    let bounds: WorkoutRouteBounds?
    let routeExists: Bool
    let fallbackStyle: StaticRouteFallbackStyle
}
