import SwiftUI
import SwiftData
import HealthKit

struct UnifiedWorkoutLibraryView: View {
    var dataRevision: Int = 0
    @StateObject private var viewModel: UnifiedWorkoutLibraryViewModel
    @State private var selectedWorkout: UnifiedWorkout?

    init(viewModel: UnifiedWorkoutLibraryViewModel, dataRevision: Int = 0) {
        self.dataRevision = dataRevision
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header

            if viewModel.isLoading && viewModel.workouts.isEmpty {
                loadingCard
            } else if viewModel.workouts.isEmpty && viewModel.errorMessage == nil {
                emptyCard
            } else {
                if let errorMessage = viewModel.errorMessage { errorCard(errorMessage) }
                if !viewModel.workouts.isEmpty {
                librarySummaryCard
                duplicateReviewEntryCard
                analysisExclusionInfoCard
                workoutList
                }
            }
        }
        .workoutCardDestination(selection: $selectedWorkout)
        .navigationTitle("가져온 운동 기록")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded(revision: dataRevision)
        }
        .onChange(of: dataRevision) { _, revision in
            Task { await viewModel.loadIfNeeded(revision: revision) }
        }
        .refreshable {
            await viewModel.loadRecentWorkouts()
        }
        .onReceive(NotificationCenter.default.publisher(for: WorkoutRecordManagement.didChange)) { _ in
            Task { await viewModel.loadRecentWorkouts(requiresFollowUp: true) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("가져온 운동 기록")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("SOOM 공통 운동 데이터로 저장된 기록을 확인합니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Spacing.md) {
            Text("저장된 운동 기록 불러오는 중").font(SOOMFont.body(16, relativeTo: .body))
            SOOMSkeleton(layout: .workout, label: "저장된 운동 기록 불러오는 중")
        }.accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.state.loading")
    }

    private var emptyCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "아직 가져온 운동 기록이 없어요",
                caption: "HealthKit 운동 가져오기를 실행하면 여기에 표시돼요."
            )

            Label("분석에 포함한 운동은 활동·회복·성장 흐름을 살펴보는 데 사용해요.", soomIcon: SOOMIcon.checkCircle)
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func errorCard(_ message: String) -> some View {
        SOOMCard {
            SOOMActionFeedback(title: "운동 기록을 불러오지 못했어요", message: message, isError: true)
            Button("다시 불러오기") { Task { await viewModel.loadRecentWorkouts() } }
                .frame(minHeight: 44).disabled(viewModel.isLoading)
                .accessibilityIdentifier("library.state.retry")
        }.accessibilityIdentifier("library.state.error")
    }

    private var librarySummaryCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "최근 30일",
                caption: "가져온 운동과 분석에 포함할 기록을 관리해요."
            )

            HStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                LibraryMetricPill(title: "운동", value: "\(viewModel.workouts.count)")
                LibraryMetricPill(title: "제외", value: "\(excludedCount)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("최근 30일 가져온 운동 기록")
        .accessibilityValue("운동 \(viewModel.workouts.count)개, 분석 제외 \(excludedCount)개")
    }

    private var duplicateReviewEntryCard: some View {
        NavigationLink {
            UnifiedWorkoutDuplicateReviewViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.sync,
                    title: "중복 후보 확인",
                    subtitle: "가져온 운동 중 같은 기록으로 보이는 후보를 검토합니다.",
                    tint: SOOMColor.secondaryInk
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("중복 후보 확인")
        .accessibilityHint("가져온 운동 기록 중 중복으로 보이는 후보 목록으로 이동합니다.")
    }

    private var analysisExclusionInfoCard: some View {
        SOOMCard {
            SOOMActionRow(
                icon: SOOMIcon.checkCircle,
                title: "분석 제외는 삭제가 아니에요",
                subtitle: "제외된 운동은 Recovery와 성장 분석에 사용하지 않지만, 기록 자체는 그대로 보관됩니다.",
                tint: SOOMColor.secondaryInk
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("분석 제외 안내")
        .accessibilityValue("제외된 운동은 회복과 성장 분석에 사용하지 않지만 기록은 유지됩니다.")
    }

    private var workoutList: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
            SOOMSectionHeader(
                "운동 목록",
                caption: "카드를 누르면 지도와 자세한 운동 기록을 볼 수 있어요."
            )

            ForEach(viewModel.workouts) { workout in
                UnifiedWorkoutLibraryRow(
                    workout: workout,
                    isUpdating: viewModel.updatingWorkoutIDs.contains(workout.id),
                    onOpen: { selectedWorkout = $0 },
                    onToggleExcluded: {
                        Task {
                            await viewModel.toggleExcluded(id: workout.id)
                        }
                    }
                )
            }
        }
    }

    private var excludedCount: Int {
        viewModel.workouts.filter(\.isExcludedFromAnalysis).count
    }
}

