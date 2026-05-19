import Foundation

struct RecoveryCoachMessagePersonalizer {
    private let signalClassifier: RecoveryCheckInSignalClassifier

    init(signalClassifier: RecoveryCheckInSignalClassifier = RecoveryCheckInSignalClassifier()) {
        self.signalClassifier = signalClassifier
    }

    func personalize(
        summary: RecoverySummary,
        latestCheckIn: RecoveryCheckIn?
    ) -> RecoverySummary {
        guard let latestCheckIn else { return summary }

        let message = personalizedCoachMessage(
            originalMessage: summary.coachMessage.message,
            latestCheckIn: latestCheckIn
        )

        return RecoverySummary(
            score: summary.score,
            status: summary.status,
            description: summary.description,
            recommendation: summary.recommendation,
            trendText: summary.trendText,
            coachMessage: RecoveryCoachMessage(
                coachName: summary.coachMessage.coachName,
                subtitle: summary.coachMessage.subtitle,
                message: message
            ),
            recommendationCard: summary.recommendationCard,
            trends: summary.trends,
            insights: summary.insights,
            lastUpdated: summary.lastUpdated,
            dataQuality: summary.dataQuality
        )
    }

    func personalizedCoachMessage(
        originalMessage: String,
        latestCheckIn: RecoveryCheckIn?
    ) -> String {
        switch signalClassifier.classify(latestCheckIn) {
        case .highFatigue:
            return "오늘은 피로감이 높게 기록됐어요. 강도보다 회복을 우선하고, 움직인다면 편안한 호흡이 유지되는 정도로 가볍게 시작해보세요."
        case .lowSleep:
            return "수면감이 낮게 기록됐어요. 오늘은 성과를 만들기보다 짧고 가벼운 움직임으로 몸 상태를 확인하는 편이 좋습니다."
        case .highSoreness:
            return "근육통이 높게 기록됐어요. 고강도 운동은 잠시 미루고, 회복성 활동이나 부드러운 스트레칭으로 몸을 풀어보세요."
        case .lowMood:
            return "컨디션이 무겁게 느껴지는 날이에요. 목표를 낮춰도 괜찮습니다. 오늘은 작은 움직임으로 리듬만 이어가도 충분해요."
        case .stable:
            return originalMessage
        }
    }
}
