import XCTest
import ActivityKit
import UIKit
import HealthKit
@testable import SOOM

final class WorkoutLiveStateTests: XCTestCase {
    @MainActor
    func testNativeActivityKitStartsUpdatesAndEnds() async throws {
        guard UIApplication.shared.applicationState == .active,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw XCTSkip("Native Live Activities require a foreground simulator with permission enabled")
        }
        let controller = WorkoutLiveActivityController.shared
        let now = Date()
        var state = WorkoutLiveState(id: UUID(), scope: "activitykit-test", sport: .running, phase: .running,
            startedAt: now, updatedAt: now, elapsed: 0, distance: 0, isWatch: false)
        controller.submit(state, force: true)
        defer { controller.clear() }
        for _ in 0..<100 {
            if Activity<SOOMWorkoutAttributes>.activities.contains(where: { $0.attributes.workoutID == state.id }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let activity = try XCTUnwrap(Activity<SOOMWorkoutAttributes>.activities.first { $0.attributes.workoutID == state.id }, controller.unavailableReason ?? "Widget extension did not register")
        state.phase = .paused; state.elapsed = 12; state.updatedAt = Date()
        controller.submit(state, force: true)
        for _ in 0..<100 {
            if activity.content.state.phase == .paused { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(activity.content.state.phase, .paused)
        XCTAssertEqual(activity.content.state.elapsed, 12)
        controller.clear()
        for _ in 0..<100 {
            if activity.activityState == .ended || activity.activityState == .dismissed { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(activity.activityState == .ended || activity.activityState == .dismissed)
    }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func state(phase: WorkoutLiveState.Phase = .running, sequence: Int = 1) -> WorkoutLiveState {
        WorkoutLiveState(id: UUID(), scope: "account-a", sport: .running, phase: phase,
            startedAt: start, updatedAt: start.addingTimeInterval(90), elapsed: 60, distance: 200, isWatch: true, sequence: sequence)
    }
    func testTimerAddsOnlyActiveTimeAfterSnapshot() {
        let active = state()
        XCTAssertEqual(active.elapsed(at: active.updatedAt.addingTimeInterval(10)), 70)
        var paused = active; paused.phase = .paused
        XCTAssertEqual(paused.elapsed(at: paused.updatedAt.addingTimeInterval(600)), 60)
        XCTAssertEqual(paused.timerStart, paused.updatedAt.addingTimeInterval(-60))
    }
    func testPaceUsesMeasuredDistanceAndActiveTime() {
        let value = state()
        XCTAssertEqual(value.pace(at: value.updatedAt), "5:00")
        XCTAssertEqual(value.distanceText, "0.20")
        var cycling = value; cycling.sport = .cycling
        XCTAssertEqual(cycling.effortText(at: value.updatedAt), "12.0")
        XCTAssertEqual(cycling.effortUnit, "km/h")
        var unknown = value; unknown.distance = 0
        XCTAssertEqual(unknown.pace(at: unknown.updatedAt), "–:––")
    }
    func testFormattingAcrossHourBoundary() {
        XCTAssertEqual(WorkoutLiveState.time(59), "0:59")
        XCTAssertEqual(WorkoutLiveState.time(3601), "1:00:01")
    }
    func testOtherAccountAndInvalidMeasurementsNeverEnterInbox() {
        var inbox = WorkoutLiveInbox()
        var packet = state()
        XCTAssertFalse(inbox.receive(packet, scope: "account-b"))
        packet.distance = .nan
        XCTAssertFalse(inbox.receive(packet, scope: "account-a"))
        packet.distance = 200; packet.heartRate = -.infinity
        XCTAssertFalse(inbox.receive(packet, scope: "account-a"))
        XCTAssertNil(inbox.latest)
    }
    func testMirroringAndConnectivityDuplicatesAndOutOfOrderPacketsAreIgnored() {
        var inbox = WorkoutLiveInbox()
        let first = state()
        XCTAssertTrue(inbox.receive(first, scope: "account-a"))
        XCTAssertFalse(inbox.receive(first, scope: "account-a"))
        var next = first; next.sequence = 3; next.updatedAt = first.updatedAt.addingTimeInterval(5); next.phase = .paused
        XCTAssertTrue(inbox.receive(next, scope: "account-a"))
        var late = first; late.sequence = 2
        XCTAssertFalse(inbox.receive(late, scope: "account-a"))
        late.sequence = 4 // Higher sequence still must not move timestamp backwards.
        XCTAssertFalse(inbox.receive(late, scope: "account-a"))
        XCTAssertEqual(inbox.latest?.phase, .paused)
    }
    func testDelayedPacketsNeverResurrectEndedWorkoutOrInterruptNextWorkout() {
        var inbox = WorkoutLiveInbox()
        let first = state()
        XCTAssertTrue(inbox.receive(first, scope: "account-a"))
        var ended = first; ended.phase = .finished; ended.sequence = 2
        XCTAssertTrue(inbox.receive(ended, scope: "account-a"))
        var late = first; late.sequence = 100
        XCTAssertFalse(inbox.receive(late, scope: "account-a"))
        var next = state(); next.startedAt = first.updatedAt; next.updatedAt = first.updatedAt.addingTimeInterval(10)
        XCTAssertTrue(inbox.receive(next, scope: "account-a"))
        XCTAssertFalse(inbox.receive(ended, scope: "account-a"))
        XCTAssertEqual(inbox.latest?.id, next.id)
    }
    func testNewWorkoutRecoversAfterOfflineFinishPacketWasLost() {
        var inbox = WorkoutLiveInbox()
        let first = state()
        XCTAssertTrue(inbox.receive(first, scope: "account-a"))
        var next = state(); next.startedAt = first.updatedAt.addingTimeInterval(600)
        next.updatedAt = next.startedAt.addingTimeInterval(60)
        XCTAssertTrue(inbox.receive(next, scope: "account-a"))
        var late = first; late.sequence = 50; late.phase = .finished
        XCTAssertFalse(inbox.receive(late, scope: "account-a"))
        XCTAssertEqual(inbox.latest?.id, next.id)
    }
    func testOlderQueuedWorkoutCannotReplaceOngoingWorkout() {
        var inbox = WorkoutLiveInbox(); let first = state()
        XCTAssertTrue(inbox.receive(first, scope: "account-a"))
        var older = state(); older.startedAt = first.startedAt.addingTimeInterval(-3600)
        XCTAssertFalse(inbox.receive(older, scope: "account-a"))
    }
    func testAccountResetRemovesPriorState() {
        var inbox = WorkoutLiveInbox(); let packet = state()
        XCTAssertTrue(inbox.receive(packet, scope: "account-a")); inbox.reset()
        XCTAssertNil(inbox.latest)
        XCTAssertFalse(inbox.receive(packet, scope: "account-b"))
    }
    func testWireRoundTripKeepsSourceAndMissingMetrics() throws {
        let value = state()
        let roundTrip = try JSONDecoder().decode(WorkoutLiveState.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(value, roundTrip)
        XCTAssertNil(roundTrip.power); XCTAssertNil(roundTrip.elevationGain)
    }
    func testSwimmingUsesMetersAndPacePerHundredMeters() {
        var swim = state(phase: .paused)
        swim.sport = .swimming; swim.distance = 1000; swim.elapsed = 1200
        swim.swimmingStrokeCount = 450; swim.poolLengthMeters = 25
        XCTAssertEqual(swim.displayDistance, "1000")
        XCTAssertEqual(swim.distanceUnit, "m")
        XCTAssertEqual(swim.effortText(at: swim.updatedAt.addingTimeInterval(900)), "2:00")
        XCTAssertEqual(swim.effortUnit, "/100m")
        XCTAssertTrue(swim.isValid)
    }
    func testPoolPlanConfiguresHealthKitWithoutGPS() throws {
        for length in [20.0, 25, 100.0 / 3, 50] {
            let plan = WatchWorkoutPlan(sport: .swimming, indoor: true, poolLengthMeters: length)
            XCTAssertTrue(plan.isValid)
            XCTAssertEqual(plan.configuration.activityType, .swimming)
            XCTAssertEqual(plan.configuration.swimmingLocationType, .pool)
            XCTAssertEqual(plan.configuration.locationType, .indoor)
            XCTAssertEqual(try XCTUnwrap(plan.configuration.lapLength).doubleValue(for: .meter()), length, accuracy: 0.001)
            XCTAssertEqual(WatchWorkoutPlan(configuration: plan.configuration), plan)
        }
    }
    func testOpenWaterAndLandWorkoutsKeepTheirHealthKitSport() {
        for sport in WorkoutLiveState.Sport.allCases {
            let plan = WatchWorkoutPlan(sport: sport)
            XCTAssertTrue(plan.isValid)
            XCTAssertEqual(plan.configuration.activityType, sport.healthKitType)
            XCTAssertEqual(plan.configuration.locationType, .outdoor)
            XCTAssertNil(plan.configuration.lapLength)
            XCTAssertEqual(WatchWorkoutPlan(configuration: plan.configuration), plan)
        }
        XCTAssertEqual(WatchWorkoutPlan(sport: .swimming).configuration.swimmingLocationType, .openWater)
    }
    func testInvalidPoolLengthsCannotStartAWorkout() {
        for length: Double? in [nil, 0, 9, 151, .nan, .infinity] {
            XCTAssertFalse(WatchWorkoutPlan(sport: .swimming, indoor: true, poolLengthMeters: length).isValid)
        }
        XCTAssertFalse(WatchWorkoutPlan(sport: .running, poolLengthMeters: 25).isValid)
        XCTAssertFalse(WatchWorkoutPlan(sport: .swimming, poolLengthMeters: 0).isValid)
    }
    func testExternalWorkoutConfigurationNeverBecomesWrongSport() throws {
        let unsupported = HKWorkoutConfiguration(); unsupported.activityType = .yoga
        XCTAssertNil(WatchWorkoutPlan(configuration: unsupported))
        let pool = HKWorkoutConfiguration(); pool.activityType = .swimming
        pool.locationType = .outdoor; pool.swimmingLocationType = .pool
        XCTAssertNil(WatchWorkoutPlan(configuration: pool)) // Do not silently invent the pool length.
        pool.lapLength = HKQuantity(unit: .yard(), doubleValue: 25)
        let plan = try XCTUnwrap(WatchWorkoutPlan(configuration: pool))
        XCTAssertEqual(plan.sport, .swimming)
        XCTAssertFalse(plan.indoor)
        XCTAssertFalse(plan.recordsRoute)
        XCTAssertEqual(try XCTUnwrap(plan.poolLengthMeters), 22.86, accuracy: 0.001)
    }
    func testSportSpecificSensorsDoNotUseRunningDataForSwimming() {
        XCTAssertEqual(WorkoutLiveState.Sport.swimming.distanceQuantity, .distanceSwimming)
        XCTAssertEqual(WorkoutLiveState.Sport.cycling.distanceQuantity, .distanceCycling)
        XCTAssertEqual(WorkoutLiveState.Sport.swimming.additionalQuantities, [.distanceSwimming, .swimmingStrokeCount])
        XCTAssertFalse(WorkoutLiveState.Sport.walking.additionalQuantities.contains(.runningPower))
    }
    func testOldPacketsDecodeWithoutNewSwimmingFields() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state())) as? [String: Any])
        json.removeValue(forKey: "swimmingStrokeCount"); json.removeValue(forKey: "poolLengthMeters")
        let value = try JSONDecoder().decode(WorkoutLiveState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(value.swimmingStrokeCount); XCTAssertNil(value.poolLengthMeters)
        XCTAssertEqual(value.sport, .running)
        XCTAssertEqual(value.distanceUnit, "km")
    }
    func testSwimmingWirePacketRoundTripsAndRejectsInvalidValues() throws {
        var swim = state(); swim.sport = .swimming; swim.poolLengthMeters = 25; swim.swimmingStrokeCount = 124
        XCTAssertEqual(try JSONDecoder().decode(WorkoutLiveState.self, from: JSONEncoder().encode(swim)), swim)
        var inbox = WorkoutLiveInbox()
        swim.swimmingStrokeCount = -.infinity
        XCTAssertFalse(inbox.receive(swim, scope: swim.scope))
        swim.swimmingStrokeCount = 124; swim.poolLengthMeters = 0
        XCTAssertFalse(inbox.receive(swim, scope: swim.scope))
    }
    func testSavedHistoryKeepsUnknownMetricsMissing() throws {
        let raw = HKWorkout(activityType: .swimming, start: start, end: start.addingTimeInterval(600),
                            workoutEvents: nil, totalEnergyBurned: nil, totalDistance: nil,
                            metadata: [HKMetadataKeyIndoorWorkout: true, HKMetadataKeySwimmingLocationType: HKWorkoutSwimmingLocationType.pool.rawValue,
                                       HKMetadataKeyLapLength: HKQuantity(unit: .meter(), doubleValue: 25)])
        let item = try XCTUnwrap(WatchWorkoutHistoryItem(workout: raw))
        XCTAssertEqual(item.id, raw.uuid); XCTAssertEqual(item.sport, .swimming)
        XCTAssertEqual(item.duration, 600); XCTAssertTrue(item.indoor)
        XCTAssertEqual(item.poolLengthMeters, 25)
        XCTAssertNil(item.distance); XCTAssertNil(item.energy); XCTAssertNil(item.averageHeartRate); XCTAssertNil(item.strokes)
        XCTAssertEqual(item.distanceText, "–"); XCTAssertEqual(item.effortText, "–")
    }
    func testSavedHistoryShowsMeasuredDistanceAndKeepsHealthKitIdentity() throws {
        let raw = HKWorkout(activityType: .swimming, start: start, end: start.addingTimeInterval(1200),
                            workoutEvents: nil, totalEnergyBurned: nil, totalDistance: HKQuantity(unit: .meter(), doubleValue: 1000), metadata: nil)
        let item = try XCTUnwrap(WatchWorkoutHistoryItem(workout: raw))
        XCTAssertEqual(item.id, raw.uuid); XCTAssertEqual(item.distanceText, "1000")
        XCTAssertEqual(item.effortText, "2:00")
    }

    func testHeartRateExpiresFromMeasurementTimeEvenWhenSnapshotsKeepRefreshing() {
        var value = state()
        value.heartRate = 142; value.heartRateMeasuredAt = value.updatedAt
        let measured = value.updatedAt
        XCTAssertEqual(value.currentHeartRate(at: measured), 142)
        XCTAssertEqual(value.currentHeartRate(at: measured.addingTimeInterval(30)), 142)
        value.updatedAt = measured.addingTimeInterval(60)
        XCTAssertNil(value.currentHeartRate(at: value.updatedAt))
        value.heartRateMeasuredAt = value.updatedAt
        XCTAssertEqual(value.currentHeartRate(at: value.updatedAt), 142)
    }
    func testHeartRateNeedsARealTimestampAndPositiveFiniteMeasurement() {
        var value = state(); value.heartRate = 142
        XCTAssertNil(value.currentHeartRate(at: value.updatedAt))
        value.heartRateMeasuredAt = value.updatedAt.addingTimeInterval(1)
        XCTAssertNil(value.currentHeartRate(at: value.updatedAt))
        value.heartRateMeasuredAt = value.updatedAt
        for invalid in [0, -1, Double.nan, .infinity] {
            value.heartRate = invalid
            XCTAssertNil(value.currentHeartRate(at: value.updatedAt))
        }
        value.heartRate = nil
        XCTAssertNil(value.currentHeartRate(at: value.updatedAt))
    }
    func testPausedAndTerminalStatesNeverPresentLiveHeartRate() {
        for phase in [WorkoutLiveState.Phase.paused, .saving, .finished, .discarded] {
            var value = state(phase: phase); value.heartRate = 138; value.heartRateMeasuredAt = value.updatedAt
            XCTAssertNil(value.currentHeartRate(at: value.updatedAt))
            XCTAssertEqual(value.elapsed(at: value.updatedAt.addingTimeInterval(60)), value.elapsed)
        }
    }
    func testLegacyPacketWithoutHeartRateTimestampDecodesWithoutInventingFreshness() throws {
        var value = state(); value.heartRate = 142; value.heartRateMeasuredAt = value.updatedAt
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        json.removeValue(forKey: "heartRateMeasuredAt")
        let old = try JSONDecoder().decode(WorkoutLiveState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.heartRate, 142)
        XCTAssertNil(old.heartRateMeasuredAt)
        XCTAssertNil(old.currentHeartRate(at: old.updatedAt))
    }
    func testHeartRateMeasurementTimestampSurvivesWatchConnectivityRoundTrip() throws {
        var value = state(); value.heartRate = 138; value.heartRateMeasuredAt = value.updatedAt.addingTimeInterval(-4)
        let decoded = try JSONDecoder().decode(WorkoutLiveState.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.currentHeartRate(at: value.updatedAt), 138)
        XCTAssertNil(decoded.currentHeartRate(at: value.updatedAt.addingTimeInterval(27)))
    }
    func testWatchClockKeepsHoursAndDoesNotChangeExistingHistoryTimeFormatting() {
        XCTAssertEqual(WorkoutLiveState.clockTime(0), "00:00:00")
        XCTAssertEqual(WorkoutLiveState.clockTime(1234), "00:20:34")
        XCTAssertEqual(WorkoutLiveState.clockTime(3601), "01:00:01")
        XCTAssertEqual(WorkoutLiveState.time(1234), "20:34")
    }

}
