import XCTest
import Supabase
@testable import SOOM

@MainActor private final class ProfileSocialStub: ProfileActivitySocialTransport {
    var calls: [(String, ProfileActivitySocialParameters)] = []
    var handler: (String, ProfileActivitySocialParameters) async throws -> Data = { _, _ in Data() }
    func call(_ name: String, params: ProfileActivitySocialParameters) async throws -> Data {
        calls.append((name, params)); return try await handler(name, params)
    }
}
@MainActor final class ProfileActivitySocialAdapterTests: XCTestCase {
    let viewer = UUID(), owner = UUID(), card = UUID(), canonical = UUID(), post = UUID()
    var row: AccountActivityFeedRow { .init(cardID: card, canonicalID: canonical, ownerID: owner, sport: "running",
        activityAt: "2026-11-14T06:00:00Z", durationSeconds: 600, distanceMeters: 1500, revision: 3, readPolicy: .profileOnlyV2) }
    var context: AccountActivityInteractionContext { .init(viewerID: viewer, generation: 1, safetyRevision: 2, storageScopeID: viewer.uuidString.lowercased()) }
    var receipt: ProfileActivitySocialReceipt { .init(version: 2, viewer_id: viewer, card_id: card, owner_id: owner, canonical_id: canonical,
        projection_revision: 3, profile_revision: 5, backing: "legacy", source_id: post, release_ready: false, write_backing:"legacy",read_sources:[.init(source_kind:"legacy",source_id:post)],source_revision:String(repeating:"a",count:32)) }
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    func data(_ input: [String: Any]) throws -> Data {
        var value = input
        for key in ["rows", "parents"] {
            if let rows = value[key] as? [[String: Any]] { value[key] = rows.map { raw in
                var row = raw
                if row["body"] != nil {
                    row["source_kind"] = "legacy"
                    row["parent_source"] = row["parent_id"] is String ? "legacy" : NSNull()
                    row["reply_to_source"] = row["reply_to_id"] is String ? "legacy" : NSNull()
                }
                return row
            } }
        }
        if var result = value["result"] as? [String: Any], result["comment_id"] != nil { result["source_kind"] = "legacy"; value["result"] = result }
        if var cursor = value["next_cursor"] as? [String: Any] { cursor["source_kind"] = "legacy"; value["next_cursor"] = cursor }
        return try JSONSerialization.data(withJSONObject: value)
    }
    func status(_ receipt: ProfileActivitySocialReceipt? = nil) throws -> Data {
        try data(["receipt":object(receipt ?? self.receipt),"state":"ready","comment_count":0,"latest_comment_at":NSNull(),"cheer_count":0,"viewer_has_cheered":false])
    }
    func mutation(_ p: ProfileActivitySocialParameters, state: String = "found", payload: ProfileActivitySocialPayload? = nil) throws -> Data {
        try data(["receipt":object(receipt),"request_id":p.p_request_id!.uuidString,"operation":p.p_operation!,"state":state,
                  "payload":object(payload ?? p.p_payload!), "result": p.p_operation == "cheer_set" ? ["desired":p.p_payload!.desired!] as [String:Any] : ["comment_id":p.p_payload!.comment_id!.uuidString,"deleted":true] as [String:Any]])
    }
    fileprivate func adapter(_ stub: ProfileSocialStub, _ journal: MemoryProfileActivitySocialJournal? = nil) -> ProfileActivitySocialAdapter {
        .localFixture(transport: stub, context: { self.context }, journal: journal ?? MemoryProfileActivitySocialJournal())
    }
    func testLiveGateRejectsBackgroundEvenWithCapturedActiveViewContext() {
        XCTAssertNil(ProfileActivitySocialLiveGate.context(context,sessionID:viewer,isActive:false).viewerID)
        XCTAssertEqual(ProfileActivitySocialLiveGate.context(context,sessionID:viewer,isActive:true),context)
    }
    func testLiveGateRejectsChangedSessionEvenWithCapturedViewer() {
        XCTAssertNil(ProfileActivitySocialLiveGate.context(context,sessionID:UUID(),isActive:true).viewerID)
        XCTAssertNil(ProfileActivitySocialLiveGate.context(context,sessionID:nil,isActive:true).viewerID)
    }
    func testStatusUsesDedicatedRPCAndNoLegacyDetail() async throws {
        let stub = ProfileSocialStub(); stub.handler = { _, _ in try self.status() }
        let result = try await adapter(stub).status(row: row)
        XCTAssertEqual(result.receipt.source_id, post)
        XCTAssertEqual(stub.calls.map(\.0), ["soom_activity_social_status_candidate_v2"])
    }
    func testNilViewerIssuesNoRequest() async {
        let stub = ProfileSocialStub()
        let a = ProfileActivitySocialAdapter.localFixture(transport: stub, context: { .init(viewerID:nil,generation:1,safetyRevision:2,storageScopeID:"guest") }, journal: MemoryProfileActivitySocialJournal())
        do { _ = try await a.status(row: row); XCTFail() } catch {}
        XCTAssertTrue(stub.calls.isEmpty)
    }
    func testAccountChangeDiscardsStatus() async {
        let stub = ProfileSocialStub(); var c = context
        stub.handler = { _, _ in c = .init(viewerID: UUID(), generation: 2, safetyRevision: 3, storageScopeID: "other"); return try self.status() }
        let a = ProfileActivitySocialAdapter.localFixture(transport: stub, context: { c }, journal: MemoryProfileActivitySocialJournal())
        do { _ = try await a.status(row: row); XCTFail() } catch { XCTAssertEqual(error as? ProfileActivitySocialError, .accountChanged) }
    }
    func testMalformedScopeOrUnreleasedReceiptFailsClosed() async throws {
        for (field, value) in [("viewer_id", UUID().uuidString as Any),("owner_id", UUID().uuidString as Any),("canonical_id",UUID().uuidString as Any),
                               ("card_id",UUID().uuidString as Any),("version",1 as Any),("projection_revision",4 as Any),("profile_revision",0 as Any),
                               ("backing","unknown" as Any),("release_ready",true as Any)] {
            var r = try object(receipt) as! [String:Any]; r[field] = value
            let stub = ProfileSocialStub(); stub.handler = { _, _ in try self.data(["receipt":r,"state":"ready","comment_count":0,"latest_comment_at":NSNull(),"cheer_count":0,"viewer_has_cheered":false]) }
            do { _ = try await adapter(stub).status(row: row); XCTFail(field) } catch {}
            XCTAssertEqual(stub.calls.count,1)
        }
    }
    func testNativeSourceMustEqualCard() async throws {
        let r = ProfileActivitySocialReceipt(version:2,viewer_id:viewer,card_id:card,owner_id:owner,canonical_id:canonical,projection_revision:3,profile_revision:5,backing:"native",source_id:post,release_ready:false)
        let stub = ProfileSocialStub(); stub.handler = { _,_ in try self.status(r) }
        do { _ = try await adapter(stub).status(row: row); XCTFail() } catch {}
    }
    func testNegativeCountsRejected() async throws {
        let stub = ProfileSocialStub(); stub.handler = { _, _ in try self.data(["receipt":self.object(self.receipt),"state":"ready","comment_count":-1,"latest_comment_at":NSNull(),"cheer_count":0,"viewer_has_cheered":false]) }
        do { _ = try await adapter(stub).status(row: row); XCTFail() } catch {}
    }
    func testTombstoneKeepsNoAuthorIdentity() async throws {
        let id = UUID(); let stub = ProfileSocialStub()
        stub.handler = { _, p in
            XCTAssertEqual(p.p_expected, self.receipt.expected)
            return try self.data(["receipt":self.object(self.receipt),"rows":[["id":id.uuidString,"card_id":self.card.uuidString,
                "author_id":NSNull(),"body":"","created_at":"2026-11-14T06:00:00Z","parent_id":NSNull(),"reply_to_id":NSNull(),
                "is_deleted":true,"mentions":[],"author_profile":NSNull()]],"parents":[],"next_cursor":NSNull()])
        }
        let page = try await adapter(stub).comments(row:row,receipt:receipt)
        XCTAssertNil(page.rows[0].author_id)
        XCTAssertThrowsError(try page.rows[0].display(viewer:viewer))
    }
    func testTombstoneWithBodyRejected() async throws {
        let stub = ProfileSocialStub(); stub.handler = { _, _ in try self.data(["receipt":self.object(self.receipt),"rows":[[
            "id":UUID().uuidString,"card_id":self.card.uuidString,"author_id":NSNull(),"body":"private","created_at":"2026-11-14T06:00:00Z",
            "is_deleted":true,"mentions":[],"author_profile":NSNull()]],"parents":[],"next_cursor":NSNull()]) }
        do { _ = try await adapter(stub).comments(row:row,receipt:receipt); XCTFail() } catch {}
    }
    func testChangedBackingOnPageDoesNotFallback() async throws {
        let changed = ProfileActivitySocialReceipt(version:2,viewer_id:viewer,card_id:card,owner_id:owner,canonical_id:canonical,projection_revision:3,profile_revision:5,backing:"native",source_id:card,release_ready:false,write_backing:"native",read_sources:[.init(source_kind:"native",source_id:card)],source_revision:String(repeating:"b",count:32))
        let stub = ProfileSocialStub(); stub.handler = { _,_ in try self.data(["receipt":self.object(changed),"rows":[],"parents":[],"next_cursor":NSNull()]) }
        do { _ = try await adapter(stub).comments(row:row,receipt:receipt); XCTFail() } catch { XCTAssertEqual(error as? ProfileActivitySocialError,.changed) }
        XCTAssertEqual(stub.calls.count,1)
    }
    func testPageReceiptMissingRoutingIsMalformedWithoutFallback() async throws {
        let malformed = ProfileActivitySocialReceipt(version:2,viewer_id:viewer,card_id:card,owner_id:owner,
            canonical_id:canonical,projection_revision:3,profile_revision:5,backing:"native",source_id:card,release_ready:false)
        let stub = ProfileSocialStub()
        stub.handler = { _,_ in try self.data(["receipt":self.object(malformed),"rows":[],"parents":[],"next_cursor":NSNull()]) }
        do { _ = try await adapter(stub).comments(row:row,receipt:receipt); XCTFail() }
        catch { XCTAssertEqual(error as? ProfileActivitySocialError,.malformed) }
        XCTAssertEqual(stub.calls.count,1)
    }
    func testUnknownCursorAndDuplicateReactionsRejected() async throws {
        let id = UUID(); let stub = ProfileSocialStub()
        stub.handler = { _, _ in
            let r: [String:Any] = ["id":id.uuidString,"card_id":self.card.uuidString,"user_id":self.viewer.uuidString,"reaction_type":"cheer","created_at":"2026-11-14T06:00:00Z","author_profile":NSNull()]
            return try self.data(["receipt":self.object(self.receipt),"rows":[r,r],"next_cursor":NSNull()])
        }
        do { _ = try await adapter(stub).reactions(row:row,receipt:receipt); XCTFail() } catch {}
    }
    func testDeleteOtherAuthorsCommentNeverWrites() async throws {
        let stub = ProfileSocialStub()
        let c = ProfileActivitySocialComment(id:UUID(),card_id:card,author_id:owner,body:"test",created_at:"2026-11-14T06:00:00Z",parent_id:nil,reply_to_id:nil,is_deleted:false,mentions:[],author_profile:nil)
        do { try await adapter(stub).deleteComment(row:row,receipt:receipt,comment:c); XCTFail() } catch { XCTAssertEqual(error as? ProfileActivitySocialError,.invalidRequest) }
        XCTAssertTrue(stub.calls.isEmpty)
    }
    func testAcknowledgedCheerRemovesJournal() async throws {
        let stub = ProfileSocialStub(), journal = MemoryProfileActivitySocialJournal()
        stub.handler = { _,p in XCTAssertEqual(journal.values.count,1); return try self.mutation(p) }
        try await adapter(stub,journal).setCheer(row:row,receipt:receipt,desired:true)
        XCTAssertTrue(journal.values.isEmpty)
        XCTAssertEqual(stub.calls.first?.1.p_payload?.desired,true)
    }
    func testUncertainWriteRetainsIDAndBlocksNewWrite() async throws {
        let stub = ProfileSocialStub(), journal = MemoryProfileActivitySocialJournal(); let a = adapter(stub,journal)
        stub.handler = { _,_ in throw URLError(.networkConnectionLost) }
        do { try await a.setCheer(row:row,receipt:receipt,desired:true); XCTFail() } catch {}
        let id = try XCTUnwrap(journal.values.first?.id)
        do { try await a.setCheer(row:row,receipt:receipt,desired:false); XCTFail() } catch { XCTAssertEqual(error as? ProfileActivitySocialError,.pendingWrite) }
        XCTAssertEqual(stub.calls.count,1); XCTAssertEqual(journal.values.first?.id,id)
    }
    func testFoundRecoveryNeverReappliesOldDesired() async throws {
        let stub = ProfileSocialStub(), journal = MemoryProfileActivitySocialJournal(); let a = adapter(stub,journal)
        stub.handler = { _,_ in throw URLError(.timedOut) }
        do { try await a.setCheer(row:row,receipt:receipt,desired:true) } catch {}
        let pending = try XCTUnwrap(journal.values.first)
        stub.handler = { name,p in XCTAssertTrue(name.contains("request_status")); return try self.mutation(p) }
        let found = try await a.resolve(row:row,request:pending,retryIfAbsent:true)
        XCTAssertTrue(found); XCTAssertTrue(journal.values.isEmpty)
        XCTAssertEqual(stub.calls.filter{$0.0.contains("_mutate_")}.count,1)
    }
    func testAbsentRecoveryRetriesExactSameIDAndPayloadOnly() async throws {
        let stub = ProfileSocialStub(), journal = MemoryProfileActivitySocialJournal(); let a = adapter(stub,journal)
        stub.handler = { _,_ in throw URLError(.timedOut) }
        do { try await a.addComment(row:row,receipt:receipt,body:" hello ",parentID:nil,mentions:[]) } catch {}
        let request = try XCTUnwrap(journal.values.first)
        XCTAssertEqual(request.payload.body,"hello")
        stub.handler = { name,p in
            XCTAssertEqual(p.p_request_id,request.id); XCTAssertEqual(p.p_payload,request.payload); XCTAssertEqual(p.p_expected,request.receipt.expected)
            return try self.mutation(p,state:name.contains("request_status") ? "absent" : "found")
        }
        _ = try await a.resolve(row:row,request:request,retryIfAbsent:true)
        XCTAssertEqual(stub.calls.count,3); XCTAssertTrue(journal.values.isEmpty)
    }
    func testMismatchedRecoveryPayloadKeepsPending() async throws {
        let stub = ProfileSocialStub(), journal = MemoryProfileActivitySocialJournal(); let a = adapter(stub,journal)
        stub.handler = { _,_ in throw URLError(.timedOut) }
        do { try await a.setCheer(row:row,receipt:receipt,desired:true) } catch {}
        let request = try XCTUnwrap(journal.values.first)
        stub.handler = { _,p in try self.mutation(p,payload:.init(desired:false)) }
        do { _ = try await a.resolve(row:row,request:request,retryIfAbsent:true); XCTFail() } catch {}
        XCTAssertEqual(journal.values,[request]); XCTAssertEqual(stub.calls.count,2)
    }
    func testAccountChangeAfterMutationKeepsPendingAndDiscardsResponse() async throws {
        let stub = ProfileSocialStub(), journal = MemoryProfileActivitySocialJournal(); var c = context
        let a = ProfileActivitySocialAdapter.localFixture(transport:stub,context:{c},journal:journal)
        stub.handler = { _,p in c = .init(viewerID:nil,generation:2,safetyRevision:3,storageScopeID:"guest"); return try self.mutation(p) }
        do { try await a.setCheer(row:row,receipt:receipt,desired:true); XCTFail() } catch {}
        XCTAssertEqual(journal.values.count,1)
    }
    func testMentionSearchPinsAuthorityAndHasNoGenericFallback() async throws {
        let stub = ProfileSocialStub(); stub.handler = { name,p in
            XCTAssertEqual(name,"soom_activity_social_mentions_candidate_v2"); XCTAssertEqual(p.p_expected,self.receipt.expected)
            throw URLError(.notConnectedToInternet)
        }
        do { _ = try await adapter(stub).mentions(row:row,receipt:receipt,query:"name"); XCTFail() } catch {}
        XCTAssertEqual(stub.calls.count,1)
    }
    func testFirstDefinitiveSQLRollbackAllowsEditingWithoutLosingUncertainRequests() async throws {
        for code in ["22023", "42501"] {
            let stub = ProfileSocialStub(), journal = MemoryProfileActivitySocialJournal()
            stub.handler = { _,_ in throw PostgrestError(code:code,message:"rejected before commit") }
            do { try await adapter(stub,journal).setCheer(row:row,receipt:receipt,desired:true); XCTFail() } catch {}
            XCTAssertTrue(journal.values.isEmpty)
        }
    }
    func testRecoverySQLRejectionDoesNotDiscardOlderUncertainRequest() async throws {
        let stub = ProfileSocialStub(), journal = MemoryProfileActivitySocialJournal(); let a = adapter(stub,journal)
        stub.handler = { _,_ in throw URLError(.timedOut) }
        do { try await a.setCheer(row:row,receipt:receipt,desired:true) } catch {}
        let request = try XCTUnwrap(journal.values.first)
        stub.handler = { _,_ in throw PostgrestError(code:"42501",message:"now denied") }
        do { _ = try await a.resolve(row:row,request:request,retryIfAbsent:true); XCTFail() } catch {}
        XCTAssertEqual(journal.values,[request])
    }
    func testFirstRejectionAfterAccountChangeKeepsOriginalAccountJournal() async throws {
        let stub = ProfileSocialStub(), journal = MemoryProfileActivitySocialJournal(); var c = context
        let a = ProfileActivitySocialAdapter.localFixture(transport:stub,context:{c},journal:journal)
        stub.handler = { _,_ in c = .init(viewerID:nil,generation:2,safetyRevision:3,storageScopeID:"guest"); throw PostgrestError(code:"42501",message:"denied") }
        do { try await a.setCheer(row:row,receipt:receipt,desired:true); XCTFail() } catch {}
        XCTAssertEqual(journal.values.count,1)
    }
    func testParentsMayContainReferencedReplyWithSameRoot() async throws {
        let root = UUID(), parent = UUID(), child = UUID(), stub = ProfileSocialStub()
        func comment(_ id:UUID,_ parentID:UUID?,_ reply:UUID?) -> [String:Any] {
            ["id":id.uuidString,"card_id":card.uuidString,"author_id":viewer.uuidString,"body":"reply","created_at":"2026-11-14T06:00:00Z",
             "parent_id":parentID?.uuidString as Any? ?? NSNull(),"reply_to_id":reply?.uuidString as Any? ?? NSNull(),"is_deleted":false,"mentions":[],"author_profile":NSNull()]
        }
        stub.handler = { _,_ in try self.data(["receipt":self.object(self.receipt),"rows":[comment(child,root,parent)],
                                               "parents":[comment(root,nil,nil),comment(parent,root,root)],"next_cursor":NSNull()]) }
        let page = try await adapter(stub).comments(row:row,receipt:receipt)
        XCTAssertEqual(page.parents.count,2)
        stub.handler = { _,_ in try self.data(["receipt":self.object(self.receipt),"rows":[comment(child,root,parent)],
                                               "parents":[comment(root,nil,nil),comment(parent,UUID(),nil)],"next_cursor":NSNull()]) }
        do { _ = try await adapter(stub).comments(row:row,receipt:receipt); XCTFail("cross-root reply") } catch {}
    }

