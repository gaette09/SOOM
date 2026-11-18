import Combine
import Foundation
import Supabase
import SwiftUI

enum ClubWorkoutFeedError: LocalizedError, Equatable {
    case membershipRequired, unavailable
    var errorDescription: String? {
        switch self {
        case .membershipRequired: return "클럽에 가입하면 멤버들이 공개한 운동을 볼 수 있어요."
        case .unavailable: return "클럽 운동을 확인하지 못했어요. 연결 상태를 확인하고 다시 불러와 주세요."
        }
    }
}

struct ClubWorkoutFeedScope: Equatable {
    let viewerID: UUID?
    let accountGeneration: Int
    let safetyRevision: Int
}

enum ClubWorkoutFeedAction: Equatable {
    case cheer(Bool), bookmark(Bool), comment(String), delete
}

@MainActor
protocol ClubWorkoutFeedRemote {
    var sessionUserID: UUID? { get }
    func fetch(clubID: UUID, viewerID: UUID, limit: Int) async throws -> [FeedItem]
    func perform(_ action: ClubWorkoutFeedAction, on item: FeedItem, clubID: UUID, viewerID: UUID) async throws
}

/// All reads use the app's authenticated client and the existing club/feed RLS.
/// Public post filtering is explicit, so even the viewer's own private posts
/// cannot be included in a club's workout list.
@MainActor
struct SupabaseClubWorkoutFeedRemote: ClubWorkoutFeedRemote {
    let client: SupabaseClient
    var sessionUserID: UUID? { client.auth.currentSession?.user.id }

    private func validate(_ viewerID: UUID) throws {
        try Task.checkCancellation()
        guard sessionUserID == viewerID else { throw CommunitySafetyError.accountChanged }
    }

    private func requireAccess(clubID: UUID, viewerID: UUID) async throws {
        try validate(viewerID)
        let session = try await client.auth.session
        try validate(viewerID)
        guard session.user.id == viewerID else { throw CommunitySafetyError.accountChanged }
        let clubs: [ClubRow] = try await client.from("clubs").select("id,owner_user_id")
            .eq("id", value: clubID).limit(1).execute().value
        try validate(viewerID)
        guard let club = clubs.first, club.id == clubID else { throw ClubWorkoutFeedError.unavailable }
        let membership: [MemberRow] = try await client.from("club_members").select("user_id")
            .eq("club_id", value: clubID).eq("user_id", value: viewerID).limit(1).execute().value
        try validate(viewerID)
        guard club.ownerID == viewerID || membership.contains(where: { $0.userID == viewerID }) else {
            throw ClubWorkoutFeedError.membershipRequired
        }
    }

    private func memberIDs(clubID: UUID, viewerID: UUID) async throws -> [UUID] {
        var ids = Set<UUID>()
        var offset = 0
        // The whole membership is paged; a large club is never silently truncated.
        while true {
            try validate(viewerID)
            let rows: [MemberRow] = try await client.from("club_members").select("user_id")
                .eq("club_id", value: clubID).order("user_id")
                .range(from: offset, to: offset + 499).execute().value
            try validate(viewerID)
            ids.formUnion(rows.map(\.userID))
            if rows.count < 500 { return Array(ids) }
            offset += 500
        }
    }

