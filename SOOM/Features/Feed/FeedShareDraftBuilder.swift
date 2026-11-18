import Foundation

struct FeedShareDraftBuilder {
    var dateProvider: () -> Date = Date.init
    var idProvider: () -> UUID = UUID.init

    func build(from workout: UnifiedWorkout) -> FeedShareDraft {
        let distanceText = Self.distanceText(workout.distanceMeters)
        let fallbackStyle = StaticRouteFallbackStyle(workoutType: workout.workoutType)

        return FeedShareDraft(
            id: idProvider(),
            sourceWorkoutId: workout.id,
            sport: workout.workoutType,
            title: workout.displayTitle,
            body: workout.userDescription ?? "",
            distanceMeters: workout.distanceMeters,
            durationSeconds: workout.durationSeconds,
            averagePaceSecondsPerKm: Self.averagePaceSecondsPerKm(
                distanceMeters: workout.distanceMeters,
                durationSeconds: workout.durationSeconds
            ),
            routePreviewPayload: FeedShareDraftRoutePreviewPayload(
                routeExists: false,
                distanceText: distanceText,
                fallbackStyleRawValue: fallbackStyle.rawValue
            ),
            photoPlaceholders: [],
            tags: [Self.sportTitle(for: workout.workoutType), "기록", "SOOM"],
            visibility: .draft,
            createdAt: dateProvider(),
            activityDate: workout.startDate,
            deviceName: workout.deviceName ?? workout.feedSourceLabel,
            locationName: workout.locationName
        )
    }

    private static func averagePaceSecondsPerKm(
        distanceMeters: Double?,
        durationSeconds: TimeInterval
    ) -> Int? {
        guard let distanceMeters, distanceMeters > 0, durationSeconds > 0 else {
            return nil
        }

        return Int((durationSeconds / (distanceMeters / 1_000)).rounded())
    }

    private static func distanceText(_ meters: Double?) -> String? {
        guard let meters, meters > 0 else {
            return nil
        }

        return String(format: "%.1f km", meters / 1_000)
    }

    private static func sportTitle(for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .cycling:
            return "라이딩"
        case .running:
            return "러닝"
        case .walking:
            return "걷기"
        case .hiking:
            return "하이킹"
        case .swimming:
            return "수영"
        case .strength:
            return "근력"
        case .yoga:
            return "요가"
        case .other:
            return "운동"
        }
    }

    private static func photoTone(for workoutType: UnifiedWorkoutType) -> FeedPhotoTone {
        switch workoutType {
        case .cycling, .swimming:
            return .water
        case .running, .walking:
            return .city
        case .hiking:
            return .trail
        case .strength, .yoga, .other:
            return .morning
        }
    }
}

enum RecordPostSaveShareAction: Equatable {
    case shareToFeed
    case later
}

/// `postedRemotely` distinguishes a real Supabase post from the local-only
/// draft fallback — without this, RecordView has no way to tell the user
/// which one actually happened, and shows the same success message either
/// way (see SOOM_KNOWN_ISSUES.md: "Share-to-Feed Success Is Indistinguishable
/// From Local-Only Fallback").
struct RecordShareOutcome: Equatable {
    let draft: FeedShareDraft
    let postedRemotely: Bool
    var rankingRegistrationPending = false
    var localFinalizationPending = false

    /// A confirmed remote post remains successful even if the local journal
    /// cannot be finalized. Never re-enter publication or create a draft here.
    mutating func finalizeConfirmedPublication(_ operation: () throws -> Void) {
        guard postedRemotely else { return }
        do { try operation() } catch { localFinalizationPending = true }
    }
    /// The visibility actually applied. Always `.privateOnly` when
    /// `postedRemotely` is false — a local-only draft isn't visible to
    /// anyone else regardless of what the user had picked as their default.
    let visibility: ShareableWorkoutVisibility

    /// Shared between every share entry point (Record, workout detail) so
    /// they can't drift into telling the user something that didn't
    /// actually happen — this was itself the bug that motivated adding this
    /// property (a message unconditionally said "공개로 게시했어요" while every
    /// share was actually going out private).
    var summaryMessage: String {
        guard postedRemotely else {
            return "온라인에 게시되지 않았어요. 이 기기에 공유 초안으로 저장했어요."
        }

        if localFinalizationPending {
            return publicationSummary + " 기기 안 기록 정리는 완료하지 못했어요. 다시 게시하지 말고 피드에서 확인해 주세요."
        }
        return publicationSummary
    }

