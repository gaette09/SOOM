import Charts
import Combine
import Foundation
import Supabase
import SwiftUI

/// Follow state is unknown until the account-scoped server read succeeds.
/// Never turn a missing schema/network failure into a false “not following”.
@MainActor
final class FeedFollowingStore: ObservableObject {
    static let didChange = Notification.Name("SOOM.feedFollowingDidChange")
    @Published private(set) var approvedStates: [UUID: ApprovedFollowReceipt]?
    @Published private(set) var followsViewer: Set<UUID>?
    @Published private(set) var following: Set<UUID>?
    @Published private(set) var errorMessage: String?
    @Published private(set) var busyIDs: Set<UUID> = []
    private var loadedViewer: UUID?
    private var loadRequestID = UUID()

    func load(ids: [UUID]) async {
        if ReviewDemoMode.isActive {
            loadedViewer = ReviewDemoMode.userID
            following = ReviewDemoCommunityStore.shared.following
            followsViewer = Set(ReviewDemoCommunityStore.shared.items.map(\.authorId)).subtracting([ReviewDemoMode.userID])
            errorMessage = nil
            return
        }
        let requestID = UUID()
        loadRequestID = requestID
        let generation = CommunitySafetyStore.shared.accountGeneration
        let revision = CommunitySafetyStore.shared.revision
        following = nil; followsViewer = nil; approvedStates = nil
        errorMessage = nil
        guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              let viewer = client.auth.currentSession?.user.id else { return }
        loadedViewer = viewer
        do {
            let privacy = SupabaseAccountPrivacyService(client: client)
            let approvedEnabled: Bool
            do { approvedEnabled = try await privacy.fetch().enabled }
            catch let error as PostgrestError where error.code == "PGRST202" && AccountActivityReadPolicy.deployed == .approvedFollowersV1 { approvedEnabled = false }
            var approved: [UUID: ApprovedFollowReceipt] = [:]
            var result = Set<UUID>()
            var incoming = Set<UUID>()
            let values = Array(Set(ids.filter { $0 != viewer }))
            for offset in stride(from: 0, to: values.count, by: 100) {
                let chunk = Array(values[offset..<min(offset + 100, values.count)])
                struct Params: Encodable { let p_ids: [UUID] }
                let rows: [RelationshipRow]
                if AccountActivityReadPolicy.deployed == .profileOnlyV2 { rows = [] }
                else { rows = try await client.rpc("soom_social_relationships", params: Params(p_ids: chunk)).execute().value }
                guard client.auth.currentSession?.user.id == viewer,
                      CommunitySafetyStore.shared.viewerID == viewer, loadedViewer == viewer, loadRequestID == requestID,
                      generation == CommunitySafetyStore.shared.accountGeneration, revision == CommunitySafetyStore.shared.revision, !Task.isCancelled else { return }
                if approvedEnabled {
                    let states = try await privacy.states(chunk)
                    for state in states { approved[state.userID] = state }
                    incoming.formUnion(states.filter { $0.policyVersion == 2 && $0.followsViewer == true }.map(\.userID))
                    result.formUnion(states.filter { $0.state == .accepted }.map(\.userID))
                } else { result.formUnion(rows.filter(\.isFollowing).map(\.userID)) }
                incoming.formUnion(rows.filter(\.followsViewer).map(\.userID))
            }
            guard client.auth.currentSession?.user.id == viewer,
                  CommunitySafetyStore.shared.viewerID == viewer, loadRequestID == requestID,
                  generation == CommunitySafetyStore.shared.accountGeneration, revision == CommunitySafetyStore.shared.revision, !Task.isCancelled else { return }
            following = result; followsViewer = incoming
            approvedStates = approvedEnabled ? approved : nil
        } catch {
            guard loadRequestID == requestID, generation == CommunitySafetyStore.shared.accountGeneration,
                  client.auth.currentSession?.user.id == viewer, !Task.isCancelled else { return }
            errorMessage = "팔로우 상태를 불러오지 못했어요."
        }
    }

