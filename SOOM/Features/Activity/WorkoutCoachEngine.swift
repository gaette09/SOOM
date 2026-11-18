import Foundation

enum CoachInterval: String, Codable, CaseIterable, Identifiable {
    case none, distance500, distance1000, distance2000, time300, time600, time900
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "상태 안내만"
        case .distance500: return "거리 · 0.5km"
        case .distance1000: return "거리 · 1km (베타 기본값)"
        case .distance2000: return "거리 · 2km"
        case .time300: return "시간 · 5분"
        case .time600: return "시간 · 10분"
        case .time900: return "시간 · 15분"
        }
    }
    var distance: Double? {
        switch self { case .distance500: return 500; case .distance1000: return 1000; case .distance2000: return 2000; default: return nil }
    }
    var seconds: Double? {
        switch self { case .time300: return 300; case .time600: return 600; case .time900: return 900; default: return nil }
    }
}

struct CoachPreferences: Codable, Equatable {
    var enabled = false
    var interval: CoachInterval = .distance1000
}

struct CoachCheckpoint: Codable, Equatable {
    var distanceBucket = 0
    var timeBucket = 0
    var state: RecordWorkoutSessionState?
    var sequence = 0
    var lastMetricAt: Date?
    var savedAnnounced = false
    var interval: CoachInterval = .distance1000
}

struct CoachEvent: Equatable {
    let id: String
    let text: String
    let expiresAt: Date
    let replacesSpeech: Bool
}

/// Consumes only the phone's currently owned recording. Imports/feed/merged workouts never enter here.
struct WorkoutCoachEngine {
    let sessionID: UUID
    var checkpoint: CoachCheckpoint
    private var wasGPSFresh: Bool?

    init(sessionID: UUID, checkpoint: CoachCheckpoint? = nil) {
        self.sessionID = sessionID
        self.checkpoint = checkpoint ?? CoachCheckpoint()
    }

    mutating func baseline(session: RecordWorkoutSession, preferences: CoachPreferences, at now: Date) {
        let sameInterval = checkpoint.interval == preferences.interval
        let d = bucket(session.accumulatedDistanceMeters, step: preferences.interval.distance)
        let t = bucket(session.elapsedTime(referenceDate: now), step: preferences.interval.seconds)
        checkpoint.distanceBucket = sameInterval ? max(checkpoint.distanceBucket, d) : d
        checkpoint.timeBucket = sameInterval ? max(checkpoint.timeBucket, t) : t
        checkpoint.interval = preferences.interval
        checkpoint.sequence = max(1, checkpoint.sequence)
        checkpoint.state = session.state
        wasGPSFresh = fresh(session, at: now)
    }

    mutating func update(session: RecordWorkoutSession, preferences: CoachPreferences, at now: Date) -> CoachEvent? {
        guard session.id == sessionID else { return nil }
        if checkpoint.interval != preferences.interval {
            baseline(session: session, preferences: preferences, at: now)
            return nil
        }
        if checkpoint.state != session.state {
            checkpoint.state = session.state
            checkpoint.sequence += 1
            let text: String
            switch session.state {
            case .active: text = checkpoint.sequence == 1 ? "\(session.sport.title)을 시작했어요." : "다시 시작해요."
            case .paused: text = "잠시 멈췄어요."
            case .finished: text = "운동을 마쳤어요. 저장을 확인해 주세요."
            case .cancelled: return nil
            }
            return event("state-\(checkpoint.sequence)", text, at: now, priority: true)
        }
        guard session.state == .active else { return nil }
        let isFresh = fresh(session, at: now)
        let lostGPS = wasGPSFresh == true && !isFresh
        wasGPSFresh = isFresh
        let d = bucket(session.accumulatedDistanceMeters, step: preferences.interval.distance)
        let t = bucket(session.elapsedTime(referenceDate: now), step: preferences.interval.seconds)
        let distanceAdvanced = d > checkpoint.distanceBucket
        let timeAdvanced = t > checkpoint.timeBucket
        // High water marks consume jumps, disabled periods and cooldown events; never replay history.
        checkpoint.distanceBucket = max(checkpoint.distanceBucket, d)
        checkpoint.timeBucket = max(checkpoint.timeBucket, t)
        if lostGPS && session.startedWithLocation {
            return event("gps-\(checkpoint.sequence)-\(now.timeIntervalSince1970)", "GPS가 약해요. 시간 기록은 계속돼요.", at: now, priority: true)
        }
        guard preferences.enabled,
              checkpoint.lastMetricAt.map({ now.timeIntervalSince($0) >= 45 }) ?? true else { return nil }
        if distanceAdvanced, isFresh, let step = preferences.interval.distance {
            checkpoint.lastMetricAt = now
            let km = Double(d) * step / 1000
            return event("distance-\(d)", "\(Self.number(km))킬로미터를 지났어요.", at: now)
        }
        if timeAdvanced, let step = preferences.interval.seconds {
            checkpoint.lastMetricAt = now
            return event("time-\(t)", "\(Self.number(Double(t) * step / 60))분 동안 운동했어요.", at: now)
        }
        return nil
    }

