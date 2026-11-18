import XCTest
@testable import SOOM

final class RoutePrivacyMaskerTests: XCTestCase {
    private let masker = RoutePrivacyMasker()

    func testStartMaskingRemovesCoordinatesNearStart() {
        let masked = masker.mask(
            route: sampleRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .startOnly, distanceMeters: 200)
        )

        XCTAssertEqual(masked.coordinates.first?.latitude, coordinate(atMeters: 300).latitude)
        XCTAssertEqual(masked.coordinates.count, 3)
    }

    func testEndMaskingRemovesCoordinatesNearEnd() {
        let masked = masker.mask(
            route: sampleRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .endOnly, distanceMeters: 200)
        )

        XCTAssertEqual(masked.coordinates.last?.latitude, coordinate(atMeters: 590).latitude)
        XCTAssertEqual(masked.coordinates.count, 4)
    }

    func testStartAndEndMaskingRemovesBothEnds() {
        let masked = masker.mask(
            route: sampleRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .startAndEnd, distanceMeters: 200)
        )

        XCTAssertEqual(masked.coordinates.map(\.latitude), [
            coordinate(atMeters: 300).latitude,
            coordinate(atMeters: 590).latitude
        ])
    }

    func testNonePolicyReturnsSameCoordinates() {
        let route = sampleRoute

        let masked = masker.mask(route: route, policy: .none)

        XCTAssertEqual(masked.coordinates, route.coordinates)
        XCTAssertEqual(masked.bounds, route.bounds)
    }

    func testShortRouteFallsBackToEmptyDerivedRoute() {
        let masked = masker.mask(
            route: shortRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .startAndEnd, distanceMeters: 200)
        )

        XCTAssertTrue(masked.coordinates.isEmpty)
        XCTAssertNil(masked.bounds)
        XCTAssertEqual(masked.totalDistanceMeters, 0)
    }

    func testOriginalRouteIsNotMutated() {
        let route = sampleRoute
        let originalCoordinates = route.coordinates

        _ = masker.mask(
            route: route,
            policy: RoutePrivacyMaskingPolicy(mode: .startAndEnd, distanceMeters: 200)
        )

        XCTAssertEqual(route.coordinates, originalCoordinates)
    }

    func testMaskedRouteBoundsAreRecalculated() {
        let masked = masker.mask(
            route: sampleRoute,
            policy: RoutePrivacyMaskingPolicy(mode: .startAndEnd, distanceMeters: 200)
        )

        XCTAssertEqual(masked.bounds?.minLatitude, coordinate(atMeters: 300).latitude)
        XCTAssertEqual(masked.bounds?.maxLatitude, coordinate(atMeters: 590).latitude)
    }

    func testLoopReentryAndCrossingEdgesCannotRevealEndpointFence() {
        let points = [coordinate(atMeters: 0), coordinate(atMeters: 300), coordinate(atMeters: 500),
                      coordinate(atMeters: 50), coordinate(atMeters: -300), coordinate(atMeters: -500),
                      coordinate(atMeters: 300), coordinate(atMeters: 500), coordinate(atMeters: 800)]
        let route = WorkoutRoute(workoutId: UUID(), source: .soomLocal, coordinates: points, totalDistanceMeters: 3000)
        let masked = masker.mask(route: route)
        XCTAssertFalse(masked.coordinates.contains { $0.latitude == points[3].latitude })
        XCTAssertGreaterThan(masked.coordinateSegments.count, 1)
        for pair in zip(masked.coordinates, masked.coordinates.dropFirst()) where pair.0.segmentIndex == pair.1.segmentIndex {
            XCTAssertFalse(pair.0.latitude < 37 && pair.1.latitude > 37 || pair.0.latitude > 37 && pair.1.latitude < 37)
        }
        XCTAssertEqual(route.coordinates, points)
    }
    func testRepeatedRenderingDoesNotTrimMaskedRouteAgain() {
        let once = masker.mask(route: sampleRoute)
        XCTAssertTrue(once.privacyMaskApplied)
        XCTAssertEqual(masker.mask(route: once), once)
        XCTAssertEqual(WorkoutMapSheetRouteContext.route(for: displayWorkout, override: once), once)
    }
    func testSinglePointIsHiddenAndEmptyMaskedOverrideCannotRestoreRawGeometry() {
        let raw = WorkoutRoute(workoutId: UUID(), source: .soomLocal,
            coordinates: [coordinate(atMeters: 0)], totalDistanceMeters: 0)
        let masked = masker.mask(route: raw)
        XCTAssertTrue(masked.coordinates.isEmpty)
        let result = WorkoutMapSheetRouteContext.route(for: displayWorkout, override: masked)
        XCTAssertEqual(result, masked)
    }

    func testContinuousLoopReentriesSplitIntoThreePartsBeforeRendering() throws {
        let offsets: [(Double, Double)] = [(0,0),(300,0),(500,0),(500,300),(300,300),(50,0),
            (-300,0),(-500,0),(-500,-300),(-300,-300),(0,0),(0,300),(0,500),(300,500),(300,300),(0,0)]
        let coordinates = offsets.map { x, y in
            WorkoutRouteCoordinate(latitude: 37 + y / 111_195,
                longitude: 127 + x / (111_195 * cos(37 * .pi / 180)))
        }
        let route = WorkoutRoute(workoutId: UUID(), source: .soomLocal, coordinates: coordinates, totalDistanceMeters: 4000)
        let masked = masker.mask(route: route)
        XCTAssertEqual(route.coordinateSegments.count, 1)
        XCTAssertEqual(masked.coordinateSegments.map(\.count), [4,4,4])
        XCTAssertTrue(masked.privacyMaskApplied)
        XCTAssertEqual(route.coordinates, coordinates)
        let interrupted = WorkoutRoute(workoutId: UUID(), source: .soomLocal,
            coordinates: coordinates.enumerated().map { index, point in
                WorkoutRouteCoordinate(id: point.id, latitude: point.latitude, longitude: point.longitude,
                    segmentIndex: index < 5 ? 0 : (index < 10 ? 1 : 2))
            }, totalDistanceMeters: 4000)
        XCTAssertEqual(interrupted.coordinateSegments.count, 3)
        XCTAssertFalse(interrupted.privacyMaskApplied)
        let data: [String: Any] = ["synthetic": true, "radiusMeters": 50,
            "raw": offsets.map { [$0.0,$0.1] },
            "masked": masked.coordinateSegments.map { segment in segment.map {
                [($0.longitude - 127) * 111_195 * cos(37 * .pi / 180), ($0.latitude - 37) * 111_195]
            } },
            "gpsSegments": interrupted.coordinateSegments.map { segment in segment.map {
                [($0.longitude - 127) * 111_195 * cos(37 * .pi / 180), ($0.latitude - 37) * 111_195]
            } }]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "Synthetic route gap causes - no tester coordinates"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test50mDisplayAnd200mSharedContractStaySeparate() {
        XCTAssertEqual(RoutePrivacyMaskingPolicy.defaultDisplay.distanceMeters, 50)
        XCTAssertEqual(RoutePrivacyMaskingPolicy.defaultShare.distanceMeters, 200)
        let raw = route([0, 120, 160, 240, 300, 600, 760, 840, 880, 1000])
        let displayed = masker.mask(route: raw)
        let shared = masker.mask(route: raw, policy: .defaultShare)
        XCTAssertEqual(displayed.coordinates.first?.id, raw.coordinates[1].id)
        XCTAssertEqual(displayed.coordinates.last?.id, raw.coordinates[8].id)
        XCTAssertEqual(shared.coordinates.first?.id, raw.coordinates[3].id)
        XCTAssertEqual(shared.coordinates.last?.id, raw.coordinates[6].id)
        XCTAssertEqual(displayed.privacyMaskRadiusMeters, 50)
        XCTAssertEqual(masker.mask(route: displayed), displayed)
        XCTAssertEqual(masker.mask(route: shared), shared) // Never recover previously hidden coordinates.
    }

    func testShortAndOverlappingEndpointFencesHideEverything() {
        XCTAssertTrue(masker.mask(route: route([0, 20, 40, 60, 90])).coordinates.isEmpty)
        XCTAssertTrue(masker.mask(route: route([0, 20, 40, 60, 20])).coordinates.isEmpty)
    }

    func testReentryBetween100And200mIsVisibleButInside100StillSplits() {
        let raw = route([0, 300, 400, 160, 140, 300, 400, 40, -300, -400, -600])
        let current = masker.mask(route: raw)
        let prior = masker.mask(route: raw, policy: .defaultShare)
        XCTAssertTrue(current.coordinates.contains { $0.id == raw.coordinates[3].id })
        XCTAssertFalse(prior.coordinates.contains { $0.id == raw.coordinates[3].id })
        XCTAssertFalse(current.coordinates.contains { $0.id == raw.coordinates[7].id })
        XCTAssertGreaterThan(current.coordinateSegments.count, 1)
    }

    func testMultiSegmentInvalidPointAndLargeGapAreNeverBridged() {
        let points = [coordinate(atMeters: 0), coordinate(atMeters: 300), coordinate(atMeters: 400),
                      WorkoutRouteCoordinate(latitude: .nan, longitude: 127),
                      coordinate(atMeters: 500), coordinate(atMeters: 600),
                      coordinate(atMeters: 2000), coordinate(atMeters: 2100),
                      WorkoutRouteCoordinate(latitude: coordinate(atMeters: 2200).latitude, longitude: 127, segmentIndex: 4),
                      WorkoutRouteCoordinate(latitude: coordinate(atMeters: 2300).latitude, longitude: 127, segmentIndex: 4),
                      coordinate(atMeters: 2600)]
        let raw = WorkoutRoute(workoutId: UUID(), source: .soomLocal, coordinates: points, totalDistanceMeters: 2600)
        let masked = masker.mask(route: raw)
        XCTAssertEqual(masked.coordinateSegments.map(\.count), [2, 2, 2, 2])
        XCTAssertEqual(masked.coordinates.count, 8)
        XCTAssertEqual(raw.coordinates.count, 11)
    }

    func test50mSyntheticGeometryForVisualInspection() throws {
        let fixtures: [(String, [Double])] = [
            ("straight", [0,120,160,240,300,600,760,840,880,1000]),
            ("short", [0,40,80,120,160]),
            ("out-and-back", [0,120,240,400,500,400,240,120,0]),
            ("middle-reentry", [0,300,400,160,140,300,400,40,-300,-400,-600])]
        let rows: [[String: Any]] = fixtures.map { name, meters in
            let raw = route(meters)
            func points(_ value: WorkoutRoute) -> [[[Double]]] {
                value.coordinateSegments.map { $0.map { [0, ($0.latitude - 37) * 111_000] } }
            }
            return ["name": name, "raw": points(raw), "radius50": points(masker.mask(route: raw)),
                    "radius200": points(masker.mask(route: raw, policy: .defaultShare))]
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "50m synthetic route comparison"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func route(_ meters: [Double]) -> WorkoutRoute {
        WorkoutRoute(workoutId: UUID(), source: .soomLocal, coordinates: meters.map(coordinate), totalDistanceMeters: 5000)
    }

    private var displayWorkout: Workout {
        Workout(id: UUID(), sport: .run, title: "Synthetic", date: Date(), distanceMeters: 800,
            duration: 100, activeCalories: 0, avgHeartRate: 0, maxHeartRate: 0, avgPower: nil,
            elevationGain: 0, cadence: nil, effort: 0, source: "", route: [], splits: [], samples: [],
            zones: [], achievements: [], aiSummary: "")
    }

    private var sampleRoute: WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            source: .appleHealthKit,
            coordinates: [
                coordinate(atMeters: 0),
                coordinate(atMeters: 100),
                coordinate(atMeters: 300),
                coordinate(atMeters: 590),
                coordinate(atMeters: 800)
            ],
            totalDistanceMeters: 800
        )
    }

    private var shortRoute: WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(),
            source: .appleHealthKit,
            coordinates: [
                coordinate(atMeters: 0),
                coordinate(atMeters: 100)
            ],
            totalDistanceMeters: 100
        )
    }

    private func coordinate(atMeters meters: Double) -> WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(
            latitude: 37.0 + meters / 111_000,
            longitude: 127.0
        )
    }
}
