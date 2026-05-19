import SwiftUI

struct RecoveryExplanationCard: View {
    let title: String
    let explanation: String
    let supportingBullets: [String]
    let icon: String
    let tone: InsightTone

    init(
        title: String,
        explanation: String,
        supportingBullets: [String] = [],
        icon: String = SOOMIcon.chartLine,
        tone: InsightTone = .neutral
    ) {
        self.title = title
        self.explanation = explanation
        self.supportingBullets = Array(supportingBullets.prefix(2))
        self.icon = icon
        self.tone = tone
    }

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: icon)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(tone.tint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(tone.tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text(title)
                        .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)

                    Text(explanation)
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if !supportingBullets.isEmpty {
                        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                            ForEach(supportingBullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: SOOMLayout.SectionHeader.spacing) {
                                    Text("•")
                                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                                    Text(bullet)
                                        .font(SOOMFont.body(12, relativeTo: .caption))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundStyle(SOOMColor.tertiaryInk)
                            }
                        }
                        .padding(.top, SOOMLayout.SectionHeader.spacing)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        ([explanation] + supportingBullets).joined(separator: ", ")
    }
}

#Preview("RecoveryExplanationCard") {
    SOOMScreen {
        RecoveryExplanationCard(
            title: "왜 이런 상태인가요?",
            explanation: "최근 운동 부하가 높게 유지되고 있어 회복을 먼저 보는 흐름입니다.",
            supportingBullets: [
                "최근 3일 부하가 높은 편입니다.",
                "오늘은 강도보다 리듬 유지가 좋습니다."
            ],
            icon: SOOMIcon.chartLine,
            tone: .warning
        )
    }
    .preferredColorScheme(.light)
}
