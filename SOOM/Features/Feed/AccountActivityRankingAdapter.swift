import Foundation
import Supabase

enum AccountActivityRankingError: Error, Equatable { case disabled, accountChanged, invalidResponse }
enum AccountActivityRankingReleaseGate { static let productionReady = false }

struct AccountActivityRankingContext: Equatable {
    let viewerID: UUID?
    let generation: Int
    let safetyRevision: Int
    let storageScopeID: String
}
struct AccountActivityRankingRequest: Encodable {
    let p_period: String
    let p_sport: String
    let p_metric: String
    var isValid: Bool {
        ["week","month"].contains(p_period) && ["running","cycling","swimming"].contains(p_sport)
            && ["duration","distance"].contains(p_metric)
    }
}
@MainActor
protocol AccountActivityRankingTransport {
    var readPolicy: AccountActivityReadPolicy { get }
    func fetch(_ request: AccountActivityRankingRequest) async throws -> Data
}

extension AccountActivityRankingTransport { var readPolicy: AccountActivityReadPolicy { .approvedFollowersV1 } }

/// Even a directly constructed production transport cannot call an undeployed RPC.
@MainActor
struct SupabaseAccountActivityRankingTransport: AccountActivityRankingTransport {
    let client: SupabaseClient
    var preview: Bool = false
    var readPolicy: AccountActivityReadPolicy = .approvedFollowersV1
    func fetch(_ request: AccountActivityRankingRequest) async throws -> Data {
        guard !preview || readPolicy == .approvedFollowersV1 else { throw AccountActivityRankingError.disabled }
        if preview {
            guard let owner = client.auth.currentSession?.user.id, try await AccountActivityPreviewService(client: client, owner: owner).capability().enabled else { throw AccountActivityRankingError.disabled }
        }
        guard preview || readPolicy.rankingProductionReady else { throw AccountActivityRankingError.disabled }
        guard request.isValid else { throw AccountActivityRankingError.invalidResponse }
        return try await client.rpc(preview ? "soom_activity_ranking_totals_preview_v1" : readPolicy.interactionRPC("soom_activity_ranking_totals_candidate_v1"), params: request).execute().data
    }
}

/// New account-transition scope is deliberately NOT a SocialRankingSnapshot.
struct AccountActivityRankingWire: Decodable {
    let version: Int
    let viewer_id: UUID
    let period: String
    let sport: String
    let metric: String
    let unit: String
    let period_start: String
    let period_end: String
    let as_of: String
    let time_zone: String
    let scope: String
    let release_ready: Bool
    let deduplication: String
    let measurement_verification: String
    let top: [SocialRankingRow]
    let around_me: [SocialRankingRow]
    let my_rank: Int?
    let total: Int
}
struct AccountActivityRankingDisplay {
    let viewerID: UUID
    let periodStart: Date
    let periodEnd: Date
    let asOf: Date
    let top: [SocialRankingRow]
    let aroundMe: [SocialRankingRow]
    let myRank: Int?
    let total: Int
    let isLocalFixture: Bool
    let scope: String
    let measurementVerification: String
}

@MainActor
final class AccountActivityRankingAdapter {
    private let transport: any AccountActivityRankingTransport
    private let policy: AccountActivityReadPolicy
    private let context: () -> AccountActivityRankingContext
    private let isFixture: Bool
    private let preview: Bool
    init(transport: any AccountActivityRankingTransport, preview: Bool = false, context: @escaping () -> AccountActivityRankingContext) {
        self.transport = transport; policy = transport.readPolicy; self.context = context; isFixture = false; self.preview = preview
    }
    #if DEBUG
    private init(fixtureTransport: any AccountActivityRankingTransport, context: @escaping () -> AccountActivityRankingContext) {
        transport = fixtureTransport; policy = fixtureTransport.readPolicy; self.context = context; isFixture = true; preview = false
    }
    static func localFixture(transport: any AccountActivityRankingTransport,
                             context: @escaping () -> AccountActivityRankingContext) -> AccountActivityRankingAdapter {
        .init(fixtureTransport: transport, context: context)
    }
    #endif

