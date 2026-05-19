import Foundation

final class WeeklyRecoverySummaryBuilder {
    private let snapshotStore: any DailyRecoverySnapshotStore
    private let calendar: Calendar

    init(
        snapshotStore: any DailyRecoverySnapshotStore,
        calendar: Calendar = .current
    ) {
        self.snapshotStore = snapshotStore
        self.calendar = calendar
    }

    func buildSummary(days: Int = 7) async -> WeeklyRecoverySummary? {
        do {
            let snapshots = try await snapshotStore.fetchRecentSnapshots(days: days)
            return makeSummary(from: snapshots, days: days)
        } catch {
            return nil
        }
    }

    func makeSummary(
        from snapshots: [DailyRecoverySnapshot],
        days: Int = 7
    ) -> WeeklyRecoverySummary? {
        let recentSnapshots = Array(
            snapshots
                .sorted { $0.date > $1.date }
                .prefix(days)
        )

        guard !recentSnapshots.isEmpty else {
            return nil
        }

        let scores = recentSnapshots.map(\.score)
        let averageScore = roundedAverage(scores)
        let bestDayScore = scores.max() ?? averageScore
        let lowestDayScore = scores.min() ?? averageScore
        let trendDirection = calculateTrendDirection(from: recentSnapshots)
        let weekStartDate = calendar.startOfDay(for: recentSnapshots.map(\.date).min() ?? Date())
        let hasRestRecovery = hasRecoveryAfterRestDay(in: recentSnapshots)
        let hasRepeatedFatigueSignal = hasRepeatedFatigueSignal(in: recentSnapshots)

        return WeeklyRecoverySummary(
            weekStartDate: weekStartDate,
            averageScore: averageScore,
            bestDayScore: bestDayScore,
            lowestDayScore: lowestDayScore,
            trendDirection: trendDirection,
            shortSummary: buildShortSummary(
                averageScore: averageScore,
                scoreSpread: bestDayScore - lowestDayScore,
                trendDirection: trendDirection,
                hasRestRecovery: hasRestRecovery
            ),
            coachInsight: buildCoachInsight(
                trendDirection: trendDirection,
                hasRestRecovery: hasRestRecovery,
                hasRepeatedFatigueSignal: hasRepeatedFatigueSignal
            ),
            recommendation: buildRecommendation(
                averageScore: averageScore,
                lowestDayScore: lowestDayScore,
                trendDirection: trendDirection
            )
        )
    }

    private func roundedAverage(_ scores: [Int]) -> Int {
        guard !scores.isEmpty else { return 0 }

        let total = scores.reduce(0, +)
        return Int((Double(total) / Double(scores.count)).rounded())
    }

    private func calculateTrendDirection(
        from snapshots: [DailyRecoverySnapshot]
    ) -> WeeklyRecoveryTrendDirection {
        guard snapshots.count >= 2 else {
            return .stable
        }

        let newestScores = snapshots.prefix(3).map(\.score)
        let olderScores = snapshots.suffix(min(3, snapshots.count)).map(\.score)
        let delta = roundedAverage(newestScores) - roundedAverage(olderScores)

        if delta >= 3 {
            return .improving
        }

        if delta <= -3 {
            return .declining
        }

        return .stable
    }

    private func hasRecoveryAfterRestDay(in snapshots: [DailyRecoverySnapshot]) -> Bool {
        let chronological = snapshots.sorted { $0.date < $1.date }

        for index in chronological.indices.dropLast() {
            let current = chronological[index]
            let next = chronological[index + 1]

            if current.activityCount == 0 && next.score - current.score >= 4 {
                return true
            }
        }

        return false
    }

    private func hasRepeatedFatigueSignal(in snapshots: [DailyRecoverySnapshot]) -> Bool {
        let fatigueMentions = snapshots.filter { snapshot in
            let text = [
                snapshot.explanation,
                snapshot.coachMessage,
                snapshot.recommendation
            ]
                .compactMap { $0 }
                .joined(separator: " ")

            return text.contains("피로")
        }

        return fatigueMentions.count >= 2
    }

    private func buildShortSummary(
        averageScore: Int,
        scoreSpread: Int,
        trendDirection: WeeklyRecoveryTrendDirection,
        hasRestRecovery: Bool
    ) -> String {
        if averageScore >= 85 && scoreSpread <= 8 {
            return "이번 주는 회복 흐름이 안정적이었어요."
        }

        if hasRestRecovery {
            return "휴식 이후 회복 흐름이 다시 안정됐어요."
        }

        switch trendDirection {
        case .improving:
            return "주 후반으로 갈수록 회복 흐름이 좋아졌어요."
        case .declining:
            return "후반부로 갈수록 피로가 누적되는 흐름이 보였어요."
        case .stable:
            return "이번 주 회복 흐름은 큰 흔들림 없이 이어졌어요."
        }
    }

    private func buildCoachInsight(
        trendDirection: WeeklyRecoveryTrendDirection,
        hasRestRecovery: Bool,
        hasRepeatedFatigueSignal: Bool
    ) -> String {
        if hasRepeatedFatigueSignal {
            return "최근 기록에서 피로 신호가 반복되어, 다음 주 초반은 강도보다 회복 리듬을 먼저 보는 편이 좋습니다."
        }

        if hasRestRecovery {
            return "휴식이나 가벼운 날 이후 회복 점수가 다시 올라오는 패턴이 보였어요."
        }

        switch trendDirection {
        case .improving:
            return "훈련 후반으로 갈수록 몸이 다시 받아들이는 흐름이 좋아지고 있습니다."
        case .declining:
            return "회복 점수가 조금씩 낮아지는 구간이 있어, 누적 피로를 먼저 풀어주는 주간 설계가 어울립니다."
        case .stable:
            return "회복 점수의 흔들림이 크지 않아 기본 컨디션 리듬은 안정적으로 유지되고 있습니다."
        }
    }

    private func buildRecommendation(
        averageScore: Int,
        lowestDayScore: Int,
        trendDirection: WeeklyRecoveryTrendDirection
    ) -> String {
        if lowestDayScore <= 60 || trendDirection == .declining {
            return "다음 주 첫 훈련은 짧고 가볍게 시작하고, 강도는 컨디션을 본 뒤 올려보세요."
        }

        if averageScore >= 85 {
            return "다음 주도 현재 리듬을 유지하되, 고강도 뒤에는 회복일을 분명히 넣어주세요."
        }

        return "다음 주는 Z2 기반의 안정적인 훈련과 충분한 회복을 함께 가져가보세요."
    }
}
