import SwiftUI

struct UnifiedWorkoutDuplicateReviewView: View {
    @Environment(\.soomBottomOverlayInset) private var bottomOverlayInset
    @StateObject private var viewModel: UnifiedWorkoutDuplicateReviewViewModel
    @State private var pendingMerge: UnifiedWorkoutDuplicateCandidate?
    @State private var pendingPrimaryID: UUID?
    @State private var isMergeConfirmationPresented = false

    init(viewModel: UnifiedWorkoutDuplicateReviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        GeometryReader { viewport in
        SOOMScreen {
            header

            if let error = viewModel.errorMessage, !viewModel.candidates.isEmpty { errorCard(error) }
            if viewModel.isLoading && viewModel.candidates.isEmpty {
                loadingCard
            } else if let errorMessage = viewModel.errorMessage, viewModel.candidates.isEmpty {
                errorCard(errorMessage)
            } else if viewModel.candidates.isEmpty {
                emptyCard
            } else {
                summaryCard
                candidateList
            }
        }
        .confirmationDialog("겹치는 기록을 합칠까요?", isPresented: $isMergeConfirmationPresented, titleVisibility: .visible) {
            Button("원본 보관하고 합치기") {
                guard let candidate = pendingMerge, let id = pendingPrimaryID else { return }
                pendingMerge = nil; pendingPrimaryID = nil
                Task { await viewModel.resolve(candidate, primaryID: id) }
            }
            Button("취소", role: .cancel) { pendingMerge = nil; pendingPrimaryID = nil }
        } message: {
            Text(mergePreview)
        }

        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = viewModel.resolutionMessage {
                SOOMBoundedFeedback(maxHeight: max(80, viewport.size.height * 0.40)) {
                    SOOMActionFeedback(title: viewModel.resolutionTitle, message: (viewModel.resolutionSelection.map { $0 + "\n" } ?? "") + message)
                }
                    .padding(SOOMLayout.screenPadding)
                    .padding(.bottom, bottomOverlayInset)
                    .background(SOOMColor.background)
                    .accessibilityIdentifier("duplicates.resolution.feedback")
            }
        }
        .navigationTitle("중복 후보 검토")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDuplicateCandidates()
        }
        .refreshable {
            await viewModel.loadDuplicateCandidates()
        }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("중복 후보 검토")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("가져온 운동 기록 중 같은 운동으로 보이는 후보를 확인합니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var loadingCard: some View {
        SOOMSkeleton(layout: .workout, label: "중복 후보 확인 중")
    }

