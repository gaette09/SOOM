import Foundation

struct FeedWeeklySnapshot: Equatable {
    let progress: WeeklyWorkoutProgress
    let sportSummary: String

    init(progress: WeeklyWorkoutProgress, sportSummary: String) {
        self.progress = progress
        self.sportSummary = sportSummary
    }
}

struct FeedRecoveryInsight: Equatable {
    let score: Int
    let status: String
    let recommendation: String
    let coachMessage: String?

    init(summary: RecoverySummary) {
        self.score = summary.score
        self.status = summary.status
        self.recommendation = summary.recommendation
        self.coachMessage = summary.coachMessage.message.nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
