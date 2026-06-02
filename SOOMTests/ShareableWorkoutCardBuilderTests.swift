import XCTest
@testable import SOOM

final class ShareableWorkoutCardBuilderTests: XCTestCase {
    private let builder = ShareableWorkoutCardBuilder()

    func testBuildCreatesCardFromSessionGrowthAndRecoveryImpact() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        XCTAssertEqual(card.id, growthInput.id)
        XCTAssertEqual(card.workoutType, .running)
        XCTAssertEqual(card.primaryMessage, sessionSummary.title)
        XCTAssertEqual(card.growthMessage, growthSummary.motivationText)
        XCTAssertEqual(card.recoveryMessage, recoveryImpact.shortMessage)
        XCTAssertFalse(card.footerText.isEmpty)
    }

    func testDistanceAndDurationTextAreFormattedForPreviewCard() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        XCTAssertEqual(card.distanceText, "10.40 km")
        XCTAssertEqual(card.durationText, "52분")
    }

    func testDefaultVisibilityIsPrivateOnly() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        XCTAssertEqual(card.visibility, .privateOnly)
        XCTAssertTrue(card.footerText.contains("미리보기"))
    }

    func testShareableCardDoesNotIncludeSensitiveHealthDataByDefault() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )
        let copy = [
            card.title,
            card.distanceText,
            card.durationText,
            card.primaryMessage,
            card.growthMessage,
            card.recoveryMessage,
            card.footerText
        ].joined(separator: " ")

        ["bpm", "심박", "회복 점수", "위치", "메모"].forEach { sensitiveWord in
            XCTAssertFalse(copy.contains(sensitiveWord), "Shareable card should not include sensitive data by default: \(sensitiveWord)")
        }
    }

    func testShareableCardCopyAvoidsNegativeOrCompetitiveTone() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )
        let copy = [
            card.primaryMessage,
            card.growthMessage,
            card.recoveryMessage,
            card.footerText
        ].joined(separator: " ")

        ["못", "실패", "나쁨", "위험", "랭킹", "순위", "이겼"].forEach { word in
            XCTAssertFalse(copy.contains(word), "Shareable card should keep a calm growth tone without '\(word)'.")
        }
    }

    func testRecoveryFriendlyImpactUsesGrowthSharingTone() {
        let recoveryFriendlyImpact = WorkoutRecoveryImpact(
            impactLevel: .recoveryFriendly,
            title: "회복 친화적인 운동",
            shortMessage: "가볍게 몸을 깨운 흐름이에요.",
            recommendation: "다음 운동도 몸 상태를 보면서 이어가보세요.",
            icon: SOOMIcon.recovery
        )

        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryFriendlyImpact,
            input: growthInput
        )

        XCTAssertTrue(card.recoveryMessage.contains("회복 흐름"))
        XCTAssertTrue(card.recoveryMessage.contains("좋은 강도"))
    }

    func testBuildCanAttachStaticRoutePreviewWithoutChangingPrivacyDefaults() {
        let preview = StaticRoutePreview(
            imageURL: URL(string: "https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/sample"),
            bounds: nil,
            routeExists: true,
            fallbackStyle: .running
        )

        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput,
            staticRoutePreview: preview
        )

        XCTAssertEqual(card.staticRoutePreview, preview)
        XCTAssertEqual(card.visibility, .privateOnly)
        XCTAssertFalse(card.footerText.contains("위치"))
    }

    func testShareCardTypeDefaultsIncludeRecoveryPrivateBoundary() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        let recoveryCard = card.configured(
            shareType: .recovery,
            backgroundOption: .mapPhoto
        )

        XCTAssertEqual(recoveryCard.shareType, .recovery)
        XCTAssertEqual(recoveryCard.visibility, .privateOnly)
        XCTAssertTrue(recoveryCard.footerText.contains("컨디션"))
        XCTAssertEqual(recoveryCard.title, "컨디션 카드")
        XCTAssertEqual(recoveryCard.primaryMessage, "82 · 좋음")
        XCTAssertEqual(recoveryCard.recoveryMessage, "무리하지 않아도 좋아요.")
    }

    func testPublicRecoveryCardExcludesFatigueAndReadinessCoachCopy() {
        let card = ShareableWorkoutCardModel(
            id: growthInput.id,
            workoutType: .running,
            title: "회복 상세",
            distanceText: "10.40 km",
            durationText: "52분",
            primaryMessage: "오늘은 리듬을 잘 이어간 운동이에요.",
            growthMessage: "조금씩 거리가 길어지고 있어요.",
            recoveryMessage: "fatigue와 readiness를 바탕으로 무리하지 마세요.",
            footerText: "SOOM · 공유 전 미리보기",
            visibility: .privateOnly
        )

        let publicRecoveryCard = card.configured(
            shareType: .recovery,
            backgroundOption: .transparent,
            visibility: .publicFeed
        )
        let copy = [
            publicRecoveryCard.primaryMessage,
            publicRecoveryCard.growthMessage,
            publicRecoveryCard.recoveryMessage
        ].joined(separator: " ")

        XCTAssertEqual(publicRecoveryCard.backgroundOption, .transparent)
        XCTAssertFalse(copy.contains("무리하지 마세요"))
        XCTAssertFalse(copy.contains("fatigue"))
        XCTAssertFalse(copy.contains("readiness"))
        XCTAssertTrue(copy.contains("공개 카드"))
    }

    func testCurrentShareTargetsHideCopyLinkUntilPublicURLBackendExists() {
        XCTAssertEqual(ShareTarget.currentTargets.map(\.title), [
            "Instagram으로 공유",
            "Save Image",
            "More"
        ])
        XCTAssertFalse(ShareTarget.currentTargets.map(\.title).contains("Copy Link"))
        XCTAssertFalse(ShareTarget.currentTargets.map(\.title).contains("Instagram Story"))
        XCTAssertTrue(ShareTarget.instagramStory.usesSystemShareSheet)
        XCTAssertTrue(ShareTarget.saveImage.usesSystemShareSheet)
        XCTAssertTrue(ShareTarget.more.usesSystemShareSheet)
    }

    func testShareCardOptionLabelsUseUserFacingCardCopy() {
        XCTAssertEqual(ShareCardType.workout.cardTitle, "운동 카드")
        XCTAssertEqual(ShareCardType.recovery.cardTitle, "컨디션 카드")
        XCTAssertEqual(ShareCardType.route.cardTitle, "코스 카드")
        XCTAssertEqual(ShareCardType.club.cardTitle, "클럽 카드")
    }

    func testShareComposerOrdersPreviewBeforeControls() {
        XCTAssertEqual(
            ShareCardComposerLayout.orderedSteps,
            [.previewCarousel, .background, .targets]
        )
    }

    func testShareComposerUsesBottomSheetCarouselOrder() {
        XCTAssertEqual(ShareCardComposerLayout.presentationStyle, .bottomSheet)
        XCTAssertEqual(ShareCardComposerLayout.selectionMode, .swipeCarousel)
        XCTAssertEqual(ShareCardComposerLayout.cardOrder, [.workout, .recovery, .route, .club])
    }

    func testShareComposerCardSelectionUpdatesByIndex() {
        XCTAssertEqual(ShareCardComposerLayout.cardType(at: 0), .workout)
        XCTAssertEqual(ShareCardComposerLayout.cardType(at: 1), .recovery)
        XCTAssertEqual(ShareCardComposerLayout.cardType(at: 2), .route)
        XCTAssertEqual(ShareCardComposerLayout.cardType(at: 3), .club)
        XCTAssertEqual(ShareCardComposerLayout.cardType(at: 99), .workout)
        XCTAssertEqual(ShareCardComposerLayout.index(for: .club), 3)
    }

    func testTransparentBackgroundUsesCheckerboardPreviewOnly() {
        XCTAssertFalse(ShareCardBackgroundOption.mapPhoto.usesCheckerboardPreview)
        XCTAssertTrue(ShareCardBackgroundOption.transparent.usesCheckerboardPreview)
        XCTAssertFalse(ShareCardBackgroundOption.mapPhoto.includesCheckerboardInExport)
        XCTAssertFalse(ShareCardBackgroundOption.transparent.includesCheckerboardInExport)
        XCTAssertTrue(ShareCardBackgroundOption.mapPhoto.includesBackgroundInExport)
        XCTAssertFalse(ShareCardBackgroundOption.transparent.includesBackgroundInExport)
        XCTAssertTrue(ShareableWorkoutCardLayout.transparentPreviewIncludesCheckerboard)
        XCTAssertTrue(ShareableWorkoutCardLayout.transparentPreviewIncludesBadge)
    }

    func testActivityDetailKeepsShareControlsOutOfInlineContent() {
        XCTAssertFalse(WorkoutDetailContent.showsInlineShareControls)
    }

    func testWorkoutShareCardVisualCopyIsConciseAndEmotionFirst() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        XCTAssertEqual(card.storyHeadline, "10.4km")
        XCTAssertEqual(card.storyInterpretation, "리듬을 잃지 않은 날")
        XCTAssertEqual(card.storySupportingText, "5'00\"/km · 52m · 러닝")
        XCTAssertFalse(ShareableWorkoutCardLayout.usesMetricGrid)
    }

    func testCyclingShareMetricSetUsesDistanceDurationAndElevation() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: input(type: .cycling, distanceKm: 44.17, durationMinutes: 111, elevationGainMeters: 434)
        )

        XCTAssertEqual(card.publicMetrics.map(\.label), ["거리", "시간", "고도"])
        XCTAssertEqual(card.publicMetrics.map(\.value), ["44.2km", "1h 51m", "434m"])
        XCTAssertEqual(card.compactPublicMetricLine, "1h 51m · 434m")
    }

    func testRunningShareMetricSetUsesDistancePaceAndDuration() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: input(type: .running, distanceKm: 10.4, durationMinutes: 52, pace: "5:02/km")
        )

        XCTAssertEqual(card.publicMetrics.map(\.label), ["거리", "페이스", "시간"])
        XCTAssertEqual(card.publicMetrics.map(\.value), ["10.4km", "5'02\"/km", "52m"])
        XCTAssertEqual(card.compactPublicMetricLine, "5'02\"/km · 52m")
    }

    func testWalkingShareMetricSetUsesDistanceAndDuration() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: input(type: .walking, distanceKm: 3.2, durationMinutes: 46)
        )

        XCTAssertEqual(card.publicMetrics.map(\.label), ["거리", "시간"])
        XCTAssertEqual(card.publicMetrics.map(\.value), ["3.2km", "46m"])
        XCTAssertEqual(card.compactPublicMetricLine, "46m")
    }

    func testRouteFirstLayoutVariantsAreAvailableForWorkoutAndRouteCards() {
        let baseCard = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )
        let workoutCard = baseCard.configured(shareType: .workout, backgroundOption: .mapPhoto)
        let routeCard = baseCard.configured(shareType: .route, backgroundOption: .mapPhoto)
        let transparentWorkout = baseCard.configured(shareType: .workout, backgroundOption: .transparent)

        XCTAssertEqual(workoutCard.layoutVariants, [.routeHero, .routeTopMetricsBottom, .routeCenteredStats])
        XCTAssertEqual(routeCard.layoutVariants, [.routeTopMetricsBottom, .routeLeftTextRight, .routeHero])
        XCTAssertEqual(transparentWorkout.exportLayoutVariant, .transparentOverlay)
    }

    func testConditionShareCardUsesConditionFirstCopyWithoutRecoveryPrimaryText() {
        let baseCard = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )
        let conditionCard = baseCard.configured(
            shareType: .recovery,
            backgroundOption: .mapPhoto
        )

        XCTAssertEqual(conditionCard.storyHeadline, "좋음")
        XCTAssertEqual(conditionCard.storySupportingText, "82")
        XCTAssertEqual(conditionCard.storyInterpretation, "밀어도 되는 날")
        XCTAssertFalse(conditionCard.storyHeadline.localizedCaseInsensitiveContains("recovery"))
        XCTAssertFalse(conditionCard.storyInterpretation.localizedCaseInsensitiveContains("recovery"))
    }

    func testRouteAndClubShareCardsUseStoryStyleCopy() {
        let baseCard = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )
        let routeCard = baseCard.configured(shareType: .route, backgroundOption: .mapPhoto)
        let clubCard = baseCard.configured(shareType: .club, backgroundOption: .mapPhoto)

        XCTAssertEqual(routeCard.storyHeadline, "한강 북단")
        XCTAssertEqual(routeCard.storyInterpretation, "좋은 바람이 있던 날")
        XCTAssertEqual(routeCard.storySupportingText, "10.4km · 강변 코스")
        XCTAssertEqual(clubCard.storyHeadline, "SOOM Riders")
        XCTAssertEqual(clubCard.storyInterpretation, "이번 주 12위")
        XCTAssertEqual(clubCard.storySupportingText, "42.6km 기여")
    }

    func testAllShareCardsIncludeQuietSOOMSignatureFooter() {
        let baseCard = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        let cards = ShareCardComposerLayout.cardOrder.map {
            baseCard.configured(shareType: $0, backgroundOption: .mapPhoto)
        }

        XCTAssertEqual(cards.map(\.signatureLine), [
            "페이스는 숨에서",
            "숨부터 잡아라",
            "길보다 리듬",
            "함께 쌓은 리듬"
        ])
        cards.forEach { card in
            XCTAssertTrue(card.signatureFooterText.hasSuffix("· SOOM"))
            XCTAssertLessThanOrEqual(card.signatureLine.count, 10)
        }
    }

    func testShareCardUsesRhythmPatternWithoutRestoringMetricGrid() {
        XCTAssertTrue(ShareableWorkoutCardLayout.usesRhythmPattern)
        XCTAssertFalse(ShareableWorkoutCardLayout.usesMetricGrid)
    }

    func testTransparentExportExcludesCardChromeAndMetadata() {
        XCTAssertFalse(ShareableWorkoutCardLayout.transparentExportIncludesCardSurface)
        XCTAssertFalse(ShareableWorkoutCardLayout.transparentExportIncludesBorder)
        XCTAssertFalse(ShareableWorkoutCardLayout.transparentExportIncludesMetadata)
        XCTAssertFalse(ShareableWorkoutCardLayout.transparentExportIncludesRhythmPattern)
    }

    func testConditionSignatureKeepsPublicCopyFreeOfRawRecoveryTerms() {
        let baseCard = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )
        let conditionCard = baseCard.configured(
            shareType: .recovery,
            backgroundOption: .transparent,
            visibility: .publicFeed
        )

        let publicVisualCopy = [
            conditionCard.storyHeadline,
            conditionCard.storyInterpretation,
            conditionCard.storySupportingText,
            conditionCard.signatureFooterText
        ].joined(separator: " ")

        ["recovery", "fatigue", "readiness"].forEach { rawTerm in
            XCTAssertFalse(publicVisualCopy.localizedCaseInsensitiveContains(rawTerm))
        }
    }

    func testBuildWithRouteAppliesPrivacyMaskingPolicy() {
        let route = WorkoutRoute(
            workoutId: growthInput.id,
            source: .appleHealthKit,
            coordinates: [
                routeCoordinate(atMeters: 0),
                routeCoordinate(atMeters: 100),
                routeCoordinate(atMeters: 300),
                routeCoordinate(atMeters: 600),
                routeCoordinate(atMeters: 900)
            ],
            totalDistanceMeters: 900
        )

        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput,
            route: route
        )

        XCTAssertTrue(card.staticRoutePreview?.routeExists == true)
        XCTAssertTrue(card.hasRoutePreviewPayload)
        XCTAssertTrue(card.shouldShowRouteVisual)
        XCTAssertGreaterThan(card.staticRoutePreview?.bounds?.minLatitude ?? 0, route.bounds?.minLatitude ?? 0)
        XCTAssertLessThan(card.staticRoutePreview?.bounds?.maxLatitude ?? 0, route.bounds?.maxLatitude ?? 0)
        XCTAssertEqual(card.visibility, .privateOnly)
    }

    func testRouteBasedTransparentWorkoutKeepsRouteLineAvailableForExport() {
        let route = WorkoutRoute(
            workoutId: growthInput.id,
            source: .appleHealthKit,
            coordinates: [
                routeCoordinate(atMeters: 0),
                routeCoordinate(atMeters: 160),
                routeCoordinate(atMeters: 420),
                routeCoordinate(atMeters: 760),
                routeCoordinate(atMeters: 1_100)
            ],
            totalDistanceMeters: 1_100
        )

        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput,
            route: route
        )
        let transparentWorkout = card.configured(
            shareType: .workout,
            backgroundOption: .transparent
        )
        let transparentRoute = card.configured(
            shareType: .route,
            backgroundOption: .transparent
        )

        XCTAssertTrue(transparentWorkout.isRouteBasedWorkout)
        XCTAssertTrue(transparentWorkout.hasRoutePreviewPayload)
        XCTAssertTrue(transparentWorkout.shouldShowRouteLineInTransparentExport)
        XCTAssertTrue(transparentRoute.shouldShowRouteLineInTransparentExport)
    }

    private func routeCoordinate(atMeters meters: Double) -> WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(
            latitude: 37.50 + meters / 111_000,
            longitude: 127.00
        )
    }

    private func input(
        type: UnifiedWorkoutType,
        distanceKm: Double?,
        durationMinutes: Int,
        pace: String? = nil,
        elevationGainMeters: Double? = nil
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .soomLocal,
            workoutType: type,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            averagePaceText: pace,
            averageSpeedKmh: nil,
            averageHeartRate: 151,
            elevationGainMeters: elevationGainMeters,
            activeEnergyKcal: nil
        )
    }

    private var sessionSummary: WorkoutSessionSummary {
        WorkoutSessionSummary(
            title: "오늘은 리듬을 잘 이어간 운동이에요",
            summaryText: "거리와 시간 모두 안정적으로 쌓였어요.",
            highlightText: "지구력 흐름이 좋아졌어요.",
            improvementText: "초반 리듬을 조금 더 부드럽게 가져가면 좋아요.",
            recoveryText: "몸에 적당한 자극을 남기는 흐름이에요.",
            closingMotivation: "다음 운동도 오늘 리듬을 기준으로 이어가보세요.",
            icon: SOOMIcon.sparkles
        )
    }

    private var growthSummary: WorkoutGrowthSummary {
        WorkoutGrowthSummary(
            workoutId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "더 오래 움직였어요",
            shortSummary: "오늘은 같은 종목의 최근 기록보다 지구력 흐름이 좋아졌어요.",
            improvementType: .endurance,
            comparisonText: "10.4 km · 이전 8.8 km",
            motivationText: "조금씩 거리가 길어지고 있어요.",
            insight: "다음에는 같은 리듬을 유지하면서 회복 여유를 확인해보세요."
        )
    }

    private var recoveryImpact: WorkoutRecoveryImpact {
        WorkoutRecoveryImpact(
            impactLevel: .moderate,
            title: "적당한 자극이 있는 운동",
            shortMessage: "회복 흐름을 생각한 안정적인 강도였어요.",
            recommendation: "다음 운동 전 회복 리듬을 한 번 확인하고 비슷한 강도를 이어가보세요.",
            icon: SOOMIcon.waveform
        )
    }

    private var growthInput: WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            source: .soomLocal,
            workoutType: .running,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: 52,
            distanceKm: 10.4,
            averagePaceText: "5:00/km",
            averageSpeedKmh: nil,
            averageHeartRate: 151,
            elevationGainMeters: 78,
            activeEnergyKcal: 676
        )
    }
}
