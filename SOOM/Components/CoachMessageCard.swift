import SwiftUI

struct CoachMessageCard: View {
    let coachName: String
    let message: String
    let subtitle: String?
    let icon: String
    let tint: Color

    init(
        coachName: String,
        message: String,
        subtitle: String? = nil,
        icon: String = SOOMIcon.sparkles,
        tint: Color = SOOMColor.orange
    ) {
        self.coachName = coachName
        self.message = message
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        SOOMCard {
            HStack(alignment: .center, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: icon)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))

                VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                    Text(coachName)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)

                    if let subtitle {
                        Text(subtitle)
                            .font(SOOMFont.body(12, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }
                }
            }

            Text(message)
                .font(SOOMFont.body(18, relativeTo: .title3))
                .foregroundStyle(SOOMColor.ink)
                .lineSpacing(SOOMLayout.RecoveryAI.messageLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coachName) 코칭 메시지")
        .accessibilityValue(message)
    }
}

#Preview("CoachMessageCard") {
    SOOMScreen {
        CoachMessageCard(
            coachName: "SOOM AI 코치",
            message: "이번 주는 강도를 올리기보다 회복을 우선하세요. 몸이 적응하면 주말에 템포 라이딩을 다시 넣어도 좋습니다.",
            subtitle: "회복 우선 주간"
        )
    }
    .preferredColorScheme(.light)
}
