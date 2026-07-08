import SwiftUI
import UIKit

struct ShareableWorkoutCardView: View {
    let card: ShareableWorkoutCardModel
    let tint: Color
    var resolvedRouteImage: UIImage?

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
                    SOOMColor.black.opacity(0.10),
                    SOOMColor.black.opacity(0.24),
                    SOOMColor.black.opacity(0.68)
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
            .padding(ShareableWorkoutCardLayout.storySafePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        GeometryReader { proxy in
            transparentLayout(in: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(ShareableWorkoutCardLayout.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("투명 공유 카드 미리보기")
        .accessibilityValue("\(card.shareType.title) 카드. \(card.compactDistanceText). \(card.compactDurationText). \(transparentPaceOrSpeedText). \(routeAccessibilityText)")
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
                StaticRoutePreviewSurface(preview: preview, tint: tint, resolvedImage: resolvedRouteImage)
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

            Text(card.shareType.title)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(headerForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .allowsTightening(true)

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
                .lineLimit(3)
                .minimumScaleFactor(0.52)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)

            Text(card.storyInterpretation)
                .font(SOOMFont.displayMedium(26, relativeTo: .title2))
                .foregroundStyle(storyForeground)
                .lineSpacing(ShareableWorkoutCardLayout.primaryLineSpacing)
                .lineLimit(3)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)

            Text(card.storySupportingText)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(storySecondaryForeground)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .shadow(color: card.backgroundOption == .transparent ? .clear : SOOMColor.black.opacity(0.18), radius: 14, x: 0, y: 8)
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
            return SOOMFont.display(44, relativeTo: .largeTitle)
        case .recovery:
            return SOOMFont.display(48, relativeTo: .largeTitle)
        case .route, .club:
            return SOOMFont.displayMedium(34, relativeTo: .title)
        }
    }

    private var transparentForeground: Color {
        SOOMColor.white
    }

    private var transparentSecondaryForeground: Color {
        SOOMColor.white.opacity(0.86)
    }

    @ViewBuilder
    private func transparentLayout(in size: CGSize) -> some View {
        switch ShareTransparentCardLayoutVariant.variant(for: card.shareType) {
        case .routeCentric:
            routeCentricLayout(in: size)
        case .metricCentric:
            metricCentricLayout(in: size)
        case .balanced:
            balancedLayout(in: size)
        case .statSummary:
            statSummaryLayout(in: size)
        }
    }

    private func routeCentricLayout(in size: CGSize) -> some View {
        let inset = transparentSafeInset(for: size)
        let safeWidth = size.width - inset.width * 2

        return transparentCanvas(size: size) {
            transparentHeaderRow(size: size, inset: inset, showsIcon: true)
                .position(x: size.width * 0.50, y: inset.height * 0.92)

            routeLine(width: safeWidth, height: size.height * 0.58)
                .position(x: size.width * 0.50, y: size.height * 0.40)

            transparentMetricRow(width: safeWidth, valueSize: size.width * 0.056)
                .position(x: size.width * 0.50, y: size.height * 0.83)
        }
    }

    private func metricCentricLayout(in size: CGSize) -> some View {
        let inset = transparentSafeInset(for: size)
        let safeWidth = size.width - inset.width * 2

        return transparentCanvas(size: size) {
            Image(systemName: sportIconName)
                .font(.system(size: size.width * 0.055, weight: .semibold))
                .foregroundStyle(transparentSecondaryForeground.opacity(0.82))
                .frame(width: size.width * 0.10, height: size.width * 0.10)
                .accessibilityHidden(true)
                .position(x: size.width * 0.50, y: inset.height * 0.86)

            soomMark(fontSize: size.width * 0.076, opacity: 0.92)
                .frame(width: safeWidth, alignment: .center)
                .position(x: size.width * 0.50, y: size.height * 0.17)

            primaryDistanceText(fontSize: size.width * 0.09)
                .frame(width: safeWidth, alignment: .center)
                .position(x: size.width * 0.50, y: size.height * 0.34)

            HStack(alignment: .top, spacing: size.width * 0.08) {
                transparentMetric(label: "시간", value: card.compactDurationText, valueSize: size.width * 0.058)
                transparentMetric(label: transparentPaceOrSpeedLabel, value: transparentPaceOrSpeedText, valueSize: size.width * 0.058)
            }
            .frame(width: safeWidth * 0.74, alignment: .center)
            .position(x: size.width * 0.50, y: size.height * 0.47)

            routeLine(width: safeWidth * 0.76, height: size.height * 0.18, opacity: 0.86)
                .position(x: size.width * 0.50, y: size.height * 0.68)

            soomMark
                .frame(width: safeWidth, alignment: .center)
                .position(x: size.width * 0.50, y: size.height - inset.height * 0.72)
        }
    }

    private func balancedLayout(in size: CGSize) -> some View {
        let inset = transparentSafeInset(for: size)
        let safeWidth = size.width - inset.width * 2
        let columnWidth = safeWidth * 0.42

        return transparentCanvas(size: size) {
            transparentHeaderRow(size: size, inset: inset, showsIcon: false)
                .position(x: size.width * 0.50, y: inset.height * 0.90)

            VStack(alignment: .leading, spacing: size.height * 0.038) {
                transparentMetric(label: "거리", value: card.compactDistanceText, valueSize: size.width * 0.060)
                transparentMetric(label: "시간", value: card.compactDurationText, valueSize: size.width * 0.050)
                transparentMetric(label: transparentPaceOrSpeedLabel, value: transparentPaceOrSpeedText, valueSize: size.width * 0.050)
            }
            .frame(width: columnWidth, alignment: .leading)
            .position(x: inset.width + columnWidth / 2, y: size.height * 0.33)

            routeLine(width: safeWidth * 0.76, height: size.height * 0.32, opacity: 0.90)
                .position(x: size.width * 0.58, y: size.height * 0.65)

            soomMark
                .frame(width: columnWidth, alignment: .leading)
                .position(x: inset.width + columnWidth / 2, y: size.height - inset.height * 0.58)
        }
    }

    private func statSummaryLayout(in size: CGSize) -> some View {
        let inset = transparentSafeInset(for: size)
        let safeWidth = size.width - inset.width * 2

        return transparentCanvas(size: size) {
            transparentHeaderRow(size: size, inset: inset, showsIcon: true)
                .position(x: size.width * 0.50, y: inset.height * 0.92)

            VStack(alignment: .leading, spacing: size.height * 0.036) {
                ForEach(Array(statSummaryRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: size.width * 0.060) {
                        ForEach(row, id: \.label) { metric in
                            statSummaryMetric(label: metric.label, value: metric.value, valueSize: size.width * 0.048)
                        }
                    }
                }
            }
            .frame(width: safeWidth, alignment: .leading)
            .position(x: size.width * 0.50, y: size.height * 0.54)
        }
    }

    private func transparentCanvas<Content: View>(
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            content()
        }
        .frame(width: size.width, height: size.height)
        .transparentExportShadow()
    }

