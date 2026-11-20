import Combine
import SwiftData
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
    @Environment(\.soomProfileOnlyDetailPresentation) private var profileOnlyDetailPresentation
    @Environment(\.historicalRecordedZoneOverlay) private var historicalZoneOverlay
    @Environment(\.workoutManagement) private var management
    @Environment(\.workoutDetailSharing) private var sharing
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var accountStorage: HealthAccountStorageController
    @EnvironmentObject private var auth: AuthViewModel
    @State private var shareScopeID: String?
    @State private var companionEditScope: String?
    @Environment(\.workoutDetailPresentationStore) private var presentationStore
    @Environment(\.workoutDetailVisitStore) private var visitStore
    @State private var localPresentationStore = WorkoutDetailPresentationStore()
    @State private var approvedMapRepair = ApprovedWorkoutMapRepair()

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
    #if DEBUG
    // Review-only injection. Do not feed derived geometry to charts, sharing or analytics.
    var mapOnlyRouteCandidate: WorkoutMapOnlyRouteCandidate? = nil
    #endif
    private var heroMapGeometry: WorkoutRoute? {
        #if DEBUG
        if let mapOnlyRouteCandidate { return mapOnlyRouteCandidate.mapGeometry(for: mapRoute) }
        #endif
        guard sharedRecord == nil, mapRoute?.workoutId == ApprovedWorkoutMapRepair.targetID else { return mapRoute }
        return approvedMapRepair.resolve(mapRoute, viewerID: auth.session.currentUser?.id,
            storage: accountStorage, context: modelContext)
    }
    var sourceUnifiedWorkout: UnifiedWorkout? = nil
    var routeAttachmentAction: ActivityDetailGPXRouteImportAction?
    var companionUpdateAction: WorkoutCompanionUpdateAction?
    var healthKitWorkout: HKWorkout?
    var zoneDataProvider: WorkoutZoneDataProviding?
    var splitDataProvider: WorkoutSplitDataProviding?
    var samplesOverride: [WorkoutSample]?
    var splitsOverride: [WorkoutSplit]?
    var heartRateChartSamplesOverride: [WorkoutDistanceChartSample]?
    var telemetryOverride: WorkoutTelemetry?
    var healthKitReadPresentation: HealthKitDetailReadPresentation?
    var relativeEffortComparisonOverride: RelativeEffortComparison?
    var achievementsOverride: [WorkoutAchievement]?
    var achievementCountOverride: Int?
    var fitnessTrendOverride: FitnessTrend?
    var sharedRecord: WorkoutDetailSharedRecord? = nil
    var renderShareImage: @MainActor (ShareableWorkoutCardModel, Color) -> UIImage? = { card, tint in
        ShareableWorkoutCardRenderer().render(card: card, tint: tint)
    }
    @State private var nativeMeasurementReviewPresented = false
    @State private var nativeMeasurementReviewScope: String?
    @State private var nativeRouteReviewPresented = false
    @State private var nativeRouteReviewScope: String?
    @State private var streamZoneSummaries: [WorkoutZoneSummary]?
    @State private var streamSplitInsight: WorkoutSplitInsight?
    @State private var isLoadingZoneSummaries = false
    @State private var didFailLoadingZoneSummaries = false
    @State private var feedDraftMessage: String?
    @State private var feedDraftErrorMessage: String?
    @State private var isCreatingFeedDraft = false
    @State private var selectedFeedVisibility: ShareableWorkoutVisibility = .privateOnly
    @State private var shareComposerPresentation: WorkoutShareCardPresentation?
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
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            WorkoutRecordHeading(
                title: sharedRecord?.item.recordTitle ?? sourceUnifiedWorkout?.displayTitle ?? workout.title,
                date: sharedRecord?.item.activityDate ?? (sharedRecord == nil ? sourceUnifiedWorkout?.startDate : sharedRecord?.item.createdAt) ?? workout.date,
                sport: sharedRecord?.item.recordSport ?? sourceUnifiedWorkout?.workoutType.shareDisplayName ?? workout.sport.title,
                description: nil,
                visibility: AccountActivityDetailFallbackPolicy.headerVisibility(sharedRecord?.item.activityProjection != nil ? nil : sharedRecord == nil ? (management == nil ? .privatePost : management?.visibility) : sharedRecord?.item.visibility.feedPostVisibility, profileOnlyContext: profileOnlyDetailPresentation),
                sportType: sharedRecord?.item.recordWorkoutType ?? sourceUnifiedWorkout?.workoutType ?? workout.comparisonWorkoutType,
                author: sharedRecord.map { $0.item.authorHandle ?? $0.item.authorName } ?? auth.session.currentUser?.displayName ?? "나",
                authorID: sharedRecord == nil ? auth.session.currentUser?.id : sharedRecord?.item.authorId,
                avatarPath: sharedRecord == nil ? auth.session.currentUser?.avatarPath : sharedRecord?.item.avatarPath,
                device: sharedRecord == nil ? (sourceUnifiedWorkout?.deviceName ?? sourceUnifiedWorkout?.feedSourceLabel ?? workout.source) : sharedRecord?.item.deviceName,
                location: sharedRecord?.item.activityProjection != nil ? "지역 정보 미표시" : FeedCardFormatting.region(sharedRecord == nil ? sourceUnifiedWorkout?.locationName : sharedRecord?.item.locationHint,
                    hasRoute: sharedRecord?.hasRouteImage ?? ((mapRoute?.coordinates.count ?? 0) > 1))
            )
            if let sharedRecord {
                WorkoutRecordMetricsCard(metrics: sharedRecord.presentationMetrics, compact: presentationStyle == .mapSheet)
                if let caption = sharedRecord.item.caption, !caption.isEmpty {
                    Text(caption).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if presentationStyle != .mapSheet {
                WorkoutPhotoMediaRow(workoutID: nil, photos: sharedRecord.item.photos,
                    hasRoute: false) { EmptyView() }
                }
                if let telemetry = historicalZoneOverlay?.applying(to: sharedRecord.presentationTelemetry,
                    id: sharedRecord.item.id, authorID: sharedRecord.item.authorId) ?? sharedRecord.presentationTelemetry {
                    detailSection(.sensorData) {
                        WorkoutTelemetrySection(telemetry: telemetry, workout: sharedRecord.presentationWorkout,
                            route: sharedRecord.route, sharedMeasurementOnly: true)
                    }
                } else {
                    Text("이 기록에서 공유된 추가 측정 데이터는 없어요.")
                        .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                        .accessibilityIdentifier("detail.shared.measurements.notAvailable")
                }
            } else {
                if let sourceUnifiedWorkout {
                    WorkoutRecordMetricsCard(metrics: ActivityWorkoutRow.metrics(sourceUnifiedWorkout)
                        + [WorkoutCardMetric(label: "활동 칼로리", value: sourceUnifiedWorkout.activeEnergyKcal.map { "\(Int($0)) kcal" } ?? "—"),
                           WorkoutCardMetric(label: "평균 파워", value: sourceUnifiedWorkout.averagePowerWatts.map { "\(Int($0)) W" } ?? "—")],
                        compact: presentationStyle == .mapSheet)
                } else {
                    ActivityDetailSummaryCard(workout: workout, processedWorkout: processedWorkout)
                }
                if let description = sourceUnifiedWorkout?.recordDescription, !description.isEmpty {
                    Text(description).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                WorkoutEffortControl(workoutID: sourceUnifiedWorkout?.id ?? workout.id,
                    directory: accountStorage.scopeDirectory, isDemo: ReviewDemoMode.isActive, workout: sourceUnifiedWorkout,
                    canAccess: { [weak accountStorage, expectedScope = accountStorage.scopeID] in accountStorage?.scopeID == expectedScope })
                    .id(accountStorage.scopeID + (sourceUnifiedWorkout?.id ?? workout.id).uuidString
                        + String(sourceUnifiedWorkout?.averageHeartRate ?? 0)
                        + String(sourceUnifiedWorkout?.durationSeconds ?? 0)
                        + String(TrainingSettingsStore.shared.loadSettings().maxHeartRate ?? 0))
                if NativeWorkoutAggregateService.reviewEnabled || ModernChartRuntime.current().ownerReviewEnabled,
                   sourceUnifiedWorkout != nil, accountStorage.userID != nil,
                   auth.session.currentUser?.id == accountStorage.userID {
                    Button("추가 측정 공유 검토") {
                        nativeMeasurementReviewScope = accountStorage.scopeID
                        nativeMeasurementReviewPresented = true
                    }
                    .accessibilityIdentifier("detail.measurementShare.review")
                }
                if NativeRoute50Upload.rawFixtureEnabled, sourceUnifiedWorkout != nil,
                   let owner = accountStorage.userID, auth.session.currentUser?.id == owner {
                    Button("새 공유 경로 50m 검토") {
                        nativeRouteReviewScope = accountStorage.scopeID
                        nativeRouteReviewPresented = true
                    }.accessibilityIdentifier("detail.route50.review")
                }
                detailSection(.sensorData) {
                    if let read = healthKitReadPresentation {
                        VStack(alignment: .leading, spacing: 8) {
                            if !read.message.isEmpty {
                                Text(read.message).font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                                    .accessibilityIdentifier("detail.health.status")
                            }
                            if read.isLoading { ProgressView("측정값 확인 중") }
                            else if let retry = read.retry {
                                Button("건강 측정값 다시 읽기") { Task { await retry() } }
                                    .frame(minHeight: 44).accessibilityIdentifier("detail.health.retry")
                            }
                        }
                    }
                    WorkoutTelemetrySection(telemetry: detailTelemetry,
                        workout: sourceUnifiedWorkout ?? unifiedWorkoutForDraft, route: mapRoute,
                        showsHeartRateZones: telemetryOverride != nil || !ActivityDetailVisibilityPolicy.showsHeartRateEffort(workout: workout, streamSummaries: streamZoneSummaries))
                    if telemetryOverride == nil {
                        if ActivityDetailVisibilityPolicy.showsHeartRateEffort(workout: workout, streamSummaries: streamZoneSummaries) {
                            WorkoutZoneSection(workout: workout, streamSummaries: streamZoneSummaries,
                                isLoadingStream: isLoadingZoneSummaries, didFailLoadingStream: didFailLoadingZoneSummaries)
                        }
                        if ActivityDetailVisibilityPolicy.showsSplits(workout: effectiveWorkout) {
                            WorkoutSplitsCard(workout: effectiveWorkout)
                        }
                    }
                }

                if let management, let error = management.sharingError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                        Button("공개 범위 다시 확인") { Task { await management.refreshSharing() } }.frame(minHeight: 44)
                    }
                }
                if let notice = management?.notice {
                    Text(notice).font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if presentationStyle == .standalone, let heroMapGeometry, RoutePrivacyMasker().mask(route: heroMapGeometry).coordinates.count > 1 {
                    ActivityDetailHeroMap(workout: workout, route: heroMapGeometry, achievements: achievements, routeMissingReason: processedWorkout.routeMissingReason)
                }
                if presentationStyle == .standalone, let sourceUnifiedWorkout {
                    WorkoutPhotoMediaRow(workoutID: sourceUnifiedWorkout.id, photos: [], hasRoute: false) {
                        EmptyView()
                    }
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
                ActivityDetailRhythmCard(insight: rhythmInsight, tint: workout.sport.tint)

                if let terrainInsight, terrainInsight.isVisible {
                    TerrainInsightCue(insight: terrainInsight, tint: workout.sport.tint)
                }

                if !companions.isEmpty || companionUpdateAction != nil {
                WorkoutCompanionCard(
                    sourceTag: processedWorkout.display.sourceTitle,
                    companions: companions,
                    tint: workout.sport.tint,
                    canEditCompanions: companionUpdateAction != nil,
                    isUpdating: isUpdatingCompanions,
                    errorMessage: companionUpdateErrorMessage,
                    onTapEdit: { companionEditScope = accountStorage.scopeID; isCompanionSheetPresented = true }
                )
                }

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

                    WorkoutInsightDisclosure(title: "AI 해석", icon: "sparkles", summary: workout.aiSummary) {
                        Text(workout.aiSummary).font(.body).foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                }


            }
        }
        .environment(\.workoutRevealContext, WorkoutRevealContext(store: visitStore ?? localPresentationStore,
            workoutID: sourceUnifiedWorkout?.id ?? workout.id))
        .onReceive(sharing?.actions.eraseToAnyPublisher() ?? Empty<WorkoutDetailShareActions.Action, Never>().eraseToAnyPublisher()) { action in
            guard sharedRecord == nil, shareScopeID == accountStorage.scopeID else { return }
            switch action {
            case .feed:
                // Ignore stale legacy events. Workout delivery is automatic;
                // this detail surface must not reopen a manual publication flow.
                break
            case .image:
                if let card = shareableCard { shareComposerPresentation = WorkoutShareCardPresentation(card: card) }
            }
        }
        .sheet(item: $shareComposerPresentation) { presentation in
            ShareCardComposer(
                baseCard: presentation.card,
                tint: SOOMColor.accent,
                renderShareImage: renderShareImage
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $nativeMeasurementReviewPresented) {
            if let workout = sourceUnifiedWorkout, let owner = accountStorage.userID,
               auth.session.currentUser?.id == owner, let scope = nativeMeasurementReviewScope,
               modelContext.container === accountStorage.container, !HealthCloudJournal.isRetired(modelContext) {
                let telemetry = try? WorkoutTelemetryStore(modelContext: modelContext).resolved(for: workout)
                let canAccess = { @MainActor in
                    accountStorage.scopeID == scope && accountStorage.userID == owner
                        && auth.session.currentUser?.id == owner && modelContext.container === accountStorage.container
                        && !HealthCloudJournal.isRetired(modelContext)
                }
                NativeMeasurementShareReviewSheet(workout: workout, telemetry: telemetry,
                    owner: owner, canAccess: canAccess)
            }
        }
        .sheet(isPresented: $nativeRouteReviewPresented) {
            if let workout = sourceUnifiedWorkout, let owner = accountStorage.userID,
               auth.session.currentUser?.id == owner, let scope = nativeRouteReviewScope,
               modelContext.container === accountStorage.container, !HealthCloudJournal.isRetired(modelContext) {
                let canAccess = { @MainActor in
                    accountStorage.scopeID == scope && accountStorage.userID == owner
                        && auth.session.currentUser?.id == owner && modelContext.container === accountStorage.container
                        && !HealthCloudJournal.isRetired(modelContext)
                }
                NativeRoute50ReviewSheet(workout: workout, owner: owner, canAccess: canAccess,
                    loadOwnerRoute: {
                        guard canAccess() else { return nil }
                        let route = try await WorkoutTelemetryStore(modelContext: modelContext).resolvedRoute(for: workout)
                        guard canAccess(), route?.workoutId == workout.id, route?.privacyMaskApplied == false else { return nil }
                        return route
                    })
            }
        }
        .onChange(of: accountStorage.scopeID) { _, _ in
            nativeMeasurementReviewPresented = false
            nativeMeasurementReviewScope = nil
            nativeRouteReviewPresented = false
            nativeRouteReviewScope = nil
            shareComposerPresentation = nil
            isCompanionSheetPresented = false; companionEditScope = nil
        }
        .onChange(of: shareableCard?.imageSourceKey) { _, _ in shareComposerPresentation = nil }
        .onAppear {
            if shareScopeID == nil { shareScopeID = accountStorage.scopeID }
        }
        .task(id: workout.id) {
            guard sharedRecord == nil else { return }
            selectedFeedVisibility = accountStorage.defaultWorkoutAudience.shareableVisibility
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
                canAccess: { companionEditScope == accountStorage.scopeID },
                onSave: { names in await updateCompanions(names) }
            )
        }
        .task(id: healthKitWorkout?.uuid) {
            guard sharedRecord == nil else { return }
            await loadStreamZoneSummaries()
            await loadStreamSplitInsight()
        }
    }


    private var detailTelemetry: WorkoutTelemetry {
        if let telemetryOverride, !telemetryOverride.isEmpty { return telemetryOverride }
        let start = (sourceUnifiedWorkout ?? unifiedWorkoutForDraft).startDate
        var telemetry = WorkoutTelemetry(workoutID: workout.id, source: (sourceUnifiedWorkout ?? unifiedWorkoutForDraft).source)
        telemetry.samples = effectiveWorkout.samples.compactMap { sample in
            guard sample.minute.isFinite, sample.minute >= 0 else { return nil }
            return WorkoutTelemetrySample(timestamp: start.addingTimeInterval(sample.minute * 60),
                heartRateBPM: sample.heartRate.map(Double.init), powerWatts: sample.power.map(Double.init))
        }
        return telemetry
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        _ group: WorkoutDetailSectionGroup,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if group.isVisible(inSharedDetail: sharedRecord != nil) {
            WorkoutDetailSectionContainer(group: group, reduceMotion: reduceMotion) {
                if group == .growth {
                    WorkoutInsightDisclosure(title: group.title, icon: "chart.line.uptrend.xyaxis",
                        summary: growthSummary?.shortSummary ?? "이 운동의 성장 지표와 이전 기록을 확인해요.") { content() }
                } else { content() }
            }
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
    private func updateCompanions(_ names: [String]) async -> WorkoutCompanionUpdateResult {
        guard let companionUpdateAction, companionEditScope == accountStorage.scopeID, !Task.isCancelled else { return .failure(.persistenceFailed) }
        let scope = accountStorage.scopeID

        isUpdatingCompanions = true
        companionUpdateErrorMessage = nil

        let result = await companionUpdateAction.updateCompanions(names)
        guard scope == accountStorage.scopeID, !Task.isCancelled else { isUpdatingCompanions = false; return .failure(.persistenceFailed) }
        switch result {
        case .success(let savedNames):
            companionNamesOverride = savedNames
            companionUpdateErrorMessage = nil
        case .failure(let error):
            companionUpdateErrorMessage = error.message
        }

        isUpdatingCompanions = false
        return result
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
        defer { isLoadingZoneSummaries = false }
        didFailLoadingZoneSummaries = false

        do {
            let summaries = try await zoneDataProvider.summaries(for: healthKitWorkout, sport: workout.sport)
            try Task.checkCancellation()
            streamZoneSummaries = summaries.contains { $0.isAvailable } ? summaries : nil
        } catch is CancellationError {
            return // Dismissal is not a missing measurement or a failed read.
        } catch {
            didFailLoadingZoneSummaries = true
        }
    }

    @MainActor
    private func loadStreamSplitInsight() async {
        guard let healthKitWorkout, let splitDataProvider else {
            streamSplitInsight = nil
            return
        }

        do {
            let insight = try await splitDataProvider.insight(
                for: healthKitWorkout,
                current: workoutGrowthInput
            )
            try Task.checkCancellation()
            streamSplitInsight = insight
        } catch is CancellationError {
            return
        } catch {
            // Preserve an already displayed result after a transient read error.
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
            workoutType: workout.comparisonWorkoutType,
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
    private func createFeedDraft() {
        guard ImportedWorkoutPublication.usesLegacyPublication else { return }
        // A preview cannot silently publish the original description instead of
        // the edited draft, nor drop selected mention identities during a write.
        if FeedMentionPicker.isPreviewEnabled {
            feedDraftErrorMessage = "멘션 미리보기 모드에서는 게시하지 않습니다. 본문과 멘션을 함께 저장하는 서버 연결이 필요해요."
            return
        }
        guard !isCreatingFeedDraft, let scope = shareScopeID,
              scope == accountStorage.scopeID else { return }

        // Capture the workout and its account-owned dependencies in the
        // button callback, before an unstructured Task can be delayed.
        let owner = accountStorage.userID
        let store = FileFeedShareDraftStore.live
        let workout = unifiedWorkoutForDraft
        let visibility = selectedFeedVisibility
        let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient()
        let remotePoster: (any FeedRemotePostPosting)? = ReviewDemoMode.isActive
            ? ReviewDemoCommunityStore.shared
            : owner.flatMap { owner in
                client.map { SupabaseFeedRemoteClient(client: $0, expectedPostingUserID: owner) }
            }
        let fallbackRoute = mapRoute
        let validateShareContext: @MainActor () throws -> Void = {
            guard accountStorage.scopeID == scope, accountStorage.userID == owner else {
                throw CommunitySafetyError.accountChanged
            }
            if let client, client.auth.currentSession?.user.id != owner {
                throw CommunitySafetyError.accountChanged
            }
            guard modelContext.container === accountStorage.container else { throw CommunitySafetyError.accountChanged }
            if sourceUnifiedWorkout != nil {
                let id = workout.id
                guard try !modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id })).isEmpty else {
                    throw WorkoutRecordManagementError.missingRecord
                }
            }
        }
        let rankingPublication = SocialRankingPublicationContext()
        let automaticShare = UnifiedWorkoutAutomaticShare(context: modelContext, validate: validateShareContext,
            makeSecondaryPrivate: { member in
                guard owner != nil else { return }
                let model = WorkoutRecordManagement(workout: member)
                model.configure(context: modelContext, storage: accountStorage)
                guard await model.setVisibility(.privatePost) else { throw WorkoutRecordManagementError.unavailable }
            })
        let coordinator = RecordShareDraftCoordinator(
            store: store, remotePoster: remotePoster, visibilityProvider: { visibility },
            validateContext: validateShareContext,
            prepareWorkout: { workout in
                guard sourceUnifiedWorkout != nil else { return workout }
                try validateShareContext()
                _ = await WorkoutRegionEnricher.resolveAndPersist(workoutID: workout.id,
                    context: modelContext, scopeID: scope, isCurrent: {
                        accountStorage.scopeID == scope && accountStorage.userID == owner
                            && modelContext.container === accountStorage.container
                    })
                try validateShareContext()
                let id = workout.id
                guard let record = try modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>(
                    predicate: #Predicate { $0.id == id })).first else {
                    throw WorkoutRecordManagementError.missingRecord
                }
                _ = record // Existence checked above; publish the unified snapshot, not this raw row.
                let prepared = try await automaticShare.prepare(workoutID: workout.id)
                if SocialRankingReleaseGate.productionReady {
                    rankingPublication.intent = try automaticShare.rankingContribution(primaryID: prepared.id)
                }
                return prepared
            },
            prepareRemoteShare: { workout in
                guard let owner, let client else { return }
                try validateShareContext()
                let storedRoute = try await WorkoutTelemetryStore(modelContext: modelContext).resolvedRoute(for: workout)
                try validateShareContext()
                let sharedRoute = storedRoute ?? (sourceUnifiedWorkout == nil ? fallbackRoute : nil)
                let measurements = try WorkoutTelemetryStore(modelContext: modelContext).resolved(for: workout)
                let sharedService = SupabaseWorkoutSharedDetailService(client: client)
                let sharedEnabled = try await sharedService.enabled()
                try await sharedService.prepare(workout: workout,
                    route: sharedRoute, telemetry: measurements, ownerID: owner)
                try validateShareContext()
                if sharedEnabled { return }
                guard let route = sharedRoute,
                      route.workoutId == workout.id else { return }
                let data = try await WorkoutRouteSnapshotRenderer().render(route: route, workoutType: workout.workoutType)
                try validateShareContext()
                guard let data else { return }
                try await WorkoutPhotoService(client: client).uploadRoute(workout: workout, ownerID: owner, data: data)
                try validateShareContext()
            }
        )
        isCreatingFeedDraft = true
        feedDraftMessage = nil
        feedDraftErrorMessage = nil

        Task { @MainActor in
            do {
                var outcome = try await coordinator.handle(.shareToFeed, workout: workout)
                guard scope == accountStorage.scopeID else { return }
                feedDraftMessage = outcome?.summaryMessage
                    ?? "온라인에 게시되지 않았어요. 이 기기에 공유 초안으로 저장했어요."
                // Posting is already confirmed. Registration is isolated and never
                // enters the posting retry/local-draft fallback path.
                if outcome?.postedRemotely == true, outcome?.visibility == .publicFeed,
                   SocialRankingReleaseGate.productionReady, let intent = rankingPublication.intent,
                   let owner, let client {
                    let safety = CommunitySafetyStore.shared
                    let result = await SocialRankingContributionClient(client: client, viewer: owner,
                        generation: safety.accountGeneration, safetyRevision: safety.revision)
                        .registerPublished(intent, store: SocialRankingRetryStore(directory: accountStorage.scopeDirectory, ownerID: owner))
                    guard scope == accountStorage.scopeID, accountStorage.userID == owner else { return }
                    outcome?.rankingRegistrationPending = result != .registered
                }
                if let confirmed = outcome, confirmed.postedRemotely {
                    outcome?.finalizeConfirmedPublication {
                        try automaticShare.complete(primaryID: confirmed.draft.sourceWorkoutId)
                    }
                    await management?.refreshSharing()
                }
                if let outcome { feedDraftMessage = outcome.summaryMessage }
                NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: owner)
            } catch {
                guard scope == accountStorage.scopeID else { return }
                feedDraftErrorMessage = (error as? RecordSharePublicationError)?.message ?? CommunitySafetyError.message(for: error)
            }
            isCreatingFeedDraft = false
        }
    }

    private var unifiedWorkoutForDraft: UnifiedWorkout {
        if let sourceUnifiedWorkout { return sourceUnifiedWorkout }
        return UnifiedWorkout(
            id: workout.id,
            externalId: "workout-detail-\(workout.id.uuidString)",
            source: .soomLocal,
            workoutType: workout.comparisonWorkoutType,
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
                Image(soom: icon)
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
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
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
                Image(soom: SOOMIcon.map)
                    .font(.system(size: SOOMFont.Size.body, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("경로 데이터 없음")
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(tint)

                    Text(fallbackMessage)
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("원본 앱에서 GPX 또는 FIT 파일을 내보내면 이 운동에 경로를 추가할 수 있습니다.")
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsImportAction {
                        Button(action: importAction) {
                            Label(isImporting ? "경로 추가 중" : "경로 파일 가져오기", soomIcon: SOOMIcon.share)
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
            .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
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
                    SOOMSportIconView(name: workout.sport.iconName, size: 21)
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
    @Binding var selectedVisibility: ShareableWorkoutVisibility
    let isCreatingFeedDraft: Bool
    let feedDraftMessage: String?
    let feedDraftErrorMessage: String?
    let createFeedDraft: () -> Void
    let openImageShare: () -> Void

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                SOOMSectionHeader("공유")

                Text(ProfileOnlyPrivacyReleaseGate.productionReady ? "운동 요약은 자동으로 반영돼요. 공개·비공개는 프로필에서만 선택하며, 비공개 프로필의 운동은 서로 팔로우한 사람만 볼 수 있어요." : "운동은 본인 피드에 자동으로 표시돼요. 공개·비공개는 계정 설정에서 관리하며, 비공개 계정은 승인된 팔로워만 볼 수 있어요. 기존 기록의 공유 범위는 전환 확인 전 유지돼요.")
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)

                if canShareImage {
                    Button(action: openImageShare) {
                        Label("이미지로 공유하기", soomIcon: SOOMIcon.share)
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
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
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
        Label(title, soomIcon: icon)
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.secondaryInk)
            .padding(.horizontal, SOOMLayout.Metrics.pillPadding)
            .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing)
            .background(SOOMColor.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }

    private func statusMessage(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SOOMLayout.Metrics.actionTextSpacing)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

/// The sheet receives its content and identity together, including first presentation.
struct WorkoutShareCardPresentation: Identifiable {
    let id = UUID()
    let card: ShareableWorkoutCardModel
}

struct WorkoutShareImagePresentation: Identifiable {
    let id = UUID()
    let image: UIImage

    init?(image: UIImage?) {
        guard let image, image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0,
              let pixels = image.cgImage, pixels.width > 0, pixels.height > 0 else { return nil }
        self.image = image
    }
}

@MainActor
final class WorkoutShareImagePreparation: ObservableObject {
    @Published private(set) var isPreparing = false
    @Published var errorMessage: String?
    private var generation = UUID()

    func prepare(render: @MainActor () async -> UIImage?) async -> WorkoutShareImagePresentation? {
        // A repeated tap does not turn an in-flight render into a failure alert.
        guard !isPreparing else { return nil }
        let request = generation
        isPreparing = true
        errorMessage = nil
        defer { if request == generation { isPreparing = false } }
        let image = await render()
        guard request == generation, !Task.isCancelled else { return nil }
        guard let payload = WorkoutShareImagePresentation(image: image) else {
            errorMessage = "공유 카드 이미지를 만들 수 없어요. 닫고 다시 시도해 주세요."
            return nil
        }
        return payload
    }

    func cancel() {
        generation = UUID()
        isPreparing = false
        errorMessage = nil
    }
}

private struct ShareCardComposer: View {
    @Environment(\.dismiss) private var dismiss

    let baseCard: ShareableWorkoutCardModel
    let tint: Color
    let renderShareImage: @MainActor (ShareableWorkoutCardModel, Color) -> UIImage?

    @State private var selectedCardIndex = 0
    @State private var sharePresentation: WorkoutShareImagePresentation?
    @StateObject private var imagePreparation = WorkoutShareImagePreparation()
    @State private var shareTargetMessage: String?
    @State private var pendingSaveCard: ShareableWorkoutCardModel?

    private var cardTypes: [ShareCardType] { ShareCardComposerLayout.availableCardTypes(for: baseCard) }

    private var selectedType: ShareCardType {
        cardTypes.indices.contains(selectedCardIndex) ? cardTypes[selectedCardIndex] : .workout
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
                    .disabled(imagePreparation.isPreparing)
                    if imagePreparation.isPreparing {
                        ProgressView("공유 이미지 준비 중")
                            .accessibilityIdentifier("share.image.preparing")
                    }
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
                        Image(soom: "xmark")
                            .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                            .foregroundStyle(SOOMColor.ink)
                    }
                    .accessibilityLabel("공유 카드 닫기")
                }
            }
        }
        .sheet(item: $sharePresentation) { presentation in
            WorkoutShareSheet(activityItems: [presentation.image])
        }
        .onDisappear { imagePreparation.cancel() }
        .onChange(of: selectedCardIndex) { _, _ in
            imagePreparation.cancel(); sharePresentation = nil; pendingSaveCard = nil
        }
        .alert(
            "공유 카드를 만들지 못했어요",
            isPresented: Binding(
                get: { imagePreparation.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        imagePreparation.errorMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(imagePreparation.errorMessage ?? "잠시 후 다시 시도해주세요.")
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
    private func prepareImage(for card: ShareableWorkoutCardModel) async -> WorkoutShareImagePresentation? {
        guard card.id == baseCard.id, card.canExportShareImage else { return nil }
        return await imagePreparation.prepare {
            let prepared = await ShareableWorkoutCardRenderer().renderPrepared(card: card, tint: tint)
            return prepared ?? renderShareImage(card, tint)
        }
    }

    @MainActor
    private func share(_ card: ShareableWorkoutCardModel) {
        Task {
            guard let presentation = await prepareImage(for: card) else { return }
            sharePresentation = presentation
        }
    }

    @MainActor
    private func saveImage(_ card: ShareableWorkoutCardModel) {
        Task {
            guard let presentation = await prepareImage(for: card) else { return }
            do {
                try await ShareImagePhotoSaver.save(presentation.image)
                shareTargetMessage = nil
            } catch {
                imagePreparation.errorMessage = "이미지를 사진 앱에 저장하지 못했어요. 사진 접근 권한을 확인해주세요."
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

    private var cardTypes: [ShareCardType] { ShareCardComposerLayout.availableCardTypes(for: baseCard) }

    private var selectedType: ShareCardType {
        cardTypes.indices.contains(selectedIndex) ? cardTypes[selectedIndex] : .workout
    }

    var body: some View {
        VStack(spacing: SOOMLayout.stackSpacing) {
            VStack(spacing: SOOMLayout.SectionHeader.spacing) {
                Text("\(selectedType.cardTitle) · \(selectedIndex + 1) / \(cardTypes.count)")
                    .font(SOOMFont.displayMedium(18, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("share.card.selection")

                Text(WorkoutDetailContent.sharePrivacyCopy)
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            TabView(selection: $selectedIndex) {
                ForEach(Array(cardTypes.enumerated()), id: \.offset) { index, type in
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
            .accessibilityIdentifier("share.card.carousel")
            .frame(
                width: ShareComposerCarouselMetrics.previewWidth,
                height: ShareComposerCarouselMetrics.previewViewportHeight
            )
            .clipped()

            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                ForEach(cardTypes.indices, id: \.self) { index in
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
                            Label(target.title, soomIcon: target.icon)
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
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
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
            workoutType: workout.comparisonWorkoutType,
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
    @Environment(\.workoutRevealContext) private var revealContext

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.WorkoutDetail.groupContentSpacing) {
            if group != .growth { header }
            content
        }
        .padding(.top, SOOMLayout.WorkoutDetail.groupTopPadding)
        .opacity(shouldAnimate ? (didAppear ? SOOMMotion.Opacity.visible : SOOMMotion.Opacity.muted) : SOOMMotion.Opacity.visible)
        .offset(y: shouldAnimate ? (didAppear ? 0 : SOOMMotion.Offset.subtleRevealY) : 0)
        .animation(SOOMMotion.normalEaseOut.delay(Double(group.priority) * 0.03), value: didAppear)
        .onAppear {
            let first = revealContext?.claim("sections.\(group.priority)") ?? !didAppear
            var transaction = Transaction()
            transaction.disablesAnimations = !first || reduceMotion
            withTransaction(transaction) { didAppear = true }
        }
        .accessibilityElement(children: .contain)
    }

    private var shouldAnimate: Bool {
        !reduceMotion
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.WorkoutDetail.groupHeaderSpacing) {
            Text(group.title)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .textCase(.none)

            Text(group.caption)
                .font(SOOMFont.body(14, relativeTo: .subheadline))
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

/// Query evidence in the currently scoped ModelContext; no HealthKit/server reads or writes.
struct WorkoutSourceEvidenceView: View {
    let workoutID: UUID
    var compact = false
    @Query private var records: [UnifiedWorkoutRecord]
    @Query private var storedRoutes: [PersistedWorkoutRoute]
    init(workoutID: UUID, date: Date, compact: Bool = false) {
        self.workoutID = workoutID; self.compact = compact
        let lower = date.addingTimeInterval(-86_400), upper = date.addingTimeInterval(86_400)
        _records = Query(filter: #Predicate<UnifiedWorkoutRecord> { $0.startDate >= lower && $0.startDate <= upper })
        if compact {
            let emptyID = UUID()
            _storedRoutes = Query(filter: #Predicate<PersistedWorkoutRoute> { $0.workoutId == emptyID })
        }
    }
    private var evidence: UnifiedWorkoutProvenance? {
        let originals = records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }
        guard let group = UnifiedWorkoutDeduplicationEngine().canonicalGroups(originals)
            .first(where: { $0.sourceWorkouts.contains { $0.id == workoutID } }) else { return nil }
        return UnifiedWorkoutProvenance(group: group)
    }
    private func overlappingSources(_ evidence: UnifiedWorkoutProvenance) -> [UnifiedWorkout] {
        let ids = Set(evidence.group.sourceWorkouts.map(\.id))
        return records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }.filter { original in
            !ids.contains(original.id) && evidence.group.sourceWorkouts.contains {
                UnifiedWorkoutDeduplicationEngine().compare($0, original) != nil
            }
        }
    }
    var body: some View {
        if let evidence {
            let overlaps = overlappingSources(evidence)
            VStack(alignment: .leading, spacing: 8) {
                Text(evidence.orderedSources.map(\.recordingSourceLabel).joined(separator: " + "))
                    .font(.caption.weight(.semibold))
                Text(evidence.status).font(.caption).foregroundStyle(.secondary)
                if !overlaps.isEmpty {
                    Text("겹치는 다른 원본 \(overlaps.count)건 · 합치기 확인 전: " + overlaps.map(\.recordingSourceLabel).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !compact {
                    Text("원본을 삭제하거나 덮어쓰지 않습니다. 피드 한 건은 두 기기 수집 완료의 증거가 아닙니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    sourceRow("거리", source: evidence.source(for: \.distanceMeters))
                    sourceRow("시간", source: evidence.group.workout)
                    sourceRow("평균 심박", source: evidence.source(for: \.averageHeartRate))
                    sourceRow("최대 심박", source: evidence.source(for: \.maxHeartRate))
                    sourceRow("칼로리", source: evidence.source(for: \.activeEnergyKcal))
                    // Inspect persisted GPS, not routeMissingReason (which may predate route fetch).
                    let routeSource = (evidence.isConfirmed ? evidence.orderedSources : [evidence.group.workout]).first { original in
                        guard let record = storedRoutes.first(where: { route in
                            route.workoutId == original.id || (original.source == .appleHealthKit && route.workoutId.uuidString == original.externalId)
                        }) else { return false }
                        let route = WorkoutRouteMapper().makeRoute(from: record)
                        return route.coordinates.filter { point in
                            guard let time = point.timestamp else { return true }
                            return time >= evidence.group.workout.startDate && time <= evidence.group.workout.endDate
                        }.count > 1
                    }
                    sourceRow("GPS 경로", source: routeSource)
                    let streamSources = (evidence.isConfirmed ? evidence.orderedSources : [evidence.group.workout]).filter { original in
                        guard let data = records.first(where: { $0.id == original.id })?.telemetryData,
                              let stream = try? JSONDecoder().decode(WorkoutTelemetry.self, from: data) else { return false }
                        return stream.validated(for: original).samples.contains { $0.heartRateBPM != nil }
                    }
                    Text("심박 시계열 수집: " + (streamSources.isEmpty ? "미수집" : streamSources.map(\.recordingSourceLabel).joined(separator: ", ")))
                        .font(.footnote)
                    Text("속도·페이스는 선택된 거리와 시간에서 계산합니다. 심박 요약 보완은 전체 시계열의 수집 완료를 뜻하지 않습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup("보관된 원본 ID·측정값") {
                        ForEach(evidence.orderedSources) { original in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(original.recordingSourceLabel)
                                Text("SOOM ID: \(original.id.uuidString)")
                                Text("원본 ID: \(original.externalId ?? "없음")")
                                Text("\(FeedCardFormatting.distance(original.distanceMeters)) · \(FeedCardFormatting.duration(original.durationSeconds)) · 심박 \(original.averageHeartRate.map { String(format: "%.0f bpm", $0) } ?? "미수집")")
                            }.font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            .accessibilityElement(children: compact ? .combine : .contain)
            .accessibilityIdentifier(compact ? "workout.source.badge" : "workout.source.evidence")
        }
    }
    private func sourceRow(_ label: String, source: UnifiedWorkout?) -> some View {
        Text("\(label): \(source?.recordingSourceLabel ?? "미수집")")
            .font(.footnote).accessibilityIdentifier("workout.source.\(label)")
    }
}

/// Compact interpretation with an explicit, accessible expansion control.
struct WorkoutInsightDisclosure<Content: View>: View {
    let title: String
    let icon: String
    let summary: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    private var shortSummary: String {
        let paragraph = summary.components(separatedBy: "\n").first ?? summary
        let first = paragraph.components(separatedBy: ". ").first ?? paragraph
        return first.count > 120 ? String(first.prefix(117)) + "…" : first
    }
    var body: some View {
        SOOMCard {
            Label(title, systemImage: icon).font(.headline)
            Text(shortSummary).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if expanded { content() }
            Button(expanded ? "접기" : "자세히 보기") { expanded.toggle() }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                .accessibilityLabel(title + (expanded ? " 접기" : " 자세히 보기"))
                .accessibilityValue(expanded ? "펼쳐짐" : "접힘")
        }.accessibilityElement(children: .contain)
    }
}


/// Owner-only panel. Loading a review never opts in. A toggle on this
/// particular workout must be affirmed afresh before Apply becomes enabled.
private struct NativeMeasurementShareReviewSheet: View {
    let workout: UnifiedWorkout
    let telemetry: WorkoutTelemetry?
    let owner: UUID
    let canAccess: @MainActor () -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var review: NativeWorkoutAggregateService.Review?
    @State private var modernReview: ModernSourceChartAdapter.Review?
    @State private var affirmed = false
    @State private var busy = false
    @State private var status: String?
    @State private var confirmingWithdrawal = false

    private var available: NativeWorkoutSharedAggregateInput? {
        telemetry.flatMap { NativeWorkoutSharedAggregateInput.build(workout: workout, telemetry: $0,
            explicitAcknowledgement: NativeWorkoutSharedAggregateInput.noticeVersion) }
    }

    private var modernAdapter: ModernSourceChartAdapter? {
        ModernSourceChartAdapter.active(ownerReview: true)
    }

    private var availableModern: ModernSourceChartInput? {
        telemetry.flatMap { ModernSourceChartInput.build(workout: workout, telemetry: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("이 운동의 추가 측정") {
                    Text("기록이 있는 랩·심박 구간·측정 구간만 공유해요. 이미 이 운동의 측정 정보를 볼 권한이 있는 사람에게만 표시돼요.")
                    Text("AI 해석, 회복 정보, 개인 심박 기준은 공유하지 않아요. 언제든 여기서 추가 공유를 끌 수 있어요.")
                    if modernReview != nil, let modern = availableModern {
                        if !modern.samples.isEmpty {
                            let measured = modern.render(cardID: workout.id, start: workout.startDate).samples
                            let channels = WorkoutTelemetryChannel.allCases.filter { channel in
                                measured.contains { $0.value(for: channel) != nil }
                            }
                            if !channels.isEmpty {
                                Label(channels.map(\.title).joined(separator: " · "), systemImage: "chart.xyaxis.line")
                            }
                        }
                        if let supplement = modern.supplement {
                            if !supplement.lapIntervals.isEmpty { Label("실제 랩·구간 시간", systemImage: "stopwatch") }
                            if supplement.zoneSeconds != nil { Label("심박 존 1–5 시간", systemImage: "heart") }
                            if !(supplement.measuredIntervals?.isEmpty ?? true) { Label("실제로 기록된 측정 구간", systemImage: "list.bullet") }
                        }
                        if !modern.pauses.isEmpty { Label("일시정지 전후의 실제 측정 시각", systemImage: "clock") }
                    } else if let available {
                        if !available.lapIntervals.isEmpty { Label("실제 랩·구간 시간", systemImage: "stopwatch") }
                        if available.zoneSeconds != nil { Label("심박 존 1–5 시간", systemImage: "heart") }
                        if available.elapsedTimeline != nil { Label("일시정지 전후의 실제 측정 시각", systemImage: "clock") }
                        if !(available.measuredIntervals?.isEmpty ?? true) {
                            Label("기록된 걸음 수·거리·칼로리·스트로크 등 측정 구간", systemImage: "chart.xyaxis.line")
                        }
                    } else { Text("이 운동에 추가 공유할 측정 기록이 없어요.") }
                }
                if (modernReview?.canApply == true && availableModern != nil)
                    || (modernReview == nil && review?.canApply == true && available != nil) {
                    Section("공유에 동의") {
                        Toggle("이 운동의 추가 측정을 공유할게요", isOn: $affirmed)
                            .accessibilityIdentifier("detail.measurementShare.affirm")
                        Button("공유 적용") { Task { await apply() } }
                            .disabled(!affirmed || busy)
                            .accessibilityIdentifier("detail.measurementShare.apply")
                    }
                }
                if modernReview?.hasSaved == true || review?.hasSavedSupplement == true {
                    Button("추가 측정 공유 철회", role: .destructive) { confirmingWithdrawal = true }
                        .disabled(busy)
                        .accessibilityIdentifier("detail.measurementShare.withdraw")
                }
                if busy { ProgressView() }
                if let status { Text(status).font(.footnote) }
            }
            .navigationTitle("추가 측정 공유")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.disabled(busy) } }
        }
        .task { await reload() }
        .confirmationDialog("이 운동의 추가 측정 공유를 철회할까요?", isPresented: $confirmingWithdrawal) {
            Button("공유 철회", role: .destructive) { Task { await withdraw() } }
        } message: { Text("추가 공유한 랩·심박 구간·측정 구간만 내려요. 운동의 기본 기록은 유지돼요.") }
    }

    @MainActor private func reload() async {
        defer { busy = false }
        busy = true
        do {
            if let modernAdapter, let next = try await modernAdapter.review(source: workout.id, owner: owner, current: canAccess) {
                guard canAccess(), !Task.isCancelled else { return }
                modernReview = next
                review = nil
                if !next.canApply && status == nil { status = "이 운동은 현재 추가 측정을 공유할 수 없어요." }
                return
            }
            guard canAccess(), !Task.isCancelled else { return }
            modernReview = nil
            let next = try await NativeWorkoutAggregateService.review(sourceID: workout.id, ownerID: owner, isCurrent: canAccess)
            guard canAccess(), !Task.isCancelled else { return }
            review = next
            if next?.canApply != true && status == nil { status = "이 운동은 현재 추가 측정을 공유할 수 없어요." }
        } catch { if canAccess() { status = "공유 설정을 확인하지 못했어요. 다시 열어 확인해 주세요." } }
    }

    @MainActor private func apply() async {
        guard !busy, canAccess(), affirmed, let telemetry else { return }
        busy = true
        affirmed = false
        do {
            let ok: Bool
            if let modernReview, let modernAdapter {
                ok = try await modernAdapter.apply(workout: workout, telemetry: telemetry,
                    review: modernReview, affirmed: true, current: canAccess)
            } else if modernReview == nil, let acknowledgement = review?.acknowledgement(affirmed: true) {
                ok = try await NativeWorkoutAggregateService.upload(workout: workout, telemetry: telemetry,
                    acknowledgement: acknowledgement, isCurrent: canAccess)
            } else { ok = false }
            guard canAccess(), !Task.isCancelled else { return }
            status = ok ? "이 운동의 추가 측정을 공유했어요." : "공유하지 못했어요. 공개 범위와 동의를 다시 확인해 주세요."
        } catch { if canAccess() { status = "저장되지 않았어요. 다시 확인해 주세요." } }
        await reload()
    }

    @MainActor private func withdraw() async {
        guard !busy, canAccess() else { return }
        busy = true
        affirmed = false
        do {
            let ok: Bool
            if let modernReview, let modernAdapter { ok = try await modernAdapter.withdraw(review: modernReview, current: canAccess) }
            else if modernReview == nil, let review { ok = try await NativeWorkoutAggregateService.withdraw(review: review, isCurrent: canAccess) }
            else { ok = false }
            guard canAccess(), !Task.isCancelled else { return }
            status = ok ? "이 운동의 추가 측정 공유를 철회했어요." : "공유 상태가 바뀌었어요. 다시 확인해 주세요."
        } catch { if canAccess() { status = "공유 철회를 확인하지 못했어요." } }
        await reload()
    }
}


/// A masked line is drawn entirely on-device. No map tiles, markers, URLs or
/// network requests receive the original route while the owner is reviewing.
private struct NativeRoute50ReviewSheet: View {
    let workout: UnifiedWorkout
    let owner: UUID
    let canAccess: @MainActor () -> Bool
    let loadOwnerRoute: @MainActor () async throws -> WorkoutRoute?
    @Environment(\.dismiss) private var dismiss
    @State private var review: NativeRoute50Upload.Review?
    @State private var ownerRoute: WorkoutRoute?
    @State private var preview: ShareRouteGeometry?
    @State private var affirmed = false
    @State private var busy = false
    @State private var withdrawConfirm = false
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("공유될 경로 미리보기") {
                    Text("출발과 도착 지점에서 각각 50m 안쪽은 표시하지 않아요. 기존 공유 기록은 바뀌지 않아요.")
                    if let preview {
                        Canvas { context, size in
                            let fitted = preview.fittedPoints(in: CGRect(origin: .zero, size: size))
                            var previous: Int?
                            var path = Path()
                            for (point, position) in zip(preview.points, fitted) {
                                if previous == point.segmentIndex { path.addLine(to: position) }
                                else { path.move(to: position) }
                                previous = point.segmentIndex
                            }
                            context.stroke(path, with: .color(SOOMColor.accent), lineWidth: 3)
                        }
                        .frame(height: 150)
                        .accessibilityLabel("출발과 도착 위치가 가려진 경로")
                        .accessibilityIdentifier("detail.route50.maskedPreview")
                    } else if !busy { Text("안전하게 표시할 수 있는 공유 경로가 없어요.") }
                    Text("공유할 때만 서버가 원본 경로를 검사해 가린 경로를 저장해요. 원본 위치는 다른 사람에게 표시되지 않아요.")
                }
                if review?.canApply == true, preview != nil {
                    Section("이 운동만 공유") {
                        Toggle("출발·도착 50m를 가린 경로를 공유할게요", isOn: $affirmed)
                            .accessibilityIdentifier("detail.route50.affirm")
                        Button("경로 공유") { Task { await apply() } }
                            .disabled(busy || !affirmed)
                            .accessibilityIdentifier("detail.route50.apply")
                    }
                }
                if review?.hasSavedRoute == true {
                    Button("이 경로 공유 철회", role: .destructive) { withdrawConfirm = true }
                        .disabled(busy).accessibilityIdentifier("detail.route50.withdraw")
                }
                if busy { ProgressView() }
                if let status { Text(status).font(.footnote) }
            }
            .navigationTitle("50m 경로 공유")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.disabled(busy) } }
        }.task { await refresh(loadPreview: true) }
        .confirmationDialog("이 운동의 50m 경로 공유를 철회할까요?", isPresented: $withdrawConfirm) {
            Button("경로 공유 철회", role: .destructive) { Task { await withdraw() } }
        }
    }

    @MainActor private func refresh(loadPreview: Bool) async {
        busy = true
        defer { busy = false }
        do {
            if loadPreview {
                let route = try await loadOwnerRoute()
                guard canAccess(), !Task.isCancelled else { return }
                ownerRoute = route
                if let route {
                    let masked = NativeRoute50Upload.maskedPreview(workout: workout, route: route)
                    preview = ShareRouteGeometry(coordinates: masked.route.map {
                        .init(latitude: $0.latitude, longitude: $0.longitude, segmentIndex: $0.segment)
                    })
                } else { preview = nil }
            }
            let next = try await NativeRoute50Upload.review(sourceID: workout.id, ownerID: owner, isCurrent: canAccess)
            guard canAccess(), !Task.isCancelled else { return }
            review = next
            if next?.canApply != true, next?.hasSavedRoute != true, status == nil {
                status = "이 운동은 새 50m 공유를 적용할 수 없어요. 기존 공유 경로는 그대로 유지돼요."
            }
        } catch { if canAccess() { status = "경로 공유 조건을 확인하지 못했어요." } }
    }

    @MainActor private func apply() async {
        guard !busy, canAccess(), preview != nil, let ownerRoute, let review,
              let revision = review.approvedConsentRevision(affirmed: affirmed, sourceID: workout.id, ownerID: owner)
        else { return }
        busy = true
        affirmed = false
        do {
            let published = try await NativeRoute50Upload.upload(workout: workout, route: ownerRoute, ownerID: owner,
                postID: review.postID, expectedRevision: review.expectedRevision, consentRevision: revision,
                acceptedNotice: NativeRoute50Upload.notice, isCurrent: canAccess)
            guard canAccess(), !Task.isCancelled else { return }
            status = published ? "출발·도착 50m를 가린 경로를 공유했어요." : "경로를 공유하지 못했어요. 공유 상태를 다시 확인해 주세요."
        } catch { if canAccess() { status = "공유되지 않았어요. 공유 조건을 다시 확인해 주세요." } }
        await refresh(loadPreview: false)
    }

    @MainActor private func withdraw() async {
        guard !busy, canAccess(), let review else { return }
        busy = true
        affirmed = false
        do {
            let removed = try await NativeRoute50Upload.withdraw(review: review, isCurrent: canAccess)
            guard canAccess(), !Task.isCancelled else { return }
            status = removed ? "이 운동의 50m 경로 공유를 철회했어요." : "경로 상태가 바뀌었어요. 다시 확인해 주세요."
        } catch { if canAccess() { status = "경로 공유 철회를 확인하지 못했어요." } }
        await refresh(loadPreview: false)
    }
}
