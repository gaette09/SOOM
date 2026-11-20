import Foundation
import Combine
import ImageIO
import PhotosUI
import Supabase
import SwiftUI
import UIKit
#if DEBUG && targetEnvironment(simulator)
import OSLog
#endif

struct WorkoutPhotoReference: Identifiable, Equatable, Codable {
    let id: UUID
    let storagePath: String
    var nativeCardID: UUID? = nil
    var profileAuthority: AccountActivityProfilePhotoAuthority? = nil
    var bucket: String { profileAuthority?.bucket ?? (nativeCardID == nil ? WorkoutPhotoPolicy.bucket : "activity-photos-candidate") }
    var cacheKey: String { nativeCardID == nil ? storagePath : "activity-photos-candidate:" + storagePath }
}

struct WorkoutPhotoDraft: Identifiable, Equatable {
    let id: UUID
    let reference: WorkoutPhotoReference?
    let jpegData: Data?
    init(id: UUID = UUID(), jpegData: Data) { self.id = id; self.jpegData = jpegData; reference = nil }
    init(reference: WorkoutPhotoReference) { id = reference.id; self.reference = reference; jpegData = nil }
}

enum WorkoutPhotoError: LocalizedError {
    case invalidImage, tooMany, uploadUnavailable, changed
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "이 사진을 불러올 수 없어요. 다른 사진을 선택해 주세요."
        case .tooMany: return "운동 사진은 최대 6장까지 추가할 수 있어요."
        case .uploadUnavailable: return "사진을 저장하지 못했어요. 연결을 확인하고 다시 시도해 주세요."
        case .changed: return "사진이 다른 곳에서 변경되었어요. 다시 열어 확인해 주세요."
        }
    }
}

enum WorkoutPhotoPolicy {
    static let maximumCount = 6
    static let maximumBytes = 5 * 1_024 * 1_024
    static let bucket = "workout-photos"
    /// Decode a bounded thumbnail, apply its orientation, then draw fresh pixels.
    /// The new JPEG has no original GPS/EXIF, filename or camera metadata.
    static func sanitizedJPEG(from data: Data) throws -> Data {
        guard data.count <= 40 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw WorkoutPhotoError.invalidImage }
        let image = UIImage(cgImage: cgImage)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.82), jpeg.count <= maximumBytes else {
            throw WorkoutPhotoError.invalidImage
        }
        return jpeg
    }
    static func path(ownerID: UUID, postID: UUID, photoID: UUID) -> String {
        "\(ownerID.uuidString.lowercased())/\(postID.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"
    }
    static func validPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, UUID(uuidString: String(parts[0])) != nil,
              UUID(uuidString: String(parts[1])) != nil, parts[2].hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(parts[2].dropLast(4))) != nil
    }
}

@MainActor
protocol WorkoutPhotoManaging {
    func load(workoutID: UUID, ownerID: UUID) async throws -> [WorkoutPhotoReference]
    func replace(workout: UnifiedWorkout, ownerID: UUID, photos: [WorkoutPhotoDraft], expectedPhotoIDs: [UUID]?) async throws
    func uploadRoute(workout: UnifiedWorkout, ownerID: UUID, data: Data) async throws
}

extension WorkoutPhotoManaging {
    func replace(workout: UnifiedWorkout, ownerID: UUID, photos: [WorkoutPhotoDraft]) async throws {
        try await replace(workout: workout, ownerID: ownerID, photos: photos, expectedPhotoIDs: nil)
    }
}

#if DEBUG && targetEnvironment(simulator)
// Pure deterministic synthetic resource mapping. Never used for production IDs.
enum FeedUniquePhotoFixturePolicy {
    static func group(ordinal: Int, groups: Int) -> Int? {
        guard [1, 2].contains(groups), [2, 6].contains(ordinal) else { return nil }
        return groups == 1 || ordinal == 2 ? 1 : 2
    }
    static func source(group: Int) -> UUID {
        UUID(uuidString: String(format: "A9721000-0000-4000-8000-%012d", group))!
    }
    static func photo(group: Int, slot: Int) -> UUID {
        UUID(uuidString: String(format: "A9722000-0000-4000-8000-%012d", group * 10 + slot))!
    }
}


// Pure bounded correlation; no observable properties, timers or image references.
struct FeedMemoryPurgeTraceState {
    private(set) var instance: UUID?
    private(set) var seen: Set<String> = []
    mutating func begin(_ id: UUID) -> Bool {
        guard instance == nil else { return false }
        instance = id; seen.insert("action"); return true
    }
    mutating func accept(_ kind: String, instance id: UUID) -> Bool {
        guard instance == id, ["cache", "clear", "authorize", "decode", "published"].contains(kind) else { return false }
        return seen.insert(kind).inserted
    }
}

struct FeedMemoryPurgeScope: Equatable {
    let viewer: UUID?
    let owner: UUID
    let generation: Int
    let safetyRevision: Int
    let returnEpoch: Int
    let activationRevision: Int
    let appearanceRevision: Int
    let publicationRevision: Int
    let card: UUID
    let photo: UUID
    let source: UUID
    let projectionRevision: Int64
    let profileRevision: Int64
    let grant: UUID?
    let active: Bool
}

@MainActor enum FeedMemoryPurgeDiagnostic {
    static var enabled: Bool {
        FeedUniquePhotoFixture.groups == 2 &&
        ProcessInfo.processInfo.environment["SOOM_MEMORY_PURGE_QA"] == "1"
    }
    static func isTarget(_ photo: WorkoutPhotoReference) -> Bool {
        guard enabled, let a = photo.profileAuthority,
              a.ownerID != ReviewDemoMode.userID,
              a.cardID == UUID(uuidString: "A9611000-0000-4000-8000-000000000006"),
              a.sourceID == FeedUniquePhotoFixturePolicy.source(group: 2),
              photo.id == FeedUniquePhotoFixturePolicy.photo(group: 2, slot: 2)
        else { return false }
        return a.permits(photo, cardID: a.cardID, ownerID: a.ownerID, revision: a.projectionRevision)
    }
    private static var state = FeedMemoryPurgeTraceState()
    static var status: String { "issued=\(state.instance == nil ? 0 : 1);published=\(state.seen.contains("published") ? 1 : 0)" }
    private static var candidate: (instance: UUID, scope: FeedMemoryPurgeScope, cacheRevision: Int)?
    private static var frozen: (scope: FeedMemoryPurgeScope, cacheRevision: Int)?
    private static let logger = Logger(subsystem: "app.soom.prototype", category: "memory-purge-diagnostic")
    static func register(photo: WorkoutPhotoReference, instance: UUID, scope: FeedMemoryPurgeScope, cacheRevision: Int) {
        guard state.instance == nil, isTarget(photo), scope.active,
              scope.viewer == ReviewDemoMode.userID, scope.grant != nil else { return }
        candidate = (instance, scope, cacheRevision)
    }
    static func cleared(_ instance: UUID) {
        guard enabled, candidate?.instance == instance else { return }
        candidate = nil // Action's scalar frozen snapshot survives observer order.
    }
    static func postOnce() {
        guard enabled, UIApplication.shared.applicationState == .active,
              let candidate, state.begin(candidate.instance) else { return }
        frozen = (candidate.scope, candidate.cacheRevision)
        emit("action", instance: candidate.instance, flags: 1)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }
    static func cachePurged() {
        guard enabled, let id = state.instance, state.accept("cache", instance: id) else { return }
        emit("cache", instance: id, flags: 1)
    }
    static func event(_ kind: String, photo: WorkoutPhotoReference, instance: UUID,
                      scope: FeedMemoryPurgeScope?, cacheRevision: Int, flags: Int) {
        guard isTarget(photo), state.accept(kind, instance: instance), let frozen else { return }
        let same = scope == frozen.scope
        emit(kind, instance: instance, flags: flags | (same ? 16 : 0),
             cacheDelta: cacheRevision - frozen.cacheRevision)
    }
    private static func emit(_ kind: String, instance: UUID, flags: Int, cacheDelta: Int = 0) {
        // Fixed synthetic target; loader UUID is correlation-only, no account/path data.
        logger.info("MEMORY_PURGE epoch=1 kind=\(kind, privacy: .public) instance=\(instance.uuidString, privacy: .public) group=2 slot=2 row=6 flags=\(flags) cacheDelta=\(cacheDelta) seq=\(state.seen.count)")
    }
}

@MainActor enum FeedUniquePhotoFixture {
    static var groups: Int? {
        let env = ProcessInfo.processInfo.environment
        guard Feed61MixedReuseDemo.enabled, env["SOOM_FEED_BATCH_QA"] == "1",
              env["SOOM_PROFILE_PHOTO_QA"] == "1",
              env["SOOM_FEED_MIXED_REUSE_COUNT"] == "16",
              let value = Int(env["SOOM_UNIQUE_PHOTO_GROUPS"] ?? ""), [1, 2].contains(value)
        else { return nil }
        return value
    }
    static func group(row: AccountActivityFeedRow) -> Int? {
        guard let groups, row.ownerID != ReviewDemoMode.userID,
              let ordinal = Int(row.cardID.uuidString.suffix(12)),
              row.cardID == UUID(uuidString: String(format: "A9611000-0000-4000-8000-%012d", ordinal))
        else { return nil }
        return FeedUniquePhotoFixturePolicy.group(ordinal: ordinal, groups: groups)
    }
    private static var receipts: Set<String> = []
    private static let logger = Logger(subsystem: "app.soom.prototype", category: "unique-photo-diagnostic")
    static func record(_ kind: String, photo: WorkoutPhotoReference, width: Int, height: Int, bytes: Int) {
        guard receipts.count < 24, let groups, let authority = photo.profileAuthority,
              authority.ownerID != ReviewDemoMode.userID,
              let ordinal = Int(authority.cardID.uuidString.suffix(12)),
              authority.cardID == UUID(uuidString: String(format: "A9611000-0000-4000-8000-%012d", ordinal)),
              let group = FeedUniquePhotoFixturePolicy.group(ordinal: ordinal, groups: groups),
              authority.sourceID == FeedUniquePhotoFixturePolicy.source(group: group),
              authority.permits(photo, cardID: authority.cardID, ownerID: authority.ownerID, revision: authority.projectionRevision),
              let slot = (0..<4).first(where: { FeedUniquePhotoFixturePolicy.photo(group: group, slot: $0) == photo.id }),
              ["generated", "decoded", "published"].contains(kind) else { return }
        let token = "\(kind):\(group):\(slot)"
        guard receipts.insert(token).inserted else { return }
        // First resource receipt only, not final event totals or live ownership.
        logger.info("UNIQUE_PHOTO kind=\(kind, privacy: .public) group=\(group) slot=\(slot) width=\(width) height=\(height) bytes=\(bytes)")
    }
}
#endif

/// Session-only image bytes. Demo media never enter Storage or the photo library.
@MainActor
final class ReviewDemoPhotoStore: WorkoutPhotoManaging {
    static let shared = ReviewDemoPhotoStore()
    private var references: [UUID: [WorkoutPhotoReference]] = [:]
    private var images: [String: Data] = [:]