    private func transparentSafeInset(
        for size: CGSize,
        horizontalRatio: CGFloat = 0.060,
        verticalRatio: CGFloat = 0.065
    ) -> CGSize {
        CGSize(
            width: max(size.width * horizontalRatio, 22),
            height: max(size.height * verticalRatio, 34)
        )
    }

    private func routeLine(width: CGFloat, height: CGFloat, opacity: Double = 0.92) -> some View {
        let fittedSize = ShareableWorkoutCardLayout.aspectFittedTransparentRouteSize(
            in: CGSize(width: width, height: height)
        )

        return Group {
            if card.shouldShowRouteVisual {
                ShareCardRouteLine(style: .transparent, tint: tint)
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .frame(width: width, height: height, alignment: .center)
                    .opacity(opacity)
                    .accessibilityHidden(true)
            } else {
                Color.clear
                    .frame(width: width, height: height)
            }
        }
    }

    private func transparentMetricRow(
        width: CGFloat,
        valueSize: CGFloat,
        order: [TransparentMetricKind] = [.distance, .duration, .pace]
    ) -> some View {
        HStack(alignment: .top, spacing: max(width * 0.055, 12)) {
            ForEach(order, id: \.self) { metric in
                let resolvedMetric = transparentMetric(for: metric)
                transparentMetric(label: resolvedMetric.label, value: resolvedMetric.value, valueSize: valueSize)
            }
        }
        .frame(width: width, alignment: .center)
    }

    private func transparentHeaderRow(size: CGSize, inset: CGSize, showsIcon: Bool) -> some View {
        HStack(alignment: .center, spacing: size.width * 0.035) {
            if showsIcon {
                Image(systemName: sportIconName)
                    .font(.system(size: size.width * 0.050, weight: .semibold))
                    .foregroundStyle(transparentForeground.opacity(0.90))
                    .frame(width: size.width * 0.075, height: size.width * 0.075)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)

            soomMark(fontSize: size.width * 0.050, opacity: 0.90)
        }
        .frame(width: size.width - inset.width * 2, alignment: .center)
    }

