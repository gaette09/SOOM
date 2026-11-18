import Foundation

/// Pure local calculator. Does not fetch health data, publish rankings, or award badges.
/// Callers must provide valid canonical workouts and separately adjudicated bonus eligibility.
enum AnnualBadgeScoring {
    struct Workout: Equatable {
        let canonicalID: UUID
        let startedAt: Date
        let validSeconds: Double
    }
    enum Period: String { case week, month }
    struct SettledBonus: Equatable {
        let period: Period
        let startsAt: Date
        let rank: Int
        let participants: Int
    }
    struct Tier: Equatable {
        let name: String
        let level: Int
        let threshold: Double
        var title: String { "\(name) \(level)" }
    }
    struct Result {
        let year: Int
        let timePoints: Double
        let activeDayPoints: Double
        let consistencyPoints: Double
        let rankingPoints: Double
        let activeDays: Int
        var points: Double { timePoints + activeDayPoints + consistencyPoints + rankingPoints }
        var tier: Tier? { tiers.last { points >= $0.threshold } }
    }
    enum Failure: Error { case invalidWorkout, conflictingCanonical, invalidBonus, duplicatePeriod, overflow }
    static let tiers: [Tier] = zip(
        ["브론즈", "실버", "골드", "플래티넘", "다이아몬드", "엘리트", "마스터", "챔피언", "전설"],
        [[100,200,300], [450,600,750], [900,1050,1200], [1350,1500,1650],
         [1800,1950,2100], [2300,2500,2700], [2900,3050,3200], [3300,3700,4100], [4600,5200,6000]]
    ).flatMap { name, values in values.enumerated().map { Tier(name: name, level: $0.offset + 1, threshold: Double($0.element)) } }

    /// Calendar boundaries are explicit: Gregorian, Seoul, Monday-start weeks.
    /// Cross-year workouts provisionally use start date under the approved attribution rule.
    /// Exact active-interval corrections belong to the revision-aware server ledger. No daily cap or rounding.
    static func calculate(year: Int, workouts: [Workout], settledBonuses: [SettledBonus] = []) throws -> Result {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        var canonical: [UUID: Workout] = [:]
        for w in workouts {
            guard w.validSeconds.isFinite, w.validSeconds >= 0, w.startedAt.timeIntervalSince1970.isFinite else { throw Failure.invalidWorkout }
            if let previous = canonical[w.canonicalID], previous != w { throw Failure.conflictingCanonical }
            canonical[w.canonicalID] = w
        }
        let selected = canonical.values.filter { calendar.component(.year, from: $0.startedAt) == year && $0.validSeconds > 0 }
        let seconds = selected.reduce(0.0) { $0 + $1.validSeconds }
        guard seconds.isFinite else { throw Failure.overflow }
        let days = Set(selected.map { calendar.startOfDay(for: $0.startedAt) })
        var weeks: [Date: Int] = [:]
        for day in days {
            let start = calendar.dateInterval(of: .weekOfYear, for: day)!.start
            weeks[start, default: 0] += 1
        }
        var bonusPoints = 0.0
        var periods = Set<String>()
        for b in settledBonuses {
            guard b.startsAt.timeIntervalSince1970.isFinite, b.rank > 0, b.participants > 0, b.rank <= b.participants else { throw Failure.invalidBonus }
            let component: Calendar.Component = b.period == .week ? .weekOfYear : .month
            guard calendar.dateInterval(of: component, for: b.startsAt)?.start == b.startsAt else { throw Failure.invalidBonus }
            // No sport multiplier. A caller must resolve cross-sport/minimum-day eligibility
            // before supplying one settled award per period. Duplicate awards fail closed.
            let key = b.period.rawValue + ":" + String(b.startsAt.timeIntervalSince1970)
            guard periods.insert(key).inserted else { throw Failure.duplicatePeriod }
            guard calendar.component(.year, from: b.startsAt) == year else { continue }
            let percentile = Double(b.rank) / Double(b.participants)
            if percentile <= 0.05 { bonusPoints += b.period == .week ? 2 : 4 }
            else if percentile <= 0.20 { bonusPoints += b.period == .week ? 1 : 2 }
        }
        return Result(year: year, timePoints: seconds / 3600 * 10,
                      activeDayPoints: Double(days.count) * 2,
                      consistencyPoints: Double(weeks.values.filter { $0 >= 3 }.count) * 4,
                      rankingPoints: bonusPoints, activeDays: days.count)
    }
}
