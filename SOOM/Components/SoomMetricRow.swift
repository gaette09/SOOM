import SwiftUI

struct SOOMMetricRow: View {
    let leading: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: SOOMLayout.Metrics.rowSpacing) {
            Text(leading)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(tint)
                .frame(width: SOOMLayout.Metrics.rowLeadingWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing) {
                Text(title)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)
                Text(subtitle)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("SOOMMetricRow") {
    SOOMScreen {
        SOOMCard {
            SOOMSectionHeader("Metric Row")
            SOOMMetricRow(leading: "1 km", title: "1.0 km · 5:02", subtitle: "5:02/km · 145bpm", tint: SOOMColor.run)
            SOOMMetricRow(leading: "2 km", title: "1.0 km · 4:58", subtitle: "4:58/km · 151bpm", tint: SOOMColor.run)
        }
    }
    .preferredColorScheme(.light)
}