private struct UnifiedWorkoutLibraryRow: View {
    let workout: UnifiedWorkout
    let isUpdating: Bool
    let onOpen: (UnifiedWorkout) -> Void
    let onToggleExcluded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ActivityWorkoutRow(workout: workout, onOpen: onOpen)
            HStack {
                Text(workout.dataQuality.displayName).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                Spacer()
                Button(action: onToggleExcluded) {
                    HStack(spacing: 6) {
                        if isUpdating { ProgressView() }
                        Text(workout.isExcludedFromAnalysis ? "분석 포함" : "분석 제외")
                    }.font(.subheadline).frame(minHeight: 44)
                }.disabled(isUpdating)
                .accessibilityHint("기록은 보관하고 회복·성장 분석에 사용할지 변경합니다.")
            }
        }.accessibilityElement(children: .contain)
    }
}

struct UnifiedWorkoutDetailDestination: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var accountStorage: HealthAccountStorageController
    @State private var routeRequestGate = ShareRouteRequestGate()
    let unifiedWorkout: UnifiedWorkout
    var contextProvider: WorkoutDetailZoneContextProviding = WorkoutDetailZoneContextProvider()
    var similarCandidateProvider: SimilarWorkoutCandidateProviding?
    var comparisonHistoryProvider: WorkoutComparisonHistoryProviding?
    var detailRouteContextProvider: WorkoutDetailRouteContextProviding?
    var relativeEffortHistoryProvider: RelativeEffortHistoryProviding?
    var achievementHistoryProvider: WorkoutAchievementHistoryProviding?
    var fitnessTrendHistoryProvider: FitnessTrendHistoryProviding?
    var gpxRouteAttachmentService: GPXRouteAttachmentService?
    var fitRouteAttachmentService: FITRouteAttachmentService?
    var tcxRouteAttachmentService: TCXRouteAttachmentService?
    var companionUpdateService: WorkoutCompanionUpdateService? = nil

    @State private var zoneContext = WorkoutDetailZoneContext.fallback
    @State private var persistedRoute: WorkoutRoute?
    @State private var comparisonWorkouts: [Workout] = []
    @State private var comparisonInsight: WorkoutComparisonInsight?
    @State private var courseRecord: CourseRecord?
    @State private var courseProgression: CourseProgressionTimeline?
    @State private var climbInsight: ClimbInsight?
    @State private var chartSamples: [WorkoutSample]?
    @State private var chartSplits: [WorkoutSplit]?
    @State private var heartRateChartSamples: [WorkoutDistanceChartSample]?
    @State private var relativeEffortComparison: RelativeEffortComparison?
    @State private var achievements: [WorkoutAchievement] = []
    @State private var achievementCount = 0
    @State private var fitnessTrend: FitnessTrend?
    @State private var telemetry: WorkoutTelemetry?
    @State private var hydratedWorkout: HKWorkout?
    @State private var detailReadMessage: String?
    @State private var isReadingDetails = false
    @State private var detailReadID = UUID()
    @State private var detailReadIdentity: String?

    var body: some View {
        WorkoutManagementHost(workout: unifiedWorkout) { stored, management in
        let current = hydratedWorkout.map { stored.withHealthKitDetails($0, telemetry: telemetry, updatedAt: stored.updatedAt) } ?? stored
        WorkoutDeepDetailView(
            workout: Workout(unifiedWorkout: current),
            comparisonWorkouts: comparisonWorkouts,
            healthKitWorkout: zoneContext.healthKitWorkout,
            zoneDataProvider: zoneContext.zoneDataProvider,
            splitDataProvider: zoneContext.splitDataProvider,
            comparisonInsightOverride: comparisonInsight,
            courseRecordOverride: courseRecord,
            courseProgressionOverride: courseProgression,
            climbInsightOverride: climbInsight,
            detailRouteOverride: persistedRoute,
            samplesOverride: chartSamples,
            splitsOverride: chartSplits,
            heartRateChartSamplesOverride: heartRateChartSamples,
            telemetryOverride: telemetry,
            healthKitReadPresentation: canRetryOwnHealthDetails
                ? HealthKitDetailReadPresentation(message: detailReadMessage ?? "", isLoading: isReadingDetails,
                    retry: { await readMissingDetails(force: true) })
                : nil,
            relativeEffortComparisonOverride: relativeEffortComparison,
            achievementsOverride: achievements,
            achievementCountOverride: achievementCount,
            fitnessTrendOverride: fitnessTrend,
            sourceUnifiedWorkout: current,
            routeAttachmentAction: routeAttachmentAction,
            companionUpdateAction: companionUpdateAction
        )
        }
        .task(id: "\(unifiedWorkout.id)-\(unifiedWorkout.updatedAt.timeIntervalSince1970)-\(accountStorage.scopeID)") {
            let scope = accountStorage.scopeID
            let token = routeRequestGate.begin(workoutID: unifiedWorkout.id, scopeID: scope)
            let container = modelContext.container
            let identity = scope + unifiedWorkout.id.uuidString
            if detailReadIdentity != identity {
                persistedRoute = nil
                telemetry = nil
                hydratedWorkout = nil
                detailReadIdentity = identity
            }
            detailReadMessage = nil
            do {
                if let stored = try WorkoutTelemetryStore(modelContext: modelContext).resolved(for: unifiedWorkout) {
                    telemetry = telemetry.map { stored.merging($0) } ?? stored
                }
            } catch { detailReadMessage = "저장된 측정값을 읽지 못했어요. 건강 앱에서 다시 확인합니다." }
            // A revision refresh keeps visible data and scroll state; it does not
            // write newly read private measurements to cloud/shared records.
            detailReadID = UUID()
            isReadingDetails = false
            zoneContext = .fallback
            let loadedRoute = await loadPersistedRoute()
            guard routeRequestGate.accepts(token, workoutID: unifiedWorkout.id,
                    scopeID: accountStorage.scopeID, isCancelled: Task.isCancelled),
                  modelContext.container === container else { return }
            if let loadedRoute { persistedRoute = loadedRoute }
            await readMissingDetails()
            guard routeRequestGate.accepts(token, workoutID: unifiedWorkout.id,
                scopeID: accountStorage.scopeID, isCancelled: Task.isCancelled) else { return }
            let candidateResult = await loadSimilarCandidateResult()
            comparisonInsight = buildComparisonInsight(from: candidateResult)
            courseRecord = buildCourseRecord(from: candidateResult)
            courseProgression = buildCourseProgression(from: candidateResult)
            comparisonWorkouts = await comparisonHistoryProvider?.comparisonWorkouts(excluding: unifiedWorkout.id) ?? []
            climbInsight = buildClimbInsight()
            await loadChartData()
            await loadRelativeEffortComparison()
            await loadAchievements()
            await loadFitnessTrend()
        }
    }

    private var canRetryOwnHealthDetails: Bool {
        !ReviewDemoMode.isActive && unifiedWorkout.source == .appleHealthKit
            && unifiedWorkout.externalId.flatMap(UUID.init(uuidString:)) != nil
            && modelContext.container === accountStorage.container
            && !HealthCloudJournal.isRetired(modelContext)
    }

    @MainActor
    private func readMissingDetails(force: Bool = false) async {
        guard canRetryOwnHealthDetails,
              let external = unifiedWorkout.externalId, UUID(uuidString: external) != nil,
              !isReadingDetails else { return }
        let needsRoute = persistedRoute == nil && unifiedWorkout.routeMissingReason != .indoorNoLocationData && [.running, .cycling, .walking, .hiking].contains(unifiedWorkout.workoutType)
        let canReadRecordedZones: Bool
        if #available(iOS 27.0, *) { canReadRecordedZones = true } else { canReadRecordedZones = false }
        let needsBase = HealthKitDetailReadCache.needsMeasurements(unifiedWorkout, telemetry: telemetry)
        let enrich = HealthKitDetailReadCache.shouldEnrichOwnerDetail(unifiedWorkout, telemetry: telemetry,
                                                                    canReadRecordedZones: canReadRecordedZones)
        guard force || needsRoute || needsBase || enrich else { return }
        let optionalOnly = enrich && !force && !needsRoute && !needsBase
        let scope = accountStorage.scopeID
        let container = modelContext.container
        let readID = UUID()
        detailReadID = readID
        isReadingDetails = true
        if !optionalOnly { detailReadMessage = "건강 앱의 측정값을 확인하고 있어요. 기존 기록은 유지됩니다." }
        defer { if detailReadID == readID { isReadingDetails = false } }
        do {
            let key = HealthKitDetailReadCache.Key(scope: scope, workoutID: unifiedWorkout.id,
                externalID: external, revision: unifiedWorkout.updatedAt, needsRoute: needsRoute,
                expandsOwnerHeartRateSeries: force)
            let original = unifiedWorkout
            let result = try await HealthKitDetailReadCache.shared.read(key: key, force: force) {
                try await HealthKitDetailReadCache.fetch(workout: original, needsRoute: needsRoute,
                    expandOwnerHeartRateSeries: force)
            }
            guard !Task.isCancelled, scope == accountStorage.scopeID,
                  container === modelContext.container, detailReadID == readID else { return }
            if !optionalOnly { hydratedWorkout = result.workout }
            if let incoming = result.telemetry {
                telemetry = (telemetry.map { optionalOnly
                    ? HealthKitDetailReadCache.mergingOwnerEnrichment(incoming, into: $0)
                    : $0.merging(incoming) } ?? incoming).validated(for: unifiedWorkout)
            }
            if persistedRoute == nil { persistedRoute = result.route }
            if optionalOnly { return }
            if result.workout == nil {
                detailReadMessage = "이 기기에서 연결된 건강 운동을 읽지 못했어요. 데이터 존재 여부와 읽기 허용 여부는 이 결과만으로 구분할 수 없어요."
            } else if !result.failedChannels.isEmpty {
                detailReadMessage = "일부 측정값을 읽지 못했어요. 이미 표시된 기록은 유지됩니다."
            } else if HealthKitDetailReadCache.needsMeasurements(result.workout.map { unifiedWorkout.withHealthKitDetails($0, telemetry: telemetry, updatedAt: unifiedWorkout.updatedAt) } ?? unifiedWorkout, telemetry: telemetry) || (needsRoute && persistedRoute == nil) {
                detailReadMessage = "읽을 수 있는 측정값만 표시했어요. 빈 항목은 건강 앱의 SOOM 읽기 허용과 기록 연결을 확인해 주세요. 경로와 심박·구간은 각각 별도로 제공될 수 있어요."
            } else { detailReadMessage = nil }
        } catch is CancellationError {
            if detailReadID == readID { detailReadMessage = nil }
        } catch {
            guard !optionalOnly, scope == accountStorage.scopeID, detailReadID == readID else { return }
            detailReadMessage = "측정값 확인을 완료하지 못했어요. 기존 기록을 유지했어요."
        }
    }

    private func loadFitnessTrend() async {
        guard let fitnessTrendHistoryProvider else { return }

        let dailyLoads = await fitnessTrendHistoryProvider.dailyTrainingLoads(
            upTo: unifiedWorkout.startDate,
            windowDays: FitnessTrendCalculator.recommendedHistoryWindowDays
        )
        fitnessTrend = FitnessTrendBuilder.build(dailyLoadsAscending: dailyLoads)
    }

    private func loadAchievements() async {
        guard let achievementHistoryProvider, let persistedRoute else { return }

        let todayEfforts = WorkoutSegmentBestEffortFinder.bestEfforts(from: persistedRoute)
        guard !todayEfforts.isEmpty else { return }

        let historicalEffortsByDuration = await achievementHistoryProvider.recentBestEfforts(
            excluding: unifiedWorkout.id,
            workoutType: unifiedWorkout.workoutType,
            before: unifiedWorkout.startDate,
            lookbackMonths: WorkoutAchievementConfig.lookbackMonths
        )

        let result = WorkoutAchievementBuilder.build(
            todayEfforts: todayEfforts,
            historicalEffortsByDuration: historicalEffortsByDuration,
            workoutType: unifiedWorkout.workoutType
        )
        achievements = result.markers
        achievementCount = result.totalCount
    }

    private func loadRelativeEffortComparison() async {
        guard let relativeEffortHistoryProvider else { return }

        let todayEffort = UnifiedWorkoutToRecoveryActivityMapper().map(unifiedWorkout).relativeEffort
        let recentEfforts = await relativeEffortHistoryProvider.recentRelativeEfforts(
            excluding: unifiedWorkout.id,
            before: unifiedWorkout.startDate,
            lookbackDays: 21
        )
        relativeEffortComparison = RelativeEffortComparisonBuilder.build(
            todayEffort: todayEffort,
            recentEfforts: recentEfforts
        )
    }

    private func loadChartData() async {
        guard let persistedRoute else { return }

        var heartRateSamples: [HealthKitWorkoutMetricSample] = []
        if let healthKitWorkout = zoneContext.healthKitWorkout {
            let fetched = try? await HealthKitWorkoutMetricStreamFetcher().fetchZoneMetricSamples(for: healthKitWorkout)
            heartRateSamples = fetched?[.heartRate] ?? []
        }

        chartSamples = WorkoutChartDataBuilder.samples(from: persistedRoute, heartRateSamples: heartRateSamples)
        chartSplits = WorkoutChartDataBuilder.splits(from: persistedRoute, heartRateSamples: heartRateSamples)
        heartRateChartSamples = WorkoutChartDataBuilder.heartRateSamples(from: persistedRoute, heartRateSamples: heartRateSamples)
    }

    private var routeAttachmentAction: ActivityDetailGPXRouteImportAction? {
        guard
            gpxRouteAttachmentService != nil || fitRouteAttachmentService != nil || tcxRouteAttachmentService != nil,
            ActivityDetailGPXRouteImportEligibility.canAttachGPXRoute(
                to: unifiedWorkout,
                hasRoute: persistedRoute != nil
            )
        else {
            return nil
        }

        return ActivityDetailGPXRouteImportAction { url in
            await attachRoute(from: url)
        }
    }

    private var companionUpdateAction: WorkoutCompanionUpdateAction? {
        guard let companionUpdateService else { return nil }

        let scope = accountStorage.scopeID
        return WorkoutCompanionUpdateAction { names in
            guard accountStorage.scopeID == scope, !Task.isCancelled else { return .failure(.persistenceFailed) }
            #if DEBUG && targetEnvironment(simulator)
            if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_COMPANION_FORM_QA"] == "1" {
                try? await Task.sleep(for: .milliseconds(500))
                if CompanionSyntheticFailure.takeFirst(unifiedWorkout.id) { return .failure(.persistenceFailed) }
            }
            #endif
            guard accountStorage.scopeID == scope, !Task.isCancelled else { return .failure(.persistenceFailed) }
            return await companionUpdateService.updateCompanions(workoutId: unifiedWorkout.id, names: names)
        }
    }

    @MainActor
    private func attachRoute(from url: URL) async -> ActivityDetailGPXRouteImportResult {
        guard let format = ActivityDetailGPXRouteFileImport.routeFileFormat(for: url) else {
            return .failure(.unsupportedFileType)
        }

        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            return .failure(.unreadableFile)
        }

        switch format {
        case .gpx:
            guard let gpxRouteAttachmentService else {
                return .failure(.unsupportedFileType)
            }
            return await attachGPXRoute(data, using: gpxRouteAttachmentService)
        case .fit:
            guard let fitRouteAttachmentService else {
                return .failure(.unsupportedFileType)
            }
            return await attachFITRoute(data, using: fitRouteAttachmentService)
        case .tcx:
            guard let tcxRouteAttachmentService else {
                return .failure(.unsupportedFileType)
            }
            return await attachTCXRoute(data, using: tcxRouteAttachmentService)
        }
    }

    @MainActor
    private func attachGPXRoute(
        _ data: Data,
        using service: GPXRouteAttachmentService
    ) async -> ActivityDetailGPXRouteImportResult {
        let result = await service.attachRoute(to: unifiedWorkout.id, gpxData: data)
        switch result {
        case .success(let attachment):
            persistedRoute = attachment.route
            await reloadRouteDerivedState()
            return .success
        case .failure(let error):
            return .failure(ActivityDetailGPXRouteImportError(attachmentError: error))
        }
    }

    @MainActor
    private func attachFITRoute(
        _ data: Data,
        using service: FITRouteAttachmentService
    ) async -> ActivityDetailGPXRouteImportResult {
        let result = await service.attachRoute(to: unifiedWorkout.id, fitData: data)
        switch result {
        case .success(let attachment):
            persistedRoute = attachment.route
            await reloadRouteDerivedState()
            return .success
        case .failure(let error):
            return .failure(ActivityDetailGPXRouteImportError(attachmentError: error))
        }
    }

    @MainActor
    private func attachTCXRoute(
        _ data: Data,
        using service: TCXRouteAttachmentService
    ) async -> ActivityDetailGPXRouteImportResult {
        let result = await service.attachRoute(to: unifiedWorkout.id, tcxData: data)
        switch result {
        case .success(let attachment):
            persistedRoute = attachment.route
            await reloadRouteDerivedState()
            return .success
        case .failure(let error):
            return .failure(ActivityDetailGPXRouteImportError(attachmentError: error))
        }
    }

    @MainActor
    private func reloadRouteDerivedState() async {
        let scope = accountStorage.scopeID, container = modelContext.container
        let token = routeRequestGate.begin(workoutID: unifiedWorkout.id, scopeID: scope)
        persistedRoute = nil
        let route = await loadPersistedRoute()
        guard routeRequestGate.accepts(token, workoutID: unifiedWorkout.id,
                scopeID: accountStorage.scopeID, isCancelled: Task.isCancelled),
              modelContext.container === container else { return }
        persistedRoute = route
        let candidateResult = await loadSimilarCandidateResult()
        comparisonInsight = buildComparisonInsight(from: candidateResult)
        courseRecord = buildCourseRecord(from: candidateResult)
        courseProgression = buildCourseProgression(from: candidateResult)
        climbInsight = buildClimbInsight()
    }

    private func loadPersistedRoute() async -> WorkoutRoute? {
        do {
            if let route = try await WorkoutTelemetryStore(modelContext: modelContext).resolvedRoute(for: unifiedWorkout) {
                return route.workoutId == unifiedWorkout.id ? route : nil
            }
        } catch { return nil }
        guard let route = await detailRouteContextProvider?.route(for: unifiedWorkout) else { return nil }
        // Legacy HealthKit routes can be keyed by the verified external UUID.
        let external = unifiedWorkout.source == .appleHealthKit ? unifiedWorkout.externalId.flatMap(UUID.init(uuidString:)) : nil
        guard route.workoutId == unifiedWorkout.id || route.workoutId == external else { return nil }
        return WorkoutRoute(id: route.id, workoutId: unifiedWorkout.id, source: route.source,
            coordinates: route.coordinates, totalDistanceMeters: route.totalDistanceMeters,
            totalElevationGain: route.totalElevationGain, createdAt: route.createdAt)
    }

    private func loadSimilarCandidateResult() async -> SimilarWorkoutCandidateResult? {
        guard let similarCandidateProvider else {
            return nil
        }

        do {
            return try await similarCandidateProvider.bestCandidate(
                for: unifiedWorkout,
                currentRoute: persistedRoute,
                candidateRoutesByWorkoutId: [:]
            )
        } catch {
            return nil
        }
    }

    private func buildComparisonInsight(from result: SimilarWorkoutCandidateResult?) -> WorkoutComparisonInsight? {
        guard let result else {
            return similarCandidateProvider == nil ? nil : .insufficientData
        }

        return WorkoutComparisonInsightBuilder().build(
            current: UnifiedWorkoutToGrowthInputMapper().map(unifiedWorkout),
            baseline: result.baseline,
            routeCandidate: result.routeCandidate
        )
    }

    private func buildCourseRecord(from result: SimilarWorkoutCandidateResult?) -> CourseRecord? {
        guard let result else {
            return similarCandidateProvider == nil ? nil : .insufficientData
        }

        return CourseRecordBuilder().build(
            current: UnifiedWorkoutToGrowthInputMapper().map(unifiedWorkout),
            candidateWorkouts: result.candidateWorkouts.isEmpty ? [result.baseline] : result.candidateWorkouts,
            routeCandidates: result.routeCandidates.isEmpty ? result.routeCandidate.map { [$0] } ?? [] : result.routeCandidates,
            courseIdentity: result.currentCourseIdentity
        )
    }

    private func buildCourseProgression(from result: SimilarWorkoutCandidateResult?) -> CourseProgressionTimeline? {
        guard let result else {
            return similarCandidateProvider == nil ? nil : .insufficientData
        }

        return CourseProgressionBuilder().build(
            current: UnifiedWorkoutToGrowthInputMapper().map(unifiedWorkout),
            candidateWorkouts: result.candidateWorkouts.isEmpty ? [result.baseline] : result.candidateWorkouts,
            routeCandidates: result.routeCandidates.isEmpty ? result.routeCandidate.map { [$0] } ?? [] : result.routeCandidates,
            courseIdentity: result.currentCourseIdentity
        )
    }

    private func buildClimbInsight() -> ClimbInsight? {
        let insight = ClimbInsightBuilder().build(
            current: UnifiedWorkoutToGrowthInputMapper().map(unifiedWorkout),
            route: persistedRoute
        )
        return insight.isVisible ? insight : nil
    }
}

