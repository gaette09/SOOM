import Foundation

struct DailyRecoverySnapshot: Identifiable {
    let id: UUID
    let date: Date
    let score: Int
    let status: String
    let recommendation: String
    let coachMessage: String
    let explanation: String?
    let dataQuality: RecoveryDataQuality
    let activityCount: Int
    let checkInId: UUID?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        score: Int,
        status: String,
        recommendation: String,
        coachMessage: String,
        explanation: String? = nil,
        dataQuality: RecoveryDataQuality,
        activityCount: Int,
        checkInId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.score = min(max(score, 45), 95)
        self.status = status
        self.recommendation = recommendation
        self.coachMessage = coachMessage
        self.explanation = explanation
        self.dataQuality = dataQuality
        self.activityCount = max(activityCount, 0)
        self.checkInId = checkInId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
