import Foundation

enum ShareCardType: String, CaseIterable, Identifiable, Equatable {
    case workout
    case recovery
    case route
    case club

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout:
            return "운동"
        case .recovery:
            return "컨디션"
        case .route:
            return "코스"
        case .club:
            return "클럽"
        }
    }

    var cardTitle: String {
        "\(title) 카드"
    }

    var icon: String {
        switch self {
        case .workout:
            return SOOMIcon.record
        case .recovery:
            return SOOMIcon.recovery
        case .route:
            return SOOMIcon.map
        case .club:
            return SOOMIcon.clubs
        }
    }

    var defaultVisibility: ShareableWorkoutVisibility {
        switch self {
        case .recovery:
            return .privateOnly
        case .workout, .route, .club:
            return .privateOnly
        }
    }
}

enum ShareCardBackgroundOption: String, CaseIterable, Identifiable, Equatable {
    case mapPhoto
    case transparent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mapPhoto:
            return "지도/사진"
        case .transparent:
            return "투명"
        }
    }

    var caption: String {
        switch self {
        case .mapPhoto:
            return "지도나 사진 위에 SOOM 카드 톤을 얹어요."
        case .transparent:
            return "배경을 비워 스토리 편집에 얹기 쉽게 만들어요."
        }
    }

    var usesCheckerboardPreview: Bool {
        self == .transparent
    }

    var includesCheckerboardInExport: Bool {
        false
    }

    var includesBackgroundInExport: Bool {
        self == .mapPhoto
    }
}

enum ShareTarget: String, CaseIterable, Identifiable, Equatable {
    case instagramStory
    case saveImage
    case more

    var id: String { rawValue }

    static let currentTargets: [ShareTarget] = [
        .instagramStory,
        .saveImage,
        .more
    ]

    var title: String {
        switch self {
        case .instagramStory:
            return "Instagram으로 공유"
        case .saveImage:
            return "Save Image"
        case .more:
            return "More"
        }
    }

    var icon: String {
        switch self {
        case .instagramStory:
            return SOOMIcon.sparkles
        case .saveImage:
            return "square.and.arrow.down"
        case .more:
            return SOOMIcon.more
        }
    }

    var usesSystemShareSheet: Bool {
        true
    }
}

enum ShareCardComposerStep: Int, CaseIterable, Equatable {
    case previewCarousel
    case background
    case targets
}

enum ShareCardComposerPresentationStyle: Equatable {
    case bottomSheet
}

enum ShareCardComposerSelectionMode: Equatable {
    case swipeCarousel
}

enum ShareCardComposerLayout {
    static let presentationStyle: ShareCardComposerPresentationStyle = .bottomSheet
    static let selectionMode: ShareCardComposerSelectionMode = .swipeCarousel
    static let cardOrder: [ShareCardType] = [
        .workout,
        .recovery,
        .route,
        .club
    ]
    static let orderedSteps: [ShareCardComposerStep] = [
        .previewCarousel,
        .background,
        .targets
    ]

    static func cardType(at index: Int) -> ShareCardType {
        guard cardOrder.indices.contains(index) else { return cardOrder[0] }
        return cardOrder[index]
    }

    static func index(for type: ShareCardType) -> Int {
        cardOrder.firstIndex(of: type) ?? 0
    }
}

enum ShareCardLayoutVariant: String, CaseIterable, Equatable {
    case routeHero
    case routeTopMetricsBottom
    case routeLeftTextRight
    case routeCenteredStats
    case transparentOverlay
}

enum ShareableWorkoutVisibility: String, Equatable {
    case privateOnly
    case followers
    case publicFeed

    var title: String {
        switch self {
        case .privateOnly:
            return "나만 보기"
        case .followers:
            return "팔로워"
        case .publicFeed:
            return "공개 피드"
        }
    }
}

struct ShareCardMetric: Equatable {
    let label: String
    let value: String
}

struct ShareableWorkoutCardModel: Identifiable, Equatable {
    let id: UUID
    let shareType: ShareCardType
    let backgroundOption: ShareCardBackgroundOption
    let workoutType: UnifiedWorkoutType
    let title: String
    let distanceText: String
    let durationText: String
    let primaryMessage: String
    let growthMessage: String
    let recoveryMessage: String
    let footerText: String
    let visibility: ShareableWorkoutVisibility
    let staticRoutePreview: StaticRoutePreview?
    let averagePaceText: String?
    let elevationGainText: String?
    let layoutVariant: ShareCardLayoutVariant

    var hasRoutePreviewPayload: Bool {
        staticRoutePreview?.routeExists == true
    }

    var isRouteBasedWorkout: Bool {
        switch workoutType {
        case .running, .cycling, .walking, .hiking:
            return true
        case .swimming, .strength, .yoga, .other:
            return false
        }
    }

    var shouldShowRouteVisual: Bool {
        hasRoutePreviewPayload || (isRouteBasedWorkout && (shareType == .workout || shareType == .route))
    }

    var shouldShowRouteLineInTransparentExport: Bool {
        hasRoutePreviewPayload
    }

