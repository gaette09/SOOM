import SwiftUI

struct WorkoutRecoveryImpactCard: View {
    let impact: WorkoutRecoveryImpact
    let tint: Color

    var body: some View {
        WorkoutInsightDisclosure(title: "회복 흐름에 미치는 영향", icon: "heart.text.clipboard", summary: impact.shortMessage) {
            HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(soom: impact.icon ?? impact.impactLevel.icon)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(subtleTint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(subtleTint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text("회복 흐름에 미치는 영향")
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(subtleTint)

                    Text(impact.title)
                        .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(impact.shortMessage)
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(impact.recommendation, soomIcon: SOOMIcon.sparkles)
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

    }

    private var subtleTint: Color {
        switch impact.impactLevel {
        case .high:
            return SOOMColor.orange
        case .recoveryFriendly:
            return SOOMColor.recovery
        case .insufficientData:
            return SOOMColor.secondaryInk
        default:
            return tint
        }
    }
}

#Preview("WorkoutRecoveryImpactCard") {
    let workout = MockWorkoutHarness().loadWorkouts()[0]
    let impact = WorkoutRecoveryImpactBuilder().build(workout: workout)

    SOOMScreen {
        WorkoutRecoveryImpactCard(impact: impact, tint: workout.sport.tint)
    }
    .preferredColorScheme(.light)
}
