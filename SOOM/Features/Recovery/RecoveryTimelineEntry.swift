import Foundation

struct RecoveryTimelineEntry: Identifiable {
    let id = UUID()
    let date: Date
    let recoveryScore: Int
    let status: String
    let shortExplanation: String?
    let checkInSummary: String?
    let recommendationSummary: String?

    var clampedScore: Int {
        min(max(recoveryScore, 45), 95)
    }
}
