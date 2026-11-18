import XCTest
@testable import SOOM

@MainActor
final class GoogleHealthWorkoutDetailsTests: XCTestCase {
    func testHeartRateSamplesAreAvailableWithoutGPS() throws {
        let response = try details(heartRate: [
            ["time": "2026-09-20T06:00:00Z", "bpm": 120],
            ["time": "2026-09-20T15:05:00.500+09:00", "bpm": 151],
            ["time": "2026-09-20T06:10:00Z", "bpm": 138]
        ])
        let workout = try imported(response)
        let telemetry = response.makeTelemetry(for: workout)

        XCTAssertNil(response.makeRoute(for: workout))
        XCTAssertEqual(telemetry.workoutID, workout.id)
        XCTAssertEqual(telemetry.source, .googleHealth)
        XCTAssertEqual(telemetry.samples.compactMap(\.heartRateBPM), [120, 151, 138])
        XCTAssertEqual(telemetry.samples[1].timestamp.timeIntervalSince(workout.startDate), 300.5, accuracy: 0.001)
        XCTAssertTrue(telemetry.samples.allSatisfy { $0.powerWatts == nil && $0.cadencePerMinute == nil })
    }

    func testHeartRateOutsideWorkoutAndInvalidMeasurementsAreRejected() throws {
        let response = try details(heartRate: [
            ["time": "2026-09-20T05:59:59.999Z", "bpm": 120],
            ["time": "2026-09-20T06:10:00.001Z", "bpm": 120],
            ["time": "not-a-timestamp", "bpm": 120],
            ["time": "2026-09-20T06:01:00Z", "bpm": 0],
            ["time": "2026-09-20T06:02:00Z", "bpm": -1],
            ["time": "2026-09-20T06:03:00Z", "bpm": 301],
            ["time": "2026-09-20T06:04:00Z", "bpm": 147]
        ])
        let telemetry = response.makeTelemetry(for: try imported(response))
        XCTAssertEqual(telemetry.samples.compactMap(\.heartRateBPM), [147])
    }

    func testIntervalsPreserveServerSIUnitsAndDoNotInventSensorReadings() throws {
        let response = try details(intervals: [
            "distance": [interval(["meters": 120.5])],
            "steps": [interval(["count": 83])],
            "energy": [interval(["kilocalories": 12.25])],
            "elevation_gain": [interval(["meters": 7.5])],
            "active_zone_minutes": [interval(["minutes": 2, "zone": "VIGOROUS"])],
        ])
        let telemetry = response.makeTelemetry(for: try imported(response))
        XCTAssertEqual(telemetry.intervals.count, 5)
        XCTAssertEqual(telemetry.intervals.first { $0.kind == .distanceMeters }?.value, 120.5)
        XCTAssertEqual(telemetry.intervals.first { $0.kind == .steps }?.value, 83)
        XCTAssertEqual(telemetry.intervals.first { $0.kind == .energyKcal }?.value, 12.25)
        XCTAssertEqual(telemetry.intervals.first { $0.kind == .elevationGainMeters }?.value, 7.5)
        XCTAssertEqual(telemetry.intervals.first { $0.kind == .activeZoneMinutes }?.zone, "VIGOROUS")
        XCTAssertTrue(telemetry.samples.isEmpty, "Interval totals are not measured point samples.")
        let derived = WorkoutTelemetryChartBuilder.addingDerivedChannels(to: telemetry, route: nil)
        XCTAssertEqual(try XCTUnwrap(derived.samples.compactMap(\.speedMetersPerSecond).first), 120.5 / 60, accuracy: 0.0001)
        XCTAssertTrue(derived.samples.allSatisfy { $0.elevationMeters == nil }, "Elevation gain is not absolute altitude.")
        // Existing chart enrichment derives interval-average cadence from 83 steps / 60 seconds.
        // The raw telemetry above remains empty; no measured cadence or power is invented.
        XCTAssertEqual(derived.samples.compactMap(\.cadencePerMinute), [83])
        XCTAssertTrue(derived.samples.allSatisfy { $0.powerWatts == nil })
    }

    func testIntervalsRejectPartialOverlapInvalidOrderAndNegativeValues() throws {
        let response = try details(intervals: ["distance": [
            interval(["meters": 30], start: "2026-09-20T05:59:59Z"),
            interval(["meters": 30], end: "2026-09-20T06:10:01Z"),
            interval(["meters": 30], end: "2026-09-20T06:00:00Z"),
            interval(["meters": -1]),
            interval(["meters": 30], start: "invalid"),
            interval(["meters": 0]),
            interval(["meters": 60])
        ]])
        let telemetry = response.makeTelemetry(for: try imported(response))
        XCTAssertEqual(telemetry.intervals.map(\.value), [0, 60])
    }

