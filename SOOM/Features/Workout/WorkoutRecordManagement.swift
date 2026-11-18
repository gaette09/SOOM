import Combine
import CryptoKit
import Foundation
import Supabase
import SwiftData

/// Produced only by the internal readback call site below. This is not a
/// server authorization receipt and cannot be decoded from network payloads.
fileprivate struct PassiveWorkoutReadback {
    let ownerID: UUID
    let workoutID: UUID
    let scopeID: String
    let generation: Int
    let changedFields: Set<String>
}

enum WorkoutRecordChange {
    static func passiveReadbackWorkoutID(_ notification: Notification, viewerID: UUID?, authOwnerID: UUID?,
        generation: Int, policy: AccountActivityReadPolicy = .deployed) -> UUID? {
        guard policy == .profileOnlyV2, notification.name == WorkoutRecordManagement.didChange,
              let viewerID, authOwnerID == viewerID,
              let receipt = notification.userInfo?["passiveReadback"] as? PassiveWorkoutReadback,
              notification.object as? UUID == viewerID, receipt.ownerID == viewerID,
              receipt.scopeID == viewerID.uuidString.lowercased(), receipt.generation == generation,
              !receipt.changedFields.isEmpty,
              receipt.changedFields.isSubset(of: ["title", "description", "legacyVisibility"]) else { return nil }
        return receipt.workoutID
    }
}

extension UnifiedWorkout {
    var displayTitle: String {
        userTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? "\(workoutType.shareDisplayName) 기록"
    }
    var recordDescription: String? { userDescription?.nilIfBlank }
    var recordVisibility: FeedPostVisibility? { sharingVisibilityRaw.flatMap(FeedPostVisibility.init(rawValue:)) }
}
private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

enum WorkoutRecordEditPolicy {
    static let descriptionLimit = 100
    static let titleLimit = 80
    static let locationLimit = 80
    static func validate(title: String, description: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= titleLimit else { throw WorkoutRecordManagementError.invalidTitle }
        guard description.count <= descriptionLimit else { throw WorkoutRecordManagementError.descriptionTooLong }
    }
    static func owns(_ item: FeedItem, viewerID: UUID?) -> Bool {
        item.isLocalDraft || (viewerID != nil && item.authorId == viewerID)
    }
}

enum WorkoutRecordManagementError: LocalizedError {
    case invalidTitle, descriptionTooLong, invalidLocation, missingRecord, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidTitle: return "제목을 1~80자로 입력해 주세요."
        case .descriptionTooLong: return "설명은 공백 포함 100자까지 입력할 수 있어요."
        case .invalidLocation: return "지역명은 80자까지 입력할 수 있어요."
        case .missingRecord: return "이 기록이 삭제되었거나 더 이상 이 계정에 없어요."
        case .unavailable: return "서버에 적용하지 못했어요. 연결을 확인한 뒤 다시 시도해 주세요."
        }
    }
}

@MainActor
protocol WorkoutRecordRemoteManaging {
    func linkedPosts(workoutID: UUID, ownerID: UUID) async throws -> [FeedPostDTO]
    func update(workout: UnifiedWorkout, ownerID: UUID, visibility: FeedPostVisibility?, createIfMissing: Bool) async throws
    func delete(workoutID: UUID, ownerID: UUID) async throws
    func makeAllWorkoutPostsPrivate(ownerID: UUID) async throws
}

