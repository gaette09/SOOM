import SwiftUI

struct FeedItemCard: View {
    let item: FeedItem
    var isOwnPost: Bool = false
    var onToggleCheer: () -> Void = {}
    var onSubmitComment: (String) -> Void = { _ in }
    var onDeletePost: () -> Void = {}

    @State private var isComposingComment = false
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, SOOMLayout.Spacing.lg)

            titleBlock
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, SOOMLayout.Spacing.md)

            mediaPreview
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, SOOMLayout.Spacing.md)

            metricsBlock
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, SOOMLayout.Spacing.md)

            actionBar
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, SOOMLayout.Spacing.md)
                .padding(.bottom, SOOMLayout.Spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.black.opacity(0.08), lineWidth: SOOMLayout.Card.borderWidth)
        }
        .shadow(color: SOOMColor.black.opacity(0.07), radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.authorName)의 \(item.itemType.title) 피드")
        .accessibilityValue(accessibilitySummary)
        .confirmationDialog(
            "이 게시물을 삭제할까요?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive, action: onDeletePost)
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제하면 되돌릴 수 없어요.")
        }
        .sheet(isPresented: $isComposingComment) {
            FeedCommentComposeSheet { body in
                onSubmitComment(body)
            }
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            FeedProfileAvatar()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.authorName)
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(1)

                    Text(feedTypeText)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Text(relativeTimeText)
                }
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isOwnPost {
                Button {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: SOOMIcon.more)
                        .font(.system(size: SOOMFont.Size.body, weight: .semibold))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("피드 더보기")
            }
        }
    }

    private var titleBlock: some View {
        Text(feedTitle)
            .font(SOOMFont.displayMedium(19, relativeTo: .headline))
            .foregroundStyle(SOOMColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.86)
    }

    @ViewBuilder
    private var mediaPreview: some View {
        switch item.cardData {
        case .workoutSession(let card):
            FeedReferenceMediaPreview(
                routeStyle: card.staticRoutePreview?.fallbackStyle ?? StaticRouteFallbackStyle(workoutType: card.workoutType),
                routeExists: card.staticRoutePreview?.routeExists == true,
                distanceText: card.distanceText,
                routeLabel: item.routeMood ?? "\(card.workoutType.feedShortTitle) route",
                photos: item.photoPlaceholders,
                tint: tint
            )
        case .weeklyProgress:
            FeedReferenceMediaPreview(
                routeStyle: .generic,
                routeExists: false,
                distanceText: "이번 주",
                routeLabel: item.routeMood ?? "반복된 루틴",
                photos: item.photoPlaceholders,
                tint: tint
            )
        }
    }

    @ViewBuilder
    private var metricsBlock: some View {
        switch item.cardData {
        case .workoutSession(let card):
            FeedReferenceMetricGrid(metrics: [
                FeedReferenceMetric(label: "거리", value: card.distanceText),
                FeedReferenceMetric(label: "시간", value: card.durationText),
                FeedReferenceMetric(label: speedOrPaceLabel(for: card), value: card.averagePaceText ?? "-"),
                FeedReferenceMetric(label: "획득 고도", value: card.elevationGainText ?? "-")
            ])
        case .weeklyProgress(let card):
            FeedReferenceMetricGrid(metrics: [
                FeedReferenceMetric(label: "운동", value: card.workoutCountText),
                FeedReferenceMetric(label: "거리", value: card.totalDistanceText),
                FeedReferenceMetric(label: "시간", value: card.totalDurationText)
            ])
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(action: onToggleCheer) {
                FeedReferenceAction(
                    icon: item.viewerHasCheered ? "hands.clap.fill" : "hands.clap",
                    title: "응원",
                    isProminent: item.viewerHasCheered
                )
            }
            .buttonStyle(.plain)
            .disabled(item.isLocalDraft)
            .accessibilityAddTraits(item.viewerHasCheered ? [.isSelected] : [])

            Spacer()

            Button {
                isComposingComment = true
            } label: {
                FeedReferenceAction(icon: SOOMIcon.comment, title: "댓글")
            }
            .buttonStyle(.plain)
            .disabled(item.isLocalDraft)

            Spacer()
            FeedReferenceAction(icon: SOOMIcon.bookmark, title: "저장", isProminent: true)
        }
        .padding(.top, SOOMLayout.Spacing.md)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SOOMColor.line.opacity(0.12))
                .frame(height: 1)
        }
    }

    private var tint: Color {
        switch item.cardData {
        case .workoutSession(let card):
            return card.workoutType.feedTint
        case .weeklyProgress:
            return SOOMColor.accent
        }
    }

    private var feedTypeText: String {
        switch item.cardData {
        case .workoutSession(let card):
            return card.workoutType.feedShortTitle
        case .weeklyProgress:
            return "주간 기록"
        }
    }

    private var feedTitle: String {
        switch item.cardData {
        case .workoutSession(let card):
            return item.activityContext.isEmpty ? card.title : item.activityContext
        case .weeklyProgress(let card):
            return item.activityContext.isEmpty ? card.weekLabel : item.activityContext
        }
    }

    private var feedBody: String {
        let source = item.caption ?? item.optionalShortStory ?? item.emotionalContext ?? fallbackMessage
        return trimmedCopy(source, limit: 54)
    }

    private var fallbackMessage: String {
        switch item.cardData {
        case .workoutSession(let card):
            return card.primaryMessage
        case .weeklyProgress(let card):
            return card.progressMessage
        }
    }

    private var relativeTimeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.createdAt, relativeTo: Date(timeIntervalSince1970: 1_800_480_000))
    }

    private var accessibilitySummary: String {
        switch item.cardData {
        case .workoutSession(let card):
            return "\(feedTitle). \(card.distanceText), \(card.durationText). \(feedBody)"
        case .weeklyProgress(let card):
            return "\(feedTitle). \(card.workoutCountText), \(card.totalDistanceText), \(card.totalDurationText). \(feedBody)"
        }
    }

    private func trimmedCopy(_ value: String, limit: Int) -> String {
        let line = value.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? value
        guard line.count > limit else {
            return line
        }
        return "\(line.prefix(limit))..."
    }

    private func speedOrPaceLabel(for card: ShareableWorkoutCardModel) -> String {
        switch card.workoutType {
        case .running:
            return "페이스"
        case .cycling, .walking, .hiking:
            return "속도"
        case .swimming:
            return "페이스"
        case .strength, .yoga, .other:
            return "페이스"
        }
    }

}