    func toggle(_ userID: UUID) async {
        guard let following, let viewer = loadedViewer, viewer != userID,
              !CommunitySafetyStore.shared.isBlocked(userID), busyIDs.insert(userID).inserted else { return }
        defer { busyIDs.remove(userID) }
        let generation = CommunitySafetyStore.shared.accountGeneration
        CommunitySafetyStore.shared.invalidateRelationships()
        errorMessage = nil
        do {
            let confirmed: Bool
            let requested = approvedStates?[userID]?.policyVersion == 2 ? !following.contains(userID) : (approvedStates?[userID]?.state != .pending && !following.contains(userID))
            if ReviewDemoMode.isActive {
                confirmed = try await ReviewDemoCommunityStore.shared.setFollowing(requested, userID: userID)
            } else {
                guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
                      client.auth.currentSession?.user.id == viewer else { throw CommunitySafetyError.accountChanged }
                confirmed = try await SupabaseProfileSocialService(client: client).setFollowing(requested, userID: userID)
                guard client.auth.currentSession?.user.id == viewer else { throw CommunitySafetyError.accountChanged }
            }
            guard loadedViewer == viewer, CommunitySafetyStore.shared.viewerID == viewer,
                  generation == CommunitySafetyStore.shared.accountGeneration else { return }
            guard confirmed == requested else { throw FeedPostManagementError.changeNotConfirmed }
            CommunitySafetyStore.shared.invalidateRelationships()
            await load(ids: Array(following.union([userID])))
            NotificationCenter.default.post(name: Self.didChange, object: nil, userInfo: ["viewerID": viewer])
        } catch {
            guard loadedViewer == viewer, CommunitySafetyStore.shared.viewerID == viewer,
                  generation == CommunitySafetyStore.shared.accountGeneration else { return }
            CommunitySafetyStore.shared.invalidateRelationships()
            await load(ids: Array(following.union([userID])))
            errorMessage = "팔로우 변경을 확인하지 못했어요. 다시 시도해 주세요."
        }
    }

    func actionTitle(_ userID: UUID) -> String {
        if approvedStates?[userID]?.policyVersion == 2 { return following?.contains(userID) == true ? "팔로우해제" : "팔로우" }
        if approvedStates?[userID]?.state == .pending { return "요청 취소" }
        if following?.contains(userID) == true { return "팔로우해제" }
        if let scope = approvedStates?[userID]?.accountScope { return scope == "public" ? "팔로우" : "팔로우 요청" }
        return "팔로우"
    }
    func relationshipTitle(_ userID: UUID) -> String {
        if approvedStates?[userID]?.policyVersion == 2 { return following?.contains(userID) == true ? "팔로잉" : "팔로우" }
        if approvedStates?[userID]?.state == .pending { return "요청됨" }
        return following?.contains(userID) == true ? "팔로잉" : actionTitle(userID)
    }
    private struct RelationshipRow: Decodable {
        let userID: UUID; let isFollowing: Bool; let followsViewer: Bool
        enum CodingKeys: String, CodingKey { case userID = "user_id", isFollowing = "is_following", followsViewer = "follows_viewer" }
    }
    private struct FollowingRow: Decodable {
        let followedID: UUID
        enum CodingKeys: String, CodingKey { case followedID = "followed_id" }
    }
    private struct FollowInsert: Encodable {
        let followerID: UUID
        let followedID: UUID
        enum CodingKeys: String, CodingKey { case followerID = "follower_id", followedID = "followed_id" }
    }
}

/// Feed header entry only. Every mutation uses the same account-bound service;
/// unverified state never becomes an inferred follow or content permission.
struct FeedAuthorFollowControl: View {
    let userID: UUID
    let author: String
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @StateObject private var following = FeedFollowingStore()
    var body: some View {
        Group {
            if userID != safety.viewerID, safety.viewerID != nil {
                if following.following != nil {
                    Button(following.relationshipTitle(userID)) { Task { await following.toggle(userID) } }
                        .font(.caption.weight(.semibold)).foregroundStyle(SOOMColor.accent)
                        .frame(minWidth: 68, minHeight: 44)
                        .disabled(following.busyIDs.contains(userID))
                        .accessibilityLabel("\(author) \(following.actionTitle(userID))")
                        .accessibilityValue(following.relationshipTitle(userID))
                        .accessibilityIdentifier("feed.author.follow.\(userID)")
                } else if following.errorMessage != nil {
                    Button("다시 확인") { Task { await following.load(ids: [userID]) } }
                        .font(.caption).frame(minHeight: 44)
                        .accessibilityLabel("\(author) 팔로우 상태 다시 확인")
                } else { SOOMSkeleton(layout: .value, label: "팔로우 상태 확인 중").frame(width: 68, height: 44) }
            }
        }.task(id: "\(userID)-\(safety.accountGeneration)-\(safety.revision)") {
            guard safety.canUseSocial else { return }
            await following.load(ids: [userID])
        }
    }
}

struct FeedCheersSheet: View {
    let item: FeedItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @StateObject private var management: FeedPostManagement
    @StateObject private var following = FeedFollowingStore()
    @State private var profiles: [UUID: FeedProfileDTO] = [:]
    @State private var isLoading = true
    @State private var profileError: String?