    func reset() { references = [:]; images = [:] }
    func remove(workoutID: UUID) {
        for reference in references.removeValue(forKey: workoutID) ?? [] { images.removeValue(forKey: reference.storagePath) }
    }
    private func validate(_ ownerID: UUID) throws {
        guard ReviewDemoMode.isActive, ownerID == ReviewDemoMode.userID else { throw CommunitySafetyError.accountChanged }
    }
    static func sampleJPEGData() -> Data? {
        let size = CGSize(width: 800, height: 600)
        let artwork = UIImage(named: "soom_running") ?? UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.27, green: 0.20, blue: 0.48, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            ("SOOM Demo\n오늘의 운동 기록" as NSString).draw(in: CGRect(x: 60, y: 200, width: 680, height: 200),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.white])
        }
        return artwork.jpegData(compressionQuality: 0.8)
    }
    func seed(workoutIDs: [UUID]) {
        guard ReviewDemoMode.isActive, let bytes = Self.sampleJPEGData() else { return }
        for workoutID in workoutIDs.prefix(3) {
            var seeded: [WorkoutPhotoReference] = []
            #if DEBUG && targetEnvironment(simulator)
            let count = ProcessInfo.processInfo.environment["SOOM_PROJECTION_OWN_PARITY_QA"] == "1" ? 2 : 1
            #else
            let count = 1
            #endif
            for _ in 0..<count {
                let photoID = UUID()
                let photo = WorkoutPhotoReference(id: photoID, storagePath: WorkoutPhotoPolicy.path(
                    ownerID: ReviewDemoMode.userID, postID: workoutID, photoID: photoID))
                seeded.append(photo); images[photo.storagePath] = bytes
            }
            references[workoutID] = seeded
        }
    }
    #if DEBUG && targetEnvironment(simulator)
    func seedProfilePhotoFixture(row: AccountActivityFeedRow, context: AccountActivityInteractionContext) async throws -> [WorkoutPhotoReference] {
        guard ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_PROFILE_PHOTO_QA"] == "1", let viewer = context.viewerID else { return [] }
        let uniqueGroup = FeedUniquePhotoFixture.group(row: row)
        let source = uniqueGroup.map { FeedUniquePhotoFixturePolicy.source(group: $0) } ?? UUID(uuidString: "A9110000-0000-4000-8000-000000000888")!
        let colors: [UIColor] = [.systemIndigo, .systemTeal, .systemOrange, .systemPink]
        var rows: [AccountActivityPhotoMetadata] = []
        for index in 0..<4 {
            let id = uniqueGroup.map { FeedUniquePhotoFixturePolicy.photo(group: $0, slot: index) } ?? UUID(uuidString: "A9110000-0000-4000-8000-00000000090\(index)")!
            let path = WorkoutPhotoPolicy.path(ownerID: row.ownerID, postID: source, photoID: id)
            let size = CGSize(width: 800, height: 600)
            let format = UIGraphicsImageRendererFormat.default()
            if ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_QA"] == "1" {
                // Controlled synthetic size, never a production cache policy.
                format.scale = ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_SMALL_PHOTOS"] == "1" ? 1 : 3
            }
            let artwork = UIGraphicsImageRenderer(size: size, format: format).image { canvas in
                colors[index].setFill(); canvas.fill(CGRect(origin: .zero, size: size))
                ("PROFILE PHOTO \(index + 1) · SYNTHETIC" as NSString).draw(at: CGPoint(x: 40, y: 260),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 32), .foregroundColor: UIColor.white])
            }
            images[path] = artwork.jpegData(compressionQuality: 0.85)
            rows.append(.init(id: id, card_id: row.cardID, storage_path: path, sort_order: index))
        }
        let envelope = AccountActivityProfilePhotoEnvelope(version: 2, viewer_id: viewer, card_id: row.cardID,
            owner_id: row.ownerID, canonical_id: row.canonicalID, projection_revision: row.revision,
            profile_revision: 1, backing: "legacy", source_id: source, bucket: "workout-photos",
            release_ready: true, rows: rows)
        let result = try await AccountActivityProfilePhotoAdapter(read: { _ in envelope }, context: { context }).load(row: row)
        if uniqueGroup != nil {
            for photo in result {
                let scale = ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_SMALL_PHOTOS"] == "1" ? 1 : 3
                FeedUniquePhotoFixture.record("generated", photo: photo, width: 800 * scale, height: 600 * scale, bytes: images[photo.storagePath]?.count ?? 0)
            }
        }
        return result
    }
    func seedNativeFixture(cardID: UUID) -> [WorkoutPhotoReference] {
        guard ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_NATIVE_PHOTO_QA"] == "1" else { return [] }
        let id = UUID(), size = CGSize(width: 800, height: 600)
        let art = UIGraphicsImageRenderer(size: size).image { canvas in
            UIColor.systemIndigo.setFill(); canvas.fill(CGRect(origin: .zero, size: size))
            UIColor.systemTeal.setFill(); canvas.fill(CGRect(x: 80, y: 80, width: 640, height: 280))
            ("SOOM · 합성 사진 검수" as NSString).draw(at: CGPoint(x: 80, y: 420), withAttributes: [.font:UIFont.boldSystemFont(ofSize:38),.foregroundColor:UIColor.white])
        }
        guard let bytes = art.jpegData(compressionQuality: 0.85) else { return [] }
        let reference = WorkoutPhotoReference(id: id, storagePath: WorkoutPhotoPolicy.path(ownerID: ReviewDemoMode.userID, postID: cardID, photoID: id), nativeCardID: cardID)
        images[reference.storagePath] = bytes
        return [reference]
    }
    #endif
    func bytes(for reference: WorkoutPhotoReference) -> Data? {
        guard ReviewDemoMode.isActive else { return nil }
        return images[reference.storagePath]
    }
    func load(workoutID: UUID, ownerID: UUID) async throws -> [WorkoutPhotoReference] {
        try validate(ownerID); return references[workoutID] ?? []
    }
    func replace(workout: UnifiedWorkout, ownerID: UUID, photos: [WorkoutPhotoDraft], expectedPhotoIDs: [UUID]?) async throws {
        try validate(ownerID)
        guard photos.count <= WorkoutPhotoPolicy.maximumCount else { throw WorkoutPhotoError.tooMany }
        let originals = references[workout.id] ?? []
        if let expectedPhotoIDs, Set(expectedPhotoIDs) != Set(originals.map(\.id)) { throw WorkoutPhotoError.changed }
        var nextImages: [String: Data] = [:]
        var nextReferences: [WorkoutPhotoReference] = []
        for photo in photos {
            if let reference = photo.reference {
                guard originals.contains(reference), let bytes = images[reference.storagePath] else { throw WorkoutPhotoError.changed }
                nextReferences.append(reference); nextImages[reference.storagePath] = bytes
            } else if let bytes = photo.jpegData {
                let sanitized = try WorkoutPhotoPolicy.sanitizedJPEG(from: bytes)
                let reference = WorkoutPhotoReference(id: photo.id,
                    storagePath: WorkoutPhotoPolicy.path(ownerID: ownerID, postID: workout.id, photoID: photo.id))
                nextReferences.append(reference); nextImages[reference.storagePath] = sanitized
            } else { throw WorkoutPhotoError.invalidImage }
        }
        let community = ReviewDemoCommunityStore.shared
        if !nextReferences.isEmpty && !community.items.contains(where: { $0.sourceWorkoutId == workout.id }) {
            try await community.postPublicPost(FeedShareDraftBuilder().build(from: workout), visibility: .privatePost)
        }
        try validate(ownerID)
        remove(workoutID: workout.id)
        references[workout.id] = nextReferences
        images.merge(nextImages) { _, new in new }
        try community.setPhotos(workoutID: workout.id, photos: nextReferences)
        NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: ownerID)
    }
    func uploadRoute(workout: UnifiedWorkout, ownerID: UUID, data: Data) async throws {
        try validate(ownerID)
        _ = try WorkoutPhotoPolicy.sanitizedJPEG(from: data)
        // The normal demo workout detail already renders its isolated route.
    }
}

@MainActor
struct WorkoutPhotoService: WorkoutPhotoManaging {
    let client: SupabaseClient
    private let accountGeneration = CommunitySafetyStore.shared.accountGeneration
    private func check(_ ownerID: UUID) throws {
        guard client.auth.currentSession?.user.id == ownerID,
              CommunitySafetyStore.shared.accountGeneration == accountGeneration else { throw CommunitySafetyError.accountChanged }
    }
    func load(workoutID: UUID, ownerID: UUID) async throws -> [WorkoutPhotoReference] {
        try check(ownerID)
        let posts = try await SupabaseWorkoutRecordRemote(client: client).linkedPosts(workoutID: workoutID, ownerID: ownerID)
        guard let post = posts.sorted(by: { $0.createdAt < $1.createdAt }).first else { return [] }
        let rows = try await media(postID: post.id)
        try check(ownerID)
        return rows.compactMap(\.photoReference)
    }
    func media(postID: UUID) async throws -> [FeedPostMediaDTO] {
        try await client.from("feed_post_media").select().eq("post_id", value: postID)
            .eq("media_type", value: "photo").order("sort_order").execute().value
    }
    /// Metadata replacement is one compare-and-swap RPC. Uploads are private
    /// until committed; removed references stop other viewers' access immediately.
    /// No bearer/signed image URL is ever persisted or exposed to another user.
    func replace(workout: UnifiedWorkout, ownerID: UUID, photos: [WorkoutPhotoDraft],
                 expectedPhotoIDs: [UUID]? = nil) async throws {
        guard photos.count <= WorkoutPhotoPolicy.maximumCount else { throw WorkoutPhotoError.tooMany }
        try check(ownerID)
        let remote = SupabaseWorkoutRecordRemote(client: client)
        var posts = try await remote.linkedPosts(workoutID: workout.id, ownerID: ownerID)
        if posts.isEmpty {
            guard !photos.isEmpty else { return }
            try await remote.update(workout: workout, ownerID: ownerID, visibility: .privatePost, createIfMissing: true)
            posts = try await remote.linkedPosts(workoutID: workout.id, ownerID: ownerID)
        }
        guard let post = posts.sorted(by: { $0.createdAt < $1.createdAt }).first else { throw WorkoutPhotoError.uploadUnavailable }
        let existing = try await media(postID: post.id)
        let originals = existing.compactMap(\.photoReference)
        let expected = expectedPhotoIDs ?? originals.map(\.id)
        if Set(originals.map(\.id)) != Set(expected) {
            // A timeout may have committed this exact request. Accept that retry.
            let requested = photos.map { WorkoutPhotoReference(id: $0.id,
                storagePath: WorkoutPhotoPolicy.path(ownerID: ownerID, postID: post.id, photoID: $0.id)) }
            guard originals == requested else { throw WorkoutPhotoError.changed }
            return
        }
        var rows: [PhotoWrite] = []
        for (index, photo) in photos.enumerated() {
            try check(ownerID)
            let path = WorkoutPhotoPolicy.path(ownerID: ownerID, postID: post.id, photoID: photo.id)
            if let reference = photo.reference {
                guard reference.storagePath == path, originals.contains(reference) else { throw WorkoutPhotoError.changed }
            } else if let bytes = photo.jpegData {
                guard bytes.count <= WorkoutPhotoPolicy.maximumBytes else { throw WorkoutPhotoError.invalidImage }
                // Stable photo IDs allow safe retry after an uncertain upload response.
                try await client.storage.from(WorkoutPhotoPolicy.bucket).upload(path, data: bytes,
                    options: FileOptions(cacheControl: "0", contentType: "image/jpeg", upsert: true))
                try check(ownerID)
            } else { throw WorkoutPhotoError.invalidImage }
            rows.append(PhotoWrite(id: photo.id, storagePath: path, sortOrder: index))
        }
        try check(ownerID)
        let saved: [FeedPostMediaDTO] = try await client.rpc("replace_workout_photos_v1", params:
            ReplaceParams(postID: post.id, expectedPhotoIDs: expected, photos: rows)).execute().value
        try check(ownerID)
        let requested = rows.map { WorkoutPhotoReference(id: $0.id, storagePath: $0.storagePath) }
        guard saved.count == requested.count, saved.allSatisfy({ $0.postId == post.id && $0.mediaType == .photo }),
              saved.sorted(by: { $0.sortOrder < $1.sortOrder }).compactMap(\.photoReference) == requested else {
            throw WorkoutPhotoError.uploadUnavailable
        }
        // The transaction enqueues old keys. Only the cleanup worker may remove
        // their bytes after atomically retiring the key; a direct client DELETE
        // could race another device reattaching that image before retirement.
        NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: ownerID)
    }
    private struct PhotoWrite: Encodable {
        let id: UUID; let storagePath: String; let sortOrder: Int
        enum CodingKeys: String, CodingKey { case id; case storagePath = "storage_path", sortOrder = "sort_order" }
    }
    private struct ReplaceParams: Encodable {
        let postID: UUID; let expectedPhotoIDs: [UUID]; let photos: [PhotoWrite]
        enum CodingKeys: String, CodingKey { case postID = "p_post_id", expectedPhotoIDs = "p_expected_photo_ids", photos = "p_photos" }
    }
    /// Called only from an explicit sharing action, after the route was masked.
    /// A new immutable key leaves the prior image intact if publication fails.
    func uploadRoute(workout: UnifiedWorkout, ownerID: UUID, data: Data) async throws {
        try check(ownerID)
        let bytes = try WorkoutPhotoPolicy.sanitizedJPEG(from: data)
        let remote = SupabaseWorkoutRecordRemote(client: client)
        var posts = try await remote.linkedPosts(workoutID: workout.id, ownerID: ownerID)
        if posts.isEmpty {
            try await remote.update(workout: workout, ownerID: ownerID, visibility: .privatePost, createIfMissing: true)
            posts = try await remote.linkedPosts(workoutID: workout.id, ownerID: ownerID)
        }
        guard !posts.isEmpty else { throw WorkoutPhotoError.uploadUnavailable }
        for post in posts {
            try check(ownerID)
            let id = UUID()
            let path = WorkoutPhotoPolicy.path(ownerID: ownerID, postID: post.id, photoID: id)
            try await client.storage.from(WorkoutPhotoPolicy.bucket).upload(path, data: bytes,
                options: FileOptions(cacheControl: "0", contentType: "image/jpeg", upsert: false))
            try check(ownerID)
            let rows: [FeedPostMediaDTO] = try await client.rpc("replace_workout_route_v1",
                params: RouteParams(postID: post.id, mediaID: id, storagePath: path)).execute().value
            try check(ownerID)
            guard rows.count == 1, rows.first?.postId == post.id,
                  rows.first?.routeReference == WorkoutPhotoReference(id: id, storagePath: path) else {
                throw WorkoutPhotoError.uploadUnavailable
            }
        }
    }
    private struct RouteParams: Encodable {
        let postID: UUID; let mediaID: UUID; let storagePath: String
        enum CodingKeys: String, CodingKey { case postID = "p_post_id", mediaID = "p_media_id", storagePath = "p_storage_path" }
    }
}

/// Scoped to an account generation and workout, including explicit media revisions.
struct WorkoutPhotoLoadIdentity: Equatable {
    let ownerID: UUID?
    let accountGeneration: Int
    let workoutID: UUID?
    let revision: Int
    let photoPaths: [String]
    var photosAreKnown = false

    func sharesScope(with other: Self) -> Bool {
        ownerID == other.ownerID && accountGeneration == other.accountGeneration && workoutID == other.workoutID
    }
}

struct WorkoutPhotoRowLoadState: Equatable {
    struct Decision {
        let resetScope: Bool
        let shouldLoad: Bool
    }
    private(set) var current: WorkoutPhotoLoadIdentity?
    private(set) var completed: WorkoutPhotoLoadIdentity?
    private(set) var failed: WorkoutPhotoLoadIdentity?
    private(set) var protected: WorkoutPhotoLoadIdentity?
    mutating func fail(_ identity: WorkoutPhotoLoadIdentity, protected isProtected: Bool = false) {
        guard current == identity else { return }
        if isProtected { protected = identity } else { failed = identity }
    }
    func isConfirmedEmpty(_ identity: WorkoutPhotoLoadIdentity, hasPhotos: Bool) -> Bool {
        completed == identity && !hasPhotos
    }

