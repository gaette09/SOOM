import Combine
import Foundation
import Supabase
import SwiftUI

enum FeedAudience: String, CaseIterable, Identifiable {
    case all, following, home
    var id: String { rawValue }
    var title: String { self == .home ? "내 운동과 팔로잉" : self == .all ? "전체" : "팔로잉" }
}

enum SocialPeopleKind: String, Identifiable {
    case followers, following
    var id: String { rawValue }
    var title: String { self == .followers ? "팔로워" : "팔로잉" }
}

/// Only fresh server/RLS results authorize a mutual post; unknown relations deny.
enum SocialPostPolicy {
    static func allows(_ visibility: FeedPostVisibility, owner: UUID, viewer: UUID?,
                       following: Bool?, followsViewer: Bool?, blocked: Bool = false) -> Bool {
        guard let viewer, !blocked else { return false }
        if owner == viewer { return true }
        switch visibility {
        case .publicPost: return true
        case .mutual: return following == true && followsViewer == true
        case .privatePost, .followers: return false
        }
    }
}

struct SocialSummary: Decodable, Equatable {
    let postCount: Int
    let followerCount: Int
    let followingCount: Int
    enum CodingKeys: String, CodingKey {
        case postCount = "post_count", followerCount = "follower_count", followingCount = "following_count"
    }
}

struct SocialPerson: Decodable, Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let handle: String?
    let avatarPath: String?
    let followedAt: Date
    var isFollowing: Bool
    let followsViewer: Bool
    var approvedState: ApprovedFollowState? = nil
    var approvedAccountScope: String? = nil
    var readPolicy: AccountActivityReadPolicy = .approvedFollowersV1
    var profile: FeedProfileDTO { FeedProfileDTO(id: id, displayName: displayName, handle: handle, avatarPath: avatarPath) }
    var relationshipTitle: String {
        if readPolicy == .profileOnlyV2 { return isFollowing ? "팔로잉" : "팔로우" }
        if approvedState == .pending { return "요청됨" }
        if isFollowing { return "팔로잉" }
        return approvedAccountScope == "private" || approvedAccountScope == "unselected" ? "팔로우 요청" : "팔로우"
    }
    func matches(search: String) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = term.hasPrefix("@") ? String(term.dropFirst()) : term
        return normalized.isEmpty || displayName.localizedCaseInsensitiveContains(normalized)
            || handle?.localizedCaseInsensitiveContains(normalized) == true
    }

    func actionTitle(viewerID: UUID?) -> String? {
        guard let viewerID, viewerID != id else { return nil }
        if readPolicy == .profileOnlyV2 { return isFollowing ? "팔로우해제" : "팔로우" }
        if approvedState == .pending { return "요청 취소" }
        return isFollowing ? "팔로우해제" : (approvedAccountScope == "private" || approvedAccountScope == "unselected" ? "팔로우 요청" : "팔로우")
    }
    enum CodingKeys: String, CodingKey {
        case id, handle, displayName = "display_name", avatarPath = "avatar_path", followedAt = "followed_at"
        case isFollowing = "is_following", followsViewer = "follows_viewer", approvedState = "approved_state", approvedAccountScope = "approved_account_scope"
    }
}

@MainActor
protocol ProfileSocialServing {
    var viewerID: UUID? { get }
    func summary(ownerID: UUID) async throws -> SocialSummary
    func people(ownerID: UUID, kind: SocialPeopleKind, after: SocialPerson?, limit: Int) async throws -> [SocialPerson]
    func setFollowing(_ enabled: Bool, userID: UUID) async throws -> Bool
}

struct ProfileOnlySocialEnvelope<Row: Decodable>: Decodable {
    let version: Int
    let viewerID: UUID
    let rows: [Row]
    let releaseReady: Bool
    enum CodingKeys: String, CodingKey { case version, rows, viewerID = "viewer_id", releaseReady = "release_ready" }
    func validated(viewer: UUID, currentViewer: UUID?) throws -> [Row] {
        guard ProfileOnlyPrivacyReleaseGate.productionReady, version == 2, releaseReady,
              viewerID == viewer, currentViewer == viewer, !Task.isCancelled else { throw CommunitySafetyError.unavailable }
        return rows
    }
}

