import Foundation

struct RecoveryExplanation {
    let title: String
    let explanation: String
    let supportingBullets: [String]
    let icon: String
    let tone: InsightTone
}

struct RecoveryExplanationBuilder {
    private let signalClassifier: RecoveryCheckInSignalClassifier

    init(signalClassifier: RecoveryCheckInSignalClassifier = RecoveryCheckInSignalClassifier()) {
        self.signalClassifier = signalClassifier
    }

    func build(
        summary: RecoverySummary,
        latestCheckIn: RecoveryCheckIn?
    ) -> RecoveryExplanation {
        switch signalClassifier.classify(latestCheckIn) {
        case .highFatigue:
            return RecoveryExplanation(
                title: "왜 이런 상태인가요?",
                explanation: "최근 컨디션 기록에서 피로감이 높게 나타났어요.",
                supportingBullets: [
                    "회복 점수는 운동 기록 기준을 유지합니다.",
                    "오늘은 강도보다 회복 리듬을 먼저 확인해보세요."
                ],
                icon: SOOMIcon.recovery,
                tone: .warning
            )
        case .lowSleep:
            return RecoveryExplanation(
                title: "왜 이런 상태인가요?",
                explanation: "수면감 기록이 낮아 회복을 우선하는 흐름으로 해석하고 있어요.",
                supportingBullets: [
                    "짧고 가벼운 움직임이 몸 상태 확인에 좋습니다.",
                    "코칭 문구에만 반영되고 점수는 바꾸지 않습니다."
                ],
                icon: SOOMIcon.moon,
                tone: .warning
            )
        case .highSoreness:
            return RecoveryExplanation(
                title: "왜 이런 상태인가요?",
                explanation: "근육통 신호가 있어 고강도보다 부드러운 움직임을 먼저 권합니다.",
                supportingBullets: [
                    "불편감이 크면 하체 강도는 낮추는 편이 좋습니다."
                ],
                icon: SOOMIcon.recovery,
                tone: .neutral
            )
        case .lowMood:
            return RecoveryExplanation(
                title: "왜 이런 상태인가요?",
                explanation: "오늘 컨디션이 무겁게 기록되어 목표를 낮추는 방향으로 안내하고 있어요.",
                supportingBullets: [
                    "완료하기 쉬운 세션이 리듬 유지에 도움이 됩니다."
                ],
                icon: SOOMIcon.sparkles,
                tone: .neutral
            )
        case .stable:
            break
        }

        if hasHighTrainingLoad(summary) {
            return RecoveryExplanation(
                title: "왜 이런 상태인가요?",
                explanation: "최근 운동 부하가 높게 유지되고 있어요.",
                supportingBullets: [
                    summary.trendText,
                    "다음 고강도 전에는 피로를 먼저 낮추는 편이 좋습니다."
                ],
                icon: SOOMIcon.chartLine,
                tone: .warning
            )
        }

        if hasRestSignal(summary) {
            return RecoveryExplanation(
                title: "왜 이런 상태인가요?",
                explanation: "휴식일이 포함되어 회복 리듬이 안정적으로 유지되고 있어요.",
                supportingBullets: [
                    "최근 부하는 관리 가능한 흐름입니다.",
                    "오늘은 편안한 강도로 리듬을 이어가기 좋습니다."
                ],
                icon: SOOMIcon.moon,
                tone: .positive
            )
        }

        return RecoveryExplanation(
            title: "왜 이런 상태인가요?",
            explanation: "최근 운동 기록과 컨디션 흐름을 함께 보고 오늘의 회복 상태를 정리했어요.",
            supportingBullets: [
                summary.trendText
            ],
            icon: SOOMIcon.chartLine,
            tone: .neutral
        )
    }

    private func hasHighTrainingLoad(_ summary: RecoverySummary) -> Bool {
        summary.trends.contains { trend in
            guard trend.title == "운동 부하" else { return false }
            if case .up = trend.direction {
                return true
            }

            return trend.values.suffix(3).contains { $0 >= 85 }
        } || summary.insights.contains { insight in
            guard insight.title.contains("부하") else { return false }

            if case .warning = insight.tone {
                return true
            }

            return false
        }
    }

    private func hasRestSignal(_ summary: RecoverySummary) -> Bool {
        summary.description.contains("휴식일") ||
            summary.coachMessage.message.contains("리듬") ||
            summary.insights.contains { insight in
                insight.title.contains("안정") || insight.message.contains("관리 가능한")
            }
    }
}
