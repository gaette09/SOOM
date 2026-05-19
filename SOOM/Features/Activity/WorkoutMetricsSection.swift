import SwiftUI

struct WorkoutMetricsSection: View {
    let workout: Workout
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("운동 요약", caption: "\(workout.source)에서 가져온 더미 운동 데이터입니다.")
            LazyVGrid(columns: columns, spacing: SOOMLayout.Metrics.gridSpacing) {
                SOOMMetricPill("거리", workout.formattedDistance, tint: workout.sport.tint)
                SOOMMetricPill("시간", workout.formattedDuration, tint: SOOMColor.ink)
                SOOMMetricPill("평균 페이스", workout.formattedPace, tint: workout.sport.tint)
                SOOMMetricPill("활동 칼로리", "\(workout.activeCalories) kcal", tint: SOOMColor.warning)
                SOOMMetricPill("평균 심박", "\(workout.avgHeartRate)bpm", tint: SOOMColor.run)
                SOOMMetricPill("최대 심박", "\(workout.maxHeartRate)bpm", tint: SOOMColor.run)
                SOOMMetricPill("평균 파워", workout.avgPower.map { "\($0)w" } ?? "-", tint: SOOMColor.bike)
                SOOMMetricPill("상승 고도", "\(workout.elevationGain)m", tint: SOOMColor.swim)
                SOOMMetricPill("케이던스", workout.cadence.map { "\($0)" } ?? "-", tint: SOOMColor.ink)
                SOOMMetricPill("체감 강도", "\(workout.effort)/10", tint: SOOMColor.warning)
            }

            if !workout.achievements.isEmpty {
                Divider()
                ForEach(workout.achievements, id: \.self) { achievement in
                    Label(achievement, systemImage: SOOMIcon.medal)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.warning)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("운동 요약")
        .accessibilityValue("\(workout.formattedDistance), \(workout.formattedDuration), 평균 심박 \(workout.avgHeartRate)bpm")
    }
}
