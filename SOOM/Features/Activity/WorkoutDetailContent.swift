import HealthKit
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum WorkoutDetailPresentationStyle {
    case standalone
    case mapSheet
}

struct WorkoutDetailContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let workout: Workout
    let showsHeader: Bool
    var presentationStyle: WorkoutDetailPresentationStyle = .standalone
    var sessionSummary: WorkoutSessionSummary?
    var growthSummary: WorkoutGrowthSummary?
    var growthMetrics: [WorkoutGrowthMetric]?
    var comparisonInsight: WorkoutComparisonInsight?
    var courseRecord: CourseRecord?
    var courseProgression: CourseProgressionTimeline?
    var terrainInsight: TerrainInsight?
    var splitInsight: WorkoutSplitInsight?
    var climbInsight: ClimbInsight?
    var weaknessInsight: WorkoutWeaknessInsight?
    var recoveryImpact: WorkoutRecoveryImpact?
    var shareableCard: ShareableWorkoutCardModel?
    var mapRoute: WorkoutRoute?
    var sourceUnifiedWorkout: UnifiedWorkout? = nil
    var routeAttachmentAction: ActivityDetailGPXRouteImportAction?
    var companionUpdateAction: WorkoutCompanionUpdateAction?
    var healthKitWorkout: HKWorkout?
    var zoneDataProvider: WorkoutZoneDataProviding?
    var splitDataProvider: WorkoutSplitDataProviding?
    var samplesOverride: [WorkoutSample]?
    var splitsOverride: [WorkoutSplit]?
    var heartRateChartSamplesOverride: [WorkoutDistanceChartSample]?
    var relativeEffortComparisonOverride: RelativeEffortComparison?
    var achievementsOverride: [WorkoutAchievement]?
    var achievementCountOverride: Int?
    var fitnessTrendOverride: FitnessTrend?
    var renderShareImage: @MainActor (ShareableWorkoutCardModel, Color) -> UIImage? = { card, tint in
        ShareableWorkoutCardRenderer().render(card: card, tint: tint)
    }
    @State private var streamZoneSummaries: [WorkoutZoneSummary]?
    @State private var streamSplitInsight: WorkoutSplitInsight?
    @State private var isLoadingZoneSummaries = false
    @State private var didFailLoadingZoneSummaries = false
    @State private var feedDraftMessage: String?
    @State private var feedDraftErrorMessage: String?
    @State private var isCreatingFeedDraft = false
    @State private var isShareComposerPresented = false
    @State private var isRouteFileImporterPresented = false
    @State private var isAttachingRouteFile = false
    @State private var routeAttachmentMessage: String?
    @State private var routeAttachmentErrorMessage: String?
    @State private var companionNamesOverride: [String]?
    @State private var isCompanionSheetPresented = false
    @State private var isUpdatingCompanions = false
    @State private var companionUpdateErrorMessage: String?

    static let sharePrivacyCopy = "스토리에 올릴 이미지를 고르세요."
    static let shareComposerTitle = "공유 카드"
    static let showsInlineShareControls = false

    var body: some View {
        Group {
            if showsHeader {
                DetailHeader(
                    icon: workout.sport.iconName,
                    title: workout.title,
                    subtitle: "\(workout.sport.title) · \(processedWorkout.display.distanceText) · \(processedWorkout.display.durationText)",
                    tint: workout.sport.tint
                )
            }

            if presentationStyle == .standalone {
                ActivityDetailHeroMap(workout: workout, route: mapRoute, achievements: achievements, routeMissingReason: processedWorkout.routeMissingReason)
            }
            ForEach(achievements) { achievement in
                WorkoutAchievementCard(achievement: achievement, tint: workout.sport.tint)
            }
            if let achievementCountOverride, achievementCountOverride > 0 {
                WorkoutResultsCard(achievementCount: achievementCountOverride, tint: workout.sport.tint)
            }
            if processedWorkout.routeMissingReason.isActionableForRouteAttachment {
                ActivityDetailRouteMissingCard(
                    reason: processedWorkout.routeMissingReason,
                    tint: workout.sport.tint,
                    showsImportAction: routeAttachmentAction != nil,
                    isImporting: isAttachingRouteFile,
                    message: routeAttachmentMessage,
                    errorMessage: routeAttachmentErrorMessage,
                    importAction: { isRouteFileImporterPresented = true }
                )
            }
            ActivityDetailSummaryCard(
                workout: workout,
                processedWorkout: processedWorkout
            )
            ActivityDetailRhythmCard(insight: rhythmInsight, tint: workout.sport.tint)

            if let terrainInsight, terrainInsight.isVisible {
                TerrainInsightCue(insight: terrainInsight, tint: workout.sport.tint)
            }

            WorkoutCompanionCard(
                sourceTag: processedWorkout.display.sourceTitle,
                companions: companions,
                tint: workout.sport.tint,
                canEditCompanions: companionUpdateAction != nil,
                isUpdating: isUpdatingCompanions,
                errorMessage: companionUpdateErrorMessage,
                onTapEdit: { isCompanionSheetPresented = true }
            )

            detailSection(.core) {
                if let sessionSummary {
                    WorkoutSessionSummaryCard(summary: sessionSummary, tint: workout.sport.tint)
                }
            }

            detailSection(.growth) {
                if let metrics = growthMetrics, !metrics.isEmpty {
                    WorkoutGrowthMetricsCard(metrics: metrics, tint: workout.sport.tint)
                }

                if let growthSummary {
                    WorkoutGrowthCard(summary: growthSummary, tint: workout.sport.tint)
                }

                if ActivityDetailVisibilityPolicy.showsComparisonInsight(comparisonInsight),
                   let comparisonInsight {
                    WorkoutComparisonInsightCard(insight: comparisonInsight, tint: workout.sport.tint)
                }

                if let courseRecord {
                    CourseRecordCard(record: courseRecord, tint: workout.sport.tint)
                }

                if let courseProgression {
                    CourseProgressionCard(timeline: courseProgression, tint: workout.sport.tint)
                }

                if ActivityDetailVisibilityPolicy.showsSplitInsight(displayedSplitInsight),
                   let displayedSplitInsight {
                    WorkoutSplitInsightCard(insight: displayedSplitInsight, tint: workout.sport.tint)
                }

                if let climbInsight, climbInsight.isVisible {
                    ClimbInsightCard(insight: climbInsight, tint: workout.sport.tint)
                }
            }

            if showsSensorDataSection {
                detailSection(.sensorData) {
                    if ActivityDetailVisibilityPolicy.showsHeartRateEffort(workout: workout, streamSummaries: streamZoneSummaries) {
                        WorkoutZoneSection(
                            workout: workout,
                            streamSummaries: streamZoneSummaries,
                            isLoadingStream: isLoadingZoneSummaries,
                            didFailLoadingStream: didFailLoadingZoneSummaries
                        )
                    }
                    if ActivityDetailVisibilityPolicy.showsCharts(workout: effectiveWorkout) {
                        WorkoutChartStack(workout: effectiveWorkout)
                    }
                    if ActivityDetailVisibilityPolicy.showsSplits(workout: effectiveWorkout) {
                        WorkoutSplitsCard(workout: effectiveWorkout)
                    }

                    WorkoutDistanceChartCard(
                        title: "파워",
                        unitLabel: "W",
                        samples: [],
                        tint: workout.sport.tint,
                        placeholderMessage: "파워 데이터가 있는 워크아웃에서 제공됩니다."
                    )

                    WorkoutDistanceChartCard(
                        title: "심박수",
                        unitLabel: "bpm",
                        samples: heartRateChartSamples,
                        tint: workout.sport.tint,
                        placeholderMessage: heartRateChartSamples.isEmpty ? "Apple Health 연동 시 제공됩니다." : nil,
                        stats: heartRateStats
                    )

                    if let heartRateInsightText {
                        WorkoutInsightCueCard(
                            icon: SOOMIcon.heart,
                            eyebrow: "심박 흐름",
                            message: heartRateInsightText,
                            tint: workout.sport.tint,
                            accessibilityLabel: "심박 흐름",
                            accessibilityValue: heartRateInsightText
                        )
                    }

                    WorkoutDistanceChartCard(
                        title: "속도",
                        unitLabel: "km/h",
                        samples: speedChartSamples,
                        tint: workout.sport.tint,
                        showsInfoIcon: false,
                        placeholderMessage: speedChartSamples.isEmpty ? "GPS 경로 데이터가 있는 워크아웃에서 제공됩니다." : nil,
                        stats: speedStats
                    )

                    WorkoutDistanceChartCard(
                        title: "케이던스",
                        unitLabel: "rpm",
                        samples: [],
                        tint: workout.sport.tint,
                        placeholderMessage: "케이던스 데이터가 있는 워크아웃에서 제공됩니다.",
                        stats: cadenceStats
                    )

                    WorkoutDistanceChartCard(
                        title: "고도",
                        unitLabel: "m",
                        samples: elevationChartSamples,
                        tint: workout.sport.tint,
                        placeholderMessage: elevationChartSamples.isEmpty ? "GPS 고도 데이터가 있는 워크아웃에서 제공됩니다." : nil,
                        stats: elevationStats
                    )
                }
            }

            detailSection(.recovery) {
                if let fitnessTrendOverride {
                    FitnessTrendCard(trend: fitnessTrendOverride, tint: workout.sport.tint)
                }

                if let relativeEffortComparisonOverride {
                    RelativeEffortCard(comparison: relativeEffortComparisonOverride)
                }

                if let recoveryImpact {
                    WorkoutRecoveryImpactCard(impact: recoveryImpact, tint: workout.sport.tint)
                }

                if let weaknessInsight {
                    WorkoutWeaknessCard(insight: weaknessInsight, tint: workout.sport.tint)
                }

                SOOMCard {
                    SOOMSectionHeader("AI 해석")
                    Text(workout.aiSummary)
                        .font(SOOMFont.body(15, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("AI 해석")
                .accessibilityValue(workout.aiSummary)
            }

            ActivityDetailActionsCard(
                canShareImage: shareableCard != nil,
                isCreatingFeedDraft: isCreatingFeedDraft,
                feedDraftMessage: feedDraftMessage,
                feedDraftErrorMessage: feedDraftErrorMessage,
                createFeedDraft: { await createFeedDraft() },
                openImageShare: { isShareComposerPresented = true }
            )
        }
        .sheet(isPresented: $isShareComposerPresented) {
            if let shareableCard {
                ShareCardComposer(
                    baseCard: shareableCard,
                    tint: SOOMColor.accent,
                    renderShareImage: renderShareImage
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            } else {
                EmptyView()
            }
        }
        .fileImporter(
            isPresented: $isRouteFileImporterPresented,
            allowedContentTypes: ActivityDetailGPXRouteFileImport.allowedContentTypes
        ) { result in
            handleRouteFileImport(result)
        }
        .sheet(isPresented: $isCompanionSheetPresented) {
            WorkoutCompanionEditSheet(
                initialNames: companions,
                tint: workout.sport.tint,
                onSave: { names in await updateCompanions(names) }
            )
        }
        .task(id: healthKitWorkout?.uuid) {
            await loadStreamZoneSummaries()
            await loadStreamSplitInsight()
        }
    }


    @ViewBuilder
    private func detailSection<Content: View>(
        _ group: WorkoutDetailSectionGroup,
        @ViewBuilder content: () -> Content
    ) -> some View {
        WorkoutDetailSectionContainer(group: group, reduceMotion: reduceMotion) {
            content()
        }
    }

    @MainActor
    private func handleRouteFileImport(_ result: Result<URL, Error>) {
        guard let routeAttachmentAction else { return }

        switch result {
        case .success(let url):
            routeAttachmentMessage = nil
            routeAttachmentErrorMessage = nil
            isAttachingRouteFile = true

            Task {
                let importResult = await routeAttachmentAction.importRoute(url)
                await MainActor.run {
                    switch importResult {
                    case .success:
                        routeAttachmentMessage = "경로가 추가되었습니다."
                        routeAttachmentErrorMessage = nil
                    case .failure(let error):
                        routeAttachmentMessage = nil
                        routeAttachmentErrorMessage = error.message
                    }
                    isAttachingRouteFile = false
                }
            }
        case .failure:
            routeAttachmentMessage = nil
            routeAttachmentErrorMessage = ActivityDetailGPXRouteImportError.unreadableFile.message
        }
    }

    @MainActor
    private func updateCompanions(_ names: [String]) async {
        guard let companionUpdateAction else { return }

        isUpdatingCompanions = true
        companionUpdateErrorMessage = nil

        let result = await companionUpdateAction.updateCompanions(names)
        switch result {
        case .success(let savedNames):
            companionNamesOverride = savedNames
            companionUpdateErrorMessage = nil
        case .failure(let error):
            companionUpdateErrorMessage = error.message
        }

        isUpdatingCompanions = false
    }

    @MainActor
    private func loadStreamZoneSummaries() async {
        guard let healthKitWorkout, let zoneDataProvider else {
            streamZoneSummaries = nil
            isLoadingZoneSummaries = false
            didFailLoadingZoneSummaries = false
            return
        }

        isLoadingZoneSummaries = true
        didFailLoadingZoneSummaries = false

        do {
            let summaries = try await zoneDataProvider.summaries(for: healthKitWorkout, sport: workout.sport)
            streamZoneSummaries = summaries.contains { $0.isAvailable } ? summaries : nil
        } catch {
            streamZoneSummaries = nil
            didFailLoadingZoneSummaries = true
        }

        isLoadingZoneSummaries = false
    }

    @MainActor
    private func loadStreamSplitInsight() async {
        guard let healthKitWorkout, let splitDataProvider else {
            streamSplitInsight = nil
            return
        }

        do {
            streamSplitInsight = try await splitDataProvider.insight(
                for: healthKitWorkout,
                current: workoutGrowthInput
            )
        } catch {
            streamSplitInsight = nil
        }
    }

    private var displayedSplitInsight: WorkoutSplitInsight? {
        streamSplitInsight ?? splitInsight
    }

    private var rhythmInsight: String {
        ActivityDetailRhythmInterpreter.primaryMessage(
            workout: workout,
            sessionSummary: sessionSummary,
            splitInsight: displayedSplitInsight,
            weaknessInsight: weaknessInsight,
            recoveryImpact: recoveryImpact
        )
    }

    private var showsSensorDataSection: Bool {
        ActivityDetailVisibilityPolicy.showsHeartRateEffort(workout: workout, streamSummaries: streamZoneSummaries)
            || ActivityDetailVisibilityPolicy.showsCharts(workout: effectiveWorkout)
            || ActivityDetailVisibilityPolicy.showsSplits(workout: effectiveWorkout)
    }

    private var effectiveWorkout: Workout {
        guard samplesOverride != nil || splitsOverride != nil else { return workout }
        return workout.withChartData(
            samples: samplesOverride ?? workout.samples,
            splits: splitsOverride ?? workout.splits
        )
    }

    private var processedWorkout: ProcessedWorkout {
        ProcessedWorkoutBuilder().make(
            from: sourceUnifiedWorkout ?? unifiedWorkoutForDraft,
            route: mapRoute,
            hasHeartRateSeries: !heartRateChartSamples.isEmpty
        )
    }

    private var speedChartSamples: [WorkoutDistanceChartSample] {
        guard let mapRoute, processedWorkout.metricAvailability[.speedSeries] == .measured else { return [] }
        return WorkoutChartDataBuilder.speedSamples(from: mapRoute)
    }

    private var elevationChartSamples: [WorkoutDistanceChartSample] {
        guard let mapRoute, processedWorkout.metricAvailability[.elevationSeries] == .measured else { return [] }
        return WorkoutChartDataBuilder.elevationSamples(from: mapRoute)
    }

    /// Resolved asynchronously by the caller (HealthKit stream fetch happens outside
    /// `WorkoutDetailContent`'s scope, same pattern as `samplesOverride`/`splitsOverride`).
    private var heartRateChartSamples: [WorkoutDistanceChartSample] {
        heartRateChartSamplesOverride ?? []
    }

    /// Resolved asynchronously by the caller (route-batch fetch + ranking against
    /// recent history happens outside this view's scope, same override pattern).
    private var achievements: [WorkoutAchievement] {
        achievementsOverride ?? []
    }

    /// Free-text companion names (batch 8) — `companionNamesOverride` reflects
    /// an in-sheet edit immediately, before `sourceUnifiedWorkout` (owned by the
    /// caller) has a chance to be refetched. `sourceUnifiedWorkout` is nil on the
    /// legacy `Workout`-only navigation path, so this safely falls back to `[]`.
    private var companions: [String] {
        companionNamesOverride ?? sourceUnifiedWorkout?.companionNames ?? []
    }

    private var heartRateInsightText: String? {
        guard !heartRateChartSamples.isEmpty else { return nil }
        let avg = processedWorkout.display.averageHeartRateText
        let max = processedWorkout.display.maxHeartRateText
        guard avg != "—", max != "—" else { return nil }
        return "평균 심박 \(avg), 최고 \(max)까지 올라갔어요."
    }

    /// Max Heart Rate uses the existing measured aggregate (`display.maxHeartRateText`,
    /// a real HealthKit sensor reading) rather than the max of `heartRateChartSamples` —
    /// unlike Speed/Elevation below, SOOM already has a genuine point-in-time max for HR,
    /// which is more accurate than deriving one from 200m-bucket averages.
    private var heartRateStats: [ActivityDetailMetric] {
        guard !heartRateChartSamples.isEmpty else { return [] }
        return [
            ActivityDetailMetric(label: "평균 심박", value: processedWorkout.display.averageHeartRateText),
            ActivityDetailMetric(label: "최고 심박", value: processedWorkout.display.maxHeartRateText)
        ]
    }

    /// Max Speed/Max Elevation below have no existing aggregate anywhere in SOOM, so
    /// they're derived from the same bucketed samples the chart already renders — the
    /// max of ~200m-bucket averages, not a true instantaneous peak (slightly smoothed,
    /// never fabricated). See feed-detail-migration-plan.md batch 5.
    private var speedStats: [ActivityDetailMetric] {
        guard !speedChartSamples.isEmpty else { return [] }
        let maxSpeed = speedChartSamples.map(\.value).max() ?? 0
        return [
            ActivityDetailMetric(label: "평균 속도", value: processedWorkout.display.speedText),
            ActivityDetailMetric(label: "최고 속도", value: String(format: "%.1f km/h", maxSpeed)),
            ActivityDetailMetric(label: "이동 시간", value: processedWorkout.display.durationText),
            ActivityDetailMetric(label: "경과 시간", value: processedWorkout.display.durationText)
        ]
    }

    /// No max/peak companion stat like speedStats/elevationStats have — those derive
    /// a max from a bucketed per-record series, but cadence (batch 11) only has a
    /// single FIT session-summary average, no per-record series to take a max from.
    private var cadenceStats: [ActivityDetailMetric] {
        guard let text = processedWorkout.display.averageCadenceText else { return [] }
        return [ActivityDetailMetric(label: "평균 케이던스", value: text)]
    }

    private var elevationStats: [ActivityDetailMetric] {
        guard !elevationChartSamples.isEmpty else { return [] }
        let maxElevation = elevationChartSamples.map(\.value).max() ?? 0
        return [
            ActivityDetailMetric(label: "상승 고도", value: processedWorkout.display.elevationText),
            ActivityDetailMetric(label: "최고 고도", value: "\(Int(maxElevation.rounded()))m")
        ]
    }

    private var workoutGrowthInput: WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: workout.id,
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(workoutSport: workout.sport),
            startDate: workout.date,
            durationMinutes: Int(workout.duration / 60),
            distanceKm: workout.distanceMeters > 0 ? workout.distanceMeters / 1_000 : nil,
            averagePaceText: workout.sport == .run ? workout.formattedPace : nil,
            averageSpeedKmh: workout.duration > 0 ? (workout.distanceMeters / 1_000) / (workout.duration / 3_600) : nil,
            averageHeartRate: Double(workout.avgHeartRate),
            elevationGainMeters: Double(workout.elevationGain),
            activeEnergyKcal: Double(workout.activeCalories)
        )
    }

    @MainActor
    private func createFeedDraft() async {
        guard !isCreatingFeedDraft else { return }

        isCreatingFeedDraft = true
        feedDraftMessage = nil
        feedDraftErrorMessage = nil

        do {
            let clientProvider = SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
            let remotePoster = clientProvider.makeClient().map(SupabaseFeedRemoteClient.init(client:))
            let coordinator = RecordShareDraftCoordinator(store: FileFeedShareDraftStore.live, remotePoster: remotePoster)
            let outcome = try await coordinator.handle(.shareToFeed, workout: unifiedWorkoutForDraft)
            feedDraftMessage = outcome?.summaryMessage
                ?? "이 기기에 저장했어요. 로그인하면 다른 사람도 볼 수 있어요."
        } catch {
            feedDraftErrorMessage = "피드 초안을 만들지 못했어요. 잠시 후 다시 시도해주세요."
        }

        isCreatingFeedDraft = false
    }

    private var unifiedWorkoutForDraft: UnifiedWorkout {
        UnifiedWorkout(
            id: workout.id,
            externalId: "workout-detail-\(workout.id.uuidString)",
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(workoutSport: workout.sport),
            startDate: workout.date,
            endDate: workout.date.addingTimeInterval(workout.duration),
            durationSeconds: workout.duration,
            distanceMeters: workout.distanceMeters > 0 ? workout.distanceMeters : nil,
            activeEnergyKcal: workout.activeCalories > 0 ? Double(workout.activeCalories) : nil,
            averageHeartRate: workout.avgHeartRate > 0 ? Double(workout.avgHeartRate) : nil,
            maxHeartRate: workout.maxHeartRate > 0 ? Double(workout.maxHeartRate) : nil,
            averageSpeedMetersPerSecond: workout.duration > 0 && workout.distanceMeters > 0 ? workout.distanceMeters / workout.duration : nil,
            elevationGainMeters: workout.elevationGain > 0 ? Double(workout.elevationGain) : nil,
            dataQuality: .partial,
            isExcludedFromAnalysis: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @MainActor
    func renderedShareImage(for card: ShareableWorkoutCardModel) -> UIImage? {
        renderShareImage(card, SOOMColor.accent)
    }
}

struct DetailHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        SOOMCard {
            HStack(spacing: SOOMLayout.Metrics.detailHeaderSpacing) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: SOOMLayout.Metrics.detailIconFrame, height: SOOMLayout.Metrics.detailIconFrame)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(title)
                        .font(SOOMFont.display(22, relativeTo: .title2))
                        .foregroundStyle(SOOMColor.ink)
                    Text(subtitle)
                        .font(SOOMFont.body(15, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}

private struct ActivityDetailHeroMap: View {
    let workout: Workout
    let route: WorkoutRoute?
    var achievements: [WorkoutAchievement] = []
    var routeMissingReason: WorkoutRouteMissingReason = .none

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WorkoutDetailMapView(route: route, fallbackStyle: fallbackStyle, tint: workout.sport.tint, achievements: achievements)
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))

            LinearGradient(
                colors: [
                    SOOMColor.black.opacity(0.0),
                    SOOMColor.black.opacity(0.26)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text("오늘의 경로")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.white.opacity(0.86))

                Text(route == nil ? "경로가 없어도 운동의 흐름은 남아 있어요." : "움직인 길을 먼저 보고, 의미를 천천히 읽어요.")
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SOOMLayout.Card.padding)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("운동 경로")
        .accessibilityValue(route == nil ? "경로 데이터 없음" : "운동 경로 미리보기")
    }

    private var fallbackStyle: StaticRouteFallbackStyle {
        if routeMissingReason == .indoorNoLocationData {
            return .indoor
        }
        switch workout.sport {
        case .run: return .running
        case .bike, .brick: return .cycling
        case .swim: return .swimming
        }
    }
}

private struct ActivityDetailRouteMissingCard: View {
    let reason: WorkoutRouteMissingReason
    let tint: Color
    let showsImportAction: Bool
    let isImporting: Bool
    let message: String?
    let errorMessage: String?
    let importAction: () -> Void

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.Metrics.rowTextSpacing) {
                Image(systemName: SOOMIcon.map)
                    .font(.system(size: SOOMFont.Size.body, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("경로 데이터 없음")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(tint)

                    Text(fallbackMessage)
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("원본 앱에서 GPX 또는 FIT 파일을 내보내면 이 운동에 경로를 추가할 수 있습니다.")
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsImportAction {
                        Button(action: importAction) {
                            Label(isImporting ? "경로 추가 중" : "경로 파일 가져오기", systemImage: SOOMIcon.share)
                                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                                .foregroundStyle(SOOMColor.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SOOMLayout.Metrics.rowTextSpacing)
                                .background(tint)
                                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                        .accessibilityHint("GPX 또는 FIT 파일을 선택해 이 운동에 경로를 추가합니다.")
                    }

                    if let message {
                        statusMessage(message, tint: SOOMColor.accent)
                    }

                    if let errorMessage {
                        statusMessage(errorMessage, tint: SOOMColor.warning)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("경로 데이터 없음")
        .accessibilityValue([fallbackMessage, message, errorMessage].compactMap { $0 }.joined(separator: " "))
    }

    private var fallbackMessage: String {
        switch reason {
        case .routeFetchFailed:
            return "Apple Health에서 운동은 가져왔지만 경로를 확인하지 못했습니다. 원본 앱에서 경로 파일을 가져오면 경로를 추가할 수 있습니다."
        case .routePersistenceFailed:
            return "Apple Health에서 경로를 찾았지만 저장하지 못했습니다. 원본 앱에서 경로 파일을 가져오면 경로를 다시 추가할 수 있습니다."
        case .externalSourceRouteNotShared:
            return "Apple Health에서 운동은 가져왔지만 원본 앱의 경로 데이터는 포함되지 않았습니다. 원본 앱에서 경로 파일을 가져오면 경로를 추가할 수 있습니다."
        case .healthKitRouteUnavailable:
            return "Apple Health에서 운동은 가져왔지만 경로 데이터는 포함되지 않았습니다. 원본 앱에서 경로 파일을 가져오면 경로를 추가할 수 있습니다."
        case .none, .notApplicable, .userSkippedRouteAttachment, .indoorNoLocationData, .unknown:
            return "경로 데이터가 없어도 운동 요약은 확인할 수 있습니다."
        }
    }

    private func statusMessage(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SOOMLayout.Metrics.actionTextSpacing)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ActivityDetailSummaryCard: View {
    let workout: Workout
    let processedWorkout: ProcessedWorkout
    private let columns = [GridItem(.flexible(), spacing: SOOMLayout.Metrics.gridSpacing), GridItem(.flexible(), spacing: SOOMLayout.Metrics.gridSpacing)]

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                HStack(alignment: .top, spacing: SOOMLayout.Metrics.rowTextSpacing) {
                    Image(systemName: workout.sport.iconName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(workout.sport.tint)
                        .frame(width: 36, height: 36)
                        .background(workout.sport.tint.opacity(0.12))
                        .clipShape(Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.sport.title)
                            .font(SOOMFont.display(20, relativeTo: .title3))
                            .foregroundStyle(SOOMColor.ink)
                        Text(dateText)
                            .font(SOOMFont.body(13, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }

                    Spacer()
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: SOOMLayout.Metrics.gridSpacing) {
                    ForEach(summaryMetrics) { metric in
                        ActivityDetailStatTile(metric: metric, tint: workout.sport.tint)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("운동 요약")
        .accessibilityValue(summaryMetrics.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }

    private var summaryMetrics: [ActivityDetailMetric] {
        ActivityDetailSummaryMetrics.metrics(processedWorkout: processedWorkout)
    }

    private var dateText: String {
        "\(processedWorkout.display.dateText) \(processedWorkout.display.timeText)"
    }
}

private struct ActivityDetailStatTile: View {
    let metric: ActivityDetailMetric
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.label)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(1)

            Text(metric.value)
                .font(SOOMFont.displayMedium(19, relativeTo: .headline))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(.horizontal, SOOMLayout.Spacing.md)
        .padding(.vertical, SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ActivityDetailRhythmCard: View {
    let insight: String
    let tint: Color

    var body: some View {
        WorkoutInsightCueCard(
            icon: SOOMIcon.waveform,
            eyebrow: "오늘의 리듬",
            message: insight,
            tint: tint,
            messageFont: SOOMFont.body(16, weight: .bold, relativeTo: .body),
            messageColor: SOOMColor.ink,
            accessibilityLabel: "오늘의 리듬",
            accessibilityValue: insight
        )
    }
}

private struct ActivityDetailActionsCard: View {
    let canShareImage: Bool
    let isCreatingFeedDraft: Bool
    let feedDraftMessage: String?
    let feedDraftErrorMessage: String?
    let createFeedDraft: () async -> Void
    let openImageShare: () -> Void

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                SOOMSectionHeader("액션", caption: "운동 해석은 그대로 두고, 공유는 필요할 때만 열어요.")

                HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                    statusPill("저장됨", icon: SOOMIcon.checkCircle)
                    statusPill("수정 준비 중", icon: SOOMIcon.edit)
                    statusPill("삭제 준비 중", icon: SOOMIcon.trash)
                }

                Button {
                    Task { await createFeedDraft() }
                } label: {
                    Label(isCreatingFeedDraft ? "피드 초안 만드는 중" : "피드에 공유하기", systemImage: SOOMIcon.feed)
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SOOMLayout.Card.padding)
                        .background(SOOMColor.ink)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isCreatingFeedDraft)
                .accessibilityHint("공개하지 않고 로컬 피드 초안으로 저장합니다.")

                if canShareImage {
                    Button(action: openImageShare) {
                        Label("이미지로 공유하기", systemImage: SOOMIcon.share)
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SOOMLayout.Card.padding)
                            .background(SOOMColor.accentSurface)
                            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("공유 카드 composer를 열어 이미지 미리보기와 내보내기 옵션을 확인합니다.")
                }

                Text("회복 점수와 개인 코칭 문장은 피드 초안에 포함하지 않아요.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let feedDraftMessage {
                    statusMessage(feedDraftMessage, tint: SOOMColor.accent)
                }

                if let feedDraftErrorMessage {
                    statusMessage(feedDraftErrorMessage, tint: SOOMColor.warning)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func statusPill(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.secondaryInk)
            .padding(.horizontal, SOOMLayout.Metrics.pillPadding)
            .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing)
            .background(SOOMColor.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }

    private func statusMessage(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SOOMLayout.Metrics.actionTextSpacing)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ShareCardComposer: View {
    @Environment(\.dismiss) private var dismiss

    let baseCard: ShareableWorkoutCardModel
    let tint: Color
    let renderShareImage: @MainActor (ShareableWorkoutCardModel, Color) -> UIImage?

    @State private var selectedCardIndex = 0
    @State private var shareImage: UIImage?
    @State private var isShareSheetPresented = false
    @State private var isRenderingShareImage = false
    @State private var shareErrorMessage: String?
    @State private var shareTargetMessage: String?
    @State private var pendingSaveCard: ShareableWorkoutCardModel?

    private var selectedType: ShareCardType {
        ShareCardComposerLayout.cardType(at: selectedCardIndex)
    }

    private var configuredCard: ShareableWorkoutCardModel {
        baseCard.configured(
            shareType: selectedType,
            backgroundOption: .transparent
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SOOMLayout.Feed.sectionSpacing) {
                    ShareCardCarousel(
                        baseCard: baseCard,
                        selectedIndex: $selectedCardIndex,
                        tint: tint
                    )

                    ShareTargetGrid(
                        message: shareTargetMessage,
                        handle: { target in handleShareTarget(target, card: configuredCard) }
                    )
                }
                .padding(.horizontal, SOOMLayout.screenPadding)
                .padding(.top, SOOMLayout.stackSpacing)
                .padding(.bottom, SOOMLayout.screenPadding * 2)
            }
            .background(SOOMColor.background.ignoresSafeArea())
            .navigationTitle("공유하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                            .foregroundStyle(SOOMColor.ink)
                    }
                    .accessibilityLabel("공유 카드 닫기")
                }
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if let shareImage {
                WorkoutShareSheet(activityItems: [shareImage])
            }
        }
        .alert(
            "공유 카드를 만들지 못했어요",
            isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        shareErrorMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "잠시 후 다시 시도해주세요.")
        }
        .alert(
            "이미지를 저장할까요?",
            isPresented: Binding(
                get: { pendingSaveCard != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingSaveCard = nil
                    }
                }
            )
        ) {
            Button("취소", role: .cancel) {
                pendingSaveCard = nil
            }
            Button("저장") {
                guard let card = pendingSaveCard else { return }
                pendingSaveCard = nil
                saveImage(card)
            }
        } message: {
            Text("선택한 공유 이미지를 사진 앱에 저장합니다.")
        }
    }

    @MainActor
    private func renderImage(for card: ShareableWorkoutCardModel) async -> UIImage? {
        guard !isRenderingShareImage else { return nil }

        isRenderingShareImage = true
        let preparedImage = await ShareableWorkoutCardRenderer().renderPrepared(card: card, tint: tint)
        let image = preparedImage ?? renderShareImage(card, tint)
        isRenderingShareImage = false
        return image
    }

    @MainActor
    private func share(_ card: ShareableWorkoutCardModel) {
        Task {
            let image = await renderImage(for: card)

            guard let image else {
                shareErrorMessage = "공유 카드 이미지를 만들 수 없어요."
                return
            }

            shareImage = image
            isShareSheetPresented = true
        }
    }

    @MainActor
    private func saveImage(_ card: ShareableWorkoutCardModel) {
        Task {
            let image = await renderImage(for: card)

            guard let image else {
                shareErrorMessage = "공유 카드 이미지를 만들 수 없어요."
                return
            }

            do {
                try await ShareImagePhotoSaver.save(image)
                shareTargetMessage = nil
            } catch {
                shareErrorMessage = "이미지를 사진 앱에 저장하지 못했어요. 사진 접근 권한을 확인해주세요."
            }
        }
    }

    @MainActor
    private func handleShareTarget(_ target: ShareTarget, card: ShareableWorkoutCardModel) {
        shareTargetMessage = nil

        switch target {
        case .instagramStory:
            shareTargetMessage = ShareTarget.instagramStory.helperText
            share(card)
        case .saveImage:
            pendingSaveCard = card
        case .more:
            share(card)
        }
    }
}

private struct ShareCardCarousel: View {
    let baseCard: ShareableWorkoutCardModel
    @Binding var selectedIndex: Int
    let tint: Color

    private var selectedType: ShareCardType {
        ShareCardComposerLayout.cardType(at: selectedIndex)
    }

    var body: some View {
        VStack(spacing: SOOMLayout.stackSpacing) {
            VStack(spacing: SOOMLayout.SectionHeader.spacing) {
                Text("\(selectedType.cardTitle) · \(selectedIndex + 1) / \(ShareCardComposerLayout.cardOrder.count)")
                    .font(SOOMFont.displayMedium(18, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .lineLimit(1)

                Text(WorkoutDetailContent.sharePrivacyCopy)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            TabView(selection: $selectedIndex) {
                ForEach(Array(ShareCardComposerLayout.cardOrder.enumerated()), id: \.offset) { index, type in
                    ShareCardCarouselPreview(
                        card: configuredCard(for: type),
                        tint: tint
                    )
                    .frame(
                        width: ShareComposerCarouselMetrics.previewWidth,
                        height: ShareComposerCarouselMetrics.previewHeight
                    )
                    .tag(index)
                    .padding(.vertical, ShareComposerCarouselMetrics.previewShadowPadding)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(
                width: ShareComposerCarouselMetrics.previewWidth,
                height: ShareComposerCarouselMetrics.previewViewportHeight
            )
            .clipped()

            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                ForEach(ShareCardComposerLayout.cardOrder.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIndex ? SOOMColor.accent : SOOMColor.line)
                        .frame(
                            width: index == selectedIndex ? ShareComposerCarouselMetrics.activeDotWidth : ShareComposerCarouselMetrics.dotSize,
                            height: ShareComposerCarouselMetrics.dotSize
                        )
                        .animation(.easeOut(duration: 0.18), value: selectedIndex)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("\(selectedType.cardTitle) 선택됨")
        }
    }

    private func configuredCard(for type: ShareCardType) -> ShareableWorkoutCardModel {
        baseCard.configured(
            shareType: type,
            backgroundOption: .transparent
        )
    }
}

private struct ShareCardCarouselPreview: View {
    let card: ShareableWorkoutCardModel
    let tint: Color

    var body: some View {
        ZStack {
            if card.backgroundOption.usesCheckerboardPreview {
                ShareCardCheckerboardPreview()
                    .clipShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius + 8, style: .continuous))
            }

            if card.backgroundOption == .transparent {
                RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SOOMColor.black.opacity(0.92),
                                SOOMColor.black.opacity(0.76)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(card.backgroundOption.usesCheckerboardPreview ? ShareComposerCarouselMetrics.transparentPreviewInset : 0)
                    .accessibilityHidden(true)
            }

            ShareableWorkoutCardView(card: card, tint: tint)
                .padding(card.backgroundOption.usesCheckerboardPreview ? ShareComposerCarouselMetrics.transparentPreviewInset : 0)

            if card.backgroundOption.usesCheckerboardPreview {
                ShareTransparencyBadge()
                    .padding(ShareComposerCarouselMetrics.transparencyBadgePadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(
            width: ShareComposerCarouselMetrics.previewWidth,
            height: ShareComposerCarouselMetrics.previewHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius + 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius + 8, style: .continuous))
        .shadow(color: SOOMColor.black.opacity(0.12), radius: 20, x: 0, y: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct ShareCardCheckerboardPreview: View {
    private let tileSize: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / tileSize))
            let rows = Int(ceil(size.height / tileSize))

            for row in 0..<rows {
                for column in 0..<columns {
                    let isDarkTile = (row + column).isMultiple(of: 2)
                    let rect = CGRect(
                        x: CGFloat(column) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isDarkTile ? SOOMColor.surfaceMuted : SOOMColor.white)
                    )
                }
            }
        }
        .overlay(SOOMColor.accent.opacity(0.06))
        .accessibilityHidden(true)
    }
}

private struct ShareTransparencyBadge: View {
    var body: some View {
        Text("투명")
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.accentInk)
            .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
            .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding)
            .background(SOOMColor.white.opacity(0.92))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(SOOMColor.accentLine, lineWidth: SOOMLayout.Card.borderWidth)
            )
    }
}

private enum ShareComposerCarouselMetrics {
    static let previewWidth: CGFloat = 292
    static let previewHeight: CGFloat = previewWidth / ShareableWorkoutCardLayout.aspectRatio
    static let previewShadowPadding: CGFloat = 18
    static let previewViewportHeight: CGFloat = previewHeight + previewShadowPadding * 2
    static let dotSize: CGFloat = 7
    static let activeDotWidth: CGFloat = 22
    static let transparentPreviewInset: CGFloat = 8
    static let transparencyBadgePadding: CGFloat = 14
}

private struct ShareTargetGrid: View {
    let message: String?
    let handle: (ShareTarget) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                SOOMSectionHeader("공유하기", caption: "공개 업로드 없이 선택한 이미지로만 내보내요.")

                LazyVGrid(columns: columns, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    ForEach(ShareTarget.currentTargets) { target in
                        Button {
                            handle(target)
                        } label: {
                            Label(target.title, systemImage: target.icon)
                                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                                .foregroundStyle(SOOMColor.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(SOOMLayout.Card.padding)
                                .background(target == .more ? SOOMColor.accentSurface : SOOMColor.surfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let message {
                    Text(message)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

enum ShareImagePhotoSaveError: Error {
    case unauthorized
    case invalidImageData
}

struct ShareImagePhotoSaver {
    static func save(_ image: UIImage) async throws {
        let status = await requestAuthorizationIfNeeded()
        guard status == .authorized || status == .limited else {
            throw ShareImagePhotoSaveError.unauthorized
        }

        guard let data = image.pngData() else {
            throw ShareImagePhotoSaveError.invalidImageData
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    private static func requestAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch current {
        case .notDetermined:
            return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        default:
            return current
        }
    }
}

struct ActivityDetailRhythmInterpreter {
    static func primaryMessage(
        workout: Workout,
        sessionSummary: WorkoutSessionSummary?,
        splitInsight: WorkoutSplitInsight?,
        weaknessInsight: WorkoutWeaknessInsight?,
        recoveryImpact: WorkoutRecoveryImpact?
    ) -> String {
        messages(
            workout: workout,
            sessionSummary: sessionSummary,
            splitInsight: splitInsight,
            weaknessInsight: weaknessInsight,
            recoveryImpact: recoveryImpact
        )
        .first ?? "운동 데이터가 더 쌓이면 오늘의 리듬을 조금 더 또렷하게 읽을 수 있어요."
    }

    static func messages(
        workout: Workout,
        sessionSummary: WorkoutSessionSummary?,
        splitInsight: WorkoutSplitInsight?,
        weaknessInsight: WorkoutWeaknessInsight?,
        recoveryImpact: WorkoutRecoveryImpact?
    ) -> [String] {
        var messages: [String] = []

        if let sessionSummary {
            messages.append(sessionSummary.summaryText)
        } else if workout.duration > 0 {
            messages.append("오늘은 \(workout.formattedDuration) 동안 움직임을 이어간 기록이에요.")
        } else {
            messages.append("운동 데이터가 더 쌓이면 오늘의 리듬을 조금 더 또렷하게 읽을 수 있어요.")
        }

        if let splitInsight, splitInsight.splitType != .insufficientData {
            messages.append(splitInsight.summary)
        }

        if let weaknessInsight {
            messages.append(weaknessInsight.shortInsight)
        } else if let recoveryImpact {
            messages.append(recoveryImpact.shortMessage)
        }

        return Array(messages.prefix(3))
    }
}

struct ActivityDetailVisibilityPolicy {
    static func showsComparisonInsight(_ insight: WorkoutComparisonInsight?) -> Bool {
        guard let insight else { return false }
        return insight.comparisonType != .insufficientData && !insight.metricRows.isEmpty
    }

    static func showsSplitInsight(_ insight: WorkoutSplitInsight?) -> Bool {
        guard let insight else { return false }
        return insight.splitType != .insufficientData
    }

    static func showsSplits(workout: Workout) -> Bool {
        !workout.splits.isEmpty
    }

    static func showsCharts(workout: Workout) -> Bool {
        !workout.samples.isEmpty
    }

    static func showsHeartRateEffort(workout: Workout, streamSummaries: [WorkoutZoneSummary]?) -> Bool {
        if let streamSummaries, streamSummaries.contains(where: \.isAvailable) {
            return true
        }

        return workout.avgHeartRate > 0 || !workout.zones.isEmpty
    }
}

struct ActivityDetailMetric: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: String

    static func == (lhs: ActivityDetailMetric, rhs: ActivityDetailMetric) -> Bool {
        lhs.label == rhs.label && lhs.value == rhs.value
    }
}

enum ActivityDetailSummaryMetrics {
    /// PDF's "피드 상세 (2)" 통계 그리드(2열×3행, 6칸)와 필드/배치를 맞춘 순서.
    /// 회복 영향은 그리드에서 뺐음 — WorkoutRecoveryImpactCard(회복 섹션)가 이미
    /// 같은 값을 별도로 보여주고 있어 그리드에 남기면 중복이었음. See feed-detail-migration-plan.md batch 2.
    static func metrics(workout: Workout) -> [ActivityDetailMetric] {
        metrics(processedWorkout: ProcessedWorkoutBuilder().make(from: unifiedWorkout(from: workout)))
    }

    static func metrics(processedWorkout: ProcessedWorkout) -> [ActivityDetailMetric] {
        let display = processedWorkout.display
        return [
            ActivityDetailMetric(label: "거리", value: display.distanceText),
            ActivityDetailMetric(label: "상승 고도", value: display.elevationText),
            ActivityDetailMetric(label: "시간", value: display.durationText),
            ActivityDetailMetric(label: "평균 파워", value: display.averagePowerText ?? "—"),
            ActivityDetailMetric(label: movementMetricLabel(for: processedWorkout), value: display.primaryMetricValue),
            ActivityDetailMetric(label: "활동 칼로리", value: display.caloriesText)
        ]
    }

    private static func movementMetricLabel(for processedWorkout: ProcessedWorkout) -> String {
        switch processedWorkout.workoutType {
        case .cycling, .walking:
            return "평균 속도"
        case .running, .hiking:
            return "평균 페이스"
        default:
            return "평균 \(processedWorkout.display.primaryMetricLabel)"
        }
    }

    private static func unifiedWorkout(from workout: Workout) -> UnifiedWorkout {
        UnifiedWorkout(
            id: workout.id,
            externalId: "workout-detail-\(workout.id.uuidString)",
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(workoutSport: workout.sport),
            startDate: workout.date,
            endDate: workout.date.addingTimeInterval(workout.duration),
            durationSeconds: workout.duration,
            distanceMeters: workout.distanceMeters > 0 ? workout.distanceMeters : nil,
            activeEnergyKcal: workout.activeCalories > 0 ? Double(workout.activeCalories) : nil,
            averageHeartRate: workout.avgHeartRate > 0 ? Double(workout.avgHeartRate) : nil,
            maxHeartRate: workout.maxHeartRate > 0 ? Double(workout.maxHeartRate) : nil,
            averageSpeedMetersPerSecond: workout.duration > 0 && workout.distanceMeters > 0 ? workout.distanceMeters / workout.duration : nil,
            elevationGainMeters: workout.elevationGain > 0 ? Double(workout.elevationGain) : nil,
            dataQuality: .partial,
            isExcludedFromAnalysis: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

enum ActivityDetailDistanceCopy {
    static func value(distanceMeters: Double, formattedDistance: String) -> String {
        distanceMeters > 0 ? formattedDistance : "거리 준비 중"
    }
}

private struct WorkoutDetailSectionContainer<Content: View>: View {
    let group: WorkoutDetailSectionGroup
    let reduceMotion: Bool
    @ViewBuilder let content: Content
    @State private var didAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.WorkoutDetail.groupContentSpacing) {
            header
            content
        }
        .padding(.top, SOOMLayout.WorkoutDetail.groupTopPadding)
        .opacity(shouldAnimate ? (didAppear ? SOOMMotion.Opacity.visible : SOOMMotion.Opacity.muted) : SOOMMotion.Opacity.visible)
        .offset(y: shouldAnimate ? (didAppear ? 0 : SOOMMotion.Offset.subtleRevealY) : 0)
        .animation(SOOMMotion.normalEaseOut.delay(Double(group.priority) * 0.03), value: didAppear)
        .onAppear {
            didAppear = true
        }
        .accessibilityElement(children: .contain)
    }

    private var shouldAnimate: Bool {
        !reduceMotion
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.WorkoutDetail.groupHeaderSpacing) {
            Text(group.title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .textCase(.none)

            Text(group.caption)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(group.title)
        .accessibilityValue(group.caption)
    }
}


private extension UnifiedWorkoutType {
    init(workoutSport sport: WorkoutSport) {
        switch sport {
        case .swim:
            self = .swimming
        case .bike, .brick:
            self = .cycling
        case .run:
            self = .running
        }
    }
}
