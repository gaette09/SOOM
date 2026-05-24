import SwiftUI

struct WorkoutSplitInsightCard: View {
    let insight: WorkoutSplitInsight
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
        .accessibilityLabel("운동 흐름")
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
                Text("운동 흐름")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(toneTint)

                Text(insight.title)
                    .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metricRow(_ row: WorkoutSplitMetricRow) -> some View {
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
        switch insight.trend {
        case .improving:
            return SOOMIcon.trendUp
        case .stable:
            return SOOMIcon.trendFlat
        case .lighter:
            return SOOMIcon.waveform
        case .insufficientData:
            return SOOMIcon.checkCircle
        }
    }

    private var accessibilityValue: String {
        let rows = insight.metricRows.map { "\($0.title) \($0.valueText). \($0.detailText)" }.joined(separator: ". ")
        return [insight.title, insight.summary, rows].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

#Preview("WorkoutSplitInsightCard") {
    let input = WorkoutGrowthInput(
        id: UUID(),
        source: .soomLocal,
        workoutType: .cycling,
        startDate: Date(),
        durationMinutes: 90,
        distanceKm: 42,
        averagePaceText: nil,
        averageSpeedKmh: 28.0,
        averageHeartRate: 138,
        elevationGainMeters: 320,
        activeEnergyKcal: 720
    )

    SOOMScreen {
        WorkoutSplitInsightCard(
            insight: WorkoutSplitInsightBuilder().build(current: input),
            tint: SOOMColor.bike
        )
    }
}
