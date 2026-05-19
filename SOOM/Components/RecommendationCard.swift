import SwiftUI

struct RecommendationCard: View {
    let title: String
    let description: String
    let actionLabel: String
    let icon: String
    let tint: Color
    let action: () -> Void

    init(
        title: String,
        description: String,
        actionLabel: String,
        icon: String = SOOMIcon.recovery,
        tint: Color = SOOMColor.recovery,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.description = description
        self.actionLabel = actionLabel
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: icon)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text(title)
                        .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)

                    Text(description)
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: action) {
                HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(actionLabel)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    Image(systemName: SOOMIcon.chevronRight)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(SOOMColor.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SOOMLayout.RecoveryAI.ctaVerticalPadding)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.RecoveryAI.ctaCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionLabel)
            .accessibilityHint("추천 행동을 선택합니다.")
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("RecommendationCard") {
    SOOMScreen {
        RecommendationCard(
            title: "오늘의 추천",
            description: "강도를 올리기보다 가볍게 몸을 깨우는 라이딩이 적합합니다.",
            actionLabel: "40분 Z2 라이딩 보기",
            icon: SOOMIcon.bike,
            tint: SOOMColor.bike
        )
    }
    .preferredColorScheme(.light)
}
