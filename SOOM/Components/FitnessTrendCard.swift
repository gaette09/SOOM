import SwiftUI

/// PDF's Fitness Increased card (feed-detail-migration-plan.md batch 9): "Points +3" /
/// "Fitness Score 35" label/value pairs plus an unlabeled mini sparkline. The PDF's
/// "View your Fitness trend" link is omitted — its destination (an aggregate fitness-trend
/// screen) doesn't exist yet and isn't in scope for this batch (same "View X" deferral
/// convention as the rest of this migration).
struct FitnessTrendCard: View {
    let trend: FitnessTrend
    let tint: Color

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("체력 향상")

            HStack(alignment: .center) {
                HStack(spacing: 20) {
                    valuePair(label: "포인트", value: pointsDeltaText)
                    valuePair(label: "체력 점수", value: "\(trend.score)")
                }

                Spacer()

                MiniSparkline(values: trend.sparkline, tint: tint)
                    .frame(width: 64, height: SOOMLayout.RecoveryAI.trendLineHeight)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("체력 향상")
        .accessibilityValue("체력 점수 \(trend.score), \(pointsAccessibilityText)")
    }

    private func valuePair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
            Text(label)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
            Text(value)
                .font(SOOMFont.displayMedium(20, relativeTo: .title3))
                .foregroundStyle(SOOMColor.ink)
        }
    }

    private var pointsDeltaText: String {
        trend.pointsDelta >= 0 ? "+\(trend.pointsDelta)" : "\(trend.pointsDelta)"
    }

    private var pointsAccessibilityText: String {
        if trend.pointsDelta > 0 {
            return "어제보다 \(trend.pointsDelta) 상승"
        } else if trend.pointsDelta < 0 {
            return "어제보다 \(-trend.pointsDelta) 하락"
        } else {
            return "어제와 동일"
        }
    }
}

private struct MiniSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let normalized = normalize(values)
            Path { path in
                for index in normalized.indices {
                    let point = CGPoint(
                        x: proxy.size.width * CGFloat(index) / CGFloat(max(normalized.count - 1, 1)),
                        y: proxy.size.height * (1 - CGFloat(normalized[index]))
                    )

                    if index == normalized.startIndex {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: SOOMLayout.RecoveryAI.trendLineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalize(_ values: [Double]) -> [Double] {
        guard let minValue = values.min(), let maxValue = values.max(), minValue != maxValue else {
            return values.map { _ in 0.5 }
        }

        return values.map { ($0 - minValue) / (maxValue - minValue) }
    }
}

#Preview("FitnessTrendCard") {
    VStack(spacing: 16) {
        FitnessTrendCard(
            trend: FitnessTrend(score: 35, pointsDelta: 3, sparkline: [18, 20, 22, 24, 23, 26, 28, 30, 29, 32, 33, 34, 34, 35]),
            tint: SOOMColor.accent
        )
        FitnessTrendCard(
            trend: FitnessTrend(score: 22, pointsDelta: -2, sparkline: [30, 29, 28, 27, 26, 25, 25, 24, 24, 23, 23, 22, 22, 22]),
            tint: SOOMColor.accent
        )
    }
    .padding(SOOMLayout.screenPadding)
    .background(SOOMColor.background)
}
