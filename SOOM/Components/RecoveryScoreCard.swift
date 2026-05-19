import SwiftUI

struct RecoveryScoreCard: View {
    let score: Int
    let status: String
    let description: String
    let recommendation: String
    let trendText: String?
    let tint: Color

    init(
        score: Int,
        status: String,
        description: String,
        recommendation: String,
        trendText: String? = nil,
        tint: Color = SOOMColor.recovery
    ) {
        self.score = score
        self.status = status
        self.description = description
        self.recommendation = recommendation
        self.trendText = trendText
        self.tint = tint
    }

    var body: some View {
        SOOMCard {
            HStack(alignment: .center, spacing: SOOMLayout.RecoveryAI.scoreHeaderSpacing) {
                SOOMMetricRing(score: score, title: "회복 점수", tint: tint)
                    .accessibilityLabel("회복 점수")
                    .accessibilityValue("\(score)점")

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text(status)
                        .font(SOOMFont.displayMedium(22, relativeTo: .title3))
                        .foregroundStyle(SOOMColor.ink)

                    Text(description)
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if let trendText {
                        Label(trendText, systemImage: SOOMIcon.trend)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(tint)
                    }
                }
            }

            Divider()
                .overlay(SOOMColor.line)

            Label(recommendation, systemImage: SOOMIcon.recovery)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .labelStyle(.titleAndIcon)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("회복 상태 카드")
        .accessibilityValue("회복 점수 \(score)점, \(status). \(recommendation)")
    }
}

#Preview("RecoveryScoreCard") {
    SOOMScreen {
        RecoveryScoreCard(
            score: 82,
            status: "좋음",
            description: "수면과 휴식 흐름이 안정적입니다. 오늘은 강도보다 리듬 유지가 더 중요합니다.",
            recommendation: "오늘은 Z2 라이딩 40분을 추천해요.",
            trendText: "지난 7일 대비 +6점"
        )
    }
    .preferredColorScheme(.light)
}
