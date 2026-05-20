import SwiftUI

struct WorkoutSessionSummaryCard: View {
    let summary: WorkoutSessionSummary
    let tint: Color

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: summary.icon ?? SOOMIcon.sparkles)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text("오늘 운동 요약")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(tint)

                    Text(summary.title)
                        .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary.summaryText)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                        SessionSummaryLine(title: "좋아진 점", text: summary.highlightText, tint: tint)
                        SessionSummaryLine(title: "다음 힌트", text: summary.improvementText, tint: SOOMColor.orange)
                        SessionSummaryLine(title: "회복 연결", text: summary.recoveryText, tint: SOOMColor.recovery)
                    }
                    .padding(.top, SOOMLayout.Metrics.actionTextSpacing)

                    Label(summary.closingMotivation, systemImage: SOOMIcon.sparkles)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, SOOMLayout.Metrics.actionTextSpacing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("오늘 운동 요약")
        .accessibilityValue("\(summary.title). \(summary.summaryText). \(summary.closingMotivation)")
    }
}

private struct SessionSummaryLine: View {
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Text(title)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(tint)
            Text(text)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("WorkoutSessionSummaryCard") {
    let workout = MockWorkoutHarness().loadWorkouts()[0]
    let growth = WorkoutGrowthSummaryBuilder().build(current: workout, recentWorkouts: [workout])
    let weakness = WorkoutWeaknessInsightBuilder().build(current: workout, recentWorkouts: [workout])
    let impact = WorkoutRecoveryImpactBuilder().build(workout: workout)
    let summary = WorkoutSessionSummaryBuilder().build(
        workout: workout,
        growthSummary: growth,
        weaknessInsight: weakness,
        recoveryImpact: impact
    )

    SOOMScreen {
        WorkoutSessionSummaryCard(summary: summary, tint: workout.sport.tint)
    }
    .preferredColorScheme(.light)
}