@MainActor
struct SupabaseProfileSocialService: ProfileSocialServing {
    let client: SupabaseClient
    var readPolicy: AccountActivityReadPolicy = .deployed
    var viewerID: UUID? { client.auth.currentSession?.user.id }
    func summary(ownerID: UUID) async throws -> SocialSummary {
        struct Params: Encodable { let p_owner: UUID }
        let rows: [SocialSummary]
        if readPolicy == .profileOnlyV2 {
            guard let viewer = viewerID else { throw CommunitySafetyError.signInRequired }
            let receipt: ProfileOnlySocialEnvelope<SocialSummary> = try await client.rpc("soom_social_summary_candidate_v2", params: Params(p_owner: ownerID)).execute().value
            rows = try receipt.validated(viewer: viewer, currentViewer: viewerID)
            guard rows.count == 1, rows.allSatisfy({ $0.postCount >= 0 && $0.followerCount >= 0 && $0.followingCount >= 0 }) else { throw CommunitySafetyError.unavailable }
        } else { rows = try await client.rpc("soom_social_summary", params: Params(p_owner: ownerID)).execute().value }
        guard let value = rows.first else { throw CommunitySafetyError.unavailable }
        return value
    }
    func people(ownerID: UUID, kind: SocialPeopleKind, after: SocialPerson?, limit: Int) async throws -> [SocialPerson] {
        struct Params: Encodable {
            let p_owner: UUID; let p_kind: String; let p_before: Date?; let p_before_id: UUID?; let p_limit: Int
        }
        let params = Params(p_owner: ownerID, p_kind: kind.rawValue, p_before: after?.followedAt, p_before_id: after?.id, p_limit: limit)
        var rows: [SocialPerson]
        if readPolicy == .profileOnlyV2 {
            guard let viewer = viewerID else { throw CommunitySafetyError.signInRequired }
            let receipt: ProfileOnlySocialEnvelope<SocialPerson> = try await client.rpc("soom_social_people_candidate_v2", params: params).execute().value
            rows = try receipt.validated(viewer: viewer, currentViewer: viewerID)
            guard rows.count <= min(max(limit, 1), 100), Set(rows.map(\.id)).count == rows.count else { throw CommunitySafetyError.unavailable }
            for index in rows.indices { rows[index].readPolicy = .profileOnlyV2 }
            return rows
        }
        rows = try await client.rpc("soom_social_people", params: params).execute().value
        let privacy = SupabaseAccountPrivacyService(client: client, readPolicy: readPolicy)
        do {
            if try await privacy.fetch().enabled {
                let states = try await privacy.states(rows.map(\.id))
                for index in rows.indices {
                    let state = states.first { $0.userID == rows[index].id }?.state ?? .none
                    rows[index].approvedState = state; rows[index].isFollowing = state == .accepted
                    rows[index].approvedAccountScope = states.first { $0.userID == rows[index].id }?.accountScope
                }
            }
        } catch let error as PostgrestError where error.code == "PGRST202" && readPolicy == .approvedFollowersV1 { }
        return rows
    }
    func setFollowing(_ enabledFollowing: Bool, userID: UUID) async throws -> Bool {
        guard let actor = viewerID else { throw CommunitySafetyError.signInRequired }
        func check() throws { guard viewerID == actor else { throw CommunitySafetyError.accountChanged } }
        let privacy = SupabaseAccountPrivacyService(client: client, readPolicy: readPolicy)
        let enabled: Bool
        do { enabled = try await privacy.fetch().enabled }
        catch let error as PostgrestError where error.code == "PGRST202" && readPolicy == .approvedFollowersV1 { enabled = false }
        try check()
        if enabled {
            let current = try await privacy.states([userID]).first
            try check()
            let receipt = try await privacy.request(userID, following: enabledFollowing, expectedRequest: current?.requestID,actor:actor, expectedRevision: current?.edgeRevision)
            try check()
            // Return the resulting outgoing intent, not a success flag.
            // A confirmed cancellation/unfollow must return false to callers.
            return receipt.state != .none
        }
        struct Params: Encodable { let p_user: UUID; let p_following: Bool }
        return try await client.rpc("soom_set_following", params: Params(p_user: userID, p_following: enabledFollowing)).execute().value
    }
}

