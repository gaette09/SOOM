import Foundation

enum WorkoutRecoveryImpactLevel: String, Equatable {
    case light
    case moderate
    case high
    case recoveryFriendly
    case insufficientData

    var icon: String {
        switch self {
        case .light:
            return SOOMIcon.trendFlat
        case .moderate:
            return SOOMIcon.waveform
        case .high:
            return SOOMIcon.bolt
        case .recoveryFriendly:
            return SOOMIcon.recovery
        case .insufficientData:
            return SOOMIcon.checkCircle
        }
    }
}

struct WorkoutRecoveryImpact: Equatable {
    let impactLevel: WorkoutRecoveryImpactLevel
    let title: String
    let shortMessage: String
    let recommendation: String
    let icon: String?
}