    mutating func begin(_ next: WorkoutPhotoLoadIdentity) -> Decision {
        let reset = current.map { !$0.sharesScope(with: next) } ?? true
        if current != next { failed = nil; protected = nil }
        if reset { completed = nil }
        current = next
        return Decision(resetScope: reset, shouldLoad: completed != next)
    }

    mutating func complete(_ identity: WorkoutPhotoLoadIdentity) -> Bool {
        guard current == identity, completed != identity else { return false }
        completed = identity
        failed = nil; protected = nil
        return true
    }

    func canDisplayLoaded(for identity: WorkoutPhotoLoadIdentity) -> Bool {
        current?.sharesScope(with: identity) == true
    }
}

/// ImageIO realizes bounded pixels on a detached task before UIKit display.
/// No shared cross-account bitmap cache is introduced.
/// Sizing changes pixels, never authority. Gallery keeps the existing 2048px limit.
struct WorkoutPhotoDecodeSize: Equatable {
    let maximumWidthPixels: Int
    let heightPixels: Int
    let minimumPortraitPixels: Int
    let maximumPortraitPixels: Int
    let minimumLandscapePixels: Int
    var cacheVariant: String { "feed:\(maximumWidthPixels):\(heightPixels):\(minimumPortraitPixels):\(maximumPortraitPixels):\(minimumLandscapePixels)" }
    static func feed(maximumWidth: CGFloat, height: CGFloat, displayScale: CGFloat) -> Self? {
        guard maximumWidth.isFinite, height.isFinite, displayScale.isFinite,
              maximumWidth > 0, height > 0, displayScale > 0, displayScale <= 8 else { return nil }
        func bucket(_ value: CGFloat) -> Int { Int(ceil(min(2048, value) / 64)) * 64 }
        return .init(maximumWidthPixels: bucket(maximumWidth * displayScale),
                     heightPixels: bucket(height * displayScale), minimumPortraitPixels: bucket(145 * displayScale),
                     maximumPortraitPixels: bucket(190 * displayScale), minimumLandscapePixels: bucket(200 * displayScale))
    }
    func maximumPixelSize(sourceWidth: Int, sourceHeight: Int, orientation: Int) -> Int {
        guard sourceWidth > 0, sourceHeight > 0 else { return 2048 }
        let swapped = [5,6,7,8].contains(orientation)
        let width = Double(swapped ? sourceHeight : sourceWidth), height = Double(swapped ? sourceWidth : sourceHeight)
        // Match the unchanged tile layout: portrait 145...190pt, landscape >=200pt.
        let naturalWidth = Double(heightPixels) * width / height
        let boundedWidth = width < height
            ? max(Double(minimumPortraitPixels), min(Double(maximumPortraitPixels), naturalWidth))
            : max(Double(minimumLandscapePixels), naturalWidth)
        let tileWidth = min(Double(maximumWidthPixels), boundedWidth)
        let scale = min(1, max(tileWidth / width, Double(heightPixels) / height))
        return min(2048, max(64, Int(ceil(min(2048, max(width,height) * scale) / 64)) * 64))
    }
}
enum WorkoutPhotoImageDecoder {
    nonisolated static func decode(_ data: Data, size: WorkoutPhotoDecodeSize? = nil) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard !data.isEmpty,
                  let source = CGImageSourceCreateWithData(data as CFData,
                    [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let maximum = size.map { $0.maximumPixelSize(
                sourceWidth: properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
                sourceHeight: properties?[kCGImagePropertyPixelHeight] as? Int ?? 0,
                orientation: properties?[kCGImagePropertyOrientation] as? Int ?? 1) } ?? 2048
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximum,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }.value
    }
}

/// Memory-only, bounded pixels. Reads normally reauthorize; a nonnil presentation
/// epoch permits reuse only within the explicit active feed visit, never a TTL.
struct SOOMMediaCacheScope: Equatable {
    let viewerID: UUID
    let accountGeneration: Int
    let safetyRevision: Int
}

enum SOOMMediaCacheError: Error { case supersededVersion }

@MainActor
final class SOOMValidatedMemoryCache<Key: Hashable, Value> {
    struct Statistics {
        var hits = 0
        var misses = 0
        var joinedRequests = 0
        var invalidations = 0
        var evictions = 0
    }
    private struct EntryKey: Hashable {
        let resource: Key
        let variant: String?
    }
    private struct Entry {
        let version: String
        let value: Value
        let cost: Int
        var lastUsed: UInt64
        var presentationEpoch: String?
    }
    private struct FlightKey: Hashable {
        let resource: Key
        let requestOwner: String?
    }
    private struct Flight {
        let id: UUID
        let presentationEpoch: String?
        let variant: String?
        let task: Task<(Value, String?), Error>
    }
    private struct ResourceState {
        let epoch = UUID()
        var authorizationOrder: UInt64 = 0
        var version: String?
    }
    private var resources: [Key: ResourceState] = [:]
    private var readers: [Key: Int] = [:]
    var onResourceInvalidated: ((Key) -> Void)?
    /// A newly authorized object version invalidates other mounted presentations,
    /// but must not invalidate the caller that just proved the new version.
    var onResourceVersionChanged: ((Key, String?) -> Void)?
    private let maximumCost: Int
    private let maximumCount: Int
    private var entries: [EntryKey: Entry] = [:]
    private var flights: [FlightKey: Flight] = [:]
    private var scope: SOOMMediaCacheScope?
    private var generation = UUID()
    private var clock: UInt64 = 0
    private(set) var totalCost = 0
    private(set) var statistics = Statistics()
    var entryCount: Int { entries.count }
    var inFlightCount: Int { flights.count }

    init(maximumCost: Int, maximumCount: Int) {
        self.maximumCost = max(0, maximumCost)
        self.maximumCount = max(0, maximumCount)
    }

    func invalidate() {
        generation = UUID()
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
        entries.removeAll()
        resources.removeAll()
        totalCost = 0
        statistics.invalidations += 1
    }

    func cancel(for key: Key, requestOwner: String?) {
        let flightKey = FlightKey(resource: key, requestOwner: requestOwner)
        flights.removeValue(forKey: flightKey)?.task.cancel()
        cleanResource(key)
    }

    /// Pure lookup only. The caller must independently prove a current grant;
    /// a cache hit cannot authorize access, extend a receipt, or mutate SwiftUI
    /// during body evaluation. Unknown versions and superseded scopes miss.
    func residentValue(for key: Key, scope expectedScope: SOOMMediaCacheScope,
                       version: String?, variant: String? = nil, allowAlternateVariant: Bool = false) -> Value? {
        guard scope == expectedScope, let version, !version.isEmpty,
              resources[key]?.version == version else { return nil }
        if let entry = entries[EntryKey(resource: key, variant: variant)], entry.version == version {
            return entry.value
        }
        // A decode size is a presentation preference, not a different object.
        // While layout settles, display already-resident pixels of this exact
        // authorized resource/version. No receipt, cache age or state is changed;
        // the normal load still requests the final size independently.
        guard allowAlternateVariant else { return nil }
        return entries.filter { $0.key.resource == key && $0.value.version == version }
            .max(by: { $0.value.lastUsed < $1.value.lastUsed })?.value.value
    }

    func value(for key: Key, scope nextScope: SOOMMediaCacheScope,
               presentationEpoch: String? = nil, reusePresentation: Bool = true, requestOwner: String? = nil,
               variant: String? = nil,
               authorize: @escaping @MainActor () async throws -> String?,
               load: @escaping @MainActor () async throws -> (Value, Int)) async throws -> Value {
        try Task.checkCancellation()
        let flightKey = FlightKey(resource: key, requestOwner: requestOwner)
        let entryKey = EntryKey(resource: key, variant: variant)
        if scope != nextScope {
            invalidate()
            scope = nextScope
        }
        if resources[key] == nil { resources[key] = ResourceState() }
        readers[key, default: 0] += 1
        defer {
            readers[key, default: 1] -= 1
            if readers[key] == 0 { readers.removeValue(forKey: key) }
            cleanResource(key)
        }
        if let flight = flights[flightKey] {
            if flight.presentationEpoch == presentationEpoch, flight.variant == variant {
                statistics.joinedRequests += 1
                let expectedGeneration = generation
                guard let expectedResource = resources[key]?.epoch else { throw CancellationError() }
                let result = try await flight.task.value
                try requireCurrent(expectedGeneration, scope: nextScope, key: key, resource: expectedResource)
                guard resources[key]?.version == result.1 else { throw SOOMMediaCacheError.supersededVersion }
                return result.0
            }
            flight.task.cancel()
            flights.removeValue(forKey: flightKey)
        }
        if reusePresentation, let presentationEpoch, var entry = entries[entryKey],
           entry.presentationEpoch == presentationEpoch, entry.version == resources[key]?.version {
            clock &+= 1
            entry.lastUsed = clock
            entries[entryKey] = entry
            statistics.hits += 1
            return entry.value
        }
        let expectedGeneration = generation
        let expectedResource = resources[key]!.epoch
        clock &+= 1
        let order = clock
        let id = UUID()
        let task = Task { @MainActor [self] in
            defer {
                if flights[flightKey]?.id == id { flights.removeValue(forKey: flightKey) }
                cleanResource(key)
            }
            do {
                let version = try await authorize()
                try requireCurrent(expectedGeneration, scope: nextScope, key: key, resource: expectedResource)
                guard var state = resources[key] else { throw CancellationError() }
                if state.authorizationOrder > order, state.version != version {
                    throw SOOMMediaCacheError.supersededVersion
                }
                if order >= state.authorizationOrder {
                    if state.version != version {
                        let hadPriorVersion = state.version != nil
                        removeVariants(for: key)
                        if hadPriorVersion { onResourceVersionChanged?(key, requestOwner) }
                    }
                    state.authorizationOrder = order; state.version = version; resources[key] = state
                }
                if let version, var entry = entries[entryKey], entry.version == version {
                    clock &+= 1
                    entry.lastUsed = clock
                    entry.presentationEpoch = reusePresentation ? presentationEpoch : nil
                    entries[entryKey] = entry
                    statistics.hits += 1
                    return (entry.value, Optional(version))
                }
                remove(entryKey)
                statistics.misses += 1
                let (value, cost) = try await load()
                try requireCurrent(expectedGeneration, scope: nextScope, key: key, resource: expectedResource)
                guard resources[key]?.version == version else { throw SOOMMediaCacheError.supersededVersion }
                // Another independently authorized presentation can finish while
                // this load is suspended. Replace its resident atomically so the
                // byte budget counts exactly one entry, never both insertions.
                remove(entryKey)
                if let version, cost > 0, cost <= maximumCost, maximumCount > 0 {
                    while totalCost > maximumCost - cost || entries.count >= maximumCount {
                        guard let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key else { break }
                        remove(oldest)
                        cleanResource(oldest.resource)
                        statistics.evictions += 1
                    }
                    clock &+= 1
                    entries[entryKey] = Entry(version: version, value: value, cost: cost, lastUsed: clock, presentationEpoch: reusePresentation ? presentationEpoch : nil)
                    totalCost += cost
                }
                return (value, version)
            } catch {
                // Superseded/canceled presentations cannot revoke a newer request.
                // A real denied/deleted/offline/invalid response revokes all older
                // work for this resource, including another presentation's load.
                if !(error is CancellationError), !(error is SOOMMediaCacheError), !Task.isCancelled,
                   generation == expectedGeneration, flights[flightKey]?.id == id,
                   resources[key]?.epoch == expectedResource {
                    revoke(key)
                }
                throw error
            }
        }
        flights[flightKey] = Flight(id: id, presentationEpoch: presentationEpoch, variant: variant, task: task)
        let result = try await task.value
        try requireCurrent(expectedGeneration, scope: nextScope, key: key, resource: expectedResource)
        // Readers retain receipts even for oversized or unknown-version values
        // until every waiting caller has consumed its result.
        guard resources[key]?.version == result.1 else { throw SOOMMediaCacheError.supersededVersion }
        return result.0
    }

    private func requireCurrent(_ expectedGeneration: UUID, scope expectedScope: SOOMMediaCacheScope,
                                key: Key, resource: UUID) throws {
        try Task.checkCancellation()
        guard generation == expectedGeneration, scope == expectedScope,
              resources[key]?.epoch == resource else { throw CancellationError() }
    }

    func invalidateResource(_ key: Key) { revoke(key) }

    private func revoke(_ key: Key) {
        removeVariants(for: key)
        resources.removeValue(forKey: key)
        for flightKey in Array(flights.keys) where flightKey.resource == key {
            flights.removeValue(forKey: flightKey)?.task.cancel()
        }
        onResourceInvalidated?(key)
    }

    private func cleanResource(_ key: Key) {
        if !entries.keys.contains(where: { $0.resource == key }), readers[key] == nil, !flights.keys.contains(where: { $0.resource == key }) {
            resources.removeValue(forKey: key)
        }
    }

    private func removeVariants(for resource: Key) {
        for key in Array(entries.keys) where key.resource == resource { remove(key) }
    }

    private func remove(_ key: EntryKey) {
        if let entry = entries.removeValue(forKey: key) { totalCost -= entry.cost }
    }
}

