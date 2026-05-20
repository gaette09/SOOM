import SwiftUI

struct FourWeekWorkoutTrendCard: View {
    let trend: FourWeekWorkoutTrend
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                    Image(systemName: trend.trendType.icon)
                        .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                        .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                        Text("최근 4주 성장 추세")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(tint)

                        Text(trend.trendType.title)
                            .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink)

                        Text(trend.summaryText)
                            .font(SOOMFont.body(13, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                    ForEach(trend.weeks) { week in
                        weekRow(week)
                    }
                }

                Text(trend.motivationText)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("최근 4주 성장 추세")
        .accessibilityValue("\(trend.trendType.title). \(trend.summaryText)")
    }

    private func weekRow(_ week: WeeklyWorkoutTrendPoint) -> some View {
        HStack(spacing: SOOMLayout.Metrics.gridSpacing) {
            Text(weekLabel(for: week.weekStartDate))
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .frame(width: SOOMLayout.Metrics.rowLeadingWidth, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SOOMColor.line)
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth(in: proxy.size.width, for: week))
                }
            }
            .frame(height: 6)

            Text("\(week.workoutCount)회 · \(formattedDistance(week.totalDistanceKm))")
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .frame(width: SOOMLayout.Metrics.tagMinWidth, alignment: .trailing)
        }
    }

    private func barWidth(in fullWidth: CGFloat, for week: WeeklyWorkoutTrendPoint) -> CGFloat {
        let maxDistance = max(trend.weeks.map(\.totalDistanceKm).max() ?? 0, 1)
        return max(week.totalDistanceKm / maxDistance * fullWidth, week.workoutCount > 0 ? SOOMLayout.Metrics.tagSpacing : 0)
    }

    private func weekLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M.d"
        return formatter.string(from: date)
    }

    private func formattedDistance(_ distance: Double) -> String {
        String(format: "%.1f km", distance)
    }
}

#Preview("FourWeekWorkoutTrendCard") {
    let workouts = MockWorkoutHarness().loadWorkouts()
    let trend = FourWeekWorkoutTrendBuilder().build(workouts: workouts)

    SOOMScreen {
        FourWeekWorkoutTrendCard(trend: trend, tint: SOOMColor.bike)
    }
    .preferredColorScheme(.light)
}