@MainActor
final class ProfileSocialModel: ObservableObject {
    @Published private(set) var summary: SocialSummary?
    @Published private(set) var people: [SocialPerson] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = false
    @Published private(set) var busyIDs = Set<UUID>()
    @Published private(set) var errorMessage: String?
    private let service: (any ProfileSocialServing)?
    private let safety: CommunitySafetyStore
    private var requestID = UUID()
    private var cursor: SocialPerson?
    private var selectedKind: SocialPeopleKind?
    private var selectedQuery = ""
    private let generation: Int
    private let viewer: UUID?
    private var subscription: AnyCancellable?
    private(set) var ownerID: UUID
    static let pageSize = 20

    init(ownerID: UUID, service: (any ProfileSocialServing)?, safety: CommunitySafetyStore = .shared) {
        self.ownerID = ownerID; self.service = service; self.safety = safety
        generation = safety.accountGeneration; viewer = safety.viewerID
        subscription = safety.$revision.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.requestID = UUID(); self.summary = nil; self.people = []; self.cursor = nil
            self.hasMore = false; self.isLoading = false
        }
    }
    convenience init(ownerID: UUID) {
        let service: (any ProfileSocialServing)? = ReviewDemoMode.isActive ? ReviewDemoCommunityStore.shared :
            SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient().map { SupabaseProfileSocialService(client: $0) }
        self.init(ownerID: ownerID, service: service)
    }
    private var current: Bool {
        viewer != nil && viewer == service?.viewerID && viewer == safety.viewerID && generation == safety.accountGeneration && safety.canUseSocial && !safety.isBlocked(ownerID)
    }
    func load(kind: SocialPeopleKind? = nil, reset: Bool = true, query: String? = nil) async {
        guard current, let service else { summary = nil; people = []; return }
        let proposed = (query ?? selectedQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard proposed.count <= 80 else { requestID = UUID(); people = []; hasMore = false; isLoading = false; errorMessage = "검색어를 80자 이내로 입력해 주세요."; return }
        if !reset && (isLoading || !hasMore || proposed != selectedQuery) { return }
        if reset { selectedQuery = proposed; requestID = UUID(); people = []; cursor = nil; hasMore = false; selectedKind = kind; summary = nil }
        let token = requestID; let revision = safety.revision
        isLoading = true; errorMessage = nil
        defer { if token == requestID { isLoading = false } }
        do {
            let counts = try await service.summary(ownerID: ownerID)
            guard current, token == requestID, revision == safety.revision, !Task.isCancelled else { return }
            summary = counts
            guard let kind = selectedKind else { return }
            let initialMatchCount = people.count
            repeat {
                let previousCursor = cursor
                let rows = try await service.people(ownerID: ownerID, kind: kind, after: cursor, limit: Self.pageSize)
                guard current, token == requestID, revision == safety.revision, !Task.isCancelled else { return }
                // Search only this authorized list. Walk raw pages so a matching
                // name after page1 is discoverable without new server privileges.
                var ids = Set(people.map(\.id))
                people.append(contentsOf: rows.filter {
                    !safety.isBlocked($0.id) && $0.matches(search: selectedQuery) && ids.insert($0.id).inserted
                })
                cursor = rows.last ?? cursor; hasMore = rows.count == Self.pageSize
                if hasMore, let previousCursor, cursor?.id == previousCursor.id,
                   cursor?.followedAt == previousCursor.followedAt { throw FeedPostManagementError.changeNotConfirmed }
            } while !selectedQuery.isEmpty && hasMore && people.count - initialMatchCount < Self.pageSize

        } catch {
            guard current, token == requestID, !Task.isCancelled else { return }
            errorMessage = "소셜 정보를 불러오지 못했어요. 다시 시도해 주세요."
            // A failed read grants no relationship or cached restricted content.
        }
    }
    func toggle(_ person: SocialPerson) async {
        guard current, let service, person.id != viewer, !safety.isBlocked(person.id),
              people.contains(where: { $0.id == person.id }), busyIDs.insert(person.id).inserted else { return }
        defer { busyIDs.remove(person.id) }
        let desired = person.readPolicy == .profileOnlyV2 ? !person.isFollowing : (person.approvedState == .pending ? false : !person.isFollowing)
        safety.invalidateRelationships()
        do {
            let confirmed = try await service.setFollowing(desired, userID: person.id)
            guard current else { return }
            guard confirmed == desired else { throw FeedPostManagementError.changeNotConfirmed }
            safety.invalidateRelationships()
            NotificationCenter.default.post(name: FeedFollowingStore.didChange, object: nil, userInfo: ["viewerID": viewer as Any])
            await load(kind: selectedKind)
        } catch {
            guard current else { return }
            safety.invalidateRelationships()
            await load(kind: selectedKind)
            errorMessage = "팔로우 변경을 확인하지 못했어요. 현재 상태를 다시 확인해 주세요."
        }
    }
}

