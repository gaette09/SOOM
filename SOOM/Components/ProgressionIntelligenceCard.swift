import SwiftUI

struct ProgressionIntelligenceCard: View {
    let intelligence: ProgressionIntelligence
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                    Image(systemName: intelligence.trend.trendType.icon)
                        .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                        .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                        Text("최근 흐름")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(tint)

                        Text("\(intelligence.period.title) · \(intelligence.trend.trendType.title)")
                            .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink)

                        Text(intelligence.trend.summary)
                            .font(SOOMFont.body(13, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !intelligence.metricRows.isEmpty {
                    VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                        ForEach(intelligence.metricRows) { row in
                            metricRow(row)
                        }
                    }
                }

                Text(intelligence.insightSummary)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("최근 운동 흐름")
        .accessibilityValue("\(intelligence.trend.trendType.title). \(intelligence.trend.summary)")
    }

    private func metricRow(_ row: ProgressionIntelligenceMetricRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)
                Spacer(minLength: SOOMLayout.Metrics.gridSpacing)
                Text(row.valueText)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(tint)
            }

            Text(row.comparisonText)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

#Preview("ProgressionIntelligenceCard") {
    let workouts = MockWorkoutHarness().loadWorkouts()
    let intelligence = ProgressionIntelligenceBuilder().build(workouts: workouts)

    SOOMScreen {
        ProgressionIntelligenceCard(intelligence: intelligence, tint: SOOMColor.bike)
    }
    .preferredColorScheme(.light)
}
