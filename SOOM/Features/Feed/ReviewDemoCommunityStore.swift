import Foundation
import SwiftData

/// An explicitly selected demonstration session. It never uses a network client.
@MainActor
final class ReviewDemoCommunityStore: FeedRepositoryProtocol, FeedRemoteReactionPosting,
    FeedRemoteBookmarkPosting, FeedRemoteCommentPosting, FeedRemotePostDeleting,
    FeedRemotePostPosting, FeedRemoteProfileFetching, NotificationInboxFetching,
    CommunitySafetyServicing, FeedPostRemoteManaging, ClubWorkoutFeedRemote {
    static let shared = ReviewDemoCommunityStore()
    private(set) var items: [FeedItem] = []
    private(set) var following = Set<UUID>()
    private var blocked: [CommunityBlockedUser] = []
    private(set) var reportReceipts: [UUID] = []
    #if DEBUG
    private var qaDeniedPosts = Set<UUID>()
    private var qaDeepRows: [AccountActivityFeedRow] = []
    private var qaUnverifiedClubs = Set<UUID>()
    func denyPostForLocalQA(_ id: UUID) {
        guard ReviewDemoMode.isActive else { return }
        qaDeniedPosts.insert(id)
    }
    #endif
    private func localAccessAllowed(_ id: UUID) -> Bool {
        #if DEBUG
        return !qaDeniedPosts.contains(id)
        #else
        return true
        #endif
    }
    private var notificationsRead = false
    private var notificationHidden = false
    private var clubIDs: [String: UUID] = [:]
    private(set) var clubs = InMemoryClubService(details: InMemoryClubService.seedDetails)
    private let companionID = UUID(uuidString: "D3100000-0000-4000-8000-000000000001")!
    private let secondCompanionID = UUID(uuidString: "D3100000-0000-4000-8000-000000000002")!
    var sessionUserID: UUID? { ReviewDemoMode.isActive ? ReviewDemoMode.userID : nil }

    init() { reset() }

    func reset() {
        #if DEBUG
        qaDeniedPosts = []; qaUnverifiedClubs = []; qaDeepRows = []
        #endif
        following = []; blocked = []; reportReceipts = []; notificationsRead = false; notificationHidden=false; clubIDs = [:]
        clubs = InMemoryClubService(details: InMemoryClubService.seedDetails)
        let now = Date()
        let authors = [ReviewDemoMode.userID, companionID, secondCompanionID]
        let names = ["SOOM Demo", "민서 · Demo", "도윤 · Demo"]
        items = FeedMockData.items.enumerated().map { index, item in
            var value = copy(item, authorID: authors[index % authors.count], authorName: names[index % names.count],
                visibility: .publicFeed, createdAt: now.addingTimeInterval(-Double(index + 1) * 3600))
            value.activityDate = value.createdAt
            value.workoutDistanceMeters = index == 2 ? 24_800 : 10_400
            value.workoutDurationSeconds = index == 2 ? 4_320 : 3_120
            value.reactions = [FeedReaction(symbol: "👏", label: "화이팅", authorId: companionID,
                createdAt: now.addingTimeInterval(-1200), profile: profile(companionID))]
            value.comments = [FeedComment(id: UUID(), authorId: companionID, body: "좋은 리듬이에요! 함께 응원해요.",
                createdAt: now.addingTimeInterval(-600), isViewerAuthor: false, profile: profile(companionID))]
            if index == 2 {
                var post = FeedPostDTO(id: value.id, userId: value.authorId, sport: .cycling,
                    title: value.recordTitle, body: value.caption, distanceMeters: 24800, durationSeconds: 4320,
                    visibility: .publicPost, createdAt: value.createdAt)
                post.sharedDetailRevision = 1; post.audienceContract = 1
                var input = WorkoutSharedDetailInput(durationSeconds: 4320, distanceMeters: 24800)
                input.route = (0...200).map { i in
                    .init(latitude: 37.552 + 0.003 * sin(Double(i) / 35), longitude: 126.94 + Double(i) * 0.00012,
                        seconds: Double(i) * 21.6, altitude: 20 + Double(i % 30), segment: 0)
                }
                for i in 0...120 {
                    let elapsed = Double(i) * 36.0
                    let meters = Double(i) * 24800.0 / 120.0
                    let heart = 125.0 + Double(i % 35)
                    let cadence = 75.0 + Double(i % 12)
                    let power = 120.0 + Double(i % 70)
                    let speed = 5.0 + Double(i % 4) / 2.0
                    input.samples.append(WorkoutSharedDetailInput.Sample(seconds: elapsed, distanceMeters: meters,
                        heartRateBPM: heart, cadencePerMinute: cadence, powerWatts: power,
                        speedMetersPerSecond: speed, elevationMeters: 20.0 + Double(i % 30), cadenceUnit: .revolutionsPerMinute))
                }
                value.sharedDetail = WorkoutSharedDetailSnapshot(postID: value.id, revision: 1, payload: input.masked())
                value.sharedDetailContractEnabled = true; value.serverPostSnapshot = post
            }
            return value
        }
        #if DEBUG && targetEnvironment(simulator)
        Feed60PaginationDemo.reset()
        Feed61MixedReuseDemo.reset()
        configureUXPostScopeFixture()
        if ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
           ProcessInfo.processInfo.environment["SOOM_NOTIFICATION_CARD_QA"] == "1", let base = items.first {
            for index in 0..<10 {
                let id = UUID(uuidString: String(format: "D3600000-0000-4000-8000-%012d", index + 1))!
                let title = index == 9 ? "알림 대상 운동" : "앞선 합성 운동"
                let card = copy(base, id: id, title: title)
                var value = FeedItem(id: id, authorName: base.authorName, authorHandle: nil,
                    authorId: base.authorId, createdAt: now.addingTimeInterval(-Double(index + 20) * 3600),
                    itemType: .workoutSession, visibility: .publicFeed, cardData: card.cardData,
                    caption: nil, activityContext: title, comments: base.comments)
                value.activityDate = value.createdAt
                items.append(value)
            }
        }
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private func configureUXPostScopeFixture() {
        guard ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
              let value = ProcessInfo.processInfo.environment["SOOM_UX_POST_COUNT"],
              let count = Int(value), [0, 9].contains(count),
              let base = items.first(where: { $0.authorId == ReviewDemoMode.userID }) else { return }
        items.removeAll { $0.authorId == ReviewDemoMode.userID }
        for index in 0..<count {
            items.append(copy(base, id: UUID(), title: "QA 공유 운동 \(index + 1)"))
        }
    }
    #endif

    private func requireActive(_ userID: UUID? = nil) throws {
        guard ReviewDemoMode.isActive, userID == nil || userID == ReviewDemoMode.userID else {
            throw CommunitySafetyError.accountChanged
        }
    }
    private func index(_ id: UUID) throws -> Int {
        try requireActive()
        guard localAccessAllowed(id), let index = items.firstIndex(where: { $0.id == id }),
              !blocked.contains(where: { $0.id == items[index].authorId }) else {
            throw FeedPostManagementError.contentUnavailable
        }
        return index
    }
    private func ownedIndex(_ id: UUID, ownerID: UUID) throws -> Int {
        try requireActive(ownerID)
        let i = try index(id)
        guard items[i].authorId == ownerID else { throw CommunitySafetyError.invalidTarget }
        return i
    }
    func profile(_ id: UUID) -> FeedProfileDTO {
        FeedProfileDTO(id: id, displayName: id == ReviewDemoMode.userID ? "SOOM Demo" : id == companionID ? "민서 · Demo" : "도윤 · Demo",
            handle: id == ReviewDemoMode.userID ? "@soom_demo" : id == companionID ? "@demo_minseo" : "@demo_doyun",
            avatarPath: id == ReviewDemoMode.userID ? ReviewDemoAvatarStore.shared.currentPath : nil)
    }
    func fetchFeed(limit: Int) async throws -> [FeedItem] { try await fetchFeedPage(limit: limit, offset: 0) }
    func fetchFeedPage(limit: Int, offset: Int) async throws -> [FeedItem] {
        try requireActive()
        return Array(items.filter { item in
            localAccessAllowed(item.id) && (item.visibility == .publicFeed || item.authorId == ReviewDemoMode.userID)
            && !blocked.contains(where: { $0.id == item.authorId }) }.dropFirst(max(0, offset)).prefix(max(0, limit)))
    }
    func fetchFeedPage(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedItem] {
        var visible = try await fetchFeedPage(limit: 500, offset: 0).filter {
            audience == .all || following.contains($0.authorId) || (audience == .home && $0.authorId == ReviewDemoMode.userID)
        }
        #if DEBUG && targetEnvironment(simulator)
        if Feed61MixedReuseDemo.enabled, audience == .home {
            return try Feed61MixedReuseDemo.page(limit: limit, offset: offset, owner: companionID)
        }
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_FEED_PAGINATION_QA"] == "1", audience == .home {
            return try await Feed60PaginationDemo.page(limit: limit, offset: offset, owner: companionID)
        }
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_QA"] == "1", audience == .home {
            // Match the production v2 repository: a stable, foreign-owned
            // projection-only remote page, before any local content merging.
            let row = AccountActivityFeedRow(cardID: UUID(uuidString: "A9110000-0000-4000-8000-000000000777")!,
                canonicalID: UUID(uuidString: "A9120000-0000-4000-8000-000000000777")!, ownerID: companionID,
                sport: "running", activityAt: "2026-01-01T00:00:00Z", durationSeconds: 1800,
                distanceMeters: 5000, revision: 1, readPolicy: .profileOnlyV2)
            let page = AccountActivityHydratedPage(cards: [.init(projection: row, legacyItem: nil)], nextCursor: nil, hasMore: false)
            return Array(page.displayItems().dropFirst(max(0, offset)).prefix(max(0, limit)))
        }
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_QA"] == "1" {
            if qaDeepRows.isEmpty {
                let anchor = Date().addingTimeInterval(-60)
                var ownRecords: [UnifiedWorkoutRecord] = []
                if ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_OWN_QA"] == "1",
                   let storage = ReviewDemoController.shared.runtime?.storage,
                   HealthCloudJournal.accountID(for: storage.container.mainContext) == ReviewDemoMode.userID {
                    ownRecords = (try? storage.container.mainContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>(sortBy: [SortDescriptor(\UnifiedWorkoutRecord.startDate, order: .reverse)]))) ?? []
                    if ProcessInfo.processInfo.environment["SOOM_PROJECTION_RECONCILE_QA"] == "1" {
                        for record in ownRecords { record.sharingVisibilityRaw = FeedPostVisibility.publicPost.rawValue }
                        try? storage.container.mainContext.save()
                    }
                }
                qaDeepRows = (0..<238).map { index in
                    let id = UUID(uuidString: String(format: "A9540000-0000-4000-8000-%012d", index + 1000))!
                    if index < ownRecords.count {
                        let workout = UnifiedWorkoutPersistenceMapper().makeWorkout(from: ownRecords[index])
                        return .init(cardID: id, canonicalID: workout.id, ownerID: ReviewDemoMode.userID,
                            sport: workout.workoutType.rawValue, activityAt: ISO8601DateFormatter().string(from: workout.startDate),
                            durationSeconds: Int(workout.durationSeconds), distanceMeters: workout.distanceMeters, revision: 1)
                    }
                    return .init(cardID: id, canonicalID: UUID(uuidString: String(format: "A9550000-0000-4000-8000-%012d", index + 1000))!,
                        ownerID: companionID, sport: "running", activityAt: ISO8601DateFormatter().string(from: anchor.addingTimeInterval(-Double(index + (ownRecords.isEmpty ? 0 : 40)) * 86400)),
                        durationSeconds: 1800, distanceMeters: 5000, revision: 1)
                }
            }
            let page = AccountActivityHydratedPage(cards: qaDeepRows.map { .init(projection: $0, legacyItem: nil) }, nextCursor: nil, hasMore: false)
            return Array(page.displayItems().dropFirst(max(0, offset)).prefix(max(0, limit)))
        }
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_PROJECTION_SUMMARY_QA"] == "1" {
            var row = AccountActivityFeedRow(cardID: UUID(uuidString: "A9110000-0000-4000-8000-000000000777")!, canonicalID: UUID(),
                ownerID: ReviewDemoMode.userID, sport: "running", activityAt: ISO8601DateFormatter().string(from: Date()),
                durationSeconds: 1800, distanceMeters: 5000, revision: 1)
            if ProcessInfo.processInfo.environment["SOOM_PROJECTION_OWN_PARITY_QA"] == "1",
               let context = ReviewDemoController.shared.runtime?.storage.container.mainContext {
                var query = FetchDescriptor<UnifiedWorkoutRecord>(sortBy: [SortDescriptor(\UnifiedWorkoutRecord.startDate, order: .reverse)])
                query.fetchLimit = 1
                if let record = try? context.fetch(query).first {
                    let workout = UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)
                    row = .init(cardID: row.cardID, canonicalID: workout.id, ownerID: ReviewDemoMode.userID,
                        sport: workout.workoutType.rawValue, activityAt: ISO8601DateFormatter().string(from: workout.startDate),
                        durationSeconds: Int(workout.durationSeconds), distanceMeters: workout.distanceMeters, revision: 1)
                }
            }
            if ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_QA"] == "1" {
                // Re-fetching the same synthetic card from a profile must retain its real identity.
                row = .init(cardID: row.cardID, canonicalID: UUID(uuidString: "A9580000-0000-4000-8000-000000000777")!,
                    ownerID: row.ownerID, sport: row.sport, activityAt: row.activityAt,
                    durationSeconds: row.durationSeconds, distanceMeters: row.distanceMeters,
                    revision: row.revision, readPolicy: .profileOnlyV2)
            }
            if ProcessInfo.processInfo.environment["SOOM_PROFILE_PHOTO_QA"] == "1" || ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_QA"] == "1" { row.readPolicy = .profileOnlyV2 }
            var rows = [row]
            if ProcessInfo.processInfo.environment["SOOM_PROJECTION_LOADING_QA"] == "1" {
                rows += (778...780).map { value in
                    AccountActivityFeedRow(cardID: UUID(uuidString: "A9110000-0000-4000-8000-000000000\(value)")!,
                        canonicalID: UUID(uuidString: "A9120000-0000-4000-8000-000000000\(value)")!,
                        ownerID: ReviewDemoMode.userID, sport: "running", activityAt: ISO8601DateFormatter().string(from: (row.cursor?.activityAt ?? Date()).addingTimeInterval(-Double(value - 777) * 3600)),
                        durationSeconds: 1800, distanceMeters: 5000, revision: 1)
                }
            }
            visible.insert(contentsOf: AccountActivityHydratedPage(cards: rows.map { .init(projection: $0, legacyItem: nil) }, nextCursor: rows.last?.cursor, hasMore: false).displayItems(), at: 0)
        }
        #endif
        return Array(visible.dropFirst(max(0, offset)).prefix(max(0, limit)))
    }
    func fetchSavedPosts() async throws -> [FeedItem] {
        try requireActive()
        return items.filter { item in localAccessAllowed(item.id) && item.viewerHasSaved && !blocked.contains(where: { $0.id == item.authorId }) }
    }
    func fetchPost(id: UUID) async throws -> FeedItem? {
        try requireActive()
        guard localAccessAllowed(id), let item = items.first(where: { $0.id == id }), !blocked.contains(where: { $0.id == item.authorId }) else { return nil }
        return item
    }
    func addReaction(postId: UUID, reactionType: String) async throws {
        let i = try index(postId)
        guard !items[i].viewerHasCheered else { return }
        items[i].viewerHasCheered = true
        items[i].reactions.append(FeedReaction(symbol: "👏", label: "화이팅", authorId: ReviewDemoMode.userID,
            createdAt: Date(), profile: profile(ReviewDemoMode.userID)))
    }
    func removeReaction(postId: UUID, reactionType: String) async throws {
        let i = try index(postId)
        items[i].viewerHasCheered = false
        items[i].reactions.removeAll { $0.authorId == ReviewDemoMode.userID }
    }
    func addBookmark(postId: UUID) async throws { items[try index(postId)].viewerHasSaved = true }
    func removeBookmark(postId: UUID) async throws { items[try index(postId)].viewerHasSaved = false }
    func addComment(postId: UUID, body: String) async throws {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { throw CommunitySafetyError.invalidDetails }
        let i = try index(postId)
        items[i].comments.append(FeedComment(id: UUID(), authorId: ReviewDemoMode.userID, body: text,
            createdAt: Date(), isViewerAuthor: true, profile: profile(ReviewDemoMode.userID)))
    }
    func addReply(postId: UUID, body: String, parent: FeedComment) async throws {
        let i = try index(postId)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500,
              items[i].comments.contains(where: { $0.id == parent.id }) else { throw CommunitySafetyError.invalidDetails }
        let rootID = parent.parentCommentID ?? parent.id
        items[i].comments.append(FeedComment(id: UUID(), authorId: ReviewDemoMode.userID, body: text,
            createdAt: Date(), isViewerAuthor: true, profile: profile(ReviewDemoMode.userID), parentCommentID: rootID))
    }
    func deleteComment(postId: UUID, commentID: UUID) async throws {
        let i = try index(postId)
        guard let comment = items[i].comments.first(where: { $0.id == commentID }),
              comment.authorId == ReviewDemoMode.userID else {
            throw FeedPostManagementError.contentUnavailable
        }
        items[i].comments.removeAll { $0.id == commentID }
    }
    func deletePost(id: UUID) async throws { items.remove(at: try ownedIndex(id, ownerID: ReviewDemoMode.userID)) }
    func postPublicPost(_ draft: FeedShareDraft, visibility: FeedPostVisibility) async throws {
        try requireActive()
        if let index = items.firstIndex(where: { $0.sourceWorkoutId == draft.sourceWorkoutId && $0.authorId == ReviewDemoMode.userID }) {
            items[index] = copy(items[index], visibility: visibility.shareableVisibility, title: draft.title, caption: draft.body)
        } else {
            let photos = try await ReviewDemoPhotoStore.shared.load(workoutID: draft.sourceWorkoutId, ownerID: ReviewDemoMode.userID)
            try requireActive()
            var item = copy(draft.makeFeedItem(), authorID: ReviewDemoMode.userID, authorName: "SOOM Demo", visibility: visibility.shareableVisibility, photos: photos)
            item.workoutDistanceMeters = draft.distanceMeters
            item.workoutDurationSeconds = draft.durationSeconds
            items.insert(item, at: 0)
        }
        NotificationCenter.default.post(name: FeedPostManagement.didChange, object: ReviewDemoMode.userID)
    }
    func updatePostVisibility(sourceWorkoutId: UUID, visibility: FeedPostVisibility) async throws {
        try requireActive()
        guard let item = items.first(where: { $0.sourceWorkoutId == sourceWorkoutId }) else { return }
        try await setVisibility(postID: item.id, ownerID: ReviewDemoMode.userID, visibility: visibility)
    }
    func fetchProfiles(ids: [UUID]) async throws -> [FeedProfileDTO] { try requireActive(); return Array(Set(ids)).map(profile) }
    func fetchNotifications() async throws -> [NotificationDTO] {
        try requireActive()
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
           ProcessInfo.processInfo.environment["SOOM_NOTIFICATION_CARD_QA"] == "1" {
            return [NotificationKind.comment, .reaction, .comment].enumerated().map { index, kind in
                .init(id: UUID(uuidString: String(format: "D3700000-0000-4000-8000-%012d", index + 1))!,
                    recipientId: ReviewDemoMode.userID, actorId: companionID, type: kind,
                    postId: UUID(uuidString: index == 2 ? "D3600000-0000-4000-8000-000000000999" : "D3600000-0000-4000-8000-000000000010"),
                    body: nil, readAt: notificationsRead ? Date() : nil, createdAt: Date())
            }
        }
        #endif
        guard !notificationHidden,let first = items.first(where: { $0.authorId == ReviewDemoMode.userID }) else { return [] }
        return [NotificationDTO(id: UUID(uuidString: "D3000000-0000-4000-8000-000000000099")!, recipientId: ReviewDemoMode.userID,
            actorId: companionID, type: .comment, postId: first.id, body: "좋은 리듬이에요! 함께 응원해요.",
            readAt: notificationsRead ? Date() : nil, createdAt: first.createdAt)]
    }
    func markAllNotificationsAsRead() async throws { try requireActive(); notificationsRead = true }
    func hideNotification(id:UUID) async throws { try requireActive();notificationHidden=true }
    func restoreNotification(id:UUID) async throws { try requireActive();notificationHidden=false }
    func authenticatedUserID() async throws -> UUID { try requireActive(); return ReviewDemoMode.userID }
    func report(target: CommunityReportTarget, reason: CommunityReportReason, details: String?) async throws -> UUID {
        try requireActive()
        guard (details?.count ?? 0) <= 2_000 else { throw CommunitySafetyError.invalidDetails }
        let receipt = UUID()
        reportReceipts.append(receipt)
        return receipt
    }
    func block(userID: UUID) async throws {
        try requireActive()
        guard userID != ReviewDemoMode.userID else { throw CommunitySafetyError.invalidTarget }
        if !blocked.contains(where: { $0.id == userID }) {
            blocked.append(CommunityBlockedUser(blockedUserID: userID, displayName: profile(userID).displayName, blockedAt: Date()))
        }
        following.remove(userID)
    }
    func unblock(userID: UUID) async throws { try requireActive(); blocked.removeAll { $0.id == userID } }
    func listBlockedUsers() async throws -> [CommunityBlockedUser] { try requireActive(); return blocked }
    func clubID(for id: String) -> UUID {
        if let existing = clubIDs[id] { return existing }
        let value = UUID(); clubIDs[id] = value; return value
    }
    func clubIdentity(id: UUID) async throws -> CommunityClubIdentity? {
        try requireActive()
        guard let key = clubIDs.first(where: { $0.value == id })?.key,
              let detail = try? await clubs.fetchClubDetail(clubId: key) else { return nil }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
           ProcessInfo.processInfo.environment["SOOM_UX_CLUB_STATE"] == "identity_first_read_failure",
           detail.name == "Synthetic Identity Club", !qaUnverifiedClubs.contains(id) {
            qaUnverifiedClubs.insert(id)
            throw ClubServiceError.clubNotFound
        }
        #endif
        return CommunityClubIdentity(id: id, ownerID: detail.membershipState == .owned ? ReviewDemoMode.userID : companionID)
    }
    func toggleFollow(_ id: UUID) throws {
        try requireActive()
        guard id != ReviewDemoMode.userID, !blocked.contains(where: { $0.id == id }) else { return }
        if following.contains(id) { following.remove(id) } else { following.insert(id) }
    }
    func fetchPost(id: UUID, viewerID: UUID) async throws -> FeedItem? { try requireActive(viewerID); return try await fetchPost(id: id) }
    func setBookmark(postID: UUID, viewerID: UUID, isSaved: Bool) async throws {
        try requireActive(viewerID); items[try index(postID)].viewerHasSaved = isSaved
    }
    func editPost(id: UUID, ownerID: UUID, title: String, description: String) async throws {
        let i = try ownedIndex(id, ownerID: ownerID); items[i] = copy(items[i], title: title, caption: description)
    }
    func setVisibility(postID: UUID, ownerID: UUID, visibility: FeedPostVisibility) async throws {
        let i = try ownedIndex(postID, ownerID: ownerID); items[i] = copy(items[i], visibility: visibility.shareableVisibility)
    }
    func deletePost(id: UUID, ownerID: UUID) async throws { items.remove(at: try ownedIndex(id, ownerID: ownerID)) }
    func fetch(clubID: UUID, viewerID: UUID, limit: Int) async throws -> [FeedItem] {
        try requireActive(viewerID)
        guard let key = clubIDs.first(where: { $0.value == clubID })?.key,
              let detail = try? await clubs.fetchClubDetail(clubId: key) else { throw ClubWorkoutFeedError.unavailable }
        guard detail.membershipState != .recommended else { throw ClubWorkoutFeedError.membershipRequired }
        return Array(try await fetchFeed(limit: limit).filter { $0.visibility == .publicFeed })
    }
    func perform(_ action: ClubWorkoutFeedAction, on item: FeedItem, clubID: UUID, viewerID: UUID) async throws {
        _ = try await fetch(clubID: clubID, viewerID: viewerID, limit: 100)
        switch action {
        case .cheer(let enabled):
            if enabled { try await addReaction(postId: item.id, reactionType: "cheer") }
            else { try await removeReaction(postId: item.id, reactionType: "cheer") }
        case .bookmark(let enabled): try await setBookmark(postID: item.id, viewerID: viewerID, isSaved: enabled)
        case .comment(let body): try await addComment(postId: item.id, body: body)
        case .delete: try await deletePost(id: item.id, ownerID: viewerID)
        }
    }

    func setPhotos(workoutID: UUID, photos: [WorkoutPhotoReference]) throws {
        try requireActive()
        for index in items.indices where items[index].sourceWorkoutId == workoutID {
            items[index] = copy(items[index], photos: photos)
        }
        NotificationCenter.default.post(name: FeedPostManagement.didChange, object: ReviewDemoMode.userID)
    }

    private func copy(_ item: FeedItem, id: UUID? = nil, authorID: UUID? = nil, authorName: String? = nil,
                      visibility: ShareableWorkoutVisibility? = nil, createdAt: Date? = nil,
                      title: String? = nil, caption: String? = nil, photos: [WorkoutPhotoReference]? = nil) -> FeedItem {
        let visibility = visibility ?? item.visibility
        var card = item.cardData
        if case .workoutSession(let value) = card {
            card = .workoutSession(ShareableWorkoutCardModel(id: id ?? value.id, shareType: value.shareType,
                backgroundOption: value.backgroundOption, workoutType: value.workoutType, title: title ?? value.title,
                distanceText: value.distanceText, durationText: value.durationText, averagePaceText: value.averagePaceText,
                elevationGainText: value.elevationGainText, averageHeartRateText: value.averageHeartRateText,
                activeEnergyText: value.activeEnergyText, primaryMessage: value.primaryMessage, growthMessage: value.growthMessage,
                recoveryMessage: value.recoveryMessage, footerText: "SOOM Demo", visibility: visibility,
                staticRoutePreview: value.staticRoutePreview, layoutVariant: value.layoutVariant))
        }
        var result = FeedItem(id: id ?? item.id, authorName: authorName ?? item.authorName, authorHandle: item.authorHandle,
            authorId: authorID ?? item.authorId, isLocalDraft: false, createdAt: createdAt ?? item.createdAt,
            itemType: item.itemType, visibility: visibility, cardData: card, sourceWorkoutId: item.sourceWorkoutId,
            caption: caption ?? item.caption, photoPlaceholders: item.photoPlaceholders, photos: photos ?? item.photos,
            routePhoto: item.routePhoto, activityContext: title ?? item.activityContext, emotionalContext: item.emotionalContext,
            movementMood: item.movementMood, optionalShortStory: item.optionalShortStory, routeMood: item.routeMood,
            recoveryCue: item.recoveryCue, locationHint: item.locationHint, clubContext: item.clubContext,
            contextLabels: item.contextLabels, reactions: item.reactions, viewerHasCheered: item.viewerHasCheered,
            viewerHasSaved: item.viewerHasSaved, comments: item.comments, microComment: item.microComment,
            activityDate: item.activityDate, deviceName: item.deviceName, workoutDistanceMeters: item.workoutDistanceMeters,
            workoutDurationSeconds: item.workoutDurationSeconds)
        if id == nil && visibility == item.visibility && authorID == nil && title == nil && caption == nil && photos == nil {
            result.serverPostSnapshot = item.serverPostSnapshot
            result.sharedDetail = item.sharedDetail
            result.sharedDetailContractEnabled = item.sharedDetailContractEnabled
        }
        return result
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Offset-page transport fixture only. No session, network client, or user data.
@MainActor enum Feed60PaginationDemo {
    static private(set) var pageRequests = 0
    static private(set) var heldCount = 0
    static private(set) var lastOffset = 0
    static private(set) var failureAttempts = 0
    static private(set) var returnedRows = 0
    private static var secondPageReleased = false
    static func reset() {
        pageRequests = 0; heldCount = 0; lastOffset = 0
        failureAttempts = 0; returnedRows = 0; secondPageReleased = false
    }
    static func releaseSecondPage() { secondPageReleased = true }
    static func page(limit: Int, offset: Int, owner: UUID) async throws -> [FeedItem] {
        guard ReviewDemoMode.isActive,
              ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
              ProcessInfo.processInfo.environment["SOOM_FEED_PAGINATION_QA"] == "1" else {
            throw CommunitySafetyError.accountChanged
        }
        lastOffset = offset
        if offset > 0 { pageRequests += 1 }
        // One logical failure includes FeedViewModel's two transient retries.
        // A fourth transport attempt is possible only after explicit retry.
        if offset == 8, ProcessInfo.processInfo.environment["SOOM_FEED_PAGINATION_FAIL_SECOND_ONCE"] == "1",
           failureAttempts < 3 {
            failureAttempts += 1
            throw URLError(.notConnectedToInternet)
        }
        if offset == 8, ProcessInfo.processInfo.environment["SOOM_FEED_PAGINATION_HOLD_SECOND"] == "1", !secondPageReleased {
            heldCount += 1
            defer { heldCount -= 1 }
            while !secondPageReleased { try await Task.sleep(for: .milliseconds(20)) }
        }
        try Task.checkCancellation()
        let anchor = Date(timeIntervalSince1970: 1_767_225_600) // Invented 2026-01-01.
        let rows = (0..<20).map { index in
            AccountActivityFeedRow(
                cardID: UUID(uuidString: String(format: "A9600000-0000-4000-8000-%012d", index + 1))!,
                canonicalID: UUID(uuidString: String(format: "A9610000-0000-4000-8000-%012d", index + 1))!,
                ownerID: owner, sport: "running",
                activityAt: ISO8601DateFormatter().string(from: anchor.addingTimeInterval(-Double(index) * 3600)),
                durationSeconds: 1800 + index, distanceMeters: Double(5000 + index),
                revision: 1, readPolicy: .profileOnlyV2)
        }
        let slice = Array(rows.dropFirst(max(0, offset)).prefix(max(0, limit)))
        returnedRows = max(returnedRows, min(20, max(0, offset) + slice.count))
        return AccountActivityHydratedPage(cards: slice.map { .init(projection: $0, legacyItem: nil) },
            nextCursor: slice.last?.cursor, hasMore: offset + slice.count < 20).displayItems()
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
/// Synthetic mixed feed. Reads only ReviewDemo's isolated SwiftData container.
/// Counters are deliberately not observable: measuring scrolling must not cause it.
@MainActor enum Feed61MixedReuseDemo {
    static var enabled: Bool {
        ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1"
            && ProcessInfo.processInfo.environment["SOOM_FEED_MIXED_REUSE_QA"] == "1"
    }
    static var total: Int { FeedUniquePhotoFixture.groups != nil ? 16 : (ProcessInfo.processInfo.environment["SOOM_FEED_MIXED_REUSE_COUNT"] == "48" ? 48 : 80) }
    static private(set) var pageRequests = 0
    static private(set) var returnedRows = 0
    private static var rows: [AccountActivityFeedRow] = []
    static func reset() { rows = []; pageRequests = 0; returnedRows = 0 }
    static func page(limit: Int, offset: Int, owner: UUID) throws -> [FeedItem] {
        guard enabled, let storage = ReviewDemoController.shared.runtime?.storage,
              HealthCloudJournal.accountID(for: storage.container.mainContext) == ReviewDemoMode.userID else {
            throw CommunitySafetyError.accountChanged
        }
        if rows.isEmpty {
            var query = FetchDescriptor<UnifiedWorkoutRecord>(sortBy: [SortDescriptor(\UnifiedWorkoutRecord.startDate, order: .reverse)])
            query.fetchLimit = 1
            guard let record = try storage.container.mainContext.fetch(query).first else {
                throw CommunitySafetyError.accountChanged
            }
            let own = UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)
            let formatter = ISO8601DateFormatter()
            rows = (0..<total).map { index in
                let isOwn = index == 0
                return AccountActivityFeedRow(
                    cardID: UUID(uuidString: String(format: "A9611000-0000-4000-8000-%012d", index + 1))!,
                    canonicalID: isOwn ? own.id : UUID(uuidString: String(format: "A9612000-0000-4000-8000-%012d", index + 1))!,
                    ownerID: isOwn ? ReviewDemoMode.userID : owner,
                    sport: isOwn ? own.workoutType.rawValue : "running",
                    activityAt: formatter.string(from: own.startDate.addingTimeInterval(-Double(index) * 3600)),
                    durationSeconds: isOwn ? Int(own.durationSeconds) : 1800 + index,
                    distanceMeters: isOwn ? own.distanceMeters : Double(5000 + index),
                    revision: 1, readPolicy: .profileOnlyV2)
            }
        }
        try Task.checkCancellation()
        if offset > 0 { pageRequests += 1 }
        let slice = Array(rows.dropFirst(max(0, offset)).prefix(max(0, limit)))
        returnedRows = max(returnedRows, min(total, max(0, offset) + slice.count))
        return AccountActivityHydratedPage(cards: slice.map { .init(projection: $0, legacyItem: nil) },
            nextCursor: slice.last?.cursor, hasMore: offset + slice.count < total).displayItems()
    }
}
#endif
