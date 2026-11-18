import XCTest
@testable import SOOM

@MainActor private final class MixedSocialContractStub: ProfileActivitySocialTransport {
    var response = Data()
    var handler: ((String, ProfileActivitySocialParameters) throws -> Data)?
    var calls: [(String, ProfileActivitySocialParameters)] = []
    func call(_ name: String, params: ProfileActivitySocialParameters) async throws -> Data {
        calls.append((name, params)); if let handler { return try handler(name, params) }; return response
    }
}
@MainActor final class ProfileSocialMixedContractTests: XCTestCase {
    private var fixture: Data { Data(#"""
{"status": {"state": "ready", "receipt": {"backing": "mixed", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "read_sources": [{"source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "source_kind": "legacy"}, {"source_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "source_kind": "native"}], "release_ready": true, "write_backing": "legacy", "source_revision": "abb5b4bf6a2b9b487c4f242f05043ba5", "profile_revision": 1, "projection_revision": 1}, "cheer_count": 2, "comment_count": 8, "latest_comment_at": "2026-11-14T18:11:09.242901+09:00", "viewer_has_cheered": true}, "comments": {"rows": [{"id": "89e261c9-d2e9-18ca-f269-8c5845415b7d", "body": "Existing synthetic comment", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": "a95dc583-796f-9823-9ecc-147995af54ad", "parent_id": null, "created_at": "2019-01-01T00:00:00+09:00", "is_deleted": false, "reply_to_id": null, "source_kind": "legacy", "parent_source": null, "author_profile": {"id": "a95dc583-796f-9823-9ecc-147995af54ad", "handle": "socialfixture1", "avatar_path": null, "display_name": "SOOM 사용자"}, "reply_to_source": null}, {"id": "89e261c9-d2e9-18ca-f269-8c5845415b7d", "body": "", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": null, "parent_id": null, "created_at": "2019-01-01T00:00:00+09:00", "is_deleted": true, "reply_to_id": null, "source_kind": "native", "parent_source": null, "author_profile": null, "reply_to_source": null}, {"id": "76eb5f57-ee4b-f6c1-d597-05e2f979a425", "body": "Native chronological second", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "parent_id": null, "created_at": "2019-01-02T00:00:00+09:00", "is_deleted": false, "reply_to_id": null, "source_kind": "native", "parent_source": null, "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}, "reply_to_source": null}, {"id": "990a3f63-4dc1-5dd6-7d75-324a45b69605", "body": "Native different author", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": "ec80a615-a6a5-d94a-e184-dd3515996035", "parent_id": null, "created_at": "2019-01-03T00:00:00+09:00", "is_deleted": false, "reply_to_id": null, "source_kind": "native", "parent_source": null, "author_profile": {"id": "ec80a615-a6a5-d94a-e184-dd3515996035", "handle": "socialfixture3", "avatar_path": null, "display_name": "SOOM 사용자"}, "reply_to_source": null}, {"id": "0ba02826-b8e9-9d40-b637-67b59819a0e5", "body": "Reply @socialfixture1", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [{"handle": "socialfixture1", "user_id": "a95dc583-796f-9823-9ecc-147995af54ad"}], "author_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "parent_id": "fceb5502-51c3-43f0-6138-fa3e16175164", "created_at": "2026-11-14T18:11:07.649245+09:00", "is_deleted": false, "reply_to_id": "fceb5502-51c3-43f0-6138-fa3e16175164", "source_kind": "legacy", "parent_source": "legacy", "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}, "reply_to_source": "legacy"}, {"id": "fceb5502-51c3-43f0-6138-fa3e16175164", "body": "", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": null, "parent_id": null, "created_at": "2026-11-14T18:11:07.649245+09:00", "is_deleted": true, "reply_to_id": null, "source_kind": "legacy", "parent_source": null, "author_profile": null, "reply_to_source": null}, {"id": "1c9e87c7-5777-6894-505c-5b0027cd844c", "body": "Reply legacy collision", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "parent_id": "89e261c9-d2e9-18ca-f269-8c5845415b7d", "created_at": "2026-11-14T18:11:09.242901+09:00", "is_deleted": false, "reply_to_id": "89e261c9-d2e9-18ca-f269-8c5845415b7d", "source_kind": "legacy", "parent_source": "legacy", "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}, "reply_to_source": "legacy"}, {"id": "9b6ebbce-1b86-ebf6-aed2-326ca005937d", "body": "Root in original legacy source", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "parent_id": null, "created_at": "2026-11-14T18:11:09.242901+09:00", "is_deleted": false, "reply_to_id": null, "source_kind": "legacy", "parent_source": null, "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}, "reply_to_source": null}, {"id": "5e8094b2-ab81-7a8d-7fd1-5de2b7632f9a", "body": "Old native writer registered source", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "parent_id": null, "created_at": "2026-11-14T18:11:09.242901+09:00", "is_deleted": false, "reply_to_id": null, "source_kind": "native", "parent_source": null, "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}, "reply_to_source": null}, {"id": "f676cbf0-0e0e-0968-631a-154f734ec726", "body": "Reply native collision", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "mentions": [], "author_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "parent_id": "89e261c9-d2e9-18ca-f269-8c5845415b7d", "created_at": "2026-11-14T18:11:09.242901+09:00", "is_deleted": false, "reply_to_id": "89e261c9-d2e9-18ca-f269-8c5845415b7d", "source_kind": "native", "parent_source": "native", "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}, "reply_to_source": "native"}], "parents": [], "receipt": {"backing": "mixed", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "read_sources": [{"source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "source_kind": "legacy"}, {"source_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "source_kind": "native"}], "release_ready": true, "write_backing": "legacy", "source_revision": "abb5b4bf6a2b9b487c4f242f05043ba5", "profile_revision": 1, "projection_revision": 1}, "next_cursor": null}, "expected": {"backing": "mixed", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "read_sources": [{"source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "source_kind": "legacy"}, {"source_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "source_kind": "native"}], "write_backing": "legacy", "source_revision": "abb5b4bf6a2b9b487c4f242f05043ba5", "profile_revision": 1, "projection_revision": 1}, "reactions": {"rows": [{"id": "ca8e69a1-7a36-c8d3-05c0-6202ac4d7550", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "user_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "created_at": "2026-11-14T18:11:09.242901+09:00", "provenance": [{"id": "ca8e69a1-7a36-c8d3-05c0-6202ac4d7550", "source_kind": "legacy"}, {"id": "c47ac7ba-e320-6792-2a35-a6b5ed8d270f", "source_kind": "native"}], "source_kind": "legacy", "reaction_type": "cheer", "author_profile": {"id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "handle": "socialfixture2", "avatar_path": null, "display_name": "SOOM 사용자"}}, {"id": "ea76481a-cbe6-fb3b-179a-ed741b76dd47", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "user_id": "ec80a615-a6a5-d94a-e184-dd3515996035", "created_at": "2026-11-14T18:11:09.242901+09:00", "provenance": [{"id": "ea76481a-cbe6-fb3b-179a-ed741b76dd47", "source_kind": "legacy"}, {"id": "074292ba-7e0e-6e4e-9c97-8c82efc49d5f", "source_kind": "native"}], "source_kind": "legacy", "reaction_type": "cheer", "author_profile": {"id": "ec80a615-a6a5-d94a-e184-dd3515996035", "handle": "socialfixture3", "avatar_path": null, "display_name": "SOOM 사용자"}}], "receipt": {"backing": "mixed", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "read_sources": [{"source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "source_kind": "legacy"}, {"source_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "source_kind": "native"}], "release_ready": true, "write_backing": "legacy", "source_revision": "abb5b4bf6a2b9b487c4f242f05043ba5", "profile_revision": 1, "projection_revision": 1}, "next_cursor": null}}

