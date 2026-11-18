import XCTest
@testable import SOOM

@MainActor
private final class ActivityInteractionStub: AccountActivityInteractionTransport {
    var readPolicy: AccountActivityReadPolicy = .approvedFollowersV1
    var calls: [String] = []
    var handler: (String, AccountActivityInteractionParameters) throws -> Data = { _, _ in Data() }
    func call(_ name: String, params: AccountActivityInteractionParameters) async throws -> Data {
        calls.append(name); return try handler(name, params)
    }
}
@MainActor
final class AccountActivityInteractionAdapterTests: XCTestCase {
    let owner = UUID(), card = UUID()
    func data(_ json: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: json) }
    var context: AccountActivityInteractionContext { .init(viewerID: owner, generation: 1, safetyRevision: 1, storageScopeID: owner.uuidString.lowercased()) }
    var target: AccountActivityInteractionTarget { .native(cardID: card, ownerID: owner) }
    fileprivate func configure(_ stub: ActivityInteractionStub, rows: [[String: Any]] = []) {
        stub.handler = { [self] name, _ in
            if name == "soom_activity_interaction_status_candidate_v1" {
                return try data(["version":1,"card_id":card.uuidString,"backing":"native","state":"native_ready","release_ready":false])
            }
            return try data(["version":1,"backing":"native","rows":rows,"release_ready":false])
        }
    }
    func testV2CommentsUseOnlyV2RPCAndExactEnvelope() async throws {
        let stub = ActivityInteractionStub(); stub.readPolicy = .profileOnlyV2
        stub.handler = { [self] name, _ in
            XCTAssertTrue(name.hasSuffix("_candidate_v2"))
            if name.contains("interaction_status") { return try data(["version":2,"card_id":card.uuidString,"backing":"native","state":"native_ready","release_ready":false]) }
            return try data(["version":2,"backing":"native","rows":[],"release_ready":false])
        }
        let adapter = AccountActivityInteractionAdapter.localFixture(transport: stub, context: { self.context })
        let rows = try await adapter.loadComments(target)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(stub.calls.count, 2)
    }
    func testV2CommentsRejectV1StatusAndNeverReachWrite() async {
        let stub = ActivityInteractionStub(); stub.readPolicy = .profileOnlyV2; configure(stub)
        let adapter = AccountActivityInteractionAdapter.localFixture(transport: stub, context: { self.context })
        do { _ = try await adapter.loadComments(target); XCTFail() } catch {}
        XCTAssertEqual(stub.calls.count, 1)
    }
    func testV2CommentProductionCannotBorrowV1PreviewPermission() async {
        let stub = ActivityInteractionStub(); stub.readPolicy = .profileOnlyV2
        let adapter = AccountActivityInteractionAdapter(transport: stub, context: { self.context }, journal: MemoryAccountActivityCommentJournal(), preview: true)
        do { _ = try await adapter.loadComments(target); XCTFail() } catch {}
        XCTAssertTrue(stub.calls.isEmpty)
    }
    func testSignedOutCannotDeleteComment() async {
        let stub = ActivityInteractionStub()
        let adapter = AccountActivityInteractionAdapter.localFixture(transport: stub, context: {
            .init(viewerID: nil, generation: 1, safetyRevision: 1, storageScopeID: "guest")
        })
        do { try await adapter.delete(target, commentID: UUID(), authorID: owner); XCTFail() } catch {}
        XCTAssertTrue(stub.calls.isEmpty)
    }
    func testPostOwnerCannotDeleteAnotherAuthorsComment() async {
        let stub = ActivityInteractionStub(); configure(stub)
        let adapter = AccountActivityInteractionAdapter.localFixture(transport: stub, context: { self.context })
        do { try await adapter.delete(target, commentID: UUID(), authorID: UUID()); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError, .invalidRequest) }
        XCTAssertTrue(stub.calls.isEmpty)
    }
    func testAccountSwitchBeforeDeleteStatusCannotIssueDelete() async {
        let stub = ActivityInteractionStub(); configure(stub)
        var c = context; let handler = stub.handler
        stub.handler = { name, params in
            c = .init(viewerID: UUID(), generation: 2, safetyRevision: 2, storageScopeID: "other")
            return try handler(name, params)
        }
        let adapter = AccountActivityInteractionAdapter.localFixture(transport: stub, context: { c })
        do { try await adapter.delete(target, commentID: UUID(), authorID: owner); XCTFail() } catch {}
        XCTAssertFalse(stub.calls.contains("soom_activity_native_delete_comment_candidate_v1"))
    }
    func testExplicitPreviewIsSeparateFromFixtureAndRejectsReleasedReceipt() async throws {
        let stub = ActivityInteractionStub(); configure(stub)
        let adapter = AccountActivityInteractionAdapter(transport: stub, context: { self.context }, journal: MemoryAccountActivityCommentJournal(), preview: true)
        let rows = try await adapter.loadComments(target)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertFalse(AccountActivityInteractionReleaseGate.productionReady)
        stub.handler = { [self] _, _ in try data(["version":1,"card_id":card.uuidString,"backing":"native","state":"native_ready","release_ready":true]) }
        do { _ = try await adapter.loadComments(target); XCTFail("wrong namespace receipt accepted") }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError, .invalidResponse) }
    }
    func testProductionGatePreventsEvenStatusRequest() async {
        let stub = ActivityInteractionStub()
        let adapter = AccountActivityInteractionAdapter(transport: stub, context: { self.context })
        do { _ = try await adapter.loadComments(target); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError, .disabled) }
        XCTAssertTrue(stub.calls.isEmpty)
    }
    func testLegacyNeverUsesCardAsPostID() async {
        let stub = ActivityInteractionStub()
        let adapter = AccountActivityInteractionAdapter.localFixture(transport: stub, context: { self.context })
        do { _ = try await adapter.loadComments(.legacy(cardID:card,postID:UUID())); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError, .requiresLegacyPath) }
        XCTAssertTrue(stub.calls.isEmpty)
    }
    func testEmptyNativePagePassesAndWrongCardRejects() async throws {
        let stub = ActivityInteractionStub(); configure(stub)
        let adapter = AccountActivityInteractionAdapter.localFixture(transport:stub,context:{self.context})
        let empty = try await adapter.loadComments(target); XCTAssertTrue(empty.isEmpty)
        configure(stub, rows:[["id":UUID().uuidString,"card_id":UUID().uuidString,"author_id":owner.uuidString,
                              "created_at":"2026-11-11T10:00:00Z","is_deleted":false,"body":"test","mentions":[]]])
        do { _ = try await adapter.loadComments(target); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError, .invalidResponse) }
    }
    func testAccountRevisionChangeDiscardsStatus() async {
        let stub = ActivityInteractionStub(); configure(stub)
        var c = context; let original = stub.handler
        stub.handler = { name, params in
            c = .init(viewerID:c.viewerID,generation:c.generation,safetyRevision:2,storageScopeID:c.storageScopeID)
            return try original(name,params)
        }
        let adapter = AccountActivityInteractionAdapter.localFixture(transport:stub,context:{c})
        do { _ = try await adapter.loadComments(target); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError, .accountChanged) }
        XCTAssertEqual(stub.calls.count,1)
    }
    func testUncertainWriteBlocksReplayAndFreshID() async throws {
        let stub = ActivityInteractionStub(); configure(stub); let original = stub.handler
        stub.handler = { name, params in
            if name.contains("add_comment") { throw URLError(.timedOut) }
            return try original(name,params)
        }
        let adapter = AccountActivityInteractionAdapter.localFixture(transport:stub,context:{self.context})
        let request = AccountActivityCommentRequest(id:UUID(),body:"합성",mentions:[],parentID:nil)
        for id in [request.id,request.id,UUID()] {
            do { _ = try await adapter.submit(target,request:.init(id:id,body:request.body,mentions:[],parentID:nil)); XCTFail() }
            catch { XCTAssertEqual(error as? AccountActivityInteractionError,.uncertainWrite) }
        }
        XCTAssertEqual(stub.calls.filter{$0.contains("add_comment")}.count,1)
    }
    func testPhotoPathRejectsCrossOwnerAndExternalURL() async {
        let stub = ActivityInteractionStub(); configure(stub); let original = stub.handler
        stub.handler = { [self] name, params in
            if name.contains("photos_candidate") {
                return try data(["version":1,"backing":"native","release_ready":false,"bucket":"activity-photos-candidate",
                    "rows":[["id":UUID().uuidString,"card_id":card.uuidString,"storage_path":"https://example.com/private.jpg","sort_order":0]]])
            }
            return try original(name,params)
        }
        let adapter = AccountActivityInteractionAdapter.localFixture(transport:stub,context:{self.context})
        do { _ = try await adapter.loadPhotos(target); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError,.invalidResponse) }
    }
    func testRequestStatusUnavailableDoesNotRetry() async throws {
        let stub = ActivityInteractionStub(); configure(stub); let original = stub.handler
        stub.handler = { [self] name, params in
            if name.contains("request_status") { return try data(["state":"unavailable"]) }
            return try original(name,params)
        }
        let adapter = AccountActivityInteractionAdapter.localFixture(transport:stub,context:{self.context})
        let result = try await adapter.resolve(target,request:.init(id:UUID(),body:"합성",mentions:[],parentID:nil))
        XCTAssertEqual(result,.unavailable)
        XCTAssertFalse(stub.calls.contains{$0.contains("add_comment")})
    }
}

