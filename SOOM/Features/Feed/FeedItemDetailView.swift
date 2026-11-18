import SwiftData
import SwiftUI

/// Own posts resolve to the exact same account-scoped detail as Activity.
/// Author identity is checked before any local UUID lookup.
struct FeedItemDetailDestination: View {
    let item: FeedItem
    let onSubmitComment: ((String) async throws -> Void)?

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    @State private var openingAccountGeneration: Int

    private enum ResolutionState {
        case loading
        case ownWorkout(UnifiedWorkout)
        case sanitized
    }

    @State private var visitReveals = WorkoutDetailPresentationStore()
    @State private var state: ResolutionState = .loading

    init(item: FeedItem, onSubmitComment: ((String) async throws -> Void)? = nil) {
        self.item = item
        self.onSubmitComment = onSubmitComment
        _openingAccountGeneration = State(initialValue: CommunitySafetyStore.shared.accountGeneration)
    }

    var body: some View {
        SocialAccessBoundary(allowActivityPreview: true) {
        Group {
            if safetyStore.isBlocked(item.authorId) || openingAccountGeneration != safetyStore.accountGeneration {
                CommunityContentUnavailableView()
            } else {
                switch state {
                case .loading:
                    ScrollView { SOOMSkeleton(layout: .detail, label: "운동 상세 불러오는 중").padding(SOOMLayout.screenPadding) }
                case .ownWorkout(let workout):
                    ownWorkoutDestination(for: workout)

                case .sanitized:
                    if safetyStore.canUseActivityPreview && !safetyStore.canUseSocial {
                        PreviewLegacyReadOnlyDetail(postID: item.id)
                    } else {
                        FeedItemDetailView(item: safetyStore.filtered([item]).first ?? item, onSubmitComment: onSubmitComment)
                    }
                }
            }
        }
        .task(id: item.id) {
            await resolve()
        }


        }.environment(\.workoutDetailVisitStore, visitReveals)
            .feedCommentProfileNavigationHost()
    }

    private func resolve() async {
        guard WorkoutRecordEditPolicy.owns(item, viewerID: safetyStore.viewerID),
              let sourceWorkoutId = item.sourceWorkoutId else {
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
        OwnWorkoutDetailDestination(workout: workout)
    }
}

/// Uses the same detail surface and summary components, limited to the fields
/// the server permits this viewer to read. Never derives private analytics.
struct FeedItemDetailView: View {
    let onSubmitComment: ((String) async throws -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.workoutDetailVisitStore) private var inheritedVisit
    @State private var visitReveals = WorkoutDetailPresentationStore()
    @StateObject private var management: FeedPostManagement
    init(item: FeedItem, onSubmitComment: ((String) async throws -> Void)? = nil, remote: (any FeedPostRemoteManaging)? = nil) {
        self.onSubmitComment = onSubmitComment
        _management = StateObject(wrappedValue: remote.map { FeedPostManagement(item: item, remote: $0, safetyStore: .shared) } ?? FeedPostManagement(item: item))
    }
    var body: some View {
        SocialAccessBoundary {
        Group {
            if management.canDisplayContent && management.item.permittedSharedDetail != nil {
                let shared = WorkoutDetailSharedRecord(item: management.item)
                WorkoutDeepDetailView(workout: shared.layoutIdentity,
                    sharedRecord: shared, sharedPostManagement: management)
                    .environment(\.workoutManagement, nil)

            } else if management.canDisplayContent {
                ContentUnavailableView("운동 상세 공유를 기다리고 있어요", soomIcon: "lock",
                    description: Text(WorkoutRecordEditPolicy.owns(management.item, viewerID: safety.viewerID)
                        ? "이 운동의 상세 공유 연결을 아직 확인하지 못했어요. 기존 기록은 그대로 보관되어 있으며 다시 게시할 필요는 없어요."
                        : "작성자의 상세 공유 동의와 연결이 확인되면 경로·측정 차트와 모션을 볼 수 있어요. 기존 측정자료는 자동으로 공개하지 않습니다."))
                    .accessibilityIdentifier("workout.sharedDetail.awaitingConsent")
            } else if !management.hasLoaded || management.isWorking || management.isCheckingAccess {
                ScrollView { SOOMSkeleton(layout: .detail, label: "공개 범위 확인 중").padding(SOOMLayout.screenPadding) }
            } else {
                ContentUnavailableView("기록을 표시할 수 없어요", soomIcon: "lock",
                    description: Text(management.errorMessage ?? "삭제되었거나 공개 범위가 변경된 기록입니다."))
                Button("다시 시도") { Task { await management.refresh() } }.frame(minHeight: 44)
            }
        }
        .hidesSOOMTabBar()
        .task { await management.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await management.refresh() } } }
        .onChange(of: safety.revision) { _, _ in Task { await management.refresh() } }



        }.environment(\.workoutDetailVisitStore, inheritedVisit ?? visitReveals)
    }
}


/// A fresh, read-only legacy view while the new write contract remains off.
/// It never renders the cached navigation item as an access grant.
private struct PreviewLegacyReadOnlyDetail: View {
    let postID: UUID
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var item: FeedItem?
    @State private var finished = false
    var body: some View {
        Group {
            if let item, !safety.isBlocked(item.authorId), safety.canUseActivityPreview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.authorName).font(.headline)
                        Text(item.activityDate ?? item.createdAt, style: .date)
                        if let seconds = item.workoutDurationSeconds { Text("운동 시간 \(Int(seconds / 60))분") }
                        if let meters = item.workoutDistanceMeters { Text(String(format: "거리 %.2f km", meters / 1000)) }
                        if let caption = item.caption, !caption.isEmpty { Text(caption) }
                        Text("열람이 허용된 운동 요약 · 읽기 전용").font(.caption).foregroundStyle(.secondary)
                        Text("추가 경로·측정자료 공유와 댓글 작성·좋아요는 별도 연결 확인 후 사용할 수 있어요.").font(.caption)
                        ForEach(item.comments.filter { !$0.isDeleted }) { comment in
                            Text(comment.body).font(.body)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            } else if finished { ContentUnavailableView("기록을 표시할 수 없어요", systemImage: "lock", description: Text("팔로우 또는 공개 범위가 변경되었을 수 있어요.")) }
            else { ProgressView("공개 범위 확인 중") }
        }
        .task(id: safety.revision) { await refresh() }
        .onChange(of: safety.accountGeneration) { _, _ in item = nil; finished = true }
        .onChange(of: scenePhase) { _, phase in
            item = nil
            if phase == .active { Task { await refresh() } }
        }
    }
    @MainActor private func refresh() async {
        item = nil; finished = false
        guard let viewer = safety.viewerID, safety.canUseActivityPreview,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { finished = true; return }
        let generation = safety.accountGeneration, revision = safety.revision
        let result = try? await SupabaseFeedRemoteClient(client: client).previewLegacyHome(
            .init(viewerID: viewer, scope: .home, ownerID: nil, before: nil, limit: 1), postID: postID)
        guard !Task.isCancelled, safety.viewerID == viewer, safety.accountGeneration == generation, safety.revision == revision else { return }
        item = result?.first; finished = true
    }
}
