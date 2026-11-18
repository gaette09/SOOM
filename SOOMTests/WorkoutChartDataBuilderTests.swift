import XCTest
@testable import SOOM

final class WorkoutChartDataBuilderTests: XCTestCase {
    // Match the spherical Earth model used to measure route distances.
    private let metersPerLatitudeDegree = 6_371_000.0 * Double.pi / 180

    func testTooFewPointsProducesNoSamplesOrSplits() {
        let route = makeRoute(coordinates: [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: Date())
        ], totalDistanceMeters: 0)

        XCTAssertTrue(WorkoutChartDataBuilder.samples(from: route).isEmpty)
        XCTAssertTrue(WorkoutChartDataBuilder.splits(from: route).isEmpty)
    }

    func testZeroDurationProducesNoSamples() {
        let now = Date()
        let route = makeRoute(coordinates: [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: now),
            WorkoutRouteCoordinate(latitude: 37.501, longitude: 127.0, timestamp: now)
        ], totalDistanceMeters: 111)

        XCTAssertTrue(WorkoutChartDataBuilder.samples(from: route).isEmpty)
    }

    func testMissingTimestampsAreExcluded() {
        let now = Date()
        let route = makeRoute(coordinates: [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: now),
            WorkoutRouteCoordinate(latitude: 37.501, longitude: 127.0, timestamp: nil),
            WorkoutRouteCoordinate(latitude: 37.502, longitude: 127.0, timestamp: now.addingTimeInterval(60))
        ], totalDistanceMeters: 222)

        // Only 2 timestamped points remain once the nil-timestamp point is dropped.
        let samples = WorkoutChartDataBuilder.samples(from: route)
        XCTAssertEqual(samples.count, 1)
    }

    /// A straight-line, constant-pace route: 10km over 50 minutes (5:00/km),
    /// one point per minute, each step covering exactly 200m.
    func testConstantPaceRouteProducesRealPaceSamplesAndKmSplits() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let stepMeters = 200.0
        let stepSeconds = 60.0
        let pointCount = 51 // 0...50 minutes

        var coordinates: [WorkoutRouteCoordinate] = []
        for index in 0..<pointCount {
            let latitudeOffset = (Double(index) * stepMeters) / metersPerLatitudeDegree
            coordinates.append(
                WorkoutRouteCoordinate(
                    latitude: 37.5 + latitudeOffset,
                    longitude: 127.0,
                    timestamp: start.addingTimeInterval(Double(index) * stepSeconds)
                )
            )
        }

        let route = makeRoute(coordinates: coordinates, totalDistanceMeters: 10_000)

        let samples = WorkoutChartDataBuilder.samples(from: route)
        XCTAssertEqual(samples.count, 50)
        for sample in samples {
            // 200m per 60s => 300 sec/km pace, allow float tolerance.
            XCTAssertEqual(sample.paceSeconds, 300, accuracy: 0.000_001)
            XCTAssertNil(sample.heartRate)
        }

        let splits = WorkoutChartDataBuilder.splits(from: route)
        XCTAssertEqual(splits.count, 10)
        for (index, split) in splits.enumerated() {
            XCTAssertEqual(split.label, "\(index + 1) km")
            XCTAssertEqual(split.time, "5:00")
            XCTAssertEqual(split.pace, "5:00/km")
            XCTAssertNil(split.heartRate)
        }
    }

    func testSubKilometerRouteProducesNoSplits() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = makeRoute(coordinates: [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: start),
            WorkoutRouteCoordinate(
                latitude: 37.5 + (500.0 / metersPerLatitudeDegree),
                longitude: 127.0,
                timestamp: start.addingTimeInterval(150)
            )
        ], totalDistanceMeters: 500)

        XCTAssertTrue(WorkoutChartDataBuilder.splits(from: route).isEmpty)
    }

    func testHeartRateSamplesAreAveragedIntoMatchingBucketsOnly() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let stepMeters = 200.0
        var coordinates: [WorkoutRouteCoordinate] = []
        for index in 0..<3 {
            let latitudeOffset = (Double(index) * stepMeters) / metersPerLatitudeDegree
            coordinates.append(
                WorkoutRouteCoordinate(
                    latitude: 37.5 + latitudeOffset,
                    longitude: 127.0,
                    timestamp: start.addingTimeInterval(Double(index) * 60)
                )
            )
        }
        let route = makeRoute(coordinates: coordinates, totalDistanceMeters: 400)

        // Two HR samples land inside minute-bucket 0 (start...start+60s), none in bucket 1.
        let heartRateSamples = [
            HealthKitWorkoutMetricSample(
                sampleType: .heartRate, value: 140, unit: "bpm",
                startDate: start.addingTimeInterval(10), endDate: start.addingTimeInterval(11)
            ),
            HealthKitWorkoutMetricSample(
                sampleType: .heartRate, value: 150, unit: "bpm",
                startDate: start.addingTimeInterval(20), endDate: start.addingTimeInterval(21)
            )
        ]

        let samples = WorkoutChartDataBuilder.samples(from: route, heartRateSamples: heartRateSamples)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].heartRate, 145)
        XCTAssertNil(samples[1].heartRate)
    }

    func testDistanceBucketedHeartRateSamplesUseOnlyMatchingStreamData() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let stepMeters = 200.0
        let stepSeconds = 60.0
        var coordinates: [WorkoutRouteCoordinate] = []
        for index in 0..<51 {
            let latitudeOffset = (Double(index) * stepMeters) / metersPerLatitudeDegree
            coordinates.append(
                WorkoutRouteCoordinate(
                    latitude: 37.5 + latitudeOffset,
                    longitude: 127.0,
                    timestamp: start.addingTimeInterval(Double(index) * stepSeconds)
                )
            )
        }
        let route = makeRoute(coordinates: coordinates, totalDistanceMeters: 10_000)

        // One HR sample every 30s across the whole 50-minute route.
        var heartRateSamples: [HealthKitWorkoutMetricSample] = []
        var cursor = 0.0
        while cursor < 3_000 {
            heartRateSamples.append(
                HealthKitWorkoutMetricSample(
                    sampleType: .heartRate, value: 150, unit: "bpm",
                    startDate: start.addingTimeInterval(cursor), endDate: start.addingTimeInterval(cursor + 1)
                )
            )
            cursor += 30
        }

        let samples = WorkoutChartDataBuilder.heartRateSamples(from: route, heartRateSamples: heartRateSamples)
        XCTAssertFalse(samples.isEmpty)
        for sample in samples {
            XCTAssertEqual(sample.value, 150, accuracy: 0.01)
        }
    }

    func testHeartRateSamplesEmptyWithoutStream() {
        let route = makeRoute(coordinates: [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: Date()),
            WorkoutRouteCoordinate(latitude: 37.501, longitude: 127.0, timestamp: Date().addingTimeInterval(60))
        ], totalDistanceMeters: 111)

        XCTAssertTrue(WorkoutChartDataBuilder.heartRateSamples(from: route, heartRateSamples: []).isEmpty)
    }

    func testConstantPaceRouteProducesConstantSpeedSamplesCoveringFullDistance() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let stepMeters = 200.0
        let stepSeconds = 60.0
        let pointCount = 51 // 0...50 minutes, 10km @ 200m/60s => 12 km/h constant.

        var coordinates: [WorkoutRouteCoordinate] = []
        for index in 0..<pointCount {
            let latitudeOffset = (Double(index) * stepMeters) / metersPerLatitudeDegree
            coordinates.append(
                WorkoutRouteCoordinate(
                    latitude: 37.5 + latitudeOffset,
                    longitude: 127.0,
                    timestamp: start.addingTimeInterval(Double(index) * stepSeconds)
                )
            )
        }
        let route = makeRoute(coordinates: coordinates, totalDistanceMeters: 10_000)

        let samples = WorkoutChartDataBuilder.speedSamples(from: route)
        XCTAssertFalse(samples.isEmpty)
        for sample in samples {
            XCTAssertEqual(sample.value, 12.0, accuracy: 0.000_001)
        }
        XCTAssertEqual(samples.last?.distanceKilometers ?? 0, 10.0, accuracy: 0.000_001)
    }

    func testSpeedSamplesEmptyWithoutTimestamps() {
        let route = makeRoute(coordinates: [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: nil),
            WorkoutRouteCoordinate(latitude: 37.501, longitude: 127.0, timestamp: nil)
        ], totalDistanceMeters: 111)

        XCTAssertTrue(WorkoutChartDataBuilder.speedSamples(from: route).isEmpty)
    }

    func testLinearClimbRouteProducesIncreasingElevationSamples() {
        let stepMeters = 200.0
        var coordinates: [WorkoutRouteCoordinate] = []
        for index in 0..<51 {
            let latitudeOffset = (Double(index) * stepMeters) / metersPerLatitudeDegree
            coordinates.append(
                WorkoutRouteCoordinate(
                    latitude: 37.5 + latitudeOffset,
                    longitude: 127.0,
                    altitude: Double(index) * 2.0
                )
            )
        }
        let route = makeRoute(coordinates: coordinates, totalDistanceMeters: 10_000)

        let samples = WorkoutChartDataBuilder.elevationSamples(from: route)
        XCTAssertFalse(samples.isEmpty)
        for index in 1..<samples.count {
            XCTAssertGreaterThan(samples[index].value, samples[index - 1].value)
        }
        XCTAssertEqual(samples.last?.value ?? 0, 100.0, accuracy: 5.0)
    }

    func testElevationSamplesEmptyWithoutAltitude() {
        let route = makeRoute(coordinates: [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0),
            WorkoutRouteCoordinate(latitude: 37.501, longitude: 127.0)
        ], totalDistanceMeters: 111)

        XCTAssertTrue(WorkoutChartDataBuilder.elevationSamples(from: route).isEmpty)
    }

    func testIrregularIntervalsAreDividedAcrossMinuteBoundaries() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = makeTimedRoute(points: [(0, 0), (300, 90), (390, 120)], start: start)

        let samples = WorkoutChartDataBuilder.samples(from: route)

        XCTAssertEqual(samples.count, 2)
        guard samples.count == 2 else { return }
        // The first interval contributes 200m to minute 0 and 100m to minute 1.
        XCTAssertEqual(samples[0].paceSeconds, 300, accuracy: 0.000_001)
        XCTAssertEqual(samples[1].paceSeconds, 60 / 0.190, accuracy: 0.000_001)
        XCTAssertEqual(samples.map(\.minute), [0.5, 1.5])
    }

    func testSparseIntervalKeepsEveryMinuteAndFinalPartialMinute() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = makeTimedRoute(points: [(0, 0), (450, 135)], start: start)

        let samples = WorkoutChartDataBuilder.samples(from: route)

        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.map(\.minute), [0.5, 1.5, 2.125])
        for sample in samples {
            XCTAssertEqual(sample.paceSeconds, 300, accuracy: 0.000_001)
            XCTAssertNil(sample.heartRate)
        }
    }

    func testStationaryIntervalContributesElapsedTimeToPace() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = makeTimedRoute(points: [(0, 0), (100, 30), (100, 60)], start: start)

        let samples = WorkoutChartDataBuilder.samples(from: route)

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.paceSeconds ?? 0, 600, accuracy: 0.000_001)
    }

    func testHeartRateMinuteBoundariesAndPartialBucketAreHalfOpen() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = makeTimedRoute(points: [(0, 0), (450, 135)], start: start)
        let stream = [
            makeHeartRate(100, at: -1, start: start),
            makeHeartRate(120, at: 0, start: start),
            makeHeartRate(140, at: 59, start: start),
            makeHeartRate(160, at: 60, start: start),
            makeHeartRate(170, at: 120, start: start),
            makeHeartRate(190, at: 134, start: start),
            makeHeartRate(220, at: 135, start: start),
            makeHeartRate(240, at: 149, start: start)
        ]

        let samples = WorkoutChartDataBuilder.samples(from: route, heartRateSamples: stream)

        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.map(\.heartRate), [130, 160, 180])
    }

    func testKilometerSplitsInterpolateIrregularIntervalsAndHeartRateBoundaries() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = makeTimedRoute(points: [(0, 0), (600, 180), (1_400, 420), (2_300, 780)], start: start)
        let stream = [
            makeHeartRate(140, at: 0, start: start),
            makeHeartRate(160, at: 299, start: start),
            makeHeartRate(180, at: 300, start: start),
            makeHeartRate(200, at: 659, start: start),
            makeHeartRate(220, at: 660, start: start)
        ]

        let splits = WorkoutChartDataBuilder.splits(from: route, heartRateSamples: stream)

        // Crossings are at 300s and 660s, not the route endpoints at 420s and 780s.
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits.map(\.label), ["1 km", "2 km"])
        XCTAssertEqual(splits.map(\.time), ["5:00", "6:00"])
        XCTAssertEqual(splits.map(\.pace), ["5:00/km", "6:00/km"])
        XCTAssertEqual(splits.map(\.heartRate), [150, 190])
    }

    func testSparseIntervalProducesEveryCompleteKilometer() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = makeTimedRoute(points: [(0, 0), (3_500, 1_050)], start: start)

        let splits = WorkoutChartDataBuilder.splits(from: route)

        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits.map(\.label), ["1 km", "2 km", "3 km"])
        for split in splits {
            XCTAssertEqual(split.distance, "1.0 km")
            XCTAssertEqual(split.time, "5:00")
            XCTAssertEqual(split.pace, "5:00/km")
            XCTAssertNil(split.heartRate)
        }
    }

    func testExactKilometerEndpointProducesOneSplit() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = makeTimedRoute(points: [(0, 0), (1_000, 300)], start: start)

        let splits = WorkoutChartDataBuilder.splits(from: route)

        XCTAssertEqual(splits.count, 1)
        XCTAssertEqual(splits.first?.time, "5:00")
        XCTAssertEqual(splits.first?.pace, "5:00/km")
    }

    private func makeTimedRoute(
        points: [(meters: Double, seconds: TimeInterval)],
        start: Date
    ) -> WorkoutRoute {
        makeRoute(
            coordinates: points.map {
                WorkoutRouteCoordinate(
                    latitude: 37.5 + $0.meters / metersPerLatitudeDegree,
                    longitude: 127.0,
                    timestamp: start.addingTimeInterval($0.seconds)
                )
            },
            totalDistanceMeters: points.last?.meters ?? 0
        )
    }

    private func makeHeartRate(_ value: Double, at seconds: TimeInterval, start: Date) -> HealthKitWorkoutMetricSample {
        HealthKitWorkoutMetricSample(
            sampleType: .heartRate, value: value, unit: "bpm",
            startDate: start.addingTimeInterval(seconds), endDate: start.addingTimeInterval(seconds + 1)
        )
    }

    private func makeRoute(coordinates: [WorkoutRouteCoordinate], totalDistanceMeters: Double) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(),
            source: .soomLocal,
            coordinates: coordinates,
            totalDistanceMeters: totalDistanceMeters,
            createdAt: Date()
        )
    }
}