struct FeedProfileAvatar: View {
    var body: some View {
        Circle()
            .fill(SOOMColor.surfaceMuted)
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: SOOMIcon.profile)
                    .font(.system(size: SOOMFont.Size.headline, weight: .regular))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }
            .overlay {
                Circle()
                    .stroke(SOOMColor.black.opacity(0.06), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct FeedReferenceMediaPreview: View {
    let routeStyle: StaticRouteFallbackStyle
    let routeExists: Bool
    let distanceText: String
    let routeLabel: String
    let photos: [FeedPhotoPlaceholder]
    let tint: Color

    var body: some View {
        FeedReferenceRoutePreview(
            routeStyle: routeStyle,
            routeExists: routeExists,
            route: FeedPreviewRouteFactory.route(style: routeStyle, distanceText: distanceText),
            distanceText: distanceText,
            routeLabel: routeLabel,
            photoCount: photos.count,
            tint: tint
        )
        .frame(height: mediaHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(photos.isEmpty ? "지도 경로 미리보기" : "지도 경로 미리보기, 사진 \(photos.count)장")
    }

    private var mediaHeight: CGFloat {
        return 216
    }
}

private enum FeedPreviewRouteFactory {
    static func route(style: StaticRouteFallbackStyle, distanceText: String) -> WorkoutRoute? {
        let points = coordinates(for: style)
        guard points.count >= 2 else { return nil }

        return WorkoutRoute(
            workoutId: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            source: .soomLocal,
            coordinates: points.map {
                WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            totalDistanceMeters: distanceMeters(from: distanceText),
            totalElevationGain: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_480_000)
        )
    }

    private static func coordinates(for style: StaticRouteFallbackStyle) -> [(latitude: Double, longitude: Double)] {
        switch style {
        case .cycling:
            return [
                (37.5262, 126.9058),
                (37.5314, 126.9189),
                (37.5226, 126.9384),
                (37.5168, 126.9632),
                (37.5228, 126.9850),
                (37.5350, 127.0048),
                (37.5297, 127.0218)
            ]
        case .running:
            return [
                (37.5209, 127.1218),
                (37.5165, 127.1254),
                (37.5116, 127.1216),
                (37.5128, 127.1134),
                (37.5191, 127.1118),
                (37.5232, 127.1168)
            ]
        case .swimming:
            return [
                (37.5105, 127.0982),
                (37.5107, 127.1006),
                (37.5104, 127.1032),
                (37.5108, 127.1058)
            ]
        case .walking:
            return [
                (37.5794, 126.9769),
                (37.5781, 126.9810),
                (37.5752, 126.9836),
                (37.5728, 126.9802),
                (37.5746, 126.9758)
            ]
        case .generic:
            return [
                (37.5446, 127.0373),
                (37.5484, 127.0430),
                (37.5450, 127.0502),
                (37.5389, 127.0460),
                (37.5402, 127.0384)
            ]
        }
    }

    private static func distanceMeters(from text: String) -> Double {
        let normalized = text.lowercased().replacingOccurrences(of: ",", with: "")
        let number = normalized
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .first
            .flatMap { Double($0) } ?? 0

        if normalized.contains("km") {
            return number * 1_000
        }

        if normalized.contains("m") {
            return number
        }

        return max(number * 1_000, 1_000)
    }
}

private struct FeedReferenceRoutePreview: View {
    let routeStyle: StaticRouteFallbackStyle
    let routeExists: Bool
    let route: WorkoutRoute?
    let distanceText: String
    let routeLabel: String
    let photoCount: Int
    let tint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorkoutDetailMapView(
                route: route,
                fallbackStyle: routeStyle,
                tint: tint,
                routeLineWidth: SOOMRouteRenderingStyle.feedLineWidth
            )
                .allowsHitTesting(false)

            Text(distanceText)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .padding(.horizontal, SOOMLayout.Spacing.md)
                .padding(.vertical, SOOMLayout.Spacing.sm)
                .background(SOOMColor.white.opacity(0.94))
                .clipShape(Capsule())
                .padding(SOOMLayout.Spacing.md)

            if photoCount > 0 {
                HStack {
                    Spacer()

                    Label(photoCountText, systemImage: "camera")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.ink.opacity(0.78))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, SOOMLayout.Spacing.md)
                        .padding(.vertical, SOOMLayout.Spacing.sm)
                        .background(SOOMColor.white.opacity(0.90))
                        .clipShape(Capsule())
                        .padding(SOOMLayout.Spacing.md)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Text(trimmedLabel(routeLabel))
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.ink.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, SOOMLayout.Spacing.sm)
                        .padding(.vertical, SOOMLayout.Spacing.sm)
                        .background(SOOMColor.white.opacity(0.90))
                        .clipShape(Capsule())

                    Spacer(minLength: 0)
                }
                .padding(SOOMLayout.Spacing.md)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous)
                .stroke(SOOMColor.black.opacity(0.06), lineWidth: 1)
        }
    }

    private var routeBackground: LinearGradient {
        LinearGradient(
            colors: [
                SOOMColor.surfaceAmbient,
                SOOMColor.surfaceMuted.opacity(0.78),
                tint.opacity(0.13)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var routeMapCanvas: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)

            var water = Path()
            water.move(to: CGPoint(x: rect.width * 0.62, y: 0))
            water.addCurve(
                to: CGPoint(x: rect.width, y: rect.height * 0.68),
                control1: CGPoint(x: rect.width * 0.92, y: rect.height * 0.12),
                control2: CGPoint(x: rect.width * 0.78, y: rect.height * 0.48)
            )
            water.addLine(to: CGPoint(x: rect.width, y: 0))
            water.closeSubpath()
            context.fill(water, with: .color(SOOMColor.swim.opacity(0.16)))

            [
                CGRect(x: rect.width * 0.06, y: rect.height * 0.10, width: rect.width * 0.30, height: rect.height * 0.18),
                CGRect(x: rect.width * 0.50, y: rect.height * 0.68, width: rect.width * 0.34, height: rect.height * 0.15)
            ].forEach { park in
                context.fill(Path(roundedRect: park, cornerRadius: 18), with: .color(SOOMColor.green.opacity(0.15)))
            }

            let minorRoads: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 0.00, y: 0.36), CGPoint(x: 0.72, y: 0.18)),
                (CGPoint(x: 0.00, y: 0.56), CGPoint(x: 0.76, y: 0.43)),
                (CGPoint(x: 0.12, y: 0.92), CGPoint(x: 1.00, y: 0.62)),
                (CGPoint(x: 0.25, y: 0.00), CGPoint(x: 0.30, y: 1.00)),
                (CGPoint(x: 0.48, y: 0.00), CGPoint(x: 0.56, y: 0.92))
            ]

            minorRoads.forEach { start, end in
                var road = Path()
                road.move(to: CGPoint(x: rect.width * start.x, y: rect.height * start.y))
                road.addLine(to: CGPoint(x: rect.width * end.x, y: rect.height * end.y))
                context.stroke(road, with: .color(SOOMColor.white.opacity(0.82)), lineWidth: 7)
                context.stroke(road, with: .color(SOOMColor.ink.opacity(0.065)), lineWidth: 2)
            }

            [
                CGRect(x: rect.width * 0.10, y: rect.height * 0.42, width: rect.width * 0.13, height: rect.height * 0.08),
                CGRect(x: rect.width * 0.38, y: rect.height * 0.18, width: rect.width * 0.12, height: rect.height * 0.07),
                CGRect(x: rect.width * 0.62, y: rect.height * 0.48, width: rect.width * 0.14, height: rect.height * 0.09)
            ].forEach { block in
                context.fill(Path(roundedRect: block, cornerRadius: 7), with: .color(SOOMColor.ink.opacity(0.055)))
            }
        }
        .accessibilityHidden(true)
    }

    private func routeEndpoint(isStart: Bool) -> some View {
        GeometryReader { proxy in
            Circle()
                .fill(isStart ? SOOMColor.white : tint)
                .frame(width: 11, height: 11)
                .overlay {
                    Circle()
                        .stroke(tint, lineWidth: 1.7)
                }
                .position(endpointPosition(in: proxy.size, isStart: isStart))
        }
        .accessibilityHidden(true)
    }

    private func endpointPosition(in size: CGSize, isStart: Bool) -> CGPoint {
        if isStart {
            return CGPoint(x: size.width * 0.20, y: size.height * 0.70)
        }

        return CGPoint(x: size.width * 0.81, y: size.height * 0.36)
    }

    private func trimmedLabel(_ value: String) -> String {
        guard value.count > 16 else {
            return value
        }
        return "\(value.prefix(16))..."
    }

    private var photoCountText: String {
        if photoCount == 1 {
            return "사진 1"
        }
        return "사진 \(photoCount)"
    }
}

