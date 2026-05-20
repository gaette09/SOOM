import SwiftUI

struct WorkoutGrowthCard: View {
    let summary: WorkoutGrowthSummary
    let tint: Color

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: summary.improvementType.icon)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text("오늘 운동에서 좋아진 점")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(tint)

                    Text(summary.title)
                        .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary.shortSummary)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary.comparisonText)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)

                    Text(summary.motivationText)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if let insight = summary.insight {
                        Label(insight, systemImage: SOOMIcon.sparkles)
                            .font(SOOMFont.body(12, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("오늘 운동에서 좋아진 점")
        .accessibilityValue("\(summary.title). \(summary.shortSummary). \(summary.motivationText)")
    }
}

#Preview("WorkoutGrowthCard") {
    let workouts = MockWorkoutHarness().loadWorkouts()
    let workout = workouts[0]
    let summary = WorkoutGrowthSummaryBuilder().build(current: workout, recentWorkouts: workouts)

    SOOMScreen {
        WorkoutGrowthCard(summary: summary, tint: workout.sport.tint)
    }
    .preferredColorScheme(.light)
}