    private func currentAuthors(_ ids: [UUID], clubID: UUID, viewerID: UUID) async throws -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        try validate(viewerID)
        let rows: [MemberRow] = try await client.from("club_members").select("user_id")
            .eq("club_id", value: clubID).in("user_id", values: ids).execute().value
        try validate(viewerID)
        return Set(rows.map(\.userID))
    }

    func fetch(clubID: UUID, viewerID: UUID, limit: Int) async throws -> [FeedItem] {
        try await requireAccess(clubID: clubID, viewerID: viewerID)
        let members = try await memberIDs(clubID: clubID, viewerID: viewerID)
        let remote = SupabaseFeedRemoteClient(client: client, expectedPostingUserID: viewerID)
        let bundles = try await remote.fetchPublicMemberPosts(authorIDs: members, viewerID: viewerID, limit: limit)
        try validate(viewerID)
        let authors = Array(Set(bundles.map { $0.post.userId }))
        let profiles = try await remote.fetchProfiles(ids: authors)
        try validate(viewerID)
        // Recheck membership and club visibility after hydration. A removed
        // member or a now-hidden club cannot survive a late response.
        try await requireAccess(clubID: clubID, viewerID: viewerID)
        let permittedAuthors = try await currentAuthors(authors, clubID: clubID, viewerID: viewerID)
        return bundles.compactMap { bundle in
            guard bundle.post.visibility == .publicPost, permittedAuthors.contains(bundle.post.userId) else { return nil }
            let profile = profiles.first { $0.id == bundle.post.userId }
            return bundle.makeFeedItem(authorName: profile?.displayName ?? "SOOM 사용자",
                authorHandle: profile?.handle, avatarPath: profile?.avatarPath, currentUserId: viewerID)
        }
    }

    func perform(_ action: ClubWorkoutFeedAction, on item: FeedItem, clubID: UUID, viewerID: UUID) async throws {
        try await requireAccess(clubID: clubID, viewerID: viewerID)
        let management = SupabaseFeedPostManagementRemote(client: client)
        guard let current = try await management.fetchPost(id: item.id, viewerID: viewerID),
              current.authorId == item.authorId, current.visibility == .publicFeed, !current.isLocalDraft else {
            throw FeedPostManagementError.contentUnavailable
        }
        let authors = try await currentAuthors([current.authorId], clubID: clubID, viewerID: viewerID)
        guard authors.contains(current.authorId) else { throw FeedPostManagementError.contentUnavailable }
        try validate(viewerID)
        switch action {
        case .cheer(let enabled):
            if enabled {
                try await client.from("feed_reactions")
                    .upsert(FeedReactionInsertDTO(postId: item.id, userId: viewerID, reactionType: "cheer"),
                        onConflict: "post_id,user_id,reaction_type", ignoreDuplicates: true).execute()
            } else {
                try await client.from("feed_reactions").delete().eq("post_id", value: item.id)
                    .eq("user_id", value: viewerID).eq("reaction_type", value: "cheer").execute()
            }
        case .bookmark(let enabled):
            try await management.setBookmark(postID: item.id, viewerID: viewerID, isSaved: enabled)
        case .comment(let body):
            let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 500 else { throw CommunitySafetyError.invalidTarget }
            try await client.from("feed_comments")
                .insert(FeedCommentInsertDTO(postId: item.id, userId: viewerID, body: text)).execute()
        case .delete:
            guard current.authorId == viewerID else { throw CommunitySafetyError.invalidTarget }
            try await management.deletePost(id: item.id, ownerID: viewerID)
        }
        try validate(viewerID)
    }

    private struct ClubRow: Decodable {
        let id: UUID
        let ownerID: UUID
        enum CodingKeys: String, CodingKey { case id; case ownerID = "owner_user_id" }
    }
    private struct MemberRow: Decodable {
        let userID: UUID
        enum CodingKeys: String, CodingKey { case userID = "user_id" }
    }
}

@MainActor
final class ClubWorkoutFeedModel: ObservableObject {
    static let pageLimit = 20
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var requiresMembership = false
    private let clubID: UUID
    private let remote: (any ClubWorkoutFeedRemote)?
    private let scope: () -> ClubWorkoutFeedScope
    private let filter: ([FeedItem]) -> [FeedItem]
    private var verifiedScope: ClubWorkoutFeedScope?
    private var loadID = UUID()
    private var mutations: Set<UUID> = []

    init(clubID: UUID, remote: (any ClubWorkoutFeedRemote)?,
         scope: @escaping () -> ClubWorkoutFeedScope, filter: @escaping ([FeedItem]) -> [FeedItem] = { $0 }) {
        self.clubID = clubID; self.remote = remote; self.scope = scope; self.filter = filter
    }

    var visibleItems: [FeedItem] {
        guard verifiedScope == scope(), remote?.sessionUserID == verifiedScope?.viewerID else { return [] }
        return filter(items)
    }

    private func validate(_ expected: ClubWorkoutFeedScope) throws -> UUID {
        try Task.checkCancellation()
        guard let viewerID = expected.viewerID else { throw CommunitySafetyError.signInRequired }
        guard expected == scope(), remote?.sessionUserID == viewerID else { throw CommunitySafetyError.accountChanged }
        return viewerID
    }

