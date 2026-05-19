import Foundation

struct RecoveryInsightPersonalizer {
    private let signalClassifier: RecoveryCheckInSignalClassifier

    init(signalClassifier: RecoveryCheckInSignalClassifier = RecoveryCheckInSignalClassifier()) {
        self.signalClassifier = signalClassifier
    }

    func personalize(
        summary: RecoverySummary,
        latestCheckIn: RecoveryCheckIn?
    ) -> RecoverySummary {
        guard let insight = personalizedInsight(from: latestCheckIn) else {
            return summary
        }

        return RecoverySummary(
            score: summary.score,
            status: summary.status,
            description: summary.description,
            recommendation: summary.recommendation,
            trendText: summary.trendText,
            coachMessage: summary.coachMessage,
            recommendationCard: summary.recommendationCard,
            trends: summary.trends,
            insights: [insight] + summary.insights,
            lastUpdated: summary.lastUpdated,
            dataQuality: summary.dataQuality
        )
    }

    private func personalizedInsight(from checkIn: RecoveryCheckIn?) -> RecoveryInsight? {
        switch signalClassifier.classify(checkIn) {
        case .highFatigue:
            return RecoveryInsight(
                title: "피로감이 높게 기록됐어요",
                message: "오늘은 훈련 강도보다 회복 리듬을 우선해도 좋아요.",
                icon: SOOMIcon.recovery,
                tone: .warning
            )
        case .lowSleep:
            return RecoveryInsight(
                title: "수면감이 낮아요",
                message: "짧고 가벼운 움직임으로 몸을 깨우는 정도를 추천해요.",
                icon: SOOMIcon.moon,
                tone: .neutral
            )
        case .highSoreness:
            return RecoveryInsight(
                title: "근육통 신호가 있어요",
                message: "하체나 전신 피로가 크다면 고강도 운동은 하루 미뤄도 괜찮아요.",
                icon: SOOMIcon.bolt,
                tone: .warning
            )
        case .lowMood:
            return RecoveryInsight(
                title: "컨디션이 무겁게 느껴지는 날이에요",
                message: "목표를 낮추고 완료 경험을 만드는 쪽이 더 좋을 수 있어요.",
                icon: SOOMIcon.sparkles,
                tone: .neutral
            )
        case .stable:
            return nil
        }
    }
}
