import SwiftUI

enum TrendDirection {
    case up
    case down
    case flat

    var icon: String {
        switch self {
        case .up:
            return SOOMIcon.trendUp
        case .down:
            return SOOMIcon.trendDown
        case .flat:
            return SOOMIcon.trendFlat
        }
    }

    var tint: Color {
        switch self {
        case .up:
            return SOOMColor.warning
        case .down:
            return SOOMColor.recovery
        case .flat:
            return SOOMColor.secondaryInk
        }
    }
}

struct TrendCard: View {
    let title: String
    let currentValue: String
    let unit: String
    let changeText: String
    let trendDirection: TrendDirection
    let values: [Double]

    init(
        title: String,
        currentValue: String,
        unit: String,
        changeText: String,
        trendDirection: TrendDirection,
        values: [Double] = [0.28, 0.34, 0.32, 0.46, 0.44, 0.52]
    ) {
        self.title = title
        self.currentValue = currentValue
        self.unit = unit
        self.changeText = changeText
        self.trendDirection = trendDirection
        self.values = values
    }

    var body: some View {
        SOOMCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text(title)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)

                    HStack(alignment: .firstTextBaseline, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                        Text(currentValue)
                            .font(SOOMFont.displayMedium(22, relativeTo: .title3))
                            .foregroundStyle(SOOMColor.ink)
                        Text(unit)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }
                }

                Spacer()

                Label(changeText, systemImage: trendDirection.icon)
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(trendDirection.tint)
            }

            MiniTrendLine(values: values, tint: trendDirection.tint)
                .frame(height: SOOMLayout.RecoveryAI.trendLineHeight)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(currentValue) \(unit), \(changeText)")
    }
}

private struct MiniTrendLine: View {
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

#Preview("TrendCard") {
    SOOMScreen {
        TrendCard(title: "휴식기 심박", currentValue: "48", unit: "bpm", changeText: "3 낮아짐", trendDirection: .down)
        TrendCard(title: "운동 부하", currentValue: "642", unit: "TL", changeText: "12% 증가", trendDirection: .up)
    }
    .preferredColorScheme(.light)
}
