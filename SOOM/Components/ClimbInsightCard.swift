import SwiftUI

struct ClimbInsightCard: View {
    let insight: ClimbInsight
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                header

                Text(insight.summary)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if !insight.metricRows.isEmpty {
                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing + 6) {
                        ForEach(insight.metricRows) { row in
                            metricRow(row)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("오르막 흐름")
        .accessibilityValue(accessibilityValue)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Image(systemName: iconName)
                .font(.system(size: SOOMLayout.IconButton.iconSize, weight: .semibold))
                .foregroundStyle(toneTint)
                .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                .background(toneTint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text("오르막 흐름")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(toneTint)

                Text(insight.title)
                    .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metricRow(_ row: ClimbInsightMetricRow) -> some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing) {
                Text(row.title)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)

                Text(row.detailText)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

            Text(row.valueText)
                .font(SOOMFont.displayMedium(15, relativeTo: .subheadline))
                .foregroundStyle(toneTint)
                .lineLimit(1)
        }
        .padding(SOOMLayout.Metrics.actionTextSpacing)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
    }

    private var toneTint: Color {
        switch insight.trend {
        case .improving:
            return tint
        case .stable:
            return SOOMColor.secondaryInk
        case .lighter:
            return SOOMColor.orange
        case .insufficientData:
            return SOOMColor.tertiaryInk
        }
    }

    private var iconName: String {
        switch insight.climbType {
        case .strongFinish:
            return SOOMIcon.trendUp
        case .steadyClimb:
            return SOOMIcon.trendFlat
        case .elevationFatigue:
            return SOOMIcon.waveform
        case .rollingTerrain:
            return SOOMIcon.map
        case .insufficientData:
            return SOOMIcon.checkCircle
        }
    }

    private var accessibilityValue: String {
        let rows = insight.metricRows.map { "\($0.title) \($0.valueText). \($0.detailText)" }.joined(separator: ". ")
        return [insight.title, insight.summary, rows].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

#Preview("ClimbInsightCard") {
    let input = WorkoutGrowthInput(
        id: UUID(),
        source: .soomLocal,
        workoutType: .cycling,
        startDate: Date(),
        durationMinutes: 95,
        distanceKm: 38,
        averagePaceText: nil,
        averageSpeedKmh: 24,
        averageHeartRate: 144,
        elevationGainMeters: 420,
        activeEnergyKcal: 760
    )

    SOOMScreen {
        ClimbInsightCard(
            insight: ClimbInsightBuilder().build(current: input),
            tint: SOOMColor.bike
        )
    }
}