private struct FeedReferenceRouteLine: Shape {
    let style: StaticRouteFallbackStyle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = normalizedPoints.map { point in
            CGPoint(
                x: rect.minX + rect.width * point.x,
                y: rect.minY + rect.height * point.y
            )
        }

        guard let first = points.first else { return path }
        path.move(to: first)

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }

    private var normalizedPoints: [CGPoint] {
        switch style {
        case .running:
            return [
                CGPoint(x: 0.02, y: 0.72),
                CGPoint(x: 0.17, y: 0.50),
                CGPoint(x: 0.34, y: 0.58),
                CGPoint(x: 0.50, y: 0.30),
                CGPoint(x: 0.66, y: 0.46),
                CGPoint(x: 0.82, y: 0.25),
                CGPoint(x: 0.98, y: 0.38)
            ]
        case .cycling:
            return [
                CGPoint(x: 0.02, y: 0.62),
                CGPoint(x: 0.15, y: 0.42),
                CGPoint(x: 0.33, y: 0.40),
                CGPoint(x: 0.48, y: 0.68),
                CGPoint(x: 0.64, y: 0.56),
                CGPoint(x: 0.78, y: 0.34),
                CGPoint(x: 0.98, y: 0.30)
            ]
        case .swimming:
            return [
                CGPoint(x: 0.03, y: 0.55),
                CGPoint(x: 0.20, y: 0.44),
                CGPoint(x: 0.38, y: 0.57),
                CGPoint(x: 0.56, y: 0.44),
                CGPoint(x: 0.74, y: 0.57),
                CGPoint(x: 0.97, y: 0.46)
            ]
        case .walking:
            return [
                CGPoint(x: 0.02, y: 0.66),
                CGPoint(x: 0.22, y: 0.58),
                CGPoint(x: 0.34, y: 0.43),
                CGPoint(x: 0.54, y: 0.51),
                CGPoint(x: 0.72, y: 0.36),
                CGPoint(x: 0.98, y: 0.42)
            ]
        case .generic:
            return [
                CGPoint(x: 0.02, y: 0.60),
                CGPoint(x: 0.22, y: 0.44),
                CGPoint(x: 0.40, y: 0.52),
                CGPoint(x: 0.58, y: 0.38),
                CGPoint(x: 0.78, y: 0.50),
                CGPoint(x: 0.98, y: 0.34)
            ]
        }
    }
}