extension AccountActivityInteractionAdapterTests {
    func testFrozenIntentSurvivesAdapterRecreationAndRetriesOnlySameIDAfterAbsent() async throws {
        let stub = ActivityInteractionStub(); configure(stub); let original = stub.handler
        let journal = MemoryAccountActivityCommentJournal()
        var failWrite = true; var sent: [UUID] = []
        stub.handler = { [self] name, params in
            if name.contains("request_status") { return try data(["version":1,"backing":"native","state":"absent","release_ready":false]) }
            if name.contains("add_comment") {
                sent.append(params.p_comment_id!)
                if failWrite { throw URLError(.timedOut) }
                return try JSONEncoder().encode(params.p_comment_id!)
            }
            return try original(name,params)
        }
        let request = AccountActivityCommentRequest(id:UUID(),body:"합성 보존",mentions:[],parentID:nil)
        let first = AccountActivityInteractionAdapter.localFixture(transport:stub,context:{self.context},journal:journal)
        do { _ = try await first.submit(target,request:request); XCTFail() } catch {}
        let second = AccountActivityInteractionAdapter.localFixture(transport:stub,context:{self.context},journal:journal)
        XCTAssertEqual(try second.pendingRequests(target),[request])
        failWrite = false
        let id = try await second.retryConfirmedAbsent(target,request:request)
        XCTAssertEqual(id,request.id); XCTAssertEqual(sent,[request.id,request.id])
        XCTAssertTrue(try second.pendingRequests(target).isEmpty)
    }
    func testFileJournalPersistsAndIsAccountScoped() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("pending.json")
        defer { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
        let journal = FileAccountActivityCommentJournal(ownerID:owner,url:url)
        let request = AccountActivityCommentRequest(id:UUID(),body:"합성",mentions:[],parentID:nil)
        try journal.write([.init(ownerID:owner,target:target,request:request)])
        XCTAssertEqual(try FileAccountActivityCommentJournal(ownerID:owner,url:url).read().first?.request,request)
        let other = UUID()
        let adapter = AccountActivityInteractionAdapter.localFixture(transport:ActivityInteractionStub(),context:{
            .init(viewerID:other,generation:2,safetyRevision:2,storageScopeID:other.uuidString.lowercased())
        },journal:journal)
        XCTAssertTrue(try adapter.pendingRequests(target).isEmpty)
    }
}