    private func transparentMetric(for kind: TransparentMetricKind) -> ShareCardMetric {
        switch kind {
        case .distance:
            return ShareCardMetric(label: "거리", value: card.compactDistanceText)
        case .duration:
            return ShareCardMetric(label: "시간", value: card.compactDurationText)
        case .pace:
            return ShareCardMetric(label: transparentPaceOrSpeedLabel, value: transparentPaceOrSpeedText)
        }
    }

    private func primaryDistanceText(fontSize: CGFloat) -> some View {
        Text(card.compactDistanceText)
            .font(SOOMFont.display(fontSize, relativeTo: .largeTitle))
            .foregroundStyle(transparentForeground)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.42)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .center)
            .layoutPriority(2)
    }

    private func transparentMetric(label: String, value: String, valueSize: CGFloat = 22) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SOOMFont.body(9, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(transparentSecondaryForeground.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(SOOMFont.displayMedium(valueSize, relativeTo: .title3))
                .foregroundStyle(transparentForeground.opacity(0.94))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.50)
                .allowsTightening(true)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private func statSummaryMetric(label: String, value: String, valueSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(SOOMFont.body(9, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(transparentSecondaryForeground.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(SOOMFont.displayMedium(valueSize, relativeTo: .title3))
                .foregroundStyle(transparentForeground.opacity(0.95))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.48)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statSummaryRows: [[ShareCardMetric]] {
        [
            [
                ShareCardMetric(label: "거리", value: card.compactDistanceText),
                ShareCardMetric(label: "시간", value: card.compactDurationText)
            ],
            [
                ShareCardMetric(label: transparentPaceOrSpeedLabel, value: transparentPaceOrSpeedText),
                ShareCardMetric(label: "고도", value: card.elevationGainText ?? ShareableWorkoutCardLayout.statSummaryMissingMetricPlaceholder)
            ],
            [
                ShareCardMetric(label: "심박", value: card.averageHeartRateText ?? ShareableWorkoutCardLayout.statSummaryMissingMetricPlaceholder),
                ShareCardMetric(label: "칼로리", value: card.activeEnergyText ?? ShareableWorkoutCardLayout.statSummaryMissingMetricPlaceholder)
            ]
        ]
    }

    private var soomMark: some View {
        soomMark(fontSize: 10, opacity: 0.84)
    }

    private func soomMark(fontSize: CGFloat, opacity: Double) -> some View {
        Text("SOOM")
            .font(SOOMFont.body(fontSize, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(transparentSecondaryForeground.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.70)
            .allowsTightening(true)
    }

    private var transparentPaceOrSpeedLabel: String {
        card.workoutType == .cycling ? "속도" : "페이스"
    }

    private var transparentPaceOrSpeedText: String {
        if let pace = card.normalizedPaceText {
            return pace
        }
        return card.publicMetrics.dropFirst().first?.value ?? "-"
    }

    private var sportIconName: String {
        switch card.workoutType {
        case .running:
            return SOOMIcon.run
        case .cycling:
            return SOOMIcon.bike
        case .swimming:
            return SOOMIcon.swim
        case .walking:
            return "figure.walk"
        case .hiking:
            return "figure.hiking"
        case .strength:
            return "dumbbell"
        case .yoga:
            return "figure.mind.and.body"
        case .other:
            return SOOMIcon.activity
        }
    }

}

private enum TransparentMetricKind: Hashable {
    case distance
    case duration
    case pace
}

enum ShareTransparentCardLayoutVariant: String, CaseIterable, Equatable, Hashable {
    case routeCentric
    case metricCentric
    case balanced
    case statSummary

    static func variant(for shareType: ShareCardType) -> ShareTransparentCardLayoutVariant {
        switch shareType {
        case .workout:
            return .routeCentric
        case .recovery:
            return .metricCentric
        case .route:
            return .balanced
        case .club:
            return .statSummary
        }
    }
}

private extension View {
    func transparentExportShadow() -> some View {
        shadow(color: SOOMColor.black.opacity(0.30), radius: 4, x: 0, y: 2)
    }
}

private struct StaticRoutePreviewSurface: View {
    let preview: StaticRoutePreview
    let tint: Color
    let resolvedImage: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            routeVisual
                .overlay(tint.opacity(0.08))

            if showsSyntheticRouteLine {
                ShareCardRouteLine(style: .mapPhoto, tint: tint)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 48)
            }

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
        if let resolvedImage {
            Image(uiImage: resolvedImage)
                .resizable()
                .scaledToFill()
                .overlay(SOOMColor.surface.opacity(0.18))
                .overlay(tint.opacity(0.08))
        } else if let imageURL = preview.imageURL {
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

    private var showsSyntheticRouteLine: Bool {
        resolvedImage == nil && preview.imageURL == nil
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
    static let outerPadding: CGFloat = 28
    static let storySafePadding: CGFloat = 34
    static let outerRadius: CGFloat = 22
    static let innerRadius: CGFloat = 16
    static let transparentContentInset: CGFloat = 16
    static let headerIconFrame: CGFloat = 42
    static let headerIconSize: CGFloat = 20
    static let metricSpacing: CGFloat = 10
    static let messageSpacing: CGFloat = 8
    static let primaryLineSpacing: CGFloat = 3
    static let storyTextSpacing: CGFloat = 13
    static let storyVerticalBreathing: CGFloat = 18
    static let accentCircleSize: CGFloat = 156
    static let accentCircleOffset: CGFloat = 58
    static let routePreviewHeight: CGFloat = 148
    static let routePreviewPadding: CGFloat = 12
    static let rhythmPatternInset: CGFloat = 18
    static let rhythmPatternLineWidth: CGFloat = 1.4
    static let rhythmPatternOpacity: Double = 0.16
    static let transparentExportPadding: CGFloat = 34
    static let transparentRouteHorizontalPadding: CGFloat = 24
    static let transparentTextSpacing: CGFloat = 11
    static let transparentMetricSpacing: CGFloat = 12
    static let transparentMetricColumnSpacing: CGFloat = 24
    static let transparentFooterTopPadding: CGFloat = 22
    static let transparentRouteNaturalBoundingBox = CGSize(width: 0.74, height: 0.56)
    static let statSummaryMissingMetricPlaceholder = "—"

    static func aspectFittedTransparentRouteSize(in availableSize: CGSize) -> CGSize {
        let boundedWidth = max(availableSize.width - SOOMRouteRenderingStyle.shareTransparentOuterLineWidth * 2, 1)
        let boundedHeight = max(availableSize.height - SOOMRouteRenderingStyle.shareTransparentOuterLineWidth * 2, 1)
        let scaleFactor = min(
            boundedWidth / transparentRouteNaturalBoundingBox.width,
            boundedHeight / transparentRouteNaturalBoundingBox.height
        )

        return CGSize(
            width: transparentRouteNaturalBoundingBox.width * scaleFactor,
            height: transparentRouteNaturalBoundingBox.height * scaleFactor
        )
    }
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
                    .stroke(SOOMColor.black.opacity(0.24), style: StrokeStyle(lineWidth: 6.8, lineCap: .round, lineJoin: .round))
                    .blur(radius: 0.4)
            } else {
                RouteRibbonShape()
                    .stroke(SOOMColor.black.opacity(0.18), style: StrokeStyle(lineWidth: 5.8, lineCap: .round, lineJoin: .round))
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
            return SOOMRouteRenderingStyle.accentColor.opacity(0.42)
        }
    }

    private var innerLineColor: Color {
        switch style {
        case .transparent:
            return SOOMRouteRenderingStyle.accentColor.opacity(0.96)
        case .mapPhoto:
            return SOOMRouteRenderingStyle.accentColor.opacity(0.92)
        case .fallback:
            return SOOMColor.white.opacity(0.70)
        }
    }

    private var outerLineWidth: CGFloat {
        style == .transparent
            ? SOOMRouteRenderingStyle.shareTransparentOuterLineWidth
            : SOOMRouteRenderingStyle.shareOuterLineWidth
    }

    private var innerLineWidth: CGFloat {
        style == .transparent
            ? SOOMRouteRenderingStyle.shareTransparentInnerLineWidth
            : SOOMRouteRenderingStyle.shareInnerLineWidth
    }

    private var endpointColor: Color {
        style == .transparent ? SOOMRouteRenderingStyle.accentColor : SOOMColor.white
    }

    private var endpointHaloColor: Color {
        style == .transparent ? SOOMColor.white : SOOMRouteRenderingStyle.accentColor
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