@MainActor
struct SupabaseWorkoutRecordRemote: WorkoutRecordRemoteManaging {
    let client: SupabaseClient
    private func check(_ ownerID: UUID) throws {
        guard client.auth.currentSession?.user.id == ownerID else { throw CommunitySafetyError.accountChanged }
    }
    private func checkWrite(_ ownerID: UUID) throws {
        try check(ownerID);try CommunitySafetyStore.shared.requireSocialAccess(viewerID: ownerID)
    }
    func linkedPosts(workoutID: UUID, ownerID: UUID) async throws -> [FeedPostDTO] {
        try check(ownerID)
        let rows: [FeedPostDTO] = try await client.from("feed_posts").select()
            .eq("user_id", value: ownerID).eq("source_workout_id", value: workoutID).execute().value
        try check(ownerID)
        return rows
    }
    func update(workout: UnifiedWorkout, ownerID: UUID, visibility: FeedPostVisibility?, createIfMissing: Bool) async throws {
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: ownerID)
        let rows = try await linkedPosts(workoutID: workout.id, ownerID: ownerID)
        try checkWrite(ownerID)
        if !rows.isEmpty {
            for row in rows {
                try checkWrite(ownerID)
                let changed: [Receipt] = try await client.from("feed_posts")
                    .update(Edit(title: workout.userTitle ?? row.title, body: workout.userDescription ?? row.body ?? "", visibility: visibility,
                        routeSummary: FeedRouteSummaryDTO(title: row.routeSummary?.title,
                            distanceText: row.routeSummary?.distanceText, fallbackStyle: row.routeSummary?.fallbackStyle,
                            routeExists: row.routeSummary?.routeExists ?? false,
                            startedAt: workout.startDate, deviceName: workout.deviceName ?? row.routeSummary?.deviceName ?? workout.feedSourceLabel,
                            locationName: workout.locationName ?? row.routeSummary?.locationName),
                        distanceMeters: workout.distanceMeters, durationSeconds: Int(workout.durationSeconds),
                        averagePaceSecondsPerKm: workout.distanceMeters.flatMap { $0 > 0 ? Int(workout.durationSeconds / ($0 / 1_000)) : nil }))
                    .eq("id", value: row.id).eq("user_id", value: ownerID)
                    .eq("source_workout_id", value: workout.id).select("id").execute().value
                guard changed.contains(where: { $0.id == row.id }) else { throw WorkoutRecordManagementError.missingRecord }
            }
        } else if createIfMissing, let visibility {
            // Stable per-account id makes a timeout/retry safe without publishing duplicate posts.
            let request = NewPost(id: Self.postID(owner: ownerID, workout: workout.id),
                userId: ownerID, sourceWorkoutId: workout.id, sport: workout.workoutType,
                title: workout.displayTitle, body: workout.userDescription ?? "",
                distanceMeters: workout.distanceMeters, durationSeconds: Int(workout.durationSeconds),
                averagePaceSecondsPerKm: workout.distanceMeters.flatMap { $0 > 0 ? Int(workout.durationSeconds / ($0 / 1000)) : nil },
                visibility: visibility, routeSummary: FeedRouteSummaryDTO(startedAt: workout.startDate,
                    deviceName: workout.deviceName ?? workout.feedSourceLabel, locationName: workout.locationName))
            let changed: [Receipt] = try await client.from("feed_posts").upsert(request, onConflict: "id").select("id").execute().value
            guard changed.contains(where: { $0.id == request.id }) else { throw WorkoutRecordManagementError.unavailable }
        }
        try checkWrite(ownerID)
    }
    func delete(workoutID: UUID, ownerID: UUID) async throws {
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: ownerID)
        let existing = try await linkedPosts(workoutID: workoutID, ownerID: ownerID)
        try checkWrite(ownerID)
        do { try await AccountActivityPreviewService(client: client, owner: ownerID).deleteProjectionIfEnrolled(canonicalID: workoutID) }
        catch let error as PostgrestError where error.code == "PGRST202" { /* Older server has no preview module. */ }
        try checkWrite(ownerID)
        let removed: [Receipt] = try await client.from("feed_posts").delete().eq("user_id", value: ownerID)
            .eq("source_workout_id", value: workoutID).select("id").execute().value
        try checkWrite(ownerID)
        guard Set(existing.map(\.id)).isSubset(of: Set(removed.map(\.id))) else { throw WorkoutRecordManagementError.unavailable }
    }
    func makeAllWorkoutPostsPrivate(ownerID: UUID) async throws {
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: ownerID)
        try checkWrite(ownerID)
        // Server first: this includes workout posts missing from this device's local Activity store.
        try await client.from("feed_posts")
            .update(VisibilityOnly(visibility: .privatePost))
            .eq("user_id", value: ownerID)
            .not("source_workout_id", operator: .is, value: "null")
            .execute()
        try checkWrite(ownerID)
    }
    private struct VisibilityOnly: Encodable { let visibility: FeedPostVisibility }
    nonisolated static func postID(owner: UUID, workout: UUID) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("SOOM.workout.\(owner).\(workout)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    private struct Receipt: Decodable { let id: UUID }
    private struct Edit: Encodable {
        let title: String; let body: String; let visibility: FeedPostVisibility?; let routeSummary: FeedRouteSummaryDTO
        let distanceMeters: Double?; let durationSeconds: Int; let averagePaceSecondsPerKm: Int?
        enum CodingKeys: String, CodingKey {
            case title, body, visibility; case routeSummary = "route_summary"
            case distanceMeters = "distance_meters", durationSeconds = "duration_seconds", averagePaceSecondsPerKm = "average_pace_seconds_per_km"
        }
    }
    private struct NewPost: Encodable {
        let id: UUID; let userId: UUID; let sourceWorkoutId: UUID; let sport: UnifiedWorkoutType
        let title: String; let body: String; let distanceMeters: Double?; let durationSeconds: Int
        let averagePaceSecondsPerKm: Int?; let visibility: FeedPostVisibility
        let routeSummary: FeedRouteSummaryDTO
        enum CodingKeys: String, CodingKey {
            case id, sport, title, body, visibility
            case userId = "user_id", sourceWorkoutId = "source_workout_id", distanceMeters = "distance_meters"
            case durationSeconds = "duration_seconds", averagePaceSecondsPerKm = "average_pace_seconds_per_km"
            case routeSummary = "route_summary"
        }
    }
}

/// Uses the same workout-management flow against the demonstration feed only.
/// It checks the mode on every call so an old screen cannot mutate a later session.
@MainActor
struct ReviewDemoWorkoutRecordRemote: WorkoutRecordRemoteManaging {
    private let store: ReviewDemoCommunityStore

    init(store: ReviewDemoCommunityStore? = nil) { self.store = store ?? .shared }

    private func check(_ ownerID: UUID) throws {
        guard ReviewDemoMode.isActive, ownerID == ReviewDemoMode.userID else {
            throw CommunitySafetyError.accountChanged
        }
    }

    func linkedPosts(workoutID: UUID, ownerID: UUID) async throws -> [FeedPostDTO] {
        try check(ownerID)
        return store.items.filter { $0.authorId == ownerID && $0.sourceWorkoutId == workoutID }.map { item in
            let sport: UnifiedWorkoutType
            if case .workoutSession(let card) = item.cardData { sport = card.workoutType }
            else { sport = .other }
            return FeedPostDTO(id: item.id, userId: ownerID, sourceWorkoutId: workoutID,
                sport: sport, title: item.activityContext, body: item.caption,
                distanceMeters: item.workoutDistanceMeters,
                durationSeconds: item.workoutDurationSeconds.map(Int.init),
                routeSummary: FeedRouteSummaryDTO(startedAt: item.activityDate,
                    deviceName: item.deviceName, locationName: item.locationHint),
                visibility: item.visibility.feedPostVisibility, createdAt: item.createdAt)
        }
    }

