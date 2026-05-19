import Charts
import SwiftUI

struct WorkoutChartStack: View {
    let workout: Workout

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("그래프", caption: "페이스, 심박, 파워 흐름")

            heartRateChart
            paceChart

            if workout.samples.contains(where: { $0.power != nil }) {
                powerChart
            }
        }
    }

    private var heartRateChart: some View {
        Chart(workout.samples) { sample in
            LineMark(x: .value("분", sample.minute), y: .value("심박", sample.heartRate))
                .foregroundStyle(SOOMColor.run)
                .interpolationMethod(.catmullRom)
        }
        .chartYAxisLabel("bpm")
        .frame(height: 150)
        .accessibilityLabel("심박 그래프")
        .accessibilityValue("평균 \(workout.avgHeartRate)bpm, 최대 \(workout.maxHeartRate)bpm")
    }

    private var paceChart: some View {
        Chart(workout.samples) { sample in
            LineMark(x: .value("분", sample.minute), y: .value("페이스", sample.paceSeconds))
                .foregroundStyle(workout.sport.tint)
                .interpolationMethod(.catmullRom)
        }
        .chartYAxisLabel(workout.sport == .bike ? "속도 지표" : "sec")
        .frame(height: 150)
        .accessibilityLabel(workout.sport == .bike ? "속도 흐름 그래프" : "페이스 흐름 그래프")
        .accessibilityValue("평균 페이스 \(workout.formattedPace)")
    }

    private var powerChart: some View {
        Chart(workout.samples) { sample in
            if let power = sample.power {
                LineMark(x: .value("분", sample.minute), y: .value("파워", power))
                    .foregroundStyle(SOOMColor.bike)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxisLabel("w")
        .frame(height: 150)
        .accessibilityLabel("파워 그래프")
        .accessibilityValue(workout.avgPower.map { "평균 \($0)w" } ?? "파워 데이터 없음")
    }
}

struct WorkoutSplitsCard: View {
    let workout: Workout

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("스플릿")
            ForEach(workout.splits) { split in
                SOOMMetricRow(
                    leading: split.label,
                    title: "\(split.distance) · \(split.time)",
                    subtitle: "\(split.pace) · \(split.heartRate)bpm" + (split.power.map { " · \($0)w" } ?? ""),
                    tint: workout.sport.tint
                )
                Divider()
            }
        }
        .accessibilityLabel("스플릿")
    }
}

struct WorkoutZonesCard: View {
    let workout: Workout

    var totalMinutes: Double {
        Double(max(workout.zones.map(\.minutes).reduce(0, +), 1))
    }

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("심박 존")
            ForEach(workout.zones) { zone in
                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing + 3) {
                    HStack {
                        Text(zone.name)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.ink)
                        Spacer()
                        Text("\(zone.minutes)분")
                            .font(SOOMFont.body(12, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }
                    ProgressView(value: Double(zone.minutes) / totalMinutes)
                        .tint(zone.tint)
                        .accessibilityLabel(zone.name)
                        .accessibilityValue("\(zone.minutes)분")
                }
            }
        }
        .accessibilityLabel("심박 존")
    }
}
