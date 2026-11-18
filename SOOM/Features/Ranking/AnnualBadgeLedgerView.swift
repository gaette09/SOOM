import SwiftUI
import Supabase

struct AnnualBadgeLedgerView: View {
    private let source:AnnualBadgeLedgerSource = .ownerReported
    @EnvironmentObject private var accountStorage: HealthAccountStorageController
    @ObservedObject private var safety=CommunitySafetyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int = {
        var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"Asia/Seoul")!
        return c.component(.year,from:Date())
    }()
    @State private var record:AnnualBadgeLedgerWire?
    @State private var loading=false
    @State private var failure:String?
    private var key:String { "\(year):\(safety.accountGeneration):\(safety.revision):\(accountStorage.scopeID)" }
    var body:some View {
        NavigationStack {
            List {
                Section {
                    Stepper("\(String(year))년",value:$year,in:2000...9998)
                    Text("로컬 원장 연결 검증 · 확정 획득 이력이 아닙니다.").foregroundStyle(.secondary)
                    Text(source.explanation).font(.caption).foregroundStyle(.secondary)
                }
                if loading { ProgressView("조회 중") }
                if let record {
                    Section("검증 후보") {
                        Text("\(record.points,specifier:"%.1f")점")
                        Text(record.current_tier>0 ? AnnualBadgeScoring.tiers[record.current_tier-1].title : "등급 없음")
                        Text("자료 완전성 미확인 · 순위 보너스 제외").font(.caption)
                        if source == .ownerReported { Text(record.attributionNotice).font(.caption).foregroundStyle(.secondary) }
                    }
                    Section("연도별 후보 이력") {
                        if record.earned_tiers.isEmpty { Text("확인된 후보 이력이 없습니다. 실제 운동이 없다는 의미는 아닙니다.") }
                        ForEach(record.earned_tiers,id:\.tier) { tier in
                            VStack(alignment:.leading) {
                                Text(AnnualBadgeScoring.tiers[tier.tier-1].title)
                                Text(tier.currently_valid ? "후보 기준 충족" : "기록 정정으로 현재 기준 미충족").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if !loading {
                    Text(failure ?? "계정별 자동 집계 연결 준비 중입니다. 활성화 전에는 실제 점수나 획득 이력을 생성하지 않습니다.")
                }
            }.navigationTitle("배지 이력")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("닫기") { dismiss() } } }
        }.task(id:key) { await load() }
            .onChange(of:safety.accountGeneration) { _,_ in record=nil;dismiss() }
            .onChange(of:safety.revision) { _,_ in record=nil }
            .accessibilityIdentifier("ranking.badge.history")
    }
    @MainActor private func load() async {
        record=nil;failure=nil;loading=false
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_ANNUAL_BADGE_QA"] == "1" {
            let owner=ReviewDemoMode.userID
            let c=AccountActivityRankingContext(viewerID:owner,generation:0,safetyRevision:0,storageScopeID:owner.uuidString.lowercased())
            do { record=try await AnnualBadgeLedgerAdapter.localFixture(transport:AnnualBadgeLedgerFixture(owner:owner,source:source),source:source,context:{c}).load(year:year) }
            catch { failure="합성 원장 검증 실패" }
            return
        }
        #endif
        guard AnnualBadgeLedgerGate.productionReady else { return }
        let expected=key
        guard let viewer=safety.viewerID,accountStorage.userID==viewer,safety.canUseSocial,
              let client=SupabaseClientProvider(environment:AuthEnvironmentLoader().load()).makeClient(),client.auth.currentSession?.user.id==viewer else { return }
        let adapter=AnnualBadgeLedgerAdapter(transport:SupabaseAnnualBadgeLedgerTransport(client:client,source:source),source:source) {
            AccountActivityRankingContext(viewerID:client.auth.currentSession?.user.id==self.safety.viewerID ? self.safety.viewerID:nil,generation:self.safety.accountGeneration,safetyRevision:self.safety.revision,storageScopeID:self.accountStorage.scopeID)
        }
        loading=true
        defer { if key==expected { loading=false } }
        do { let next=try await adapter.load(year:year);guard key==expected else{return};record=next }
        catch { guard key==expected else{return};record=nil;failure="배지 이력을 확인하지 못했습니다. 계정과 접근 권한을 다시 확인해 주세요." }
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor private struct AnnualBadgeLedgerFixture: AnnualBadgeLedgerTransport {
    let owner:UUID
    let source:AnnualBadgeLedgerSource
    func fetch(year:Int) async throws -> Data {
        try JSONSerialization.data(withJSONObject:[
            "version":1,"policy_id":source.policy,"viewer_id":owner.uuidString,"year":year,
            "time_zone":"Asia/Seoul","revision":1,"points":100,"current_tier":1,
            "computed_at":"2026-11-12T00:00:00Z","status":source.status,"data_completeness":"unknown",
            "ranking_bonus_status":"eligibility_unresolved_excluded","components":["duration":98,"day":2,"week":0],
            "earned_tiers":[["tier":1,"first_earned_at":"2026-11-12T00:00:00Z","currently_valid":true]],"release_ready":false
        ])
    }
}
#endif
