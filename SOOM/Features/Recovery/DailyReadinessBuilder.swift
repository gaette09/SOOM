import Foundation

struct DailyReadinessBuilder {
    func build(from summary: RecoverySummary) -> DailyReadinessState {
        if summary.status == "데이터 부족" {
            return DailyReadinessState(
                readinessLevel: .insufficientData,
                title: "기록이 더 필요해요",
                shortMessage: "가벼운 움직임부터 시작하며 몸 상태를 확인해보세요.",
                actionTone: .observe,
                icon: SOOMIcon.calendarClock
            )
        }

        switch summary.score {
        case 85...:
            return DailyReadinessState(
                readinessLevel: .ready,
                title: "오늘은 훈련하기 좋은 흐름이에요",
                shortMessage: "몸 상태가 안정적입니다. 계획한 훈련을 차분히 진행해도 좋아요.",
                actionTone: .proceed,
                icon: SOOMIcon.checkCircle
            )
        case 70..<85:
            return DailyReadinessState(
                readinessLevel: .moderate,
                title: "가벼운 강도부터 확인해보세요",
                shortMessage: "준비도는 무난합니다. 워밍업에서 몸의 반응을 먼저 살펴보세요.",
                actionTone: .easeIn,
                icon: SOOMIcon.trendFlat
            )
        default:
            return DailyReadinessState(
                readinessLevel: .recovery,
                title: "오늘은 회복을 우선해도 좋아요",
                shortMessage: "강도를 올리기보다 피로를 낮추는 움직임을 선택해보세요.",
                actionTone: .recover,
                icon: SOOMIcon.recovery
            )
        }
    }
}