    private var publicationSummary: String {
        switch visibility {
        case .publicFeed:
            return rankingRegistrationPending ? "피드에 공개로 게시했어요. 랭킹 반영은 대기 중이며 랭킹 탭에서 재시도할 수 있어요." : "피드에 공개로 게시했어요."
        case .mutual:
            return "피드에 맞팔공개로 게시했어요."
        case .followers:
            return "피드에 승인된 팔로워 공개로 게시했어요."
        case .privateOnly:
            return "피드에 나만 보기로 게시했어요."
        }
    }
}

enum RecordSharePublicationError: Error, Equatable {
    case resultUnconfirmed
    var message: String { "게시 결과를 확인하지 못했어요. 이미 공개됐을 수 있으니 피드에서 확인해 주세요. 자동 재게시하거나 공유 초안으로 바꾸지 않았어요." }
}

struct RecordShareDraftCoordinator {
    let builder: FeedShareDraftBuilder
    let store: any FeedShareDraftStoreProtocol
    let remotePoster: (any FeedRemotePostPosting)?
    let visibilityProvider: () -> ShareableWorkoutVisibility
    let validateContext: @MainActor () throws -> Void
    let prepareWorkout: (@MainActor (UnifiedWorkout) async throws -> UnifiedWorkout)?
    let prepareRemoteShare: (@MainActor (UnifiedWorkout) async throws -> Void)?

    init(
        builder: FeedShareDraftBuilder = FeedShareDraftBuilder(),
        store: any FeedShareDraftStoreProtocol,
        remotePoster: (any FeedRemotePostPosting)? = nil,
        visibilityProvider: @escaping () -> ShareableWorkoutVisibility = {
            TrainingSettingsStore.shared.loadSettings().privacyDefault
        },
        validateContext: @escaping @MainActor () throws -> Void = {},
        prepareWorkout: (@MainActor (UnifiedWorkout) async throws -> UnifiedWorkout)? = nil,
        prepareRemoteShare: (@MainActor (UnifiedWorkout) async throws -> Void)? = nil
    ) {
        self.builder = builder
        self.store = store
        self.remotePoster = remotePoster
        self.visibilityProvider = visibilityProvider
        self.validateContext = validateContext
        self.prepareWorkout = prepareWorkout
        self.prepareRemoteShare = prepareRemoteShare
    }

    func handle(_ action: RecordPostSaveShareAction, workout: UnifiedWorkout) async throws -> RecordShareOutcome? {
        switch action {
        case .shareToFeed:
            try Task.checkCancellation()
            try await validateContext()
            let prepared = try await prepareWorkout?(workout) ?? workout
            try Task.checkCancellation()
            try await validateContext()
            let draft = builder.build(from: prepared)
            let chosenVisibility = visibilityProvider()

            // Only confirmed remote acceptance is a published post. A
            // moderation rejection must remain an editable error, never a
            // successful-looking local fallback.
            if let remotePoster {
                // Only an explicit share action prepares a remote route image.
                // Preparation can create a private linked post, but must finish
                // before the requested public visibility is applied. A failure
                // here remains retryable instead of becoming a success notice.
                // A switch to private must not expose a replacement image on
                // an existing public row while privatization is still pending.
                if chosenVisibility == .publicFeed || chosenVisibility == .followers || chosenVisibility == .mutual, let prepareRemoteShare {
                    try await prepareRemoteShare(prepared)
                    try Task.checkCancellation()
                    try await validateContext()
                }
                do {
                    try await remotePoster.postPublicPost(draft, visibility: chosenVisibility.feedPostVisibility)
                    try await validateContext()
                    return RecordShareOutcome(draft: draft, postedRemotely: true, visibility: chosenVisibility)
                } catch {
                    // An account change or cancellation must never become a
                    // successful local fallback for a different account.
                    try await validateContext()
                    try Task.checkCancellation()
                    if CommunitySafetyError.isPolicyRejection(error)
                        || error as? CommunitySafetyError == .accountChanged
                        || error is CancellationError { throw error }
                    // A lost response does not prove no publication occurred.
                    // Do not claim local-only success or create a second draft.
                    throw RecordSharePublicationError.resultUnconfirmed
                }
            }

            try Task.checkCancellation()
            try await validateContext()
            try await store.saveDraft(draft)
            try await validateContext()
            return RecordShareOutcome(draft: draft, postedRemotely: false, visibility: .privateOnly)
        case .later:
            return nil
        }
    }
}
