import Foundation
import Supabase

enum AnnualBadgeLedgerSource: Equatable {
    case verifiedCandidate, ownerReported
    var rpc: String { self == .ownerReported ? "soom_annual_badge_reported_candidate_v1" : "soom_annual_badge_candidate_v1" }
    var policy: String { self == .ownerReported ? "annual-27-20261112-owner-reported" : "annual-27-20261112-candidate" }
    var status: String { self == .ownerReported ? "owner_reported_server_validated" : "candidate_verified_input_only" }
    var explanation: String { self == .ownerReported ? "사용자 제공 운동 · 서버 형식·중복 검증 기준입니다. 운동 내용의 진위를 검증한 결과는 아닙니다." : "별도 검증 입력 후보 원장입니다. 실제 검증 원천 연결 전이며 확정 획득이 아닙니다." }
}

enum AnnualBadgeLedgerGate { static let productionReady = false }
enum AnnualBadgeLedgerError: Error { case disabled, accountChanged, invalidResponse }
struct AnnualBadgeLedgerRequest: Encodable { let p_year: Int }
struct AnnualBadgeLedgerWire: Decodable {
    struct Earned: Decodable { let tier: Int; let first_earned_at: String; let currently_valid: Bool }
    let version: Int
    let policy_id: String
    let viewer_id: UUID
    let year: Int
    let time_zone: String
    let revision: Int
    let points: Double
    let current_tier: Int
    let computed_at: String?
    let status: String
    let data_completeness: String
    let ranking_bonus_status: String
    let components: [String: Double]
    let earned_tiers: [Earned]
    let release_ready: Bool
    let attribution_policy: String?
    let attribution_status: String?
    let daily_weekly_points_status: String?
    var attributionNotice: String {
        let unknown="날짜별 점수 귀속 상태 미확인 · 운동일·주간 점수는 확정값이 아닙니다."
        let start="사용자 승인 규칙: 총 유효시간은 시작 날짜·연도에 잠정 반영합니다. 실제 날짜별 분배는 미확인입니다. 정확한 활동 구간이 확인되면 재산정합니다."
        if attribution_policy == nil, attribution_status == "candidate_start_day_not_measured_distribution",
           daily_weekly_points_status == "provisional_attribution" { return start }
        guard attribution_policy == "start_day_then_explicit_segments_v1" else { return unknown }
        switch (attribution_status,daily_weekly_points_status) {
        case ("approved_start_day_provisional","provisional_attribution"): return start
        case ("explicit_active_segments","explicit_days_week_boundary_candidate"):
            return "명시된 활동 구간으로 날짜별 재산정했습니다. 사용자 제공 자료이며 운동의 진위를 검증한 값은 아닙니다. 연도 경계 주간 배점은 후보 상태입니다."
        case ("mixed","provisional_attribution"):
            return "시작일 기준 잠정 집계와 명시된 활동 구간 재산정이 함께 포함되어 있습니다. 운동일·주간 점수는 확정값이 아닙니다."
        case ("none","none"):
            return "현재 날짜 귀속 대상이 없습니다. 자료의 완전성은 미확인이며 실제 운동이 없다는 의미는 아닙니다."
        default: return unknown
        }
    }
}
@MainActor protocol AnnualBadgeLedgerTransport { func fetch(year: Int) async throws -> Data }
@MainActor struct SupabaseAnnualBadgeLedgerTransport: AnnualBadgeLedgerTransport {
    let client: SupabaseClient
    var source: AnnualBadgeLedgerSource = .verifiedCandidate
    func fetch(year: Int) async throws -> Data {
        guard AnnualBadgeLedgerGate.productionReady else { throw AnnualBadgeLedgerError.disabled }
        return try await client.rpc(source.rpc,params:AnnualBadgeLedgerRequest(p_year:year)).execute().data
    }
}
@MainActor final class AnnualBadgeLedgerAdapter {
    private let transport: any AnnualBadgeLedgerTransport
    private let context: () -> AccountActivityRankingContext
    private let fixture: Bool
    private let source: AnnualBadgeLedgerSource
    init(transport: any AnnualBadgeLedgerTransport, source: AnnualBadgeLedgerSource = .verifiedCandidate, context: @escaping () -> AccountActivityRankingContext) {
        self.transport=transport;self.context=context;self.source=source;fixture=false
    }
    #if DEBUG
    private init(fixtureTransport: any AnnualBadgeLedgerTransport, source: AnnualBadgeLedgerSource, context: @escaping () -> AccountActivityRankingContext) {
        transport=fixtureTransport;self.context=context;self.source=source;fixture=true
    }
    static func localFixture(transport: any AnnualBadgeLedgerTransport,source: AnnualBadgeLedgerSource = .verifiedCandidate,context: @escaping () -> AccountActivityRankingContext) -> AnnualBadgeLedgerAdapter {
        .init(fixtureTransport:transport,source:source,context:context)
    }
    #endif
    func load(year:Int) async throws -> AnnualBadgeLedgerWire {
        guard fixture || AnnualBadgeLedgerGate.productionReady else { throw AnnualBadgeLedgerError.disabled }
        let c=context()
        guard let owner=c.viewerID,c.storageScopeID==owner.uuidString.lowercased(),c.generation>=0,!AccountDeletionWriteFence.shared.isRetired(owner),!Task.isCancelled else { throw AnnualBadgeLedgerError.accountChanged }
        guard (2000...9998).contains(year) else { throw AnnualBadgeLedgerError.invalidResponse }
        let data=try await transport.fetch(year:year)
        guard c==context(),!AccountDeletionWriteFence.shared.isRetired(owner),!Task.isCancelled else { throw AnnualBadgeLedgerError.accountChanged }
        let w=try JSONDecoder().decode(AnnualBadgeLedgerWire.self,from:data)
        guard w.version==1,w.policy_id==source.policy,w.viewer_id==owner,w.year==year,w.time_zone=="Asia/Seoul",w.revision>=0,
              w.points.isFinite,w.points>=0,(0...27).contains(w.current_tier),w.status==source.status,w.data_completeness=="unknown",
              w.ranking_bonus_status=="eligibility_unresolved_excluded",!w.release_ready,
              Set(w.components.keys).isSubset(of:["duration","day","week"]),w.components.values.allSatisfy({$0.isFinite && $0>=0}),
              abs(w.components.values.reduce(0,+)-w.points)<0.000001,
              Set(w.earned_tiers.map(\.tier)).count==w.earned_tiers.count,
              w.current_tier==AnnualBadgeScoring.tiers.filter({w.points >= $0.threshold}).count else { throw AnnualBadgeLedgerError.invalidResponse }
        func validDate(_ s:String)->Bool {
            let f=ISO8601DateFormatter();if f.date(from:s) != nil{return true};f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.date(from:s) != nil
        }
        guard w.computed_at.map(validDate) ?? (w.revision==0 && w.points==0 && w.earned_tiers.isEmpty),
              w.earned_tiers.allSatisfy({(1...27).contains($0.tier) && validDate($0.first_earned_at) && $0.currently_valid == ($0.tier<=w.current_tier)}) else { throw AnnualBadgeLedgerError.invalidResponse }
        return w
    }
}