/// No disk cache, signed URLs or permission TTL. Only an explicit feed visit can
/// reuse a resident, previously authorized entry without another Storage info read.
@MainActor
final class WorkoutPhotoImageCache: ObservableObject {
    static let shared = WorkoutPhotoImageCache()
    @Published private(set) var invalidationRevision = 0
    let resourceInvalidations = PassthroughSubject<String, Never>()
    let resourceVersionChanges = PassthroughSubject<(resource: String, authorizedOwner: String?), Never>()
    let pixels = SOOMValidatedMemoryCache<String, CGImage>(maximumCost: 32 * 1_024 * 1_024, maximumCount: 12)
    private var subscriptions: Set<AnyCancellable> = []

    private init() {
        pixels.onResourceInvalidated = { [weak self] key in self?.resourceInvalidations.send(key) }
        pixels.onResourceVersionChanged = { [weak self] key, owner in self?.resourceVersionChanges.send((key, owner)) }
        CommunitySafetyStore.shared.$revision.dropFirst().sink { [weak self] _ in self?.invalidate() }
            .store(in: &subscriptions)
        for name in [WorkoutRecordManagement.didChange, FeedPostManagement.didChange] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] notification in
                let safety = CommunitySafetyStore.shared
                let authOwner = ReviewDemoMode.isActive ? ReviewDemoMode.userID
                    : SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient()?.auth.currentSession?.user.id
                if WorkoutRecordChange.passiveReadbackWorkoutID(notification, viewerID: safety.viewerID,
                    authOwnerID: authOwner, generation: safety.accountGeneration) != nil { return }
                self?.invalidate()
            }
                .store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.invalidate()
                #if DEBUG && targetEnvironment(simulator)
                if self != nil { FeedMemoryPurgeDiagnostic.cachePurged() }
                #endif
            }.store(in: &subscriptions)
    }

    func revoke(resources: Set<String>) {
        for resource in resources { pixels.invalidateResource(resource) }
    }

    private func invalidate() {
        pixels.invalidate()
        invalidationRevision += 1
    }
}

/// Fresh feed authority, shared by asynchronous loads and synchronous resident
/// display. Neither a matching batch ID alone nor cached pixels are a grant.
@MainActor enum Feed60PhotoResidentPolicy {
    static func object(batch: FeedReturnBatchPresentation?, photo: WorkoutPhotoReference,
                       viewerID: UUID?, generation: Int, safetyRevision: Int, returnEpoch: Int,
                       isBatchCurrent: (UUID) -> Bool,
                       isGrantCurrent: (FeedLinkedCardAuthority) -> Bool) -> FeedReturnStorageObject? {
        guard let batch, isBatchCurrent(batch.id),
              batch.context.matches(viewerID: viewerID, accountGeneration: generation,
                safetyRevision: safetyRevision, returnEpoch: returnEpoch),
              let authority = photo.profileAuthority, let grant = batch.grants[authority.cardID],
              !batch.denied.contains(authority.cardID), grant.photosAvailable,
              authority.permits(photo, cardID: grant.row.cardID, ownerID: grant.row.ownerID, revision: grant.row.revision),
              isGrantCurrent(.init(context: batch.context, batchID: batch.id, grantID: grant.id, row: grant.row)),
              case .authorized(let object) = batch.photoAccess(photo),
              object.bucket == photo.bucket, object.path == photo.storagePath,
              object.size.map({ $0 > 0 && $0 <= WorkoutPhotoPolicy.maximumBytes }) ?? true else { return nil }
        return object
    }
    static func allowsResident(decodeSize: WorkoutPhotoDecodeSize?, displaySizePending: Bool,
                               failed: Bool, active: Bool) -> Bool {
        (decodeSize != nil || displaySizePending) && !failed && active
    }
}

/// Presentation only, never photo authority. Nil at the call site preserves
/// independent Activity media loading; unavailable explicitly forbids fallback.
/// Every supplied photo still passes the existing exact batch/object policy.
enum Feed61OwnedPhotoPresentation: Equatable {
    case authorized([WorkoutPhotoReference])
    case unavailable

    var photos: [WorkoutPhotoReference] {
        switch self {
        case .authorized(let photos): return photos
        case .unavailable: return []
        }
    }
}

struct WorkoutPhotoImage: View {
    let photo: WorkoutPhotoReference
    var allowsFeedPresentationReuse = false
    var decodeSize: WorkoutPhotoDecodeSize? = nil
    var displaySizePending = false
    var contentMode: ContentMode = .fill
    var heroStyle = false
    var onAspectRatio: ((CGFloat) -> Void)? = nil
    var onImageLoaded: ((UIImage?) -> Void)? = nil
    var placeholderBackground: Color = SOOMColor.surface
    @EnvironmentObject private var auth: AuthViewModel
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @ObservedObject private var imageCache = WorkoutPhotoImageCache.shared
    @Environment(\.soomFeedRevalidationRevision) private var revalidationRevision
    @Environment(\.soomFeedPhotoPresentationID) private var feedPresentationID
    @Environment(\.soomFeedIsActive) private var feedIsActive
    @Environment(\.soomFeedReturnBatch) private var feedReturnBatch
    @Environment(\.soomFeedBatchIsCurrent) private var feedBatchIsCurrent
    @Environment(\.soomFeedCardGrantIsCurrent) private var feedCardGrantIsCurrent
    @State private var applicationIsActive = UIApplication.shared.applicationState == .active
    @State private var activationRevision = 0
    @State private var appearanceRevision = 0
    @State private var imagePresentationID = UUID()
    @State private var publicationRevision = 0
    @State private var image: UIImage?
    @State private var loadedKey: LoadIdentity?
    @State private var failed = false
    private struct LoadIdentity: Equatable {
        let path: String
        let decodeSize: WorkoutPhotoDecodeSize?
        let account: AccountDeletionTarget
        let safetyRevision: Int
        let accountGeneration: Int
        let imageInvalidationRevision: Int
        let revalidationRevision: Int
        let photoAuthority: AccountActivityProfilePhotoAuthority?
        let feedPresentationID: UUID?
        let activationRevision: Int
        let appearanceRevision: Int
        let isActive: Bool
        let batchGrantID: UUID?
    }
    private var applicableBatch: FeedReturnBatchPresentation? {
        allowsFeedPresentationReuse && feedPresentationID != nil ? feedReturnBatch : nil
    }
    private var currentBatchObject: FeedReturnStorageObject? {
        Feed60PhotoResidentPolicy.object(batch: applicableBatch, photo: photo,
            viewerID: auth.session.currentUser?.id ?? (ReviewDemoMode.isActive ? ReviewDemoMode.userID : nil),
            generation: safety.accountGeneration, safetyRevision: safety.revision, returnEpoch: revalidationRevision,
            isBatchCurrent: { feedBatchIsCurrent?($0) == true },
            isGrantCurrent: { feedCardGrantIsCurrent?($0) == true })
    }
    private var batchPermitsPhoto: Bool {
        applicableBatch == nil || currentBatchObject != nil
    }
    private var loadKey: LoadIdentity {
        LoadIdentity(path: photo.cacheKey, decodeSize: decodeSize, account: auth.accountDeletionTarget,
                     safetyRevision: safety.revision, accountGeneration: safety.accountGeneration,
                     imageInvalidationRevision: imageCache.invalidationRevision,
                     revalidationRevision: revalidationRevision, photoAuthority: photo.profileAuthority,
                     feedPresentationID: allowsFeedPresentationReuse ? feedPresentationID : nil, activationRevision: activationRevision,
                     appearanceRevision: appearanceRevision,
                     isActive: !displaySizePending && applicationIsActive && (!allowsFeedPresentationReuse || feedPresentationID == nil || feedIsActive) && batchPermitsPhoto,
                     batchGrantID: applicableBatch.flatMap { batch in
                        photo.profileAuthority.flatMap { batch.grants[$0.cardID]?.id } ?? batch.id
                     })
    }
    /// No callbacks or state writes during body evaluation. The existing load
    /// task still owns completion, aspect-ratio delivery and gallery callbacks.
    private var residentImage: UIImage? {
        guard applicableBatch != nil,
              Feed60PhotoResidentPolicy.allowsResident(decodeSize: decodeSize, displaySizePending: displaySizePending,
                failed: failed, active: applicationIsActive &&
                    (!allowsFeedPresentationReuse || feedPresentationID == nil || feedIsActive) && batchPermitsPhoto),
              UIApplication.shared.applicationState == .active,
              let viewer = auth.session.currentUser?.id ?? (ReviewDemoMode.isActive ? ReviewDemoMode.userID : nil),
              safety.viewerID == viewer, !AccountDeletionWriteFence.shared.isRetired(viewer),
              let owner = photo.profileAuthority?.ownerID, !safety.isBlocked(owner),
              let object = currentBatchObject,
              ReviewDemoMode.isActive || SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
                .makeClient()?.auth.currentSession?.user.id == viewer,
              let pixels = imageCache.pixels.residentValue(for: photo.cacheKey,
                scope: .init(viewerID: viewer, accountGeneration: safety.accountGeneration, safetyRevision: safety.revision),
                version: object.cacheVersionToken, variant: decodeSize?.cacheVariant, allowAlternateVariant: true) else { return nil }
        return UIImage(cgImage: pixels)
    }
    private var displayedImage: UIImage? {
        if let image, loadedKey == loadKey, loadKey.isActive { return image }
        return residentImage
    }
    var body: some View {
        Group {
            if let image = displayedImage {
                if heroStyle {
                    GeometryReader { geometry in
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .blur(radius: 28)
                                .overlay(.black.opacity(0.10))
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    }
                } else {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                }
            }
            else if failed { ContentUnavailableView("사진을 불러올 수 없어요", soomIcon: "photo") }
            else { SOOMSkeleton(layout: .photo, label: "운동 사진 불러오는 중").frame(maxWidth: .infinity, maxHeight: .infinity).background(placeholderBackground) }
        }
        .clipped()
        .accessibilityLabel("운동 사진")
        #if DEBUG && targetEnvironment(simulator)
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.environment["SOOM_FEED_LIFECYCLE_QA"] == "1", let image = displayedImage {
                Text(verbatim: "kind=\(decodeSize == nil ? "full" : "feed");w=\(Int(image.size.width));h=\(Int(image.size.height))")
                    .font(.system(size: 1)).frame(width: 1, height: 1).opacity(0.01)
                    .accessibilityIdentifier("workout.photo.decodeProbe")
            }
        }
        #endif
        .task(id: loadKey) { await load() }
        .onAppear {
            let active = UIApplication.shared.applicationState == .active
            if applicationIsActive != active { activationRevision += 1; applicationIsActive = active }
        }
        .onDisappear { cancelOwnRequest(); appearanceRevision += 1; clearPresentation() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            applicationIsActive = false
            activationRevision += 1
            cancelOwnRequest()
            clearPresentation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            activationRevision += 1
            applicationIsActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            #if DEBUG && targetEnvironment(simulator)
            let trace = FeedMemoryPurgeDiagnostic.isTarget(photo)
            let before = trace ? ((image != nil ? 1 : 0) | (loadedKey != nil ? 2 : 0)) : 0
            let observedKey = trace ? loadKey : nil
            let observedScope = observedKey.flatMap { memoryPurgeScope(for: $0) }
            #endif
            clearPresentation()
            #if DEBUG && targetEnvironment(simulator)
            if trace {
                let after = (image == nil ? 4 : 0) | (loadedKey == nil ? 8 : 0)
                FeedMemoryPurgeDiagnostic.event("clear", photo: photo, instance: imagePresentationID, scope: observedScope, cacheRevision: observedKey?.imageInvalidationRevision ?? -1, flags: before | after)
            }
            #endif
        }
        .onReceive(imageCache.resourceVersionChanges) { change in
            guard change.resource == photo.cacheKey,
                  change.authorizedOwner != requestOwner(for: loadKey) else { return }
            // Another host proved a new version. Hide old pixels until this
            // presentation gets its own fresh authority; never reuse its old grant.
            publicationRevision += 1
            cancelOwnRequest(); clearPresentation()
            if applicableBatch == nil {
                // Independent gallery/detail can perform a new Storage check.
                appearanceRevision += 1
            } else {
                // FeedViewContainer closes the old batch and obtains fresh authority.
                failed = true
            }
        }
        .onReceive(imageCache.resourceInvalidations) { resource in
            guard resource == photo.cacheKey else { return }
            // Not part of task identity: a denial must not trigger a retry.
            publicationRevision += 1
            clearPresentation(); failed = true
        }
    }
    @MainActor private func clearPresentation() {
        image = nil; loadedKey = nil; failed = false; onImageLoaded?(nil)
        #if DEBUG && targetEnvironment(simulator)
        FeedMemoryPurgeDiagnostic.cleared(imagePresentationID)
        #endif
    }
    #if DEBUG && targetEnvironment(simulator)
    private func memoryPurgeScope(for key: LoadIdentity) -> FeedMemoryPurgeScope? {
        guard FeedMemoryPurgeDiagnostic.isTarget(photo), let a = key.photoAuthority else { return nil }
        return .init(viewer: safety.viewerID, owner: a.ownerID, generation: key.accountGeneration,
            safetyRevision: key.safetyRevision, returnEpoch: key.revalidationRevision,
            activationRevision: key.activationRevision, appearanceRevision: key.appearanceRevision,
            publicationRevision: publicationRevision, card: a.cardID, photo: photo.id, source: a.sourceID,
            projectionRevision: a.projectionRevision, profileRevision: a.profileRevision,
            grant: key.batchGrantID, active: key.isActive && applicationIsActive &&
                UIApplication.shared.applicationState == .active)
    }
    #endif
    private func requestOwner(for key: LoadIdentity) -> String {
        // Lifetimes are per view; only completed resident leases are feed-shared.
        "view:\(imagePresentationID)"
    }
    @MainActor private func cancelOwnRequest() {
        imageCache.pixels.cancel(for: photo.cacheKey, requestOwner: requestOwner(for: loadKey))
    }
    private func presentationEpoch(for key: LoadIdentity) -> String {
        let authority = key.photoAuthority.map {
            "\($0.cardID):\($0.ownerID):\($0.sourceID):\($0.bucket):\($0.projectionRevision):\($0.profileRevision)"
        } ?? "legacy"
        if let feedID = key.feedPresentationID {
            return "feed:\(feedID):\(key.revalidationRevision):\(key.activationRevision):\(key.imageInvalidationRevision):\(authority):batch:\(key.batchGrantID?.uuidString ?? "none")"
        }
        // A gallery never reuses a resident authorization, but it still needs
        // a distinct request epoch so it cannot join a pre-background flight.
        return "view:\(imagePresentationID):\(key.appearanceRevision):\(key.activationRevision):\(key.imageInvalidationRevision):\(authority)"
    }
    @MainActor private func load(retryingSupersededVersion: Bool = false) async {
        guard !Task.isCancelled else { return }
        let key = loadKey
        let publication = publicationRevision
        clearPresentation()
        guard key.isActive else { return }
        if ReviewDemoMode.isActive {
            let pixels: CGImage
            if let batch = applicableBatch {
                do {
                    guard case .authorized(let object) = batch.photoAccess(photo) else { throw WorkoutPhotoError.changed }
                    pixels = try await imageCache.pixels.value(for: photo.cacheKey,
                        scope: .init(viewerID: ReviewDemoMode.userID, accountGeneration: key.accountGeneration, safetyRevision: key.safetyRevision),
                        presentationEpoch: presentationEpoch(for: key), requestOwner: requestOwner(for: key), variant: key.decodeSize?.cacheVariant,
                        authorize: {
                            guard key == loadKey, batchPermitsPhoto else { throw CancellationError() }
                            #if DEBUG && targetEnvironment(simulator)
                            FeedMemoryPurgeDiagnostic.event("authorize", photo: photo, instance: imagePresentationID, scope: memoryPurgeScope(for: key), cacheRevision: key.imageInvalidationRevision, flags: 1)
                            #endif
                            return object.cacheVersionToken
                        }, load: {
                            guard let bytes = ReviewDemoPhotoStore.shared.bytes(for: photo),
                                  let decoded = await WorkoutPhotoImageDecoder.decode(bytes, size: key.decodeSize) else { throw WorkoutPhotoError.invalidImage }
                            #if DEBUG && targetEnvironment(simulator)
                            FeedUniquePhotoFixture.record("decoded", photo: photo, width: decoded.width, height: decoded.height, bytes: decoded.bytesPerRow * decoded.height)
                            FeedMemoryPurgeDiagnostic.event("decode", photo: photo, instance: imagePresentationID, scope: memoryPurgeScope(for: key), cacheRevision: key.imageInvalidationRevision, flags: 1)
                            #endif
                            return (decoded, decoded.bytesPerRow * decoded.height)
                        })
                } catch { if key == loadKey { failed = true }; return }
            } else {
                guard let bytes = ReviewDemoPhotoStore.shared.bytes(for: photo),
                      let decoded = await WorkoutPhotoImageDecoder.decode(bytes, size: key.decodeSize) else { failed = true; return }
                pixels = decoded
            }
            guard !Task.isCancelled, key == loadKey, publication == publicationRevision else { return }
            let decoded = UIImage(cgImage: pixels)
            image = decoded; loadedKey = key
            #if DEBUG && targetEnvironment(simulator)
            FeedUniquePhotoFixture.record("published", photo: photo, width: pixels.width, height: pixels.height, bytes: pixels.bytesPerRow * pixels.height)
            if let scope = memoryPurgeScope(for: key) {
                FeedMemoryPurgeDiagnostic.register(photo: photo, instance: imagePresentationID,
                    scope: scope, cacheRevision: key.imageInvalidationRevision)
            }
            FeedMemoryPurgeDiagnostic.event("published", photo: photo, instance: imagePresentationID, scope: memoryPurgeScope(for: key), cacheRevision: key.imageInvalidationRevision, flags: 1)
            #endif
            if let batch = applicableBatch, let object = currentBatchObject {
                FeedStaleSummaryCache.shared.capture(photo: photo, object: object, image: decoded,
                    scope: FeedStaleSummaryCache.scope(batch.context))
            }
            onImageLoaded?(decoded)
            onAspectRatio?(decoded.size.width / max(decoded.size.height, 1))
            return
        }
        if let authority = photo.profileAuthority {
            guard authority.permits(photo, cardID: authority.cardID, ownerID: authority.ownerID, revision: authority.projectionRevision) else { failed = true; return }
        }
        if let nativeCard = photo.nativeCardID {
            let parts = photo.storagePath.split(separator: "/")
            guard AccountActivityReadPolicy.deployed.interactionsProductionReady, parts.count == 3,
                  UUID(uuidString: String(parts[1])) == nativeCard else { failed = true; return }
        }
        let bucket = photo.bucket
        guard WorkoutPhotoPolicy.validPath(photo.storagePath), let userID = auth.session.currentUser?.id,
              let imageOwner = UUID(uuidString: String(photo.storagePath.split(separator: "/")[0])), !safety.isBlocked(imageOwner),
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { failed = true; return }
        do {
            let cacheScope = SOOMMediaCacheScope(viewerID: userID,
                accountGeneration: key.accountGeneration, safetyRevision: key.safetyRevision)
            let pixels = try await imageCache.pixels.value(for: photo.cacheKey, scope: cacheScope,
                presentationEpoch: presentationEpoch(for: key), reusePresentation: key.feedPresentationID != nil,
                requestOwner: requestOwner(for: key), variant: key.decodeSize?.cacheVariant,
                authorize: {
                    guard auth.accountDeletionTarget == key.account, safety.accountGeneration == key.accountGeneration,
                          safety.revision == key.safetyRevision, !safety.isBlocked(imageOwner),
                          auth.session.currentUser?.id == userID, client.auth.currentSession?.user.id == userID else {
                        throw CommunitySafetyError.accountChanged
                    }
                    if let batch = applicableBatch {
                        // A stale environment receipt is cancellation, not a new
                        // server denial. It must not revoke the gallery's newer
                        // version or another current presentation's flight.
                        guard key == loadKey, batchPermitsPhoto else { throw CancellationError() }
                        guard batch.context.matches(viewerID: userID, accountGeneration: key.accountGeneration,
                                  safetyRevision: key.safetyRevision, returnEpoch: key.revalidationRevision),
                              case .authorized(let object) = batch.photoAccess(photo),
                              object.bucket == bucket, object.path == photo.storagePath else { throw WorkoutPhotoError.changed }
                        // The fresh batch proves this exact private Storage read.
                        // Null/denied never falls back to a different authority.
                        return object.cacheVersionToken
                    }
                    // This authenticated metadata request checks read access without transferring image bytes.
                    let info = try await client.storage.from(bucket).info(path: photo.storagePath)
                    guard auth.accountDeletionTarget == key.account, safety.accountGeneration == key.accountGeneration,
                          safety.revision == key.safetyRevision, !safety.isBlocked(imageOwner),
                          auth.session.currentUser?.id == userID, client.auth.currentSession?.user.id == userID,
                          info.name == photo.storagePath,
                          info.bucketId == nil || info.bucketId == bucket,
                          info.size.map({ $0 > 0 && $0 <= WorkoutPhotoPolicy.maximumBytes }) ?? true else {
                        throw WorkoutPhotoError.invalidImage
                    }
                    // Missing version metadata must degrade to a fresh download, never stale reuse.
                    return FeedReturnStorageObject.cacheVersionToken(objectID: info.id, version: info.version,
                        etag: info.etag, updatedAt: info.updatedAt, size: info.size)
                }, load: {
                    let data = try await client.storage.from(bucket).download(path: photo.storagePath)
                    try Task.checkCancellation()
                    guard auth.accountDeletionTarget == key.account, safety.accountGeneration == key.accountGeneration,
                          safety.revision == key.safetyRevision, !safety.isBlocked(imageOwner),
                          auth.session.currentUser?.id == userID, client.auth.currentSession?.user.id == userID,
                          data.count <= WorkoutPhotoPolicy.maximumBytes else { throw WorkoutPhotoError.invalidImage }
                    guard let pixels = await WorkoutPhotoImageDecoder.decode(data, size: key.decodeSize) else { throw WorkoutPhotoError.invalidImage }
                    return (pixels, pixels.bytesPerRow * pixels.height)
                })
            try Task.checkCancellation()
            guard key == loadKey, publication == publicationRevision, !safety.isBlocked(imageOwner), auth.session.currentUser?.id == userID,
                  client.auth.currentSession?.user.id == userID else { return }
            let decoded = UIImage(cgImage: pixels)
            image = decoded; loadedKey = key
            if let batch = applicableBatch, let object = currentBatchObject {
                FeedStaleSummaryCache.shared.capture(photo: photo, object: object, image: decoded,
                    scope: FeedStaleSummaryCache.scope(batch.context))
            }
            onImageLoaded?(decoded)
            onAspectRatio?(decoded.size.width / max(decoded.size.height, 1))
        } catch SOOMMediaCacheError.supersededVersion {
            if !retryingSupersededVersion, !Task.isCancelled, key == loadKey, publication == publicationRevision {
                await load(retryingSupersededVersion: true)
            } else if !Task.isCancelled, key == loadKey { failed = true }
        } catch { if !Task.isCancelled, key == loadKey { failed = true } }
    }
}

