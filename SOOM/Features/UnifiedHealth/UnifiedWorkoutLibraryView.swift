import SwiftUI

struct UnifiedWorkoutLibraryView: View {
    @StateObject private var viewModel: UnifiedWorkoutLibraryViewModel
    private let similarCandidateProvider: SimilarWorkoutCandidateProviding?

    init(
        viewModel: UnifiedWorkoutLibraryViewModel,
        similarCandidateProvider: SimilarWorkoutCandidateProviding? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.similarCandidateProvider = similarCandidateProvider
    }

    var body: some View {
        SOOMScreen {
            header

            if viewModel.isLoading && viewModel.workouts.isEmpty {
                loadingCard
            } else if let errorMessage = viewModel.errorMessage {
                errorCard(errorMessage)
            } else if viewModel.workouts.isEmpty {
                emptyCard
            } else {
                librarySummaryCard
                duplicateReviewEntryCard
                analysisExclusionInfoCard
                workoutList
            }
        }
        .navigationTitle("가져온 운동 기록")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadRecentWorkouts()
        }
        .refreshable {
            await viewModel.loadRecentWorkouts()
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
        SOOMCard {
            HStack(spacing: SOOMLayout.SectionHeader.spacing) {
                ProgressView()
                    .tint(SOOMColor.recovery)
                    .accessibilityHidden(true)

                Text("저장된 운동 기록을 불러오는 중이에요.")
                    .font(SOOMFont.body(15, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("저장된 운동 기록 불러오는 중")
    }

    private var emptyCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "아직 가져온 운동 기록이 없어요",
                caption: "HealthKit 운동 가져오기를 실행하면 여기에 표시돼요."
            )

            Label("가져온 기록은 아직 회복 점수나 성장 분석에 자동 반영되지 않습니다.", systemImage: SOOMIcon.checkCircle)
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func errorCard(_ message: String) -> some View {
        SOOMCard {
            SOOMActionRow(
                icon: SOOMIcon.health,
                title: "운동 기록을 불러오지 못했어요",
                subtitle: message,
                tint: SOOMColor.warning
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var librarySummaryCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "최근 30일",
                caption: "저장된 UnifiedWorkout을 검토하는 관리 영역입니다."
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
                caption: "Recovery와 Growth 계산 연결 전 저장 상태를 확인합니다."
            )

            ForEach(viewModel.workouts) { workout in
                UnifiedWorkoutLibraryRow(
                    workout: workout,
                    isUpdating: viewModel.updatingWorkoutIDs.contains(workout.id),
                    similarCandidateProvider: similarCandidateProvider,
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
    let similarCandidateProvider: SimilarWorkoutCandidateProviding?
    let onToggleExcluded: () -> Void

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                NavigationLink {
                    UnifiedWorkoutDetailDestination(
                        unifiedWorkout: workout,
                        similarCandidateProvider: similarCandidateProvider
                    )
                } label: {
                    rowSummary
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(workout.workoutType.displayName) 상세 보기")
                .accessibilityHint("가져온 운동 기록의 상세 화면으로 이동합니다.")

                Button(action: onToggleExcluded) {
                    HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                        if isUpdating {
                            ProgressView()
                                .tint(SOOMColor.secondaryInk)
                                .accessibilityHidden(true)
                        }

                        Text(workout.isExcludedFromAnalysis ? "분석 포함" : "분석 제외")
                            .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Metrics.pillPadding)
                    .foregroundStyle(workout.isExcludedFromAnalysis ? SOOMColor.ink : SOOMColor.secondaryInk)
                    .background(SOOMColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .accessibilityLabel(workout.isExcludedFromAnalysis ? "분석 포함" : "분석 제외")
                .accessibilityHint(workout.isExcludedFromAnalysis ? "이 운동을 Recovery와 성장 분석 후보에 다시 포함합니다." : "이 운동 기록은 유지하고 Recovery와 성장 분석 입력에서 제외합니다.")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var rowSummary: some View {
        HStack(alignment: .top, spacing: SOOMLayout.Card.contentSpacing) {
            Image(systemName: workout.workoutType.iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(workout.workoutType.tint)
                .frame(width: 44, height: 44)
                .background(workout.workoutType.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(workout.workoutType.displayName)
                        .font(SOOMFont.body(18, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)

                    Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

                    Text(workout.source.displayName)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .padding(.horizontal, SOOMLayout.Metrics.actionTextSpacing + 2)
                        .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing)
                        .background(SOOMColor.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }

                Text("\(dateText) · \(timeText)")
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)

                HStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                    LibraryMetricPill(title: "거리", value: distanceText)
                    LibraryMetricPill(title: "시간", value: durationText)
                }

                HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    statusPill(title: workout.dataQuality.displayName, tint: SOOMColor.recovery)

                    if workout.isExcludedFromAnalysis {
                        statusPill(title: "분석 제외", tint: SOOMColor.warning)
                    } else {
                        statusPill(title: "분석 후보", tint: SOOMColor.secondaryInk)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SOOMColor.secondaryInk.opacity(0.7))
                .accessibilityHidden(true)
        }
    }

    private var dateText: String {
        Self.dateFormatter.string(from: workout.startDate)
    }

    private var timeText: String {
        Self.timeFormatter.string(from: workout.startDate)
    }

    private var distanceText: String {
        guard let distanceMeters = workout.distanceMeters else {
            return "-"
        }

        let distanceKm = distanceMeters / 1_000
        return String(format: "%.1f km", distanceKm)
    }

    private var durationText: String {
        let totalMinutes = max(Int((workout.durationSeconds / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }

        return "\(minutes)분"
    }

    private func statusPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(tint)
            .padding(.horizontal, SOOMLayout.Metrics.actionTextSpacing + 3)
            .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()
}

private struct UnifiedWorkoutDetailDestination: View {
    let unifiedWorkout: UnifiedWorkout
    var contextProvider: WorkoutDetailZoneContextProviding = WorkoutDetailZoneContextProvider()
    var similarCandidateProvider: SimilarWorkoutCandidateProviding?

    @State private var zoneContext = WorkoutDetailZoneContext.fallback
    @State private var comparisonInsight: WorkoutComparisonInsight?
    @State private var courseRecord: CourseRecord?
    @State private var courseProgression: CourseProgressionTimeline?

    var body: some View {
        WorkoutDetailView(
            workout: Workout(unifiedWorkout: unifiedWorkout),
            healthKitWorkout: zoneContext.healthKitWorkout,
            zoneDataProvider: zoneContext.zoneDataProvider,
            splitDataProvider: zoneContext.splitDataProvider,
            comparisonInsightOverride: comparisonInsight,
            courseRecordOverride: courseRecord,
            courseProgressionOverride: courseProgression
        )
        .task(id: unifiedWorkout.id) {
            zoneContext = await contextProvider.context(for: unifiedWorkout)
            let candidateResult = await loadSimilarCandidateResult()
            comparisonInsight = buildComparisonInsight(from: candidateResult)
            courseRecord = buildCourseRecord(from: candidateResult)
            courseProgression = buildCourseProgression(from: candidateResult)
        }
    }

    private func loadSimilarCandidateResult() async -> SimilarWorkoutCandidateResult? {
        guard let similarCandidateProvider else {
            return nil
        }

        do {
            return try await similarCandidateProvider.bestCandidate(
                for: unifiedWorkout,
                currentRoute: nil,
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
}

private extension Workout {
    init(unifiedWorkout workout: UnifiedWorkout) {
        let sport = WorkoutSport(unifiedWorkoutType: workout.workoutType)
        let distanceMeters = workout.distanceMeters ?? 0
        let averageHeartRate = Int((workout.averageHeartRate ?? 0).rounded())
        let maxHeartRate = Int((workout.maxHeartRate ?? workout.averageHeartRate ?? 0).rounded())

        self.init(
            id: workout.id,
            sport: sport,
            title: "\(workout.source.displayName) \(sport.title)",
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
            aiSummary: "가져온 운동 기록을 기준으로 상세 흐름을 확인합니다. HealthKit stream이 있으면 존과 운동 흐름 분석에 우선 반영돼요."
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
        case .running, .other:
            return SOOMIcon.run
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
            ),
            similarCandidateProvider: SimilarWorkoutCandidateProvider(
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
    func deleteWorkout(id: UUID) async throws {}

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
