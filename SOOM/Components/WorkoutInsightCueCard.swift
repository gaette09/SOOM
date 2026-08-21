import SwiftUI

/// Shared shell for PDF's "Athlete Intelligence" pattern (icon badge + eyebrow +
/// optional title + short narrative body). Generalized out of TerrainInsightCue and
/// ActivityDetailRhythmCard, which were structurally identical. Eyebrow copy stays
/// per-card Korean text (오늘의 리듬/지형 맥락 etc.) rather than a unified English
/// "Athlete Intelligence" label — see feed-detail-migration-plan.md batch 2.
struct WorkoutInsightCueCard: View {
    let icon: String
    let eyebrow: String
    var title: String?
    let message: String
    let tint: Color
    var messageFont: Font = SOOMFont.body(13, relativeTo: .caption)
    var messageColor: Color = SOOMColor.secondaryInk
    let accessibilityLabel: String
    let accessibilityValue: String

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                HStack(alignment: .center, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Image(systemName: icon)
                        .font(.system(size: SOOMLayout.IconButton.iconSize - 2, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                        .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing) {
                        Text(eyebrow)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(tint)

                        if let title {
                            Text(title)
                                .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                                .foregroundStyle(SOOMColor.ink)
                        }
                    }

                    Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)
                }

                Text(message)
                    .font(messageFont)
                    .foregroundStyle(messageColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }
}
