import Foundation

struct DailyRecoverySnapshotMapper {
    func makeRecord(from snapshot: DailyRecoverySnapshot) -> DailyRecoverySnapshotRecord {
        DailyRecoverySnapshotRecord(
            id: snapshot.id,
            date: snapshot.date,
            score: snapshot.score,
            status: snapshot.status,
            recommendation: snapshot.recommendation,
            coachMessage: snapshot.coachMessage,
            explanation: snapshot.explanation,
            dataQuality: makeDataQualityString(from: snapshot.dataQuality),
            activityCount: snapshot.activityCount,
            checkInId: snapshot.checkInId,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
    }

    func makeSnapshot(from record: DailyRecoverySnapshotRecord) -> DailyRecoverySnapshot {
        DailyRecoverySnapshot(
            id: record.id,
            date: record.date,
            score: record.score,
            status: record.status,
            recommendation: record.recommendation,
            coachMessage: record.coachMessage,
            explanation: record.explanation,
            dataQuality: makeDataQuality(from: record.dataQuality),
            activityCount: record.activityCount,
            checkInId: record.checkInId,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    func makeDataQualityString(from dataQuality: RecoveryDataQuality) -> String {
        switch dataQuality {
        case .mock:
            return "mock"
        case .estimated:
            return "estimated"
        case .highConfidence:
            return "highConfidence"
        }
    }

    func makeDataQuality(from rawValue: String) -> RecoveryDataQuality {
        switch rawValue {
        case "mock":
            return .mock
        case "highConfidence":
            return .highConfidence
        default:
            return .estimated
        }
    }
}