@MainActor
private struct ActivityPhotoSignerStub: AccountActivityPhotoSigning {
    let trustedOrigin = URL(string:"https://fixture.supabase.co")!
    var host = "fixture.supabase.co"
    func sign(path: String, expiresIn: Int) async throws -> URL {
        XCTAssertEqual(expiresIn,60)
        return URL(string:"https://\(host)/storage/v1/object/sign/activity-photos-candidate/\(path)?token=synthetic")!
    }
}
extension AccountActivityInteractionAdapterTests {
    func testSignedPhotoRejectsForeignHostAndExpiresWithContext() async throws {
        let stub = ActivityInteractionStub(); configure(stub); let original = stub.handler; let photo = UUID()
        stub.handler = { [self] name, params in
            if name == "soom_activity_photos_candidate_v1" {
                return try data(["version":1,"backing":"native","release_ready":false,"bucket":"activity-photos-candidate",
                    "rows":[["id":photo.uuidString,"card_id":card.uuidString,
                             "storage_path":"\(owner.uuidString.lowercased())/\(card.uuidString.lowercased())/\(photo.uuidString.lowercased()).jpg","sort_order":0]]])
            }
            return try original(name,params)
        }
        var c = context
        let adapter = AccountActivityInteractionAdapter.localFixture(transport:stub,context:{c})
        do { _ = try await adapter.resolvePhotos(target,signer:ActivityPhotoSignerStub(host:"attacker.example")); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError,.invalidResponse) }
        let photos = try await adapter.resolvePhotos(target,signer:ActivityPhotoSignerStub())
        XCTAssertEqual(photos.count,1); XCTAssertTrue(adapter.isPhotoCurrent(photos[0]))
        XCTAssertFalse(adapter.isPhotoCurrent(photos[0],now:photos[0].expiresAt))
        c = .init(viewerID:c.viewerID,generation:c.generation+1,safetyRevision:c.safetyRevision,storageScopeID:c.storageScopeID)
        XCTAssertFalse(adapter.isPhotoCurrent(photos[0]))
    }
}