    private func batch(_ phase:FeedReturnBatchPresentation.Phase = .ready, grantRow:AccountActivityFeedRow? = nil) -> FeedReturnBatchPresentation {
        let grant = FeedReturnCardGrant(id:UUID(),row:grantRow ?? row,author:nil,authorRevision:nil,avatarObject:nil,photos:[],photoObjects:[:],photosAvailable:true,socialStatus:nil)
        return .init(id:UUID(),context:.init(viewerID:viewer,accountGeneration:1,safetyRevision:2,returnEpoch:4),phase:phase,grants:[card:grant],requested:[card])
    }
    private func access(_ batch:FeedReturnBatchPresentation?, viewer:UUID? = nil, safety:Int = 2, epoch:Int = 4) -> FeedReturnAccess<FeedReturnCardGrant>? {
        AccountActivityReturnBatchPolicy.access(source:row,batch:batch,viewerID:viewer ?? self.viewer,generation:1,safetyRevision:safety,returnEpoch:epoch)
    }
    func testBatchPendingNeverAuthorizesRetainedCompletedGrant() {
        guard case .pending? = access(batch(.pending)) else { return XCTFail("pending disclosed cached card") }
        guard case .denied? = access(batch(.failed)) else { return XCTFail("failed disclosed cached card") }
    }
    func testBatchWrongViewerSafetyOrReturnEpochNeverReusesRenderer() {
        guard case .denied? = access(batch(),viewer:UUID()) else { return XCTFail() }
        guard case .denied? = access(batch(),safety:3) else { return XCTFail() }
        guard case .denied? = access(batch(),epoch:5) else { return XCTFail() }
    }
    func testBatchFreshSameIdentityMayReplaceStaleSummaryMetrics() {
        let fresh = AccountActivityFeedRow(cardID:card,canonicalID:canonical,ownerID:owner,sport:"running",activityAt:row.activityAt,durationSeconds:1200,distanceMeters:3000,revision:4,readPolicy:.profileOnlyV2)
        guard case .authorized(let grant)? = access(batch(grantRow:fresh)) else { return XCTFail() }
        XCTAssertEqual(grant.row,fresh)
    }
    func testBatchChangedCanonicalIdentityIsDeniedWithoutIndependentFallback() {
        let wrong = AccountActivityFeedRow(cardID:card,canonicalID:UUID(),ownerID:owner,sport:"running",activityAt:row.activityAt,durationSeconds:600,distanceMeters:1500,revision:3,readPolicy:.profileOnlyV2)
        guard case .denied? = access(batch(grantRow:wrong)) else { return XCTFail() }
    }
    func testBatchNilMeansIndependentChildAuthorizationNotInheritedHomeGrant() {
        XCTAssertNil(access(nil))
    }
    private func postgres(_ key: String) throws -> Data {
        let fixture = try JSONSerialization.jsonObject(with:Data(Self.postgresFixture.utf8)) as! [String:Any]
        return try JSONSerialization.data(withJSONObject:try XCTUnwrap(fixture[key]))
    }
    fileprivate func postgresAdapter(_ key:String) throws -> (ProfileActivitySocialAdapter,ProfileSocialStub,AccountActivityFeedRow,ProfileActivitySocialReceipt) {
        guard ProfileActivitySocialReleaseGate.productionReady else { throw XCTSkip("Production contract compile condition required") }
        let data = try postgres(key)
        struct Envelope:Decodable {let receipt:ProfileActivitySocialReceipt}
        let r = try JSONDecoder().decode(Envelope.self,from:data).receipt
        let stub = ProfileSocialStub(); stub.handler = { _,_ in data }
        let row = AccountActivityFeedRow(cardID:r.card_id,canonicalID:r.canonical_id,ownerID:r.owner_id,sport:"running",activityAt:"2026-11-14T00:00:00Z",durationSeconds:600,distanceMeters:1000,revision:r.projection_revision,readPolicy:.profileOnlyV2)
        let c = AccountActivityInteractionContext(viewerID:r.viewer_id,generation:1,safetyRevision:1,storageScopeID:r.viewer_id.uuidString.lowercased())
        return (.init(transport:stub,context:{c},journal:MemoryProfileActivitySocialJournal()),stub,row,r)
    }
    func testAdaptedHistoricalPostgresLegacyAndNativeStatusContract() async throws {
        for key in ["legacy_status","native_status"] {
            let (a,_,row,_) = try postgresAdapter(key)
            let status = try await a.status(row:row)
            XCTAssertEqual(status.state,"ready")
        }
    }
    func testAdaptedHistoricalPostgresCommentsIncludeAuthorlessTombstoneAndReply() async throws {
        for key in ["legacy_comments","native_comments"] {
            let (a,_,row,r) = try postgresAdapter(key)
            let page = try await a.comments(row:row,receipt:r)
            XCTAssertFalse(page.rows.isEmpty)
            if key == "legacy_comments" {
                XCTAssertEqual(page.rows.filter(\.is_deleted).count,1)
                XCTAssertNil(page.rows.first(where:{$0.is_deleted})?.author_id)
            }
        }
    }
    func testAdaptedHistoricalPostgresReactionsAndScopedMentionsContract() async throws {
        let (a,_,row,r) = try postgresAdapter("native_reactions")
        let reactions = try await a.reactions(row:row,receipt:r)
        XCTAssertEqual(reactions.rows.count,1)
        let (b,_,otherRow,otherReceipt) = try postgresAdapter("mentions")
        let mentions = try await b.mentions(row:otherRow,receipt:otherReceipt,query:"social")
        XCTAssertEqual(mentions.count,1)
    }
    func testAdaptedHistoricalPostgresFoundDeletedCommentRequestIsNotRecreated() async throws {
        guard ProfileActivitySocialReleaseGate.productionReady else { throw XCTSkip("Production contract compile condition required") }
        let raw = try postgres("found_comment_request")
        let found = try JSONDecoder().decode(ProfileActivitySocialMutationResult.self,from:raw)
        let (_,stub,row,r) = try postgresAdapter("found_comment_request")
        let journal = MemoryProfileActivitySocialJournal()
        let request = ProfileActivitySocialPending(id:found.request_id,receipt:r,operation:found.operation,payload:try XCTUnwrap(found.payload))
        journal.values = [request]
        let c = AccountActivityInteractionContext(viewerID:r.viewer_id,generation:1,safetyRevision:1,storageScopeID:r.viewer_id.uuidString.lowercased())
        let a = ProfileActivitySocialAdapter(transport:stub,context:{c},journal:journal)
        let resolved = try await a.resolve(row:row,request:request,retryIfAbsent:true)
        XCTAssertTrue(resolved)
        XCTAssertTrue(journal.values.isEmpty)
        XCTAssertEqual(stub.calls.map(\.0),["soom_activity_social_request_status_candidate_v2"])
    }

