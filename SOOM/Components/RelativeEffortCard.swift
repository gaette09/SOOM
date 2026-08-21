import SwiftUI

/// PDF's Relative Effort 3-tier comparison bar (feed-detail-migration-plan.md).
/// Colors are per-tier (higher/average/lower), not the workout's sport tint —
/// these three states carry real semantic meaning, unlike the single-series
/// distance charts where one consistent tint made sense.
struct RelativeEffortCard: View {
    let comparison: RelativeEffortComparison

    var body: some View {
        SOOMCard {
            HStack(alignment: .firstTextBaseline) {
                Text("운동 강도")
                    .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                Spacer()
                Text("\(comparison.todayEffort)")
                    .font(SOOMFont.displayMedium(28, relativeTo: .title))
                    .foregroundStyle(SOOMColor.ink)
            }

            Text(subtitle)
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)

            tierBar
                .frame(height: 10)
                .padding(.top, SOOMLayout.Metrics.actionTextSpacing)

            HStack {
                Text("낮음")
                Spacer()
                Text("최근 3주 평균")
                Spacer()
                Text("높음")
            }
            .font(SOOMFont.body(11, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.tertiaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("운동 강도")
        .accessibilityValue("\(comparison.todayEffort), \(subtitle)")
    }

    private var subtitle: String {
        switch comparison.tier {
        case .higher:
            return "최근 3주 평균(\(comparison.recentAverageEffort))보다 높아요."
        case .average:
            return "최근 3주 평균(\(comparison.recentAverageEffort))과 비슷해요."
        case .lower:
            return "최근 3주 평균(\(comparison.recentAverageEffort))보다 낮아요."
        }
    }

    private var tierColor: Color {
        switch comparison.tier {
        case .higher:
            return SOOMColor.warning
        case .average:
            return SOOMColor.accent
        case .lower:
            return SOOMColor.recovery
        }
    }

    private var tierBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    Capsule().fill(SOOMColor.recovery.opacity(0.35))
                    Capsule().fill(SOOMColor.accent.opacity(0.35))
                    Capsule().fill(SOOMColor.warning.opacity(0.35))
                }

                Circle()
                    .fill(tierColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(SOOMColor.surface, lineWidth: 2))
                    .offset(x: proxy.size.width * comparison.markerPosition - 7)
            }
        }
    }
}

#Preview("RelativeEffortCard") {
    VStack(spacing: 16) {
        RelativeEffortCard(comparison: RelativeEffortComparison(todayEffort: 62, recentAverageEffort: 40, tier: .higher))
        RelativeEffortCard(comparison: RelativeEffortComparison(todayEffort: 41, recentAverageEffort: 40, tier: .average))
        RelativeEffortCard(comparison: RelativeEffortComparison(todayEffort: 20, recentAverageEffort: 40, tier: .lower))
    }
    .padding(SOOMLayout.screenPadding)
    .background(SOOMColor.background)
}
