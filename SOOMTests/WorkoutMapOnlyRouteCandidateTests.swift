import XCTest
@testable import SOOM

final class WorkoutMapOnlyRouteCandidateTests: XCTestCase {
    private func fixture() -> (WorkoutRoute, WorkoutRoute, [WorkoutRouteCoordinate], Set<WorkoutMapOnlyRouteCandidate.Gap>) {
        let ownerWorkout = UUID(), start = Date(timeIntervalSinceReferenceDate: 100)
        let raw = [0, 1, 2, 4, 5].enumerated().map { index, tick in
            WorkoutRouteCoordinate(latitude: 0, longitude: Double(tick) * 0.003,
                altitude: Double(tick), timestamp: start.addingTimeInterval(Double(tick) * 10),
                segmentIndex: index == 0 ? 0 : (index < 3 ? 1 : 2))
        }
        let donor = WorkoutRouteCoordinate(latitude: 0, longitude: 0.009, altitude: 3,
            timestamp: start.addingTimeInterval(30), segmentIndex: 1)
        let merged = (raw + [donor]).sorted { $0.timestamp! < $1.timestamp! }.map {
            WorkoutRouteCoordinate(id: $0.id, latitude: $0.latitude, longitude: $0.longitude,
                altitude: $0.altitude, timestamp: $0.timestamp, segmentIndex: $0.id == raw[0].id ? 0 : 1)
        }
        let original = WorkoutRoute(workoutId: ownerWorkout, source: .soomLocal,
            coordinates: raw, totalDistanceMeters: 999, totalElevationGain: 10, createdAt: start)
        let display = WorkoutRoute(workoutId: ownerWorkout, source: .soomLocal,
            coordinates: merged, totalDistanceMeters: 1234, totalElevationGain: 20, createdAt: start)
        return (original, display, [donor], [.init(before: raw[2].id, after: raw[3].id)])
    }
    func testDerivedGeometryIsMapOnlyAndAnalysisRetainsExactOriginal() throws {
        let (raw, display, donor, gaps) = fixture()
        let candidate = try XCTUnwrap(WorkoutMapOnlyRouteCandidate(original: raw, display: display, sourceInsertions: donor, joinedGaps: gaps))
        XCTAssertEqual(candidate.analysisGeometry(for: raw), raw)
        XCTAssertEqual(candidate.analysisGeometry(for: raw)?.totalDistanceMeters, 999)
        XCTAssertEqual(candidate.analysisGeometry(for: raw)?.totalElevationGain, 10)
        XCTAssertEqual(candidate.mapGeometry(for: raw), display)
        XCTAssertEqual(raw.coordinateSegments.count, 3)
        XCTAssertEqual(display.coordinateSegments.count, 2, "Only the selected middle gap is joined; first break remains")
        XCTAssertEqual(RoutePrivacyMasker().mask(route: candidate.mapGeometry(for: raw)!).privacyMaskRadiusMeters, 50)
    }
    func testMissingSourcePointsAndUnapprovedJoinsFailClosed() {
        let (raw, display, donor, gaps) = fixture()
        XCTAssertNil(WorkoutMapOnlyRouteCandidate(original: raw, display: display, sourceInsertions: [], joinedGaps: gaps))
        XCTAssertNil(WorkoutMapOnlyRouteCandidate(original: raw, display: display, sourceInsertions: donor, joinedGaps: []))
        let wrongGap: Set<WorkoutMapOnlyRouteCandidate.Gap> = [.init(before: raw.coordinates[0].id, after: raw.coordinates[1].id)]
        XCTAssertNil(WorkoutMapOnlyRouteCandidate(original: raw, display: display, sourceInsertions: donor, joinedGaps: wrongGap))
        let shared = RoutePrivacyMasker().mask(route: raw, policy: .init(distanceMeters: 200))
        XCTAssertNil(WorkoutMapOnlyRouteCandidate(original: shared, display: display, sourceInsertions: donor, joinedGaps: gaps))
    }
    func testChangedSourceCannotReuseCandidate() throws {
        let (raw, display, donor, gaps) = fixture()
        let candidate = try XCTUnwrap(WorkoutMapOnlyRouteCandidate(original: raw, display: display, sourceInsertions: donor, joinedGaps: gaps))
        let newer = WorkoutRoute(workoutId: raw.workoutId, source: raw.source, coordinates: raw.coordinates,
            totalDistanceMeters: 1000)
        XCTAssertEqual(candidate.mapGeometry(for: newer), newer)
        XCTAssertEqual(candidate.analysisGeometry(for: newer), newer)
        XCTAssertNil(candidate.mapGeometry(for: nil))
    }
}