struct WorkoutPhotoEditor: View {
    @Binding var photos: [WorkoutPhotoDraft]
    var isEnabled = true
    var onImportingChanged: (Bool) -> Void = { _ in }
    @State private var selected: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(photos) { photo in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let bytes = photo.jpegData, let image = UIImage(data: bytes) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                    } else if let reference = photo.reference { WorkoutPhotoImage(photo: reference) }
                                }.frame(width: 100, height: 120).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                Button { photos.removeAll { $0.id == photo.id } } label: {
                                    Image(soom: "xmark.circle.fill").font(.title2).symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.7)).frame(width: 44, height: 44)
                                }.buttonStyle(.plain).accessibilityLabel("사진 삭제")
                            }
                        }
                    }
                }
            }
            PhotosPicker(selection: $selected, maxSelectionCount: max(1, WorkoutPhotoPolicy.maximumCount - photos.count), matching: .images) {
                Label("사진 추가 (\(photos.count)/6)", soomIcon: "photo")
            }.buttonStyle(.borderless)
                .disabled(!isEnabled || importing || photos.count >= WorkoutPhotoPolicy.maximumCount)
            if ReviewDemoMode.isActive {
                Button("데모 사진 추가 / Add sample photo") {
                    if let bytes = ReviewDemoPhotoStore.sampleJPEGData() { photos.append(WorkoutPhotoDraft(jpegData: bytes)) }
                }
                .disabled(!isEnabled || importing || photos.count >= WorkoutPhotoPolicy.maximumCount)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("reviewDemo.workout.samplePhoto")
            }
            if importing { ProgressView("사진 불러오는 중") }
            if let message { Text(message).font(.footnote).foregroundStyle(.red) }
            Text(ReviewDemoMode.isActive ? "데모 사진은 이 체험 세션에서만 보관돼요. 서버에 전송하지 않습니다." : "사진은 계정에 저장되며 운동의 공개 범위를 따릅니다. 사진의 위치 정보는 제거돼요.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .disabled(!isEnabled || importing)
        .onChange(of: selected) { _, items in
            guard !items.isEmpty else { return }
            Task { @MainActor in
                importing = true; onImportingChanged(true); message = nil
                defer { selected = []; importing = false; onImportingChanged(false) }
                for item in items {
                    do {
                        guard photos.count < WorkoutPhotoPolicy.maximumCount else { throw WorkoutPhotoError.tooMany }
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw WorkoutPhotoError.invalidImage }
                        photos.append(WorkoutPhotoDraft(jpegData: try WorkoutPhotoPolicy.sanitizedJPEG(from: data)))
                    } catch { message = error.localizedDescription }
                }
            }
        }
    }
}

enum WorkoutPhotoMediaLayout {
    static func widthAnchoredHeight(imageSize: CGSize, width: CGFloat) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, width > 0 else { return 0 }
        return width * imageSize.height / imageSize.width
    }
    static func availableWidth(in viewportWidth: CGFloat) -> CGFloat {
        viewportWidth.isFinite ? max(0, viewportWidth - 32) : 0
    }
    static func tileWidth(aspectRatio: CGFloat?, maxWidth: CGFloat, height: CGFloat = 260) -> CGFloat {
        let maxWidth = maxWidth.isFinite ? max(0, maxWidth) : 0
        let height = height.isFinite ? max(0, height) : 260
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else { return maxWidth }
        if aspectRatio < 1 { return min(maxWidth, max(145, min(190, height * aspectRatio))) }
        return min(maxWidth, max(200, height * aspectRatio))
    }
}

enum WorkoutMediaPages {
    static func ids(hasRoute: Bool, photos: [UUID]) -> [String] {
        (hasRoute ? ["map"] : []) + photos.map(\.uuidString)
    }
    static func selection(_ current: String, in pages: [String]) -> String {
        pages.contains(current) ? current : (pages.first ?? "map")
    }
    static func adjacent(_ current: String, in pages: [String], forward: Bool) -> String {
        guard let index = pages.firstIndex(of: current), !pages.isEmpty else { return selection(current, in: pages) }
        return pages[min(pages.count - 1, max(0, index + (forward ? 1 : -1)))]
    }
}

