import SwiftUI

struct WorkoutRecoveryImpactCard: View {
    let impact: WorkoutRecoveryImpact
    let tint: Color

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                Image(systemName: impact.icon ?? impact.impactLevel.icon)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(subtleTint)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(subtleTint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text("회복 흐름에 미치는 영향")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(subtleTint)

                    Text(impact.title)
                        .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(impact.shortMessage)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(impact.recommendation, systemImage: SOOMIcon.sparkles)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("회복 흐름에 미치는 영향")
        .accessibilityValue("\(impact.title). \(impact.shortMessage). \(impact.recommendation)")
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
