import SwiftUI

struct WorkoutGrowthMetricsCard: View {
    let metrics: [WorkoutGrowthMetric]
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                SOOMSectionHeader("오늘 성장 데이터")

                ForEach(metrics) { metric in
                    metricRow(metric)

                    if metric.id != metrics.last?.id {
                        Divider()
                            .overlay(SOOMColor.line.opacity(0.7))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("오늘 성장 데이터")
        .accessibilityValue(metrics.map { "\($0.title) \($0.valueText). \($0.comparisonText)" }.joined(separator: ". "))
    }

    private func metricRow(_ metric: WorkoutGrowthMetric) -> some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Image(systemName: metric.trend.icon)
                .font(.system(size: SOOMLayout.IconButton.iconSize, weight: .semibold))
                .foregroundStyle(metric.trend.color(tint: tint))
                .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                .background(metric.trend.color(tint: tint).opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)

                    Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

                    Text(metric.valueText)
                        .font(SOOMFont.displayMedium(16, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                }

                Text(metric.comparisonText)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension WorkoutGrowthMetricTrend {
    var icon: String {
        switch self {
        case .improved:
            return SOOMIcon.trendUp
        case .steady:
            return SOOMIcon.trendFlat
        case .lighter:
            return SOOMIcon.trendDown
        case .insufficientData:
            return SOOMIcon.checkCircle
        }
    }

    func color(tint: Color) -> Color {
        switch self {
        case .improved:
            return tint
        case .steady:
            return SOOMColor.secondaryInk
        case .lighter:
            return SOOMColor.orange
        case .insufficientData:
            return SOOMColor.tertiaryInk
        }
    }
}

#Preview("WorkoutGrowthMetricsCard") {
    let workouts = MockWorkoutHarness().loadWorkouts()
    let workout = workouts[0]
    let input = WorkoutGrowthInput(previewWorkout: workout)
    let recent = workouts.map(WorkoutGrowthInput.init(previewWorkout:))
    let metrics = WorkoutGrowthMetricsBuilder().build(current: input, recent: recent)

    SOOMScreen {
        WorkoutGrowthMetricsCard(metrics: metrics, tint: workout.sport.tint)
    }
}

private extension WorkoutGrowthInput {
    init(previewWorkout workout: Workout) {
        self.init(
            id: workout.id,
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(previewSport: workout.sport),
            startDate: workout.date,
            durationMinutes: Int(workout.duration / 60),
            distanceKm: workout.distanceMeters > 0 ? workout.distanceMeters / 1_000 : nil,
            averagePaceText: workout.sport == .run ? workout.formattedPace : nil,
            averageSpeedKmh: workout.duration > 0 ? (workout.distanceMeters / 1_000) / (workout.duration / 3_600) : nil,
            averageHeartRate: Double(workout.avgHeartRate),
            elevationGainMeters: Double(workout.elevationGain),
            activeEnergyKcal: Double(workout.activeCalories)
        )
    }
}

private extension UnifiedWorkoutType {
    init(previewSport sport: WorkoutSport) {
        switch sport {
        case .swim:
            self = .swimming
        case .bike, .brick:
            self = .cycling
        case .run:
            self = .running
        }
    }
}
