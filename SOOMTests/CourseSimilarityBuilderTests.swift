import XCTest
@testable import SOOM

final class CourseSimilarityBuilderTests: XCTestCase {
    private let builder = CourseSimilarityBuilder()

    func testSimilarRouteBuildsCourseCandidate() {
        let current = route(
            id: UUID(),
            distance: 10_000,
            coordinates: [
                coordinate(37.5000, 127.0000),
                coordinate(37.5100, 127.0100),
                coordinate(37.5200, 127.0200)
            ]
        )
        let candidate = route(
            id: UUID(),
            distance: 10_600,
            coordinates: [
                coordinate(37.5005, 127.0005),
                coordinate(37.5105, 127.0105),
                coordinate(37.5205, 127.0205)
            ]
        )

        let result = builder.compare(current: current, candidate: candidate)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.reason, .similarRoute)
        XCTAssertGreaterThanOrEqual(result?.similarityScore ?? 0, 0.72)
    }

    func testTooDifferentRouteIsExcluded() {
        let current = route(
            id: UUID(),
            distance: 10_000,
            coordinates: [
                coordinate(37.5000, 127.0000),
                coordinate(37.5200, 127.0200)
            ]
        )
        let candidate = route(
            id: UUID(),
            distance: 16_000,
            coordinates: [
                coordinate(35.1000, 129.0000),
                coordinate(35.2000, 129.1000)
            ]
        )

        XCTAssertNil(builder.compare(current: current, candidate: candidate))
    }

    func testSameWorkoutIsExcluded() {
        let id = UUID()
        let current = route(id: id, distance: 10_000, coordinates: [coordinate(37.5, 127.0), coordinate(37.6, 127.1)])
        let candidate = route(id: id, distance: 10_000, coordinates: [coordinate(37.5, 127.0), coordinate(37.6, 127.1)])

        XCTAssertNil(builder.compare(current: current, candidate: candidate))
    }


    func testReverseDirectionRouteBuildsCourseCandidate() {
        let currentCoordinates = [
            coordinate(37.5000, 127.0000),
            coordinate(37.5100, 127.0100),
            coordinate(37.5200, 127.0200)
        ]
        let candidateCoordinates = Array(currentCoordinates.reversed())
        let current = route(id: UUID(), distance: 10_000, coordinates: currentCoordinates)
        let candidate = route(id: UUID(), distance: 10_100, coordinates: candidateCoordinates)

        let result = builder.compare(current: current, candidate: candidate)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.reason, .similarRoute)
        XCTAssertEqual(result?.isReverseDirection, true)
        XCTAssertEqual(result?.confidenceLevel, .high)
    }

    func testSimilarDistanceInDifferentAreaIsExcluded() {
        let current = route(
            id: UUID(),
            distance: 10_000,
            coordinates: [
                coordinate(37.5000, 127.0000),
                coordinate(37.5200, 127.0200)
            ]
        )
        let candidate = route(
            id: UUID(),
            distance: 10_100,
            coordinates: [
                coordinate(35.5000, 129.0000),
                coordinate(35.5200, 129.0200)
            ]
        )

        XCTAssertNil(builder.compare(current: current, candidate: candidate))
    }

    private func route(
        id: UUID,
        distance: Double,
        coordinates: [WorkoutRouteCoordinate]
    ) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: id,
            source: .appleHealthKit,
            coordinates: coordinates,
            totalDistanceMeters: distance,
            totalElevationGain: nil,
            createdAt: Date()
        )
    }

    private func coordinate(_ latitude: Double, _ longitude: Double) -> WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(latitude: latitude, longitude: longitude)
    }
}
