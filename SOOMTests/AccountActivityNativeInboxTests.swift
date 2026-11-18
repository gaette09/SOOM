import XCTest
@testable import SOOM

@MainActor final class AccountActivityNativeInboxTests: XCTestCase {
    func testV2InboxOpensOnlyV2CardWithNativeIdentity() async throws {
        let f = Fixture(); f.readPolicy = .profileOnlyV2
        let adapter = AccountActivityNativeInboxAdapter(fixtureTransport: f)
        let events = try await adapter.load(context: f.context!)
        let card = try await adapter.open(events[0], context: f.context!)
        XCTAssertEqual(card.readPolicy, .profileOnlyV2)
        XCTAssertEqual(card.cardID, f.cardID)
    }
    func testV2InboxRejectsOldEnvelopeDespiteMatchingIDs() async {
        let f = Fixture(); f.readPolicy = .profileOnlyV2; f.versionOverride = 1
        do { _ = try await AccountActivityNativeInboxAdapter(fixtureTransport: f).load(context: f.context!); XCTFail() } catch {}
    }
    func testV2InboxCannotUseLegacyPreviewToBypassProductionGate() async {
        let f = Fixture(); f.readPolicy = .profileOnlyV2
        do { _ = try await AccountActivityNativeInboxAdapter(transport: f, preview: true).load(context: f.context!); XCTFail() } catch {}
        XCTAssertEqual(f.calls, 0)
    }
    func testNativeCommentsDismissalKeepsFreshlyOpenedCardDestination() async throws {
        let f = Fixture(); let adapter = AccountActivityNativeInboxAdapter(fixtureTransport: f)
        let context = f.context!
        let events = try await adapter.load(context: context)
        let row = try await adapter.open(events[0], context: context)
        var destination = NativeNotificationCardPresentation(row: row, context: context)
        destination.presentInitialComments(current: context)
        XCTAssertTrue(destination.commentsPresented)
        destination.commentsPresented = false
        XCTAssertEqual(destination.row, row)
        XCTAssertEqual(destination.row.cardID, f.cardID)
        XCTAssertTrue(destination.permits(context))
        destination.presentInitialComments(current: context)
        XCTAssertFalse(destination.commentsPresented, "returning to card must not reopen comments")
        destination.commentsPresented = true
        XCTAssertEqual(destination.row.cardID, f.cardID)
    }
    func testNativeCardDestinationRejectsChangedAccountOrSafetyContext() async throws {
        let f = Fixture(); let adapter = AccountActivityNativeInboxAdapter(fixtureTransport: f)
        let context = f.context!
        let events = try await adapter.load(context: context)
        let row = try await adapter.open(events[0], context: context)
        for current in [nil, AccountActivityReadContext(viewerID: UUID(), generation: context.generation, safetyRevision: context.safetyRevision),
                        AccountActivityReadContext(viewerID: context.viewerID, generation: context.generation + 1, safetyRevision: context.safetyRevision),
                        AccountActivityReadContext(viewerID: context.viewerID, generation: context.generation, safetyRevision: context.safetyRevision + 1)] {
            var destination = NativeNotificationCardPresentation(row: row, context: context)
            XCTAssertFalse(destination.permits(current))
            destination.presentInitialComments(current: current)
            XCTAssertFalse(destination.commentsPresented)
        }
    }
    func testExplicitPreviewUsesUnreleasedReceiptWithoutFixtureAndChecksContext() async throws {
        let f = Fixture(); let adapter = AccountActivityNativeInboxAdapter(transport: f, preview: true)
        let rows = try await adapter.load(context: f.context!)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertFalse(AccountActivityNativeInboxGate.productionReady)
        let initial = f.context!; f.changeContext = true
        do { _ = try await adapter.load(context: initial); XCTFail("stale preview context accepted") } catch {}
    }
    func testProductionNeverCallsTransport() async {
        let f = Fixture()
        do { _ = try await AccountActivityNativeInboxAdapter(transport: f).load(context: f.context!); XCTFail() } catch {}
        XCTAssertEqual(f.calls, 0)
    }
    func testFixtureValidatesTypedEventAndOpensDistinctCard() async throws {
        let f = Fixture(); let a = AccountActivityNativeInboxAdapter(fixtureTransport: f)
        let rows = try await a.load(context: f.context!)
        let row = try await a.open(rows[0], context: f.context!)
        XCTAssertEqual(row.cardID, f.cardID)
        XCTAssertNotEqual(row.cardID, rows[0].commentID)
        XCTAssertEqual(f.cardRequests, [f.cardID])
    }
    func testWrongSourceAndDuplicatesRejected() async {
        for mode in ["legacy", "duplicate", "wrongViewer", "badUnread"] {
            let f = Fixture(); f.mode = mode
            do { _ = try await AccountActivityNativeInboxAdapter(fixtureTransport: f).load(context: f.context!); XCTFail(mode) } catch {}
        }
    }
    func testAccountOrRelationshipChangeDiscardsResponse() async {
        let f = Fixture(); let initial = f.context!; f.changeContext = true
        do { _ = try await AccountActivityNativeInboxAdapter(fixtureTransport: f).load(context: initial); XCTFail() } catch {}
    }
    func testRemovedEventCannotOpenEvenIfCardStillPublic() async throws {
        let f = Fixture(); let a = AccountActivityNativeInboxAdapter(fixtureTransport: f)
        let rows = try await a.load(context: f.context!)
        f.mode = "empty"
        do { _ = try await a.open(rows[0], context: f.context!); XCTFail() } catch {}
        XCTAssertTrue(f.cardRequests.isEmpty)
    }
    func testRevocationAfterCardReadPreventsDestination() async throws {
        let f = Fixture(); let a = AccountActivityNativeInboxAdapter(fixtureTransport: f)
        let rows = try await a.load(context: f.context!); f.removeAfterCard = true
        do { _ = try await a.open(rows[0], context: f.context!); XCTFail() } catch {}
    }
    func testMutationsReadHideUndoAndAuthoritativeCount() async throws {
        let f = Fixture(); let a = AccountActivityNativeInboxAdapter(fixtureTransport: f)
        let context = f.context!, row = try await a.load(context: context)[0]
        let initialCount = try await a.unreadCount(context: context); XCTAssertEqual(initialCount, 2)
        let read = try await a.mutate(row, action: .markRead, context: context)
        XCTAssertEqual(read.unreadCount, 1); XCTAssertNotNil(read.rows.first?.readAt)
        let repeated = try await a.mutate(row, action: .markRead, context: context)
        XCTAssertEqual(repeated.unreadCount, 1); XCTAssertEqual(repeated.rows.first?.readAt, read.rows.first?.readAt)
        let hidden = try await a.mutate(row, action: .hide, context: context)
        XCTAssertTrue(hidden.rows.isEmpty)
        let restored = try await a.mutate(row, action: .undoHide, context: context)
        XCTAssertEqual(restored.rows.count, 1)
        _ = try await a.mutate(row, action: .markUnread, context: context)
        let count = try await a.unreadCount(context: context); XCTAssertEqual(count, 2)
    }
    func testMutationWrongReceiptOrContextDoesNotReturnSuccess() async throws {
        for mode in ["wrongState", "switchState", "throwState"] {
            let f = Fixture(); let a = AccountActivityNativeInboxAdapter(fixtureTransport: f)
            let context = f.context!, row = try await a.load(context: context)[0]; f.mode = mode
            do { _ = try await a.mutate(row, action: .hide, context: context); XCTFail(mode) } catch {}
            XCTAssertEqual(f.stateCalls, 1)
        }
    }
    func testMutationProductionGateDoesNotCallState() async throws {
        let f = Fixture(); let a = AccountActivityNativeInboxAdapter(fixtureTransport: f)
        let row = try await a.load(context: f.context!)[0]
        do { _ = try await AccountActivityNativeInboxAdapter(transport: f).mutate(row, action: .hide, context: f.context!); XCTFail() } catch {}
        XCTAssertEqual(f.stateCalls, 0)
    }
    func testRetiredAccountBlocksReadOpenAndMutationBeforeTransport() async throws {
        let f=Fixture()
        let adapter=AccountActivityNativeInboxAdapter(fixtureTransport:f),context=f.context!
        let row=try await adapter.load(context:context)[0]
        let prior=f.calls
        AccountDeletionWriteFence.shared.retire(f.viewer)
        do {_ = try await adapter.load(context:context);XCTFail("retired read returned")}catch{}
        do {_ = try await adapter.open(row,context:context);XCTFail("retired open returned")}catch{}
        do {_ = try await adapter.mutate(row,action:.hide,context:context);XCTFail("retired mutation returned")}catch{}
        XCTAssertEqual(f.calls,prior);XCTAssertEqual(f.stateCalls,0);XCTAssertTrue(f.cardRequests.isEmpty)
    }
    func testDeletionDuringInboxReadDiscardsSameContextResponse() async {
        let f=Fixture();f.retireAt="inbox"
        do {_ = try await AccountActivityNativeInboxAdapter(fixtureTransport:f).load(context:f.context!);XCTFail("late deleted-account rows returned")}catch{}
        XCTAssertEqual(f.calls,1)
    }
    func testDeletionDuringCardReadPreventsDeepLinkAndFurtherLookup() async throws {
        let f=Fixture()
        let a=AccountActivityNativeInboxAdapter(fixtureTransport:f),context=f.context!
        let row=try await a.load(context:context)[0];f.retireAt="card"
        do {_ = try await a.open(row,context:context);XCTFail("late deleted-account destination returned")}catch{}
        XCTAssertEqual(f.cardRequests.count,1);XCTAssertEqual(f.calls,2)
    }
    func testDeletionDuringStateWriteDoesNotReportSuccessOrReload() async throws {
        let f=Fixture()
        let adapter=AccountActivityNativeInboxAdapter(fixtureTransport:f),context=f.context!
        let row=try await adapter.load(context:context)[0];f.retireAt="state"
        do {_ = try await adapter.mutate(row,action:.markRead,context:context);XCTFail("late state success returned")}catch{}
        XCTAssertEqual(f.stateCalls,1);XCTAssertEqual(f.calls,1)
    }
    private final class Fixture: AccountActivityNativeInboxTransport {
        var readPolicy: AccountActivityReadPolicy = .approvedFollowersV1
        var versionOverride: Int?
        let viewer = UUID(), actor = UUID(), event = UUID(), comment = UUID(), cardID = UUID(), canonical = UUID()
        var generation = 1, calls = 0, mode = "ok", changeContext = false, removeAfterCard = false
        var cardRequests: [UUID] = []
        var read = false, hidden = false, stateCalls = 0
        var retireAt: String?
        var context: AccountActivityReadContext? { .init(viewerID: viewer, generation: generation, safetyRevision: generation) }
        func inbox(limit: Int) async throws -> Data {
            calls += 1
            if retireAt == "inbox" { AccountDeletionWriteFence.shared.retire(viewer) }
            if changeContext { generation += 1 }
            let row: [String: Any] = ["event_id":event.uuidString,"comment_id":comment.uuidString,"card_id":cardID.uuidString,"actor_id":actor.uuidString,"reason":"mention","created_at":"2026-01-01T00:00:00Z","read_at":read ? "2026-01-02T00:00:00Z" : NSNull()]
            let rows = (mode == "empty" || hidden) ? [] : mode == "duplicate" ? [row,row] : [row]
            return try JSONSerialization.data(withJSONObject: ["version":versionOverride ?? readPolicy.rawValue,"viewer_id":(mode == "wrongViewer" ? actor : viewer).uuidString,"source_kind":mode == "legacy" ? "legacy" : readPolicy.nativeSourceKind,"backing":"native","rows":rows,"push_delivery":"candidate_disabled","release_ready":false,"unread_count":mode == "badUnread" ? -1 : (read || hidden ? 1 : 2)])
        }
        func state(commentID: UUID, action: AccountActivityNativeInboxAction) async throws -> Data {
            stateCalls += 1
            if retireAt == "state" { AccountDeletionWriteFence.shared.retire(viewer) }
            if mode == "throwState" { throw AccountActivityNativeInboxError.unavailable }
            if mode == "switchState" { generation += 1 }
            switch action { case .markRead: read = true; case .markUnread: read = false; case .hide: hidden = true; case .undoHide: hidden = false }
            return try JSONSerialization.data(withJSONObject: ["version":versionOverride ?? readPolicy.rawValue,"viewer_id":viewer.uuidString,"source_kind":readPolicy.nativeSourceKind,"event_id":(mode == "wrongState" ? cardID : event).uuidString,"comment_id":comment.uuidString,"read_at":read ? "2026-01-02T00:00:00Z" : NSNull(),"hidden_at":hidden ? "2026-01-02T00:00:00Z" : NSNull(),"release_ready":false])
        }
        func card(id: UUID) async throws -> AccountActivityCardEnvelope {
            cardRequests.append(id)
            if retireAt == "card" { AccountDeletionWriteFence.shared.retire(viewer) }
            if removeAfterCard { mode = "empty" }
            let object: [String: Any] = ["version":versionOverride ?? readPolicy.rawValue,"viewer_id":viewer.uuidString,"release_ready":false,"row":["card_id":cardID.uuidString,"canonical_id":canonical.uuidString,"owner_id":actor.uuidString,"sport":"running","activity_at":"2026-01-01T00:00:00Z","duration_seconds":60,"distance_meters":100,"revision":1]]
            return try JSONDecoder().decode(AccountActivityCardEnvelope.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
}

@MainActor final class FeedCommentProfileNavigationTests: XCTestCase {
    private var context: AccountActivityReadContext { .init(viewerID: UUID(), generation: 1, safetyRevision: 2) }
    func testProfileIsNotPublishedUntilCommentsDisappearAndFirstTapWins() throws {
        let router = FeedCommentProfileRouter(), current = context, author = UUID()
        let token = try XCTUnwrap(router.request(userID: author, profile: nil, context: current))
        XCTAssertNil(router.destination)
        XCTAssertNil(router.request(userID: UUID(), profile: nil, context: current))
        router.commentsDidDismiss(requestID: UUID(), context: current)
        XCTAssertNil(router.destination)
        router.commentsDidDismiss(requestID: token, context: current)
        XCTAssertEqual(router.destination?.userID, author)
        XCTAssertNil(router.request(userID: UUID(), profile: nil, context: current))
    }
    func testCancelledOrChangedContextCannotOpenLateProfile() throws {
        let current = context
        for cancel in [false, true] {
            let router = FeedCommentProfileRouter()
            let token = try XCTUnwrap(router.request(userID: UUID(), profile: nil, context: current))
            if cancel { router.cancel() }
            router.commentsDidDismiss(requestID: token, context: .init(viewerID: current.viewerID, generation: current.generation, safetyRevision: current.safetyRevision + 1))
            XCTAssertNil(router.destination)
        }
    }
    func testBackClearsOnlyProfileRouteAndAllowsAnotherAuthor() throws {
        let router = FeedCommentProfileRouter(), current = context, first = UUID(), second = UUID()
        let token = try XCTUnwrap(router.request(userID: first, profile: nil, context: current))
        router.commentsDidDismiss(requestID: token, context: current)
        router.cancel()
        XCTAssertNil(router.destination)
        let next = try XCTUnwrap(router.request(userID: second, profile: nil, context: current))
        router.commentsDidDismiss(requestID: next, context: current)
        XCTAssertEqual(router.destination?.userID, second)
    }
    func testMissingAccountAndMismatchedProfileMetadataAreNotAdopted() throws {
        let router = FeedCommentProfileRouter(), current = context
        XCTAssertNil(router.request(userID: UUID(), profile: nil, context: nil))
        let token = try XCTUnwrap(router.request(userID: UUID(), profile: .init(id: UUID(), displayName: "wrong identity", handle:nil), context: current))
        router.commentsDidDismiss(requestID: token, context: current)
        XCTAssertNil(router.destination?.profile)
    }
}

@MainActor final class SOOMProfileNavigationPolicyTests: XCTestCase {
    private let viewer = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    private let target = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000002")!
    func testPendingHandoffRequiresExactRevisionButPresentedIdentityCanRevalidate() {
        let old = AccountActivityReadContext(viewerID: viewer, generation: 2, safetyRevision: 3)
        let fresh = AccountActivityReadContext(viewerID: viewer, generation: 2, safetyRevision: 4)
        XCTAssertTrue(SOOMProfileNavigationPolicy.sameAccount(old, fresh))
        let router = FeedCommentProfileRouter()
        let token = router.request(userID: target, profile: nil, context: old)!
        router.commentsDidDismiss(requestID: token, context: fresh)
        XCTAssertNil(router.destination)
    }
    func testPresentedRouteRejectsMissingAndDifferentAccountOrGeneration() {
        let context = AccountActivityReadContext(viewerID: viewer, generation: 2, safetyRevision: 3)
        XCTAssertFalse(SOOMProfileNavigationPolicy.sameAccount(context, nil))
        XCTAssertFalse(SOOMProfileNavigationPolicy.sameAccount(context, .init(viewerID: target, generation: 2, safetyRevision: 3)))
        XCTAssertFalse(SOOMProfileNavigationPolicy.sameAccount(context, .init(viewerID: viewer, generation: 3, safetyRevision: 3)))
    }
    func testStartRejectsSameTopDuplicateInactiveBlockedAndInFlight() {
        XCTAssertTrue(SOOMProfileNavigationPolicy.canStart(userID: target, currentID: nil, active: true, blocked: false, busy: false))
        XCTAssertFalse(SOOMProfileNavigationPolicy.canStart(userID: target, currentID: target, active: true, blocked: false, busy: false))
        XCTAssertFalse(SOOMProfileNavigationPolicy.canStart(userID: target, currentID: nil, active: false, blocked: false, busy: false))
        XCTAssertFalse(SOOMProfileNavigationPolicy.canStart(userID: target, currentID: nil, active: true, blocked: true, busy: false))
        XCTAssertFalse(SOOMProfileNavigationPolicy.canStart(userID: target, currentID: nil, active: true, blocked: false, busy: true))
    }
    func testPendingCancellationDoesNotPopAnAlreadyPresentedProfile() {
        let context = AccountActivityReadContext(viewerID: viewer, generation: 2, safetyRevision: 3)
        let router = FeedCommentProfileRouter()
        let token = router.request(userID: target, profile: nil, context: context)!
        router.commentsDidDismiss(requestID: token, context: context)
        router.cancelPending()
        XCTAssertEqual(router.destination?.id, token)
        router.cancel()
        XCTAssertNil(router.destination)
    }
    func testCancelledModalDoesNotPushAndNextRequestRemainsUsable() {
        let context = AccountActivityReadContext(viewerID: viewer, generation: 2, safetyRevision: 3)
        let router = FeedCommentProfileRouter()
        let old = router.request(userID: target, profile: nil, context: context)!
        router.cancel()
        let fresh = router.request(userID: target, profile: nil, context: context)!
        router.commentsDidDismiss(requestID: old, context: context)
        XCTAssertNil(router.destination)
        router.commentsDidDismiss(requestID: fresh, context: context)
        XCTAssertEqual(router.destination?.id, fresh)
    }
}
