import SwiftData
import SwiftUI

/// Feed-detail-migration-plan.md Phase B: routes a feed item to the right
/// detail depth. "본인 글=Activity 수준 전체" needs no new presentation model —
/// `UnifiedWorkoutDetailDestination` (built across Phase A batches 1-9)
/// already renders full depth from a real `UnifiedWorkout`. Since Feed never
/// stores other users' raw workouts locally (Q1 invariant — `ActivityView`/
/// `UnifiedWorkoutDetailDestination` only ever query this device's own
/// SwiftData store), a successful local lookup of `sourceWorkoutId` is
/// itself sufficient proof this is the viewer's own post — no separate
/// author-identity check needed. Anything else (someone else's post, or an
/// own post whose local record is gone — e.g. shared from another device)
/// falls back to the existing sanitized `FeedItemDetailView`, unchanged.
struct FeedItemDetailDestination: View {
    let item: FeedItem
    let onSubmitComment: ((String) -> Void)?

    @Environment(\.modelContext) private var modelContext

    private enum ResolutionState {
        case loading
        case ownWorkout(UnifiedWorkout)
        case sanitized
    }

    @State private var state: ResolutionState = .loading

    init(item: FeedItem, onSubmitComment: ((String) -> Void)? = nil) {
        self.item = item
        self.onSubmitComment = onSubmitComment
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ownWorkout(let workout):
                ownWorkoutDestination(for: workout)
            case .sanitized:
                FeedItemDetailView(item: item, onSubmitComment: onSubmitComment)
            }
        }
        .task(id: item.id) {
            await resolve()
        }
    }

    private func resolve() async {
        guard let sourceWorkoutId = item.sourceWorkoutId else {
            state = .sanitized
            return
        }

        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        guard let workout = try? await store.fetchWorkout(id: sourceWorkoutId) else {
            state = .sanitized
            return
        }
        state = .ownWorkout(workout)
    }

    private func ownWorkoutDestination(for workout: UnifiedWorkout) -> some View {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let routeStore = SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext)
        let routeCandidateProvider = PersistedRouteCandidateProvider(store: routeStore)
        return UnifiedWorkoutDetailDestination(
            unifiedWorkout: workout,
            similarCandidateProvider: SimilarWorkoutCandidateProvider(
                store: store,
                persistedRouteProvider: routeCandidateProvider
            ),
            detailRouteContextProvider: WorkoutDetailRouteContextProvider(store: routeStore),
            relativeEffortHistoryProvider: SwiftDataRelativeEffortHistoryProvider(store: store),
            achievementHistoryProvider: SwiftDataWorkoutAchievementHistoryProvider(workoutStore: store, routeStore: routeStore),
            fitnessTrendHistoryProvider: SwiftDataFitnessTrendHistoryProvider(store: store),
            gpxRouteAttachmentService: GPXRouteAttachmentService(
                workoutStore: store,
                routeStore: routeStore
            ),
            fitRouteAttachmentService: FITRouteAttachmentService(
                workoutStore: store,
                routeStore: routeStore
            ),
            tcxRouteAttachmentService: TCXRouteAttachmentService(
                workoutStore: store,
                routeStore: routeStore
            ),
            companionUpdateService: WorkoutCompanionUpdateService(workoutStore: store)
        )
    }
}

/// Renders a single feed item's full detail. Deliberately reads only fields
/// already present on `FeedItem`/`ShareableWorkoutCardModel` — those are the
/// privacy boundary (see `ShareCardPrivacyPolicy`): sanitization already ran
/// once, at share-compose time, before the item ever reached the feed. This
/// view must never reach past that boundary to re-derive data from a raw
/// source (SwiftData workout record, HealthKit, etc.).
struct FeedItemDetailView: View {
    let item: FeedItem
    let onSubmitComment: ((String) -> Void)?

    @State private var isShowingComments = false
    @State private var isComposingComment = false

    init(item: FeedItem, onSubmitComment: ((String) -> Void)? = nil) {
        self.item = item
        self.onSubmitComment = onSubmitComment
    }