struct ProfileSocialStatsView: View {
    let userID: UUID
    var onPosts: (() -> Void)? = nil
    @StateObject private var model: ProfileSocialModel
    @ObservedObject private var safety = CommunitySafetyStore.shared
    init(userID: UUID, onPosts: (() -> Void)? = nil) { self.userID = userID; self.onPosts = onPosts; _model = StateObject(wrappedValue: ProfileSocialModel(ownerID: userID)) }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { onPosts?() } label: {
                    stat("공유한 게시물", model.summary?.postCount).frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.plain).disabled(model.summary == nil || onPosts == nil)
                    .accessibilityHint("현재 볼 수 있는 게시물 목록 열기")
                    .accessibilityIdentifier("profile.social.posts")
                ForEach([SocialPeopleKind.followers, .following]) { kind in
                    NavigationLink {
                        ProfileSocialPeopleView(ownerID: userID, kind: kind)
                    } label: {
                        stat(kind.title, kind == .followers ? model.summary?.followerCount : model.summary?.followingCount)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain).disabled(model.summary == nil)
                    .accessibilityHint("\(kind.title) 프로필 목록 열기")
                    .accessibilityIdentifier("profile.social.\(kind.rawValue)")
                }
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("소셜 정보 다시 불러오기") { Task { await model.load() } }.frame(minHeight: 44)
            }
        }
        .task(id: "\(userID)-\(safety.revision)") { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: WorkoutRecordManagement.didChange)) { _ in Task { await model.load() } }
    }
    private func stat(_ title: String, _ count: Int?) -> some View {
        VStack(spacing: 4) {
            if count == nil && model.isLoading {
                SOOMSkeleton(layout: .value, label: title + " 불러오는 중").frame(width: 50)
            } else { Text(count.map(String.init) ?? "—").font(.headline) }
            Text(title).font(.subheadline)
        }.accessibilityElement(children: .ignore).accessibilityLabel(title)
            .accessibilityValue(count.map(String.init) ?? (model.isLoading ? "불러오는 중" : "확인되지 않음"))
    }
}

