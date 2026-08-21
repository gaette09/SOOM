import SwiftUI

/// PDF's achievement banner (block 5) — same content as the map markers, shown as
/// a card below the map. feed-detail-migration-plan.md batch 7.
struct WorkoutAchievementCard: View {
    let achievement: WorkoutAchievement
    let tint: Color

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: SOOMIcon.medal)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text(achievement.pinLabel)
                        .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)

                    Text(achievement.bannerComparisonText)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(achievement.bannerMotivationText)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(achievement.pinLabel)
        .accessibilityValue("\(achievement.bannerComparisonText) \(achievement.bannerMotivationText)")
    }
}

#Preview("WorkoutAchievementCard") {
    VStack(spacing: 16) {
        WorkoutAchievementCard(
            achievement: WorkoutAchievement(
                durationMinutes: 5,
                rank: 1,
                coordinate: WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0),
                valueText: "4:32/km",
                isPaceBased: true
            ),
            tint: SOOMColor.run
        )
        WorkoutAchievementCard(
            achievement: WorkoutAchievement(
                durationMinutes: 10,
                rank: 2,
                coordinate: WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0),
                valueText: "28.4 km/h",
                isPaceBased: false
            ),
            tint: SOOMColor.bike
        )
    }
    .padding(SOOMLayout.screenPadding)
    .background(SOOMColor.background)
}