    func testRecordedSplitsZonesAndMobilitySummariesRetainUnits() throws {
        let response = try details(exercise: [
            "metricsSummary": [
                "steps": "2200", "activeZoneMinutes": "5", "runVo2Max": 52.5,
                "totalSwimLengths": 4,
                "heartRateZoneDurations": ["lightTime": "10.5s", "moderateTime": "20s", "vigorousTime": "30s", "peakTime": "0s"],
                "mobilityMetrics": ["avgCadenceStepsPerMinute": 170, "avgStrideLengthMillimeters": "1100",
                    "avgGroundContactTimeDuration": "0.25s", "avgVerticalOscillationMillimeters": "80", "avgVerticalRatio": 7.1]
            ],
            "exerciseMetadata": ["hasGps": false, "poolLengthMillimeters": "25000"],
            "splits": [split(distanceMillimeters: 9_000_000)],
            "splitSummaries": [
                split(distanceMillimeters: 1_000_000, activeDuration: "240s", metrics: [
                    "averageHeartRateBeatsPerMinute": "145", "mobilityMetrics": ["avgCadenceStepsPerMinute": 169]
                ]),
                split(start: "2026-09-20T06:05:00Z", end: "2026-09-20T06:10:00Z",
                      distanceMillimeters: 500_000, activeDuration: "999s")
            ]
        ])
        let telemetry = response.makeTelemetry(for: try imported(response))
        XCTAssertEqual(telemetry.splits.map(\.distanceMeters), [1000, 500], "Recorded laps take priority over automatic splits.")
        XCTAssertEqual(telemetry.splits.map(\.durationSeconds), [240, 300])
        XCTAssertEqual(telemetry.splits[0].averageHeartRate, 145)
        XCTAssertEqual(telemetry.splits[0].averageCadence, 169)
        XCTAssertEqual(telemetry.heartRateZones.map(\.durationSeconds), [10.5, 20, 30, 0], "An explicitly supplied zero duration is not missing data.")
        XCTAssertEqual(Set(telemetry.heartRateZones.map(\.name)).count, 4)
        let metrics = Dictionary(uniqueKeysWithValues: telemetry.summaryMetrics.map { ($0.key, $0) })
        XCTAssertEqual(metrics["steps"]?.value, 2200)
        XCTAssertEqual(metrics["activeZoneMinutes"]?.value, 5)
        XCTAssertEqual(metrics["runVo2Max"]?.value, 52.5)
        XCTAssertEqual(metrics["swimLengths"]?.value, 4)
        XCTAssertEqual(metrics["poolLength"]?.value, 25)
        XCTAssertEqual(metrics["runningCadence"]?.unit, "spm")
        XCTAssertEqual(metrics["runningCadence"]?.value, 170)
        XCTAssertEqual(try XCTUnwrap(metrics["strideLength"]?.value), 1.1, accuracy: 0.0001)
        XCTAssertEqual(metrics["groundContact"]?.value, 250)
        XCTAssertEqual(metrics["groundContact"]?.unit, "ms")
        XCTAssertEqual(metrics["verticalOscillation"]?.value, 8)
        XCTAssertEqual(metrics["verticalOscillation"]?.unit, "cm")
        XCTAssertEqual(metrics["verticalRatio"]?.value, 7.1)
    }

    func testAutomaticSplitsAreFallbackAndInvalidSplitsAreDropped() throws {
        let response = try details(exercise: [
            "splitSummaries": [],
            "splits": [
                split(distanceMillimeters: 800_000),
                split(start: "2026-09-20T05:59:00Z", distanceMillimeters: 100_000),
                split(end: "2026-09-20T06:11:00Z", distanceMillimeters: 100_000),
                split(end: "2026-09-20T06:00:00Z", distanceMillimeters: 100_000)
            ]
        ])
        let telemetry = response.makeTelemetry(for: try imported(response))
        XCTAssertEqual(telemetry.splits.count, 1)
        XCTAssertEqual(telemetry.splits.first?.distanceMeters, 800)
        XCTAssertEqual(telemetry.splits.first?.durationSeconds, 300)
    }

    func testSummaryAveragesDoNotBecomePowerCadenceOrHeartRateGraphs() throws {
        let response = try details(exercise: ["metricsSummary": [
            "averageHeartRateBeatsPerMinute": "152", "averageSpeedMillimetersPerSecond": 3000,
            "mobilityMetrics": ["avgCadenceStepsPerMinute": 175]
        ]])
        let workout = try imported(response)
        let telemetry = response.makeTelemetry(for: workout)
        XCTAssertEqual(workout.averageHeartRate, 152)
        XCTAssertEqual(workout.averageCadence, 175)
        XCTAssertNil(workout.averagePowerWatts)
        XCTAssertTrue(telemetry.samples.isEmpty)
        XCTAssertTrue(telemetry.heartRateZones.isEmpty)
        XCTAssertTrue(telemetry.splits.isEmpty)
        XCTAssertEqual(telemetry.summaryMetrics.first { $0.key == "runningCadence" }?.value, 175)
    }