/// Bounded, session-only page positions. Account transitions discard all positions.
@MainActor
final class WorkoutMediaSelectionCache {
    static let shared = WorkoutMediaSelectionCache()
    private var owner: UUID?
    private var generation: Int?
    private var values: [String: String] = [:]
    private var order: [String] = []
    private let capacity: Int
    init(capacity: Int = 128) { self.capacity = max(1, capacity) }
    private func scope(owner: UUID?, generation: Int) {
        if self.owner != owner || self.generation != generation {
            values = [:]; order = []; self.owner = owner; self.generation = generation
        }
    }
    func restore(key: String, owner: UUID?, generation: Int, pages: [String], fallback: String) -> String {
        scope(owner: owner, generation: generation)
        return WorkoutMediaPages.selection(values[key] ?? fallback, in: pages)
    }
    func save(_ selection: String, key: String, owner: UUID?, generation: Int) {
        scope(owner: owner, generation: generation)
        values[key] = selection; order.removeAll { $0 == key }; order.append(key)
        if order.count > capacity { values.removeValue(forKey: order.removeFirst()) }
    }
}

struct WorkoutMediaPage {
    let id: String
    let content: AnyView
    var width: CGFloat? = nil
}

/// Real content bounds, with no synthetic end padding to center the last tile.
struct WorkoutMediaStripGeometry {
    let frames: [CGRect]
    let viewportWidth: CGFloat
    let contentWidth: CGFloat
    var maximumOffset: CGFloat { max(0, contentWidth - viewportWidth) }
    init(widths: [CGFloat], viewportWidth: CGFloat, height: CGFloat = 260,
         inset: CGFloat = 16, spacing: CGFloat = 8) {
        self.viewportWidth = viewportWidth.isFinite ? max(0, viewportWidth) : 0
        let inset = inset.isFinite ? max(0, inset) : 0
        let gap = spacing.isFinite ? max(0, spacing) : 0
        var x = inset
        var frames: [CGRect] = []
        for width in widths {
            let width = width.isFinite ? max(0, width) : 0
            frames.append(CGRect(x: x, y: 0, width: width, height: max(0, height)))
            x += width + gap
        }
        self.frames = frames
        contentWidth = widths.isEmpty ? 0 : x - gap + inset
    }
    func offset(at index: Int) -> CGFloat {
        guard frames.indices.contains(index) else { return 0 }
        return min(maximumOffset, max(0, frames[index].midX - viewportWidth / 2))
    }
    func nearest(to proposed: CGFloat, preferred: Int) -> Int {
        guard !frames.isEmpty else { return 0 }
        var best = min(frames.count - 1, max(0, preferred))
        for index in frames.indices where abs(offset(at: index) - proposed) + 0.01 < abs(offset(at: best) - proposed) {
            best = index
        }
        return best
    }
    func targetIndex(from start: Int, proposed: CGFloat, velocity: CGFloat) -> Int {
        guard !frames.isEmpty else { return 0 }
        let start = min(frames.count - 1, max(0, start))
        var candidate = nearest(to: proposed, preferred: start)
        if candidate == start, velocity.isFinite, abs(velocity) > 0.2 {
            candidate += velocity > 0 ? 1 : -1
        }
        return min(frames.count - 1, max(0, min(start + 1, max(start - 1, candidate))))
    }
}

/// UIKit owns gesture arbitration; tiles retain the established variable widths.
private struct WorkoutMediaPager: UIViewControllerRepresentable {
    let pages: [WorkoutMediaPage]
    @Binding var selection: String
    let reduceMotion: Bool
    var inset: CGFloat = 16
    var spacing: CGFloat = 8
    var onRouteVisibility: ((Bool, Bool) -> Void)? = nil
    func makeUIViewController(context: Context) -> WorkoutMediaPagerController { WorkoutMediaPagerController() }
    func updateUIViewController(_ controller: WorkoutMediaPagerController, context: Context) {
        controller.onSelect = { if selection != $0 { selection = $0 } }
        controller.onRouteVisibility = onRouteVisibility
        controller.update(pages: pages, selectedID: selection, animated: !reduceMotion, inset: inset, spacing: spacing)
    }
}

