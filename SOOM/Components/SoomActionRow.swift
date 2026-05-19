import SwiftUI

struct SOOMActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: SOOMLayout.Metrics.actionRowSpacing) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text(title)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)
                Text(subtitle)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }

            Spacer()
            Image(systemName: SOOMIcon.chevronRight)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SOOMColor.tertiaryInk)
        }
    }
}

#Preview("SOOMActionRow") {
    SOOMScreen {
        SOOMCard {
            SOOMSectionHeader("Action Row")
            SOOMActionRow(icon: SOOMIcon.run, title: "유산소 러닝", subtitle: "10.4 km · 52분 · 평균 151bpm", tint: SOOMColor.run)
            SOOMActionRow(icon: SOOMIcon.bike, title: "템포 인터벌", subtitle: "46.2 km · 1시간 30분", tint: SOOMColor.bike)
        }
    }
    .preferredColorScheme(.light)
}
