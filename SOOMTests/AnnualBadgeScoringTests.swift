import XCTest
@testable import SOOM
final class AnnualBadgeScoringTests: XCTestCase {
    func testTwoHourWeeklyThreeDays48And52Weeks() throws {
        let start=ISO8601DateFormatter().date(from:"2026-01-04T15:00:00Z")!
        for (weeks,expected) in [(48,3360.0),(52,3640.0)] {
            let workouts=(0..<weeks).flatMap { w in (0..<3).map { d in AnnualBadgeScoring.Workout(canonicalID:UUID(),startedAt:start.addingTimeInterval(Double(w*7+d)*86400+3600),validSeconds:7200) } }
            let r=try AnnualBadgeScoring.calculate(year:2026,workouts:workouts)
            XCTAssertEqual(r.points,expected);XCTAssertEqual(r.tier?.title,"챔피언 1")
        }
    }
    func testAll27ThresholdsAndNo50PercentBonus() throws {
        XCTAssertEqual(AnnualBadgeScoring.tiers.count,27)
        for t in AnnualBadgeScoring.tiers {
            let r=AnnualBadgeScoring.Result(year:2026,timePoints:t.threshold,activeDayPoints:0,consistencyPoints:0,rankingPoints:0,activeDays:0)
            XCTAssertEqual(r.tier,t)
        }
        let b=AnnualBadgeScoring.SettledBonus(period:.month,startsAt:ISO8601DateFormatter().date(from:"2025-12-31T15:00:00Z")!,rank:50,participants:100)
        XCTAssertEqual(try AnnualBadgeScoring.calculate(year:2026,workouts:[],settledBonuses:[b]).points,0)
    }
    @MainActor func testYearPreservationLogoutAndDeletionFence() throws {
        let owner=UUID();var context:AnnualBadgeHistoryStore.Context? = .init(ownerID:owner,generation:1)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store=AnnualBadgeHistoryStore(context:context!,directory:directory,current:{context})
        for year in [2025,2026] { try store.save(.init(year:year,timePoints:3300,activeDayPoints:0,consistencyPoints:0,rankingPoints:0,activeDays:0)) }
        XCTAssertEqual(try store.read().map(\.year),[2026,2025]);XCTAssertTrue(try store.read().allSatisfy{$0.status=="provisional"})
        context=nil;XCTAssertThrowsError(try store.read())
        context = .init(ownerID:owner,generation:2);XCTAssertThrowsError(try store.read())
        context = .init(ownerID:owner,generation:1)
        AccountDeletionWriteFence.shared.retire(owner)
        XCTAssertThrowsError(try store.read());XCTAssertThrowsError(try store.save(.init(year:2027,timePoints:0,activeDayPoints:0,consistencyPoints:0,rankingPoints:0,activeDays:0)))
    }
}

