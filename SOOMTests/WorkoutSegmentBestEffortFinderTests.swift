import XCTest
@testable import SOOM

final class WorkoutSegmentBestEffortFinderTests: XCTestCase {
    private let metersPerLatitudeDegree = 111_320.0

    func testFindsFasterSegmentWithinVariablePaceRoute() {
        // 20 minutes total: first 10 min at 200m/60s (12 km/h), last 10 min at
        // 400m/60s (24 km/h). The 1-minute best effort should land in the fast half.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var coordinates: [WorkoutRouteCoordinate] = [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: start)
        ]
        var cumulativeLatitudeOffset = 0.0

        for minute in 1...20 {
            let stepMeters = minute <= 10 ? 200.0 : 400.0
            cumulativeLatitudeOffset += stepMeters / metersPerLatitudeDegree
            coordinates.append(
                WorkoutRouteCoordinate(
                    latitude: 37.5 + cumulativeLatitudeOffset,
                    longitude: 127.0,
                    timestamp: start.addingTimeInterval(Double(minute) * 60)
                )
            )
        }

        let route = makeRoute(coordinates: coordinates)
        let efforts = WorkoutSegmentBestEffortFinder.bestEfforts(from: route)

        let oneMinuteEffort = efforts.first { $0.durationMinutes == 1 }
        XCTAssertNotNil(oneMinuteEffort)
        // ~400m/60s = ~6.67 m/s
        XCTAssertEqual(oneMinuteEffort?.averageMetersPerSecond ?? 0, 6.67, accuracy: 0.2)
    }

    func testConstantPaceRouteProducesConsistentEffortAcrossDurations() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var coordinates: [WorkoutRouteCoordinate] = []
        for minute in 0...15 {
            let latitudeOffset = (Double(minute) * 200.0) / metersPerLatitudeDegree
            coordinates.append(
                WorkoutRouteCoordinate(
                    latitude: 37.5 + latitudeOffset,
                    longitude: 127.0,
                    timestamp: start.addingTimeInterval(Double(minute) * 60)
                )
            )
        }

        let route = makeRoute(coordinates: coordinates)
        let efforts = WorkoutSegmentBestEffortFinder.bestEfforts(from: route)

        // 200m/60s ≈ 3.33 m/s constant pace — every duration should find ~the same speed.
        for effort in efforts {
            XCTAssertEqual(effort.averageMetersPerSecond, 3.33, accuracy: 0.1)
        }
        XCTAssertEqual(efforts.map(\.durationMinutes).sorted(), [1, 5, 10])
    }

    func testTooShortRouteReturnsNoEffortsForLongerDurations() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let coordinates = [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: start),
            WorkoutRouteCoordinate(latitude: 37.502, longitude: 127.0, timestamp: start.addingTimeInterval(90))
        ]

        let route = makeRoute(coordinates: coordinates)
        let efforts = WorkoutSegmentBestEffortFinder.bestEfforts(from: route)

        // Only 90 seconds total — no 5 or 10 minute window is possible.
        XCTAssertTrue(efforts.allSatisfy { $0.durationMinutes == 1 })
    }

    func testEmptyOrSinglePointRouteReturnsNoEfforts() {
        XCTAssertTrue(WorkoutSegmentBestEffortFinder.bestEfforts(from: makeRoute(coordinates: [])).isEmpty)
        XCTAssertTrue(
            WorkoutSegmentBestEffortFinder.bestEfforts(
                from: makeRoute(coordinates: [WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: Date())])
            ).isEmpty
        )
    }

    func testPointsWithoutTimestampsAreIgnored() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let coordinates = [
            WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0, timestamp: start),
            WorkoutRouteCoordinate(latitude: 37.501, longitude: 127.0, timestamp: nil),
            WorkoutRouteCoordinate(latitude: 37.502, longitude: 127.0, timestamp: start.addingTimeInterval(60))
        ]

        let route = makeRoute(coordinates: coordinates)
        let efforts = WorkoutSegmentBestEffortFinder.bestEfforts(from: route)

        XCTAssertEqual(efforts.count, 1)
        XCTAssertEqual(efforts.first?.durationMinutes, 1)
    }

    private func makeRoute(coordinates: [WorkoutRouteCoordinate]) -> WorkoutRoute {
        WorkoutRoute(workoutId: UUID(), source: .soomLocal, coordinates: coordinates, totalDistanceMeters: 0, createdAt: Date())
    }
}