    func load() async {
        let requestID = UUID(); loadID = requestID
        let expected = scope()
        isLoading = true; errorMessage = nil; requiresMembership = false
        // A fresh RLS check must finish before previously loaded photos are shown.
        items = []; verifiedScope = nil
        defer { if loadID == requestID { isLoading = false } }
        do {
            let viewerID = try validate(expected)
            guard let remote else { throw CommunitySafetyError.unavailable }
            let fetched = try await remote.fetch(clubID: clubID, viewerID: viewerID, limit: Self.pageLimit)
            _ = try validate(expected)
            guard loadID == requestID else { return }
            items = Array(filter(fetched).filter { $0.visibility == .publicFeed && !$0.isLocalDraft }
                .sorted { $0.createdAt > $1.createdAt }.prefix(Self.pageLimit))
            verifiedScope = expected
        } catch {
            guard loadID == requestID else { return }
            items = []; verifiedScope = nil
            guard !(error is CancellationError), expected == scope() else { return }
            requiresMembership = error as? ClubWorkoutFeedError == .membershipRequired
            errorMessage = (error as? ClubWorkoutFeedError)?.errorDescription ?? CommunitySafetyError.message(for: error)
        }
    }

    func perform(_ action: ClubWorkoutFeedAction, on item: FeedItem) async throws {
        guard mutations.insert(item.id).inserted else { throw CommunitySafetyError.unavailable }
        defer { mutations.remove(item.id) }
        let expected = scope()
        do {
            let viewerID = try validate(expected)
            guard verifiedScope == expected, let current = visibleItems.first(where: { $0.id == item.id }),
                  let remote else { throw FeedPostManagementError.contentUnavailable }
            if action == .delete, current.authorId != viewerID { throw CommunitySafetyError.invalidTarget }
            try await remote.perform(action, on: current, clubID: clubID, viewerID: viewerID)
            _ = try validate(expected)
            await load()
            _ = try validate(expected)
        } catch {
            if expected == scope() { errorMessage = CommunitySafetyError.message(for: error) }
            throw error
        }
    }
}

struct ClubWorkoutFeedSection: View {
    let clubID: UUID
    let membershipState: ClubMembershipState
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: ClubWorkoutFeedModel
    @State private var selectedItem: FeedItem?

    init(clubID: UUID, membershipState: ClubMembershipState) {
        self.clubID = clubID; self.membershipState = membershipState
        let store = CommunitySafetyStore.shared
        let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient()
        let remote: (any ClubWorkoutFeedRemote)? = ReviewDemoMode.isActive
            ? ReviewDemoCommunityStore.shared : client.map { SupabaseClubWorkoutFeedRemote(client: $0) }
        _model = StateObject(wrappedValue: ClubWorkoutFeedModel(clubID: clubID,
            remote: remote,
            scope: { ClubWorkoutFeedScope(viewerID: store.viewerID,
                accountGeneration: store.accountGeneration, safetyRevision: store.revision) }, filter: store.filtered))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SOOMSectionHeader("멤버들의 운동", caption: "멤버가 전체 공개한 최근 운동 20개예요. 비공개 운동은 표시하지 않아요.")
            if safety.viewerID == nil {
                Text("로그인하고 클럽에 가입하면 멤버들의 공개 운동을 볼 수 있어요.")
                    .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            } else if model.isLoading && model.visibleItems.isEmpty {
                SOOMSkeleton(layout: .feed, label: "클럽 운동을 불러오는 중")
            } else if model.requiresMembership {
                Text(model.errorMessage ?? "클럽에 가입하면 공개 운동을 볼 수 있어요.")
                    .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            } else if let error = model.errorMessage {
                Text(error).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                Button("다시 불러오기") { Task { await model.load() } }.frame(minHeight: 44)
            } else if model.visibleItems.isEmpty {
                Text("멤버들이 공개한 운동이 아직 없어요.").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            }
            ForEach(model.visibleItems) { item in
                FeedItemCard(item: item, isOwnPost: item.authorId == safety.viewerID,
                    onToggleCheer: { Task { try? await model.perform(.cheer(!item.viewerHasCheered), on: item) } },
                    onToggleSave: { Task { try? await model.perform(.bookmark(!item.viewerHasSaved), on: item) } },
                    onSubmitComment: { try await model.perform(.comment($0), on: item) },
                    onDeletePost: { Task { try? await model.perform(.delete, on: item) } },
                    onOpen: { selectedItem = item }, requiresPublicVisibility: true)
            }
        }
        .accessibilityIdentifier("club.workoutFeed")
        .feedCardDestination(selection: $selectedItem, onSubmitComment: { item, body in
            try await model.perform(.comment(body), on: item)
        })
        .task(id: "\(clubID):\(safety.revision):\(membershipState)") { await model.load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load() } } }
        .onReceive(NotificationCenter.default.publisher(for: FeedPostManagement.didChange)) { _ in Task { await model.load() } }
        .onReceive(NotificationCenter.default.publisher(for: WorkoutRecordManagement.didChange)) { _ in Task { await model.load() } }
    }
}
