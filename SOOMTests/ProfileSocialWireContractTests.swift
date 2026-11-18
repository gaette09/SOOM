import XCTest
import Supabase
@testable import SOOM

private final class SocialWireHTTP: URLProtocol {
    static let lock = NSLock()
    static var expected: [String: Any] = [:]
    static var bodies: [[String: Any]] = []
    static func configure(_ value: [String: Any]) { lock.lock(); defer { lock.unlock() }; expected=value; bodies=[] }
    static func captured() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return bodies }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "social-wire.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var buffer=[UInt8](repeating:0,count:4096)
                while stream.hasBytesAvailable { let count=stream.read(&buffer,maxLength:buffer.count); if count<0 { throw URLError(.cannotDecodeRawData) }; if count==0 { break }; data.append(buffer,count:count) }
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
            Self.lock.lock(); Self.bodies.append(body); let expected=Self.expected; Self.lock.unlock()
            let path = request.url?.path ?? ""
            let prefix = "/rest/v1/rpc/soom_activity_social_"
            guard path.hasPrefix(prefix), path.hasSuffix("_candidate_v2") else { throw URLError(.unsupportedURL) }
            let suffix = String(path.dropFirst(prefix.count).dropLast("_candidate_v2".count))
            let shapes: [String:Set<String>] = [
                "status":["p_card_id"], "comments":["p_card_id","p_expected","p_limit"],
                "reactions":["p_card_id","p_expected","p_limit"], "mentions":["p_card_id","p_expected","p_limit","p_query"],
                "mutate":["p_card_id","p_expected","p_request_id","p_operation","p_payload"],
                "request_status":["p_card_id","p_expected","p_request_id","p_operation","p_payload"]]
            guard request.httpMethod == "POST", shapes[suffix] == Set(body.keys) else { throw URLError(.badServerResponse) }
            let value=body["p_expected"] as? [String:Any]
            let accepted = suffix == "status" || (value != nil && NSDictionary(dictionary:value!).isEqual(to:expected))
            let response=HTTPURLResponse(url:request.url!,statusCode:accepted ? 200:403,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:Data((accepted ? "{}" : #"{"code":"42501","message":"social_stale_receipt","details":null,"hint":null}"#).utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}

@MainActor final class ProfileSocialWireContractTests: XCTestCase {
    let card=UUID(uuidString:"abcdef01-aaaa-4bbb-8ccc-abcdef012345")!
    let source=UUID(uuidString:"fedcba01-bbbb-4ccc-8ddd-fedcba012345")!
    func receipt(_ backing:String) -> ProfileActivitySocialReceipt {
        let write=backing == "native" ? "native":"legacy", id=backing == "native" ? card:source
        return .init(version:2,viewer_id:card,card_id:card,owner_id:source,canonical_id:source,projection_revision:7,profile_revision:8,backing:backing,source_id:id,release_ready:true,
            write_backing:write,read_sources:backing == "mixed" ? [.init(source_kind:"legacy",source_id:source),.init(source_kind:"native",source_id:card)] : [.init(source_kind:write,source_id:id)],source_revision:String(repeating:"a",count:32))
    }
    func sqlExpected(_ r:ProfileActivitySocialReceipt) -> [String:Any] {
        ["backing":r.backing,"source_id":r.source_id.uuidString.lowercased(),"projection_revision":r.projection_revision,"profile_revision":r.profile_revision,
         "write_backing":r.write_backing!,"read_sources":r.read_sources!.map {["source_kind":$0.source_kind,"source_id":$0.source_id.uuidString.lowercased()]},"source_revision":r.source_revision!]
    }
    func sdk() -> SupabaseClient {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[SocialWireHTTP.self]
        return SupabaseClient(supabaseURL:URL(string:"https://social-wire.invalid")!,supabaseKey:"synthetic-not-a-credential",
            options:.init(auth:.init(autoRefreshToken:false,emitLocalSessionAsInitialSession:false),global:.init(session:URLSession(configuration:config))))
    }
    func testActualSDKAllSocialRPCEndsEncodeExactSQLLowercaseExpectedForEveryBacking() async throws {
        for backing in ["legacy","native","mixed"] {
            let r=receipt(backing);SocialWireHTTP.configure(sqlExpected(r));let transport=SupabaseProfileActivitySocialTransport(client:sdk())
            for suffix in ["status","comments","reactions","mentions","mutate","request_status"] {
                var p=ProfileActivitySocialParameters(p_card_id:card)
                switch suffix {
                case "comments", "reactions": p.p_expected=r.expected; p.p_limit=50
                case "mentions": p.p_expected=r.expected; p.p_limit=5; p.p_query="HandleCASE"
                case "mutate", "request_status":
                    p.p_expected=r.expected; p.p_request_id=source; p.p_operation="comment_add"
                    p.p_payload = .init(comment_id:source,body:"KEEP ABCDEF01 and HandleCASE",mentions:[.init(userID:card,handle:"HandleCASE")],source_kind:r.write_backing)
                default: break
                }
                _ = try await transport.call("soom_activity_social_\(suffix)_candidate_v2",params:p)
            }
            let bodies=SocialWireHTTP.captured();XCTAssertEqual(bodies.count,6)
            XCTAssertNil(bodies[0]["p_expected"])
            for body in bodies.dropFirst() {
                XCTAssertTrue(NSDictionary(dictionary:try XCTUnwrap(body["p_expected"] as? [String:Any])).isEqual(to:sqlExpected(r)))
                if let payload=body["p_payload"] as? [String:Any] {
                    XCTAssertEqual(payload["body"] as? String,"KEEP ABCDEF01 and HandleCASE")
                    let mentions=try XCTUnwrap(payload["mentions"] as? [[String:Any]]);XCTAssertEqual(mentions.first?["handle"] as? String,"HandleCASE")
                }
            }
        }
    }
    func testDefaultUUIDWireCaseReproducesStrictJSONBStaleReceiptAtHTTPBoundary() async throws {
        struct UpperSource:Encodable { let source_kind:String;let source_id:UUID }
        struct UpperExpected:Encodable {let backing:String;let source_id:UUID;let projection_revision:Int;let profile_revision:Int;let write_backing:String;let read_sources:[UpperSource];let source_revision:String}
        struct Params:Encodable {let p_card_id:UUID;let p_expected:UpperExpected;let p_limit:Int}
        let r=receipt("mixed");SocialWireHTTP.configure(sqlExpected(r))
        let value=UpperExpected(backing:"mixed",source_id:source,projection_revision:7,profile_revision:8,write_backing:"legacy",read_sources:[.init(source_kind:"legacy",source_id:source),.init(source_kind:"native",source_id:card)],source_revision:String(repeating:"a",count:32))
        do { _ = try await sdk().rpc("soom_activity_social_comments_candidate_v2",params:Params(p_card_id:card,p_expected:value,p_limit:50)).execute();XCTFail("Old synthesized UUID wire must fail strict expected equality") }
        catch let error as PostgrestError { XCTAssertEqual(error.code,"42501");XCTAssertEqual(error.message,"social_stale_receipt") }
    }
    func testSavedRequestRoundtripPreservesIdentityAndCanonicalExpectedOnRecoveryHTTP() async throws {
        let r=receipt("mixed"), request=ProfileActivitySocialPending(id:source,receipt:receipt("mixed"),operation:"comment_add",payload:.init(comment_id:source,body:"Unchanged ABCD",mentions:[],source_kind:"legacy"))
        let decoded=try JSONDecoder().decode(ProfileActivitySocialPending.self,from:JSONEncoder().encode(request))
        XCTAssertEqual(decoded,request);SocialWireHTTP.configure(sqlExpected(r))
        let p=ProfileActivitySocialParameters(p_card_id:card,p_expected:decoded.receipt.expected,p_request_id:decoded.id,p_operation:decoded.operation,p_payload:decoded.payload)
        _ = try await SupabaseProfileActivitySocialTransport(client:sdk()).call("soom_activity_social_request_status_candidate_v2",params:p)
        let body=try XCTUnwrap(SocialWireHTTP.captured().first)
        XCTAssertEqual(UUID(uuidString:try XCTUnwrap(body["p_request_id"] as? String)),request.id)
        XCTAssertTrue(NSDictionary(dictionary:try XCTUnwrap(body["p_expected"] as? [String:Any])).isEqual(to:sqlExpected(r)))
    }
}

// Pseudonymized/masked actual shape fixture SHA256: 03a101918c3d911fc0fea5ee69b747d8da901880466aec0157afce8abda1446c


@MainActor private final class Build58ActualShapeTransport: ProfileActivitySocialTransport {
    let payload: [String:Any]
    init(_ data:Data) throws { payload = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]) }
    func call(_ name:String,params:ProfileActivitySocialParameters) async throws -> Data {
        let key = name.contains("_comments_") ? "comments" : "status"
        return try JSONSerialization.data(withJSONObject:try XCTUnwrap(payload[key]))
    }
}
@MainActor private final class Build58BrokenJournal: ProfileActivitySocialJournal {
    var writes=0
    func read() throws -> [ProfileActivitySocialPending] { throw CocoaError(.fileReadCorruptFile) }
    func write(_ values:[ProfileActivitySocialPending]) throws { writes += 1 }
}
extension ProfileSocialWireContractTests {
    private var maskedActualFixture:Data { Data(#"""
{
  "status": {
    "state": "ready",
    "receipt": {
      "backing": "mixed",
      "card_id": "bb19efe6-8d38-5c5b-ae6d-0a7aa9b410dc",
      "version": 2,
      "owner_id": "c5742656-1519-5d57-bc2a-eb0067d05724",
      "source_id": "aa583238-e66b-544d-84ad-91bef77209b5",
      "viewer_id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
      "canonical_id": "b9d059de-8943-5668-b7c5-b5e64f551eb5",
      "read_sources": [
        {
          "source_id": "aa583238-e66b-544d-84ad-91bef77209b5",
          "source_kind": "legacy"
        },
        {
          "source_id": "bb19efe6-8d38-5c5b-ae6d-0a7aa9b410dc",
          "source_kind": "native"
        }
      ],
      "release_ready": true,
      "write_backing": "legacy",
      "source_revision": "7a77821986738691e6ae087713a2c21e",
      "profile_revision": 1,
      "projection_revision": 1
    },
    "cheer_count": 1,
    "comment_count": 4,
    "latest_comment_at": "2000-11-14T07:40:07.398409+00:00",
    "viewer_has_cheered": true
  },
  "masking": "SYNTHETIC fixture from actual JSON structure: all UUIDs pseudonymized consistently; timestamp year shifted to 2000 preserving format/order; original body/name/handle/avatar text masked server-side. NEVER use fixture identifiers against production.",
  "section": "masked_contract",
  "comments": {
    "rows": [
      {
        "id": "96b90c28-c7db-58b3-b59d-aa4798690892",
        "body": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
        "card_id": "bb19efe6-8d38-5c5b-ae6d-0a7aa9b410dc",
        "mentions": [],
        "author_id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
        "parent_id": null,
        "created_at": "2000-11-09T12:25:01.435061+00:00",
        "is_deleted": false,
        "reply_to_id": null,
        "source_kind": "legacy",
        "parent_source": null,
        "author_profile": {
          "id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
          "handle": null,
          "avatar_path": "redacted/avatar.jpg",
          "display_name": "redacted"
        },
        "reply_to_source": null
      },
      {
        "id": "cf173e84-55ff-5897-8b7b-10663f09b1a2",
        "body": "xxxxxxxxx",
        "card_id": "bb19efe6-8d38-5c5b-ae6d-0a7aa9b410dc",
        "mentions": [],
        "author_id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
        "parent_id": null,
        "created_at": "2000-11-14T07:39:51.949425+00:00",
        "is_deleted": false,
        "reply_to_id": null,
        "source_kind": "native",
        "parent_source": null,
        "author_profile": {
          "id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
          "handle": null,
          "avatar_path": "redacted/avatar.jpg",
          "display_name": "redacted"
        },
        "reply_to_source": null
      },
      {
        "id": "176b6d97-9d30-53d3-9ed0-36376fc0a27b",
        "body": "x",
        "card_id": "bb19efe6-8d38-5c5b-ae6d-0a7aa9b410dc",
        "mentions": [],
        "author_id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
        "parent_id": null,
        "created_at": "2000-11-14T07:39:55.840429+00:00",
        "is_deleted": false,
        "reply_to_id": null,
        "source_kind": "native",
        "parent_source": null,
        "author_profile": {
          "id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
          "handle": null,
          "avatar_path": "redacted/avatar.jpg",
          "display_name": "redacted"
        },
        "reply_to_source": null
      },
      {
        "id": "d06a1ab4-e33a-522e-9813-16994f3da0a1",
        "body": "x",
        "card_id": "bb19efe6-8d38-5c5b-ae6d-0a7aa9b410dc",
        "mentions": [],
        "author_id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
        "parent_id": "cf173e84-55ff-5897-8b7b-10663f09b1a2",
        "created_at": "2000-11-14T07:40:07.398409+00:00",
        "is_deleted": false,
        "reply_to_id": "cf173e84-55ff-5897-8b7b-10663f09b1a2",
        "source_kind": "native",
        "parent_source": "native",
        "author_profile": {
          "id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
          "handle": null,
          "avatar_path": "redacted/avatar.jpg",
          "display_name": "redacted"
        },
        "reply_to_source": "native"
      }
    ],
    "parents": [],
    "receipt": {
      "backing": "mixed",
      "card_id": "bb19efe6-8d38-5c5b-ae6d-0a7aa9b410dc",
      "version": 2,
      "owner_id": "c5742656-1519-5d57-bc2a-eb0067d05724",
      "source_id": "aa583238-e66b-544d-84ad-91bef77209b5",
      "viewer_id": "2d55110f-eec9-54c8-b720-96f2e09b7e23",
      "canonical_id": "b9d059de-8943-5668-b7c5-b5e64f551eb5",
      "read_sources": [
        {
          "source_id": "aa583238-e66b-544d-84ad-91bef77209b5",
          "source_kind": "legacy"
        },
        {
          "source_id": "bb19efe6-8d38-5c5b-ae6d-0a7aa9b410dc",
          "source_kind": "native"
        }
      ],
      "release_ready": true,
      "write_backing": "legacy",
      "source_revision": "7a77821986738691e6ae087713a2c21e",
      "profile_revision": 1,
      "projection_revision": 1
    },
    "next_cursor": null
  },
  "shape_audit": [
    {
      "body_type": "string",
      "source_kind": "legacy",
      "mentions_type": "array",
      "body_characters": 44,
      "created_at_type": "string",
      "is_deleted_type": "boolean",
      "display_name_type": "string",
      "author_profile_type": "object"
    },
    {
      "body_type": "string",
      "source_kind": "native",
      "mentions_type": "array",
      "body_characters": 9,
      "created_at_type": "string",
      "is_deleted_type": "boolean",
      "display_name_type": "string",
      "author_profile_type": "object"
    },
    {
      "body_type": "string",
      "source_kind": "native",
      "mentions_type": "array",
      "body_characters": 1,
      "created_at_type": "string",
      "is_deleted_type": "boolean",
      "display_name_type": "string",
      "author_profile_type": "object"
    },
    {
      "body_type": "string",
      "source_kind": "native",
      "mentions_type": "array",
      "body_characters": 1,
      "created_at_type": "string",
      "is_deleted_type": "boolean",
      "display_name_type": "string",
      "author_profile_type": "object"
    }
  ],
  "synthetic_fixture": true
}

"""#.utf8) }
    func testMaskedActualServerFourRowsDecodeAndValidateWithProductionAdapter() async throws {
        let transport=try Build58ActualShapeTransport(maskedActualFixture)
        let status=try JSONDecoder().decode(ProfileActivitySocialStatus.self,from:JSONSerialization.data(withJSONObject:try XCTUnwrap(transport.payload["status"])))
        let r=status.receipt
        let row=AccountActivityFeedRow(cardID:r.card_id,canonicalID:r.canonical_id,ownerID:r.owner_id,sport:"running",activityAt:"2000-01-01T00:00:00Z",durationSeconds:600,distanceMeters:1000,revision:r.projection_revision,readPolicy:.profileOnlyV2)
        let adapter=ProfileActivitySocialAdapter(transport:transport,context:{.init(viewerID:r.viewer_id,generation:1,safetyRevision:1,storageScopeID:r.viewer_id.uuidString.lowercased())},journal:MemoryProfileActivitySocialJournal())
        let fresh=try await adapter.status(row:row)
        let page=try await adapter.comments(row:row,receipt:fresh.receipt)
        XCTAssertEqual(page.rows.count,4);XCTAssertEqual(page.parents.count,0);XCTAssertEqual(page.receipt,fresh.receipt)
        XCTAssertEqual(Set(page.rows.map(\.sourceKey)).count,4)
        XCTAssertTrue(page.rows.allSatisfy { ProfileActivitySocialAdapter.date($0.created_at) != nil })
    }
    func testJournalFaultIsIndependentOfValidCommentReadAndCannotWrite() async throws {
        let transport=try Build58ActualShapeTransport(maskedActualFixture)
        let status=try JSONDecoder().decode(ProfileActivitySocialStatus.self,from:JSONSerialization.data(withJSONObject:try XCTUnwrap(transport.payload["status"])))
        let r=status.receipt,journal=Build58BrokenJournal()
        let row=AccountActivityFeedRow(cardID:r.card_id,canonicalID:r.canonical_id,ownerID:r.owner_id,sport:"running",activityAt:"2000-01-01T00:00:00Z",durationSeconds:600,distanceMeters:1000,revision:r.projection_revision,readPolicy:.profileOnlyV2)
        let adapter=ProfileActivitySocialAdapter(transport:transport,context:{.init(viewerID:r.viewer_id,generation:1,safetyRevision:1,storageScopeID:r.viewer_id.uuidString.lowercased())},journal:journal)
        let page=try await adapter.comments(row:row,receipt:r);XCTAssertEqual(page.rows.count,4)
        XCTAssertThrowsError(try adapter.pending(row:row))
        do { try await adapter.addComment(row:row,receipt:r,body:"must remain unsent",parentID:nil,mentions:[]);XCTFail() } catch {}
        XCTAssertEqual(journal.writes,0)
    }
}