struct ProfileSocialPeopleView: View {
    @Environment(\.dismiss) private var dismiss
    let ownerID: UUID
    let kind: SocialPeopleKind
    @State private var query = ""
    @StateObject private var model: ProfileSocialModel
    @ObservedObject private var safety = CommunitySafetyStore.shared
    init(ownerID: UUID, kind: SocialPeopleKind, service: (any ProfileSocialServing)? = nil) {
        self.ownerID = ownerID; self.kind = kind
        _model = StateObject(wrappedValue: service.map { ProfileSocialModel(ownerID: ownerID, service: $0) } ?? ProfileSocialModel(ownerID: ownerID))
    }
    var body: some View {
        SocialAccessBoundary {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                    Button("다시 시도") { Task { await model.load(kind: kind, query: query) } }.frame(minHeight: 44)
                }
                ForEach(model.people) { person in
                    HStack(spacing: 12) {
                        SOOMProfileLink(userID: person.id, profile: person.profile) {
                            HStack {
                                SOOMAvatarView(userID: person.id, avatarPath: person.avatarPath, size: 44)
                                VStack(alignment: .leading) { Text(person.displayName); if let handle = person.handle { Text(handle).font(.caption).foregroundStyle(.secondary) } }
                            }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityLabel("\(person.displayName) 프로필 열기")
                        if let title = person.actionTitle(viewerID: safety.viewerID) {
                            Button(person.relationshipTitle) { Task { await model.toggle(person) } }
                                .frame(minWidth: 92, minHeight: 44).font(.subheadline)
                                .disabled(model.busyIDs.contains(person.id))
                                .accessibilityLabel("\(person.displayName) \(title)")
                                .accessibilityValue(person.relationshipTitle)
                                .accessibilityIdentifier("profile.social.action.\(person.id)")
                        }
                    }.padding(.horizontal)
                }
                if model.isLoading && model.people.isEmpty { SOOMSkeleton(layout: .list, label: "목록 불러오는 중").padding(.horizontal) }
                if model.people.isEmpty && !model.isLoading && model.errorMessage == nil {
                    ContentUnavailableView(query.isEmpty ? "\(kind.title) 목록이 비어 있어요" : "검색 결과가 없어요", systemImage: "person.2")
                }
                if model.hasMore { Button("더 보기") { Task { await model.load(kind: kind, reset: false, query: query) } }.frame(minHeight: 44).disabled(model.isLoading) }
            }.padding(.vertical)
        }.navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .onChange(of: safety.canUseSocial) { _, allowed in if !allowed { dismiss() } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "이름 또는 사용자 이름")
            .task(id: query) {
                if !query.isEmpty {
                    do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                }
                guard !Task.isCancelled else { return }
                await model.load(kind: kind, query: query)
            }
            .onChange(of: safety.revision) { _, _ in
                if model.busyIDs.isEmpty { Task { await model.load(kind: kind, query: query) } }
            }
    
        }
    }
}


/// Cursor state is request-scoped and actor isolated. Offset is only a local
/// page identity; the server uses (activity_at,id), never upload/update time.
actor FeedKeysetPages {
    struct Token: Sendable { let key: String; let epoch: UUID; let date: Date?; let postID: UUID? }
    private struct Entry { let viewer: UUID; let revision: Int; var epoch: UUID; var offset: Int; var date: Date?; var postID: UUID? }
    private var entries: [String: Entry] = [:]
    func begin(scope: String, authorID: UUID?, offset: Int, viewer: UUID, revision: Int) throws -> Token {
        let key = "\(scope):\(authorID?.uuidString ?? "-")"
        if offset == 0 {
            entries[key] = Entry(viewer: viewer, revision: revision, epoch: UUID(), offset: 0)
        }
        guard let entry = entries[key], entry.viewer == viewer, entry.revision == revision, entry.offset == offset else {
            throw CancellationError()
        }
        return Token(key: key, epoch: entry.epoch, date: entry.date, postID: entry.postID)
    }
    func finish(token: Token, rows: [FeedPostDTO], offset: Int) throws {
        guard var entry = entries[token.key], entry.epoch == token.epoch, entry.offset == offset else { throw CancellationError() }
        entry.offset += rows.count
        if let last = rows.last { entry.date = last.activityAt ?? last.routeSummary?.startedAt ?? last.createdAt; entry.postID = last.id }
        entries[token.key] = entry
    }
}

