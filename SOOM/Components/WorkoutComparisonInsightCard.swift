import SwiftUI

struct WorkoutComparisonInsightCard: View {
    let insight: WorkoutComparisonInsight
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                header

                if insight.metricRows.isEmpty {
                    Text(insight.summary)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(insight.summary)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing + 6) {
                        ForEach(insight.metricRows) { row in
                            metricRow(row)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("이전 비슷한 운동과 비교")
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
                Text("이전 비슷한 운동과 비교")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(toneTint)

                Text(insight.title)
                    .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metricRow(_ row: WorkoutComparisonMetricRow) -> some View {
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
        switch insight.tone {
        case .improved:
            return tint
        case .steady, .insufficientData:
            return SOOMColor.secondaryInk
        case .lighter:
            return SOOMColor.orange
        }
    }

    private var iconName: String {
        switch insight.tone {
        case .improved:
            return SOOMIcon.trendUp
        case .steady:
            return SOOMIcon.trendFlat
        case .lighter:
            return SOOMIcon.trendDown
        case .insufficientData:
            return SOOMIcon.map
        }
    }

    private var accessibilityValue: String {
        let rows = insight.metricRows.map { "\($0.title) \($0.valueText). \($0.detailText)" }.joined(separator: ". ")
        return [insight.title, insight.summary, rows].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

#Preview("WorkoutComparisonInsightCard") {
    let current = WorkoutGrowthInput(
        id: UUID(),
        source: .soomLocal,
        workoutType: .cycling,
        startDate: Date(),
        durationMinutes: 70,
        distanceKm: 32,
        averagePaceText: nil,
        averageSpeedKmh: 27.4,
        averageHeartRate: 136,
        elevationGainMeters: 260,
        activeEnergyKcal: 620
    )
    let baseline = WorkoutGrowthInput(
        id: UUID(),
        source: .soomLocal,
        workoutType: .cycling,
        startDate: Date().addingTimeInterval(-86_400 * 7),
        durationMinutes: 72,
        distanceKm: 30,
        averagePaceText: nil,
        averageSpeedKmh: 25.1,
        averageHeartRate: 140,
        elevationGainMeters: 210,
        activeEnergyKcal: 580
    )
    let insight = WorkoutComparisonInsightBuilder().build(current: current, baseline: baseline)

    SOOMScreen {
        WorkoutComparisonInsightCard(insight: insight, tint: SOOMColor.bike)
    }
}