    var body: some View {
        SOOMScreen {
            header

            titleBlock

            mediaPreview

            metricsBlock

            messageBlock

            if item.contextLabels.isEmpty == false {
                contextLabelsRow
            }

            if let caption = item.caption, caption.isEmpty == false {
                textBlock(title: "코멘트", body: caption)
            }

            if let story = item.optionalShortStory, story.isEmpty == false, story != item.caption {
                textBlock(title: "이야기", body: story)
            }

            if item.reactions.isEmpty == false {
                reactionsRow
            }

            if item.comments.isEmpty == false {
                commentsButton
            }

            if onSubmitComment != nil {
                composeCommentButton
            }
        }
        .navigationTitle("피드 상세")
        .navigationBarTitleDisplayMode(.inline)
        .hidesSOOMTabBar()
        .sheet(isPresented: $isShowingComments) {
            FeedCommentListView(comments: item.comments)
        }
        .sheet(isPresented: $isComposingComment) {
            FeedCommentComposeSheet { body in
                onSubmitComment?(body)
            }
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
    }

    private var commentsButton: some View {
        Button {
            isShowingComments = true
        } label: {
            HStack(spacing: SOOMLayout.Spacing.sm) {
                Text("댓글 \(item.comments.count)개 보기")
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))

                Spacer(minLength: SOOMLayout.Spacing.sm)

                Image(systemName: SOOMIcon.chevronRight)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(SOOMColor.accent)
            .padding(SOOMLayout.Spacing.lg)
            .background(SOOMColor.surfaceAmbient)
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("댓글 \(item.comments.count)개 보기")
    }

    private var composeCommentButton: some View {
        Button {
            isComposingComment = true
        } label: {
            HStack(spacing: SOOMLayout.Spacing.sm) {
                Text("댓글 쓰기")
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))

                Spacer(minLength: SOOMLayout.Spacing.sm)

                Image(systemName: SOOMIcon.edit)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(SOOMColor.accent)
            .padding(SOOMLayout.Spacing.lg)
            .background(SOOMColor.surfaceAmbient)
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("댓글 쓰기")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            FeedProfileAvatar()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.authorName)
                        .font(SOOMFont.body(16, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(1)

                    Text(feedTypeText)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(relativeTimeText)
                    Text("·")
                    Text(item.visibility.title)
                }
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
            }

            Spacer(minLength: 8)
        }
    }

    private var titleBlock: some View {
        Text(feedTitle)
            .font(SOOMFont.displayMedium(22, relativeTo: .title3))
            .foregroundStyle(SOOMColor.ink)
            .fixedSize(horizontal: false, vertical: true)
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
            FeedReferenceMetricGrid(metrics: workoutMetrics(for: card))
        case .weeklyProgress(let card):
            FeedReferenceMetricGrid(metrics: [
                FeedReferenceMetric(label: "운동", value: card.workoutCountText),
                FeedReferenceMetric(label: "거리", value: card.totalDistanceText),
                FeedReferenceMetric(label: "시간", value: card.totalDurationText)
            ])
        }
    }

    private func workoutMetrics(for card: ShareableWorkoutCardModel) -> [FeedReferenceMetric] {
        var metrics = [
            FeedReferenceMetric(label: "거리", value: card.distanceText),
            FeedReferenceMetric(label: "시간", value: card.durationText),
            FeedReferenceMetric(label: speedOrPaceLabel(for: card), value: card.averagePaceText ?? "-"),
            FeedReferenceMetric(label: "획득 고도", value: card.elevationGainText ?? "-")
        ]
        if let heartRate = card.averageHeartRateText {
            metrics.append(FeedReferenceMetric(label: "평균 심박", value: heartRate))
        }
        if let energy = card.activeEnergyText {
            metrics.append(FeedReferenceMetric(label: "활동 에너지", value: energy))
        }
        return metrics
    }

    private var messageBlock: some View {
        SOOMCard(depth: .ambient) {
            Text(primaryMessage)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let growthMessage, growthMessage.isEmpty == false {
                Text(growthMessage)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let recoveryMessage, recoveryMessage.isEmpty == false {
                Label(recoveryMessage, systemImage: SOOMIcon.recovery)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.recovery)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var contextLabelsRow: some View {
        HStack(spacing: 8) {
            ForEach(item.contextLabels) { label in
                if let icon = label.icon {
                    Label(label.title, systemImage: icon)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(label.title)
                }
            }
        }
        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
        .foregroundStyle(SOOMColor.tertiaryInk)
    }

    private var reactionsRow: some View {
        HStack(spacing: 14) {
            ForEach(item.reactions) { reaction in
                HStack(spacing: 4) {
                    Text(reaction.symbol)
                    Text(reaction.label)
                }
            }
        }
        .font(SOOMFont.body(12, relativeTo: .caption))
        .foregroundStyle(SOOMColor.secondaryInk)
    }

    private func textBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)
            Text(body)
                .font(SOOMFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .fixedSize(horizontal: false, vertical: true)
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

    private var primaryMessage: String {
        switch item.cardData {
        case .workoutSession(let card):
            return card.primaryMessage
        case .weeklyProgress(let card):
            return card.progressMessage
        }
    }

    private var growthMessage: String? {
        switch item.cardData {
        case .workoutSession(let card):
            return card.growthMessage
        case .weeklyProgress(let card):
            return card.motivationText
        }
    }

    private var recoveryMessage: String? {
        switch item.cardData {
        case .workoutSession(let card):
            return card.recoveryMessage
        case .weeklyProgress:
            return nil
        }
    }

    private var relativeTimeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
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

#Preview("FeedItemDetailView - followers") {
    NavigationStack {
        FeedItemDetailView(item: FeedMockData.items[0])
    }
    .preferredColorScheme(.light)
}

#Preview("FeedItemDetailView - publicFeed") {
    NavigationStack {
        FeedItemDetailView(item: FeedMockData.items[2])
    }
    .preferredColorScheme(.light)
}
