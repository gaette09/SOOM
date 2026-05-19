import SwiftUI

struct WeeklyCoachSummaryCard: View {
    let summary: WeeklyRecoverySummary

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                header
                scoreRow

                Text(summary.shortSummary)
                    .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary.coachInsight)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .overlay(SOOMColor.line)

                HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                    Image(systemName: SOOMIcon.sparkles)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SOOMColor.orange)
                        .accessibilityHidden(true)

                    Text(summary.recommendation)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("이번 주 회복 흐름")
        .accessibilityValue(accessibilityValue)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Image(systemName: summary.trendDirection.icon)
                .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .bold))
                .foregroundStyle(trendTint)
                .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                .background(trendTint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                Text(Self.weekFormatter.string(from: summary.weekStartDate))
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)

                Text(summary.trendDirection.label)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(trendTint)
            }
        }
    }

    private var scoreRow: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                Text("평균 회복 점수")
                    .font(SOOMFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)

                Text("\(summary.averageScore)")
                    .font(SOOMFont.display(30, relativeTo: .title))
                    .foregroundStyle(SOOMColor.ink)
            }

            Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

            VStack(alignment: .trailing, spacing: SOOMLayout.SectionHeader.spacing) {
                Text("최고 \(summary.bestDayScore)")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.recovery)

                Text("최저 \(summary.lowestDayScore)")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
        }
    }

    private var trendTint: Color {
        switch summary.trendDirection {
        case .improving:
            return SOOMColor.recovery
        case .declining:
            return SOOMColor.warning
        case .stable:
            return SOOMColor.secondaryInk
        }
    }

    private var accessibilityValue: String {
        [
            "평균 회복 점수 \(summary.averageScore)",
            summary.trendDirection.label,
            summary.shortSummary,
            summary.coachInsight,
            summary.recommendation
        ].joined(separator: ", ")
    }

    private static let weekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 주간"
        return formatter
    }()
}

#Preview("WeeklyCoachSummaryCard") {
    SOOMScreen {
        WeeklyCoachSummaryCard(summary: .mockStable)
    }
    .preferredColorScheme(.light)
}