extension ReviewDemoCommunityStore: ProfileSocialServing {
    var viewerID: UUID? { ReviewDemoMode.isActive ? ReviewDemoMode.userID : nil }
    private var demoPeopleIDs: Set<UUID> { Set(items.map(\.authorId)).subtracting([ReviewDemoMode.userID]) }
    func summary(ownerID: UUID) async throws -> SocialSummary {
        let values = try await fetchFeed(limit: 500).filter { $0.authorId == ownerID }
        let incoming = ownerID == ReviewDemoMode.userID ? demoPeopleIDs.count : (following.contains(ownerID) ? 1 : 0)
        let outgoing = ownerID == ReviewDemoMode.userID ? following.count : 1
        return SocialSummary(postCount: values.count, followerCount: incoming, followingCount: outgoing)
    }
    func people(ownerID: UUID, kind: SocialPeopleKind, after: SocialPerson?, limit: Int) async throws -> [SocialPerson] {
        let ids: Set<UUID>
        if ownerID == ReviewDemoMode.userID { ids = kind == .followers ? demoPeopleIDs : following }
        else { ids = kind == .following || following.contains(ownerID) ? [ReviewDemoMode.userID] : [] }
        return Array(ids.sorted { $0.uuidString > $1.uuidString }.filter { after == nil || $0.uuidString < after!.id.uuidString }.prefix(limit)).map { id in
            let value = profile(id)
            return SocialPerson(id: id, displayName: value.displayName, handle: value.handle, avatarPath: value.avatarPath,
                followedAt: Date(timeIntervalSince1970: 1), isFollowing: following.contains(id), followsViewer: demoPeopleIDs.contains(id))
        }
    }
    func setFollowing(_ enabled: Bool, userID: UUID) async throws -> Bool {
        if following.contains(userID) != enabled { try toggleFollow(userID) }
        return following.contains(userID)
    }
}