    func update(workout: UnifiedWorkout, ownerID: UUID, visibility: FeedPostVisibility?, createIfMissing: Bool) async throws {
        let rows = try await linkedPosts(workoutID: workout.id, ownerID: ownerID)
        if rows.isEmpty, createIfMissing, let visibility {
            let builder = FeedShareDraftBuilder(dateProvider: { workout.createdAt },
                idProvider: { SupabaseWorkoutRecordRemote.postID(owner: ownerID, workout: workout.id) })
            try await store.postPublicPost(builder.build(from: workout), visibility: visibility)
        } else {
            for row in rows {
                try check(ownerID)
                try await store.editPost(id: row.id, ownerID: ownerID,
                    title: workout.userTitle ?? row.title, description: workout.userDescription ?? row.body ?? "")
                if let visibility { try await store.setVisibility(postID: row.id, ownerID: ownerID, visibility: visibility) }
            }
        }
        NotificationCenter.default.post(name: FeedPostManagement.didChange, object: ownerID)
    }

    func delete(workoutID: UUID, ownerID: UUID) async throws {
        for row in try await linkedPosts(workoutID: workoutID, ownerID: ownerID) {
            try await store.deletePost(id: row.id, ownerID: ownerID)
        }
        ReviewDemoPhotoStore.shared.remove(workoutID: workoutID)
        NotificationCenter.default.post(name: FeedPostManagement.didChange, object: ownerID)
    }

    func makeAllWorkoutPostsPrivate(ownerID: UUID) async throws {
        try check(ownerID)
        for item in store.items where item.authorId == ownerID && item.sourceWorkoutId != nil {
            try await store.setVisibility(postID: item.id, ownerID: ownerID, visibility: .privatePost)
        }
        NotificationCenter.default.post(name: FeedPostManagement.didChange, object: ownerID)
    }
}

@MainActor
final class WorkoutRecordManagement: ObservableObject {
    @Published private(set) var workout: UnifiedWorkout
    @Published private(set) var isWorking = false
    @Published private(set) var isDeleted = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var sharingChecked = false
    @Published private(set) var sharingError: String?
    @Published private(set) var photos: [WorkoutPhotoDraft] = []
    @Published private(set) var photosLoading = false
    @Published private(set) var photosError: String?
    private var photoService: (any WorkoutPhotoManaging)?
    private var mutationRevision = 0
    private var context: ModelContext?
    private weak var storage: HealthAccountStorageController?
    private var scopeID: String?
    private var ownerID: UUID?
    private var remote: (any WorkoutRecordRemoteManaging)?
    private var drafts: (any FeedShareDraftStoreProtocol)?
    private var serverApplied = false
    private var isReviewDemoSession = false
    private var socialState: CommunitySafetyStore?
    static let didChange = Notification.Name("SOOM.WorkoutRecordManagement.didChange")

