import SwiftUI
import Supabase

struct SocialRankingView: View {
    @EnvironmentObject private var accountStorage: HealthAccountStorageController
    @State private var previewEnabled = false
    @State private var pendingEntries: [SocialRankingRetryStore.Entry] = []
    @State private var retryBusy = false
    @State private var badgePreview = false
    @State private var badgePolicy = false
    @State private var badgeHistory = false
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @State private var period = SocialRankingPeriod.week
    @State private var sport = SocialRankingSport.running
    @State private var metric = SocialRankingMetric.duration
    @State private var accountSnapshot: AccountActivityRankingDisplay?
    @State private var snapshot: SocialRankingSnapshot?
    @State private var loading = false
    @State private var error: String?
    @State private var selected: SocialRankingRow?
    private var requestKey: String { "\(period.rawValue):\(sport.rawValue):\(metric.rawValue):\(safety.accountGeneration):\(safety.revision)" }

    @Environment(\.soomOpenProfile) private var openRootProfile
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("soom").font(.system(size: 22, weight: .bold, design: .rounded)).tracking(4)
                Text("랭킹").font(.largeTitle.bold())
                Button("연간 배지 · 27단계 기준 보기") { badgePolicy = true }
                    .font(.subheadline).accessibilityIdentifier("ranking.badge.policy")
                Button("연도별 배지 이력") { badgeHistory = true }.accessibilityIdentifier("ranking.badge.history.open")
                #if DEBUG && targetEnvironment(simulator)
                if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_RANKING_LAYOUT_QA"] == "1" {
                    Button("배지 동작 미리보기") { badgePreview = true }.font(.caption)
                        .accessibilityIdentifier("ranking.badge.preview")
                }
                #endif
                HStack {
                    Picker("기간", selection: $period) { ForEach(SocialRankingPeriod.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).frame(maxWidth: 180)
                    Spacer()
                    Text("비교 기간").font(.caption).foregroundStyle(.secondary)
                }
                if let snapshot {
                    Text(periodLabel(snapshot))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    ForEach([SocialRankingSport.swimming, .running, .cycling]) { option in
                        Button { sport = option } label: {
                            VStack(spacing: 12) {
                                Text(option.title).font(.subheadline.weight(sport == option ? .semibold : .regular))
                                Rectangle().fill(sport == option ? Color.purple : .clear).frame(height: 2)
                            }.frame(maxWidth: .infinity).foregroundStyle(sport == option ? Color.purple : Color.secondary)
                        }.buttonStyle(.plain).accessibilityAddTraits(sport == option ? .isSelected : [])
                    }
                }
                Divider()
                Text("이번 기간의 기록").font(.headline)
                Picker("집계 기준", selection: $metric) { ForEach(SocialRankingMetric.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Text(accountSnapshot == nil ? "전체 공개 계정의 공개 공유 운동만 집계 · 한국 시간 기준\n중복 검증을 마친 기록부터 반영하며 이전 운동은 자동 포함되지 않습니다.\n클럽은 출시 후 업데이트로 제공됩니다. 기존 클럽 데이터는 보존됩니다." : "계정 전환 확인을 마친 운동 기준 · 한국 시간\n참여 정책 검토 중이며 이전 공유 집계와 구분됩니다. 클럽 데이터는 보존됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if snapshot != nil, let error { Text(error).font(.caption).foregroundStyle(.red) }
                if !pendingEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("랭킹 반영 대기 \(pendingEntries.count)건").font(.headline)
                        Text("피드는 이미 공유됐습니다. 아래 버튼은 랭킹 반영만 다시 확인하며 글을 재게시하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                        Button(retryBusy ? "확인 중" : "랭킹 반영 다시 시도") { Task { await retryRegistration() } }.disabled(retryBusy)
                    }.padding().background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
                if loading { ProgressView("순위를 불러오는 중").frame(maxWidth: .infinity) }
                else if let accountSnapshot {
                    Text("계정 전환 확인·랭킹 참여 범위의 운동만 집계합니다. 기존 공개 공유 집계와 다른 기준이며 참여 정책은 검토 중입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(kstPeriod(accountSnapshot.periodStart, accountSnapshot.periodEnd))
                        .font(.caption)
                    if let mine = accountSnapshot.aroundMe.first(where: { $0.id == safety.viewerID }) {
                        Text("현재 \(mine.rank)위 · \(metric.display(mine.value))").font(.headline)
                    }
                    podium(accountSnapshot.top)
                    section("내 위치 · 위아래 3명", rows: accountSnapshot.aroundMe)
                    section("전체 순위 · 최대 300명", rows: accountSnapshot.top)
                    if accountSnapshot.top.isEmpty { Text("현재 조건에 포함된 운동이 없습니다.").foregroundStyle(.secondary) }
                    Text("집계 시각 \(accountSnapshot.asOf.formatted())").font(.caption2).foregroundStyle(.secondary)
                }
                else if let snapshot {
                    if let mine = snapshot.around_me.first(where: { $0.id == safety.viewerID }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("현재 순위").font(.caption).foregroundStyle(.secondary)
                            HStack { Text("\(mine.rank)위 · \(metric.display(mine.value))").font(.headline); Spacer(); Text("MY").font(.caption2.bold()).foregroundStyle(.purple) }
                        }.padding(18).background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    podium(snapshot.top)
                    if !snapshot.around_me.isEmpty {
                        section("내 위치 · 위아래 3명", rows: snapshot.around_me)
                    } else {
                        Text("현재 집계에 포함된 공개 운동이 없습니다.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    section("전체 순위 · 최대 300명", rows: snapshot.top)
                    if snapshot.top.isEmpty { ContentUnavailableView("아직 집계된 운동이 없어요", systemImage: "figure.run", description: Text("공개 공유한 운동이 집계되면 순위를 확인할 수 있어요.")) }
                    Text("집계 시각 \(snapshot.as_of)").font(.caption2).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView(SocialRankingReleaseGate.productionReady ? "랭킹을 불러오지 못했어요" : "랭킹 연결 준비 중", systemImage: "medal", description: Text(error ?? "공개 범위와 중복 기록 집계를 검증하고 있어요. 검증 전에는 예시 순위를 실제 순위로 표시하지 않습니다."))
                    if previewEnabled || SocialRankingReleaseGate.productionReady || AccountActivityRankingReleaseGate.productionReady { Button("다시 시도") { Task { await load() } }.buttonStyle(.bordered) }
                }
            }.padding(20).padding(.bottom, 100)
        }
        .background(SOOMColor.background).navigationBarHidden(true)
        .task(id: requestKey) { await load() }
        .sheet(isPresented: $badgeHistory) { AnnualBadgeLedgerView() }
        .sheet(isPresented: $badgePolicy) {
            NavigationStack {
                List {
                    Section("연간 점수") {
                        Text("유효 운동 1시간당 10점 · 시간 상한 없음")
                        Text("운동한 날 2점 · 한 주 3일 이상 운동하면 4점")
                        Text("상위 5%: 주간 2점·월간 4점 / 상위 20%: 주간 1점·월간 2점")
                        Text("매년 1월 1일 새 점수로 시작하며 연도별 획득 배지는 보존합니다.")
                        Text("총 유효시간은 시작 날짜·연도에 잠정 반영하고, 정확한 활동 구간이 확인되면 재산정합니다.")
                    }
                    Section("등급 기준") {
                        ForEach(Array(AnnualBadgeScoring.tiers.enumerated()), id: \.offset) { _, tier in
                            HStack { Text(tier.title); Spacer(); Text("\(Int(tier.threshold))점") }
                        }
                    }
                    Section("현재 상태") {
                        Text("점수 집계와 획득 이력 연결 준비 중입니다. 이 화면은 승인된 기준 안내이며 실제 획득 배지가 아닙니다.")
                        Text("순위 보너스의 종목별 중복 지급·최소 운동일은 확인 중입니다.")
                    }
                }.navigationTitle("연간 배지")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { badgePolicy = false } } }
            }
        }
        .sheet(isPresented: $badgePreview) {
            RankingBadgeReveal(title: "배지 공개 동작", detail: "연간 27단계 배지 동작 예시입니다. 실제 승급이나 획득을 기록하지 않습니다.", isPreview: true)
        }
        .onChange(of: safety.accountGeneration) { _, _ in snapshot = nil; accountSnapshot = nil; selected = nil; pendingEntries = []; badgePolicy = false; badgePreview = false; badgeHistory = false }
        .onChange(of: safety.revision) { _, _ in snapshot = nil; accountSnapshot = nil; selected = nil; pendingEntries = []; badgePolicy = false; badgePreview = false; badgeHistory = false }
        .accessibilityIdentifier("ranking.screen")
    }
    private func kstPeriod(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.timeZone = TimeZone(identifier: "Asia/Seoul"); formatter.dateFormat = "M월 d일"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end.addingTimeInterval(-1))) · 한국 시간"
    }
    private func periodLabel(_ snapshot: SocialRankingSnapshot) -> String {
        let iso = ISO8601DateFormatter()
        func parse(_ string: String) -> Date? {
            if let date = iso.date(from: string) { return date }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return iso.date(from: string)
        }
        guard let start = parse(snapshot.period_start), let end = parse(snapshot.period_end) else { return "한국 시간 기준" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.timeZone = TimeZone(identifier: "Asia/Seoul"); formatter.dateFormat = "M월 d일"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end.addingTimeInterval(-1))) · 한국 시간"
    }
    private func podium(_ rows: [SocialRankingRow]) -> some View {
        let first = Array(rows.filter { $0.rank <= 3 && !safety.isBlocked($0.id) }.prefix(3))
        let winners = first.count == 3 ? [first[1], first[0], first[2]] : first
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(winners)) { row in
                SOOMProfileLink(userID: row.id) {
                    VStack(spacing: 10) {
                        RankingMedal(rank: row.rank).frame(width: 60, height: 74)
                        Text(row.display_name).font(.caption.bold()).lineLimit(2)
                        Text(metric.display(row.value)).font(.caption2).foregroundStyle(.secondary)
                        Text("\(row.rank)").font(.headline).frame(maxWidth: .infinity).frame(height: row.rank == 1 ? 46 : 32)
                            .background(Color.purple.opacity(0.05), in: UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                    }.frame(maxWidth: .infinity).padding(.top, row.rank == 1 ? 0 : 20)
                }.buttonStyle(.plain).accessibilityLabel("\(row.rank)위 \(row.display_name), \(metric.display(row.value)), 프로필 보기")
            }
        }
    }
    private func section(_ title: String, rows: [SocialRankingRow]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 12)
            ForEach(rows.filter { !safety.isBlocked($0.id) }) { row in
                SOOMProfileLink(userID: row.id) {
                    HStack(spacing: 12) {
                        Text("\(row.rank)").font(.headline.monospacedDigit()).frame(width: 38)
                        Image(systemName: row.rank <= 3 ? "medal.fill" : "person.crop.circle.fill")
                            .font(.title2).foregroundStyle(row.rank <= 3 ? .orange : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.display_name).font(.subheadline.bold())
                            if row.id == safety.viewerID { Text("내 순위").font(.caption).foregroundStyle(.secondary) }
                            if let badge = row.badge, !badge.isEmpty { Text(badge).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(metric.display(row.value)).font(.subheadline.monospacedDigit())
                    }.foregroundStyle(SOOMColor.ink).padding(.vertical, 14)
                }.buttonStyle(.plain)
                Divider()
            }
        }
    }
    @MainActor private func retryRegistration() async {
        guard SocialRankingReleaseGate.productionReady, let viewer = safety.viewerID,
              accountStorage.userID == viewer, safety.canUseSocial,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
        let store = SocialRankingRetryStore(directory: accountStorage.scopeDirectory, ownerID: viewer)
        let remote = SocialRankingContributionClient(client: client, viewer: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision)
        retryBusy = true; defer { retryBusy = false }
        // Explicit user retry only; no timer or silent background re-publication.
        for entry in pendingEntries {
            guard !Task.isCancelled, safety.viewerID == viewer, accountStorage.userID == viewer, let intent = entry.intent else { break }
            _ = await remote.registerPublished(intent, store: store)
        }
        await load()
    }
    @MainActor private func loadAccountRanking() async {
        let key = requestKey
        guard let viewer = safety.viewerID, (safety.canUseSocial || (previewEnabled && safety.canUseActivityPreview)), accountStorage.userID == viewer,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == viewer else { return }
        loading = true
        defer { if key == requestKey { loading = false } }
        let policy = AccountActivityReadPolicy.deployed
        let adapter = AccountActivityRankingAdapter(transport: SupabaseAccountActivityRankingTransport(client: client, preview: previewEnabled, readPolicy: policy), preview: previewEnabled) {
            AccountActivityRankingContext(viewerID: client.auth.currentSession?.user.id == self.safety.viewerID ? self.safety.viewerID : nil,
                generation: self.safety.accountGeneration, safetyRevision: self.safety.revision,
                storageScopeID: self.accountStorage.scopeID)
        }
        do {
            let result = try await adapter.load(.init(p_period: period.rawValue, p_sport: sport.rawValue, p_metric: metric.rawValue))
            guard key == requestKey, !Task.isCancelled else { return }
            accountSnapshot = result
        } catch { if key == requestKey { self.error = "새 집계 응답의 범위와 권한을 확인하지 못했습니다. 이전 순위를 대신 표시하지 않습니다." } }
    }

    @MainActor private func load() async {
        snapshot = nil; accountSnapshot = nil; error = nil; selected = nil; loading = false
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_RANKING_LAYOUT_QA"] == "1" {
            snapshot = SocialRankingLayoutFixture.snapshot(viewer: ReviewDemoMode.userID, period: period, sport: sport, metric: metric)
            return
        }
        #endif
        if AccountActivityReadPolicy.deployed == .profileOnlyV2 { previewEnabled = false }
        else if let owner = safety.viewerID, accountStorage.userID == owner,
           let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() {
            previewEnabled = (try? await AccountActivityPreviewService(client: client, owner: owner).capability().enabled) == true
            guard !Task.isCancelled, owner == safety.viewerID else { return }
        } else { previewEnabled = false }
        if previewEnabled || AccountActivityReadPolicy.deployed.rankingProductionReady {
            await loadAccountRanking()
            return
        }
        guard SocialRankingReleaseGate.productionReady else { return }
        let key = requestKey
        guard safety.canUseSocial, let viewer = safety.viewerID, accountStorage.userID == viewer,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == viewer else { error = "로그인 상태를 확인해 주세요."; return }
        do { pendingEntries = try SocialRankingRetryStore(directory: accountStorage.scopeDirectory, ownerID: viewer).entries() }
        catch { pendingEntries = []; self.error = "랭킹 반영 대기 기록을 읽지 못했습니다. 자동 재전송하지 않습니다." }
        loading = true
        defer { if key == requestKey { loading = false } }
        struct Params: Encodable { let p_period: String; let p_sport: String; let p_metric: String }
        do {
            let result: SocialRankingSnapshot = try await client.rpc("soom_global_ranking_v1", params: Params(p_period: period.rawValue, p_sport: sport.rawValue, p_metric: metric.rawValue)).execute().value
            guard !Task.isCancelled, key == requestKey, safety.canUseSocial, safety.viewerID == viewer,
                  client.auth.currentSession?.user.id == viewer else { return }
            guard result.isValid(viewer: viewer), result.matches(period: period, sport: sport, metric: metric) else { error = "집계 응답을 검증하지 못했습니다. 잠시 후 다시 시도해 주세요."; return }
            snapshot = result
        } catch { if !Task.isCancelled && key == requestKey { self.error = "연결을 확인한 뒤 다시 시도해 주세요. 이전 순위는 표시하지 않습니다." } }
    }
}

