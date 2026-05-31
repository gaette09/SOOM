import SwiftUI

struct ShareableWorkoutCardView: View {
    let card: ShareableWorkoutCardModel
    let tint: Color

    var body: some View {
        if card.backgroundOption == .transparent {
            transparentCard
        } else {
            standardCard
        }
    }

    private var standardCard: some View {
        ZStack(alignment: .bottomLeading) {
            backgroundLayer

            LinearGradient(
                colors: [
                    SOOMColor.black.opacity(0.04),
                    SOOMColor.black.opacity(0.18),
                    SOOMColor.black.opacity(0.54)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            rhythmPatternLayer

            VStack(alignment: .leading, spacing: 0) {
                storyHeader

                Spacer(minLength: ShareableWorkoutCardLayout.storyVerticalBreathing)

                storyContent

                Spacer(minLength: ShareableWorkoutCardLayout.storyVerticalBreathing)

                storyFooter
            }
            .padding(ShareableWorkoutCardLayout.outerPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(ShareableWorkoutCardLayout.aspectRatio, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius, style: .continuous)
                .stroke(card.backgroundOption == .transparent ? tint.opacity(0.20) : SOOMColor.white.opacity(0.16), lineWidth: SOOMLayout.Card.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("공유 카드 미리보기")
        .accessibilityValue("\(card.shareType.title) 카드. \(card.storyHeadline). \(card.storyInterpretation). \(card.storySupportingText). \(routeAccessibilityText) \(card.visibility.title)")
    }

    private var transparentCard: some View {
        ZStack(alignment: .bottomLeading) {
            if card.shouldShowRouteLineInTransparentExport {
                ShareCardRouteLine(style: .transparent, tint: tint)
                    .frame(height: ShareableWorkoutCardLayout.transparentRouteLineHeight)
                    .padding(.horizontal, ShareableWorkoutCardLayout.transparentRouteHorizontalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, ShareableWorkoutCardLayout.transparentRouteTopPadding)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: ShareableWorkoutCardLayout.transparentTextSpacing) {
                Spacer(minLength: 0)

                Text(card.storyHeadline)
                    .font(transparentHeadlineFont)
                    .foregroundStyle(transparentForeground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                if card.shareType == .workout || card.shareType == .route {
                    transparentMetricLine
                }

                Text(card.storyInterpretation)
                    .font(SOOMFont.displayMedium(26, relativeTo: .title2))
                    .foregroundStyle(transparentForeground)
                    .lineSpacing(ShareableWorkoutCardLayout.primaryLineSpacing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
                    .fixedSize(horizontal: false, vertical: true)

                if card.shareType == .club {
                    Text(card.storySupportingText)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(transparentSecondaryForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(card.signatureFooterText)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(transparentSecondaryForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, ShareableWorkoutCardLayout.transparentSignatureTopPadding)
            }
            .padding(ShareableWorkoutCardLayout.transparentExportPadding)
            .shadow(color: SOOMColor.black.opacity(0.36), radius: 12, x: 0, y: 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(ShareableWorkoutCardLayout.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("투명 공유 카드 미리보기")
        .accessibilityValue("\(card.shareType.title) 카드. \(card.storyHeadline). \(card.storyInterpretation). \(card.storySupportingText). \(routeAccessibilityText)")
    }

    private var routeAccessibilityText: String {
        guard card.staticRoutePreview?.routeExists == true else { return "" }
        return "경로 미리보기 포함."
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch card.backgroundOption {
        case .mapPhoto:
            if let preview = card.staticRoutePreview, preview.routeExists {
                StaticRoutePreviewSurface(preview: preview, tint: tint)
            } else {
                ShareCardMediaPlaceholder(card: card, tint: tint)
            }
        case .transparent:
            EmptyView()
        }
    }

    private var storyHeader: some View {
        HStack(alignment: .center, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Image(systemName: card.shareType.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(headerForeground)
                .accessibilityHidden(true)

            Text("\(card.shareType.cardTitle) · \(ShareCardComposerLayout.index(for: card.shareType) + 1) / \(ShareCardComposerLayout.cardOrder.count)")
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(headerForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer()

            Text("SOOM")
                .font(SOOMFont.displayMedium(14, relativeTo: .caption))
                .foregroundStyle(headerForeground)
        }
    }

    private var storyContent: some View {
        VStack(alignment: .leading, spacing: ShareableWorkoutCardLayout.storyTextSpacing) {
            Text(card.storyHeadline)
                .font(storyHeadlineFont)
                .foregroundStyle(storyForeground)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            if card.shareType == .workout || card.shareType == .route {
                standardMetricStrip
            }

            Text(card.storyInterpretation)
                .font(SOOMFont.displayMedium(30, relativeTo: .title))
                .foregroundStyle(storyForeground)
                .lineSpacing(ShareableWorkoutCardLayout.primaryLineSpacing)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .fixedSize(horizontal: false, vertical: true)

            Text(card.storySupportingText)
                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(storySecondaryForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .shadow(color: card.backgroundOption == .transparent ? .clear : SOOMColor.black.opacity(0.18), radius: 14, x: 0, y: 8)
    }

    private var standardMetricStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(card.publicMetrics.prefix(3).enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.label)
                        .font(SOOMFont.body(9, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.white.opacity(0.66))
                        .lineLimit(1)

                    Text(metric.value)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(SOOMColor.black.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var transparentMetricLine: some View {
        Text(transparentMetricText)
            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
            .foregroundStyle(transparentSecondaryForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
    }

    private var transparentMetricText: String {
        switch card.shareType {
        case .workout:
            return card.publicMetrics.dropFirst().map(\.value).joined(separator: " · ")
        case .route:
            return card.compactDistanceText
        case .recovery, .club:
            return card.storySupportingText
        }
    }

    private var storyFooter: some View {
        HStack(alignment: .center, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Capsule()
                .fill(tint)
                .frame(width: 28, height: 4)
                .accessibilityHidden(true)

            Text(card.visibility.title)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(storySecondaryForeground)

            Spacer()

            Text(card.signatureFooterText)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(storySecondaryForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private var rhythmPatternLayer: some View {
        ShareCardRhythmPattern(tint: tint, isTransparent: card.backgroundOption == .transparent)
            .padding(ShareableWorkoutCardLayout.rhythmPatternInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var headerForeground: Color {
        card.backgroundOption == .transparent ? SOOMColor.secondaryInk : SOOMColor.white.opacity(0.86)
    }

    private var storyForeground: Color {
        card.backgroundOption == .transparent ? SOOMColor.ink : SOOMColor.white
    }

    private var storySecondaryForeground: Color {
        card.backgroundOption == .transparent ? SOOMColor.secondaryInk : SOOMColor.white.opacity(0.78)
    }

    private var storyHeadlineFont: Font {
        switch card.shareType {
        case .workout:
            return SOOMFont.display(48, relativeTo: .largeTitle)
        case .recovery:
            return SOOMFont.display(54, relativeTo: .largeTitle)
        case .route, .club:
            return SOOMFont.displayMedium(36, relativeTo: .largeTitle)
        }
    }

    private var transparentHeadlineFont: Font {
        switch card.shareType {
        case .workout:
            return SOOMFont.display(50, relativeTo: .largeTitle)
        case .recovery:
            return SOOMFont.display(58, relativeTo: .largeTitle)
        case .route, .club:
            return SOOMFont.displayMedium(38, relativeTo: .largeTitle)
        }
    }

    private var transparentForeground: Color {
        SOOMColor.white
    }

    private var transparentSecondaryForeground: Color {
        SOOMColor.white.opacity(0.86)
    }
}

private struct StaticRoutePreviewSurface: View {
    let preview: StaticRoutePreview
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            routeVisual
                .overlay(tint.opacity(0.08))

            ShareCardRouteLine(style: .mapPhoto, tint: tint)
                .padding(.horizontal, 26)
                .padding(.vertical, 48)

            Image(systemName: SOOMIcon.map)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(SOOMColor.white.opacity(0.16))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(ShareableWorkoutCardLayout.routePreviewPadding)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var routeVisual: some View {
        if let imageURL = preview.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    placeholderVisual
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .overlay(SOOMColor.surface.opacity(0.18))
                        .overlay(tint.opacity(0.08))
                case .failure:
                    fallbackVisual
                @unknown default:
                    fallbackVisual
                }
            }
        } else {
            fallbackVisual
        }
    }

    private var placeholderVisual: some View {
        fallbackVisual
            .overlay(
                RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.innerRadius, style: .continuous)
                    .fill(SOOMColor.surface.opacity(0.18))
            )
    }

    private var fallbackVisual: some View {
        LinearGradient(
            colors: [
                tint.opacity(0.26),
                SOOMColor.accentSurface,
                SOOMColor.surfaceMuted
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
            .overlay(alignment: .trailing) {
                Image(systemName: SOOMIcon.map)
                    .font(.system(size: 74, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.18))
                    .padding(.trailing, ShareableWorkoutCardLayout.routePreviewPadding)
            }
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
    static let usesMetricGrid = false
    static let usesRhythmPattern = true
    static let transparentExportIncludesCardSurface = false
    static let transparentExportIncludesBorder = false
    static let transparentExportIncludesMetadata = false
    static let transparentExportIncludesRhythmPattern = false
    static let transparentPreviewIncludesCheckerboard = true
    static let transparentPreviewIncludesBadge = true
    static let aspectRatio: CGFloat = 9.0 / 16.0
    static let exportWidth: CGFloat = 360
    static let exportScale: CGFloat = 3
    static let outerPadding: CGFloat = 22
    static let outerRadius: CGFloat = 22
    static let innerRadius: CGFloat = 16
    static let transparentContentInset: CGFloat = 16
    static let headerIconFrame: CGFloat = 42
    static let headerIconSize: CGFloat = 20
    static let metricSpacing: CGFloat = 10
    static let messageSpacing: CGFloat = 8
    static let primaryLineSpacing: CGFloat = 3
    static let storyTextSpacing: CGFloat = 14
    static let storyVerticalBreathing: CGFloat = 32
    static let accentCircleSize: CGFloat = 156
    static let accentCircleOffset: CGFloat = 58
    static let routePreviewHeight: CGFloat = 148
    static let routePreviewPadding: CGFloat = 12
    static let rhythmPatternInset: CGFloat = 18
    static let rhythmPatternLineWidth: CGFloat = 1.4
    static let rhythmPatternOpacity: Double = 0.16
    static let transparentExportPadding: CGFloat = 26
    static let transparentRouteLineHeight: CGFloat = 210
    static let transparentRouteHorizontalPadding: CGFloat = 24
    static let transparentRouteTopPadding: CGFloat = 82
    static let transparentTextSpacing: CGFloat = 12
    static let transparentSignatureTopPadding: CGFloat = 7
}

private enum ShareCardRouteLineStyle: Equatable {
    case mapPhoto
    case transparent
    case fallback
}

private struct ShareCardRouteLine: View {
    let style: ShareCardRouteLineStyle
    let tint: Color

    var body: some View {
        ZStack {
            if style == .transparent {
                RouteRibbonShape()
                    .stroke(SOOMColor.black.opacity(0.32), style: StrokeStyle(lineWidth: 8.5, lineCap: .round, lineJoin: .round))
                    .blur(radius: 0.4)
            } else {
                RouteRibbonShape()
                    .stroke(SOOMColor.black.opacity(0.24), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    .blur(radius: 0.4)
            }

            RouteRibbonShape()
                .stroke(outerLineColor, style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .round, lineJoin: .round))

            RouteRibbonShape()
                .stroke(innerLineColor, style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round, lineJoin: .round))

            RouteEndpointDots(tint: endpointColor, halo: endpointHaloColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var outerLineColor: Color {
        switch style {
        case .transparent:
            return SOOMColor.white.opacity(0.92)
        case .mapPhoto:
            return SOOMColor.white.opacity(0.86)
        case .fallback:
            return tint.opacity(0.42)
        }
    }

    private var innerLineColor: Color {
        switch style {
        case .transparent:
            return SOOMColor.accent.opacity(0.96)
        case .mapPhoto:
            return tint.opacity(0.92)
        case .fallback:
            return SOOMColor.white.opacity(0.70)
        }
    }

    private var outerLineWidth: CGFloat {
        style == .transparent ? 6.4 : 5.4
    }

    private var innerLineWidth: CGFloat {
        style == .transparent ? 3.5 : 2.8
    }

    private var endpointColor: Color {
        style == .transparent ? SOOMColor.accent : SOOMColor.white
    }

    private var endpointHaloColor: Color {
        style == .transparent ? SOOMColor.white : tint
    }
}

private struct RouteRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.72))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.26),
            control1: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.70),
            control2: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.63, y: rect.minY + rect.height * 0.46),
            control1: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.minX + rect.width * 0.50, y: rect.minY + rect.height * 0.52)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.22),
            control1: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.38),
            control2: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.18)
        )
        return path
    }
}

private struct RouteEndpointDots: View {
    let tint: Color
    let halo: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let start = CGPoint(x: size.width * 0.12, y: size.height * 0.72)
            let end = CGPoint(x: size.width * 0.88, y: size.height * 0.22)

            ZStack {
                endpoint(at: start, size: 15)
                endpoint(at: end, size: 18)
            }
        }
        .allowsHitTesting(false)
    }

    private func endpoint(at point: CGPoint, size: CGFloat) -> some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(halo.opacity(0.92), lineWidth: 3)
            )
            .position(point)
    }
}

private struct ShareCardRhythmPattern: View {
    let tint: Color
    let isTransparent: Bool

    var body: some View {
        ZStack {
            BreathingCircleShape()
                .stroke(
                    tint.opacity(isTransparent ? 0.10 : ShareableWorkoutCardLayout.rhythmPatternOpacity),
                    style: StrokeStyle(lineWidth: ShareableWorkoutCardLayout.rhythmPatternLineWidth, lineCap: .round)
                )
                .frame(width: 170, height: 170)
                .offset(x: 84, y: -184)

            RhythmWaveShape()
                .stroke(
                    rhythmColor,
                    style: StrokeStyle(lineWidth: ShareableWorkoutCardLayout.rhythmPatternLineWidth, lineCap: .round, lineJoin: .round)
                )
                .frame(height: 128)
                .offset(y: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rhythmColor: Color {
        isTransparent
            ? tint.opacity(0.09)
            : SOOMColor.white.opacity(ShareableWorkoutCardLayout.rhythmPatternOpacity)
    }
}

private struct BreathingCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2

        for index in 0..<3 {
            let inset = CGFloat(index) * maxRadius * 0.22
            let radius = maxRadius - inset
            let circleRect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            path.addEllipse(in: circleRect)
        }

        return path
    }
}

private struct RhythmWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX - rect.width * 0.08, y: rect.midY + rect.height * 0.14)
        path.move(to: start)
        path.addCurve(
            to: CGPoint(x: rect.midX * 0.92, y: rect.midY - rect.height * 0.20),
            control1: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.midY - rect.height * 0.24),
            control2: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.midY + rect.height * 0.24)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX + rect.width * 0.08, y: rect.midY - rect.height * 0.06),
            control1: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.midY - rect.height * 0.56),
            control2: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.midY + rect.height * 0.28)
        )
        return path
    }
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

private struct ShareCardMediaPlaceholder: View {
    let card: ShareableWorkoutCardModel
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    tint.opacity(0.18),
                    SOOMColor.surfaceMuted,
                    SOOMColor.accentSurface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if card.shouldShowRouteVisual {
                ShareCardRouteLine(style: .fallback, tint: tint)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 54)
            }

            Image(systemName: card.shareType == .route ? SOOMIcon.map : SOOMIcon.sparkles)
                .font(.system(size: 88, weight: .semibold))
                .foregroundStyle(tint.opacity(0.24))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
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