    private var existingDetailRefresher:(any WorkoutExistingDetailRefreshing)?
    init(workout: UnifiedWorkout) { self.workout = workout }
    func configure(context: ModelContext, storage: HealthAccountStorageController,
                   remote: (any WorkoutRecordRemoteManaging)? = nil,
                   drafts: (any FeedShareDraftStoreProtocol)? = nil, socialState: CommunitySafetyStore? = nil,
                   photoProvider: (any WorkoutPhotoManaging)? = nil,
                   existingDetailRefresher:(any WorkoutExistingDetailRefreshing)? = nil) {
        guard self.context == nil else { return }
        self.existingDetailRefresher=existingDetailRefresher
        if existingDetailRefresher == nil,remote == nil,!ReviewDemoMode.isActive,
           let client=SupabaseClientProvider(environment:AuthEnvironmentLoader().load()).makeClient() {
            self.existingDetailRefresher=WorkoutExistingDetailRefreshService(transport:SupabaseWorkoutExistingDetailRefreshTransport(client:client))
        }
        self.context = context; self.storage = storage; scopeID = storage.scopeID; ownerID = storage.userID
        self.socialState = socialState ?? (remote == nil && !ReviewDemoMode.isActive ? .shared : nil)
        self.drafts = drafts ?? FileFeedShareDraftStore.live
        isReviewDemoSession = ReviewDemoMode.isActive && storage.userID == ReviewDemoMode.userID
        if isReviewDemoSession {
            self.remote = ReviewDemoWorkoutRecordRemote()
            photoService = ReviewDemoPhotoStore.shared
        } else {
            self.remote = remote ?? SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient().map(SupabaseWorkoutRecordRemote.init)
            if remote == nil, let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() {
                photoService = AccountActivityPhotoProviderFactory.make(client: client, storage: storage, safety: socialState ?? .shared) ?? WorkoutPhotoService(client: client)
            }
        }
        // Explicit injected provider uses the same record-edit surface. A missing
        // candidate never changes visibility or creates a new photo action.
        if let photoProvider { photoService = photoProvider }
    }
    func adopt(_ workout: UnifiedWorkout) { guard !isWorking else { return }; self.workout = workout }
    var visibility: FeedPostVisibility? {
        if ownerID == nil { return .privatePost }
        return sharingChecked ? workout.recordVisibility : nil
    }
    var isBookmarked: Bool { workout.isBookmarked == true }
    var canSavePhotos: Bool { ownerID != nil && photoService != nil }
    func refreshPhotos() async {
        guard let ownerID, let photoService, !photosLoading, !isWorking else { return }
        photosLoading = true; photosError = nil
        defer { photosLoading = false }
        do {
            try validate()
            let references = try await photoService.load(workoutID: workout.id, ownerID: ownerID)
            try validate()
            guard !isWorking else { return }
            photos = references.map(WorkoutPhotoDraft.init(reference:))
        } catch { photosError = "사진을 불러오지 못했어요. 다시 시도해 주세요." }
    }
    private func validate() throws {
        guard let storage, let context, context.container === storage.container,
              storage.scopeID == scopeID, storage.userID == ownerID,
              ReviewDemoMode.isActive == isReviewDemoSession else { throw CommunitySafetyError.accountChanged }
    }
    private func currentRecord() throws -> UnifiedWorkoutRecord {
        try validate()
        guard let context else { throw WorkoutRecordManagementError.unavailable }
        let id = workout.id
        guard let record = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id })).first else {
            throw WorkoutRecordManagementError.missingRecord
        }
        return record
    }
    private enum Field: Hashable { case title, description, location, visibility, bookmark }
    private func persist(_ value: UnifiedWorkout, fields: Set<Field> = [.title, .description, .visibility, .bookmark], passiveReadbackGeneration: Int? = nil) throws {
        let record = try currentRecord()
        guard let context else { throw WorkoutRecordManagementError.unavailable }
        // Actual differences, not the requested write mask. Unknown changes
        // retain the original global mutation notification semantics.
        var actualChanges = Set<String>()
        if fields.contains(.title), record.userTitle != value.userTitle { actualChanges.insert("title") }
        if fields.contains(.description), record.userDescription != value.userDescription { actualChanges.insert("description") }
        if fields.contains(.visibility), record.sharingVisibilityRaw != value.sharingVisibilityRaw { actualChanges.insert("legacyVisibility") }
        if fields.contains(.location), record.locationName != value.locationName { actualChanges.insert("location") }
        if fields.contains(.bookmark), record.isBookmarked != value.isBookmarked { actualChanges.insert("bookmark") }
        if fields.contains(.title) { record.userTitle = value.userTitle }
        if fields.contains(.description) { record.userDescription = value.userDescription }
        if fields.contains(.location) { record.locationName = value.locationName }
        if fields.contains(.visibility) { record.sharingVisibilityRaw = value.sharingVisibilityRaw }
        if fields.contains(.bookmark) { record.isBookmarked = value.isBookmarked }
        record.updatedAt = Date()
        do {
            try HealthCloudJournal.workout(record, context: context)
            try HealthCloudJournal.commit(context)
        } catch { context.rollback(); throw error }
        workout = UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)
        var info: [AnyHashable: Any] = [:]
        if let passiveReadbackGeneration, let ownerID, let scopeID {
            info["passiveReadback"] = PassiveWorkoutReadback(ownerID: ownerID, workoutID: record.id,
                scopeID: scopeID, generation: passiveReadbackGeneration, changedFields: actualChanges)
        }
        #if DEBUG && targetEnvironment(simulator)
        ProjectionVerificationProbe.trace("persist origin=\(passiveReadbackGeneration == nil ? "mutation" : "passiveReadback") workout=\(record.id) fields=\(actualChanges.sorted())")
        #endif
        NotificationCenter.default.post(name: Self.didChange, object: ownerID, userInfo: info)
    }
    @discardableResult
    func refreshProviderMeasurements() async -> Bool {
        await perform {
            let value = UnifiedWorkoutPersistenceMapper().makeWorkout(from: try self.currentRecord())
            if !ImportedWorkoutPublication.usesLegacyPublication,let ownerID=self.ownerID {
                let token=WorkoutExistingDetailRefreshPending.mark(ownerID:ownerID,workoutID:value.id)
                guard let refresher=self.existingDetailRefresher,let context=self.context else {throw WorkoutRecordManagementError.unavailable}
                let count=try await refresher.refresh(sourceID:value.id,ownerID:ownerID,validate:{try self.validate()},loadInput:{
                    try self.validate()
                    let fresh=UnifiedWorkoutPersistenceMapper().makeWorkout(from:try self.currentRecord())
                    let telemetry=WorkoutTelemetryStore(modelContext:context)
                    let route=try await telemetry.resolvedRoute(for:fresh)
                    try self.validate()
                    return WorkoutSharedDetailInput.build(workout:fresh,route:route,telemetry:try telemetry.resolved(for:fresh))
                })
                try Task.checkCancellation();try self.validate()
                WorkoutExistingDetailRefreshPending.acknowledge(ownerID:ownerID,workoutID:value.id,token:token)
                self.notice=count>0 ? "기존에 공유한 상세 기록을 보완했어요." : "원본을 보완했어요. 새로운 상세 공유는 만들지 않았어요."
            }
            let localOnly = !ImportedWorkoutPublication.usesLegacyPublication || self.socialState?.canUseSocial == false
            if !localOnly, let ownerID = self.ownerID {
                guard let remote = self.remote else { throw WorkoutRecordManagementError.unavailable }
                let rows = try await remote.linkedPosts(workoutID: value.id, ownerID: ownerID)
                try self.validate()
                if !rows.isEmpty {
                    let binding = try await self.currentSharedBinding(rows, ownerID: ownerID)
                    try await remote.update(workout: value, ownerID: ownerID, visibility: nil, createIfMissing: false)
                    if let binding {
                        try await self.uploadRouteSnapshot(value, ownerID: ownerID,
                            expectedConsentRevision: binding.revision, onlyPostIDs: binding.posts)
                    }
                }
            }
            try self.validate()
            self.workout = value
            NotificationCenter.default.post(name: Self.didChange, object: self.ownerID)
        }
    }

    func refreshSharing() async {
        guard !isWorking else { return }
        guard let ownerID else { sharingChecked = true; return }
        guard let remote else { return }
        let revision = mutationRevision
        let readbackGeneration = CommunitySafetyStore.shared.accountGeneration
        let recordDate = try? currentRecord().updatedAt
        do {
            try validate()
            let rows = try await remote.linkedPosts(workoutID: workout.id, ownerID: ownerID)
            try validate()
            guard !isWorking, revision == mutationRevision, CommunitySafetyStore.shared.accountGeneration == readbackGeneration, try currentRecord().updatedAt == recordDate else { return }
            var value = UnifiedWorkoutPersistenceMapper().makeWorkout(from: try currentRecord())
            let visibility: FeedPostVisibility = rows.contains { $0.visibility == .publicPost } ? .publicPost
                : rows.contains { $0.visibility == .followers && $0.audienceContract == 1 } ? .followers
                : rows.contains { $0.visibility == .mutual } ? .mutual : .privatePost
            // A new import stays pending when publication failed. Opening its card must not erase retry intent.
            let before = value
            if !ImportedWorkoutPublication.isPending(value.sharingVisibilityRaw) && value.sharingVisibilityRaw != "source_review_pending" || !rows.isEmpty {
                value.sharingVisibilityRaw = visibility.rawValue
            }
            if let latest = rows.sorted(by: { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }).first {
                if value.userTitle == nil { value.userTitle = latest.title }
                if value.userDescription == nil { value.userDescription = latest.body }
            }
            if value != before {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_QA"] == "1" { print("SOOM54 sharing-reconcile workout=\(workout.id)") }
                #endif
                try persist(value, passiveReadbackGeneration: readbackGeneration)
            }
            sharingChecked = true; sharingError = nil
        } catch {
            guard revision == mutationRevision else { return }
            sharingChecked = false; sharingError = "공개 범위를 확인하지 못했어요. 다시 시도해 주세요."
        }
    }
    /// Photo-only editing must not overwrite title/description/location from a stale UI snapshot.
    @discardableResult
    func replacePhotos(_ proposedPhotos: [WorkoutPhotoDraft]) async -> Bool {
        await perform {
            if self.socialState?.canUseSocial == false { throw CommunitySafetyError.socialUnverified }
            let value = UnifiedWorkoutPersistenceMapper().makeWorkout(from: try self.currentRecord())
            guard let ownerID = self.ownerID, let photoService = self.photoService else {
                throw CommunitySafetyError.signInRequired
            }
            try await photoService.replace(workout: value, ownerID: ownerID, photos: proposedPhotos,
                expectedPhotoIDs: self.photos.map(\.id))
            try self.validate()
            self.photos = proposedPhotos
            self.serverApplied = !self.isReviewDemoSession
            self.notice = "운동 사진을 수정했어요."
        }
    }
    @discardableResult
    func edit(title: String, description: String, location proposedLocation: String? = nil, photos proposedPhotos: [WorkoutPhotoDraft]? = nil) async -> Bool {
        await perform {
            try WorkoutRecordEditPolicy.validate(title: title, description: description)
            var value = UnifiedWorkoutPersistenceMapper().makeWorkout(from: try self.currentRecord())
            value.userTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            value.userDescription = description
            if let proposedLocation {
                let name = proposedLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.count <= WorkoutRecordEditPolicy.locationLimit else { throw WorkoutRecordManagementError.invalidLocation }
                if !name.isEmpty { value.locationName = name }
            }
            let localOnly = self.socialState?.canUseSocial == false
            if !localOnly, let ownerID = self.ownerID {
                guard let remote = self.remote else { throw WorkoutRecordManagementError.unavailable }
                try await remote.update(workout: value, ownerID: ownerID, visibility: nil, createIfMissing: false)
                self.serverApplied = !self.isReviewDemoSession
            }
            try self.validate()
            if let proposedPhotos {
                if localOnly { throw CommunitySafetyError.socialUnverified }
                guard let ownerID = self.ownerID, let photoService = self.photoService else { throw CommunitySafetyError.signInRequired }
                try await photoService.replace(workout: value, ownerID: ownerID, photos: proposedPhotos,
                    expectedPhotoIDs: self.photos.map(\.id))
                try self.validate()
                self.photos = proposedPhotos
                self.serverApplied = !self.isReviewDemoSession
            }
            try await self.updateDrafts(value)
            try self.persist(value, fields: [.title, .description, .location])
            self.notice = localOnly ? "이 기기의 기록을 수정했어요. 소셜 공유 내용은 변경하지 않았어요." : "기록을 수정했어요."
        }
    }
    @discardableResult
    func setVisibility(_ visibility: FeedPostVisibility, expectedConsentRevision: Int64? = nil) async -> Bool {
        await perform {
            if self.socialState?.canUseSocial == false { throw CommunitySafetyError.socialUnverified }
            var value = UnifiedWorkoutPersistenceMapper().makeWorkout(from: try self.currentRecord())
            if let ownerID = self.ownerID {
                guard let remote = self.remote else { throw WorkoutRecordManagementError.unavailable }
                let sharesDetails = visibility != .privatePost && !self.isReviewDemoSession
                var confirmedConsentRevision = expectedConsentRevision
                if sharesDetails {
                    confirmedConsentRevision = try await self.confirmSharingConsent(ownerID: ownerID, expected: expectedConsentRevision)
                    guard let context = self.context, let scopeID = self.scopeID else {
                        throw WorkoutRecordManagementError.unavailable
                    }
                    _ = await WorkoutRegionEnricher.resolveAndPersist(workoutID: value.id,
                        context: context, scopeID: scopeID, isCurrent: {
                            self.storage?.scopeID == scopeID && self.storage?.container === context.container
                                && self.ownerID == ownerID
                        })
                    try self.validate()
                    value = UnifiedWorkoutPersistenceMapper().makeWorkout(from: try self.currentRecord())
                }
                // Metadata/visibility increments the server post revision. Prepare
                // the full snapshot afterwards, bound to that exact final revision.
                try await remote.update(workout: value, ownerID: ownerID, visibility: visibility, createIfMissing: visibility != .privatePost)
                if sharesDetails {
                    try await self.uploadRouteSnapshot(value, ownerID: ownerID, expectedConsentRevision: confirmedConsentRevision)
                }
                self.serverApplied = !self.isReviewDemoSession
            } else if visibility != .privatePost { throw CommunitySafetyError.signInRequired }
            try self.validate()
            value.sharingVisibilityRaw = visibility.rawValue
            try self.persist(value, fields: [.visibility])
            self.sharingChecked = true; self.sharingError = nil
            self.notice = visibility == .publicPost ? "공개로 변경했어요." : visibility == .followers ? "승인된 팔로워 공개로 변경했어요." : visibility == .mutual ? "기존 맞팔공개로 변경했어요." : "개인 전용으로 보관했어요."
        }
    }
    func toggleBookmark() async {
        await perform {
            var value = UnifiedWorkoutPersistenceMapper().makeWorkout(from: try self.currentRecord())
            value.isBookmarked = !(value.isBookmarked ?? false)
            try self.persist(value, fields: [.bookmark])
            self.notice = value.isBookmarked == true ? "저장한 기록에 추가했어요." : "저장한 기록에서 해제했어요."
        }
    }
    func delete() async {
        await perform {
            if self.socialState?.canUseSocial == false { throw CommunitySafetyError.socialUnverified }
            _ = try self.currentRecord()
            if let ownerID = self.ownerID {
                guard let remote = self.remote else { throw WorkoutRecordManagementError.unavailable }
                try await remote.delete(workoutID: self.workout.id, ownerID: ownerID)
                self.serverApplied = !self.isReviewDemoSession
            }
            try self.validate()
            if let drafts = self.drafts {
                for draft in try await drafts.fetchDrafts() where draft.sourceWorkoutId == self.workout.id {
                    try self.validate(); try await drafts.deleteDraft(id: draft.id)
                }
            }
            try self.validate()
            guard let context = self.context else { throw WorkoutRecordManagementError.unavailable }
            try await SwiftDataUnifiedWorkoutStore(modelContext: context).deleteWorkout(id: self.workout.id)
            self.isDeleted = true
            NotificationCenter.default.post(name: Self.didChange, object: self.ownerID)
        }
    }
    private func updateDrafts(_ value: UnifiedWorkout) async throws {
        guard let drafts else { return }
        for draft in try await drafts.fetchDrafts() where draft.sourceWorkoutId == value.id {
            try validate()
            try await drafts.saveDraft(FeedShareDraft(id: draft.id, sourceWorkoutId: draft.sourceWorkoutId,
                sport: draft.sport, title: value.displayTitle, body: value.userDescription ?? "",
                distanceMeters: draft.distanceMeters, durationSeconds: draft.durationSeconds,
                averagePaceSecondsPerKm: draft.averagePaceSecondsPerKm, routePreviewPayload: draft.routePreviewPayload,
                photoPlaceholders: draft.photoPlaceholders, tags: draft.tags, visibility: draft.visibility, createdAt: draft.createdAt,
                activityDate: draft.activityDate, deviceName: draft.deviceName, locationName: value.locationName ?? draft.locationName))
        }
    }
    private func confirmSharingConsent(ownerID: UUID, expected: Int64?) async throws -> Int64? {
        guard photoService != nil, !isReviewDemoSession,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return expected }
        let service = SupabaseAccountPrivacyService(client: client)
        let receipt = try await service.fetch()
        try validate()
        guard service.viewerID == ownerID, receipt.isSelected, receipt.shareMeasurements == true else { throw CommunitySafetyError.socialUnverified }
        if let expected, receipt.revision != expected { throw FeedPostManagementError.changeNotConfirmed }
        return receipt.revision
    }
    private func currentSharedBinding(_ posts: [FeedPostDTO], ownerID: UUID) async throws -> (revision: Int64, posts: Set<UUID>)? {
        guard photoService != nil, !isReviewDemoSession,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return nil }
        let privacy = SupabaseAccountPrivacyService(client: client)
        let receipt = try await privacy.fetch()
        try validate()
        guard privacy.viewerID == ownerID, receipt.isSelected, receipt.shareMeasurements == true else { return nil }
        let ids = try await SupabaseWorkoutSharedDetailService(client: client).authorizedPosts(posts)
        try validate()
        return ids.isEmpty ? nil : (receipt.revision, ids)
    }
    private func uploadRouteSnapshot(_ value: UnifiedWorkout, ownerID: UUID,
                                     expectedConsentRevision: Int64? = nil, onlyPostIDs: Set<UUID>? = nil) async throws {
        guard let context, let photoService else { return }
        let route = try await WorkoutTelemetryStore(modelContext: context).resolvedRoute(for: value)
        if let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() {
            let measurements = try WorkoutTelemetryStore(modelContext: context).resolved(for: value)
            let sharedService = SupabaseWorkoutSharedDetailService(client: client)
            let sharedEnabled = try await sharedService.enabled()
            try await sharedService.prepare(workout: value, route: route,
                telemetry: measurements, ownerID: ownerID,
                expectedConsentRevision: expectedConsentRevision, onlyPostIDs: onlyPostIDs)
            try validate()
            if sharedEnabled { return }
        }
        guard let route,
              let data = try await WorkoutRouteSnapshotRenderer().render(route: route, workoutType: value.workoutType) else { return }
        try validate()
        try await photoService.uploadRoute(workout: value, ownerID: ownerID, data: data)
        try validate()
    }
    @discardableResult
    private func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !isWorking else { return false }
        mutationRevision += 1
        isWorking = true; errorMessage = nil; notice = nil; serverApplied = false
        defer { isWorking = false }
        do { try validate(); try await operation(); return true }
        catch {
            errorMessage = serverApplied
                ? "서버 변경 후 이 기기의 저장을 마치지 못했어요. 같은 작업을 다시 시도하면 나머지 저장을 완료합니다. " + error.localizedDescription
                : error.localizedDescription
            return false
        }
    }
}


