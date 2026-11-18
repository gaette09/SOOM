import Foundation

/// Wire model shared by iPhone, watch and ActivityKit. No tokens, account names or route coordinates.
struct WorkoutLiveState: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Sendable { case running, paused, saving, finished, discarded }
    enum Sport: String, Codable, CaseIterable, Sendable {
        case running, walking, cycling, swimming
        var title: String { switch self { case .running: "러닝"; case .walking: "걷기"; case .cycling: "라이딩"; case .swimming: "수영" } }
        var symbol: String { switch self { case .running: "figure.run"; case .walking: "figure.walk"; case .cycling: "figure.outdoor.cycle"; case .swimming: "figure.pool.swim" } }
    }
    var id: UUID
    var scope: String
    var sport: Sport
    var phase: Phase
    var startedAt: Date
    var updatedAt: Date
    var elapsed: TimeInterval
    var distance: Double
    var heartRate: Double?
    var power: Double?
    var cadence: Double?
    var elevationGain: Double?
    var energy: Double?
    var isWatch: Bool
    var sequence: Int = 0
    var savedWorkoutID: UUID?
    // Optional additions keep previously saved checkpoints and phone packets readable.
    var swimmingStrokeCount: Double?
    var poolLengthMeters: Double?
    /// End of the actual HealthKit heart-rate sample, not the snapshot refresh time.
    var heartRateMeasuredAt: Date?
    var isTerminal: Bool { phase == .finished || phase == .discarded }
    var timerStart: Date { updatedAt.addingTimeInterval(-max(0, elapsed)) }
    var distanceText: String { String(format: "%.2f", max(0, distance) / 1000) }
    var displayDistance: String { sport == .swimming ? String(format: "%.0f", max(0, distance)) : distanceText }
    var distanceUnit: String { sport == .swimming ? "m" : "km" }
    func elapsed(at date: Date) -> TimeInterval {
        max(0, elapsed) + (phase == .running ? max(0, date.timeIntervalSince(updatedAt)) : 0)
    }
    func pace(at date: Date) -> String {
        guard distance.isFinite, distance >= 20, elapsed(at: date) > 0 else { return "–:––" }
        let seconds = Int((elapsed(at: date) / (distance / (sport == .swimming ? 100 : 1000))).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    func effortText(at date: Date) -> String {
        guard sport == .cycling else { return pace(at: date) }
        let time = elapsed(at: date)
        guard distance.isFinite, time > 0 else { return "–" }
        return String(format: "%.1f", distance / time * 3.6)
    }
    var effortUnit: String { sport == .cycling ? "km/h" : sport == .swimming ? "/100m" : "/km" }
    static func time(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
    /// UI freshness only, not a clinical threshold or a heart-rate-zone boundary.
    static let heartRateFreshness: TimeInterval = 30
    func currentHeartRate(at date: Date) -> Double? {
        guard phase == .running, let heartRate, heartRate.isFinite, heartRate > 0,
              let heartRateMeasuredAt else { return nil }
        let age = date.timeIntervalSince(heartRateMeasuredAt)
        guard age >= 0, age <= Self.heartRateFreshness else { return nil }
        return heartRate
    }
    static func clockTime(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    /// Reject malformed packets instead of displaying fabricated measurements.
    var isValid: Bool {
        elapsed.isFinite && elapsed >= 0 && distance.isFinite && distance >= 0 && elapsed < 172_800
            && distance < 2_000_000 && !scope.isEmpty
            && [heartRate, power, cadence, elevationGain, energy, swimmingStrokeCount].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 }
            && (poolLengthMeters.map { $0.isFinite && $0 >= 10 && $0 <= 150 } ?? true)
    }
}

struct WorkoutLiveInbox {
    private(set) var latest: WorkoutLiveState?
    private var ended: Set<UUID> = []
    mutating func reset() { latest = nil; ended.removeAll() }
    mutating func receive(_ state: WorkoutLiveState, scope: String) -> Bool {
        guard state.isValid, state.scope == scope, !ended.contains(state.id) else { return false }
        if let old = latest {
            if old.id == state.id {
                guard state.sequence > old.sequence, state.updatedAt >= old.updatedAt else { return false }
            } else {
                // A completed message can be lost while disconnected. A genuinely newer workout
                // supersedes it; an older queued snapshot must never replace the current one.
                guard state.startedAt >= old.updatedAt, state.startedAt > old.startedAt else { return false }
                ended.insert(old.id)
            }
        }
        latest = state
        if state.isTerminal { ended.insert(state.id) }
        return true
    }
}

struct WorkoutRemoteCommand: Codable, Sendable {
    enum Action: String, Codable, Sendable { case snapshot, pause, resume, finish }
    var workoutID: UUID?
    var scope: String
    var action: Action
}

#if os(iOS)
import ActivityKit
struct SOOMWorkoutAttributes: ActivityAttributes {
    typealias ContentState = WorkoutLiveState
    var workoutID: UUID
    var sport: WorkoutLiveState.Sport
    var isWatch: Bool
}
#endif