    func testContinuationPageAddsMeasurementsWithoutRepeatingSummaryOrEvents() throws {
        let summary: [String: Any] = [
            "metricsSummary": ["steps": "2000", "heartRateZoneDurations": ["lightTime": "600s"]],
            "splits": [split(distanceMillimeters: 1_000_000)],
            "exerciseEvents": [["eventTime": "2026-09-20T06:01:00Z", "exerciseEventType": "PAUSE"]]
        ]
        let first = try details(exercise: summary, heartRate: [["time": "2026-09-20T06:00:00Z", "bpm": 120]],
                                nextTokens: ["heart_rate": "opaque-next-token"])
        let next = try details(exercise: summary, heartRate: [["time": "2026-09-20T06:01:00Z", "bpm": 130]])
        let workout = try imported(first)
        let firstTelemetry = first.makeTelemetry(for: workout)
        let nextTelemetry = next.makeTelemetry(for: workout, includeSummary: false)
        XCTAssertEqual(first.next_page_tokens?["heart_rate"], "opaque-next-token")
        XCTAssertFalse(firstTelemetry.splits.isEmpty)
        XCTAssertFalse(firstTelemetry.heartRateZones.isEmpty)
        XCTAssertFalse(firstTelemetry.summaryMetrics.isEmpty)
        XCTAssertFalse(firstTelemetry.events.isEmpty)
        XCTAssertTrue(nextTelemetry.splits.isEmpty)
        XCTAssertTrue(nextTelemetry.heartRateZones.isEmpty)
        XCTAssertTrue(nextTelemetry.summaryMetrics.isEmpty)
        XCTAssertTrue(nextTelemetry.events.isEmpty)
        XCTAssertEqual((firstTelemetry.samples + nextTelemetry.samples).compactMap(\.heartRateBPM), [120, 130])
    }

    func testOptionalSwimStrokesAndExerciseEventsStayWithinWorkout() throws {
        let response = try details(exercise: [
            "exerciseType": "POOL_SWIMMING",
            "exerciseEvents": [
                ["eventTime": "2026-09-20T06:01:00Z", "exerciseEventType": "PAUSE"],
                ["eventTime": "2026-09-20T06:02:00Z", "exerciseEventType": "RESUME"],
                ["eventTime": "2026-09-20T06:11:00Z", "exerciseEventType": "PAUSE"],
                ["eventTime": "invalid", "exerciseEventType": "RESUME"]
            ]
        ], intervals: ["swim_lengths": [
            interval(["stroke_count": 18, "stroke_type": "FREESTYLE"]),
            interval(["stroke_count": -2, "stroke_type": "BREASTSTROKE"]),
            interval(["stroke_count": 19], end: "2026-09-20T06:11:00Z")
        ]])
        let telemetry = response.makeTelemetry(for: try imported(response))
        XCTAssertEqual(telemetry.events.map(\.type), ["PAUSE", "RESUME"])
        XCTAssertEqual(telemetry.intervals.count, 1)
        XCTAssertEqual(telemetry.intervals.first?.kind, .swimStrokeCount)
        XCTAssertEqual(telemetry.intervals.first?.value, 18)
        XCTAssertEqual(telemetry.intervals.first?.zone, "FREESTYLE")
    }

    func testActualTCXRouteAndSensorChannelsAreAssociatedWithImportedWorkout() throws {
        let response = try details(tcx: tcx())
        let workout = try imported(response)
        let route = try XCTUnwrap(response.makeRoute(for: workout))
        XCTAssertEqual(route.workoutId, workout.id)
        XCTAssertEqual(route.source, .googleHealth)
        XCTAssertEqual(route.coordinates.map(\.latitude), [37.5, 37.501])
        XCTAssertEqual(route.coordinates.map(\.altitude), [12, 18])
        XCTAssertEqual(route.coordinates.first?.timestamp, workout.startDate)
        let telemetry = response.makeTelemetry(for: workout)
        XCTAssertEqual(telemetry.samples.compactMap(\.heartRateBPM), [140, 146])
        XCTAssertEqual(telemetry.samples.compactMap(\.powerWatts), [210, 225])
        XCTAssertEqual(telemetry.samples.compactMap(\.cadencePerMinute), [82, 84])
        XCTAssertEqual(telemetry.samples.compactMap(\.cadenceUnit), [.revolutionsPerMinute, .revolutionsPerMinute])
    }