@MainActor
private final class ActivityPhotoStorageStub: AccountActivityPhotoStorageTransport {
    var uploads = 0
    func uploadImmutable(_ upload: AccountActivityPhotoUpload) async throws { uploads += 1 }
    func probe(_ upload: AccountActivityPhotoUpload) async throws -> AccountActivityPhotoProbe { .matches }
}
extension AccountActivityInteractionAdapterTests {
    func testPhotoCASConflictNeverUploadsOrCommits() async throws {
        let stub=ActivityInteractionStub();configure(stub);let original=stub.handler
        stub.handler = { [self] name,params in
            if name=="soom_activity_photos_candidate_v1" {
                return try data(["version":1,"backing":"native","release_ready":false,"bucket":"activity-photos-candidate","rows":[]])
            }; return try original(name,params)
        }
        let storage=ActivityPhotoStorageStub(),journal=MemoryAccountActivityPhotoEditJournal()
        let reader=AccountActivityInteractionAdapter.localFixture(transport:stub,context:{self.context})
        let writer=AccountActivityPhotoMutationAdapter.localFixture(reader:reader,transport:stub,storage:storage,context:{self.context},journal:journal)
        let id=UUID(),ref=AccountActivityPhotoReference(id:id,storage_path:"\(owner.uuidString.lowercased())/\(card.uuidString.lowercased())/\(id.uuidString.lowercased()).jpg")
        let edit=AccountActivityPhotoEdit(id:UUID(),ownerID:owner,cardID:card,expectedIDs:[id],desired:[ref],uploads:[])
        do { try await writer.apply(edit);XCTFail() } catch {}
        XCTAssertEqual(storage.uploads,0)
        XCTAssertFalse(stub.calls.contains("soom_activity_replace_photos_candidate_v1"))
        XCTAssertEqual(try writer.pending(cardID:card),[edit])
    }
    func testPhotoProductionGatePreventsStorageAndRPC() async {
        let stub=ActivityInteractionStub(),storage=ActivityPhotoStorageStub()
        let reader=AccountActivityInteractionAdapter(transport:stub,context:{self.context})
        let writer=AccountActivityPhotoMutationAdapter(reader:reader,transport:stub,storage:storage,context:{self.context},journal:MemoryAccountActivityPhotoEditJournal())
        do { try await writer.apply(.init(id:UUID(),ownerID:owner,cardID:card,expectedIDs:[],desired:[],uploads:[]));XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError,.disabled) }
        XCTAssertEqual(storage.uploads,0);XCTAssertTrue(stub.calls.isEmpty)
    }
    func testUncertainPhotoMetadataIsLookedUpWithoutReplayOrDeletion() async throws {
        let stub=ActivityInteractionStub();configure(stub);let original=stub.handler
        let photo=UUID()
        let path="\(owner.uuidString.lowercased())/\(card.uuidString.lowercased())/\(photo.uuidString.lowercased()).jpg"
        stub.handler = { [self] name,params in
            if name=="soom_activity_replace_photos_candidate_v1" { throw URLError(.timedOut) }
            if name=="soom_activity_photos_candidate_v1" {
                return try data(["version":1,"backing":"native","release_ready":false,"bucket":"activity-photos-candidate",
                    "rows":[["id":photo.uuidString,"card_id":card.uuidString,"storage_path":path,"sort_order":0]]])
            }; return try original(name,params)
        }
        let storage=ActivityPhotoStorageStub(),journal=MemoryAccountActivityPhotoEditJournal()
        let reader=AccountActivityInteractionAdapter.localFixture(transport:stub,context:{self.context})
        let writer=AccountActivityPhotoMutationAdapter.localFixture(reader:reader,transport:stub,storage:storage,context:{self.context},journal:journal)
        let edit=AccountActivityPhotoEdit(id:UUID(),ownerID:owner,cardID:card,expectedIDs:[photo],desired:[],uploads:[])
        for _ in 0..<2 { do { try await writer.apply(edit);XCTFail() } catch {} }
        XCTAssertEqual(stub.calls.filter{$0=="soom_activity_replace_photos_candidate_v1"}.count,1)
        XCTAssertEqual(storage.uploads,0);XCTAssertEqual(try writer.pending(cardID:card),[edit])
    }
}