    var layoutVariants: [ShareCardLayoutVariant] {
        switch shareType {
        case .workout:
            return [.routeHero, .routeTopMetricsBottom, .routeCenteredStats]
        case .route:
            return [.routeTopMetricsBottom, .routeLeftTextRight, .routeHero]
        case .recovery:
            return [.routeCenteredStats]
        case .club:
            return [.routeCenteredStats]
        }
    }

    var exportLayoutVariant: ShareCardLayoutVariant {
        backgroundOption == .transparent ? .transparentOverlay : layoutVariant
    }

    var publicMetrics: [ShareCardMetric] {
        switch workoutType {
        case .cycling:
            return [
                ShareCardMetric(label: "거리", value: compactDistanceText),
                ShareCardMetric(label: "시간", value: compactDurationText),
                ShareCardMetric(label: "고도", value: elevationGainText ?? "0m")
            ]
        case .running:
            return [
                ShareCardMetric(label: "거리", value: compactDistanceText),
                ShareCardMetric(label: "페이스", value: normalizedPaceText ?? "-"),
                ShareCardMetric(label: "시간", value: compactDurationText)
            ]
        case .walking:
            return [
                ShareCardMetric(label: "거리", value: compactDistanceText),
                ShareCardMetric(label: "시간", value: compactDurationText)
            ]
        default:
            return [
                ShareCardMetric(label: "거리", value: compactDistanceText),
                ShareCardMetric(label: "시간", value: compactDurationText)
            ]
        }
    }

    var compactPublicMetricLine: String {
        let metrics = publicMetrics
        switch workoutType {
        case .cycling:
            return metrics.dropFirst().map(\.value).joined(separator: " · ")
        case .running:
            return metrics.dropFirst().map(\.value).joined(separator: " · ")
        case .walking:
            return metrics.dropFirst().map(\.value).joined(separator: " · ")
        default:
            return metrics.dropFirst().map(\.value).joined(separator: " · ")
        }
    }

    var storyHeadline: String {
        switch shareType {
        case .workout:
            return compactDistanceText
        case .recovery:
            return "좋음"
        case .route:
            return "한강 북단"
        case .club:
            return "SOOM Riders"
        }
    }

    var storyInterpretation: String {
        switch shareType {
        case .workout:
            return "리듬을 잃지 않은 날"
        case .recovery:
            return "밀어도 되는 날"
        case .route:
            return "좋은 바람이 있던 날"
        case .club:
            return "이번 주 12위"
        }
    }

    var storySupportingText: String {
        switch shareType {
        case .workout:
            let metricLine = compactPublicMetricLine
            guard metricLine.isEmpty == false else {
                return workoutType.shareDisplayName
            }
            return "\(metricLine) · \(workoutType.shareDisplayName)"
        case .recovery:
            return "82"
        case .route:
            return "\(compactDistanceText) · 강변 코스"
        case .club:
            return "42.6km 기여"
        }
    }

    var signatureLine: String {
        switch shareType {
        case .workout:
            return "페이스는 숨에서"
        case .recovery:
            return "숨부터 잡아라"
        case .route:
            return "길보다 리듬"
        case .club:
            return "함께 쌓은 리듬"
        }
    }

    var signatureFooterText: String {
        "\(signatureLine) · SOOM"
    }

    var compactDistanceText: String {
        let trimmed = distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(" km") else { return trimmed }

        let numberText = trimmed.replacingOccurrences(of: " km", with: "")
        guard let value = Double(numberText) else {
            return trimmed.replacingOccurrences(of: " km", with: "km")
        }

        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))km"
        }
        return String(format: "%.1fkm", rounded)
    }

    var compactDurationText: String {
        let trimmed = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
            .replacingOccurrences(of: "시간 ", with: "h ")
            .replacingOccurrences(of: "시간", with: "h")
            .replacingOccurrences(of: "분", with: "m")
    }

    var normalizedPaceText: String? {
        guard let averagePaceText,
              averagePaceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        let trimmed = averagePaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("/km") else { return trimmed }
        let value = trimmed.replacingOccurrences(of: "/km", with: "")
        let components = value.split(separator: ":")
        guard components.count == 2,
              let minutes = components.first,
              let seconds = components.last else {
            return trimmed
        }

        return "\(minutes)'\(seconds)\"/km"
    }

    init(
        id: UUID,
        shareType: ShareCardType = .workout,
        backgroundOption: ShareCardBackgroundOption = .mapPhoto,
        workoutType: UnifiedWorkoutType,
        title: String,
        distanceText: String,
        durationText: String,
        averagePaceText: String? = nil,
        elevationGainText: String? = nil,
        primaryMessage: String,
        growthMessage: String,
        recoveryMessage: String,
        footerText: String,
        visibility: ShareableWorkoutVisibility,
        staticRoutePreview: StaticRoutePreview? = nil,
        layoutVariant: ShareCardLayoutVariant? = nil
    ) {
        self.id = id
        self.shareType = shareType
        self.backgroundOption = backgroundOption
        self.workoutType = workoutType
        self.title = title
        self.distanceText = distanceText
        self.durationText = durationText
        self.averagePaceText = averagePaceText
        self.elevationGainText = elevationGainText
        self.primaryMessage = primaryMessage
        self.growthMessage = growthMessage
        self.recoveryMessage = recoveryMessage
        self.footerText = footerText
        self.visibility = visibility
        self.staticRoutePreview = staticRoutePreview
        self.layoutVariant = layoutVariant ?? Self.defaultLayoutVariant(shareType: shareType)
    }

    func configured(
        shareType: ShareCardType,
        backgroundOption: ShareCardBackgroundOption,
        visibility requestedVisibility: ShareableWorkoutVisibility? = nil
    ) -> ShareableWorkoutCardModel {
        let resolvedVisibility = requestedVisibility ?? shareType.defaultVisibility
        let content = ShareCardPrivacyPolicy.publicContent(
            base: self,
            shareType: shareType,
            visibility: resolvedVisibility
        )

        return ShareableWorkoutCardModel(
            id: id,
            shareType: shareType,
            backgroundOption: backgroundOption,
            workoutType: workoutType,
            title: content.title,
            distanceText: distanceText,
            durationText: durationText,
            averagePaceText: averagePaceText,
            elevationGainText: elevationGainText,
            primaryMessage: content.primaryMessage,
            growthMessage: content.growthMessage,
            recoveryMessage: content.recoveryMessage,
            footerText: content.footerText,
            visibility: resolvedVisibility,
            staticRoutePreview: staticRoutePreview,
            layoutVariant: Self.defaultLayoutVariant(shareType: shareType)
        )
    }

    private static func defaultLayoutVariant(shareType: ShareCardType) -> ShareCardLayoutVariant {
        switch shareType {
        case .workout:
            return .routeHero
        case .route:
            return .routeTopMetricsBottom
        case .recovery, .club:
            return .routeCenteredStats
        }
    }
}