final class WorkoutMediaScrollView: UIScrollView {
    static func allowsHorizontalPan(velocity: CGPoint) -> Bool {
        velocity.x.isFinite && velocity.y.isFinite && abs(velocity.x) > abs(velocity.y)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer,
           !Self.allowsHorizontalPan(velocity: panGestureRecognizer.velocity(in: self)) { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

final class WorkoutMediaPagerController: UIViewController, UIScrollViewDelegate {
    private let scroll = WorkoutMediaScrollView()
    private var hosts: [String: UIHostingController<AnyView>] = [:]
    private var pages: [WorkoutMediaPage] = []
    private var selectedID = "map"
    private var dragStart = 0
    private var pendingTarget: String?
    private var deferredLayout: (pages: [WorkoutMediaPage], inset: CGFloat, spacing: CGFloat)?
    private var lastSize: CGSize = .zero
    private var inset: CGFloat = 0
    private var spacing: CGFloat = 0
    private var applyingLayout = false
    private var geometry = WorkoutMediaStripGeometry(widths: [], viewportWidth: 0)
    var onSelect: ((String) -> Void)?
    var onRouteVisibility: ((Bool, Bool) -> Void)?
    private var lastRouteVisible: Bool?
    private var lastRoutePresent: Bool?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear; view.clipsToBounds = true
        scroll.backgroundColor = .clear
        scroll.accessibilityIdentifier = "workout.media.pager"
        scroll.isPagingEnabled = false; scroll.isDirectionalLockEnabled = true
        scroll.showsHorizontalScrollIndicator = false; scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false; scroll.alwaysBounceHorizontal = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = self
        view.addSubview(scroll)
    }
    func update(pages next: [WorkoutMediaPage], selectedID: String, animated: Bool,
                inset: CGFloat = 0, spacing: CGFloat = 0) {
        loadViewIfNeeded()
        if (scroll.isDragging || scroll.isDecelerating), next.map(\.id) == pages.map(\.id), selectedID == self.selectedID {
            // Image decoding can change a tile's preferred width. Keep the active
            // drag geometry stable and apply the new widths at its snapped stop.
            deferredLayout = (next, inset, spacing)
            for page in next { hosts[page.id]?.rootView = page.content }
            return
        }
        let wasApplying = applyingLayout
        applyingLayout = true
        defer { applyingLayout = wasApplying }
        deferredLayout = nil
        let previous = self.selectedID
        if next.map(\.id) != pages.map(\.id) || selectedID != self.selectedID { pendingTarget = nil }
        self.pages = next; self.inset = inset; self.spacing = spacing
        self.selectedID = WorkoutMediaPages.selection(selectedID, in: next.map(\.id))
        let ids = Set(next.map(\.id))
        for id in Array(hosts.keys) where !ids.contains(id) {
            guard let host = hosts.removeValue(forKey: id) else { continue }
            host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
        }
        for page in next {
            if let host = hosts[page.id] { host.rootView = page.content }
            else {
                let host = UIHostingController(rootView: page.content)
                host.safeAreaRegions = []
                host.view.backgroundColor = .clear
                host.view.clipsToBounds = true
                addChild(host); scroll.addSubview(host.view); host.didMove(toParent: self)
                hosts[page.id] = host
            }
        }
        layoutPages()
        if !scroll.isDragging && !scroll.isDecelerating {
            positionSelected(animated: animated && previous != self.selectedID && lastSize != .zero)
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let wasApplying = applyingLayout
        applyingLayout = true
        defer { applyingLayout = wasApplying }
        let changed = lastSize != view.bounds.size
        layoutPages()
        if changed { positionSelected(animated: false); lastSize = view.bounds.size }
    }
    private func layoutPages() {
        scroll.frame = view.bounds
        let size = scroll.bounds.size
        geometry = WorkoutMediaStripGeometry(widths: pages.map { $0.width ?? size.width },
            viewportWidth: size.width, height: size.height, inset: inset, spacing: spacing)
        scroll.contentSize = CGSize(width: geometry.contentWidth, height: size.height)
        for (index, page) in pages.enumerated() {
            hosts[page.id]?.view.frame = geometry.frames[index]
            hosts[page.id]?.view.accessibilityElementsHidden = page.id != selectedID
        }
        scroll.isScrollEnabled = pages.count > 1 && geometry.maximumOffset > 0
        reportRouteVisibility()
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { reportRouteVisibility() }
    private func reportRouteVisibility() {
        let fraction = pages.firstIndex(where: { $0.id == "map" }).map {
            geometry.visibleFraction(at: $0, offset: scroll.contentOffset.x)
        } ?? 0
        let visible = fraction >= 0.65, present = fraction >= 0.01
        guard visible != lastRouteVisible || present != lastRoutePresent else { return }
        lastRouteVisible = visible; lastRoutePresent = present
        // Publish only threshold crossings, after SwiftUI's current update.
        DispatchQueue.main.async { [weak self] in self?.onRouteVisibility?(visible, present) }
    }
    private func positionSelected(animated: Bool) {
        guard let index = pages.firstIndex(where: { $0.id == selectedID }) else { return }
        scroll.setContentOffset(CGPoint(x: geometry.offset(at: index), y: 0), animated: animated)
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A new swipe may interrupt the previous deceleration. Advance from
        // that gesture's target rather than repeating its still-uncommitted page.
        dragStart = pendingTarget.flatMap { id in pages.firstIndex(where: { $0.id == id }) }
            ?? pages.firstIndex(where: { $0.id == selectedID }) ?? 0
        pendingTarget = nil
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scroll.bounds.width > 0, !pages.isEmpty else { return }
        let index = geometry.targetIndex(from: dragStart, proposed: targetContentOffset.pointee.x, velocity: velocity.x)
        pendingTarget = pages[index].id
        targetContentOffset.pointee = CGPoint(x: geometry.offset(at: index), y: 0)
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishPaging() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { finishPaging() } }
    // SwiftUI already owns programmatic selections; never echo them during layout.
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {}
    private func finishPaging() {
        guard !applyingLayout, scroll.bounds.width > 0, !pages.isEmpty else { return }
        let current = pages.firstIndex(where: { $0.id == selectedID }) ?? 0
        let index = pendingTarget.flatMap { id in pages.firstIndex(where: { $0.id == id }) }
            ?? geometry.nearest(to: scroll.contentOffset.x, preferred: current)
        pendingTarget = nil
        let changed = selectedID != pages[index].id
        selectedID = pages[index].id
        if let deferred = deferredLayout {
            update(pages: deferred.pages, selectedID: selectedID, animated: false, inset: deferred.inset, spacing: deferred.spacing)
        } else { layoutPages() }
        positionSelected(animated: false)
        if changed { onSelect?(selectedID) }
    }
}

/// Geometry-only knowledge for the parent loading placeholder; never contains
/// an image, path, record identity or route coordinates.
struct WorkoutCardMediaPresenceKey: PreferenceKey {
    static let defaultValue: Bool? = nil
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        if let next = nextValue() { value = (value ?? false) || next }
    }
}

struct WorkoutPhotoMediaRow<Route: View>: View {
    let workoutID: UUID?
    let photos: [WorkoutPhotoReference]
    var photosAreKnown = false
    var allowsFeedPresentationReuse = false
    var hasRoute = false
    var routeHandlesOpen = false
    var onOpenPhoto: (() -> Void)? = nil
    var metadataLoader: ((UUID) async throws -> [WorkoutPhotoReference])? = nil
    @ViewBuilder var route: () -> Route
    @EnvironmentObject private var auth: AuthViewModel
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var mediaScenePhase
    @Environment(\.soomFeedPhotoPresentationID) private var feedPresentationID
    @Environment(\.soomFeedRevalidationRevision) private var feedRevalidationRevision
    @Environment(\.soomFeedIsActive) private var feedIsActive
    @Environment(\.soomFeedIsScrolling) private var feedIsScrolling
    @Environment(\.soomFeedScrollMotionGate) private var scrollMotionGate
    @Environment(\.soomFeedReturnBatch) private var feedReturnBatch
    @Environment(\.soomFeedBatchIsCurrent) private var feedBatchIsCurrent
    @Environment(\.soomFeedCardGrantIsCurrent) private var feedCardGrantIsCurrent
    @Environment(\.soomFeedRoutePlaybackHistory) private var feedRoutePlaybackHistory
    private var feedRoutePlaybackScope: FeedRoutePlaybackScope? {
        guard allowsFeedPresentationReuse, feedReturnBatch != nil, let visitID = feedPresentationID,
              let viewerID = auth.session.currentUser?.id, viewerID == safety.viewerID else { return nil }
        return .init(visitID: visitID, viewerID: viewerID, accountGeneration: safety.accountGeneration,
                     safetyRevision: safety.revision, returnEpoch: feedRevalidationRevision)
    }
    @State private var viewportVisible = false
    @State private var viewportPresent = false
    @State private var routeVisible = true
    @State private var routePresent = true
    @State private var loadState = WorkoutPhotoRowLoadState()
    @State private var loaded: [WorkoutPhotoReference] = []
    @State private var ratios: [UUID: CGFloat] = [:]
    @State private var selectedMediaID = "map"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revision = 0
    @State private var selectedPhoto: WorkoutPhotoReference?
    private let mediaHeight: CGFloat = 260
    private var loadIdentity: WorkoutPhotoLoadIdentity {
        WorkoutPhotoLoadIdentity(ownerID: auth.session.currentUser?.id,
            accountGeneration: safety.accountGeneration, workoutID: workoutID,
            revision: revision, photoPaths: photos.map(\.storagePath), photosAreKnown: photosAreKnown)
    }
    private var visible: [WorkoutPhotoReference] {
        photosAreKnown ? photos : (photos.isEmpty ? (loadState.canDisplayLoaded(for: loadIdentity) ? loaded : []) : photos)
    }

    private var selectionKey: String {
        (workoutID?.uuidString ?? ("photos:" + photos.map { $0.id.uuidString }.joined(separator: ",")))
            + (hasRoute ? ":map" : ":photos")
    }
    private func restoredSelection(in pages: [String], fallback: String? = nil) -> String {
        WorkoutMediaSelectionCache.shared.restore(key: selectionKey, owner: loadIdentity.ownerID,
            generation: loadIdentity.accountGeneration, pages: pages, fallback: fallback ?? selectedMediaID)
    }
    private var mediaIDs: [String] { WorkoutMediaPages.ids(hasRoute: hasRoute, photos: visible.map(\.id)) }
    private var pageNumber: Int { (mediaIDs.firstIndex(of: selectedMediaID) ?? 0) + 1 }

    var body: some View {
        Group {
            if !hasRoute && visible.isEmpty && loadState.protected == loadIdentity {
                Label("사진을 보려면 계정을 확인해 주세요", systemImage: "lock")
                    .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk).frame(minHeight: 44)
            } else if !hasRoute && visible.isEmpty && loadState.failed == loadIdentity {
                Button { revision += 1 } label: {
                    Label("사진 다시 불러오기", systemImage: "arrow.clockwise")
                        .font(.subheadline).frame(minHeight: 44)
                }.accessibilityIdentifier("workout.media.retry")
            } else if hasRoute || !visible.isEmpty || (workoutID != nil && !photosAreKnown && !loadState.isConfirmedEmpty(loadIdentity, hasPhotos: !visible.isEmpty) && WorkoutPhotoLayoutHints.shared.hasPhotos(for: loadIdentity) != false) {
                GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    if mediaIDs.isEmpty {
                        SOOMSkeleton(layout: .photo, label: "사진 확인 중")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(SOOMColor.surfaceMuted)
                    } else {
                        WorkoutMediaPager(pages: mediaPages(viewportWidth: geometry.size.width), selection: $selectedMediaID, reduceMotion: reduceMotion,
                            inset: visible.isEmpty && hasRoute ? 0 : 16, spacing: 8,
                            onRouteVisibility: { visible, present in
                                if routeVisible != visible { routeVisible = visible }
                                if routePresent != present { routePresent = present }
                            })
                            .frame(width: geometry.size.width, height: mediaHeight)
                            .accessibilityIdentifier("workout.media.pager")
                        if mediaIDs.count > 1 {
                            Text("\(pageNumber) / \(mediaIDs.count)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.black.opacity(0.65), in: Capsule()).padding(8)
                                .accessibilityLabel(selectedMediaID == "map" ? "지도" : "운동 사진")
                                .accessibilityValue("\(mediaIDs.count)페이지 중 \(pageNumber)페이지")
                                .accessibilityAdjustableAction { direction in
                                    switch direction {
                                    case .increment: advance(forward: true)
                                    case .decrement: advance(forward: false)
                                    @unknown default: break
                                    }
                                }
                                .accessibilityIdentifier("workout.media.pageIndicator")
                        }
                    }
                }
                }
                .frame(height: mediaHeight).clipped()
                .onAppear { selectedMediaID = restoredSelection(in: mediaIDs) }
                .onChange(of: mediaIDs) { _, ids in selectedMediaID = restoredSelection(in: ids) }
                .accessibilityScrollAction { edge in
                    if edge == .trailing { advance(forward: true) }
                    if edge == .leading { advance(forward: false) }
                }
            }
        }
        .preference(key: WorkoutCardMediaPresenceKey.self,
            value: hasRoute || !visible.isEmpty ? true : (photosAreKnown || loadState.isConfirmedEmpty(loadIdentity, hasPhotos: false) ? false : nil))
        .onScrollVisibilityChange(threshold: 0.65) { viewportVisible = $0 }
        .onScrollVisibilityChange(threshold: 0.01) { viewportPresent = $0 }
        .onChange(of: selectedMediaID) { _, id in
            guard mediaIDs.count > 1, mediaIDs.contains(id) else { return }
            WorkoutMediaSelectionCache.shared.save(id, key: selectionKey, owner: loadIdentity.ownerID,
                generation: loadIdentity.accountGeneration)
        }
        .task(id: loadIdentity) { await loadPhotos(loadIdentity) }
        .onChange(of: mediaScenePhase) { _, phase in if phase == .active { revision += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: WorkoutRecordManagement.didChange)) { notification in
            guard WorkoutRecordChange.passiveReadbackWorkoutID(notification, viewerID: safety.viewerID,
                authOwnerID: auth.session.currentUser?.id, generation: safety.accountGeneration) == nil else { return }
            revision += 1
        }
        .workoutPhotoGallery(photos: visible, selection: $selectedPhoto)
    }

    private func mediaPages(viewportWidth: CGFloat) -> [WorkoutMediaPage] {
        let available = WorkoutPhotoMediaLayout.availableWidth(in: viewportWidth)
        var result: [WorkoutMediaPage] = []
        if hasRoute {
            let content = Group {
                if routeHandlesOpen { route() }
                else { tappableMedia("map") { route() } }
            }
            .environment(\.soomFeedRoutePlaybackHistory, allowsFeedPresentationReuse && feedReturnBatch != nil ? feedRoutePlaybackHistory : nil)
            .environment(\.soomFeedRoutePlaybackScope, feedRoutePlaybackScope)
            .environment(\.soomFeedScrollMotionGate, scrollMotionGate)
            .environment(\.workoutCardRouteViewport, WorkoutCardRouteViewport(
                isScrolling: feedIsScrolling, sufficientlyVisible: viewportVisible && routeVisible && selectedMediaID == "map",
                present: viewportPresent && routePresent && selectedMediaID == "map", active: mediaScenePhase == .active, reduceMotion: reduceMotion))
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            let width = visible.isEmpty ? viewportWidth : min(available, mediaHeight * 4 / 3)
            result.append(WorkoutMediaPage(id: "map", content: AnyView(content
                .clipShape(RoundedRectangle(cornerRadius: visible.isEmpty ? 0 : 10)).environmentObject(auth)), width: width))
        }
        result += visible.map { photo in
            let content = Button { selectedPhoto = photo } label: {
                WorkoutPhotoImage(photo: photo, allowsFeedPresentationReuse: allowsFeedPresentationReuse,
                    decodeSize: allowsFeedPresentationReuse ? WorkoutPhotoDecodeSize.feed(maximumWidth: available, height: mediaHeight, displayScale: displayScale) : nil,
                    displaySizePending: allowsFeedPresentationReuse && available <= 0, onAspectRatio: { ratio in
                    if ratios[photo.id] != ratio { ratios[photo.id] = ratio }
                })
                    .environment(\.soomFeedPhotoPresentationID, allowsFeedPresentationReuse ? feedPresentationID : nil)
                    .environment(\.soomFeedRevalidationRevision, feedRevalidationRevision)
                    .environment(\.soomFeedIsActive, feedIsActive)
                    .environment(\.soomFeedReturnBatch, allowsFeedPresentationReuse ? feedReturnBatch : nil)
                    .environment(\.soomFeedBatchIsCurrent, allowsFeedPresentationReuse ? feedBatchIsCurrent : nil)
                    .environment(\.soomFeedCardGrantIsCurrent, allowsFeedPresentationReuse ? feedCardGrantIsCurrent : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle()).clipped()
            }.buttonStyle(.plain).accessibilityLabel("운동 사진 크게 보기")
                .accessibilityIdentifier("workout.card.open.photo")
            return WorkoutMediaPage(id: photo.id.uuidString, content: AnyView(content
                .clipShape(RoundedRectangle(cornerRadius: 10)).environmentObject(auth)),
                width: WorkoutPhotoMediaLayout.tileWidth(aspectRatio: ratios[photo.id], maxWidth: available, height: mediaHeight))
        }
        return result
    }

    private func advance(forward: Bool) {
        let next = WorkoutMediaPages.adjacent(selectedMediaID, in: mediaIDs, forward: forward)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { selectedMediaID = next }
    }

    @MainActor private func loadPhotos(_ key: WorkoutPhotoLoadIdentity) async {
        var next = loadState
        let decision = next.begin(key)
        if next != loadState { loadState = next }
        if decision.resetScope {
            loaded = []; ratios = [:]
            // onAppear may already have restored a cached photo for this scope.
            // Keep that authorized position when the initial load task starts;
            // a new account/workout still falls back to its own first page.
            selectedMediaID = restoredSelection(in: mediaIDs, fallback: mediaIDs.first ?? "map")
        }
        guard decision.shouldLoad else { return }
        if photosAreKnown || !photos.isEmpty {
            finishLoading(key, result: photos, knownPhotoIDs: Set(photos.map(\.id)))
            return
        }
        if let metadataLoader, let workoutID {
            do {
                let result = try await metadataLoader(workoutID)
                try Task.checkCancellation()
                guard key == loadIdentity else { return }
                finishLoading(key, result: result)
            } catch {
                guard !Task.isCancelled, key == loadIdentity else { return }
                loaded = []; loadState.fail(key)
            }
            return
        }
        if ReviewDemoMode.isActive {
            #if DEBUG
            WorkoutCardPerformanceProbe.hit("photoMetadata")
            #endif
            guard let workoutID else { finishLoading(key, result: []); return }
            do {
                let result = try await ReviewDemoPhotoStore.shared.load(workoutID: workoutID, ownerID: ReviewDemoMode.userID)
                guard !Task.isCancelled, key == loadIdentity else { return }
                finishLoading(key, result: result)
            } catch {
                guard !Task.isCancelled, key == loadIdentity else { return }
                loaded = []; loadState.fail(key)
            }
            return
        }
        guard let workoutID else { finishLoading(key, result: []); return }
        guard let ownerID = key.ownerID else {
            loadState.fail(key, protected: true); return
        }
        guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else {
            if key == loadIdentity { loaded = []; loadState.fail(key) }
            return
        }
        do {
            let result = try await WorkoutPhotoService(client: client).load(workoutID: workoutID, ownerID: ownerID)
            try Task.checkCancellation()
            guard key == loadIdentity else { return }
            finishLoading(key, result: result)
        } catch {
            guard !Task.isCancelled, key == loadIdentity else { return }
            loaded = []; loadState.fail(key)
        }
    }

    @MainActor private func finishLoading(_ key: WorkoutPhotoLoadIdentity,
                                         result: [WorkoutPhotoReference], knownPhotoIDs: Set<UUID>? = nil) {
        guard key == loadIdentity else { return }
        var next = loadState
        guard next.complete(key) else { return }
        WorkoutPhotoLayoutHints.shared.record(!result.isEmpty, for: key)
        if result != loaded { loaded = result }
        let retained = ratios.filter { (knownPhotoIDs ?? Set(result.map(\.id))).contains($0.key) }
        if retained != ratios { ratios = retained }
        loadState = next
    }

    @ViewBuilder private func tappableMedia<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        if let onOpenPhoto {
            Button(action: onOpenPhoto) {
                content().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("운동 상세 보기")
            .accessibilityIdentifier("workout.card.open.\(name)")
        } else { content() }
    }


}

/// The dismissal transform belongs to the whole black presentation surface.
/// Photo zoom and horizontal paging are handled by their own UIKit scroll views.
struct WorkoutPhotoDismissal: Equatable {
    static let minimumScale: CGFloat = 0.93
    let scale: CGFloat
    let translation: CGFloat
    let isArmed: Bool

    static func state(drag: CGFloat, height: CGFloat) -> Self {
        guard drag.isFinite, height.isFinite, height > 0 else {
            return Self(scale: 1, translation: 0, isArmed: false)
        }
        let distance = max(0, drag)
        let shrinkDistance = height * 0.12
        let progress = min(1, distance / shrinkDistance)
        let translation = max(0, distance - shrinkDistance)
        return Self(scale: 1 - (1 - minimumScale) * progress,
                    translation: translation, isArmed: translation >= height * 0.05)
    }

    static func canBegin(velocity: CGPoint, zoomScale: CGFloat) -> Bool {
        zoomScale <= 1.01 && velocity.y > 0 && velocity.y > abs(velocity.x) * 1.2
    }
}

extension View {
    /// `overFullScreen` retains the presenting feed/detail underneath the clear
    /// root view, so shrinking the black surface reveals the actual screen.
    func workoutPhotoGallery(photos: [WorkoutPhotoReference], selection: Binding<WorkoutPhotoReference?>) -> some View {
        background(WorkoutPhotoGalleryPresenter(photos: photos, selection: selection))
    }
}

private struct WorkoutPhotoGalleryPresenter: UIViewControllerRepresentable {
    let photos: [WorkoutPhotoReference]
    @Binding var selection: WorkoutPhotoReference?
    @EnvironmentObject private var auth: AuthViewModel

    func makeUIViewController(context: Context) -> WorkoutPhotoPresentationAnchor {
        WorkoutPhotoPresentationAnchor()
    }

    func updateUIViewController(_ anchor: WorkoutPhotoPresentationAnchor, context: Context) {
        anchor.update(photos: photos, selection: selection, auth: auth) { selection = nil }
    }

    static func dismantleUIViewController(_ anchor: WorkoutPhotoPresentationAnchor, coordinator: ()) {
        anchor.close()
    }
}

private final class WorkoutPhotoPresentationAnchor: UIViewController {
    private var pending: (() -> Void)?
    private var gallery: WorkoutPhotoGalleryController?

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pending?()
        pending = nil
    }

