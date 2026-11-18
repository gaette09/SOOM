import XCTest
@testable import SOOM

final class WorkoutCoachTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000)
    func session(distance: Double = 0, seconds: Double = 0, state: RecordWorkoutSessionState = .active) -> RecordWorkoutSession {
        var s = RecordWorkoutSession(id: UUID(), sport: .running, workoutType: .running, startedAt: start, startedWithLocation: true, state: state, pausedAt: state == .paused ? start.addingTimeInterval(seconds) : nil, endedAt: state == .finished ? start.addingTimeInterval(seconds) : nil)
        s.accumulatedDistanceMeters = distance; s.lastLocationTimestamp = start.addingTimeInterval(seconds); s.lastHorizontalAccuracy = 5
        return s
    }
    func testDefaultsAreOffAndVisibleBetaDistance() {
        XCTAssertFalse(CoachPreferences().enabled)
        XCTAssertEqual(CoachPreferences().interval, .distance1000)
        XCTAssertTrue(CoachInterval.distance1000.title.contains("베타"))
    }
    func testDistanceBoundaryAndHundredDuplicates() {
        var s = session(distance: 999); var e = WorkoutCoachEngine(sessionID: s.id)
        let p = CoachPreferences(enabled: true)
        XCTAssertNotNil(e.update(session: s, preferences: p, at: start))
        s.accumulatedDistanceMeters = 1001
        XCTAssertEqual(e.update(session: s, preferences: p, at: start)?.text, "1킬로미터를 지났어요.")
        for _ in 0..<100 { XCTAssertNil(e.update(session: s, preferences: p, at: start)) }
    }
    func testJumpAndRegressionNeverCatchUp() {
        var s = session(distance: 800); var e = WorkoutCoachEngine(sessionID: s.id); let p = CoachPreferences(enabled: true)
        e.baseline(session: s, preferences: p, at: start)
        s.accumulatedDistanceMeters = 3200
        XCTAssertEqual(e.update(session: s, preferences: p, at: start)?.text, "3킬로미터를 지났어요.")
        s.accumulatedDistanceMeters = 2900
        XCTAssertNil(e.update(session: s, preferences: p, at: start))
        s.accumulatedDistanceMeters = 3201
        s.lastLocationTimestamp = start.addingTimeInterval(60)
        XCTAssertNil(e.update(session: s, preferences: p, at: start.addingTimeInterval(60)))
    }
    func testPauseDurationExcludedAndTransitionDedup() {
        var s = session(); s.lastLocationTimestamp = nil
        var e = WorkoutCoachEngine(sessionID: s.id); let p = CoachPreferences(enabled: true, interval: .time600)
        e.baseline(session: s, preferences: p, at: start)
        s = s.paused(at: start.addingTimeInterval(599))
        XCTAssertEqual(e.update(session: s, preferences: p, at: start.addingTimeInterval(599))?.text, "잠시 멈췄어요.")
        XCTAssertNil(e.update(session: s, preferences: p, at: start.addingTimeInterval(1199)))
        s = s.resumed(at: start.addingTimeInterval(1199))
        XCTAssertEqual(e.update(session: s, preferences: p, at: start.addingTimeInterval(1199))?.text, "다시 시작해요.")
        XCTAssertEqual(e.update(session: s, preferences: p, at: start.addingTimeInterval(1200))?.text, "10분 동안 운동했어요.")
    }
    func testStaleGPSConsumesMilestoneWithoutSpeech() {
        var s = session(distance: 999); var e = WorkoutCoachEngine(sessionID: s.id); let p = CoachPreferences(enabled: true)
        e.baseline(session: s, preferences: p, at: start)
        s.accumulatedDistanceMeters = 1001
        XCTAssertTrue(e.update(session: s, preferences: p, at: start.addingTimeInterval(30))?.text.contains("GPS") == true)
        XCTAssertNil(e.update(session: s, preferences: p, at: start.addingTimeInterval(31)))
        s.lastLocationTimestamp = start.addingTimeInterval(32)
        XCTAssertNil(e.update(session: s, preferences: p, at: start.addingTimeInterval(32)))
    }
    func testCheckpointRestoreAndVoiceEnableDoNotReplay() throws {
        let s = session(distance: 3200); let p = CoachPreferences(enabled: true)
        var e = WorkoutCoachEngine(sessionID: s.id); e.baseline(session: s, preferences: p, at: start)
        let data = try JSONEncoder().encode(e.checkpoint)
        var restored = WorkoutCoachEngine(sessionID: s.id, checkpoint: try JSONDecoder().decode(CoachCheckpoint.self, from: data))
        XCTAssertNil(restored.update(session: s, preferences: p, at: start))
    }
    func testDisabledAndCooldownConsumeOldBuckets() {
        var s = session(); var e = WorkoutCoachEngine(sessionID: s.id); var p = CoachPreferences()
        e.baseline(session: s, preferences: p, at: start)
        s.accumulatedDistanceMeters = 1001
        XCTAssertNil(e.update(session: s, preferences: p, at: start))
        p.enabled = true
        XCTAssertNil(e.update(session: s, preferences: p, at: start))
        s.accumulatedDistanceMeters = 2001
        XCTAssertNotNil(e.update(session: s, preferences: p, at: start))
        s.accumulatedDistanceMeters = 3001
        XCTAssertNil(e.update(session: s, preferences: p, at: start.addingTimeInterval(1)))
        s.lastLocationTimestamp = start.addingTimeInterval(60)
        XCTAssertNil(e.update(session: s, preferences: p, at: start.addingTimeInterval(60)))
    }
    func testSavingOnlyAfterFinishAndOnce() {
        var s = session(); var e = WorkoutCoachEngine(sessionID: s.id); let p = CoachPreferences()
        _ = e.update(session: s, preferences: p, at: start)
        XCTAssertNil(e.saved(at: start))
        s = s.finished(at: start.addingTimeInterval(60))
        XCTAssertEqual(e.update(session: s, preferences: p, at: start)?.text, "운동을 마쳤어요. 저장을 확인해 주세요.")
        XCTAssertEqual(e.saved(at: start)?.text, "운동 기록을 저장했어요.")
        XCTAssertNil(e.saved(at: start))
    }
    func testOldCheckpointStillDecodesAndBaselineDoesNotLowerHighWater() throws {
        var s = session(distance: 3200); var e = WorkoutCoachEngine(sessionID: s.id)
        let p = CoachPreferences(enabled: true)
        e.baseline(session: s, preferences: p, at: start)
        s.accumulatedDistanceMeters = 2900
        e.baseline(session: s, preferences: p, at: start)
        s.accumulatedDistanceMeters = 3201
        XCTAssertNil(e.update(session: s, preferences: p, at: start))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        object.removeValue(forKey: "coachCheckpoint")
        XCTAssertNil(try JSONDecoder().decode(RecordWorkoutSession.self, from: JSONSerialization.data(withJSONObject: object)).coachCheckpoint)
    }
    func testOtherSessionAndNonfiniteInputIgnored() {
        var s = session(); var e = WorkoutCoachEngine(sessionID: s.id); let p = CoachPreferences(enabled: true)
        e.baseline(session: s, preferences: p, at: start)
        XCTAssertNil(e.update(session: session(distance: 5000), preferences: p, at: start))
        s.accumulatedDistanceMeters = .infinity
        XCTAssertNil(e.update(session: s, preferences: p, at: start))
    }
    func testRequestContainsNoHealthMetricsOrProviderKey() throws {
        let r = request(); let data = try JSONEncoder().encode(r)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for field in ["name", "gpsRoute", "heartRate", "distance", "pace", "elapsedTime", "providerApiKey", "userId"] { XCTAssertNil(object[field]) }
    }
    func request() -> CoachPhraseRequest { CoachPhraseRequest(requestId: UUID(), sessionId: UUID(), generation: 1, eventId: UUID(), sport: "running") }
    func testMockValidPhraseAndInvalidNumbers() async throws {
        let r = request()
        let valid = CoachPhraseClient(transport: MockTransport(text: CoachPhraseClient.reviewedPhrases[0]))
        let phrase = try await valid.phrase(request: r, paused: true, consented: true, requestedAt: start, now: { self.start })
        XCTAssertEqual(phrase, CoachPhraseClient.reviewedPhrases[0])
        let invalid = CoachPhraseClient(transport: MockTransport(text: "심박 180으로 더 빨리 달려요."))
        do { _ = try await invalid.phrase(request: r, paused: true, consented: true, requestedAt: start, now: { self.start }); XCTFail() } catch { }
    }
    func testLateOrUnconsentedResponseAndMissingConnection() async {
        let c = CoachPhraseClient(transport: MockTransport(text: CoachPhraseClient.reviewedPhrases[0]))
        do { _ = try await c.phrase(request: request(), paused: true, consented: true, requestedAt: start, now: { self.start.addingTimeInterval(4) }); XCTFail() } catch { }
        do { _ = try await c.phrase(request: request(), paused: true, consented: false, requestedAt: start); XCTFail() } catch { }
        do { _ = try await UnconnectedCoachPhraseTransport().phrase(for: request()); XCTFail() } catch { }
    }
    struct MockTransport: CoachPhraseTransport {
        let text: String
        func phrase(for r: CoachPhraseRequest) async throws -> CoachPhraseResponse {
            CoachPhraseResponse(requestId: r.requestId, eventId: r.eventId, schemaVersion: 1, phrase: text, ttlSeconds: 10, source: "local")
        }
    }
    @MainActor func testAccountSeparationMuteAndWatchOwner() {
        let defaults = UserDefaults(suiteName: "coach-tests-\(UUID())")!; let speech = MockSpeech()
        let c = WorkoutCoachCoordinator(defaults: defaults, speech: speech)
        c.bind(scope: "one"); var s = session()
        c.configure(CoachPreferences(enabled: true), session: nil, at: start)
        c.update(session: s, at: Date())
        XCTAssertEqual(speech.events.count, 1)
        c.bind(scope: "two"); XCTAssertFalse(c.preferences.enabled)
        c.update(session: s, at: Date(), phoneOwnsRecording: false)
        XCTAssertEqual(speech.events.count, 1)
        c.bind(scope: "one"); XCTAssertTrue(c.preferences.enabled)
        c.update(session: s, at: Date(), restored: true)
        XCTAssertEqual(speech.events.count, 1)
        c.configure(CoachPreferences(enabled: false), session: s, at: start)
        s = s.paused(at: start.addingTimeInterval(10)); c.update(session: s, at: Date())
        XCTAssertEqual(speech.events.count, 1)
        XCTAssertEqual(c.caption, "잠시 멈췄어요.")
    }
    @MainActor final class MockSpeech: CoachSpeechOutput {
        var status = "mock"; var events: [CoachEvent] = []; var stops = 0
        func speak(_ event: CoachEvent) { events.append(event) }
        func stop() { stops += 1 }
        func confirmOutput() { }
    }
}
