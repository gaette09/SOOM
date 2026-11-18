import Foundation

enum PersonalWorkoutRankingMetric: String, CaseIterable, Identifiable {
    case distance, pace, speed, duration, elevation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .distance: return "최장 거리"
        case .pace: return "평균 페이스"
        case .speed: return "평균 속도"
        case .duration: return "최장 운동 시간"
        case .elevation: return "누적 상승"
        }
    }
    static func available(for sport: UnifiedWorkoutType) -> [Self] {
        switch sport {
        case .running, .walking, .hiking: return [.distance, .pace, .duration, .elevation]
        case .cycling: return [.distance, .speed, .duration, .elevation]
        case .swimming: return [.distance, .speed, .duration]
        case .strength, .yoga, .other: return [.duration]
        }
    }
}

enum PersonalWorkoutRankingPeriod: String, CaseIterable, Identifiable {
    case all, year, recent90Days
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "전체 기간"
        case .year: return "올해"
        case .recent90Days: return "최근 90일"
        }
    }
    func startDate(referenceDate: Date, calendar: Calendar) -> Date {
        switch self {
        case .all: return .distantPast
        case .year: return calendar.dateInterval(of: .year, for: referenceDate)?.start ?? referenceDate
        case .recent90Days:
            return calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        }
    }
}

enum PersonalWorkoutDistanceBand: String, CaseIterable, Identifiable {
    case all, under5, from5to10, from10to21, from21
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "모든 거리"
        case .under5: return "5 km 미만"
        case .from5to10: return "5–10 km 미만"
        case .from10to21: return "10–21.1 km 미만"
        case .from21: return "21.1 km 이상"
        }
    }
    func includes(_ meters: Double?) -> Bool {
        if self == .all { return true }
        guard let meters, meters.isFinite, meters > 0 else { return false }
        switch self {
        case .all: return true
        case .under5: return meters < 5_000
        case .from5to10: return meters >= 5_000 && meters < 10_000
        case .from10to21: return meters >= 10_000 && meters < 21_100
        case .from21: return meters >= 21_100
        }
    }
}

struct PersonalWorkoutRankingEntry: Identifiable {
    let workout: UnifiedWorkout
    /// Competition ranking: equal displayed values share a rank (1, 1, 3).
    let rank: Int
    let comparableValue: Double
    let valueText: String
    var id: UUID { workout.id }
}

struct PersonalWorkoutRankingBuilder {
    func build(
        workouts: [UnifiedWorkout],
        sport: UnifiedWorkoutType,
        metric: PersonalWorkoutRankingMetric,
        period: PersonalWorkoutRankingPeriod = .all,
        distanceBand: PersonalWorkoutDistanceBand = .all,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [PersonalWorkoutRankingEntry] {
        guard PersonalWorkoutRankingMetric.available(for: sport).contains(metric) else { return [] }
        let threshold = period.startDate(referenceDate: referenceDate, calendar: calendar)
        // Resolve exact duplicates before exclusion: an older included copy must
        // never bring back a record the user excluded in its latest revision.
        let latest = workouts.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.isExcludedFromAnalysis != $1.isExcludedFromAnalysis { return $0.isExcludedFromAnalysis }
            return $0.id.uuidString < $1.id.uuidString
        }
        var seenIDs = Set<UUID>()
        var seenExternalIDs = Set<String>()
        var eligible: [(UnifiedWorkout, Double)] = []
        for workout in latest {
            guard seenIDs.insert(workout.id).inserted else { continue }
            if let externalID = workout.externalId, !externalID.isEmpty {
                let key = workout.source.rawValue + ":" + externalID
                guard seenExternalIDs.insert(key).inserted else { continue }
            }
            guard !workout.isExcludedFromAnalysis,
                  workout.workoutType == sport,
                  workout.startDate >= threshold,
                  workout.startDate <= referenceDate,
                  workout.endDate >= workout.startDate,
                  workout.endDate <= referenceDate,
                  workout.durationSeconds.isFinite, workout.durationSeconds > 0,
                  distanceBand.includes(workout.distanceMeters),
                  let value = value(for: workout, metric: metric) else { continue }
            eligible.append((workout, value))
        }
        eligible.sort {
            if $0.1 != $1.1 { return metric == .pace ? $0.1 < $1.1 : $0.1 > $1.1 }
            if $0.0.startDate != $1.0.startDate { return $0.0.startDate > $1.0.startDate }
            return $0.0.id.uuidString < $1.0.id.uuidString
        }
        var previousValue: Double?
        var rank = 0
        return eligible.enumerated().map { index, item in
            if previousValue != item.1 { rank = index + 1 }
            previousValue = item.1
            return PersonalWorkoutRankingEntry(
                workout: item.0, rank: rank, comparableValue: item.1,
                valueText: formatted(item.1, metric: metric)
            )
        }
    }

    private func value(for workout: UnifiedWorkout, metric: PersonalWorkoutRankingMetric) -> Double? {
        let raw: Double
        switch metric {
        case .distance: raw = (workout.distanceMeters ?? .nan) / 10 // display 0.01 km
        case .duration: raw = workout.durationSeconds
        case .elevation: raw = workout.elevationGainMeters ?? .nan
        case .pace, .speed:
            guard let distance = workout.distanceMeters, distance.isFinite, distance > 0 else { return nil }
            // Same definition for every source: saved active duration + distance.
            raw = metric == .pace
                ? workout.durationSeconds * 1_000 / distance
                : distance / workout.durationSeconds * 36 // display 0.1 km/h
        }
        guard raw.isFinite, raw > 0, raw < Double(Int.max / 2) else { return nil }
        let rounded = raw.rounded()
        return rounded > 0 ? rounded : nil
    }

    private func formatted(_ value: Double, metric: PersonalWorkoutRankingMetric) -> String {
        switch metric {
        case .distance: return String(format: "%.2f km", value / 100)
        case .speed: return String(format: "%.1f km/h", value / 10)
        case .elevation: return "\(Int(value)) m"
        case .pace:
            let seconds = Int(value)
            return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
        case .duration:
            let seconds = Int(value)
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
    }
}