/// Import-only publication. The pending marker is written with the new workout,
/// so an interrupted import can be retried from Activity without republishing
/// duplicates or older records that the owner made private.
@MainActor
struct ImportedWorkoutPublication {
    nonisolated static let pendingVisibility = "auto_pending_v1"
    let context: ModelContext
    let storage: HealthAccountStorageController
    var remote: (any WorkoutRecordRemoteManaging)? = nil
    var privacy: (any AccountPrivacyServing)? = nil

    nonisolated static func pendingVisibility(for audience: FeedPostVisibility) -> String {
        "auto_pending_v1." + (audience == .mutual ? "private" : audience.rawValue)
    }
    nonisolated static func isPending(_ raw: String?) -> Bool {
        raw == pendingVisibility || [FeedPostVisibility.privatePost,.followers,.publicPost].contains { raw == pendingVisibility(for:$0) }
    }
    /// Missing historic source-review intent never adopts a later, broader default.
    nonisolated static func resolutionAudience(_ raw: String?, autoPublish: Bool) -> FeedPostVisibility {
        autoPublish ? (capturedAudience(raw) ?? .privatePost) : .privatePost
    }
    nonisolated static func capturedAudience(_ raw: String?) -> FeedPostVisibility? {
        guard let raw, raw.hasPrefix("auto_pending_v1."), let scope = FeedPostVisibility(rawValue:String(raw.dropFirst("auto_pending_v1.".count))), scope != .mutual else { return nil }
        return scope
    }

