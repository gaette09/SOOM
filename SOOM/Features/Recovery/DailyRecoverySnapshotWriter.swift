import Foundation

struct DailyRecoverySnapshotWriter {
    private let snapshotStore: any DailyRecoverySnapshotStore
    private let referenceDate: () -> Date

    init(
        snapshotStore: any DailyRecoverySnapshotStore,
        referenceDate: @escaping () -> Date = Date.init
    ) {
        self.snapshotStore = snapshotStore
        self.referenceDate = referenceDate
    }

    func saveTodaySnapshot(
        from summary: RecoverySummary,
        latestCheckIn: RecoveryCheckIn?,
        explanation: String?,
        activityCount: Int = 0
    ) async throws {
        let snapshot = makeTodaySnapshot(
            from: summary,
            latestCheckIn: latestCheckIn,
            explanation: explanation,
            activityCount: activityCount
        )

        try await snapshotStore.saveSnapshot(snapshot)
    }

    func makeTodaySnapshot(
        from summary: RecoverySummary,
        latestCheckIn: RecoveryCheckIn?,
        explanation: String?,
        activityCount: Int = 0
    ) -> DailyRecoverySnapshot {
        DailyRecoverySnapshot(
            date: referenceDate(),
            score: summary.score,
            status: summary.status,
            recommendation: summary.recommendation,
            coachMessage: summary.coachMessage.message,
            explanation: explanation,
            dataQuality: summary.dataQuality,
            activityCount: activityCount,
            checkInId: latestCheckIn?.id
        )
    }
}