    private var emptyCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "중복으로 보이는 운동 기록이 없어요",
                caption: "가져온 기록이 늘어나면 여기에서 확인할 수 있어요."
            )

            Label("원본은 보관하고, 같은 운동은 대표 기록 하나로 표시할 수 있어요.", soomIcon: SOOMIcon.checkCircle)
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func errorCard(_ message: String) -> some View {
        SOOMCard {
            SOOMActionRow(
                icon: SOOMIcon.sync,
                title: viewModel.errorTitle,
                subtitle: message,
                tint: SOOMColor.warning
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var summaryCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "최근 90일 중복 후보",
                caption: "거리·시간의 기준이 될 기록을 선택하세요. 없는 경로와 측정값만 다른 기기에서 보완합니다."
            )

            HStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                DuplicateMetricPill(title: "후보", value: "\(viewModel.candidates.count)")
                DuplicateMetricPill(title: "최고 신뢰도", value: highestConfidenceText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("최근 90일 중복 후보")
        .accessibilityValue("후보 \(viewModel.candidates.count)개, 최고 신뢰도 \(highestConfidenceText)")
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
            SOOMSectionHeader(
                "후보 목록",
                caption: "대표 후보와 중복 후보를 함께 비교합니다."
            )

            ForEach(Array(viewModel.candidates.enumerated()), id: \.offset) { _, candidate in
                VStack(spacing: 8) {
                    UnifiedWorkoutDuplicateCandidateRow(candidate: candidate)
                    ForEach([candidate.primaryWorkout, candidate.duplicateWorkout]) { workout in
                        Button("\(workout.recordingSourceLabel) 기록을 대표로 사용") {
                            pendingPrimaryID = workout.id; pendingMerge = candidate; isMergeConfirmationPresented = true
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(SOOMColor.accentSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button("각각 다른 운동으로 유지") { Task { await viewModel.resolve(candidate, primaryID: nil) } }
                        .frame(minHeight: 44)
                }
                .disabled(viewModel.isResolving)
            }
        }
    }

    private var mergePreview: String {
        guard let candidate = pendingMerge, let selected = pendingPrimaryID else { return "" }
        let copies = [candidate.primaryWorkout, candidate.duplicateWorkout].map { original in
            var value = original; value.preferredWorkoutID = selected; return value
        }
        guard let group = UnifiedWorkoutDeduplicationEngine().canonicalGroups(copies).first else { return "" }
        let evidence = UnifiedWorkoutProvenance(group: group)
        return "거리·시간 기준: \(group.workout.recordingSourceLabel)\n\(FeedCardFormatting.distance(group.workout.distanceMeters)) · \(FeedCardFormatting.duration(group.workout.durationSeconds))\n평균 심박: \(group.workout.averageHeartRate.map { String(format: "%.0f bpm", $0) } ?? "미수집") · \(evidence.source(for: \.averageHeartRate)?.recordingSourceLabel ?? "출처 없음")\n선택 원본의 유효한 GPS·측정값을 우선하고 누락만 보완합니다. 충돌 값은 더하거나 평균내지 않습니다. \(ImportedWorkoutPublication.usesLegacyPublication ? "원본 ID와 측정값은 보관하며 보완용 피드는 비공개로 전환합니다." : "원본 ID와 측정값은 보관합니다. 운동 요약은 프로필 공개 설정을 따르며, 이미 별도 카드인 기록의 병합·분리는 확인이 필요할 수 있어요.")"
    }

    private var highestConfidenceText: String {
        guard let maxConfidence = viewModel.candidates.map(\.confidence).max() else {
            return "-"
        }
        return "\(Int((maxConfidence * 100).rounded()))%"
    }
}

private struct UnifiedWorkoutDuplicateCandidateRow: View {
    let candidate: UnifiedWorkoutDuplicateCandidate

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                        Text("중복 가능성")
                            .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)

                        Text(confidenceText)
                            .font(SOOMFont.body(24, weight: .bold, relativeTo: .title3))
                            .foregroundStyle(SOOMColor.ink)
                    }

                    Spacer()

                    Text(candidate.resolutionPolicy.displayName)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.recovery)
                        .padding(.horizontal, SOOMLayout.Metrics.actionTextSpacing + 3)
                        .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing)
                        .background(SOOMColor.recovery.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }

                VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                    workoutSummary(
                        title: "대표 후보",
                        workout: candidate.primaryWorkout,
                        tint: SOOMColor.recovery
                    )

                    workoutSummary(
                        title: "중복 후보",
                        workout: candidate.duplicateWorkout,
                        tint: SOOMColor.secondaryInk
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text("판단 근거")
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)

                    ForEach(candidate.reasons, id: \.self) { reason in
                        Label(reason.localizedDuplicateReason, soomIcon: SOOMIcon.checkCircle)
                            .font(SOOMFont.body(13, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }
                }

                HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    statusPill(title: "우선 source: \(candidate.preferredSource.displayName)", tint: SOOMColor.secondaryInk)
                    statusPill(title: candidate.resolutionPolicy.displayName, tint: SOOMColor.recovery)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("중복 운동 후보")
        .accessibilityValue("신뢰도 \(confidenceText), 대표 후보 \(candidate.primaryWorkout.workoutType.displayName), 중복 후보 \(candidate.duplicateWorkout.workoutType.displayName), 우선 source \(candidate.preferredSource.displayName)")
    }

    private var confidenceText: String {
        "\(Int((candidate.confidence * 100).rounded()))%"
    }

    private func workoutSummary(
        title: String,
        workout: UnifiedWorkout,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.compactListSpacing) {
            SOOMSportIconView(name: workout.workoutType.iconName, size: SOOMFont.Size.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text(title)
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.secondaryInk)

                Text("\(workout.workoutType.displayName) · \(workout.source.displayName)")
                    .font(SOOMFont.body(16, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)

                Text("\(dateText(for: workout)) · \(distanceText(for: workout)) · \(durationText(for: workout))")
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }

            Spacer(minLength: 0)
        }
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
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

    private func dateText(for workout: UnifiedWorkout) -> String {
        Self.dateFormatter.string(from: workout.startDate)
    }

    private func distanceText(for workout: UnifiedWorkout) -> String {
        guard let distanceMeters = workout.distanceMeters else {
            return "거리 -"
        }

        return String(format: "%.1f km", distanceMeters / 1_000)
    }

    private func durationText(for workout: UnifiedWorkout) -> String {
        let totalMinutes = max(Int((workout.durationSeconds / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }

        return "\(minutes)분"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter
    }()
}

private struct DuplicateMetricPill: View {
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

private extension UnifiedWorkoutDuplicateResolutionPolicy {
    var displayName: String {
        switch self {
        case .keepPrimary:
            return "대표 유지 후보"
        case .preferDuplicate:
            return "중복 후보 우선"
        case .needsReview:
            return "검토 필요"
        case .ignore:
            return "무시 후보"
        }
    }
}

private extension String {
    var localizedDuplicateReason: String {
        switch self {
        case "same externalId and source":
            return "같은 source와 external ID입니다."
        case "same workout type":
            return "운동 타입이 같습니다."
        case "start and end within 10 minutes":
            return "시작·종료가 10분 이내이며 짧은 기록의 85% 이상이 겹칩니다."
        case "duration difference within 25%":
            return "운동 시간 차이가 25% 이내입니다."
        case "distance difference within 25%":
            return "거리 차이가 25% 이내입니다."
        case "cross-source duplicate candidate":
            return "서로 다른 source에서 들어온 중복 후보입니다."
        case "average heart rate is similar":
            return "평균 심박이 유사합니다."
        default:
            return self
        }
    }
}

#Preview("UnifiedWorkoutDuplicateReviewView") {
    NavigationStack {
        UnifiedWorkoutDuplicateReviewView(
            viewModel: UnifiedWorkoutDuplicateReviewViewModel(
                store: PreviewUnifiedWorkoutDuplicateReviewStore()
            )
        )
    }
    .preferredColorScheme(.light)
}

private final class PreviewUnifiedWorkoutDuplicateReviewStore: UnifiedWorkoutStore {
    func saveWorkout(_ workout: UnifiedWorkout) async throws {}
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {}

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        let start = Date()
        return [
            makeWorkout(source: .garmin, startDate: start, externalId: "garmin-ride"),
            makeWorkout(source: .appleHealthKit, startDate: start.addingTimeInterval(90), externalId: "health-ride")
        ]
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}
    func deleteWorkout(id: UUID) async throws {}
    func deleteAllWorkouts() async throws {}

    private func makeWorkout(
        source: UnifiedDataSource,
        startDate: Date,
        externalId: String
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: UUID(),
            externalId: externalId,
            source: source,
            workoutType: .cycling,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(90 * 60),
            durationSeconds: 90 * 60,
            distanceMeters: 41_700,
            activeEnergyKcal: 720,
            averageHeartRate: 148,
            maxHeartRate: 172,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 77,
            dataQuality: .partial,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