@MainActor final class AnnualBadgeLedgerAdapterTests: XCTestCase {
    final class Transport: AnnualBadgeLedgerTransport {
        var data:Data;var calls=0;var onFetch:(()->Void)?
        init(_ data:Data){self.data=data}
        func fetch(year:Int) async throws -> Data { calls+=1;onFetch?();return data }
    }
    func context(_ owner:UUID, _ generation:Int=1)->AccountActivityRankingContext {
        .init(viewerID:owner,generation:generation,safetyRevision:1,storageScopeID:owner.uuidString.lowercased())
    }
    func data(_ owner:UUID, change:([String:Any])->[String:Any] = {$0}) throws -> Data {
        try JSONSerialization.data(withJSONObject:change(["version":1,"policy_id":"annual-27-20261112-candidate","viewer_id":owner.uuidString,"year":2026,"time_zone":"Asia/Seoul","revision":1,"points":100,"current_tier":1,"computed_at":"2026-11-12T00:00:00Z","status":"candidate_verified_input_only","data_completeness":"unknown","ranking_bonus_status":"eligibility_unresolved_excluded","components":["duration":98,"day":2,"week":0],"earned_tiers":[["tier":1,"first_earned_at":"2026-11-12T00:00:00Z","currently_valid":true]],"release_ready":false]))
    }
    func testCandidateYearReadAndNoProductionCall() async throws {
        let owner=UUID(),t=Transport(try data(owner));let c=context(owner)
        let candidate=AnnualBadgeLedgerAdapter.localFixture(transport:t,context:{c})
        let row=try await candidate.load(year:2026);XCTAssertEqual(row.current_tier,1);XCTAssertFalse(row.release_ready)
        let live=AnnualBadgeLedgerAdapter(transport:t,context:{c})
        do {_ = try await live.load(year:2026);XCTFail()}catch{}
        XCTAssertEqual(t.calls,1)
        do {_ = try await candidate.load(year:9999);XCTFail()}catch{}
        XCTAssertEqual(t.calls,1)
    }
    func testOwnerYearPolicyAndEarnedForgeryRejected() async throws {
        let owner=UUID(),c=context(owner)
        for mutation in [
            { (d:[String:Any]) in var d=d;d["viewer_id"]=UUID().uuidString;return d },
            { d in var d=d;d["year"]=2025;return d },
            { d in var d=d;d["status"]="confirmed";return d },
            { d in var d=d;d["release_ready"]=true;return d },
            { d in var d=d;d["current_tier"]=27;return d },
            { d in var d=d;d["points"]=200;return d }
        ] {
            let t=Transport(try data(owner,change:mutation));let a=AnnualBadgeLedgerAdapter.localFixture(transport:t,context:{c})
            do {_ = try await a.load(year:2026);XCTFail()}catch{}
        }
    }
    func testInFlightAccountChangeAndDeletionFailClosed() async throws {
        let owner=UUID();var c=context(owner);let t=Transport(try data(owner))
        let a=AnnualBadgeLedgerAdapter.localFixture(transport:t,context:{c})
        t.onFetch={c=self.context(owner,2)}
        do {_ = try await a.load(year:2026);XCTFail()}catch{}
        t.onFetch={AccountDeletionWriteFence.shared.retire(owner)}
        do {_ = try await a.load(year:2026);XCTFail()}catch{}
    }
    func testEmptyYearAndRevokedHistoricalTier() async throws {
        let owner=UUID(),c=context(owner)
        for revoked in [false,true] {
            let t=Transport(try data(owner,change:{d in var d=d;d["revision"]=revoked ? 2:0;d["points"]=0;d["current_tier"]=0;d["components"]=[String:Int]();d["computed_at"]=revoked ? "2026-11-12T00:00:00Z" : NSNull();d["earned_tiers"]=revoked ? [["tier":1,"first_earned_at":"2026-11-12T00:00:00Z","currently_valid":false]]:[];return d}))
            let a=AnnualBadgeLedgerAdapter.localFixture(transport:t,context:{c});let row=try await a.load(year:2026)
            XCTAssertEqual(row.points,0);XCTAssertEqual(row.earned_tiers.count,revoked ? 1:0)
        }
    }
    func testActualIsolatedPostgresRPCPayloads() async throws {
        let owner=UUID(uuidString:"bb120000-0000-4000-8000-000000000001")!
        let c=context(owner)
        let samples:[(Int,String)] = [
            (2027, #"""
{
  "year": 2027,
  "points": 102.0,
  "status": "candidate_verified_input_only",
  "version": 1,
  "revision": 4,
  "policy_id": "annual-27-20261112-candidate",
  "time_zone": "Asia/Seoul",
  "viewer_id": "bb120000-0000-4000-8000-000000000001",
  "components": {
    "day": 2,
    "duration": 100.0
  },
  "computed_at": "2026-11-12T11:42:59.875627+09:00",
  "current_tier": 1,
  "earned_tiers": [
    {
      "tier": 1,
      "currently_valid": true,
      "first_earned_at": "2026-11-12T11:42:59.875627+09:00"
    }
  ],
  "release_ready": false,
  "data_completeness": "unknown",
  "ranking_bonus_status": "eligibility_unresolved_excluded"
}
"""#),
            (2028, #"""
{
  "year": 2028,
  "points": 0,
  "status": "candidate_verified_input_only",
  "version": 1,
  "revision": 0,
  "policy_id": "annual-27-20261112-candidate",
  "time_zone": "Asia/Seoul",
  "viewer_id": "bb120000-0000-4000-8000-000000000001",
  "components": {},
  "computed_at": null,
  "current_tier": 0,
  "earned_tiers": [],
  "release_ready": false,
  "data_completeness": "unknown",
  "ranking_bonus_status": "eligibility_unresolved_excluded"
}
"""#),
            (2026, #"""
{
  "year": 2026,
  "points": 0,
  "status": "candidate_verified_input_only",
  "version": 1,
  "revision": 3,
  "policy_id": "annual-27-20261112-candidate",
  "time_zone": "Asia/Seoul",
  "viewer_id": "bb120000-0000-4000-8000-000000000001",
  "components": {},
  "computed_at": "2026-11-12T11:42:59.869684+09:00",
  "current_tier": 0,
  "earned_tiers": [
    {
      "tier": 1,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 2,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 3,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 4,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 5,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 6,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 7,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 8,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 9,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 10,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 11,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 12,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 13,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 14,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 15,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 16,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 17,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 18,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 19,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 20,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 21,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    },
    {
      "tier": 22,
      "currently_valid": false,
      "first_earned_at": "2026-11-12T11:42:59.859215+09:00"
    }
  ],
  "release_ready": false,
  "data_completeness": "unknown",
  "ranking_bonus_status": "eligibility_unresolved_excluded"
}
"""#),
        ]
        for (year,json) in samples {
            let adapter=AnnualBadgeLedgerAdapter.localFixture(transport:Transport(Data(json.utf8)),context:{c})
            let row=try await adapter.load(year:year)
            XCTAssertEqual(row.viewer_id,owner);XCTAssertEqual(row.year,year);XCTAssertFalse(row.release_ready)
        }
    }

}

@MainActor final class AnnualBadgeReportedSourceTests: XCTestCase {
    func testReportedAndVerifiedSourcesNeverMix() async throws {
        let helper=AnnualBadgeLedgerAdapterTests(),owner=UUID()
        let context=helper.context(owner)
        let verified=try helper.data(owner)
        let reported=try helper.data(owner,change:{d in var d=d;d["policy_id"]="annual-27-20261112-owner-reported";d["status"]="owner_reported_server_validated";return d})
        for (source,data) in [(AnnualBadgeLedgerSource.ownerReported,reported),(.verifiedCandidate,verified)] {
            let a=AnnualBadgeLedgerAdapter.localFixture(transport:AnnualBadgeLedgerAdapterTests.Transport(data),source:source,context:{context})
            let row=try await a.load(year:2026);XCTAssertEqual(row.status,source.status)
        }
        for (source,data) in [(AnnualBadgeLedgerSource.ownerReported,verified),(.verifiedCandidate,reported)] {
            let a=AnnualBadgeLedgerAdapter.localFixture(transport:AnnualBadgeLedgerAdapterTests.Transport(data),source:source,context:{context})
            do {_ = try await a.load(year:2026);XCTFail()}catch{}
        }
        XCTAssertNotEqual(AnnualBadgeLedgerSource.ownerReported.rpc,AnnualBadgeLedgerSource.verifiedCandidate.rpc)
    }
    func testActualReportedTriggerRPCPayloads() async throws {
        let owner=UUID(uuidString:"bb120000-0000-4000-8000-000000000001")!
        let helper=AnnualBadgeLedgerAdapterTests(),c=AnnualBadgeLedgerAdapterTests().context(owner)
        let samples:[(Int,String)] = [
            (2027, #"""
{
  "year": 2027,
  "points": 22.0,
  "status": "owner_reported_server_validated",
  "version": 1,
  "revision": 1,
  "policy_id": "annual-27-20261112-owner-reported",
  "time_zone": "Asia/Seoul",
  "viewer_id": "bb120000-0000-4000-8000-000000000001",
  "components": {
    "day": 2,
    "duration": 20.0
  },
  "computed_at": "2026-11-12T12:07:12.591393+09:00",
  "current_tier": 0,
  "earned_tiers": [],
  "release_ready": false,
  "data_completeness": "unknown",
  "ranking_bonus_status": "eligibility_unresolved_excluded"
}
"""#),
            (2026, #"""
{
  "year": 2026,
  "points": 0,
  "status": "owner_reported_server_validated",
  "version": 1,
  "revision": 2,
  "policy_id": "annual-27-20261112-owner-reported",
  "time_zone": "Asia/Seoul",
  "viewer_id": "bb120000-0000-4000-8000-000000000001",
  "components": {},
  "computed_at": "2026-11-12T12:07:12.595289+09:00",
  "current_tier": 0,
  "earned_tiers": [],
  "release_ready": false,
  "data_completeness": "unknown",
  "ranking_bonus_status": "eligibility_unresolved_excluded"
}
"""#),
        ]
        _ = helper
        for (year,json) in samples {
            let transport=AnnualBadgeLedgerAdapterTests.Transport(Data(json.utf8))
            let adapter=AnnualBadgeLedgerAdapter.localFixture(transport:transport,source:.ownerReported,context:{c})
            let row=try await adapter.load(year:year)
            XCTAssertEqual(row.status,"owner_reported_server_validated");XCTAssertFalse(row.release_ready)
        }
    }

    func testAttributionMetadataKnownMissingAndUnknownStayProvisional() async throws {
        let helper=AnnualBadgeLedgerAdapterTests(),owner=UUID()
        let c=helper.context(owner)
        for mode in 0..<3 {
            let data=try helper.data(owner,change:{d in
                var d=d;d["policy_id"]="annual-27-20261112-owner-reported";d["status"]="owner_reported_server_validated"
                if mode>0 {
                    d["attribution_status"]=mode==1 ? "candidate_start_day_not_measured_distribution":"future_verified_claim"
                    d["daily_weekly_points_status"]=mode==1 ? "provisional_attribution":"confirmed"
                }
                return d
            })
            let a=AnnualBadgeLedgerAdapter.localFixture(transport:AnnualBadgeLedgerAdapterTests.Transport(data),source:.ownerReported,context:{c})
            let row=try await a.load(year:2026)
            XCTAssertTrue(row.attributionNotice.contains(mode==1 ? "사용자 승인 규칙":"상태 미확인"))
            XCTAssertFalse(row.release_ready)
        }
    }

    func testRevisionAwareAttributionStatesNeverBecomeConfirmed() async throws {
        let helper=AnnualBadgeLedgerAdapterTests(),owner=UUID();let c=helper.context(owner)
        let cases=[("approved_start_day_provisional","provisional_attribution","사용자 승인 규칙"),
                   ("explicit_active_segments","explicit_days_week_boundary_candidate","명시된 활동 구간"),
                   ("mixed","provisional_attribution","함께 포함"),("none","none","귀속 대상이 없습니다"),
                   ("unknown","provisional_attribution","상태 미확인"),
                   ("explicit_active_segments","confirmed","상태 미확인")]
        for (status,pointsStatus,expected) in cases {
            let data=try helper.data(owner,change:{d in var d=d
                d["policy_id"]="annual-27-20261112-owner-reported";d["status"]="owner_reported_server_validated"
                d["attribution_policy"]="start_day_then_explicit_segments_v1";d["attribution_status"]=status;d["daily_weekly_points_status"]=pointsStatus
                return d
            })
            let a=AnnualBadgeLedgerAdapter.localFixture(transport:AnnualBadgeLedgerAdapterTests.Transport(data),source:.ownerReported,context:{c})
            let row=try await a.load(year:2026)
            XCTAssertTrue(row.attributionNotice.contains(expected));XCTAssertFalse(row.release_ready)
        }
    }

}
