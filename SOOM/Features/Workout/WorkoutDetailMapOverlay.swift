import SwiftUI

struct WorkoutDetailMapOverlay: View {
    let workout: Workout
    let route: WorkoutRoute?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WorkoutDetailMapView(route: route, fallbackStyle: fallbackStyle, tint: workout.sport.tint)
                .frame(height: 260)

            metricOverlay
                .padding(SOOMLayout.Card.padding)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("운동 지도와 핵심 지표")
        .accessibilityValue(accessibilityValue)
    }

    private var metricOverlay: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("오늘 운동 흐름")
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: SOOMLayout.Metrics.tagSpacing)], alignment: .leading, spacing: SOOMLayout.Metrics.tagSpacing) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label)
                            .font(SOOMFont.body(11, relativeTo: .caption2))
                            .foregroundStyle(SOOMColor.secondaryInk)
                        Text(metric.value)
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
            }
        }
        .padding(SOOMLayout.Card.padding)
        .frame(maxWidth: 310, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous)
                .stroke(SOOMColor.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: SOOMColor.black.opacity(0.12), radius: 12, y: 6)
    }

    private var metrics: [OverlayMetric] {
        var base = [
            OverlayMetric(label: "거리", value: workout.formattedDistance),
            OverlayMetric(label: "시간", value: workout.formattedDuration)
        ]

        switch workout.sport {
        case .bike, .brick:
            base.append(OverlayMetric(label: "평균 속도", value: averageSpeedText))
            if workout.elevationGain > 0 {
                base.append(OverlayMetric(label: "상승", value: "\(workout.elevationGain)m"))
            }
        case .swim:
            base.append(OverlayMetric(label: "100m 페이스", value: swimPaceText))
        case .run:
            base.append(OverlayMetric(label: "페이스", value: workout.formattedPace))
            if workout.elevationGain > 0 {
                base.append(OverlayMetric(label: "상승", value: "\(workout.elevationGain)m"))
            }
        }

        return Array(base.prefix(4))
    }

    private var fallbackStyle: StaticRouteFallbackStyle {
        switch workout.sport {
        case .run: return .running
        case .bike, .brick: return .cycling
        case .swim: return .swimming
        }
    }

    private var averageSpeedText: String {
        guard workout.duration > 0 else { return "-" }
        let speed = (workout.distanceMeters / 1_000) / (workout.duration / 3_600)
        return String(format: "%.1f km/h", speed)
    }

    private var swimPaceText: String {
        guard workout.distanceMeters > 0 else { return "-" }
        let pace = workout.duration / (workout.distanceMeters / 100)
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return "\(minutes):\(String(format: "%02d", seconds))/100m"
    }

    private var accessibilityValue: String {
        metrics.map { "\($0.label) \($0.value)" }.joined(separator: ", ")
    }
}

private struct OverlayMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}