    struct Result: Equatable {
        var published = 0
        var failed = 0
        var leftPrivate = 0
        var serverFailed = false
    }

    static var usesLegacyPublication: Bool { !ProfileOnlyPrivacyReleaseGate.productionReady || ReviewDemoMode.isActive }
    static var profileImportDescription: String {
        "가져온 운동 요약은 프로필의 공개·비공개 설정에 따라 자동으로 반영돼요. 심박·GPS 공유 동의는 별도예요."
    }

    func publish(ids: [UUID]? = nil, explicitlySharingWorkoutID: UUID? = nil) async -> Result {
        // Profile-only uses the canonical durable worker. Keeping old import
        // markers for rollback does not authorize a second legacy post write.
        guard Self.usesLegacyPublication else { return Result() }
        guard let owner = storage.userID, context.container === storage.container,
              ReviewDemoMode.isActive == (owner == ReviewDemoMode.userID) else { return Result() }
        let expectedScope = storage.scopeID
        // Never infer Everyone from an old auto-publish flag. Confirm the current
        // account and selected default before publishing this new-import marker.
        var confirmedAudience: FeedPostVisibility = .privatePost
        var consentRevision: Int64?
        if owner == ReviewDemoMode.userID { confirmedAudience = storage.defaultWorkoutAudience }
        else if storage.autoPublishImportedWorkouts {
            do {
                let service: any AccountPrivacyServing
                if let privacy { service = privacy }
                else {
                    guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return Result(failed: ids?.count ?? 1) }
                    service = SupabaseAccountPrivacyService(client: client)
                }
                guard service.viewerID == owner else { return Result(failed:ids?.count ?? 1) }
                let receipt = try await service.fetch()
                guard service.viewerID == owner, storage.scopeID == expectedScope, storage.userID == owner,
                      receipt.isSelected, receipt.shareMeasurements == true, let audience = receipt.workoutDefault else { return Result(failed:ids?.count ?? 1) }
                confirmedAudience = audience
                consentRevision = receipt.revision
            } catch { return Result(failed: ids?.count ?? 1) }
        }
        let selected = ids.map(Set.init)
        var result = Result()
        let records: [UnifiedWorkoutRecord]
        do { records = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()) }
        catch { return Result(failed: ids?.count ?? 1) }
        let groups = UnifiedWorkoutDeduplicationEngine().canonicalGroups(
            records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }
        )
        let visibilityByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.sharingVisibilityRaw ?? "") })
        let publishableIDs = Set(groups.compactMap { group -> UUID? in
            let pending = group.sourceWorkouts.filter { Self.isPending(visibilityByID[$0.id]) }
            guard !pending.isEmpty,
                  group.sourceWorkouts.allSatisfy({ Self.isPending(visibilityByID[$0.id]) })
            else { return nil }
            return group.workout.id
        })
        for record in records where Self.isPending(record.sharingVisibilityRaw)
            && (selected.map { $0.contains(record.id) } ?? true) {
            guard storage.userID == owner, storage.scopeID == expectedScope,
                  context.container === storage.container else { break }
            let explicitlySelected = explicitlySharingWorkoutID == record.id && ids?.count == 1 && ids?.first == record.id
            if storage.autoPublishImportedWorkouts && owner != ReviewDemoMode.userID && !explicitlySelected {
                // Do not replay historical pending imports when old false consent
                // is completed. The marker is tied to this exact confirmed revision.
                guard let consentRevision, let completedAt = FullWorkoutSharingConsent.date(owner: owner, revision: consentRevision),
                      record.startDate >= completedAt else { continue }
            }
            if !publishableIDs.contains(record.id) {
                do {
                    record.sharingVisibilityRaw = FeedPostVisibility.privatePost.rawValue
                    record.updatedAt = Date()
                    try HealthCloudJournal.workout(record, context: context)
                    try HealthCloudJournal.commit(context)
                    result.leftPrivate += 1
                } catch { context.rollback(); result.failed += 1 }
                continue
            }
            let model = WorkoutRecordManagement(workout: UnifiedWorkoutPersistenceMapper().makeWorkout(from: record))
            model.configure(context: context, storage: storage, remote: remote)
            let captured = Self.capturedAudience(record.sharingVisibilityRaw) ?? confirmedAudience
            let visibility: FeedPostVisibility = !storage.autoPublishImportedWorkouts || confirmedAudience == .privatePost
                ? .privatePost : (confirmedAudience == .followers && captured == .publicPost ? .followers : captured)
            if await model.setVisibility(visibility, expectedConsentRevision: consentRevision) {
                if visibility != .privatePost { result.published += 1 } else { result.leftPrivate += 1 }
            } else { result.failed += 1 }
        }
        return result
    }

    func makeAllPrivate() async -> Result {
        guard let owner = storage.userID, context.container === storage.container,
              ReviewDemoMode.isActive == (owner == ReviewDemoMode.userID) else {
            return Result(failed: 1, serverFailed: true)
        }
        let expectedScope = storage.scopeID
        // Disable future auto-publication before the first network call. A ZIP
        // import that was already running will be handled as private on completion.
        storage.setAutoPublishImportedWorkouts(false)
        var result = Result()
        let selectedRemote: (any WorkoutRecordRemoteManaging)?
        if ReviewDemoMode.isActive {
            guard owner == ReviewDemoMode.userID else { return Result(failed: 1, serverFailed: true) }
            selectedRemote = ReviewDemoWorkoutRecordRemote()
        } else {
            selectedRemote = remote ?? SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
                .makeClient().map(SupabaseWorkoutRecordRemote.init)
        }
        do {
            guard let selectedRemote else { throw WorkoutRecordManagementError.unavailable }
            try await selectedRemote.makeAllWorkoutPostsPrivate(ownerID: owner)
        } catch { return Result(failed: 1, serverFailed: true) }
        guard storage.userID == owner, storage.scopeID == expectedScope,
              context.container === storage.container else { return Result(failed: 1) }
        let records: [UnifiedWorkoutRecord]
        do { records = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()) }
        catch { return Result(failed: 1) }
        do {
            for record in records {
                guard storage.userID == owner, storage.scopeID == expectedScope,
                      context.container === storage.container else { throw CommunitySafetyError.accountChanged }
                record.sharingVisibilityRaw = FeedPostVisibility.privatePost.rawValue
                record.updatedAt = Date()
                try HealthCloudJournal.workout(record, context: context)
            }
            try HealthCloudJournal.commit(context)
            NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: owner)
            result.leftPrivate = records.count
        } catch {
            context.rollback()
            result.failed = records.count
        }
        return result
    }
}


