import SwiftUI

enum InsightTone {
    case neutral
    case positive
    case warning

    var tint: Color {
        switch self {
        case .neutral:
            return SOOMColor.blue
        case .positive:
            return SOOMColor.green
        case .warning:
            return SOOMColor.warning
        }
    }
}

struct InsightCard: View {
    let title: String
    let message: String
    let icon: String
    let tone: InsightTone

    init(title: String, message: String, icon: String = SOOMIcon.waveform, tone: InsightTone = .neutral) {
        self.title = title
        self.message = message
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

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text(title)
                        .font(SOOMFont.displayMedium(15, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)

                    Text(message)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

#Preview("InsightCard") {
    SOOMScreen {
        InsightCard(
            title: "심박 안정",
            message: "최근 7일 평균 심박이 안정적으로 내려가고 있어요.",
            icon: SOOMIcon.heart,
            tone: .positive
        )
        InsightCard(
            title: "피로 누적",
            message: "러닝 볼륨이 빠르게 늘었습니다. 다음 훈련 전 회복 시간을 확보하세요.",
            icon: SOOMIcon.bolt,
            tone: .warning
        )
    }
    .preferredColorScheme(.light)
}