"""#.utf8) }
    private func section(_ key: String) throws -> Data {
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: XCTUnwrap(all[key]))
    }
    private func status() throws -> ProfileActivitySocialStatus { try JSONDecoder().decode(ProfileActivitySocialStatus.self, from: section("status")) }
    private func localData(_ key: String) throws -> Data {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: section(key)) as? [String: Any])
        var receipt = try XCTUnwrap(value["receipt"] as? [String: Any]); receipt["release_ready"] = false; value["receipt"] = receipt
        return try JSONSerialization.data(withJSONObject: value)
    }
    private func localReceipt() throws -> ProfileActivitySocialReceipt {
        try JSONDecoder().decode(ProfileActivitySocialStatus.self, from: localData("status")).receipt
    }
    private func projection(_ r: ProfileActivitySocialReceipt) -> AccountActivityFeedRow {
        .init(cardID:r.card_id,canonicalID:r.canonical_id,ownerID:r.owner_id,sport:"running",activityAt:"2020-01-01T00:00:00Z",durationSeconds:600,distanceMeters:1000,revision:r.projection_revision,readPolicy:.profileOnlyV2)
    }
    private func adapter(_ stub: MixedSocialContractStub, _ r: ProfileActivitySocialReceipt) -> ProfileActivitySocialAdapter {
        .localFixture(transport:stub,context:{ .init(viewerID:r.viewer_id,generation:1,safetyRevision:1,storageScopeID:r.viewer_id.uuidString.lowercased()) },journal:MemoryProfileActivitySocialJournal())
    }
    func testActualSQLMixedReceiptHasExactImmutableRouting() throws {
        let r = try status().receipt
        XCTAssertTrue(r.hasValidRouting); XCTAssertEqual(r.backing,"mixed"); XCTAssertEqual(r.write_backing,"legacy")
        XCTAssertEqual(r.expected.read_sources,r.read_sources); XCTAssertEqual(r.expected.source_revision,r.source_revision)
    }
    func testMalformedSourceRegistryCannotAuthorize() throws {
        var r = try status().receipt; r.read_sources = Array((r.read_sources ?? []).reversed()); XCTAssertFalse(r.hasValidRouting)
        r = try status().receipt; r.source_revision = nil; XCTAssertFalse(r.hasValidRouting)
        r = try status().receipt; r.read_sources = [.init(source_kind:"legacy",source_id:r.source_id),.init(source_kind:"native",source_id:UUID())]; XCTAssertFalse(r.hasValidRouting)
    }
    func testActualSQLSameUUIDTwoSourcesPreservedByAdapter() async throws {
        let r = try localReceipt(), stub = MixedSocialContractStub(); stub.response = try localData("comments")
        let page = try await adapter(stub,r).comments(row:projection(r),receipt:r)
        XCTAssertEqual(Set(page.rows.map(\.sourceKey)).count,page.rows.count)
        XCTAssertLessThan(Set(page.rows.map(\.id)).count,page.rows.count)
        XCTAssertTrue(page.rows.contains(where:{$0.is_deleted && $0.author_id == nil}))
    }
    func testCrossSourceParentSpoofRejected() async throws {
        let r = try localReceipt(), stub = MixedSocialContractStub()
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with:localData("comments")) as? [String:Any])
        var rows = try XCTUnwrap(data["rows"] as? [[String:Any]])
        let i = try XCTUnwrap(rows.firstIndex(where:{ $0["parent_id"] is String }))
        rows[i]["parent_source"] = rows[i]["source_kind"] as? String == "legacy" ? "native" : "legacy"; data["rows"] = rows
        stub.response = try JSONSerialization.data(withJSONObject:data)
        do { _ = try await adapter(stub,r).comments(row:projection(r),receipt:r); XCTFail("Cross-source chain must fail") } catch {}
    }
    func testActualSQLCheersHaveDistinctActorsAndOriginalProvenance() async throws {
        let r = try localReceipt(), stub = MixedSocialContractStub(); stub.response = try localData("reactions")
        let page = try await adapter(stub,r).reactions(row:projection(r),receipt:r)
        XCTAssertEqual(Set(page.rows.map(\.user_id)).count,page.rows.count)
        XCTAssertTrue(page.rows.contains(where:{ ($0.provenance?.count ?? 0) == 2 }))
    }
    func testNewRootAndNativeReplySendOriginalSourceNotUISurrogate() async throws {
        let r = try localReceipt(), stub = MixedSocialContractStub()
        stub.handler = { _, p in
            let payload = try XCTUnwrap(p.p_payload), id = try XCTUnwrap(p.p_request_id)
            let receipt = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r))
            let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload))
            return try JSONSerialization.data(withJSONObject:["receipt":receipt,"request_id":id.uuidString,
                "operation":p.p_operation!,"state":"found","payload":body,
                "result":["comment_id":payload.comment_id!.uuidString,"source_kind":payload.source_kind!]])
        }
        let api = adapter(stub,r), rawParent = UUID()
        try await api.addComment(row:projection(r),receipt:r,body:"root",parentID:nil,mentions:[])
        XCTAssertEqual(stub.calls.last?.1.p_payload?.source_kind,"legacy")
        try await api.addComment(row:projection(r),receipt:r,body:"reply",parentID:rawParent,mentions:[],parentSource:"native")
        XCTAssertEqual(stub.calls.last?.1.p_payload?.source_kind,"native")
        XCTAssertEqual(stub.calls.last?.1.p_payload?.parent_comment_id,rawParent)
        XCTAssertEqual(stub.calls.last?.1.p_expected?.source_revision,r.source_revision)
    }
    func testUnspecifiedReplySourceRejectedBeforeTransport() async throws {
        let r = try localReceipt(), stub = MixedSocialContractStub()
        do { try await adapter(stub,r).addComment(row:projection(r),receipt:r,body:"reply",parentID:UUID(),mentions:[]); XCTFail() } catch {}
        XCTAssertTrue(stub.calls.isEmpty)
    }
    private func hundredParentPage(_ receipt: ProfileActivitySocialReceipt, extra: Bool = false) throws -> Data {
        func id(_ n: Int) -> String { String(format: "CA000000-0000-4000-8000-%012d", n) }
        func comment(_ n: Int, source: String, parent: String?, reply: String?) -> [String: Any] {
            ["id":id(n), "card_id":receipt.card_id.uuidString, "source_kind":source,
             "author_id":receipt.owner_id.uuidString, "author_profile":NSNull(), "body":"parent cap fixture",
             "created_at":"2020-01-01T00:00:00Z", "is_deleted":false, "mentions":[],
             "parent_id":parent as Any? ?? NSNull(), "reply_to_id":reply as Any? ?? NSNull(),
             "parent_source":parent == nil ? NSNull() : source as Any,
             "reply_to_source":reply == nil ? NSNull() : source as Any]
        }
        var parents: [[String:Any]] = [], rows: [[String:Any]] = []
        for n in 1...50 {
            let source = n <= 25 ? "legacy" : "native"
            parents.append(comment(n,source:source,parent:nil,reply:nil))
            parents.append(comment(n+50,source:source,parent:id(n),reply:id(n)))
            rows.append(comment(n+100,source:source,parent:id(n),reply:id(n+50)))
        }
        if extra { parents.append(comment(999,source:"legacy",parent:nil,reply:nil)) }
        let r = try JSONSerialization.jsonObject(with:JSONEncoder().encode(receipt))
        return try JSONSerialization.data(withJSONObject:["receipt":r,"rows":rows,"parents":parents,"next_cursor":NSNull()])
    }
    func testFiftyRowsMayReturnHundredDistinctTypedRootAndReplyParents() async throws {
        let r = try localReceipt(), stub = MixedSocialContractStub()
        stub.response = try hundredParentPage(r)
        let result = try await adapter(stub,r).comments(row:projection(r),receipt:r)
        XCTAssertEqual(result.rows.count,50); XCTAssertEqual(result.parents.count,100)
        XCTAssertEqual(Set(result.parents.map(\.sourceKey)).count,100)
        XCTAssertEqual(Set(result.parents.compactMap(\.source_kind)),Set(["legacy","native"]))
    }
    func testMoreThanHundredSupplementalParentsRejected() async throws {
        let r = try localReceipt(), stub = MixedSocialContractStub()
        stub.response = try hundredParentPage(r,extra:true)
        do { _ = try await adapter(stub,r).comments(row:projection(r),receipt:r); XCTFail() }
        catch { XCTAssertEqual(error as? ProfileActivitySocialError,.malformed) }
    }
    func testUISurrogatesAreStableBijectiveAndNeverOriginalRouting() {
        let raw = UUID(), a = ProfileSocialSourceKey(source_kind:"legacy",id:UUID()), b = ProfileSocialSourceKey(source_kind:"native",id:UUID())
        var map = ProfileSocialPresentationIdentity()
        let sameA = ProfileSocialSourceKey(source_kind:"legacy",id:raw), sameB = ProfileSocialSourceKey(source_kind:"native",id:raw)
        let x = map.presentationID(for:sameA), y = map.presentationID(for:sameB)
        XCTAssertNotEqual(x,y); XCTAssertEqual(map.presentationID(for:sameA),x)
        XCTAssertEqual(map.sourceKey(for:x),sameA); XCTAssertEqual(map.sourceKey(for:y),sameB)
        XCTAssertNotEqual(map.presentationID(for:a),map.presentationID(for:b))
        map.reset(); XCTAssertNil(map.sourceKey(for:x))
    }
    func testSessionMismatchCannotAuthorizeCachedBatch() {
        let viewer = UUID()
        XCTAssertNil(AccountActivityReturnBatchPolicy.verifiedViewer(sessionID:nil,safetyViewerID:viewer))
        XCTAssertNil(AccountActivityReturnBatchPolicy.verifiedViewer(sessionID:UUID(),safetyViewerID:viewer))
        XCTAssertNil(AccountActivityReturnBatchPolicy.verifiedViewer(sessionID:viewer,safetyViewerID:nil))
        XCTAssertEqual(AccountActivityReturnBatchPolicy.verifiedViewer(sessionID:viewer,safetyViewerID:viewer),viewer)
    }
    func testOldJournalReceiptDecodesButDoesNotGainRoutingAuthority() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:section("status")) as? [String:Any])
        var r = try XCTUnwrap(object["receipt"] as? [String:Any]); r.removeValue(forKey:"read_sources"); r.removeValue(forKey:"write_backing"); r.removeValue(forKey:"source_revision"); object["receipt"] = r
        let decoded = try JSONDecoder().decode(ProfileActivitySocialStatus.self,from:JSONSerialization.data(withJSONObject:object)).receipt
        XCTAssertFalse(decoded.hasValidRouting); XCTAssertNil(decoded.read_sources); XCTAssertNil(decoded.source_revision)
    }
}