extension Workout {
    init(unifiedWorkout workout: UnifiedWorkout) {
        let sport = WorkoutSport(unifiedWorkoutType: workout.workoutType)
        let distanceMeters = workout.distanceMeters ?? 0
        let averageHeartRate = Int((workout.averageHeartRate ?? 0).rounded())
        let maxHeartRate = Int((workout.maxHeartRate ?? 0).rounded())

        self.init(
            id: workout.id,
            sport: sport,
            title: workout.displayTitle,
            date: workout.startDate,
            distanceMeters: distanceMeters,
            duration: workout.durationSeconds,
            activeCalories: Int((workout.activeEnergyKcal ?? 0).rounded()),
            avgHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            avgPower: nil,
            elevationGain: Int((workout.elevationGainMeters ?? 0).rounded()),
            cadence: nil,
            effort: Self.estimatedEffort(durationSeconds: workout.durationSeconds, averageHeartRate: workout.averageHeartRate),
            source: workout.source.displayName,
            route: [],
            splits: [],
            samples: [],
            zones: [],
            achievements: [],
            aiSummary: "가져온 운동 기록과 실제 측정값을 기준으로 운동 흐름을 확인합니다. 연동 서비스가 제공하는 데이터에 따라 분석 항목이 달라져요.",
            originalWorkoutType: workout.workoutType
        )
    }