/// Rank-position medal, not an invented activity-grade or health achievement.
private struct RankingMedal: View {
    let rank: Int
    private var metal: Color { rank == 1 ? Color(red: 0.72, green: 0.55, blue: 0.20) : rank == 2 ? Color(red: 0.55, green: 0.62, blue: 0.70) : Color(red: 0.66, green: 0.43, blue: 0.29) }
    var body: some View {
        ZStack {
            RankingHexagon().fill(LinearGradient(colors: [metal.opacity(0.5), .white, metal, metal.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RankingHexagon().stroke(metal.opacity(0.9), lineWidth: 1)
            RankingHexagon().inset(by: 6).stroke(.white.opacity(0.6), lineWidth: 1)
            Image(systemName: "water.waves").font(.title2).foregroundStyle(.white.opacity(0.85))
        }.shadow(color: metal.opacity(0.18), radius: 5, y: 3).accessibilityHidden(true)
    }
}
private struct RankingHexagon: InsettableShape {
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return Path { p in
            p.move(to: CGPoint(x:r.midX,y:r.minY))
            for point in [CGPoint(x:r.maxX,y:r.minY+r.height*0.22),CGPoint(x:r.maxX,y:r.maxY-r.height*0.22),CGPoint(x:r.midX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY-r.height*0.22),CGPoint(x:r.minX,y:r.minY+r.height*0.22)] { p.addLine(to: point) }
            p.closeSubpath()
        }
    }
    func inset(by amount: CGFloat) -> Self { var copy=self;copy.insetAmount += amount;return copy }
}

#if DEBUG && targetEnvironment(simulator)
/// Explicit DEMO-only layout fixture. Never compiled into Release.
private enum SocialRankingLayoutFixture {
    static func snapshot(viewer: UUID, period: SocialRankingPeriod, sport: SocialRankingSport, metric: SocialRankingMetric) -> SocialRankingSnapshot {
        let rows = (1...320).map { index in
            SocialRankingRow(user_id: index == 148 ? viewer : UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d",index))!,
                display_name: index == 148 ? "예시 사용자" : "예시 참가자 \(index)", rank: index,
                value: Double(400-index) * (metric == .duration ? 60 : 100), badge: nil)
        }
        return SocialRankingSnapshot(version: 1, viewer_id: viewer, period: period.rawValue, sport: sport.rawValue, metric: metric.rawValue,
            unit: metric == .duration ? "seconds" : "meters", period_start: period == .week ? "2026-11-08T15:00:00Z" : "2026-10-31T15:00:00Z", period_end: period == .week ? "2026-11-15T15:00:00Z" : "2026-11-30T15:00:00Z",
            time_zone: "Asia/Seoul", as_of: "2026-11-11T11:00:00Z", scope: "public_shared_workouts", release_ready: true,
            deduplication: "canonical_workout_group", top: Array(rows.prefix(300)), around_me: Array(rows[144...150]), my_rank: 148, total: 320)
    }
}
#endif