    func load(_ request: AccountActivityRankingRequest) async throws -> AccountActivityRankingDisplay {
        guard !preview || policy == .approvedFollowersV1 else { throw AccountActivityRankingError.disabled }
        guard isFixture || (preview && policy == .approvedFollowersV1) || policy.rankingProductionReady else { throw AccountActivityRankingError.disabled }
        let expected = context()
        guard let viewer = expected.viewerID, expected.storageScopeID == viewer.uuidString.lowercased(),
              expected.generation >= 0, request.isValid, !Task.isCancelled else { throw AccountActivityRankingError.accountChanged }
        let data = try await transport.fetch(request)
        guard !Task.isCancelled, transport.readPolicy == policy, context() == expected else { throw AccountActivityRankingError.accountChanged }
        let wire = try JSONDecoder().decode(AccountActivityRankingWire.self, from: data)
        return try Self.validate(wire, request: request, viewer: viewer, isFixture: isFixture, preview: preview, expectedPolicy: policy)
    }

    static func validate(_ w: AccountActivityRankingWire, request: AccountActivityRankingRequest,
                         viewer: UUID, isFixture: Bool, preview: Bool = false, expectedPolicy: AccountActivityReadPolicy = .approvedFollowersV1) throws -> AccountActivityRankingDisplay {
        func reject() throws -> Never { throw AccountActivityRankingError.invalidResponse }
        guard request.isValid, w.version == expectedPolicy.rawValue, w.viewer_id == viewer,
              w.scope == expectedPolicy.rankingScope, w.deduplication == "canonical_workout_group",
              w.measurement_verification == expectedPolicy.rankingMeasurementVerification, w.time_zone == "Asia/Seoul",
              w.period == request.p_period, w.sport == request.p_sport, w.metric == request.p_metric,
              w.unit == (request.p_metric == "distance" ? "meters" : "seconds"),
              (isFixture || preview) ? !w.release_ready : (w.release_ready && expectedPolicy.rankingProductionReady),
              w.total >= 0, w.top.count == min(300,w.total), w.around_me.count <= min(7,w.total) else { try reject() }
        func date(_ value: String) -> Date? {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            if let d = f.date(from:value) { return d }
            f.formatOptions = [.withInternetDateTime]; return f.date(from:value)
        }
        guard let start = date(w.period_start), let end = date(w.period_end), let updated = date(w.as_of),
              start <= updated, updated < end else { try reject() }
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"Asia/Seoul")!
        calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
        let component: Calendar.Component = request.p_period == "week" ? .weekOfYear : .month
        guard let interval = calendar.dateInterval(of:component,for:updated),
              start == interval.start, end == interval.end else { try reject() }
        func ordered(_ rows:[SocialRankingRow]) -> Bool {
            guard Set(rows.map(\.id)).count == rows.count,
                  rows.allSatisfy({ $0.rank > 0 && $0.rank <= w.total && $0.value.isFinite && $0.value > 0 && $0.value <= 1e12 && !$0.display_name.isEmpty && $0.badge == nil }) else { return false }
            return zip(rows,rows.dropFirst()).allSatisfy {
                if $0.value == $1.value { return $0.rank == $1.rank && $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
                return $0.value > $1.value && $0.rank < $1.rank
            }
        }
        guard ordered(w.top), ordered(w.around_me) else { try reject() }
        for (index,row) in w.top.enumerated() {
            let expectedRank = index > 0 && w.top[index-1].value == row.value ? w.top[index-1].rank : index+1
            guard row.rank == expectedRank else { try reject() }
        }
        for row in w.around_me {
            if let same = w.top.first(where:{$0.id == row.id}) {
                guard same.rank == row.rank, same.value == row.value, same.display_name == row.display_name else { try reject() }
            }
        }
        if let mine = w.my_rank {
            guard let index = w.around_me.firstIndex(where:{$0.id == viewer}), w.around_me[index].rank == mine,
                  index <= 3, w.around_me.count-index-1 <= 3 else { try reject() }
            if w.total <= 300 {
                guard let position = w.top.firstIndex(where:{$0.id == viewer}) else { try reject() }
                let expected = Array(w.top[max(0,position-3)...min(w.top.count-1,position+3)]).map(\.id)
                guard w.around_me.map(\.id) == expected else { try reject() }
            }
        } else if !w.around_me.isEmpty || w.top.contains(where:{$0.id == viewer}) { try reject() }
        return AccountActivityRankingDisplay(viewerID:viewer,periodStart:start,periodEnd:end,asOf:updated,
            top:w.top,aroundMe:w.around_me,myRank:w.my_rank,total:w.total,isLocalFixture:isFixture,
            scope:w.scope,measurementVerification:w.measurement_verification)
    }
}
