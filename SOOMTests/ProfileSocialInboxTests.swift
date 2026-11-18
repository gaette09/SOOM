import XCTest
@testable import SOOM

@MainActor private final class SocialInboxStub: ProfileSocialInboxTransport {
    var payload = Data()
    var statePayload = Data()
    var beforeRead: (() -> Void)?
    var cardResponse: AccountActivityCardEnvelope?
    var cardReads = 0
    var reads = 0
    var writes: [(String, UUID, String)] = []
    func inbox(limit: Int) async throws -> Data { reads += 1; beforeRead?(); return payload }
    func state(source: String, eventID: UUID, action: String) async throws -> Data { writes.append((source, eventID, action)); return statePayload }
    func card(id: UUID) async throws -> AccountActivityCardEnvelope { cardReads += 1; guard let cardResponse else { throw ProfileActivitySocialError.changed }; return cardResponse }
}
@MainActor final class ProfileSocialInboxTests: XCTestCase {
    private let viewer = UUID(uuidString: "CC000000-0000-4000-8000-000000000001")!
    private let actor = UUID(uuidString: "CC000000-0000-4000-8000-000000000002")!
    private let card = UUID(uuidString: "CC000000-0000-4000-8000-000000000003")!
    private let event = UUID(uuidString: "CC000000-0000-4000-8000-000000000004")!
    private let source = UUID(uuidString: "CC000000-0000-4000-8000-000000000005")!
    private let at = "2026-11-01T00:00:00Z"
    private var context: AccountActivityReadContext { .init(viewerID: viewer, generation: 1, safetyRevision: 2) }
    private var receipt: [String: Any] { ["version": 2, "viewer_id": viewer.uuidString, "card_id": card.uuidString,
        "owner_id": viewer.uuidString, "canonical_id": card.uuidString, "projection_revision": 1, "profile_revision": 1,
        "backing": "legacy", "source_id": source.uuidString, "release_ready": false, "write_backing":"legacy", "read_sources":[["source_kind":"legacy","source_id":source.uuidString]], "source_revision":String(repeating:"a",count:32)] }
    private func row(_ kind: String = "legacy") -> [String: Any] {
        ["source_kind": kind, "event_id": event.uuidString, "recipient_id": viewer.uuidString, "actor_id": actor.uuidString,
         "card_id": card.uuidString, "comment_id": NSNull(), "reason": "comment", "created_at": at,
         "read_at": NSNull(), "receipt": receipt, "actor_profile": NSNull()]
    }
    private func envelope(_ rows: [[String: Any]], unread: Int? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 2, "viewer_id": viewer.uuidString, "release_ready": false,
            "rows": rows, "unread_count": unread ?? rows.count, "push_delivery": "unchanged_no_new_scope_push"])
    }
    private func state(_ kind: String = "legacy", hidden: Any = NSNull()) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 2, "viewer_id": viewer.uuidString, "source_kind": kind,
            "event_id": event.uuidString, "card_id": card.uuidString, "receipt": receipt, "read_at": NSNull(),
            "hidden_at": hidden, "release_ready": false])
    }
    private func make(_ stub: SocialInboxStub) -> ProfileSocialInboxAdapter {
        .localFixture(transport: stub, context: { self.context })
    }
    func testValidTypedLegacyInboxDoesNotFetchDetail() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row()])
        let value = try await make(stub).load()
        XCTAssertEqual(value.rows.count, 1); XCTAssertEqual(stub.reads, 1); XCTAssertTrue(stub.writes.isEmpty)
    }
    func testFixtureOpenReturnsCardAfterFreshReceiptWithoutDetailOrMutation() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row("profile_social_v2")])
        let projection = AccountActivityFeedRow(cardID: card, canonicalID: card, ownerID: viewer,
            sport: "running", activityAt: at, durationSeconds: 600, distanceMeters: 1500,
            revision: 1, readPolicy: .profileOnlyV2)
        stub.cardResponse = .init(version: 2, viewerID: viewer, row: projection, releaseReady: false)
        let api = make(stub)
        let loaded = try await api.load()
        let event = try XCTUnwrap(loaded.rows.first)
        let result = try await api.open(event)
        XCTAssertEqual(result.cardID, card); XCTAssertEqual(result.canonicalID, card)
        XCTAssertEqual(stub.reads, 3); XCTAssertEqual(stub.cardReads, 1)
        XCTAssertTrue(stub.writes.isEmpty)
    }
    func testSameUUIDAcrossSourcesRemainsTwoTypedEvents() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row("approved_v2"), row("legacy")])
        let value = try await make(stub).load()
        XCTAssertEqual(Set(value.rows.map(\.id)).count, 2)
    }
    func testDuplicateTypedEventRejected() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row(), row()])
        do { _ = try await make(stub).load(); XCTFail() } catch { }
    }
    func testWrongRecipientRejected() async throws {
        var r = row(); r["recipient_id"] = actor.uuidString
        let stub = SocialInboxStub(); stub.payload = try envelope([r])
        do { _ = try await make(stub).load(); XCTFail() } catch { }
    }
    func testWrongReceiptViewerRejected() async throws {
        var r = row(); var p = receipt; p["viewer_id"] = actor.uuidString; r["receipt"] = p
        let stub = SocialInboxStub(); stub.payload = try envelope([r])
        do { _ = try await make(stub).load(); XCTFail() } catch { }
    }
    func testNativeSourceMismatchRejected() async throws {
        var r = row(); var p = receipt; p["backing"] = "native"; r["receipt"] = p
        let stub = SocialInboxStub(); stub.payload = try envelope([r])
        do { _ = try await make(stub).load(); XCTFail() } catch { }
    }
    func testUnknownSourceRejected() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row("made_up")])
        do { _ = try await make(stub).load(); XCTFail() } catch { }
    }
    func testFutureReadTimeRejected() async throws {
        var r = row(); r["read_at"] = "2099-01-01T00:00:00Z"
        let stub = SocialInboxStub(); stub.payload = try envelope([r])
        do { _ = try await make(stub).load(); XCTFail() } catch { }
    }
    func testUnreadCannotBeLessThanVisibleUnreadRows() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row()], unread: 0)
        do { _ = try await make(stub).load(); XCTFail() } catch { }
    }
    func testAccountChangeDiscardsResponse() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row()]); var c: AccountActivityReadContext? = context
        stub.beforeRead = { c = nil }
        let api = ProfileSocialInboxAdapter.localFixture(transport: stub, context: { c })
        do { _ = try await api.load(); XCTFail() } catch { }
    }
    func testHideUsesTypedKeyAndReturnsFreshSnapshot() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row()]); let api = make(stub)
        let event = try await api.load().rows[0]
        stub.payload = try envelope([]); stub.statePayload = try state(hidden: "2026-11-02T00:00:00Z")
        let result = try await api.change(event, action: "hide")
        XCTAssertTrue(result.rows.isEmpty); XCTAssertEqual(stub.writes.count, 1)
        XCTAssertEqual(stub.writes[0].0, "legacy"); XCTAssertEqual(stub.writes[0].2, "hide")
    }
    func testMismatchedStateNamespaceRejectedWithoutSecondWrite() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row()]); let api = make(stub)
        let event = try await api.load().rows[0]; stub.statePayload = try state("approved_v2", hidden: "2026-11-02T00:00:00Z")
        do { _ = try await api.change(event, action: "hide"); XCTFail() } catch { }
        XCTAssertEqual(stub.writes.count, 1)
    }
    func testRevokedEventDoesNotOpenCard() async throws {
        let stub = SocialInboxStub(); stub.payload = try envelope([row()]); let api = make(stub)
        let event = try await api.load().rows[0]; stub.payload = try envelope([])
        do { _ = try await api.open(event); XCTFail() } catch { }
    }
    func testAvatarRequiresFreshMatchingBindingAndOwnerPath() {
        let path = viewer.uuidString.lowercased() + "/" + event.uuidString.lowercased() + ".jpg"
        let object = FeedReturnStorageObject(bucket: "profile-avatars", path: path, objectID: event,
            version: "v1", etag: nil, updatedAt: nil, size: 500, versionHash: nil)
        let row = AccountActivityFeedRow(cardID: card, canonicalID: card, ownerID: viewer, sport: "running",
            activityAt: at, durationSeconds: 1, distanceMeters: 1, revision: 1, readPolicy: .profileOnlyV2)
        let grant = FeedReturnCardGrant(id: card, row: row, author: nil, authorRevision: nil, avatarObject: object,
            photos: [], photoObjects: [:], photosAvailable: false, socialStatus: nil)
        let binding = FeedReturnBatchContext(viewerID: viewer, accountGeneration: 1, safetyRevision: 2, returnEpoch: 3)
        let ready = FeedReturnBatchPresentation(id: UUID(), context: binding, phase: .ready, grants: [card: grant])
        XCTAssertEqual(FeedAvatarReusePolicy.object(presentation: ready, ownerID: viewer, path: path, viewerID: viewer,
            generation: 1, safetyRevision: 2, returnEpoch: 3, active: true), object)
        for (id, gen, revision, epoch, active) in [(actor,1,2,3,true),(viewer,2,2,3,true),(viewer,1,3,3,true),(viewer,1,2,4,true),(viewer,1,2,3,false)] {
            XCTAssertNil(FeedAvatarReusePolicy.object(presentation: ready, ownerID: viewer, path: path, viewerID: id,
                generation: gen, safetyRevision: revision, returnEpoch: epoch, active: active))
        }
        var pending = ready; pending.phase = .pending
        XCTAssertNil(FeedAvatarReusePolicy.object(presentation: pending, ownerID: viewer, path: path, viewerID: viewer,
            generation: 1, safetyRevision: 2, returnEpoch: 3, active: true))
        pending.phase = .failed
        XCTAssertNil(FeedAvatarReusePolicy.object(presentation: pending, ownerID: viewer, path: path, viewerID: viewer,
            generation: 1, safetyRevision: 2, returnEpoch: 3, active: true))
        XCTAssertNil(FeedAvatarReusePolicy.object(presentation: ready, ownerID: actor, path: path, viewerID: viewer,
            generation: 1, safetyRevision: 2, returnEpoch: 3, active: true))
    }
    func testAvatarThumbnailIsBoundedAndRejectsOversizedData() throws {
        let data = try XCTUnwrap(ReviewDemoAvatarStore.sampleImageData())
        let pixels = try XCTUnwrap(FeedAvatarImageCache.thumbnail(data))
        XCTAssertLessThanOrEqual(pixels.width, 256); XCTAssertLessThanOrEqual(pixels.height, 256)
        XCTAssertNil(FeedAvatarImageCache.thumbnail(Data(count: ProfileAvatarPolicy.maximumBytes + 1)))
        XCTAssertNil(FeedAvatarImageCache.thumbnail(Data()))
    }
}
