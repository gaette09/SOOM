import Charts
import SwiftUI

/// Shared shell for PDF's distance-axis area charts (Power/HR/Speed/Cadence/Elevation,
/// feed-detail-migration-plan.md batch 3). Renders a real chart when `samples` is
/// non-empty, otherwise `placeholderMessage` — callers decide which by checking the
/// relevant `ProcessedWorkout.metricAvailability` series case before constructing this.
/// Colors follow SOOM's one-tint-per-workout convention (not PDF's per-metric colors)
/// to match every other card on this screen and avoid reintroducing the accent-color
/// sprawl the SOOM-OS design audit flagged.
struct WorkoutDistanceChartCard: View {
    let title: String
    let unitLabel: String
    let samples: [WorkoutDistanceChartSample]
    let tint: Color
    var showsInfoIcon: Bool = true
    var placeholderMessage: String?
    /// PDF's stat rows below the chart (e.g. Avg/Max). Only rendered when the
    /// chart itself has real data — an empty list is normal for sections with
    /// no comparable per-workout stat (batch 5 skips Power/Cadence entirely,
    /// since SOOM has no data source for either, not even to compute a max).
    var stats: [ActivityDetailMetric] = []

    var body: some View {
        SOOMCard {
            HStack(spacing: SOOMLayout.Metrics.rowTextSpacing) {
                Text(title)
                    .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)

                if showsInfoIcon {
                    Image(systemName: "info.circle")
                        .font(.system(size: SOOMFont.Size.caption, weight: .medium))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .accessibilityHidden(true)
                }

                Spacer()
            }

            if let placeholderMessage {
                Text(placeholderMessage)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            } else {
                Chart(samples) { sample in
                    AreaMark(
                        x: .value("거리", sample.distanceKilometers),
                        y: .value(title, sample.value)
                    )
                    .foregroundStyle(tint.opacity(0.24))

                    LineMark(
                        x: .value("거리", sample.distanceKilometers),
                        y: .value(title, sample.value)
                    )
                    .foregroundStyle(tint)
                    .interpolationMethod(.monotone)
                }
                .frame(height: 140)
                .chartXAxisLabel("거리 (km)")
                .chartYAxisLabel(unitLabel)

                if !stats.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(stats) { stat in
                            if stat.id != stats.first?.id {
                                Divider()
                            }
                            HStack {
                                Text(stat.label)
                                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                                    .foregroundStyle(SOOMColor.secondaryInk)
                                Spacer()
                                Text(stat.value)
                                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                                    .foregroundStyle(SOOMColor.ink)
                            }
                            .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing)
                        }
                    }
                    .padding(.top, SOOMLayout.Metrics.actionTextSpacing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityValueText: String {
        if let placeholderMessage { return placeholderMessage }
        let statsText = stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ")
        return statsText.isEmpty ? "\(samples.count)개 구간 데이터" : statsText
    }
}
