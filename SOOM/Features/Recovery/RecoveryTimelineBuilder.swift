import Foundation

final class RecoveryTimelineBuilder {
    private let snapshotStore: (any DailyRecoverySnapshotStore)?
    private let fallbackCalendar: Calendar

    init(
        snapshotStore: (any DailyRecoverySnapshotStore)? = nil,
        fallbackCalendar: Calendar = .current
    ) {
        self.snapshotStore = snapshotStore
        self.fallbackCalendar = fallbackCalendar
    }

    func buildTimeline(
        days: Int = 5,
        fallbackSummary: RecoverySummary? = nil
    ) async -> [RecoveryTimelineEntry] {
        guard let snapshotStore else {
            guard let fallbackSummary else {
                return []
            }

            return buildMockTimeline(endingAt: fallbackSummary, calendar: fallbackCalendar)
        }

        do {
            let snapshots = try await snapshotStore.fetchRecentSnapshots(days: days)
            return makeEntries(from: snapshots)
        } catch {
            guard let fallbackSummary else {
                return []
            }

            return buildMockTimeline(endingAt: fallbackSummary, calendar: fallbackCalendar)
        }
    }

    func makeEntries(from snapshots: [DailyRecoverySnapshot]) -> [RecoveryTimelineEntry] {
        snapshots
            .sorted { $0.date > $1.date }
            .map(makeEntry)
    }

    func buildMockTimeline(
        endingAt summary: RecoverySummary,
        calendar: Calendar = .current
    ) -> [RecoveryTimelineEntry] {
        let today = calendar.startOfDay(for: summary.lastUpdated)
        let entries = [
            makeEntry(
                daysAgo: 0,
                from: today,
                calendar: calendar,
                score: summary.score,
                status: summary.status,
                explanation: summary.description,
                checkIn: "최근 컨디션 기록 반영",
                recommendation: summary.recommendation
            ),
            makeEntry(
                daysAgo: 1,
                from: today,
                calendar: calendar,
                score: min(summary.score + 2, 95),
                status: "안정",
                explanation: "가벼운 움직임과 휴식이 함께 이어졌어요.",
                checkIn: "수면감 양호",
                recommendation: "가벼운 Z2 유지"
            ),
            makeEntry(
                daysAgo: 2,
                from: today,
                calendar: calendar,
                score: max(summary.score - 6, 45),
                status: "주의",
                explanation: "운동 부하가 조금 올라와 회복 여유가 줄었어요.",
                checkIn: "피로감 보통",
                recommendation: "강도 조절"
            ),
            makeEntry(
                daysAgo: 3,
                from: today,
                calendar: calendar,
                score: max(summary.score - 3, 45),
                status: "보통",
                explanation: "훈련 리듬은 유지됐지만 완전한 휴식은 부족했어요.",
                checkIn: nil,
                recommendation: "짧은 유산소"
            ),
            makeEntry(
                daysAgo: 4,
                from: today,
                calendar: calendar,
                score: min(summary.score + 4, 95),
                status: "좋음",
                explanation: "휴식일이 포함되어 회복 흐름이 안정적이었어요.",
                checkIn: "컨디션 안정",
                recommendation: nil
            )
        ]

        return entries.sorted { $0.date > $1.date }
    }

    private func makeEntry(from snapshot: DailyRecoverySnapshot) -> RecoveryTimelineEntry {
        RecoveryTimelineEntry(
            date: snapshot.date,
            recoveryScore: snapshot.score,
            status: snapshot.status,
            shortExplanation: snapshot.explanation,
            checkInSummary: nil,
            recommendationSummary: snapshot.recommendation
        )
    }

    private func makeEntry(
        daysAgo: Int,
        from today: Date,
        calendar: Calendar,
        score: Int,
        status: String,
        explanation: String?,
        checkIn: String?,
        recommendation: String?
    ) -> RecoveryTimelineEntry {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today

        return RecoveryTimelineEntry(
            date: date,
            recoveryScore: min(max(score, 45), 95),
            status: status,
            shortExplanation: explanation,
            checkInSummary: checkIn,
            recommendationSummary: recommendation
        )
    }
}
