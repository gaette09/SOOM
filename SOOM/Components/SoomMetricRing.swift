import SwiftUI

struct SOOMMetricRing: View {
    let score: Int
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: SOOMLayout.Metrics.scoreRingSpacing) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: SOOMLayout.Metrics.scoreRingLineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: SOOMLayout.Metrics.scoreRingLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(SOOMFont.display(20, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
            }
            .frame(width: SOOMLayout.Metrics.scoreRingSize, height: SOOMLayout.Metrics.scoreRingSize)

            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
    }
}

typealias ScoreRing = SOOMMetricRing

#Preview("SOOMMetricRing") {
    SOOMScreen {
        SOOMCard {
            SOOMSectionHeader("Metric Ring")
            HStack {
                SOOMMetricRing(score: 82, title: "흐름", tint: SOOMColor.bike)
                Spacer()
                SOOMMetricRing(score: 64, title: "피로", tint: SOOMColor.warning)
                Spacer()
                SOOMMetricRing(score: 42, title: "위험", tint: SOOMColor.run)
            }
        }
    }
    .preferredColorScheme(.light)
}