    // Legacy SQL shape adapted with explicit single-source fields; historical raw SHA256: d4720cb3acc4ccfad1b41c39654c8ff81474e516994ed21b16edabdbe970e313
    private static let postgresFixture = #"""
{"mentions": {"rows": [{"id": "a95dc583-796f-9823-9ecc-147995af54ad", "handle": "socialfixture1", "avatar_path": null, "display_name": "SOOM 사용자"}], "receipt": {"backing": "legacy", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "release_ready": true, "profile_revision": 1, "projection_revision": 1, "write_backing": "legacy", "read_sources": [{"source_kind": "legacy", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788"}], "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}, "legacy_status": {"state": "ready", "receipt": {"backing": "legacy", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "release_ready": true, "profile_revision": 1, "projection_revision": 1, "write_backing": "legacy", "read_sources": [{"source_kind": "legacy", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788"}], "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "cheer_count": 0, "comment_count": 2, "latest_comment_at": "2026-11-14T17:22:40.691061+09:00", "viewer_has_cheered": false}, "native_status": {"state": "ready", "receipt": {"backing": "native", "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "374dab0a-fdae-17b7-8e57-0fb2371ec110", "release_ready": true, "profile_revision": 1, "projection_revision": 1, "write_backing": "native", "read_sources": [{"source_kind": "native", "source_id": "eba4f61f-48bf-0c18-811f-496efa16051c"}], "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "cheer_count": 1, "comment_count": 1, "latest_comment_at": "2026-11-14T17:22:40.691061+09:00", "viewer_has_cheered": true}, "legacy_comments": {"rows": [{"id": "89e261c9-d2e9-18ca-f269-8c5845415b7d", "body": "Existing synthetic comment", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": "a95dc583-796f-9823-9ecc-147995af54ad", "parent_id": null, "created_at": "2019-01-01T00:00:00+09:00", "is_deleted": false, "reply_to_id": null, "author_profile": {"id": "a95dc583-796f-9823-9ecc-147995af54ad", "handle": "socialfixture1", "avatar_path": null, "display_name": "SOOM 사용자"}, "source_kind": "legacy", "parent_source": null, "reply_to_source": null}, {"id": "0ba02826-b8e9-9d40-b637-67b59819a0e5", "body": "Reply @socialfixture1", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [{"handle": "socialfixture1", "user_id": "a95dc583-796f-9823-9ecc-147995af54ad"}], "author_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "parent_id": "fceb5502-51c3-43f0-6138-fa3e16175164", "created_at": "2026-11-14T17:22:40.691061+09:00", "is_deleted": false, "reply_to_id": "fceb5502-51c3-43f0-6138-fa3e16175164", "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}, "source_kind": "legacy", "parent_source": "legacy", "reply_to_source": "legacy"}, {"id": "fceb5502-51c3-43f0-6138-fa3e16175164", "body": "", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": null, "parent_id": null, "created_at": "2026-11-14T17:22:40.691061+09:00", "is_deleted": true, "reply_to_id": null, "author_profile": null, "source_kind": "legacy", "parent_source": null, "reply_to_source": null}], "parents": [], "receipt": {"backing": "legacy", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "release_ready": true, "profile_revision": 1, "projection_revision": 1, "write_backing": "legacy", "read_sources": [{"source_kind": "legacy", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788"}], "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "next_cursor": null}, "native_comments": {"rows": [{"id": "f7bca4be-e90c-4579-5a63-98aab71fd043", "body": "Native comment", "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "mentions": [], "author_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "parent_id": null, "created_at": "2026-11-14T17:22:40.691061+09:00", "is_deleted": false, "reply_to_id": null, "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}, "source_kind": "native", "parent_source": null, "reply_to_source": null}], "parents": [], "receipt": {"backing": "native", "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "374dab0a-fdae-17b7-8e57-0fb2371ec110", "release_ready": true, "profile_revision": 1, "projection_revision": 1, "write_backing": "native", "read_sources": [{"source_kind": "native", "source_id": "eba4f61f-48bf-0c18-811f-496efa16051c"}], "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "next_cursor": null}, "native_reactions": {"rows": [{"id": "da134276-d9c5-417b-8545-595cfd808a7b", "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "user_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "created_at": "2026-11-14T17:22:40.691061+09:00", "reaction_type": "cheer", "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}, "source_kind": "native", "provenance": [{"source_kind": "native", "id": "da134276-d9c5-417b-8545-595cfd808a7b"}]}], "receipt": {"backing": "native", "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "374dab0a-fdae-17b7-8e57-0fb2371ec110", "release_ready": true, "profile_revision": 1, "projection_revision": 1, "write_backing": "native", "read_sources": [{"source_kind": "native", "source_id": "eba4f61f-48bf-0c18-811f-496efa16051c"}], "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "next_cursor": null}, "found_comment_request": {"state": "found", "result": {"comment_id": "fceb5502-51c3-43f0-6138-fa3e16175164", "source_kind": "legacy"}, "payload": {"body": "Root social comment", "mentions": [], "comment_id": "fceb5502-51c3-43f0-6138-fa3e16175164", "parent_comment_id": null, "source_kind": "legacy"}, "receipt": {"backing": "legacy", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "release_ready": true, "profile_revision": 1, "projection_revision": 1, "write_backing": "legacy", "read_sources": [{"source_kind": "legacy", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788"}], "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "operation": "comment_add", "request_id": "fceb5502-51c3-43f0-6138-fa3e16175164", "cheer_count": 0, "comment_count": 2, "latest_comment_at": "2026-11-14T17:22:40.691061+09:00", "viewer_has_cheered": false}}
"""#

}