extension AccountActivityInteractionAdapterTests {
    func testExplicitDiscardOnlyRemovesAuthorizedAbsentAndPreservesUnavailable() async throws {
        let stub=ActivityInteractionStub();configure(stub);let original=stub.handler
        let journal=MemoryAccountActivityCommentJournal()
        let request=AccountActivityCommentRequest(id:UUID(),body:"합성",mentions:[],parentID:nil)
        try journal.write([.init(ownerID:owner,target:target,request:request)])
        var state="unavailable"
        stub.handler = { [self] name,params in
            if name.contains("request_status") { return try data(["version":1,"backing":"native","state":state,"release_ready":false]) }
            return try original(name,params)
        }
        let adapter=AccountActivityInteractionAdapter.localFixture(transport:stub,context:{self.context},journal:journal)
        let blocked=try await adapter.discardConfirmedAbsent(target,request:request)
        XCTAssertEqual(blocked,.unavailable);XCTAssertEqual(try adapter.pendingRequests(target),[request])
        state="absent"
        let removed=try await adapter.discardConfirmedAbsent(target,request:request)
        XCTAssertEqual(removed,.absent);XCTAssertTrue(try adapter.pendingRequests(target).isEmpty)
        XCTAssertFalse(stub.calls.contains{$0.contains("add_comment")})
    }
}

