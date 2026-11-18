import XCTest
@testable import SOOM

@MainActor final class Feed60PhotoResidentTests: XCTestCase {
    private struct Fixture {
        let batch: FeedReturnBatchPresentation
        let photo: WorkoutPhotoReference
        let object: FeedReturnStorageObject
        var authority: FeedLinkedCardAuthority {
            let grant = batch.grants[photo.profileAuthority!.cardID]!
            return .init(context: batch.context, batchID: batch.id, grantID: grant.id, row: grant.row)
        }
    }
    private func fixture(version: String = "v1") -> Fixture {
        let viewer = UUID(), owner = UUID(), card = UUID(), canonical = UUID(), source = UUID(), id = UUID()
        let authority = AccountActivityProfilePhotoAuthority(cardID: card, ownerID: owner, sourceID: source,
            bucket: "workout-photos", projectionRevision: 1, profileRevision: 2)
        let photo = WorkoutPhotoReference(id: id, storagePath: WorkoutPhotoPolicy.path(ownerID: owner, postID: source, photoID: id), profileAuthority: authority)
        let object = FeedReturnStorageObject(bucket: "workout-photos", path: photo.storagePath, objectID: id,
            version: version, etag: nil, updatedAt: nil, size: 100, versionHash: nil)
        let row = AccountActivityFeedRow(cardID: card, canonicalID: canonical, ownerID: owner, sport: "running",
            activityAt: "2026-01-01T00:00:00Z", durationSeconds: 60, distanceMeters: 100, revision: 1, readPolicy: .profileOnlyV2)
        let grant = FeedReturnCardGrant(id: UUID(), row: row, author: nil, authorRevision: nil, avatarObject: nil,
            photos: [photo], photoObjects: [photo.cacheKey: object], photosAvailable: true, socialStatus: nil)
        let batch = FeedReturnBatchPresentation(id: UUID(), context: .init(viewerID: viewer, accountGeneration: 1,
            safetyRevision: 2, returnEpoch: 3), phase: .ready, grants: [card: grant])
        return .init(batch: batch, photo: photo, object: object)
    }
    private func object(_ f: Fixture, batch: FeedReturnBatchPresentation? = nil,
                        currentBatch: Bool = true, currentGrant: Bool = true,
                        viewer: UUID? = nil, generation: Int = 1, safety: Int = 2, epoch: Int = 3) -> FeedReturnStorageObject? {
        Feed60PhotoResidentPolicy.object(batch: batch ?? f.batch, photo: f.photo,
            viewerID: viewer ?? f.batch.context.viewerID, generation: generation, safetyRevision: safety, returnEpoch: epoch,
            isBatchCurrent: { $0 == f.batch.id && currentBatch },
            isGrantCurrent: { $0 == f.authority && currentGrant })
    }
    func testExactCurrentGrantPermitsObjectButNotCapturedStaleReference() {
        let f = fixture()
        XCTAssertEqual(object(f), f.object)
        XCTAssertNil(object(f, currentBatch: false))
        XCTAssertNil(object(f, currentGrant: false))
        let old = f.batch.grants[f.authority.row.cardID]!
        let replacement = FeedReturnCardGrant(id: UUID(), row: old.row, author: old.author,
            authorRevision: old.authorRevision, avatarObject: old.avatarObject, photos: old.photos,
            photoObjects: old.photoObjects, photosAvailable: true, socialStatus: old.socialStatus)
        var sameBatchNewGrant = f.batch; sameBatchNewGrant.grants[old.row.cardID] = replacement
        XCTAssertNil(object(f, batch: sameBatchNewGrant))
    }
    func testPendingDeniedFailedAndContextChangesNeverAuthorizeResident() {
        let f = fixture()
        var pending = f.batch; pending.phase = .pending; XCTAssertNil(object(f, batch: pending))
        pending.phase = .failed; XCTAssertNil(object(f, batch: pending))
        var denied = f.batch; denied.denied.insert(f.authority.row.cardID); XCTAssertNil(object(f, batch: denied))
        XCTAssertNil(object(f, viewer: UUID()))
        XCTAssertNil(object(f, generation: 2)); XCTAssertNil(object(f, safety: 3)); XCTAssertNil(object(f, epoch: 4))
    }
    func testUnknownVersionAllowsFreshBytesButCannotFindResident() async throws {
        let f = fixture(version: "")
        let permitted = try XCTUnwrap(object(f))
        XCTAssertNil(permitted.cacheVersionToken)
        let cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 10, maximumCount: 1)
        let scope = SOOMMediaCacheScope(viewerID: f.batch.context.viewerID, accountGeneration: 1, safetyRevision: 2)
        _ = try await cache.value(for: f.photo.cacheKey, scope: scope, authorize: { nil }, load: { (1, 1) })
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: permitted.cacheVersionToken))
    }
    func testFeedVariantDoesNotReuseGalleryOrOtherDecodeSize() async throws {
        let f = fixture(), cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 10, maximumCount: 3)
        let scope = SOOMMediaCacheScope(viewerID: f.batch.context.viewerID, accountGeneration: 1, safetyRevision: 2)
        let size = try XCTUnwrap(WorkoutPhotoDecodeSize.feed(maximumWidth: 300, height: 260, displayScale: 2))
        let other = try XCTUnwrap(WorkoutPhotoDecodeSize.feed(maximumWidth: 600, height: 400, displayScale: 3))
        _ = try await cache.value(for: f.photo.cacheKey, scope: scope, variant: size.cacheVariant,
            authorize: { f.object.cacheVersionToken }, load: { (7, 1) })
        XCTAssertEqual(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: f.object.cacheVersionToken, variant: size.cacheVariant), 7)
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: f.object.cacheVersionToken, variant: other.cacheVariant))
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: f.object.cacheVersionToken))
    }
    func testPendingFeedSizeAllowsResidentButFailureInactiveAndIndependentGalleryDoNot() {
        let size = WorkoutPhotoDecodeSize.feed(maximumWidth: 300, height: 260, displayScale: 2)
        XCTAssertTrue(Feed60PhotoResidentPolicy.allowsResident(decodeSize: size, displaySizePending: false, failed: false, active: true))
        XCTAssertFalse(Feed60PhotoResidentPolicy.allowsResident(decodeSize: nil, displaySizePending: false, failed: false, active: true))
        XCTAssertTrue(Feed60PhotoResidentPolicy.allowsResident(decodeSize: size, displaySizePending: true, failed: false, active: true))
        XCTAssertTrue(Feed60PhotoResidentPolicy.allowsResident(decodeSize: nil, displaySizePending: true, failed: false, active: true))
        XCTAssertFalse(Feed60PhotoResidentPolicy.allowsResident(decodeSize: size, displaySizePending: false, failed: true, active: true))
        XCTAssertFalse(Feed60PhotoResidentPolicy.allowsResident(decodeSize: size, displaySizePending: false, failed: false, active: false))
    }
    func testAuthorizedAlternateSizeIsImmediateButExactSizeWins() async throws {
        let f = fixture(), cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 10, maximumCount: 3)
        let scope = SOOMMediaCacheScope(viewerID: f.batch.context.viewerID, accountGeneration: 1, safetyRevision: 2)
        _ = try await cache.value(for: f.photo.cacheKey, scope: scope, variant: "small",
            authorize: { "v1" }, load: { (1, 1) })
        XCTAssertEqual(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: "v1", variant: "large", allowAlternateVariant: true), 1)
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: "v1", variant: "large"))
        _ = try await cache.value(for: f.photo.cacheKey, scope: scope, variant: "large",
            authorize: { "v1" }, load: { (2, 1) })
        XCTAssertEqual(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: "v1", variant: "small", allowAlternateVariant: true), 1)
        XCTAssertNil(cache.residentValue(for: "other", scope: scope, version: "v1", allowAlternateVariant: true))
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: nil, allowAlternateVariant: true))
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: "v2", allowAlternateVariant: true))
        let otherScope = SOOMMediaCacheScope(viewerID: UUID(), accountGeneration: 1, safetyRevision: 2)
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: otherScope, version: "v1", allowAlternateVariant: true))
        cache.invalidateResource(f.photo.cacheKey)
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: "v1", allowAlternateVariant: true))
    }
    func testRevocationVersionSupersessionAndMemoryPurgeCannotRevivePixels() async throws {
        let f = fixture(), cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 10, maximumCount: 3)
        let scope = SOOMMediaCacheScope(viewerID: f.batch.context.viewerID, accountGeneration: 1, safetyRevision: 2)
        _ = try await cache.value(for: f.photo.cacheKey, scope: scope, authorize: { "v1" }, load: { (1, 1) })
        _ = try await cache.value(for: f.photo.cacheKey, scope: scope, authorize: { "v2" }, load: { (2, 1) })
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: "v1"))
        cache.invalidateResource(f.photo.cacheKey)
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: "v2"))
        _ = try await cache.value(for: f.photo.cacheKey, scope: scope, authorize: { "v3" }, load: { (3, 1) })
        cache.invalidate()
        XCTAssertNil(cache.residentValue(for: f.photo.cacheKey, scope: scope, version: "v3"))
    }
    func testIndependentPhotoWithoutProfileGrantCannotUseFeedResident() {
        let f = fixture()
        let photo = WorkoutPhotoReference(id: f.photo.id, storagePath: f.photo.storagePath)
        XCTAssertNil(Feed60PhotoResidentPolicy.object(batch: f.batch, photo: photo,
            viewerID: f.batch.context.viewerID, generation: 1, safetyRevision: 2, returnEpoch: 3,
            isBatchCurrent: { _ in true }, isGrantCurrent: { _ in true }))
    }
}