struct ProfileSearchPerson: Decodable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let handle: String?, avatarPath: String?
    var profile: FeedProfileDTO { .init(id:id,displayName:displayName,handle:handle,avatarPath:avatarPath) }
    enum CodingKeys: String,CodingKey { case id,displayName = "display_name",handle,avatarPath = "avatar_path" }
}
@MainActor
protocol ProfileSearchServing {
    var viewerID: UUID? { get }
    func search(query: String, after: ProfileSearchPerson?, limit: Int) async throws -> [ProfileSearchPerson]
}
@MainActor
struct SupabaseProfileSearchService: ProfileSearchServing {
    let client: SupabaseClient
    var viewerID: UUID? { client.auth.currentSession?.user.id }
    func search(query: String, after: ProfileSearchPerson?, limit: Int) async throws -> [ProfileSearchPerson] {
        struct Params: Encodable { let p_query: String; let p_after_name: String?; let p_after_id: UUID?; let p_limit: Int }
        return try await client.rpc("soom_profile_search_v1",params:Params(p_query:query,p_after_name:after?.displayName,
            p_after_id:after?.id,p_limit:limit)).execute().value
    }
}
@MainActor
struct DemoProfileSearchService: ProfileSearchServing {
    var viewerID: UUID? { ReviewDemoMode.isActive ? ReviewDemoMode.userID : nil }
    func search(query: String, after: ProfileSearchPerson?, limit: Int) async throws -> [ProfileSearchPerson] {
        guard ReviewDemoMode.isActive else { throw CommunitySafetyError.accountChanged }
        let ids = Set(ReviewDemoCommunityStore.shared.items.map(\.authorId))
        return ids.map { id in
            let profile = ReviewDemoCommunityStore.shared.profile(id)
            return ProfileSearchPerson(id:id,displayName:profile.displayName,handle:profile.handle,avatarPath:profile.avatarPath)
        }.filter { $0.displayName.localizedCaseInsensitiveContains(query) || $0.handle?.localizedCaseInsensitiveContains(query) == true }
            .sorted { ($0.displayName,$0.id.uuidString)<($1.displayName,$1.id.uuidString) }
            .filter { after == nil || ($0.displayName,$0.id.uuidString)>(after!.displayName,after!.id.uuidString) }.prefix(limit).map { $0 }
    }
}
@MainActor
final class ProfileSearchModel: ObservableObject {
    @Published private(set) var rows: [ProfileSearchPerson] = []
    @Published private(set) var busy = false
    @Published private(set) var isWaiting = false
    @Published private(set) var completedQuery: String?
    @Published private(set) var hasMore = false
    @Published private(set) var error: String?
    @Published private(set) var pageError: String?
    var isSearching: Bool { isWaiting || busy }
    private let service: (any ProfileSearchServing)?
    private let safety: CommunitySafetyStore
    private let owner: UUID?, generation: Int
    private var request = UUID()
    private var query = ""
    private var cursor: ProfileSearchPerson?
    init(service: (any ProfileSearchServing)?, safety: CommunitySafetyStore = .shared) {
        self.service = service; self.safety = safety; owner = safety.viewerID; generation = safety.accountGeneration
    }
    convenience init() {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
           let scenario = ProcessInfo.processInfo.environment["SOOM_SEARCH_QA"], ["loading", "pagination"].contains(scenario) {
            self.init(service: ProfileSearchUXFixture(scenario: scenario)); return
        }
        #endif
        let service: (any ProfileSearchServing)? = ReviewDemoMode.isActive ? DemoProfileSearchService() :
            SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient().map(SupabaseProfileSearchService.init)
        self.init(service: service)
    }
    func clear() {
        request = UUID(); rows = []; cursor = nil; hasMore = false
        busy = false; isWaiting = false; completedQuery = nil; error = nil; pageError = nil
    }
    private func currentViewerIsValid(_ service: any ProfileSearchServing) -> Bool {
        guard let owner else { return false }
        return service.viewerID == owner && safety.viewerID == owner
            && generation == safety.accountGeneration && safety.canUseSocial
    }
    /// Clear the old query immediately and distinguish debounce from a completed empty response.
    @discardableResult
    func prepareSearch(query proposed: String) -> Bool {
        clear(); query = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        guard query.count <= 80 else { error = "검색어를 80자 이내로 입력해 주세요."; return false }
        guard let service, currentViewerIsValid(service) else { return false }
        isWaiting = true; return true
    }
    func load(query proposed: String, reset: Bool = true) async {
        guard !Task.isCancelled else { return }
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if reset { guard prepareSearch(query: proposed) else { return } }
        else {
            guard let service, currentViewerIsValid(service) else { clear(); return }
            guard !busy, !isWaiting, hasMore, query == trimmed else { return }
        }
        guard let service else { return }
        let token = request, revision = safety.revision
        isWaiting = false; busy = true; error = nil; pageError = nil
        defer { if request == token { busy = false } }
        do {
            let values = try await service.search(query: trimmed, after: cursor, limit: 20)
            guard request == token else { return }
            guard currentViewerIsValid(service), revision == safety.revision else { clear(); return }
            guard !Task.isCancelled else { return }
            var ids = Set(rows.map(\.id))
            rows += values.filter { !safety.isBlocked($0.id) && ids.insert($0.id).inserted }
            cursor = values.last ?? cursor; hasMore = values.count == 20; completedQuery = trimmed
        } catch {
            guard request == token else { return }
            guard currentViewerIsValid(service), revision == safety.revision else { clear(); return }
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            // Retaining a page after a transport failure must not retain revoked access.
            if CommunitySafetyError.isPolicyRejection(error)
                || (error as? CommunitySafetyError) == .accountChanged
                || (error as? CommunitySafetyError) == .signInRequired
                || (error as? PostgrestError)?.code == "42501" {
                clear(); self.error = CommunitySafetyError.message(for: error); return
            }
            if reset {
                rows = []; cursor = nil; hasMore = false
                self.error = "사용자를 찾지 못했어요. 다시 시도해 주세요."
            } else {
                // Keep both the accepted rows and the cursor so retry asks for the same page.
                pageError = "추가 사용자를 불러오지 못했어요. 기존 결과는 유지돼요."
            }
        }
    }
}
struct ProfileSearchView: View {
    @State private var query = ""
    @StateObject private var model: ProfileSearchModel
    init(service: (any ProfileSearchServing)? = nil) {
        _model = StateObject(wrappedValue: service.map { ProfileSearchModel(service: $0) } ?? ProfileSearchModel())
    }
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        SocialAccessBoundary {
        List {
            Text("전체 사용자에서 이름이나 사용자 이름으로 찾아보세요. 비공개 계정은 기본 프로필만 찾을 수 있고, 운동은 승인받은 뒤 볼 수 있어요.")
                .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                .accessibilityIdentifier("profile.search.scope")
            if let error = model.error {
                Text(error).foregroundStyle(SOOMColor.warning)
                Button("다시 시도") { Task { await model.load(query: query) } }.frame(minHeight: 44)
            }
            ForEach(model.rows) { person in
                SOOMProfileLink(userID: person.id, profile: person.profile) {
                    HStack(spacing: 12) {
                        SOOMAvatarView(userID: person.id, avatarPath: person.avatarPath, size: 44)
                        VStack(alignment: .leading) { Text(person.displayName); if let handle = person.handle { Text(handle).font(.caption).foregroundStyle(.secondary) } }
                    }.frame(minHeight: 48)
                }.accessibilityIdentifier("profile.search.result.\(person.id)")
            }
            if model.isSearching {
                SOOMSkeleton(layout: model.rows.isEmpty ? .list : .row,
                    label: model.rows.isEmpty ? "사용자 찾는 중" : "추가 사용자 불러오는 중")
                    .accessibilityIdentifier("profile.search.loading")
            }
            if !model.isSearching, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               model.completedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines),
               model.rows.isEmpty, model.error == nil, model.pageError == nil {
                Text("일치하는 사용자가 없어요.").accessibilityIdentifier("profile.search.empty")
            }
            if let pageError = model.pageError {
                Text(pageError).foregroundStyle(SOOMColor.warning).accessibilityIdentifier("profile.search.pageError")
                Button("추가 결과 다시 불러오기") { Task { await model.load(query: query, reset: false) } }
                    .frame(minHeight: 44).accessibilityIdentifier("profile.search.pageRetry").disabled(model.isSearching)
            } else if model.hasMore {
                Button("더 보기") { Task { await model.load(query: query, reset: false) } }
                    .frame(minHeight: 44).accessibilityIdentifier("profile.search.more").disabled(model.isSearching)
            }
        }.navigationTitle("사용자 검색").searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "이름 또는 사용자 이름")
            .task(id: query) {
                guard !Task.isCancelled, model.prepareSearch(query: query) else { return }
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                await model.load(query: query)
            }
            .onChange(of: safety.accountGeneration) { _,_ in query = ""; model.clear() }
            .onChange(of: safety.revision) { _,_ in model.clear(); Task { await model.load(query: query) } }
            .onChange(of: scenePhase) { _,phase in if phase == .active { model.clear(); Task { await model.load(query: query) } } }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Synthetic search responses only, requiring an active disposable Demo and explicit QA flags.
@MainActor
private final class ProfileSearchUXFixture: ProfileSearchServing {
    let scenario: String
    var viewerID: UUID? { ReviewDemoMode.isActive ? ReviewDemoMode.userID : nil }
    private var pageAttempts = 0
    init(scenario: String) { self.scenario = scenario }
    func search(query: String, after: ProfileSearchPerson?, limit: Int) async throws -> [ProfileSearchPerson] {
        guard ReviewDemoMode.isActive else { throw CommunitySafetyError.accountChanged }
        if scenario == "loading" { try await Task.sleep(for: .seconds(4)); return [] }
        if after != nil {
            pageAttempts += 1
            if pageAttempts == 1 { throw CommunitySafetyError.unavailable }
        }
        let values = (1...21).map { index in
            ProfileSearchPerson(id: UUID(uuidString: String(format: "c0170000-0000-4000-8000-%012d", index))!,
                displayName: String(format: "검색 테스트 %02d", index), handle: "synthetic_\(index)", avatarPath: nil)
        }
        return after == nil ? Array(values.prefix(20)) : Array(values.suffix(1))
    }
}
#endif