extension AccountActivityInteractionAdapterTests {
    func testRetiredAccountCannotRecreateCommentOrPhotoJournal() throws {
        let retired=UUID()
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let comments=FileAccountActivityCommentJournal(ownerID:retired,url:directory.appendingPathComponent("comments.json"))
        let photos=FileAccountActivityPhotoEditJournal(ownerID:retired,url:directory.appendingPathComponent("photos.json"))
        AccountDeletionWriteFence.shared.retire(retired)
        XCTAssertThrowsError(try comments.write([]));XCTAssertThrowsError(try photos.write([]))
        XCTAssertThrowsError(try comments.read());XCTAssertThrowsError(try photos.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
    }
    func testJournalRejectsCrossAccountEntriesBeforeWrite() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let comments=FileAccountActivityCommentJournal(ownerID:owner,url:directory.appendingPathComponent("comments.json"))
        let request=AccountActivityCommentRequest(id:UUID(),body:"합성",mentions:[],parentID:nil)
        XCTAssertThrowsError(try comments.write([.init(ownerID:UUID(),target:target,request:request)]))
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
    }
}


extension AccountActivityInteractionAdapterTests {
    func testProfileCardBadgeKeepsServerRecencyAndIgnoresDeletedComments() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let old = FeedComment(id: UUID(), authorId: owner, body: "old", createdAt: now.addingTimeInterval(-43_200), isViewerAuthor: false)
        let recent = FeedComment(id: UUID(), authorId: owner, body: "recent", createdAt: now.addingTimeInterval(-1), isViewerAuthor: false)
        var deleted = recent; deleted.isDeleted = true
        XCTAssertEqual(AccountActivityCommentBadge(comments: [old, deleted]).count, 1)
        XCTAssertFalse(AccountActivityCommentBadge(comments: [old, deleted]).isRecent(now: now))
        XCTAssertTrue(AccountActivityCommentBadge(comments: [old, recent]).isRecent(now: now))
        XCTAssertFalse(AccountActivityCommentBadge(comments: [recent]).isRecent(now: now.addingTimeInterval(43_200)))
        XCTAssertFalse(AccountActivityCommentBadge(comments: [recent]).isRecent(now: now.addingTimeInterval(-2)))
        XCTAssertEqual(AccountActivityCommentBadge(comments: [deleted]).count, 0)
        let future = FeedComment(id: UUID(), authorId: owner, body: "future", createdAt: now.addingTimeInterval(60), isViewerAuthor: false)
        XCTAssertTrue(AccountActivityCommentBadge(comments: [future, recent]).isRecent(now: now))
    }
    func testNativeCardBadgeReadsBeyondFirstPageAndRetainsNoBody() async throws {
        let stub = ActivityInteractionStub()
        let now = Date(timeIntervalSince1970: 2_000_000)
        var pages = 0
        let format = ISO8601DateFormatter()
        stub.handler = { [self] name, params in
            if name.contains("interaction_status") {
                return try data(["version":1,"card_id":card.uuidString,"backing":"native","state":"native_ready","release_ready":false])
            }
            XCTAssertEqual(params.p_limit, 100)
            pages += 1
            let count = pages == 1 ? 100 : 1
            XCTAssertEqual(params.p_after_at == nil, pages == 1)
            let rows: [[String: Any]] = (0..<count).map { i in
                ["id":UUID().uuidString,"card_id":card.uuidString,"author_id":owner.uuidString,
                 "parent_id":NSNull(),"reply_to_id":NSNull(),"body":"synthetic", "mentions":[],"is_deleted":false,
                 "created_at":format.string(from: pages == 1 ? now.addingTimeInterval(Double(i) - 100_000) : now.addingTimeInterval(-1))]
            }
            return try data(["version":1,"backing":"native","rows":rows,"release_ready":false])
        }
        let adapter = AccountActivityInteractionAdapter.localFixture(transport: stub, context: { self.context })
        let badge = try await AccountActivityCommentBadge.load(adapter: adapter, target: target)
        XCTAssertEqual(pages, 2)
        XCTAssertEqual(badge.count, 101)
        XCTAssertTrue(badge.isRecent(now: now))
        XCTAssertEqual(stub.calls.count, 4)
        XCTAssertFalse(stub.calls.contains(where: { $0.contains("add") || $0.contains("delete") }))
    }
    func testNativeCardBadgeDoesNotTreatReadFailureAsAnEmptyThread() async {
        let stub = ActivityInteractionStub()
        stub.handler = { _, _ in throw AccountActivityInteractionError.accountChanged }
        let adapter = AccountActivityInteractionAdapter.localFixture(transport: stub, context: { self.context })
        do { _ = try await AccountActivityCommentBadge.load(adapter: adapter, target: target); XCTFail("failure must propagate") }
        catch { XCTAssertEqual(error as? AccountActivityInteractionError, .accountChanged) }
    }
}

