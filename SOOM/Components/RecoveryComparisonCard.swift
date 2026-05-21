import SwiftUI

struct RecoveryComparisonCard: View {
    let comparison: RecoveryComparisonSummary

    var body: some View {
        SOOMCard {
            SOOMSectionHeader(
                "공식 Recovery와 비교",
                caption: "미리보기 결과를 기본 점수와 분리해서 확인합니다."
            )

            HStack(alignment: .center, spacing: SOOMLayout.RecoveryAI.scoreHeaderSpacing) {
                scoreColumn(
                    title: "공식 Recovery",
                    score: comparison.officialScore,
                    tint: SOOMColor.recovery,
                    emphasized: true
                )

                Divider()
                    .overlay(SOOMColor.line)

                scoreColumn(
                    title: "미리보기",
                    score: comparison.previewScore,
                    tint: SOOMColor.secondaryInk,
                    emphasized: false
                )
            }

            Label("차이 \(comparison.difference)점", systemImage: SOOMIcon.trendFlat)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(levelTint)
                .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
                .padding(.vertical, SOOMLayout.SectionHeader.spacing + 2)
                .background(levelTint.opacity(0.10))
                .clipShape(Capsule())
                .accessibilityLabel("점수 차이")
                .accessibilityValue("\(comparison.difference)점")

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                comparisonBlock(
                    title: "차이가 나는 이유",
                    message: comparison.comparisonMessage,
                    icon: SOOMIcon.chartLine,
                    tint: levelTint
                )

                comparisonBlock(
                    title: "확인해볼 것",
                    message: comparison.recommendation,
                    icon: SOOMIcon.checkCircle,
                    tint: SOOMColor.recovery
                )

                comparisonBlock(
                    title: "참고",
                    message: comparison.confidenceNote,
                    icon: SOOMIcon.sync,
                    tint: SOOMColor.secondaryInk
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("공식 Recovery와 검증용 미리보기 비교")
        .accessibilityValue("공식 점수 \(comparison.officialScore), 미리보기 점수 \(comparison.previewScore), 차이 \(comparison.difference)점. \(comparison.comparisonMessage)")
    }

    private var levelTint: Color {
        switch comparison.differenceLevel {
        case .similar:
            return SOOMColor.recovery
        case .moderate:
            return SOOMColor.warning
        case .large:
            return SOOMColor.run
        }
    }

    private func scoreColumn(title: String, score: Int, tint: Color, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Text(title)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.tertiaryInk)

            Text("\(score)")
                .font(SOOMFont.display(emphasized ? 34 : 28, relativeTo: emphasized ? .title : .title2))
                .foregroundStyle(emphasized ? SOOMColor.ink : SOOMColor.secondaryInk)

            Text(emphasized ? "기준 점수" : "검증용")
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonBlock(title: String, message: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionRowSpacing) {
            Image(systemName: icon)
                .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text(title)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)

                Text(message)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("RecoveryComparisonCard") {
    SOOMScreen {
        RecoveryComparisonCard(
            comparison: RecoveryComparisonSummary(
                officialScore: 82,
                previewScore: 74,
                difference: 8,
                differenceLevel: .moderate,
                comparisonMessage: "가져온 운동 기록 기준으로는 회복 부하가 조금 더 높게 계산됐어요.",
                recommendation: "가져온 운동 기록과 분석 제외 설정을 한 번 확인해보세요.",
                confidenceNote: "분석 제외된 운동, 중복 기록 여부, 가져온 데이터 범위에 따라 차이가 날 수 있어요."
            )
        )
    }
    .preferredColorScheme(.light)
}
