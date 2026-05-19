import SwiftUI

struct DailyReadinessCard: View {
    let state: DailyReadinessState

    var body: some View {
        SOOMCard {
            HStack(alignment: .center, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: state.icon ?? SOOMIcon.recovery)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                    Text("오늘 준비 상태")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(tint)

                    Text(state.title)
                        .font(SOOMFont.displayMedium(18, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(state.shortMessage)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("오늘 준비 상태")
        .accessibilityValue("\(state.title). \(state.shortMessage)")
    }

    private var tint: Color {
        switch state.actionTone {
        case .proceed:
            return SOOMColor.recovery
        case .easeIn:
            return SOOMColor.orange
        case .recover:
            return SOOMColor.warning
        case .observe:
            return SOOMColor.secondaryInk
        }
    }
}

#Preview("DailyReadinessCard") {
    SOOMScreen {
        DailyReadinessCard(
            state: DailyReadinessBuilder().build(from: .mockToday)
        )
    }
    .preferredColorScheme(.light)
}
