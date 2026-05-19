import SwiftUI

struct SOOMMetricPill: View {
    let label: String
    let value: String
    let tint: Color

    init(_ label: String, _ value: String, tint: Color) {
        self.label = label
        self.value = value
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.pillSpacing) {
            Text(label)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
            Text(value)
                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
    }
}

#Preview("SOOMMetricPill") {
    SOOMScreen {
        SOOMCard {
            SOOMSectionHeader("Metric Pill")
            SOOMMetricPill("거리", "10.4 km", tint: SOOMColor.run)
            SOOMMetricPill("활동 칼로리", "676 kcal", tint: SOOMColor.warning)
        }
    }
    .preferredColorScheme(.light)
}
