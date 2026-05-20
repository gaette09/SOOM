import SwiftUI

struct WorkoutDetailContent: View {
    let workout: Workout
    let showsHeader: Bool
    var growthSummary: WorkoutGrowthSummary?
    var weaknessInsight: WorkoutWeaknessInsight?

    var body: some View {
        Group {
            if showsHeader {
                DetailHeader(
                    icon: workout.sport.iconName,
                    title: workout.title,
                    subtitle: "\(workout.sport.title) · \(workout.formattedDistance) · \(workout.formattedDuration)",
                    tint: workout.sport.tint
                )
            }

            WorkoutMetricsSection(workout: workout)
            if let growthSummary {
                WorkoutGrowthCard(summary: growthSummary, tint: workout.sport.tint)
            }
            if let weaknessInsight {
                WorkoutWeaknessCard(insight: weaknessInsight, tint: workout.sport.tint)
            }
            WorkoutChartStack(workout: workout)
            WorkoutSplitsCard(workout: workout)
            WorkoutZonesCard(workout: workout)

            SOOMCard {
                SOOMSectionHeader("AI 해석")
                Text(workout.aiSummary)
                    .font(SOOMFont.body(15, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AI 해석")
            .accessibilityValue(workout.aiSummary)

            SOOMCard {
                SOOMSectionHeader("다음 액션")
                Label("회복 상태를 확인하고 다음 세션 강도를 조절하세요.", systemImage: SOOMIcon.checkCircle)
                Label("같은 종목의 최근 4주 추세와 비교하세요.", systemImage: SOOMIcon.trend)
                Label("피드에 공유할 때는 운동 목적을 함께 남기세요.", systemImage: SOOMIcon.feed)
            }
            .font(SOOMFont.body(15, relativeTo: .subheadline))
            .foregroundStyle(SOOMColor.ink)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("다음 액션")
        }
    }
}

struct DetailHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        SOOMCard {
            HStack(spacing: SOOMLayout.Metrics.detailHeaderSpacing) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: SOOMLayout.Metrics.detailIconFrame, height: SOOMLayout.Metrics.detailIconFrame)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(title)
                        .font(SOOMFont.display(22, relativeTo: .title2))
                        .foregroundStyle(SOOMColor.ink)
                    Text(subtitle)
                        .font(SOOMFont.body(15, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}