extension AccountActivityInteractionAdapterTests {
    func testNativeBadgeBoundsBackgroundReadsWithoutClaimingTotal() async throws {
        let stub = ActivityInteractionStub(); var pages = 0
        let format = ISO8601DateFormatter()
        stub.handler = { [self] name, params in
            if name.contains("interaction_status") {
                return try data(["version":1,"card_id":card.uuidString,"backing":"native","state":"native_ready","release_ready":false])
            }
            pages += 1
            let rows: [[String: Any]] = (0..<100).map { i in
                ["id":UUID().uuidString,"card_id":card.uuidString,"author_id":owner.uuidString,
                 "parent_id":NSNull(),"reply_to_id":NSNull(),"body":"synthetic", "mentions":[],"is_deleted":false,
                 "created_at":format.string(from: Date(timeIntervalSince1970: Double(pages * 100 + i)))]
            }
            return try data(["version":1,"backing":"native","rows":rows,"release_ready":false])
        }
        let adapter = AccountActivityInteractionAdapter.localFixture(transport: stub, context: { self.context })
        let badge = try await AccountActivityCommentBadge.load(adapter: adapter, target: target)
        XCTAssertEqual(pages, 5); XCTAssertEqual(badge.count, 500)
        XCTAssertFalse(badge.isComplete)
        XCTAssertFalse(badge.isRecent(now: Date()))
    }
}

extension AccountActivityInteractionAdapterTests {
    func testSocialReadReceiptReusesOnlySameSuccessfulPresentation() {
        var receipt = AccountActivitySocialReadReceipt()
        XCTAssertFalse(receipt.isVerified(for: "account-A:active:revision-1:refresh-0"))
        receipt.recordSuccess(requestKey: "account-A:active:revision-1:refresh-0", currentKey: "account-A:active:revision-1:refresh-0", cancelled: false)
        XCTAssertTrue(receipt.isVerified(for: "account-A:active:revision-1:refresh-0"))
        for key in ["account-B:active:revision-1:refresh-0", "account-A:inactive:revision-1:refresh-0", "account-A:active:revision-2:refresh-0", "account-A:active:revision-1:refresh-1"] {
            XCTAssertFalse(receipt.isVerified(for: key))
        }
        receipt.invalidate()
        XCTAssertFalse(receipt.isVerified(for: "account-A:active:revision-1:refresh-0"))
    }
    func testSocialReadReceiptRejectsCancelledAndSupersededResponses() {
        var receipt = AccountActivitySocialReadReceipt()
        receipt.recordSuccess(requestKey: "old", currentKey: "new", cancelled: false)
        XCTAssertNil(receipt.verifiedKey)
        receipt.recordSuccess(requestKey: "new", currentKey: "new", cancelled: true)
        XCTAssertNil(receipt.verifiedKey)
        receipt.recordSuccess(requestKey: "new", currentKey: "new", cancelled: false)
        receipt.recordSuccess(requestKey: "old", currentKey: "new", cancelled: false)
        XCTAssertEqual(receipt.verifiedKey, "new")
        XCTAssertFalse(AccountActivitySocialReadReceipt.accepts(requestKey: "old", currentKey: "new", cancelled: false))
        XCTAssertFalse(AccountActivitySocialReadReceipt.accepts(requestKey: "new", currentKey: "new", cancelled: true))
    }
}