extension WorkoutChartDataBuilderTests {
    func testPausedMovementIsExcludedFromPaceSplitsAndDistanceAxisSpeed() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let perDegree = 6_371_000.0 * Double.pi / 180
        let coordinates: [WorkoutRouteCoordinate] = [
            .init(latitude: 0, longitude: 0, timestamp: start, segmentIndex: 0),
            .init(latitude: 1_000 / perDegree, longitude: 0, timestamp: start.addingTimeInterval(300), segmentIndex: 0),
            .init(latitude: 10_000 / perDegree, longitude: 0, timestamp: start.addingTimeInterval(1_200), segmentIndex: 1),
            .init(latitude: 11_000 / perDegree, longitude: 0, timestamp: start.addingTimeInterval(1_500), segmentIndex: 1)
        ]
        let route = makeRoute(coordinates: coordinates, totalDistanceMeters: 2_000)
        let splits = WorkoutChartDataBuilder.splits(from: route)
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits.map(\.time), ["5:00", "5:00"])
        let speeds = WorkoutChartDataBuilder.speedSamples(from: route)
        XCTAssertFalse(speeds.isEmpty)
        XCTAssertTrue(speeds.allSatisfy { abs($0.value - 12) < 0.01 })
        XCTAssertLessThanOrEqual(speeds.last?.distanceKilometers ?? 0, 2.0001)
        let samples = WorkoutChartDataBuilder.samples(from: route)
        XCTAssertEqual(samples.count, 10, "No synthetic pace during the 15-minute pause")
        XCTAssertTrue(samples.allSatisfy { abs($0.paceSeconds - 300) < 0.01 })
    }
}