extension UnifiedWorkoutType {
    var shareDisplayName: String {
        switch self {
        case .running:
            return "러닝"
        case .cycling:
            return "라이딩"
        case .walking:
            return "걷기"
        case .swimming:
            return "수영"
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

enum ShareCardPrivacyPolicy {
    struct PublicContent: Equatable {
        let title: String
        let primaryMessage: String
        let growthMessage: String
        let recoveryMessage: String
        let footerText: String
    }

    static func publicContent(
        base: ShareableWorkoutCardModel,
        shareType: ShareCardType,
        visibility: ShareableWorkoutVisibility
    ) -> PublicContent {
        switch shareType {
        case .workout:
            return PublicContent(
                title: base.title,
                primaryMessage: base.primaryMessage,
                growthMessage: base.growthMessage,
                recoveryMessage: sanitizedRecoveryMessage(
                    original: base.recoveryMessage,
                    shareType: shareType,
                    visibility: visibility
                ),
                footerText: footerText(type: shareType, visibility: visibility)
            )
        case .recovery:
            return PublicContent(
                title: "컨디션 카드",
                primaryMessage: visibility == .privateOnly
                    ? "82 · 좋음"
                    : "오늘 상태를 가볍게 남겼어요.",
                growthMessage: visibility == .privateOnly
                    ? "오늘은 밀어도 되는 날."
                    : "공개 카드에는 민감한 컨디션 상세를 담지 않아요.",
                recoveryMessage: sanitizedRecoveryMessage(
                    original: base.recoveryMessage,
                    shareType: shareType,
                    visibility: visibility
                ),
                footerText: footerText(type: shareType, visibility: visibility)
            )
        case .route:
            return PublicContent(
                title: "오늘의 코스",
                primaryMessage: "움직인 길의 분위기를 가볍게 남겼어요.",
                growthMessage: "시작과 끝 지점은 기본으로 조심스럽게 가려요.",
                recoveryMessage: "개인 회복 코칭은 이 카드에 포함하지 않아요.",
                footerText: footerText(type: shareType, visibility: visibility)
            )
        case .club:
            return PublicContent(
                title: "클럽 리듬",
                primaryMessage: "함께 쌓은 움직임을 조용히 공유해요.",
                growthMessage: "랭킹보다 참여와 기여의 흐름을 먼저 보여줘요.",
                recoveryMessage: "개인 회복 상태는 클럽 카드에 포함하지 않아요.",
                footerText: footerText(type: shareType, visibility: visibility)
            )
        }
    }

    static func sanitizedRecoveryMessage(
        original: String,
        shareType: ShareCardType,
        visibility: ShareableWorkoutVisibility
    ) -> String {
        guard shareType == .recovery || visibility == .publicFeed else {
            return original
        }

        if shareType == .recovery, visibility == .privateOnly {
            return "무리하지 않아도 좋아요."
        }

        return "개인 컨디션과 코칭 상세는 공개 카드에서 제외돼요."
    }

    private static func footerText(
        type: ShareCardType,
        visibility: ShareableWorkoutVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "SOOM · \(type.title) 공유 전 미리보기"
        case .followers:
            return "SOOM · \(type.title) 팔로워 공유 예정"
        case .publicFeed:
            return "SOOM · \(type.title) 공개 공유 예정"
        }
    }
}
