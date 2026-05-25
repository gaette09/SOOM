import XCTest
@testable import SOOM

final class WorkoutRouteMapperTests: XCTestCase {
    private let mapper = WorkoutRouteMapper()

    func testCoordinateEncodeDecodePreservesRouteData() {
        let route = makeRoute()

        let record = mapper.makeRecord(from: route, updatedAt: Date(timeIntervalSince1970: 2_000))
        let decodedRoute = mapper.makeRoute(from: record)

        XCTAssertEqual(decodedRoute.id, route.id)
        XCTAssertEqual(decodedRoute.workoutId, route.workoutId)
        XCTAssertEqual(decodedRoute.source, .appleHealthKit)
        XCTAssertEqual(decodedRoute.coordinates, route.coordinates)
        XCTAssertEqual(decodedRoute.totalDistanceMeters, route.totalDistanceMeters)
        XCTAssertEqual(decodedRoute.totalElevationGain, route.totalElevationGain)
        XCTAssertNotNil(record.courseIdentity)
    }

    func testEmptyRouteRoundTripsSafely() {
        let route = WorkoutRoute(
            workoutId: UUID(),
            source: .soomLocal,
            coordinates: [],
            totalDistanceMeters: 0,
            totalElevationGain: nil,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let record = mapper.makeRecord(from: route)
        let decodedRoute = mapper.makeRoute(from: record)

        XCTAssertEqual(record.coordinateCount, 0)
        XCTAssertTrue(decodedRoute.coordinates.isEmpty)
        XCTAssertNil(decodedRoute.bounds)
        XCTAssertNil(record.courseIdentity)
    }

    func testUnknownSourceFallsBackSafely() {
        let record = PersistedWorkoutRoute(
            workoutId: UUID(),
            sourceRaw: "future-device",
            totalDistanceMeters: 1_000
        )

        let route = mapper.makeRoute(from: record)

        XCTAssertEqual(route.source, .unknown)
    }

    func testUpdateOverwritesExistingRecord() {
        let record = mapper.makeRecord(from: makeRoute(distance: 1_000))
        let updatedRoute = makeRoute(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            workoutId: record.workoutId,
            source: .garmin,
            distance: 2_200
        )

        mapper.update(record, with: updatedRoute, updatedAt: Date(timeIntervalSince1970: 5_000))

        XCTAssertEqual(record.id, updatedRoute.id)
        XCTAssertEqual(record.sourceRaw, UnifiedDataSource.garmin.rawValue)
        XCTAssertEqual(record.totalDistanceMeters, 2_200)
        XCTAssertEqual(record.coordinateCount, updatedRoute.coordinates.count)
    }

    private func makeRoute(
        id: UUID = UUID(),
        workoutId: UUID = UUID(),
        source: UnifiedDataSource = .appleHealthKit,
        distance: Double = 1_250
    ) -> WorkoutRoute {
        WorkoutRoute(
            id: id,
            workoutId: workoutId,
            source: source,
            coordinates: [
                WorkoutRouteCoordinate(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    latitude: 37.500,
                    longitude: 127.000,
                    altitude: 20,
                    timestamp: Date(timeIntervalSince1970: 1_000)
                ),
                WorkoutRouteCoordinate(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    latitude: 37.505,
                    longitude: 127.005,
                    altitude: 36,
                    timestamp: Date(timeIntervalSince1970: 1_300)
                )
            ],
            totalDistanceMeters: distance,
            totalElevationGain: 16,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
