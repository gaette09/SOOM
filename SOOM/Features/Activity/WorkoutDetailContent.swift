import SwiftUI
import UIKit
import HealthKit

struct WorkoutDetailContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let workout: Workout
    let showsHeader: Bool
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
    var healthKitWorkout: HKWorkout?
    var zoneDataProvider: WorkoutZoneDataProviding?
    var splitDataProvider: WorkoutSplitDataProviding?
    var renderShareImage: @MainActor (ShareableWorkoutCardModel, Color) -> UIImage? = { card, tint in
        ShareableWorkoutCardRenderer().render(card: card, tint: tint)
    }
    @State private var shareImage: UIImage?
    @State private var isShareSheetPresented = false
    @State private var shareErrorMessage: String?
    @State private var streamZoneSummaries: [WorkoutZoneSummary]?
    @State private var streamSplitInsight: WorkoutSplitInsight?
    @State private var isLoadingZoneSummaries = false
    @State private var didFailLoadingZoneSummaries = false
    @State private var feedDraftMessage: String?
    @State private var feedDraftErrorMessage: String?
    @State private var isCreatingFeedDraft = false

    static let sharePrivacyCopy = "4:5 이미지로 저장돼요. 위치, 심박, 회복 점수는 기본으로 제외됩니다."

    var body: some View {
        Group {
            if showsHeader {
                DetailHeader(
                    icon: workout.sport.iconName,
                    title: workout.title,
                    subtitle: "\(workout.sport.title) · \(workout.formattedDistance) · \(workout.formattedDuration)",
                    tint: workout.sport.tint
                )
            }

            ActivityDetailHeroMap(workout: workout, route: mapRoute)
            ActivityDetailSummaryCard(workout: workout)
            ActivityDetailRhythmCard(messages: rhythmMessages, tint: workout.sport.tint)

            if let terrainInsight, terrainInsight.isVisible {
                TerrainInsightCue(insight: terrainInsight, tint: workout.sport.tint)
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

                if let comparisonInsight {
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
                    if ActivityDetailVisibilityPolicy.showsCharts(workout: workout) {
                        WorkoutChartStack(workout: workout)
                    }
                    if ActivityDetailVisibilityPolicy.showsSplits(workout: workout) {
                        WorkoutSplitsCard(workout: workout)
                    }
                }
            }

            detailSection(.recovery) {
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
                isCreatingFeedDraft: isCreatingFeedDraft,
                feedDraftMessage: feedDraftMessage,
                feedDraftErrorMessage: feedDraftErrorMessage,
                createFeedDraft: { await createFeedDraft() }
            )

            if let shareableCard {
                VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                    SOOMSectionHeader("공유 카드 미리보기")
                    Text(Self.sharePrivacyCopy)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ShareableWorkoutCardView(card: shareableCard, tint: workout.sport.tint)
                shareButton(for: shareableCard)
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if let shareImage {
                WorkoutShareSheet(activityItems: [shareImage])
            }
        }
        .task(id: healthKitWorkout?.uuid) {
            await loadStreamZoneSummaries()
            await loadStreamSplitInsight()
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

    private var rhythmMessages: [String] {
        ActivityDetailRhythmInterpreter.messages(
            workout: workout,
            sessionSummary: sessionSummary,
            splitInsight: displayedSplitInsight,
            weaknessInsight: weaknessInsight,
            recoveryImpact: recoveryImpact
        )
    }

    private var showsSensorDataSection: Bool {
        ActivityDetailVisibilityPolicy.showsHeartRateEffort(workout: workout, streamSummaries: streamZoneSummaries)
            || ActivityDetailVisibilityPolicy.showsCharts(workout: workout)
            || ActivityDetailVisibilityPolicy.showsSplits(workout: workout)
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

    private func shareButton(for card: ShareableWorkoutCardModel) -> some View {
        Button {
            share(card)
        } label: {
            Label("공유하기", systemImage: SOOMIcon.share)
                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SOOMLayout.Card.padding)
                .background(workout.sport.tint)
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("공유 카드 공유하기")
        .accessibilityHint("공유 카드 이미지를 만든 뒤 iOS 공유 시트를 엽니다.")
    }

    @MainActor
    private func createFeedDraft() async {
        guard !isCreatingFeedDraft else { return }

        isCreatingFeedDraft = true
        feedDraftMessage = nil
        feedDraftErrorMessage = nil

        do {
            let coordinator = RecordShareDraftCoordinator(store: FileFeedShareDraftStore.live)
            _ = try await coordinator.handle(.shareToFeed, workout: unifiedWorkoutForDraft)
            feedDraftMessage = "피드 초안으로 저장했어요. 공개 전까지는 나에게만 보여요."
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
    private func share(_ card: ShareableWorkoutCardModel) {
        guard let image = renderedShareImage(for: card) else {
            shareErrorMessage = "공유 카드 이미지를 만들 수 없어요."
            return
        }

        shareImage = image
        isShareSheetPresented = true
    }

    @MainActor
    func renderedShareImage(for card: ShareableWorkoutCardModel) -> UIImage? {
        renderShareImage(card, workout.sport.tint)
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WorkoutDetailMapView(route: route, fallbackStyle: fallbackStyle, tint: workout.sport.tint)
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
        switch workout.sport {
        case .run: return .running
        case .bike, .brick: return .cycling
        case .swim: return .swimming
        }
    }
}

private struct ActivityDetailSummaryCard: View {
    let workout: Workout
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

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
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.label)
                                .font(SOOMFont.body(11, relativeTo: .caption2))
                                .foregroundStyle(SOOMColor.secondaryInk)
                            Text(metric.value)
                                .font(SOOMFont.body(16, weight: .bold, relativeTo: .subheadline))
                                .foregroundStyle(SOOMColor.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("운동 요약")
        .accessibilityValue(summaryMetrics.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }

    private var summaryMetrics: [ActivityDetailMetric] {
        var metrics = [
            ActivityDetailMetric(label: "거리", value: workout.distanceMeters > 0 ? workout.formattedDistance : "기록 없음"),
            ActivityDetailMetric(label: "시간", value: workout.formattedDuration),
            ActivityDetailMetric(label: workout.sport == .bike ? "평균 속도" : "평균 페이스", value: workout.formattedPace)
        ]

        if workout.avgHeartRate > 0 {
            metrics.append(ActivityDetailMetric(label: "평균 심박", value: "\(workout.avgHeartRate)bpm"))
        }

        return Array(metrics.prefix(6))
    }

    private var dateText: String {
        Self.dateFormatter.string(from: workout.date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter
    }()
}

private struct ActivityDetailRhythmCard: View {
    let messages: [String]
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                SOOMSectionHeader("오늘의 리듬", caption: "숫자보다 먼저, 오늘 운동의 흐름을 읽어요.")

                ForEach(Array(messages.prefix(3).enumerated()), id: \.offset) { index, message in
                    HStack(alignment: .top, spacing: SOOMLayout.Metrics.rowTextSpacing) {
                        Circle()
                            .fill(index == 0 ? tint : SOOMColor.surfaceMuted)
                            .frame(width: 8, height: 8)
                            .padding(.top, 7)
                            .accessibilityHidden(true)

                        Text(message)
                            .font(SOOMFont.body(index == 0 ? 17 : 15, weight: index == 0 ? .bold : .regular, relativeTo: .body))
                            .foregroundStyle(index == 0 ? SOOMColor.ink : SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("오늘의 리듬")
        .accessibilityValue(messages.joined(separator: " "))
    }
}

private struct ActivityDetailActionsCard: View {
    let isCreatingFeedDraft: Bool
    let feedDraftMessage: String?
    let feedDraftErrorMessage: String?
    let createFeedDraft: () async -> Void

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                SOOMSectionHeader("액션", caption: "저장은 유지하고, 공유는 초안부터 시작해요.")

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

                Text("회복 점수와 개인 코칭 문장은 피드 초안에 포함하지 않아요.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let feedDraftMessage {
                    statusMessage(feedDraftMessage, tint: SOOMColor.recovery)
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

struct ActivityDetailRhythmInterpreter {
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

private struct ActivityDetailMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
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