/// Explicit sharing of one already unified activity. Original rows/telemetry and
/// photos are never deleted. Pending markers make partial remote work retryable.
@MainActor
struct UnifiedWorkoutAutomaticShare {
    let context: ModelContext
    let validate: @MainActor () throws -> Void
    let makeSecondaryPrivate: @MainActor (UnifiedWorkout) async throws -> Void

    func prepare(workoutID: UUID) async throws -> UnifiedWorkout {
        try validate()
        let records = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
        let mapper = UnifiedWorkoutPersistenceMapper()
        let engine = UnifiedWorkoutDeduplicationEngine()
        let originals = records.map(mapper.makeWorkout)
        guard let group = engine.canonicalGroups(originals).first(where: {
            $0.sourceWorkouts.contains { $0.id == workoutID }
        }) else { throw WorkoutRecordManagementError.missingRecord }
        let availableIDs = Set(group.sourceWorkouts.map(\.id))
        guard group.sourceWorkouts.allSatisfy({ $0.preferredWorkoutID.map(availableIDs.contains) ?? true })
        else { throw WorkoutRecordManagementError.unavailable }
        guard group.sourceWorkouts.count > 1 else { return group.workout }
        var coverage: [UUID: Int] = [:]
        let telemetry = WorkoutTelemetryStore(modelContext: context)
        let routes = SwiftDataWorkoutRoutePersistenceStore(modelContext: context)
        for member in group.sourceWorkouts {
            var score = 0
            if let measurements = try telemetry.load(workoutID: member.id) {
                score += WorkoutTelemetryChannel.allCases.filter { channel in
                    measurements.samples.contains { $0.value(for: channel) != nil }
                }.count * 2
                if !measurements.intervals.isEmpty { score += 1 }
                if !measurements.splits.isEmpty { score += 1 }
            }
            if let route = try await routes.fetchRoute(workoutId: member.id), route.coordinates.count > 1 { score += 4 }
            try validate()
            coverage[member.id] = score
        }
        guard let primary = engine.automaticPublicationPrimary(in: group.sourceWorkouts, measuredCoverage: coverage)
        else { throw WorkoutRecordManagementError.missingRecord }
        let ids = Set(group.sourceWorkouts.map(\.id))
        let members = records.filter { ids.contains($0.id) }
        let request = members.compactMap(\.resolutionRequestID).sorted { $0.uuidString < $1.uuidString }.first ?? UUID()
        // Pin synchronously before any mutation awaits, including a second tap
        // from another screen. Never overwrite provider measurements.
        for record in members {
            record.preferredWorkoutID = primary.id
            record.resolutionRequestID = request
            record.updatedAt = Date()
            try HealthCloudJournal.workout(record, context: context)
        }
        try HealthCloudJournal.commit(context)
        for member in group.sourceWorkouts where member.id != primary.id {
            try await makeSecondaryPrivate(member)
            try validate()
        }
        let refreshed = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).map(mapper.makeWorkout)
        guard let prepared = engine.canonicalGroups(refreshed).first(where: { $0.workout.id == primary.id })?.workout
        else { throw WorkoutRecordManagementError.missingRecord }
        return prepared
    }

    /// Captures only the already resolved source IDs, never guesses a new group.
    /// Caller must persist this intent before a registration attempt and keep
    /// post success separate from ranking registration success.
    func rankingContribution(primaryID: UUID) throws -> SocialRankingContribution {
        try validate()
        let records = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
        let mapper = UnifiedWorkoutPersistenceMapper()
        let groups = UnifiedWorkoutDeduplicationEngine().canonicalGroups(records.map(mapper.makeWorkout))
        guard let group = groups.first(where: { $0.workout.id == primaryID }),
              group.sourceWorkouts.allSatisfy({ $0.id == primaryID || $0.preferredWorkoutID == primaryID }),
              let intent = SocialRankingContribution(canonicalID: primaryID, sourceIDs: group.sourceWorkouts.map(\.id))
        else { throw WorkoutRecordManagementError.unavailable }
        return intent
    }

    func complete(primaryID: UUID) throws {
        try validate()
        for record in try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()) where record.preferredWorkoutID == primaryID {
            record.resolutionRequestID = nil
            record.updatedAt = Date()
            try HealthCloudJournal.workout(record, context: context)
        }
        try HealthCloudJournal.commit(context)
        NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil)
    }
}
