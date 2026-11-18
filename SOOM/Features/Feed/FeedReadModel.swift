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
    let score: Int?
    let status: String
    let recommendation: String
    let coachMessage: String?

    init(preview: UnifiedWorkoutRecoveryPreviewResult) {
        guard preview.usedWorkoutCount > 0, preview.summary.hasCalculatedScore else {
            score = nil
            status = "데이터 부족"
            recommendation = "최근 운동 기록이 쌓이면 회복 흐름을 확인할 수 있어요."
            coachMessage = nil
            return
        }
        score = preview.summary.score
        status = preview.summary.status
        recommendation = preview.summary.recommendation
        coachMessage = preview.summary.coachMessage.message.nilIfEmpty
    }

    var accessibilityValue: String {
        if let score { return "\(score)점, \(status). \(recommendation)" }
        return "\(status). \(recommendation)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
