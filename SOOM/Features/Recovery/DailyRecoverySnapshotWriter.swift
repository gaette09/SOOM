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
        activityCount: Int? = nil
    ) async throws {
        // A calculator fallback is not an observed day of recovery history.
        guard summary.hasCalculatedScore else { return }
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
        activityCount: Int? = nil
    ) -> DailyRecoverySnapshot {
        let date = referenceDate()
        let knownCount = activityCount ?? (Calendar.current.isDate(summary.lastUpdated, inSameDayAs: date) ? summary.activityCountToday : nil)
        return DailyRecoverySnapshot(
            date: date,
            score: summary.score,
            status: summary.status,
            recommendation: summary.recommendation,
            coachMessage: summary.coachMessage.message,
            explanation: explanation,
            dataQuality: summary.dataQuality,
            activityCount: knownCount ?? 0,
            activityCountKnown: knownCount != nil,
            checkInId: latestCheckIn?.id
        )
    }
}
