import Foundation

struct DailyReadinessState {
    let readinessLevel: DailyReadinessLevel
    let title: String
    let shortMessage: String
    let actionTone: DailyReadinessActionTone
    let icon: String?
}

enum DailyReadinessLevel {
    case ready
    case moderate
    case recovery
    case insufficientData
}

enum DailyReadinessActionTone {
    case proceed
    case easeIn
    case recover
    case observe
}