    private static func estimatedEffort(durationSeconds: TimeInterval, averageHeartRate: Double?) -> Int {
        let durationScore = min(max(Int(durationSeconds / 1_800), 1), 4)
        let heartRateScore: Int

        switch averageHeartRate ?? 0 {
        case 160...:
            heartRateScore = 4
        case 140..<160:
            heartRateScore = 3
        case 120..<140:
            heartRateScore = 2
        default:
            heartRateScore = 1
        }

        return min(max(durationScore + heartRateScore, 1), 10)
    }
}

private extension WorkoutSport {
    init(unifiedWorkoutType type: UnifiedWorkoutType) {
        switch type {
        case .cycling:
            self = .bike
        case .swimming:
            self = .swim
        case .running, .walking, .hiking, .strength, .yoga, .other:
            self = .run
        }
    }
}

private struct LibraryMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Text(title)
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)

            Text(value)
                .font(SOOMFont.body(16, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private extension UnifiedWorkoutType {
    var displayName: String {
        switch self {
        case .running:
            return "러닝"
        case .cycling:
            return "사이클"
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
            return "기타 운동"
        }
    }

    var iconName: String {
        switch self {
        case .cycling:
            return SOOMIcon.bike
        case .swimming:
            return SOOMIcon.swim
        case .walking, .hiking:
            return "figure.walk"
        case .strength:
            return "dumbbell"
        case .yoga:
            return "figure.mind.and.body"
        case .running:
            return SOOMIcon.run
        case .other:
            return SOOMIcon.activity
        }
    }

    var tint: Color {
        switch self {
        case .cycling:
            return SOOMColor.bike
        case .swimming:
            return SOOMColor.swim
        case .running:
            return SOOMColor.run
        default:
            return SOOMColor.recovery
        }
    }
}

private extension UnifiedDataSource {
    var displayName: String {
        switch self {
        case .appleHealthKit:
            return "Apple Health"
        case .garmin:
            return "Garmin"
        case .googleHealth:
            return "Google Health"
        case .strava:
            return "Strava"
        case .samsungHealth:
            return "Samsung Health"
        case .healthConnect:
            return "Health Connect"
        case .soomLocal:
            return "SOOM"
        case .manual:
            return "직접 입력"
        case .unknown:
            return "알 수 없음"
        }
    }
}

private extension UnifiedDataQuality {
    var displayName: String {
        switch self {
        case .complete:
            return "완전"
        case .partial:
            return "일부"
        case .estimated:
            return "추정"
        case .missing:
            return "부족"
        case .unknown:
            return "확인 필요"
        }
    }
}

#Preview("UnifiedWorkoutLibraryView") {
    NavigationStack {
        UnifiedWorkoutLibraryView(
            viewModel: UnifiedWorkoutLibraryViewModel(
                store: PreviewUnifiedWorkoutLibraryStore()
            )
        )
    }
    .preferredColorScheme(.light)
}

private final class PreviewUnifiedWorkoutLibraryStore: UnifiedWorkoutStore {
    func saveWorkout(_ workout: UnifiedWorkout) async throws {}
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {}

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        [
            makeWorkout(type: .running, source: .appleHealthKit, daysAgo: 0, distanceMeters: 10_400),
            makeWorkout(type: .cycling, source: .garmin, daysAgo: 2, distanceMeters: 41_700),
            makeWorkout(type: .swimming, source: .manual, daysAgo: 5, distanceMeters: nil, isExcluded: true)
        ]
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}
    func deleteWorkout(id: UUID) async throws {}
    func deleteAllWorkouts() async throws {}

    private func makeWorkout(
        type: UnifiedWorkoutType,
        source: UnifiedDataSource,
        daysAgo: Int,
        distanceMeters: Double?,
        isExcluded: Bool = false
    ) -> UnifiedWorkout {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: .minute, value: 52, to: startDate) ?? startDate

        return UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: 52 * 60,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 620,
            averageHeartRate: 148,
            maxHeartRate: 171,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 78,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcluded,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor
private enum CompanionSyntheticFailure {
    private static var failed = Set<UUID>()
    static func takeFirst(_ id: UUID) -> Bool { failed.insert(id).inserted }
}
#endif
