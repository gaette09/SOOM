import Foundation

struct RecoveryComparisonBuilder {
    func build(
        officialSummary: RecoverySummary,
        previewSummary: RecoverySummary
    ) -> RecoveryComparisonSummary {
        let difference = abs(previewSummary.score - officialSummary.score)
        let level = differenceLevel(for: difference)

        return RecoveryComparisonSummary(
            officialScore: officialSummary.score,
            previewScore: previewSummary.score,
            difference: difference,
            differenceLevel: level,
            comparisonMessage: comparisonMessage(
                officialScore: officialSummary.score,
                previewScore: previewSummary.score,
                level: level
            ),
            recommendation: recommendation(for: level),
            confidenceNote: "분석 제외된 운동, 중복 기록 여부, 가져온 데이터 범위에 따라 차이가 날 수 있어요."
        )
    }

    private func differenceLevel(for difference: Int) -> RecoveryComparisonSummary.DifferenceLevel {
        switch difference {
        case 0...5:
            return .similar
        case 6...12:
            return .moderate
        default:
            return .large
        }
    }

    private func comparisonMessage(
        officialScore: Int,
        previewScore: Int,
        level: RecoveryComparisonSummary.DifferenceLevel
    ) -> String {
        switch level {
        case .similar:
            return "공식 Recovery와 미리보기 흐름이 거의 비슷하게 보입니다."
        case .moderate:
            if previewScore < officialScore {
                return "가져온 운동 기록 기준으로는 회복 부하가 조금 더 높게 계산됐어요."
            }
            return "가져온 운동 기록 기준으로는 회복 흐름이 조금 더 여유롭게 보입니다."
        case .large:
            if previewScore < officialScore {
                return "가져온 운동 기록 범위에서는 회복 부하 차이가 크게 보입니다."
            }
            return "가져온 운동 기록 범위에서는 회복 흐름 차이가 크게 보입니다."
        }
    }

    private func recommendation(for level: RecoveryComparisonSummary.DifferenceLevel) -> String {
        switch level {
        case .similar:
            return "현재는 두 흐름을 참고용으로 함께 봐도 괜찮아요."
        case .moderate:
            return "가져온 운동 기록과 분석 제외 설정을 한 번 확인해보세요."
        case .large:
            return "기본 Recovery에 반영하기 전, 중복 기록과 누락된 운동이 있는지 먼저 확인하는 편이 좋아요."
        }
    }
}