    init(item: FeedItem) {
        self.item = item
        _management = StateObject(wrappedValue: FeedPostManagement(item: item, loadAllReactions: true))
    }

    private var cheers: [FeedReaction] {
        management.item.orderedCheers.filter { $0.authorId.map { !safety.isBlocked($0) } ?? false }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if isLoading && cheers.isEmpty { SOOMSkeleton(layout: .list, label: "화이팅한 사람 불러오는 중").padding(24) }
                    if management.hasLoaded && !management.isAvailable {
                        Text("이 게시물의 화이팅을 볼 수 없어요.").padding()
                    } else {
                        if let message = profileError ?? following.errorMessage {
                            Text(message).font(.caption).foregroundStyle(SOOMColor.secondaryInk).padding()
                            Button("다시 불러오기") { Task { await load() } }.padding(.horizontal)
                        }
                        if let followed = following.following {
                            peopleSection("팔로우 중", values: cheers.filter { $0.authorId.map { followed.contains($0) } ?? false })
                            peopleSection("다른 사용자", values: cheers.filter { reaction in !(reaction.authorId.map { followed.contains($0) } ?? false) })
                        } else { peopleSection("화이팅한 사람", values: cheers) }
                        if !isLoading && cheers.isEmpty { Text("아직 화이팅이 없어요.").padding() }
                    }
                }
            }
            .background(SOOMColor.background)
            .navigationTitle("화이팅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
            .task { await load() }
            .onReceive(NotificationCenter.default.publisher(for: FeedFollowingStore.didChange)) { note in
                guard note.userInfo?["viewerID"] as? UUID == safety.viewerID else { return }
                Task { await following.load(ids: cheers.compactMap(\.authorId)) }
            }
            .onChange(of: safety.accountGeneration) { _, _ in dismiss() }
            .soomProfileModalHandoff()
        }
    }
    @ViewBuilder private func peopleSection(_ title: String, values: [FeedReaction]) -> some View {
        if !values.isEmpty {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(SOOMColor.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(SOOMColor.surfaceMuted)
            ForEach(values) { reaction in
                if let userID = reaction.authorId {
                let profile = profiles[userID] ?? reaction.profile
                HStack(spacing: 12) {
                    SOOMProfileLink(userID: userID, profile: profile) {
                        HStack(spacing: 12) {
                            SOOMAvatarView(userID: userID, avatarPath: profile?.avatarPath, size: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile?.displayName ?? "SOOM 사용자").font(.body.weight(.semibold))
                                if let handle = profile?.handle, !handle.isEmpty {
                                    Text(handle.hasPrefix("@") ? handle : "@\(handle)").font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                                }
                            }
                            Spacer(minLength: 0)
                        }.foregroundStyle(SOOMColor.ink).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    followControl(userID)
                }.padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
    }
    @ViewBuilder private func followControl(_ userID: UUID) -> some View {
        if userID == safety.viewerID {
            Text("나").font(.caption).foregroundStyle(SOOMColor.secondaryInk)
        } else if let values = following.following {
            Button(following.relationshipTitle(userID)) { Task { await following.toggle(userID) } }
                .font(.caption.weight(.semibold)).foregroundStyle(SOOMColor.accent)
                .padding(.horizontal, 13).frame(minHeight: 44)
                .overlay(Capsule().stroke(SOOMColor.accent.opacity(0.5)))
                .disabled(following.busyIDs.contains(userID))
        }
    }
    @MainActor private func load() async {
        isLoading = true
        profileError = nil
        let generation = safety.accountGeneration
        await management.refresh()
        guard generation == safety.accountGeneration, management.isAvailable else { isLoading = false; return }
        let ids = cheers.compactMap(\.authorId)
        async let followRead: Void = following.load(ids: ids)
        do {
            if ReviewDemoMode.isActive {
                let rows = try await ReviewDemoCommunityStore.shared.fetchProfiles(ids: ids)
                profiles = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            } else if let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
               let viewer = client.auth.currentSession?.user.id {
                let rows = try await SupabaseFeedRemoteClient(client: client).fetchProfiles(ids: ids)
                guard generation == safety.accountGeneration, client.auth.currentSession?.user.id == viewer else { return }
                profiles = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            }
        } catch {
            if generation == safety.accountGeneration, !Task.isCancelled { profileError = "프로필을 불러오지 못했어요." }
        }
        await followRead
        if generation == safety.accountGeneration { isLoading = false }
    }
}

/// A real remote profile: identity and public activities only. It never uses
/// the viewing account's local workout store for another user's profile.
private struct FeedProfileGalleryDestination: Identifiable, Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id = UUID()
    let item: FeedItem
    let author: FeedProfileDTO?
    let viewerID: UUID
    let generation: Int
}

struct FeedPublicProfileView: View {
    let userID: UUID
    var initialProfile: FeedProfileDTO?
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var profileScene
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.soomProfileNavigationIsActive) private var navigationActive
    @State private var galleryDestination: FeedProfileGalleryDestination?
    @StateObject private var following = FeedFollowingStore()
    @State private var profile: FeedProfileDTO?
    @State private var posts: [FeedItem] = []
    @State private var isLoading = false
    @State private var loaded = false
    #if DEBUG && targetEnvironment(simulator)
    @State private var navigationProbeID = UUID()
    @State private var navigationLoadAttempts = 0
    #endif
    @State private var postRemote: SupabaseFeedRemoteClient?
    @State private var postRequestID = UUID()
    @State private var nextPostOffset = 0
    @State private var activityCursor: AccountActivityCursor?
    @State private var hasMore = true
    @State private var errorMessage: String?
    @State private var openingGeneration = CommunitySafetyStore.shared.accountGeneration

    @State private var selectedTab: ProfileSection = .progress
    @State private var galleryPhotos: [UUID: [WorkoutPhotoReference]] = [:]
    @State private var galleryVerifiedKey: String?
    @State private var galleryLoadedEpoch: String?
    @State private var galleryKnownRevisions: [UUID: Int64] = [:]
    @State private var galleryRequestID = UUID()
    @State private var galleryLoading = false
    @State private var galleryFailed = false
    @State private var galleryRetry = 0
    private var galleryEpoch: String {
        "\(selectedTab == .gallery):\(profileScene == .active):\(safety.accountGeneration):\(safety.revision):\(galleryRetry)"
    }
    private var galleryKey: String {
        galleryEpoch + ":" + posts.map { "\($0.id):\($0.activityProjection?.revision ?? 0)" }.joined(separator: ",")
    }
    private func galleryImages(_ item: FeedItem) -> [WorkoutPhotoReference] {
        guard let row = item.activityProjection else { return item.photos }
        return galleryLoadedEpoch == galleryEpoch && galleryKnownRevisions[item.id] == row.revision ? (galleryPhotos[item.id] ?? []) : []
    }

    init(userID: UUID, initialProfile: FeedProfileDTO? = nil, initialSection: ProfileSection = .progress) {
        self.userID = userID; self.initialProfile = initialProfile
        _selectedTab = State(initialValue: initialSection)
    }

    var body: some View {
        SocialAccessBoundary {
        SOOMScreen {
            if safety.isBlocked(userID) || openingGeneration != safety.accountGeneration {
                CommunityContentUnavailableView()
            } else if loaded && profile == nil {
                ContentUnavailableView("프로필을 볼 수 없어요", systemImage: "person.crop.circle")
            } else if !loaded && errorMessage == nil && profile == nil && initialProfile == nil {
                SOOMSkeleton(layout: .profile, label: "프로필 불러오는 중")
                SOOMSkeleton(layout: .feed, label: "공유 활동 불러오는 중")
            } else {
                profileHeader
                ProfileSocialStatsView(userID: userID, onPosts: { selectedTab = .activities }).id(userID)
                ProfileSectionTabs(selection: $selectedTab, activityTitle: "공유 게시물")
                if let errorMessage {
                    SOOMCard {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                        Button("다시 시도") { Task { await load() } }.frame(minHeight: 44)
                    }
                }
                if !loaded && posts.isEmpty {
                    if errorMessage == nil { SOOMSkeleton(layout: .feed, label: "공유 활동 불러오는 중") }
                } else {
                    switch selectedTab {
                    case .progress: publicProgress
                    case .activities: publicActivities
                    case .gallery: publicGallery
                    case .more: publicMore
                    }
                }
                if isLoading && loaded { ProgressView("운동 더 불러오는 중").frame(maxWidth: .infinity, minHeight: 44) }
                if hasMore && loaded && !isLoading && selectedTab != .more {
                    Button("운동 더 보기") { Task { await load() } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("profile.remote.loadMore")
                }
            }
        }
        .background(SOOMColor.background)
        .environment(\.soomCurrentProfileID, userID)
        .environment(\.soomFeedPhotoPresentationID, nil)
        .independentFeedReturnScope()
        .navigationTitle("프로필")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #if DEBUG && targetEnvironment(simulator)
        .overlay(alignment: .bottomTrailing) {
            if ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1" && safety.canUseSocial {
                Text("instance=\(navigationProbeID);loads=\(navigationLoadAttempts);tab=\(selectedTab);preview=\(safety.canUseActivityPreview)")
                    .font(.system(size: 10)).padding(.bottom, 120).accessibilityIdentifier("profile.navigation.probe.\(userID)")
                    .opacity(safety.canUseSocial ? 1 : 0).accessibilityHidden(!safety.canUseSocial)
            }
        }
        #endif
        .task { if !loaded { await load() } }
        .task(id: galleryKey) { await loadGalleryPhotos() }
        .onChange(of: profileScene) { _, phase in if phase == .active { galleryRetry += 1 } }
        .onDisappear {
            // A canceled first visit must not keep the next visit behind its busy flag.
            // Loaded pages remain intact; late responses lose ownership of this request.
            if isLoading { postRequestID = UUID(); isLoading = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: FeedFollowingStore.didChange)) { note in
            guard note.userInfo?["viewerID"] as? UUID == safety.viewerID else { return }
            invalidatePosts()
            Task { await load() }
        }
        .onChange(of: safety.accountGeneration) { _, _ in dismiss() }
        .feedCommentProfileNavigationHost()
        .onChange(of: safety.revision) { _, _ in
            invalidatePosts()
            if safety.isBlocked(userID) { profile = nil }
            else { Task { await load() } }
        }
    
        }
        // Page-owned route survives gallery row replacement and temporary checking.
        .navigationDestination(item: $galleryDestination) { target in
            SocialAccessBoundary {
                if target.viewerID == auth.session.currentUser?.id,
                   target.viewerID == safety.viewerID,
                   target.generation == safety.accountGeneration,
                   !safety.isBlocked(userID) {
                    if let row = target.item.activityProjection {
                        AccountActivitySummaryDetailDestination(row: row, author: target.author)
                            .environment(\.soomProfileOnlyDetailPresentation, row.readPolicy == .profileOnlyV2)
                    } else { FeedItemDetailDestination(item: target.item) }
                } else { CommunityContentUnavailableView() }
            }
            .environment(\.soomFeedPhotoPresentationID, nil)
            .independentFeedReturnScope()
        }
        .modifier(ProfileFinalDenialDismiss(onFinalDenied: { galleryDestination = nil }))
        .onChange(of: safety.accountGeneration) { _, _ in galleryDestination = nil }
        .onChange(of: auth.session.currentUser?.id) { _, _ in galleryDestination = nil }
        .onChange(of: safety.isBlocked(userID)) { _, blocked in if blocked { galleryDestination = nil } }
    }

    private func openGalleryDetail(_ item: FeedItem) {
        guard galleryDestination == nil, profileScene == .active, navigationActive,
              safety.canUseSocial, !safety.isBlocked(userID),
              openingGeneration == safety.accountGeneration,
              let viewerID = safety.viewerID, auth.session.currentUser?.id == viewerID,
              posts.contains(where: { $0 == item }) else { return }
        // Only this row's authority matters. Other pages may still be loading or fail.
        if let row = item.activityProjection {
            guard galleryLoadedEpoch == galleryEpoch,
                  galleryKnownRevisions[item.id] == row.revision,
                  !galleryImages(item).isEmpty else { return }
        } else {
            guard !item.photos.isEmpty else { return }
        }
        galleryDestination = .init(item: item, author: profile, viewerID: viewerID,
                                   generation: safety.accountGeneration)
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfilePublicIdentityHeader(
                userID: userID,
                avatarPath: (profile ?? initialProfile)?.avatarPath,
                displayName: (profile ?? initialProfile)?.displayName ?? "SOOM 사용자",
                handle: (profile ?? initialProfile)?.handle,
                subtitle: nil,
                workoutCountLabel: loaded ? "불러온 운동 \(posts.count)개" : (errorMessage == nil ? "운동 불러오는 중" : "운동 확인 필요")
            )
            if userID != safety.viewerID, following.following != nil {
                Button(following.relationshipTitle(userID)) { Task { await following.toggle(userID) } }
                    .font(.subheadline.weight(.semibold)).frame(minWidth: 110, minHeight: 44)
                    .foregroundStyle(SOOMColor.accent).background(SOOMColor.accent.opacity(0.1), in: Capsule())
                    .disabled(following.busyIDs.contains(userID))
            }
            if let error = following.errorMessage {
                Text(error).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            }
        }
        .padding(.vertical, 8)
    }

    private var publicProgress: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            ProfileWorkoutSummaryCard(metrics: [
                ProfileSummaryMetric(title: "운동", value: "\(posts.count)회"),
                ProfileSummaryMetric(title: "거리", value: String(format: "%.1f km", posts.compactMap(\.workoutDistanceMeters).reduce(0, +) / 1_000)),
                ProfileSummaryMetric(title: "시간", value: "\(Int(posts.compactMap(\.workoutDurationSeconds).reduce(0, +) / 60))분")
            ], footnote: hasMore ? "최근 불러온 \(posts.count)개 운동 기준 · 전체 기록 합계가 아니에요" : "현재 계정으로 볼 수 있는 운동 기준")
            SOOMCard {
                Text("운동 성향").font(.headline)
                Text(favoriteSport).font(.title3.weight(.semibold))
                Text(hasMore ? "불러온 운동의 최근 12주 거리" : "최근 12주 운동 거리").font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                Chart {
                    ForEach(publicWeeklyDistances, id: \.week) { point in
                        AreaMark(x: .value("주", point.week), y: .value("거리", point.distance))
                            .foregroundStyle(SOOMColor.accent.opacity(0.13))
                        LineMark(x: .value("주", point.week), y: .value("거리", point.distance))
                            .foregroundStyle(SOOMColor.accent)
                    }
                }
                .frame(height: 170)
                .chartYAxisLabel("km")
            }
        }
    }

    private var publicActivities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("공유한 게시물").font(.title2.weight(.bold))
                .accessibilityIdentifier("profile.sharedPosts.title")
            Text("현재 계정으로 볼 수 있는 이 사용자의 게시물만 표시해요. 개인 운동 보관함과는 별도예요.").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            if loaded && posts.isEmpty && errorMessage == nil {
                SOOMCard { Text("접근 가능한 운동이 아직 없어요.").foregroundStyle(SOOMColor.secondaryInk) }
            }
            ForEach(posts) { item in
                if let row = item.activityProjection {
                    AccountActivitySummaryCard(row: row, currentProfileID: userID)
                        .environment(\.soomFeedIsActive, true)
                        .environment(\.soomActivityPreview, false)
                        .accessibilityIdentifier("profile.sharedPost.\(item.id)")
                } else {
                NavigationLink { FeedItemDetailDestination(item: item) } label: {
                    SOOMCard {
                        Text(item.recordTitle).font(.headline).foregroundStyle(SOOMColor.ink)
                        Label(item.visibility.title, systemImage: "person.2").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                        HStack(spacing: 8) {
                            SOOMSportIconView(name: item.recordSportIcon, size: 18)
                            Text((item.activityDate ?? item.createdAt).formatted(date: .abbreviated, time: .shortened))
                            Spacer(minLength: 0)
                            Text(FeedCardFormatting.distance(item.workoutDistanceMeters, sport: item.recordWorkoutType))
                        }.font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("profile.sharedPost.\(item.id)")
                }
            }
        }
    }

    private var publicGallery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("운동 사진").font(.title2.weight(.bold))
            let withPhotos = posts.filter { !galleryImages($0).isEmpty }
            if galleryLoading || (posts.contains { $0.activityProjection?.readPolicy == .profileOnlyV2 } && galleryVerifiedKey != galleryKey) {
                SOOMSkeleton(layout: .photo, label: "프로필 운동 사진 확인 중").frame(height: 160)
            } else if galleryFailed {
                SOOMCard {
                    Text("일부 운동 사진을 불러오지 못했어요.").foregroundStyle(SOOMColor.secondaryInk)
                    Button("사진 다시 확인") { galleryRetry += 1 }.frame(minHeight: 44)
                }
            } else if withPhotos.isEmpty {
                SOOMCard { Text(hasMore ? "불러온 운동에서 표시할 수 있는 사진이 없어요. 운동을 더 불러와 확인할 수 있어요." : "현재 표시할 수 있는 운동 사진이 없어요.").foregroundStyle(SOOMColor.secondaryInk) }
            }
            ForEach(withPhotos) { item in
                Button { openGalleryDetail(item) } label: {
                    SOOMCard {
                        Text(item.recordTitle).font(.headline).foregroundStyle(SOOMColor.ink)
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(galleryImages(item)) { photo in
                                    WorkoutPhotoImage(photo: photo)
                                        .frame(width: 160, height: 160).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("profile.gallery.item.\(item.id)")
            }
        }
    }

    @MainActor private func loadGalleryPhotos() async {
        let expected = galleryKey, epoch = galleryEpoch, request = UUID()
        galleryRequestID = request
        if galleryLoadedEpoch != epoch {
            galleryPhotos = [:]; galleryKnownRevisions = [:]; galleryLoadedEpoch = epoch
        }
        galleryVerifiedKey = nil; galleryFailed = false; galleryLoading = false
        guard selectedTab == .gallery, profileScene == .active, safety.canUseSocial,
              openingGeneration == safety.accountGeneration, !safety.isBlocked(userID) else { return }
        galleryLoading = true
        defer { if galleryKey == expected, galleryRequestID == request { galleryLoading = false } }
        var failed = false
        let rows = posts.compactMap { item -> (UUID, AccountActivityFeedRow)? in
            guard let row = item.activityProjection, row.readPolicy == .profileOnlyV2,
                  galleryKnownRevisions[item.id] != row.revision else { return nil }
            return (item.id, row)
        }
        let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient()
        for (id, row) in rows {
            guard !Task.isCancelled, galleryKey == expected, galleryRequestID == request else { return }
            do {
                let photos: [WorkoutPhotoReference]
                #if DEBUG && targetEnvironment(simulator)
                if ReviewDemoMode.isActive {
                    photos = try await ReviewDemoPhotoStore.shared.seedProfilePhotoFixture(row: row,
                        context: .init(viewerID: safety.viewerID, generation: safety.accountGeneration,
                            safetyRevision: safety.revision, storageScopeID: ReviewDemoMode.userID.uuidString.lowercased()))
                } else { photos = try await readGalleryPhotos(row, client: client) }
                #else
                photos = try await readGalleryPhotos(row, client: client)
                #endif
                guard !Task.isCancelled, galleryKey == expected, galleryRequestID == request else { return }
                galleryPhotos[id] = photos; galleryKnownRevisions[id] = row.revision
            } catch { failed = true }
        }
        guard !Task.isCancelled, galleryKey == expected, galleryRequestID == request,
              openingGeneration == safety.accountGeneration else { return }
        galleryFailed = failed; galleryVerifiedKey = expected
    }
    @MainActor private func readGalleryPhotos(_ row: AccountActivityFeedRow, client: SupabaseClient?) async throws -> [WorkoutPhotoReference] {
        guard let client, let viewer = client.auth.currentSession?.user.id, viewer == safety.viewerID else {
            throw AccountActivityInteractionError.accountChanged
        }
        return try await AccountActivityProfilePhotoAdapter(client: client, context: {
            .init(viewerID: safety.canUseSocial && profileScene == .active ? client.auth.currentSession?.user.id : nil,
                generation: safety.accountGeneration, safetyRevision: safety.revision,
                storageScopeID: viewer.uuidString.lowercased())
        }).load(row: row)
    }

    private var publicMore: some View {
        SOOMCard {
            Text("운동 기록").font(.headline)
            Text("현재 계정으로 볼 수 있는 이 사용자의 운동만 표시됩니다.")
                .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            Button("활동 보기") { selectedTab = .activities }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var favoriteSport: String {
        let groups = Dictionary(grouping: posts, by: \.recordSport)
        return groups.max(by: { $0.value.count < $1.value.count })?.key ?? "아직 볼 수 있는 운동이 없어요"
    }

    private var publicWeeklyDistances: [(week: Date, distance: Double)] {
        let calendar = Calendar.current
        guard let current = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<12).reversed().compactMap { offset in
            guard let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: current),
                  let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { return nil }
            let distance = posts.filter {
                let date = $0.activityDate ?? $0.createdAt
                return date >= week && date < next
            }.compactMap(\.workoutDistanceMeters).reduce(0, +) / 1_000
            return (week: week, distance: distance)
        }
    }

    @MainActor private func invalidatePosts() {
        postRequestID = UUID(); posts = []; loaded = false; hasMore = true
        postRemote = nil; nextPostOffset = 0; activityCursor = nil; isLoading = false; errorMessage = nil
    }

    @MainActor private func load() async {
        guard !isLoading, !safety.isBlocked(userID), openingGeneration == safety.accountGeneration,
              !loaded || hasMore else { return }
        #if DEBUG && targetEnvironment(simulator)
        navigationLoadAttempts += 1
        #endif
        let token = postRequestID
        let revision = safety.revision
        isLoading = true
        errorMessage = nil
        defer { if token == postRequestID { isLoading = false } }
        if ReviewDemoMode.isActive {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["SOOM_REMOTE_PROFILE_LOADING_QA"] == "1" {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, token == postRequestID, revision == safety.revision,
                      openingGeneration == safety.accountGeneration else { return }
            }
            #endif
            let demo = ReviewDemoCommunityStore.shared
            profile = demo.profile(userID)
            let authorized = try? await demo.fetchFeedPage(limit: 500, offset: 0, audience: .all)
            guard !Task.isCancelled, token == postRequestID, revision == safety.revision,
                  openingGeneration == safety.accountGeneration, !safety.isBlocked(userID) else { return }
            let scoped = (authorized ?? []).filter { $0.authorId == userID && ($0.visibility == .publicFeed || userID == safety.viewerID) }
            let page = Array(scoped.dropFirst(nextPostOffset).prefix(8))
            await following.load(ids: [userID])
            guard !Task.isCancelled, token == postRequestID, revision == safety.revision,
                  openingGeneration == safety.accountGeneration else { return }
            var ids = Set(posts.map(\.id)); posts += page.filter { ids.insert($0.id).inserted }
            nextPostOffset += page.count
            loaded = true; hasMore = nextPostOffset < scoped.count; isLoading = false
            return
        }
        guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              let viewer = client.auth.currentSession?.user.id else {
            errorMessage = "프로필을 불러오지 못했어요. 로그인 상태를 확인해 주세요."
            return
        }
        do {
            let remote = postRemote ?? SupabaseFeedRemoteClient(client: client)
            postRemote = remote
            if !loaded {
                let profiles = try await remote.fetchProfiles(ids: [userID])
                guard token == postRequestID, revision == safety.revision,
                      openingGeneration == safety.accountGeneration, client.auth.currentSession?.user.id == viewer else { return }
                profile = profiles.first { $0.id == userID }
                await following.load(ids: [userID])
            }
            guard token == postRequestID, revision == safety.revision else { return }
            guard profile != nil else { loaded = true; hasMore = false; return }
            let items: [FeedItem]
            let nextActivityCursor: AccountActivityCursor?
            let pageHasMore: Bool
            if AccountActivityReadPolicy.deployed == .profileOnlyV2 {
                guard nextPostOffset == 0 || activityCursor != nil else { throw AccountActivityContractError.invalidRequest }
                let repository = SupabaseFeedRepository(clientProvider: SupabaseClientProvider(environment: AuthEnvironmentLoader().load()),
                    remoteFetcher: remote, profileFetcher: remote)
                let transport = SupabaseAccountActivityFeedTransport(client: client, legacyRepository: repository, readPolicy: .profileOnlyV2)
                let page = try await AccountActivityFeedAdapter(transport: transport).load(.init(viewerID: viewer,
                    scope: .profile, ownerID: userID, before: activityCursor, limit: 8))
                items = page.displayItems(); nextActivityCursor = page.nextCursor; pageHasMore = page.hasMore
            } else {
                let bundles = try await remote.fetchPublicProfilePosts(authorID: userID, viewerID: viewer, offset: nextPostOffset, limit: 8)
                items = bundles.map { $0.makeFeedItem(authorName: profile?.displayName ?? "SOOM 사용자", authorHandle: profile?.handle,
                    avatarPath: profile?.avatarPath, currentUserId: viewer) }
                nextActivityCursor = nil; pageHasMore = bundles.count == 8
            }
            guard !Task.isCancelled, token == postRequestID, revision == safety.revision, openingGeneration == safety.accountGeneration,
                  client.auth.currentSession?.user.id == viewer, !safety.isBlocked(userID) else { return }
            var ids = Set(posts.map(\.id))
            posts.append(contentsOf: items.filter { ids.insert($0.id).inserted })
            nextPostOffset += items.count
            activityCursor = nextActivityCursor
            hasMore = pageHasMore
            loaded = true
        } catch {
            if token == postRequestID, revision == safety.revision,
               openingGeneration == safety.accountGeneration, client.auth.currentSession?.user.id == viewer, !Task.isCancelled {
                errorMessage = "프로필을 불러오지 못했어요. 다시 시도해 주세요."
            }
        }
    }
}


// Observing the model (not an unobserved Environment reference) distinguishes
// in-progress same-account verification from final denial without any TTL.
struct ProfileFinalDenialDismiss: ViewModifier {
    var onFinalDenied: (() -> Void)? = nil
    @Environment(\.soomAccountPrivacyModel) private var model
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @ViewBuilder func body(content: Content) -> some View {
        if let model { content.modifier(ProfileObservedDenialDismiss(onFinalDenied: onFinalDenied, model: model)) }
        else { content.onChange(of: safety.canUseSocial) { _, allowed in if !allowed { if let onFinalDenied { onFinalDenied() } else { dismiss() } } } }
    }
}
private struct ProfileObservedDenialDismiss: ViewModifier {
    var onFinalDenied: (() -> Void)? = nil
    @ObservedObject var model: AccountPrivacyModel
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.dismiss) private var dismiss
    private var finalDenied: Bool { !model.isCheckingSocialAccess && !safety.canUseSocial }
    func body(content: Content) -> some View {
        content.onChange(of: finalDenied) { _, denied in if denied { if let onFinalDenied { onFinalDenied() } else { dismiss() } } }
    }
}
