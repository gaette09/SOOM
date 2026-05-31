import SwiftUI

struct FeedItemCard: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, 16)

            titleBlock
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, 14)

            mediaPreview
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, 14)

            metricsBlock
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, 14)

            tagsAndReactions
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, 16)

            actionBar
                .padding(.horizontal, SOOMLayout.Card.padding)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.10), lineWidth: SOOMLayout.Card.borderWidth)
        }
        .shadow(color: SOOMColor.black.opacity(0.035), radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.authorName)의 \(item.itemType.title) 피드")
        .accessibilityValue(accessibilitySummary)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))

                Text(initial)
                    .font(SOOMFont.displayMedium(15, relativeTo: .caption))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.authorName)
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(1)

                    Text(feedTypeText)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Text(relativeTimeText)
                    Text("·")
                    Text(item.locationHint ?? "근처 코스")
                }
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let label = item.contextLabels.first {
                FeedReferenceContextPill(label: label, tint: tint)
            }

            Button(action: {}) {
                Image(systemName: SOOMIcon.more)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("피드 더보기")
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(feedTitle)
                .font(SOOMFont.displayMedium(21, relativeTo: .title3))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.88)

            Text(feedBody)
                .font(SOOMFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                FeedReferenceMetric(label: averageMetricLabel(for: card), value: averageMetricText(for: card)),
                FeedReferenceMetric(label: "평균 심박", value: averageHeartRateText(for: card))
            ])
        case .weeklyProgress(let card):
            FeedReferenceMetricGrid(metrics: [
                FeedReferenceMetric(label: "운동", value: card.workoutCountText),
                FeedReferenceMetric(label: "거리", value: card.totalDistanceText),
                FeedReferenceMetric(label: "시간", value: card.totalDurationText),
                FeedReferenceMetric(label: "흐름", value: "안정")
            ])
        }
    }

    private var tagsAndReactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if feedTags.isEmpty == false {
                HStack(spacing: 7) {
                    ForEach(feedTags.prefix(4), id: \.self) { tag in
                        FeedReferenceTag(title: tag, tint: tint)
                    }

                    Spacer(minLength: 0)
                }
            }

            if item.reactions.isEmpty == false || item.microComment != nil {
                HStack(spacing: 8) {
                    ForEach(item.reactions.prefix(3)) { reaction in
                        Text(reaction.symbol)
                            .font(.system(size: 16))
                            .frame(width: 26, height: 26)
                            .background(SOOMColor.surfaceMuted)
                            .clipShape(Circle())
                            .accessibilityLabel("\(reaction.label) 반응")
                    }

                    if let microComment = item.microComment {
                        Text(microComment)
                            .font(SOOMFont.body(12, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            FeedReferenceAction(icon: SOOMIcon.thumbsUp, title: "응원하기")
            Spacer()
            FeedReferenceAction(icon: SOOMIcon.comment, title: "댓글 남기기")
            Spacer()
            FeedReferenceAction(icon: SOOMIcon.bookmark, title: "저장")
        }
        .padding(.top, 12)
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

    private var initial: String {
        String(item.authorName.prefix(1))
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

    private var feedTags: [String] {
        var tags: [String] = []

        if let mood = item.movementMood {
            tags.append(mood)
        }

        if let location = item.locationHint {
            tags.append(location)
        }

        if let routeMood = item.routeMood {
            tags.append(trimmedCopy(routeMood, limit: 8))
        }

        tags.append(contentsOf: item.contextLabels.map(\.title))

        return Array(NSOrderedSet(array: tags).compactMap { $0 as? String })
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

    private func averageMetricLabel(for card: ShareableWorkoutCardModel) -> String {
        switch card.workoutType {
        case .cycling:
            return "평균 속도"
        default:
            return "평균 페이스"
        }
    }

    private func averageMetricText(for card: ShareableWorkoutCardModel) -> String {
        switch card.workoutType {
        case .running:
            return "5'02\""
        case .cycling:
            return "20.7km/h"
        case .swimming:
            return "2'04\""
        case .walking:
            return "10'20\""
        case .hiking:
            return "14'10\""
        case .strength, .yoga, .other:
            return "안정"
        }
    }

    private func averageHeartRateText(for card: ShareableWorkoutCardModel) -> String {
        switch card.workoutType {
        case .running:
            return "142bpm"
        case .cycling:
            return "128bpm"
        case .swimming:
            return "136bpm"
        case .walking:
            return "112bpm"
        case .hiking:
            return "124bpm"
        case .strength, .yoga, .other:
            return "가벼움"
        }
    }
}

private struct FeedReferenceMediaPreview: View {
    @State private var selectedPhotoIndex = 0

    let routeStyle: StaticRouteFallbackStyle
    let routeExists: Bool
    let distanceText: String
    let routeLabel: String
    let photos: [FeedPhotoPlaceholder]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let gap: CGFloat = photos.isEmpty ? 0 : 9
            let idealPhotoWidth = availableWidth * 0.38
            let maxPhotoWidth = max(availableWidth - gap - 144, 0)
            let photoWidth = photos.isEmpty ? 0 : min(max(idealPhotoWidth, 108), maxPhotoWidth)

            HStack(spacing: gap) {
                FeedReferenceRoutePreview(
                    routeStyle: routeStyle,
                    routeExists: routeExists,
                    distanceText: distanceText,
                    routeLabel: routeLabel,
                    tint: tint
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if photos.isEmpty == false {
                    photoPreview
                        .frame(width: photoWidth, height: proxy.size.height)
                }
            }
        }
        .frame(height: mediaHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(photos.isEmpty ? "지도 경로 미리보기" : "지도와 사진 미리보기")
    }

    private var mediaHeight: CGFloat {
        return 194
    }

    private var photoPreview: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedPhotoIndex) {
                ForEach(photos.indices, id: \.self) { index in
                    FeedReferencePhotoSurface(photo: photos[index], tint: tint)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if photos.count > 1 {
                Text("\(min(selectedPhotoIndex + 1, photos.count)) / \(photos.count)")
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(SOOMColor.black.opacity(0.48))
                    .clipShape(Capsule())
                    .padding(9)
                    .accessibilityLabel("\(selectedPhotoIndex + 1)번째 사진, 총 \(photos.count)장")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct FeedReferenceRoutePreview: View {
    let routeStyle: StaticRouteFallbackStyle
    let routeExists: Bool
    let distanceText: String
    let routeLabel: String
    let tint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            routeBackground
            routeMapCanvas

            FeedReferenceRouteLine(style: routeStyle)
                .stroke(SOOMColor.white.opacity(0.92), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, 20)
                .padding(.vertical, 26)

            FeedReferenceRouteLine(style: routeStyle)
                .stroke(tint.opacity(routeExists ? 0.92 : 0.74), style: StrokeStyle(lineWidth: 3.8, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, 20)
                .padding(.vertical, 26)

            routeEndpoint(isStart: true)
            routeEndpoint(isStart: false)

            Text(distanceText)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(SOOMColor.white.opacity(0.92))
                .clipShape(Capsule())
                .padding(9)

            VStack {
                Spacer()
                HStack {
                    Text(trimmedLabel(routeLabel))
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.ink.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(SOOMColor.white.opacity(0.90))
                        .clipShape(Capsule())

                    Spacer(minLength: 0)
                }
                .padding(9)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.12), lineWidth: 1)
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
}

private struct FeedReferencePhotoSurface: View {
    let photo: FeedPhotoPlaceholder
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            photo.photoGradient(tint: tint)

            photoArtwork

            Text(photo.title)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(SOOMColor.black.opacity(0.34))
                .clipShape(Capsule())
                .padding(9)
        }
    }

    private var photoArtwork: some View {
        ZStack {
            Circle()
                .fill(SOOMColor.white.opacity(0.18))
                .frame(width: 114, height: 114)
                .offset(x: 40, y: -70)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(SOOMColor.white.opacity(0.16))
                .frame(width: 120, height: 88)
                .rotationEffect(.degrees(-8))
                .offset(x: 34, y: 24)

            Image(systemName: photo.tone.mediaIcon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SOOMColor.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
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

private struct FeedReferenceMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct FeedReferenceMetricGrid: View {
    let metrics: [FeedReferenceMetric]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.label)
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .lineLimit(1)

                    Text(metric.value)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(SOOMColor.surfaceAmbient)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct FeedReferenceContextPill: View {
    let label: FeedContextLabel
    let tint: Color

    var body: some View {
        Text(label.title)
            .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.accentInk)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(SOOMColor.accentSurface)
            .clipShape(Capsule())
    }
}

private struct FeedReferenceTag: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.secondaryInk)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(SOOMColor.surfaceMuted)
            .clipShape(Capsule())
    }
}

private struct FeedReferenceAction: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
            .foregroundStyle(SOOMColor.secondaryInk)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}

private extension FeedPhotoPlaceholder {
    func photoGradient(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: colors(tint: tint),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func colors(tint: Color) -> [Color] {
        switch tone {
        case .morning:
            return [Color(hex: 0xC78A55), Color(hex: 0x6D8C6C), tint.opacity(0.72)]
        case .city:
            return [Color(hex: 0x566B79), Color(hex: 0x9A735A), tint.opacity(0.70)]
        case .trail:
            return [Color(hex: 0x496B5B), Color(hex: 0x8E7B4E), SOOMColor.warning.opacity(0.54)]
        case .water:
            return [SOOMColor.swim.opacity(0.86), Color(hex: 0x4F7167), tint.opacity(0.64)]
        }
    }
}

private extension FeedPhotoTone {
    var mediaIcon: String {
        switch self {
        case .water:
            return SOOMIcon.waveform
        default:
            return SOOMIcon.sparkles
        }
    }
}

private extension UnifiedWorkoutType {
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
