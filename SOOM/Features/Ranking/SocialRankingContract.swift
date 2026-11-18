import Foundation

/// Separate release gate: enabling comments does not enable global aggregation.
enum SocialRankingReleaseGate { static let productionReady = false }
enum SocialRankingPeriod: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var title: String { self == .week ? "주간" : "월간" }
}
enum SocialRankingSport: String, CaseIterable, Identifiable {
    case running, cycling, swimming
    var id: String { rawValue }
    var title: String { switch self { case .running: "러닝"; case .cycling: "사이클"; case .swimming: "수영" } }
}
enum SocialRankingMetric: String, CaseIterable, Identifiable {
    case duration, distance
    var id: String { rawValue }
    var title: String { self == .duration ? "운동 시간" : "거리" }
    func display(_ value: Double) -> String {
        self == .distance ? String(format: "%.2f km", value / 1000) : "\(Int(value / 3600))시간 \(Int(value / 60) % 60)분"
    }
}
struct SocialRankingRow: Decodable, Identifiable {
    let user_id: UUID
    let display_name: String
    let rank: Int
    let value: Double
    let badge: String?
    var id: UUID { user_id }
}
struct SocialRankingSnapshot: Decodable {
    let version: Int
    let viewer_id: UUID
    let period: String
    let sport: String
    let metric: String
    let unit: String
    let period_start: String
    let period_end: String
    let time_zone: String
    let as_of: String
    let scope: String
    let release_ready: Bool
    let deduplication: String
    let top: [SocialRankingRow]
    let around_me: [SocialRankingRow]
    let my_rank: Int?
    let total: Int
    func matches(period: SocialRankingPeriod, sport: SocialRankingSport, metric: SocialRankingMetric) -> Bool {
        self.period == period.rawValue && self.sport == sport.rawValue && self.metric == metric.rawValue
            && unit == (metric == .distance ? "meters" : "seconds")
    }
    func isValid(viewer: UUID) -> Bool {
        guard version == 1, viewer_id == viewer, release_ready, deduplication == "canonical_workout_group", scope == "public_shared_workouts", time_zone == "Asia/Seoul", total >= 0,
              top.count <= min(300, total), around_me.count <= min(7, total),
              Set(top.map(\.id)).count == top.count,
              Set(around_me.map(\.id)).count == around_me.count,
              (top + around_me).allSatisfy({ $0.rank > 0 && $0.rank <= total && $0.value.isFinite && $0.value >= 0 && $0.value <= 1e12 }),
              zip(top, top.dropFirst()).allSatisfy({ $0.rank <= $1.rank && $0.value >= $1.value }) else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ value: String) -> Date? {
            if let value = formatter.date(from: value) { return value }
            let plain = ISO8601DateFormatter(); return plain.date(from: value)
        }
        guard let start = date(period_start), let end = date(period_end), let updated = date(as_of),
              start < end, updated >= start else { return false }
        for row in around_me {
            if let same = top.first(where: { $0.id == row.id }), same.rank != row.rank || same.value != row.value { return false }
        }
        if let my_rank {
            guard my_rank > 0, my_rank <= total,
                  let index = around_me.firstIndex(where: { $0.id == viewer && $0.rank == my_rank }),
                  index <= 3, around_me.count - index - 1 <= 3,
                  zip(around_me, around_me.dropFirst()).allSatisfy({ $0.rank <= $1.rank && $0.value >= $1.value }) else { return false }
        } else if !around_me.isEmpty { return false }
        return true
    }
}

/// Immutable publication intent. Never infer group identity from timestamps.
struct SocialRankingContribution: Equatable {
    let canonicalID: UUID
    let sourceIDs: [UUID]
    init?(canonicalID: UUID, sourceIDs: [UUID]) {
        let unique = Set(sourceIDs)
        guard !unique.isEmpty, unique.count <= 32, unique.contains(canonicalID), unique.count == sourceIDs.count else { return nil }
        self.canonicalID = canonicalID
        self.sourceIDs = unique.sorted { $0.uuidString < $1.uuidString }
    }
}


/// Account-scoped retry journal containing identifiers only, not workout data.
/// Never retries posting: these entries are written after confirmed publication.
struct SocialRankingRetryStore {
    let directory: URL
    let ownerID: UUID
    private var url: URL { directory.appendingPathComponent("ranking-registration-\(ownerID.uuidString).json") }
    struct Entry: Codable, Equatable, Identifiable {
        let canonicalID: UUID
        let sourceIDs: [UUID]
        var id: UUID { canonicalID }
        var intent: SocialRankingContribution? { .init(canonicalID: canonicalID, sourceIDs: sourceIDs) }
    }
    func entries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        guard entries.count <= 1000, Set(entries.map(\.id)).count == entries.count, entries.allSatisfy({ $0.intent != nil }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return entries
    }
    func save(_ intent: SocialRankingContribution) throws {
        var values = try entries()
        if let index = values.firstIndex(where: { $0.id == intent.canonicalID }) {
            let union = Set(values[index].sourceIDs).union(intent.sourceIDs).sorted { $0.uuidString < $1.uuidString }
            guard let expanded = SocialRankingContribution(canonicalID: intent.canonicalID, sourceIDs: union) else {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            if values[index].sourceIDs == expanded.sourceIDs { return }
            // Preserve newly pinned aliases even if the old receipt is uncertain.
            // An old successful receipt cannot remove this expanded retry entry.
            values[index] = Entry(canonicalID: expanded.canonicalID, sourceIDs: expanded.sourceIDs)
            try write(values)
            return
        }
        guard values.count < 1000 else { throw CocoaError(.fileWriteOutOfSpace) }
        values.append(Entry(canonicalID: intent.canonicalID, sourceIDs: intent.sourceIDs))
        try write(values)
    }
    func remove(_ intent: SocialRankingContribution) throws {
        let values = try entries()
        guard !values.contains(where: { $0.id == intent.canonicalID && $0.sourceIDs != intent.sourceIDs }) else { throw CocoaError(.fileWriteFileExists) }
        try write(values.filter { $0.id != intent.canonicalID })
    }
    private func write(_ values: [Entry]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: url, options: .atomic)
    }
}

/// Versioned policy supplied by the reviewed server contract. No hard-coded,
/// guessed production thresholds and no automatic achievement writes.
struct SocialRankingGradePolicy: Decodable {
    struct Tier: Decodable, Equatable { let id: String; let title: String; let minimumSeconds: Double }
    let revision: Int
    let tiers: [Tier]
    var isValid: Bool {
        revision > 0 && !tiers.isEmpty && tiers.count <= 20 && tiers.first?.minimumSeconds == 0
            && Set(tiers.map(\.id)).count == tiers.count
            && tiers.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty && $0.minimumSeconds.isFinite && $0.minimumSeconds >= 0 }
            && zip(tiers, tiers.dropFirst()).allSatisfy { $0.minimumSeconds < $1.minimumSeconds }
    }
    func tier(forVerifiedSeconds seconds: Double) -> Tier? {
        guard isValid, seconds.isFinite, seconds >= 0 else { return nil }
        return tiers.last(where: { seconds >= $0.minimumSeconds })
    }
}
