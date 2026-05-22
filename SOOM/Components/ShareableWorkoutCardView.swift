import SwiftUI

struct ShareableWorkoutCardView: View {
    let card: ShareableWorkoutCardModel
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            header

            if let preview = card.staticRoutePreview, preview.routeExists {
                StaticRoutePreviewSurface(preview: preview, tint: tint)
            }

            Spacer(minLength: SOOMLayout.Card.contentSpacing)

            VStack(alignment: .leading, spacing: ShareableWorkoutCardLayout.messageSpacing) {
                Text(card.title)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(tint)

                Text(card.primaryMessage)
                    .font(SOOMFont.displayMedium(25, relativeTo: .title2))
                    .foregroundStyle(SOOMColor.ink)
                    .lineSpacing(ShareableWorkoutCardLayout.primaryLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: ShareableWorkoutCardLayout.metricSpacing) {
                ShareableMetric(label: "거리", value: card.distanceText)
                ShareableMetric(label: "시간", value: card.durationText)
            }

            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                ShareableMessageLine(icon: SOOMIcon.trendUp, text: card.growthMessage, tint: tint)
                ShareableMessageLine(icon: SOOMIcon.recovery, text: card.recoveryMessage, tint: SOOMColor.recovery)
            }
            .padding(SOOMLayout.Card.padding)
            .background(SOOMColor.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.innerRadius, style: .continuous))

            Spacer(minLength: SOOMLayout.Card.contentSpacing)

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ShareableWorkoutCardLayout.outerPadding)
        .aspectRatio(ShareableWorkoutCardLayout.aspectRatio, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius, style: .continuous)
                .fill(SOOMColor.surface)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(tint.opacity(0.10))
                .frame(width: ShareableWorkoutCardLayout.accentCircleSize, height: ShareableWorkoutCardLayout.accentCircleSize)
                .offset(x: ShareableWorkoutCardLayout.accentCircleOffset, y: -ShareableWorkoutCardLayout.accentCircleOffset)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius, style: .continuous)
                .stroke(SOOMColor.line, lineWidth: SOOMLayout.Card.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("공유 카드 미리보기")
        .accessibilityValue("\(card.title). \(card.distanceText), \(card.durationText). \(routeAccessibilityText) \(card.primaryMessage). \(card.growthMessage). \(card.recoveryMessage). \(card.visibility.title)")
    }

    private var routeAccessibilityText: String {
        guard card.staticRoutePreview?.routeExists == true else { return "" }
        return "경로 미리보기 포함."
    }

    private var header: some View {
        HStack(alignment: .center, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
            Image(systemName: card.workoutType.shareableIcon)
                .font(.system(size: ShareableWorkoutCardLayout.headerIconSize, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: ShareableWorkoutCardLayout.headerIconFrame, height: ShareableWorkoutCardLayout.headerIconFrame)
                .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                Text("SOOM")
                    .font(SOOMFont.displayMedium(15, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)

                Text("오늘의 성장 기록")
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }

            Spacer()

            ShareablePrivacyBadge(title: "민감 정보 제외")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
            Divider()
                .overlay(SOOMColor.line)

            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text(card.footerText)
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.secondaryInk)

                Spacer()

                ShareablePrivacyBadge(title: card.visibility.title, tint: tint)
            }
        }
    }
}

private struct StaticRoutePreviewSurface: View {
    let preview: StaticRoutePreview
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.innerRadius, style: .continuous)
                .fill(tint.opacity(0.10))

            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Image(systemName: SOOMIcon.map)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                    Text(preview.imageURL == nil ? preview.fallbackStyle.title : "Route preview")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.ink)

                    Text(preview.imageURL == nil ? "지도 이미지는 토큰 연결 후 표시돼요" : "Mapbox static image 준비됨")
                        .font(SOOMFont.body(10, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(ShareableWorkoutCardLayout.routePreviewPadding)
        }
        .frame(height: ShareableWorkoutCardLayout.routePreviewHeight)
        .overlay(
            RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.innerRadius, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: SOOMLayout.Card.borderWidth)
        )
        .accessibilityHidden(true)
    }
}

struct ShareablePrivacyBadge: View {
    let title: String
    var tint: Color?

    var body: some View {
        Text(title)
            .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(tint ?? SOOMColor.secondaryInk)
            .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
            .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding)
            .background((tint ?? SOOMColor.black).opacity(backgroundOpacity))
            .clipShape(Capsule())
    }

    private var backgroundOpacity: Double {
        tint == nil ? 0.06 : SOOMLayout.Metrics.actionIconBackgroundOpacity
    }
}

enum ShareableWorkoutCardLayout {
    static let aspectRatio: CGFloat = 4.0 / 5.0
    static let exportWidth: CGFloat = 360
    static let exportScale: CGFloat = 3
    static let outerPadding: CGFloat = 22
    static let outerRadius: CGFloat = 22
    static let innerRadius: CGFloat = 16
    static let headerIconFrame: CGFloat = 42
    static let headerIconSize: CGFloat = 20
    static let metricSpacing: CGFloat = 10
    static let messageSpacing: CGFloat = 8
    static let primaryLineSpacing: CGFloat = 3
    static let accentCircleSize: CGFloat = 156
    static let accentCircleOffset: CGFloat = 58
    static let routePreviewHeight: CGFloat = 58
    static let routePreviewPadding: CGFloat = 12
}

private extension StaticRouteFallbackStyle {
    var title: String {
        switch self {
        case .running:
            return "러닝 경로 미리보기"
        case .cycling:
            return "라이딩 경로 미리보기"
        case .swimming:
            return "수영 기록 미리보기"
        case .walking:
            return "걷기 경로 미리보기"
        case .generic:
            return "운동 경로 미리보기"
        }
    }
}

private struct ShareableMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text(label)
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
            Text(value)
                .font(SOOMFont.displayMedium(20, relativeTo: .headline))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Card.padding)
        .background(SOOMColor.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.innerRadius, style: .continuous))
    }
}

private struct ShareableMessageLine: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
    }
}

private extension UnifiedWorkoutType {
    var shareableIcon: String {
        switch self {
        case .running:
            return SOOMIcon.run
        case .cycling:
            return SOOMIcon.bike
        case .swimming:
            return SOOMIcon.swim
        case .walking, .hiking:
            return SOOMIcon.run
        case .strength:
            return SOOMIcon.bolt
        case .yoga:
            return SOOMIcon.recovery
        case .other:
            return SOOMIcon.record
        }
    }
}

#Preview("ShareableWorkoutCardView") {
    let workout = MockWorkoutHarness().loadWorkouts()[0]
    let growth = WorkoutGrowthSummaryBuilder().build(current: workout, recentWorkouts: [workout])
    let weakness = WorkoutWeaknessInsightBuilder().build(current: workout, recentWorkouts: [workout])
    let impact = WorkoutRecoveryImpactBuilder().build(workout: workout)
    let session = WorkoutSessionSummaryBuilder().build(
        workout: workout,
        growthSummary: growth,
        weaknessInsight: weakness,
        recoveryImpact: impact
    )
    let card = ShareableWorkoutCardBuilder().build(
        workout: workout,
        sessionSummary: session,
        growthSummary: growth,
        recoveryImpact: impact
    )

    SOOMScreen {
        ShareableWorkoutCardView(card: card, tint: workout.sport.tint)
    }
    .preferredColorScheme(.light)
}
