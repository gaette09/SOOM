import SwiftUI

struct MorningCheckInPromptCard: View {
    let onRecord: () -> Void
    let onLater: (() -> Void)?

    init(
        onRecord: @escaping () -> Void,
        onLater: (() -> Void)? = nil
    ) {
        self.onRecord = onRecord
        self.onLater = onLater
    }

    var body: some View {
        SOOMCard {
            HStack(alignment: .center, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: SOOMIcon.recovery)
                    .font(.system(size: SOOMLayout.RecoveryAI.promptIconSize, weight: .semibold))
                    .foregroundStyle(SOOMColor.recovery)
                    .frame(width: SOOMLayout.RecoveryAI.promptIconFrame, height: SOOMLayout.RecoveryAI.promptIconFrame)
                    .background(SOOMColor.recovery.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                    Text("오늘 몸 상태를 가볍게 확인해볼까요?")
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("기록하면 오늘 코칭을 조금 더 맞춰볼게요.")
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
            }

            HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                Spacer(minLength: 0)

                if let onLater {
                    Button(action: onLater) {
                        Text("나중에")
                            .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .padding(.horizontal, SOOMLayout.RecoveryAI.promptButtonHorizontalPadding)
                            .padding(.vertical, SOOMLayout.RecoveryAI.promptButtonVerticalPadding)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("나중에 기록하기")
                    .accessibilityHint("오늘 컨디션 기록 안내를 닫습니다.")
                }

                Button(action: onRecord) {
                    Text("기록하기")
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.recovery)
                        .padding(.horizontal, SOOMLayout.RecoveryAI.promptButtonHorizontalPadding)
                        .padding(.vertical, SOOMLayout.RecoveryAI.promptButtonVerticalPadding)
                        .background(SOOMColor.recovery.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.RecoveryAI.ctaCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("오늘 컨디션 기록하기")
                .accessibilityHint("피로감, 수면감, 근육통, 기분을 기록하는 화면으로 이동합니다.")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("MorningCheckInPromptCard") {
    SOOMScreen {
        MorningCheckInPromptCard(onRecord: {})
    }
    .preferredColorScheme(.light)
}
