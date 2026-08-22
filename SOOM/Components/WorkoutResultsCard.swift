import SwiftUI

/// PDF's Results card (feed-detail-migration-plan.md batch 12), reduced to just
/// Achievements — Segments has no SOOM equivalent (see plan doc), and Challenges
/// needs a real progress-tracking engine that doesn't exist yet
/// (soom-club-challenge-progress-engine, blocked). `count` is the *total* number
/// of top-3 finishes this workout qualified for, not the (possibly smaller)
/// number of map-pin markers shown elsewhere on the same screen —
/// `WorkoutAchievementBuildResult.totalCount`, not `.markers.count`.
struct WorkoutResultsCard: View {
    let achievementCount: Int
    let tint: Color

    var body: some View {
        SOOMCard {
            HStack(alignment: .firstTextBaseline) {
                Text("성과")
                    .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                Spacer()
                Text("\(achievementCount)")
                    .font(SOOMFont.displayMedium(28, relativeTo: .title))
                    .foregroundStyle(tint)
            }

            Text(captionText)
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("성과")
        .accessibilityValue("\(achievementCount)개, \(captionText)")
    }

    private var captionText: String {
        achievementCount == 1
            ? "이번 운동에서 세운 개인 기록이에요."
            : "이번 운동에서 세운 개인 기록들이에요."
    }
}

#Preview("WorkoutResultsCard") {
    VStack(spacing: 16) {
        WorkoutResultsCard(achievementCount: 1, tint: SOOMColor.accent)
        WorkoutResultsCard(achievementCount: 3, tint: SOOMColor.accent)
    }
    .padding(SOOMLayout.screenPadding)
    .background(SOOMColor.background)
}
