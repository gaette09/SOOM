import XCTest
@testable import SOOM

@MainActor
final class AccountActivityRankingAdapterTests: XCTestCase {
    private let viewer = UUID(uuidString:"00000000-0000-4000-8000-000000000001")!
    private let request = AccountActivityRankingRequest(p_period:"week",p_sport:"running",p_metric:"distance")
    private func context(generation:Int = 1) -> AccountActivityRankingContext {
        .init(viewerID:viewer,generation:generation,safetyRevision:0,storageScopeID:viewer.uuidString.lowercased())
    }
    private func payload(_ edit:(inout [String:Any])->Void = {_ in}) throws -> Data {
        let row:[String:Any] = ["user_id":viewer.uuidString,"display_name":"Synthetic","rank":1,"value":5000,"badge":NSNull()]
        var p:[String:Any] = ["version":1,"viewer_id":viewer.uuidString,"period":"week","sport":"running","metric":"distance","unit":"meters",
            "period_start":"2026-11-08T15:00:00Z","period_end":"2026-11-15T15:00:00Z","as_of":"2026-11-11T10:00:00Z",
            "time_zone":"Asia/Seoul","scope":"public_account_transitioned_auto","release_ready":false,
            "deduplication":"canonical_workout_group","measurement_verification":"client_attested_projection","top":[row],"around_me":[row],"my_rank":1,"total":1]
        edit(&p);return try JSONSerialization.data(withJSONObject:p)
    }
    private func wire(_ edit:(inout [String:Any])->Void = {_ in}) throws -> AccountActivityRankingWire {
        try JSONDecoder().decode(AccountActivityRankingWire.self,from:payload(edit))
    }
    private final class Transport: AccountActivityRankingTransport {
        var readPolicy: AccountActivityReadPolicy = .approvedFollowersV1
        let data:Data; var calls=0; var after:(()->Void)?
        init(_ data:Data) {self.data=data}
        func fetch(_ request:AccountActivityRankingRequest) async throws -> Data {calls+=1;after?();return data}
    }
    func testV2RankingAcceptsOnlyExplicitPublicProfileSummaryScope() throws {
        let value = try wire { $0["version"] = 2; $0["scope"] = "public_profile_v2_auto"; $0["measurement_verification"] = "profile_v2_summary_grant" }
        let result = try AccountActivityRankingAdapter.validate(value, request: request, viewer: viewer, isFixture: true, expectedPolicy: .profileOnlyV2)
        XCTAssertEqual(result.scope, "public_profile_v2_auto")
        XCTAssertThrowsError(try AccountActivityRankingAdapter.validate(value, request: request, viewer: viewer, isFixture: true))
        XCTAssertThrowsError(try AccountActivityRankingAdapter.validate(wire(), request: request, viewer: viewer, isFixture: true, expectedPolicy: .profileOnlyV2))
    }
    func testV2RankingCannotUseOldPreviewGate() async throws {
        let transport = Transport(try payload()); transport.readPolicy = .profileOnlyV2
        let adapter = AccountActivityRankingAdapter(transport: transport, preview: true, context: { self.context() })
        do { _ = try await adapter.load(request); XCTFail() } catch {}
        XCTAssertEqual(transport.calls, 0)
    }
    func testPreviewUsesRealModeNotFixtureAndKeepsProductionGateOff() async throws {
        let a = AccountActivityRankingAdapter(transport: Transport(try payload()), preview: true, context: { self.context() })
        let result = try await a.load(request)
        XCTAssertFalse(result.isLocalFixture)
        XCTAssertFalse(AccountActivityRankingReleaseGate.productionReady)
        XCTAssertEqual(result.total, 1)
    }
    func testPreviewRejectsUnexpectedReleasedEnvelope() throws {
        XCTAssertThrowsError(try AccountActivityRankingAdapter.validate(wire { $0["release_ready"] = true }, request: request, viewer: viewer, isFixture: false, preview: true))
    }
    func testProductionGateDoesNotCallInjectedTransport() async throws {
        let t=Transport(try payload());let a=AccountActivityRankingAdapter(transport:t,context:{self.context()})
        do {_ = try await a.load(request);XCTFail("disabled")}catch {XCTAssertEqual(error as? AccountActivityRankingError,.disabled)}
        XCTAssertEqual(t.calls,0)
    }
    func testFixtureNormalizesWithoutChangingScopeOrClaimingRelease() async throws {
        let t=Transport(try payload());let a=AccountActivityRankingAdapter.localFixture(transport:t,context:{self.context()})
        let result=try await a.load(request)
        XCTAssertTrue(result.isLocalFixture);XCTAssertEqual(result.scope,"public_account_transitioned_auto")
        XCTAssertEqual(result.top.count,1);XCTAssertEqual(t.calls,1)
    }
    func testGenerationChangeAfterResponseRejected() async throws {
        var current=context();let t=Transport(try payload());t.after={current=self.context(generation:2)}
        let a=AccountActivityRankingAdapter.localFixture(transport:t,context:{current})
        do {_ = try await a.load(request);XCTFail("scope changed")}catch {XCTAssertEqual(error as? AccountActivityRankingError,.accountChanged)}
    }
    func testOldScopeFilterAndReleaseMismatchRejected() throws {
        for edit: (inout [String:Any])->Void in [{$0["scope"]="public_account_transitioned_opt_in"},{$0["scope"]="public_shared_workouts"},{$0["sport"]="cycling"},{$0["release_ready"]=true},{$0["unit"]="seconds"}] {
            XCTAssertThrowsError(try AccountActivityRankingAdapter.validate(wire(edit),request:request,viewer:viewer,isFixture:true))
        }
    }
    func testKSTPeriodAndDuplicateRowsRejected() throws {
        XCTAssertThrowsError(try AccountActivityRankingAdapter.validate(wire({$0["period_start"]="2026-11-09T00:00:00Z"}),request:request,viewer:viewer,isFixture:true))
        XCTAssertThrowsError(try AccountActivityRankingAdapter.validate(wire({p in p["top"]=(p["top"] as! [[String:Any]])+(p["top"] as! [[String:Any]]);p["total"]=2}),request:request,viewer:viewer,isFixture:true))
    }
    func testMissingOwnRowAndInvalidNumericRejected() throws {
        XCTAssertThrowsError(try AccountActivityRankingAdapter.validate(wire({$0["around_me"]=[]}),request:request,viewer:viewer,isFixture:true))
        for value in [-1.0,0,1e13] {
            XCTAssertThrowsError(try AccountActivityRankingAdapter.validate(wire({p in var rows=p["top"] as! [[String:Any]];rows[0]["value"]=value;p["top"]=rows}),request:request,viewer:viewer,isFixture:true))
        }
    }
}