    func testTCXForAnotherWorkoutCannotAttachRouteOrSensorSamples() throws {
        let response = try details(tcx: tcx(day: "2026-09-19"))
        let workout = try imported(response)
        XCTAssertNil(response.makeRoute(for: workout))
        XCTAssertTrue(response.makeTelemetry(for: workout).samples.isEmpty)
        let partiallyOverlapping = try details(tcx: tcx(lastPointTime: "2026-09-20T06:10:01Z"))
        XCTAssertNil(partiallyOverlapping.makeRoute(for: workout), "Do not attach a route with coordinates outside the activity.")
    }

    func testTransientFailuresNeedRetryButPermissionAndNoDataDoNot() throws {
        XCTAssertTrue(try details(channels: ["heart_rate": ["status": "unavailable", "error": "upstream_timeout"]]).hasRetryableFailure)
        XCTAssertFalse(try details(channels: [
            "route": ["status": "permission_required"],
            "heart_rate": ["status": "empty"]
        ]).hasRetryableFailure)
    }

    private func details(exercise: [String: Any] = [:], heartRate: [[String: Any]] = [],
                         intervals: [String: Any] = [:], tcx: String? = nil,
                         channels: [String: Any] = [:], nextTokens: [String: String]? = nil) throws -> GoogleHealthWorkoutDetails {
        var exerciseBody: [String: Any] = [
            "interval": ["startTime": "2026-09-20T06:00:00Z", "endTime": "2026-09-20T06:10:00Z"],
            "exerciseType": "RUNNING", "exerciseMetadata": ["hasGps": false]
        ]
        exerciseBody.merge(exercise) { _, replacement in replacement }
        var body: [String: Any] = [
            "workout": ["name": "users/test-account/dataTypes/exercise/dataPoints/12345", "exercise": exerciseBody],
            "heart_rate": heartRate, "telemetry": intervals, "channels": channels
        ]
        if let tcx { body["tcx"] = tcx }
        if let nextTokens { body["next_page_tokens"] = nextTokens }
        return try JSONDecoder().decode(GoogleHealthWorkoutDetails.self, from: JSONSerialization.data(withJSONObject: body))
    }

    private func imported(_ response: GoogleHealthWorkoutDetails) throws -> UnifiedWorkout {
        try XCTUnwrap(response.workout.makeWorkout(now: Date(timeIntervalSince1970: 1_900_000_000)))
    }

    private func interval(_ values: [String: Any], start: String = "2026-09-20T06:00:00Z",
                          end: String = "2026-09-20T06:01:00Z") -> [String: Any] {
        var result = values
        result["start_time"] = start
        result["end_time"] = end
        return result
    }

    private func split(start: String = "2026-09-20T06:00:00Z", end: String = "2026-09-20T06:05:00Z",
                       distanceMillimeters: Double, activeDuration: String? = nil,
                       metrics: [String: Any] = [:]) -> [String: Any] {
        var summary = metrics
        summary["distanceMillimeters"] = distanceMillimeters
        var result: [String: Any] = ["startTime": start, "endTime": end, "metricsSummary": summary]
        if let activeDuration { result["activeDuration"] = activeDuration }
        return result
    }

    /// Synthetic local fixture; no actual athlete GPS or health records.
    private func tcx(day: String = "2026-09-20", lastPointTime: String? = nil) -> String {
        let start = "\(day)T06:00:00Z"
        let end = lastPointTime ?? "\(day)T06:01:00Z"
        return """
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities><Activity Sport="Biking"><Id>\(start)</Id>
            <Lap StartTime="\(start)"><TotalTimeSeconds>60</TotalTimeSeconds><DistanceMeters>200</DistanceMeters><Track>
              <Trackpoint><Time>\(start)</Time><Position><LatitudeDegrees>37.5</LatitudeDegrees><LongitudeDegrees>127</LongitudeDegrees></Position><AltitudeMeters>12</AltitudeMeters><DistanceMeters>0</DistanceMeters><HeartRateBpm><Value>140</Value></HeartRateBpm><Cadence>82</Cadence><Extensions><TPX xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2"><Watts>210</Watts><Speed>3.1</Speed></TPX></Extensions></Trackpoint>
              <Trackpoint><Time>\(end)</Time><Position><LatitudeDegrees>37.501</LatitudeDegrees><LongitudeDegrees>127.001</LongitudeDegrees></Position><AltitudeMeters>18</AltitudeMeters><DistanceMeters>200</DistanceMeters><HeartRateBpm><Value>146</Value></HeartRateBpm><Cadence>84</Cadence><Extensions><TPX xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2"><Watts>225</Watts><Speed>3.4</Speed></TPX></Extensions></Trackpoint>
            </Track></Lap>
          </Activity></Activities>
        </TrainingCenterDatabase>
        """
    }
}