    func update(photos: [WorkoutPhotoReference], selection: WorkoutPhotoReference?, auth: AuthViewModel,
                onClose: @escaping () -> Void) {
        guard let selection, photos.contains(where: { $0.id == selection.id }) else { close(); return }
        guard gallery == nil else { return }
        let show = { [weak self] in
            guard let self, self.gallery == nil, self.view.window != nil else { return }
            let gallery = WorkoutPhotoGalleryController(photos: photos, selectedID: selection.id, auth: auth) { [weak self] in
                self?.close()
                onClose()
            }
            self.gallery = gallery
            gallery.modalPresentationStyle = .overFullScreen
            gallery.modalPresentationCapturesStatusBarAppearance = true
            self.present(gallery, animated: false)
        }
        if view.window != nil { show() } else { pending = show }
    }

    func close() {
        pending = nil
        gallery?.dismiss(animated: false)
        gallery = nil
    }
}

private final class WorkoutPhotoGalleryController: UIViewController, UIPageViewControllerDataSource,
    UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
    private let photos: [WorkoutPhotoReference]
    private let auth: AuthViewModel
    private let onClose: () -> Void
    private var selectedIndex: Int
    private var pages: [Int: WorkoutZoomPhotoController] = [:]
    private let surface = UIView()
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private let closeButton = UIButton(type: .system)
    private let dots = UIPageControl()
    private let dotsBackground = UIView()
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private var armed = false
    private var isClosing = false
    private var transitioning = false
    private lazy var dismissPan = UIPanGestureRecognizer(target: self, action: #selector(dragSurface(_:)))
    private var pagingScrollView: UIScrollView? { pager.view.subviews.compactMap { $0 as? UIScrollView }.first }
    private var currentPhoto: WorkoutZoomPhotoController? { pager.viewControllers?.first as? WorkoutZoomPhotoController }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    init(photos: [WorkoutPhotoReference], selectedID: UUID, auth: AuthViewModel, onClose: @escaping () -> Void) {
        self.photos = photos
        self.auth = auth
        self.onClose = onClose
        selectedIndex = photos.firstIndex(where: { $0.id == selectedID }) ?? 0
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        surface.backgroundColor = .black
        surface.clipsToBounds = true
        view.addSubview(surface)
        addChild(pager)
        surface.addSubview(pager.view)
        pager.didMove(toParent: self)
        pager.view.backgroundColor = .clear
        pager.dataSource = self
        pager.delegate = self
        pager.setViewControllers([page(at: selectedIndex)], direction: .forward, animated: false)

        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 24
        closeButton.accessibilityLabel = "사진 닫기"
        closeButton.accessibilityIdentifier = "workout.photo.close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        surface.addSubview(closeButton)
        dots.numberOfPages = photos.count
        dots.currentPage = selectedIndex
        dots.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.45)
        dots.currentPageIndicatorTintColor = .white
        dots.hidesForSinglePage = true
        dots.accessibilityLabel = "사진 탐색"
        dots.addTarget(self, action: #selector(pageSelected), for: .valueChanged)
        dotsBackground.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        dotsBackground.layer.cornerRadius = 15
        surface.addSubview(dotsBackground)
        surface.addSubview(dots)
        dismissPan.delegate = self
        dismissPan.maximumNumberOfTouches = 1
        surface.addGestureRecognizer(dismissPan)
        pagingScrollView?.panGestureRecognizer.require(toFail: dismissPan)
        view.accessibilityViewIsModal = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Avoid assigning a transformed frame during an interactive dismissal.
        surface.bounds = view.bounds
        surface.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        pager.view.frame = surface.bounds
        closeButton.frame = CGRect(x: 18, y: view.safeAreaInsets.top + 12, width: 48, height: 48)
        let dotWidth = max(50, dots.size(forNumberOfPages: photos.count).width + 8)
        dots.frame = CGRect(x: (view.bounds.width - dotWidth) / 2,
                            y: view.bounds.height - view.safeAreaInsets.bottom - 42, width: dotWidth, height: 30)
        dotsBackground.frame = dots.frame
        dotsBackground.isHidden = photos.count < 2
    }

    private func page(at index: Int) -> WorkoutZoomPhotoController {
        if let existing = pages[index] { return existing }
        let page = WorkoutZoomPhotoController(photo: photos[index], index: index, auth: auth)
        page.onZoomChanged = { [weak self, weak page] zoomed in
            guard let self, self.currentPhoto === page else { return }
            self.pagingScrollView?.isScrollEnabled = !zoomed
        }
        pages[index] = page
        return page
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? WorkoutZoomPhotoController, page.index > 0 else { return nil }
        return self.page(at: page.index - 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? WorkoutZoomPhotoController, page.index + 1 < photos.count else { return nil }
        return self.page(at: page.index + 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        transitioning = true
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        transitioning = false
        guard completed, let page = currentPhoto else { return }
        selectedIndex = page.index
        dots.currentPage = selectedIndex
        previousViewControllers.compactMap { $0 as? WorkoutZoomPhotoController }.forEach { $0.resetZoom() }
        pagingScrollView?.isScrollEnabled = page.zoomScale <= 1.01
    }

    @objc private func pageSelected() {
        guard !transitioning, !isClosing else { return }
        let next = dots.currentPage
        guard next != selectedIndex else { return }
        currentPhoto?.resetZoom()
        transitioning = true
        pager.setViewControllers([page(at: next)], direction: next > selectedIndex ? .forward : .reverse, animated: true) { [weak self] _ in
            guard let self else { return }
            self.transitioning = false
            self.selectedIndex = self.currentPhoto?.index ?? next
            self.dots.currentPage = self.selectedIndex
            self.pagingScrollView?.isScrollEnabled = (self.currentPhoto?.zoomScale ?? 1) <= 1.01
        }
    }

    override func accessibilityPerformEscape() -> Bool {
        closeTapped()
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan, !transitioning, !isClosing,
              currentPhoto?.isZoomInteracting != true else { return false }
        return WorkoutPhotoDismissal.canBegin(velocity: dismissPan.velocity(in: view), zoomScale: currentPhoto?.zoomScale ?? 1)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touched: UIView? = touch.view
        while let target = touched {
            if target is UIControl { return false }
            touched = target.superview
        }
        return true
    }

    @objc private func dragSurface(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            feedback.prepare()
            pagingScrollView?.isScrollEnabled = false
            currentPhoto?.setZoomInteractionEnabled(false)
            fallthrough
        case .changed:
            let state = WorkoutPhotoDismissal.state(drag: pan.translation(in: view).y, height: view.bounds.height)
            if state.isArmed != armed {
                armed = state.isArmed
                feedback.impactOccurred(intensity: 0.65)
                feedback.prepare()
            }
            surface.transform = CGAffineTransform(translationX: 0, y: state.translation).scaledBy(x: state.scale, y: state.scale)
            surface.layer.cornerRadius = (1 - state.scale) / (1 - WorkoutPhotoDismissal.minimumScale) * 24
        case .ended:
            if armed { finishDismissal() } else { restoreSurface() }
        case .cancelled, .failed:
            restoreSurface()
        default: break
        }
    }

    private func restoreSurface() {
        armed = false
        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.surface.transform = .identity
            self.surface.layer.cornerRadius = 0
        } completion: { _ in
            self.currentPhoto?.setZoomInteractionEnabled(true)
            self.pagingScrollView?.isScrollEnabled = (self.currentPhoto?.zoomScale ?? 1) <= 1.01
        }
    }

    private func finishDismissal() {
        guard !isClosing else { return }
        isClosing = true
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.surface.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                .scaledBy(x: WorkoutPhotoDismissal.minimumScale, y: WorkoutPhotoDismissal.minimumScale)
        } completion: { _ in self.onClose() }
    }
    @objc private func closeTapped() {
        guard !isClosing else { return }
        isClosing = true
        UIView.animate(withDuration: 0.18, animations: { self.surface.alpha = 0 }) { _ in self.onClose() }
    }
}

/// Image-only scroll content prevents zooming and panning into letterbox space.
enum WorkoutPhotoZoomLayout {
    static func fittedImageSize(image: CGSize, viewport: CGSize) -> CGSize {
        guard image.width.isFinite, image.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite,
              image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let fit = min(viewport.width / image.width, viewport.height / image.height)
        return CGSize(width: image.width * fit, height: image.height * fit)
    }

    static func centeringInsets(content: CGSize, viewport: CGSize) -> UIEdgeInsets {
        let horizontal = max(0, (viewport.width - content.width) / 2)
        let vertical = max(0, (viewport.height - content.height) / 2)
        return UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
}

private final class WorkoutZoomPhotoController: UIViewController, UIScrollViewDelegate {
    let index: Int
    let photo: WorkoutPhotoReference
    private let auth: AuthViewModel
    private let scroll = UIScrollView()
    private let imageView = UIImageView()
    private var loader: UIViewController?
    private var previousSize = CGSize.zero
    var onZoomChanged: ((Bool) -> Void)?
    var zoomScale: CGFloat { scroll.zoomScale }
    var isZoomInteracting: Bool { scroll.isZooming || scroll.isZoomBouncing }

    init(photo: WorkoutPhotoReference, index: Int, auth: AuthViewModel) {
        self.photo = photo; self.index = index; self.auth = auth
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let content = WorkoutPhotoImage(photo: photo, contentMode: .fit, onImageLoaded: { [weak self] image in
            guard let self else { return }
            self.imageView.image = image
            self.scroll.isHidden = image == nil
            self.layoutPhoto()
        }, placeholderBackground: .black)
            .environmentObject(auth)
            .environment(\.colorScheme, .dark)
        let loader = UIHostingController(rootView: content)
        loader.view.backgroundColor = .clear
        addChild(loader); view.addSubview(loader.view); loader.didMove(toParent: self)
        self.loader = loader
        scroll.backgroundColor = .black
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.delegate = self
        scroll.isHidden = true
        scroll.panGestureRecognizer.isEnabled = false
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "운동 사진"
        imageView.accessibilityHint = "두 번 탭하거나 두 손가락으로 확대할 수 있어요"
        scroll.addSubview(imageView)
        view.addSubview(scroll)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        loader?.view.frame = view.bounds
        scroll.frame = view.bounds
        if previousSize != view.bounds.size {
            previousSize = view.bounds.size
            layoutPhoto()
        }
    }

    private func layoutPhoto() {
        resetZoom()
        let imageSize = imageView.image?.size ?? .zero
        let fitted = WorkoutPhotoZoomLayout.fittedImageSize(image: imageSize, viewport: scroll.bounds.size)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scroll.contentSize = fitted
        centerPhoto()
        scroll.contentOffset = CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top)
    }

    private func centerPhoto() {
        scroll.contentInset = WorkoutPhotoZoomLayout.centeringInsets(content: scroll.contentSize,
                                                                     viewport: scroll.bounds.size)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        onZoomChanged?(true)
    }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        onZoomChanged?(scale > 1.01)
    }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerPhoto()
        let zoomed = scrollView.zoomScale > 1.01
        scrollView.panGestureRecognizer.isEnabled = zoomed
        onZoomChanged?(zoomed || scrollView.isZooming)
    }
    func resetZoom() { scroll.setZoomScale(1, animated: false) }
    func setZoomInteractionEnabled(_ enabled: Bool) {
        scroll.pinchGestureRecognizer?.isEnabled = enabled
        if !enabled { scroll.panGestureRecognizer.isEnabled = false }
    }
    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if scroll.zoomScale > 1.01 { scroll.setZoomScale(1, animated: true) }
        else {
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
            scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}

struct WorkoutPhotoPageDots: View {
    let photos: [WorkoutPhotoReference]
    @Binding var selectedID: UUID

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                Button { selectedID = photo.id } label: {
                    Circle()
                        .fill(photo.id == selectedID ? .white : .white.opacity(0.45))
                        .frame(width: photo.id == selectedID ? 7 : 6, height: photo.id == selectedID ? 7 : 6)
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("사진 \(index + 1)")
                .accessibilityAddTraits(photo.id == selectedID ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.black.opacity(0.58), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("사진 탐색")
    }
}

extension WorkoutMediaStripGeometry {
    func visibleFraction(at index: Int, offset: CGFloat) -> CGFloat {
        guard frames.indices.contains(index), offset.isFinite, viewportWidth > 0,
              frames[index].width > 0 else { return 0 }
        let window = CGRect(x: offset, y: 0, width: viewportWidth, height: frames[index].height)
        return max(0, min(1, frames[index].intersection(window).width / frames[index].width))
    }
}


/// Layout hint only, never a metadata response or an access grant. Every new row
/// still validates metadata. Confirmed absence avoids a repeated 260->0 placeholder.
@MainActor
final class WorkoutPhotoLayoutHints {
    static let shared = WorkoutPhotoLayoutHints()
    private var owner: UUID?
    private var generation: Int?
    private var values: [UUID: Bool] = [:]
    private var order: [UUID] = []
    private let capacity: Int
    init(capacity: Int = 128) { self.capacity = max(1, capacity) }
    var count: Int { values.count }
    func clear() { values = [:]; order = [] }
    private func scope(_ key: WorkoutPhotoLoadIdentity) {
        if owner != key.ownerID || generation != key.accountGeneration {
            clear(); owner = key.ownerID; generation = key.accountGeneration
        }
    }
    func hasPhotos(for key: WorkoutPhotoLoadIdentity) -> Bool? {
        scope(key); guard let id = key.workoutID else { return nil }; return values[id]
    }
    func record(_ present: Bool, for key: WorkoutPhotoLoadIdentity) {
        scope(key); guard let id = key.workoutID else { return }
        values[id] = present; order.removeAll { $0 == id }; order.append(id)
        if order.count > capacity { values.removeValue(forKey: order.removeFirst()) }
    }
}