struct FeedReferenceMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct FeedReferenceMetricGrid: View {
    let metrics: [FeedReferenceMetric]

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: metrics.count),
            alignment: .leading,
            spacing: 0
        ) {
            ForEach(metrics) { metric in
                VStack(alignment: .center, spacing: 4) {
                    Text(metric.label)
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .lineLimit(1)
                        .frame(height: 12, alignment: .bottom)

                    Text(metric.value)
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(height: 19, alignment: .top)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, SOOMLayout.Spacing.md)
        .padding(.vertical, SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous)
                .stroke(SOOMColor.black.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct FeedReferenceAction: View {
    let icon: String
    let title: String
    var isProminent = false

    var body: some View {
        Label(title, systemImage: icon)
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(isProminent ? SOOMColor.ink : SOOMColor.secondaryInk)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, isProminent ? 10 : 0)
            .frame(minHeight: 28)
            .background {
                if isProminent {
                    Capsule(style: .continuous)
                        .fill(SOOMColor.surfaceMuted)
                }
            }
    }
}

extension UnifiedWorkoutType {
    var feedTint: Color {
        switch self {
        case .running:
            return SOOMColor.run
        case .cycling:
            return SOOMColor.bike
        case .swimming:
            return SOOMColor.swim
        case .walking, .hiking, .strength, .yoga, .other:
            return SOOMColor.green
        }
    }

    var feedShortTitle: String {
        switch self {
        case .running:
            return "러닝"
        case .cycling:
            return "라이딩"
        case .swimming:
            return "수영"
        case .walking:
            return "걷기"
        case .hiking:
            return "하이킹"
        case .strength:
            return "근력"
        case .yoga:
            return "요가"
        case .other:
            return "운동"
        }
    }
}

#Preview("FeedItemCard") {
    SOOMScreen {
        FeedItemCard(item: FeedMockData.items[0])
    }
    .preferredColorScheme(.light)
}
