import SwiftUI

struct WorkoutWeaknessCard: View {
    let insight: WorkoutWeaknessInsight
    let tint: Color

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: insight.icon ?? insight.insightType.icon)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(subtleTint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(subtleTint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text("다음에 좋아질 수 있는 점")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(subtleTint)

                    Text(insight.title)
                        .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(insight.shortInsight)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(insight.suggestion, systemImage: SOOMIcon.sparkles)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("다음에 좋아질 수 있는 점")
        .accessibilityValue("\(insight.title). \(insight.shortInsight). \(insight.suggestion)")
    }

    private var subtleTint: Color {
        switch insight.insightType {
        case .none:
            return tint
        default:
            return SOOMColor.orange
        }
    }
}

#Preview("WorkoutWeaknessCard") {
    let workouts = MockWorkoutHarness().loadWorkouts()
    let workout = workouts[0]
    let insight = WorkoutWeaknessInsightBuilder().build(current: workout, recentWorkouts: workouts)

    SOOMScreen {
        WorkoutWeaknessCard(insight: insight, tint: workout.sport.tint)
    }
    .preferredColorScheme(.light)
}
