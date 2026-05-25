import SwiftUI

struct CourseProgressionCard: View {
    let timeline: CourseProgressionTimeline
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                header

                Text(timeline.summary)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if timeline.direction != .insufficientData {
                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing + 6) {
                        ForEach(displayedPoints) { point in
                            timelineRow(point)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("코스 흐름")
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
                Text("코스 흐름")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(toneTint)

                Text(title)
                    .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func timelineRow(_ point: CourseProgressionPoint) -> some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing) {
                Text(dateText(point.recordedAt))
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)

                Text(trendText(point.trend))
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

            Text(metricText(point))
                .font(SOOMFont.displayMedium(14, relativeTo: .subheadline))
                .foregroundStyle(point.trend == .improved ? toneTint : SOOMColor.secondaryInk)
                .lineLimit(1)
        }
        .padding(SOOMLayout.Metrics.actionTextSpacing)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
    }

    private var displayedPoints: [CourseProgressionPoint] {
        Array(timeline.points.sorted { $0.recordedAt > $1.recordedAt }.prefix(5))
    }

    private var title: String {
        switch timeline.direction {
        case .improving:
            return "이 코스에서 흐름이 조금씩 좋아지고 있어요"
        case .stable:
            return "이 코스의 리듬을 안정적으로 이어가고 있어요"
        case .fluctuating:
            return "최근 코스 흐름을 차분히 비교해볼 수 있어요"
        case .insufficientData:
            return "비슷한 기록이 더 쌓이면 흐름을 보여줄게요"
        }
    }

    private var toneTint: Color {
        switch timeline.direction {
        case .improving:
            return tint
        case .stable:
            return SOOMColor.secondaryInk
        case .fluctuating:
            return SOOMColor.orange
        case .insufficientData:
            return SOOMColor.tertiaryInk
        }
    }

    private var iconName: String {
        switch timeline.direction {
        case .improving:
            return SOOMIcon.trendUp
        case .stable:
            return SOOMIcon.trendFlat
        case .fluctuating:
            return SOOMIcon.trend
        case .insufficientData:
            return SOOMIcon.map
        }
    }

    private func metricText(_ point: CourseProgressionPoint) -> String {
        switch point.comparisonMetric {
        case .pace:
            return paceText(point.metricValue)
        case .averageSpeed:
            return "\(String(format: "%.1f", point.metricValue)) km/h"
        case .completionTime:
            return "\(Int(point.metricValue.rounded()))분"
        case .distance:
            return "\(String(format: "%.1f", point.metricValue)) km"
        case .stableRhythm:
            return "\(String(format: "%.1f", point.metricValue))"
        }
    }

    private func trendText(_ trend: CourseProgressionPointTrend?) -> String {
        switch trend {
        case .improved:
            return "이전 기록보다 리듬이 가벼웠어요."
        case .stable:
            return "이전과 비슷한 흐름을 유지했어요."
        case .lighter:
            return "오늘은 기록보다 코스 리듬을 확인했어요."
        case nil:
            return "비교 기준이 되는 기록이에요."
        }
    }

    private func paceText(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private func dateText(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private var accessibilityValue: String {
        let rows = displayedPoints.map { "\(dateText($0.recordedAt)) \(metricText($0)). \(trendText($0.trend))" }
            .joined(separator: ". ")
        return [title, timeline.summary, rows].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()
}

#Preview("CourseProgressionCard") {
    let now = Date()
    let points: [CourseProgressionPoint] = [
        CourseProgressionPoint(
            workoutId: UUID(),
            recordedAt: now,
            comparisonMetric: .averageSpeed,
            metricValue: 28.0,
            trend: .improved,
            routeSimilarityScore: nil
        ),
        CourseProgressionPoint(
            workoutId: UUID(),
            recordedAt: now.addingTimeInterval(-604_800),
            comparisonMetric: .averageSpeed,
            metricValue: 27.1,
            trend: .improved,
            routeSimilarityScore: 0.86
        ),
        CourseProgressionPoint(
            workoutId: UUID(),
            recordedAt: now.addingTimeInterval(-1_209_600),
            comparisonMetric: .averageSpeed,
            metricValue: 26.2,
            trend: .stable,
            routeSimilarityScore: 0.84
        )
    ]

    SOOMScreen {
        CourseProgressionCard(
            timeline: CourseProgressionTimeline(
                courseId: "preview",
                points: points,
                summary: "비슷한 코스에서 시간이 지나며 리듬이 조금씩 좋아지고 있어요.",
                direction: .improving
            ),
            tint: SOOMColor.bike
        )
    }
}
