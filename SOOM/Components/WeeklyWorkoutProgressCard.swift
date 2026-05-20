import SwiftUI

struct WeeklyWorkoutProgressCard: View {
    let progress: WeeklyWorkoutProgress
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                    Image(systemName: progress.trendType.icon)
                        .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                        .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                        Text("이번 주 운동 흐름")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(tint)

                        Text(progress.trendType.title)
                            .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink)

                        Text(progress.progressSummary)
                            .font(SOOMFont.body(13, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SOOMLayout.Metrics.gridSpacing), count: 3), spacing: SOOMLayout.Metrics.gridSpacing) {
                    SOOMMetricPill("운동", "\(progress.workoutCount)회", tint: tint)
                    SOOMMetricPill("거리", formattedDistance, tint: SOOMColor.swim)
                    SOOMMetricPill("시간", formattedDuration, tint: SOOMColor.warning)
                }

                Text(progress.averagePaceOrSpeedText)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)

                Text(progress.motivationText)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("이번 주 운동 흐름")
        .accessibilityValue("\(progress.trendType.title). \(progress.progressSummary). 운동 \(progress.workoutCount)회, 총 거리 \(formattedDistance), 총 시간 \(formattedDuration).")
    }

    private var formattedDistance: String {
        String(format: "%.1f km", progress.totalDistanceKm)
    }

    private var formattedDuration: String {
        if progress.totalDurationMinutes >= 60 {
            return "\(progress.totalDurationMinutes / 60)시간 \(progress.totalDurationMinutes % 60)분"
        }
        return "\(progress.totalDurationMinutes)분"
    }
}

#Preview("WeeklyWorkoutProgressCard") {
    let workouts = MockWorkoutHarness().loadWorkouts()
    let progress = WeeklyWorkoutProgressBuilder().build(workouts: workouts)

    SOOMScreen {
        WeeklyWorkoutProgressCard(progress: progress, tint: SOOMColor.bike)
    }
    .preferredColorScheme(.light)
}
