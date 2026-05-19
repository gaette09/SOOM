import Foundation
import SwiftData

@Model
final class DailyRecoverySnapshotRecord {
    var id: UUID
    var date: Date
    var score: Int
    var status: String
    var recommendation: String
    var coachMessage: String
    var explanation: String?
    var dataQuality: String
    var activityCount: Int
    var checkInId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        score: Int,
        status: String,
        recommendation: String,
        coachMessage: String,
        explanation: String? = nil,
        dataQuality: String,
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
