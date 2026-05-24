import XCTest
@testable import SOOM

final class RouteSimilarityBuilderTests: XCTestCase {
    private let builder = RouteSimilarityBuilder()

    func testSimilarDistanceCandidateWithoutGeometryIsReturned() {
        let current = makeRoute(distance: 10_000, coordinates: [])
        let candidate = makeRoute(distance: 10_800, coordinates: [])

        let candidates = builder.findCandidates(current: current, candidates: [candidate])

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.reason, .similarDistance)
        XCTAssertGreaterThanOrEqual(candidates.first?.similarityScore ?? 0, 0.65)
    }

    func testSimilarRouteCandidateUsesBoundsAndEndpoints() {
        let current = makeRoute(distance: 10_000, coordinates: [
            coordinate(37.5000, 127.0000),
            coordinate(37.5050, 127.0060)
        ])
        let candidate = makeRoute(distance: 9_700, coordinates: [
            coordinate(37.5005, 127.0004),
            coordinate(37.5055, 127.0064)
        ])

        let result = builder.compare(current, candidate)

        XCTAssertEqual(result?.reason, .similarRoute)
        XCTAssertGreaterThan(result?.similarityScore ?? 0, 0.8)
        XCTAssertEqual(result?.matchedDistanceMeters, 9_700)
    }

    func testRouteTooDifferentIsExcluded() {
        let current = makeRoute(distance: 10_000, coordinates: [
            coordinate(37.5000, 127.0000),
            coordinate(37.5050, 127.0060)
        ])
        let candidate = makeRoute(distance: 10_200, coordinates: [
            coordinate(35.1000, 129.0000),
            coordinate(35.1100, 129.0200)
        ])

        XCTAssertNil(builder.compare(current, candidate))
    }

    func testDistanceOutsideToleranceIsExcluded() {
        let current = makeRoute(distance: 10_000, coordinates: [])
        let candidate = makeRoute(distance: 12_000, coordinates: [])

        XCTAssertNil(builder.compare(current, candidate))
    }

    private func makeRoute(
        id: UUID = UUID(),
        distance: Double,
        coordinates: [WorkoutRouteCoordinate]
    ) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: id,
            source: .appleHealthKit,
            coordinates: coordinates,
            totalDistanceMeters: distance,
            createdAt: Date()
        )
    }

    private func coordinate(_ latitude: Double, _ longitude: Double) -> WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(latitude: latitude, longitude: longitude)
    }
}
