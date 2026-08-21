import XCTest
@testable import SOOM

final class WorkoutChartDataBuilderTests: XCTestCase {
    private let metersPerLatitudeDegree = 111_320.0

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
            XCTAssertEqual(sample.paceSeconds, 300, accuracy: 1.0)
            XCTAssertNil(sample.heartRate)
        }

        let splits = WorkoutChartDataBuilder.splits(from: route)
        XCTAssertEqual(splits.count, 10)
        for (index, split) in splits.enumerated() {
            XCTAssertEqual(split.label, "\(index + 1) km")
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
            XCTAssertEqual(sample.value, 12.0, accuracy: 0.5)
        }
        XCTAssertEqual(samples.last?.distanceKilometers ?? 0, 10.0, accuracy: 0.3)
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
