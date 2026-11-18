import XCTest
@testable import SOOM

@MainActor final class Feed60SocialPresentationStoreTests: XCTestCase {
    private func authority() -> FeedLinkedCardAuthority {
        .init(context: .init(viewerID: UUID(), accountGeneration: 1, safetyRevision: 2, returnEpoch: 3),
              batchID: UUID(), grantID: UUID(), row: .init(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(),
              sport: "running", activityAt: "2026-01-01T00:00:00Z", durationSeconds: 60, distanceMeters: 100,
              revision: 1, readPolicy: .profileOnlyV2))
    }
    private func status(_ a: FeedLinkedCardAuthority, cheered: Bool) -> ProfileActivitySocialStatus {
        .init(receipt: .init(version: 2, viewer_id: a.context.viewerID, card_id: a.row.cardID,
            owner_id: a.row.ownerID, canonical_id: a.row.canonicalID, projection_revision: a.row.revision,
            profile_revision: 1, backing: "native", source_id: a.row.cardID, release_ready: true),
            state: "ready", comment_count: 2, latest_comment_at: nil, cheer_count: cheered ? 1 : 0, viewer_has_cheered: cheered)
    }
    private func batch(_ a: FeedLinkedCardAuthority) -> FeedReturnBatchPresentation {
        .init(id: a.batchID, context: a.context, phase: .ready, grants: [a.row.cardID:
            .init(id: a.grantID, row: a.row, author: nil, authorRevision: nil, avatarObject: nil,
            photos: [], photoObjects: [:], photosAvailable: false, socialStatus: status(a, cheered: false))])
    }
    func testRecreatedCardChoosesFreshOverrideNotInitialBatchStatus() throws {
        let store = Feed60SocialPresentationStore(), a = authority()
        let stale = status(a, cheered: false)
        // Use the actual authority for the mutation's independently validated status.
        XCTAssertNil(store.resident(a, isCurrent: { true }))
        let token = try XCTUnwrap(store.begin(a, isCurrent: { true }))
        let fresh = status(a, cheered: true)
        XCTAssertTrue(store.finish(a, requestID: token, status: fresh, isCurrent: { true }))
        XCTAssertEqual(store.resident(a, isCurrent: { true }), .ready(fresh))
        XCTAssertNotEqual(fresh.viewer_has_cheered, stale.viewer_has_cheered)
    }
    func testBeginAndFailureRemainUnknownRatherThanFalseOrAbsent() throws {
        let store = Feed60SocialPresentationStore(), a = authority()
        let token = try XCTUnwrap(store.begin(a, isCurrent: { true }))
        XCTAssertEqual(store.resident(a, isCurrent: { true }), .unknown)
        XCTAssertTrue(store.finish(a, requestID: token, status: nil, isCurrent: { true }))
        XCTAssertEqual(store.resident(a, isCurrent: { true }), .unknown)
        XCTAssertFalse(store.finish(a, requestID: token, status: status(a, cheered: true), isCurrent: { true }))
    }
    func testNewRequestAndUnknownSupersedeOlderSuccess() throws {
        let store = Feed60SocialPresentationStore(), a = authority()
        let old = try XCTUnwrap(store.begin(a, isCurrent: { true }))
        let current = try XCTUnwrap(store.markUnknown(a, isCurrent: { true }))
        XCTAssertFalse(store.finish(a, requestID: old, status: status(a, cheered: true), isCurrent: { true }))
        XCTAssertEqual(store.resident(a, isCurrent: { true }), .unknown)
        let newest = status(a, cheered: false)
        XCTAssertTrue(store.finish(a, requestID: current, status: newest, isCurrent: { true }))
        XCTAssertFalse(store.finish(a, requestID: old, status: status(a, cheered: true), isCurrent: { true }))
        XCTAssertEqual(store.resident(a, isCurrent: { true }), .ready(newest))
    }
    func testCurrentReferenceGateAndChangedGrantNeverRestoreOverride() throws {
        let store = Feed60SocialPresentationStore(), a = authority()
        let token = try XCTUnwrap(store.begin(a, isCurrent: { true }))
        XCTAssertFalse(store.finish(a, requestID: token, status: status(a, cheered: true), isCurrent: { false }))
        XCTAssertNil(store.resident(a, isCurrent: { false }))
        XCTAssertNil(store.begin(a, isCurrent: { false }))
        let changed = FeedLinkedCardAuthority(context: a.context, batchID: a.batchID, grantID: UUID(), row: a.row)
        XCTAssertNil(store.resident(changed, isCurrent: { true }))
        XCTAssertFalse(store.finish(changed, requestID: token, status: status(changed, cheered: true), isCurrent: { true }))
    }
    func testRetainPrunesDeniedChangedGrantAndPendingContext() throws {
        let store = Feed60SocialPresentationStore(), a = authority()
        _ = store.begin(a, isCurrent: { true })
        store.retain(using: batch(a)); XCTAssertEqual(store.count, 1)
        var denied = batch(a); denied.denied.insert(a.row.cardID)
        store.retain(using: denied); XCTAssertEqual(store.count, 0)
        _ = store.begin(a, isCurrent: { true })
        let changed = FeedLinkedCardAuthority(context: a.context, batchID: a.batchID, grantID: UUID(), row: a.row)
        store.retain(using: batch(changed)); XCTAssertEqual(store.count, 0)
        _ = store.begin(a, isCurrent: { true })
        var pending = batch(a); pending.phase = .pending
        store.retain(using: pending); XCTAssertEqual(store.count, 0)
    }
    func testClearAndChangedEpochRejectLateCompletions() throws {
        let store = Feed60SocialPresentationStore(), a = authority()
        let token = try XCTUnwrap(store.begin(a, isCurrent: { true }))
        store.clear()
        XCTAssertFalse(store.finish(a, requestID: token, status: status(a, cheered: true), isCurrent: { true }))
        XCTAssertNil(store.resident(a, isCurrent: { true }))
        let changed = FeedLinkedCardAuthority(context: .init(viewerID: a.context.viewerID,
            accountGeneration: 1, safetyRevision: 2, returnEpoch: 4), batchID: UUID(), grantID: UUID(), row: a.row)
        _ = store.begin(changed, isCurrent: { true })
        XCTAssertNil(store.resident(a, isCurrent: { true }))
        XCTAssertEqual(store.resident(changed, isCurrent: { true }), .unknown)
    }
    func testWrongStatusIdentityCannotCommitEvenWithCurrentToken() throws {
        let store = Feed60SocialPresentationStore(), a = authority()
        let token = try XCTUnwrap(store.begin(a, isCurrent: { true }))
        XCTAssertFalse(store.finish(a, requestID: token, status: status(authority(), cheered: true), isCurrent: { true }))
        XCTAssertEqual(store.resident(a, isCurrent: { true }), .unknown)
    }
    func testMemoryPressurePurgesValuesButKeepsUnknownFenceAndRejectsLateCompletion() throws {
        let store = Feed60SocialPresentationStore(), a = authority()
        let token = try XCTUnwrap(store.begin(a, isCurrent: { true }))
        store.purgeForMemoryPressure()
        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(store.resident(a, isCurrent: { true }), .unknown)
        XCTAssertFalse(store.finish(a, requestID: token, status: status(a, cheered: true), isCurrent: { true }))
        store.retain(using: batch(a))
        XCTAssertEqual(store.resident(a, isCurrent: { true }), .unknown)
        let fresh = try XCTUnwrap(store.begin(a, isCurrent: { true }))
        XCTAssertTrue(store.finish(a, requestID: fresh, status: status(a, cheered: true), isCurrent: { true }))
        XCTAssertEqual(store.resident(a, isCurrent: { true }), .ready(status(a, cheered: true)))
    }
    func testOverflowStaysBoundedWithoutResurrectingEvictedStaleBatchState() throws {
        let store = Feed60SocialPresentationStore(), first = authority()
        let token = try XCTUnwrap(store.begin(first, isCurrent: { true }))
        XCTAssertTrue(store.finish(first, requestID: token, status: status(first, cheered: true), isCurrent: { true }))
        for _ in 0..<64 {
            let another = authority()
            let a = FeedLinkedCardAuthority(context: first.context, batchID: first.batchID, grantID: another.grantID, row: another.row)
            _ = store.begin(a, isCurrent: { true })
        }
        XCTAssertEqual(store.count, 64)
        XCTAssertEqual(store.resident(first, isCurrent: { true }), .unknown)
        XCTAssertNil(store.resident(first, isCurrent: { false }))
        store.clear(); XCTAssertNil(store.resident(first, isCurrent: { true }))
    }
}