    mutating func saved(at now: Date) -> CoachEvent? {
        guard checkpoint.state == .finished, !checkpoint.savedAnnounced else { return nil }
        checkpoint.savedAnnounced = true
        return event("saved", "운동 기록을 저장했어요.", at: now, priority: true)
    }

    static func number(_ value: Double) -> String {
        String(format: value.rounded() == value ? "%.0f" : "%.1f", locale: Locale(identifier: "ko_KR"), value)
    }
    private func fresh(_ session: RecordWorkoutSession, at now: Date) -> Bool {
        guard let stamp = session.lastLocationTimestamp, let accuracy = session.lastHorizontalAccuracy else { return false }
        return (-5...15).contains(now.timeIntervalSince(stamp)) && accuracy.isFinite && (0...50).contains(accuracy)
    }
    private func bucket(_ value: Double, step: Double?) -> Int {
        guard value.isFinite, value >= 0, let step, step > 0 else { return 0 }
        return Int(min(floor(value / step), Double(Int.max / 2)))
    }
    private func event(_ key: String, _ text: String, at now: Date, priority: Bool = false) -> CoachEvent {
        CoachEvent(id: "\(sessionID)-\(key)", text: text, expiresAt: now.addingTimeInterval(15), replacesSpeech: priority)
    }
}

/// This beta deliberately has no configured production transport or provider credentials.
struct CoachPhraseRequest: Encodable, Equatable {
    let requestId: UUID
    let sessionId: UUID
    let generation: Int
    let eventId: UUID
    let eventKind = "paused_encouragement"
    let consentVersion = "phrase-no-metrics-v1"
    let sport: String
    let locale = "ko-KR"
    let tone = "calm"
    let schemaVersion = 1
}
struct CoachPhraseResponse: Codable {
    let requestId: UUID
    let eventId: UUID
    let schemaVersion: Int
    let phrase: String
    let ttlSeconds: Int
    let source: String
}
enum CoachPhraseError: Error { case unavailable, invalid, expired, notPaused }
protocol CoachPhraseTransport {
    func phrase(for request: CoachPhraseRequest) async throws -> CoachPhraseResponse
}
struct UnconnectedCoachPhraseTransport: CoachPhraseTransport {
    func phrase(for request: CoachPhraseRequest) async throws -> CoachPhraseResponse { throw CoachPhraseError.unavailable }
}
struct CoachPhraseClient {
    let transport: any CoachPhraseTransport
    static let reviewedPhrases = ["잠시 숨을 고르고 편하게 이어가요.", "지금까지 잘 이어왔어요. 편안하게 쉬어가요."]
    func phrase(request: CoachPhraseRequest, paused: Bool, consented: Bool, requestedAt: Date, now: @escaping () -> Date = Date.init) async throws -> String {
        guard paused, consented else { throw CoachPhraseError.notPaused }
        let response = try await transport.phrase(for: request)
        try Task.checkCancellation()
        guard response.requestId == request.requestId, response.eventId == request.eventId,
              response.schemaVersion == 1, (1...10).contains(response.ttlSeconds),
              ["ai", "local"].contains(response.source), Self.reviewedPhrases.contains(response.phrase) else { throw CoachPhraseError.invalid }
        guard now().timeIntervalSince(requestedAt) >= 0,
              now().timeIntervalSince(requestedAt) <= min(3, Double(response.ttlSeconds)) else { throw CoachPhraseError.expired }
        return response.phrase
    }
}
