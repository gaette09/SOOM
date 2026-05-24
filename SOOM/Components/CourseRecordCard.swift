import SwiftUI

struct CourseRecordCard: View {
    let record: CourseRecord
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                header

                if record.comparisonType == .insufficientData {
                    Text(record.bestMetric.detailText)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    metricRow(record.bestMetric, isPrimary: true)

                    if let previousMetric = record.previousMetric {
                        metricRow(previousMetric, isPrimary: false)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("비슷한 코스 기록")
        .accessibilityValue(accessibilityValue)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Image(systemName: iconName)
                .font(.system(size: SOOMLayout.IconButton.iconSize, weight: .semibold))
                .foregroundStyle(toneTint)
                .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                .background(toneTint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text("비슷한 코스 기록")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(toneTint)

                Text(title)
                    .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let improvement = record.improvementValue {
                    Text(improvement)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(toneTint)
                }
            }
        }
    }

    private func metricRow(_ metric: CourseRecordMetric, isPrimary: Bool) -> some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing) {
                Text(metric.title)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)

                Text(metric.detailText)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

            Text(metric.valueText)
                .font(SOOMFont.displayMedium(isPrimary ? 15 : 13, relativeTo: .subheadline))
                .foregroundStyle(isPrimary ? toneTint : SOOMColor.secondaryInk)
                .lineLimit(1)
        }
        .padding(SOOMLayout.Metrics.actionTextSpacing)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
    }

    private var title: String {
        switch record.comparisonType {
        case .bestPace:
            return "이 코스에서 페이스 흐름이 좋아졌어요"
        case .bestSpeed:
            return "이 코스에서 속도 흐름이 좋아졌어요"
        case .longestDistance:
            return "비슷한 흐름에서 거리가 조금 길어졌어요"
        case .fastestCompletion:
            return "비슷한 흐름을 조금 더 빠르게 마무리했어요"
        case .stableRhythm, .recentImprovement:
            return "비슷한 코스 흐름을 다시 확인했어요"
        case .insufficientData:
            return "비슷한 기록이 더 쌓이면 비교해볼게요"
        }
    }

    private var toneTint: Color {
        switch record.comparisonType {
        case .bestPace, .bestSpeed, .longestDistance, .fastestCompletion:
            return tint
        case .stableRhythm, .recentImprovement:
            return SOOMColor.secondaryInk
        case .insufficientData:
            return SOOMColor.tertiaryInk
        }
    }

    private var iconName: String {
        switch record.comparisonType {
        case .bestPace, .bestSpeed, .fastestCompletion:
            return SOOMIcon.trendUp
        case .longestDistance:
            return SOOMIcon.map
        case .stableRhythm, .recentImprovement:
            return SOOMIcon.trendFlat
        case .insufficientData:
            return SOOMIcon.checkCircle
        }
    }

    private var accessibilityValue: String {
        [
            title,
            record.improvementValue,
            record.bestMetric.valueText,
            record.bestMetric.detailText,
            record.previousMetric?.valueText,
            record.previousMetric?.detailText
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }
}

#Preview("CourseRecordCard") {
    let current = WorkoutGrowthInput(
        id: UUID(),
        source: .soomLocal,
        workoutType: .cycling,
        startDate: Date(),
        durationMinutes: 68,
        distanceKm: 31,
        averagePaceText: nil,
        averageSpeedKmh: 27.3,
        averageHeartRate: nil,
        elevationGainMeters: 260,
        activeEnergyKcal: nil
    )
    let baseline = WorkoutGrowthInput(
        id: UUID(),
        source: .soomLocal,
        workoutType: .cycling,
        startDate: Date().addingTimeInterval(-604_800),
        durationMinutes: 70,
        distanceKm: 31,
        averagePaceText: nil,
        averageSpeedKmh: 25.8,
        averageHeartRate: nil,
        elevationGainMeters: 250,
        activeEnergyKcal: nil
    )

    SOOMScreen {
        CourseRecordCard(
            record: CourseRecordBuilder().build(current: current, candidateWorkouts: [baseline]),
            tint: SOOMColor.bike
        )
    }
}
