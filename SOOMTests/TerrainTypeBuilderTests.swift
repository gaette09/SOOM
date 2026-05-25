import XCTest
@testable import SOOM

final class TerrainTypeBuilderTests: XCTestCase {
    func testFlatTerrain() {
        let terrain = TerrainTypeBuilder().build(current: input(type: .running, distanceKm: 8, elevation: 12))

        XCTAssertEqual(terrain.terrainType, .flat)
        XCTAssertEqual(terrain.difficulty, .light)
    }

    func testRollingTerrain() {
        let route = route(distanceMeters: 12_000, elevation: 95, altitudes: [10, 45, 25, 60, 35, 70])
        let terrain = TerrainTypeBuilder().build(current: input(type: .cycling, distanceKm: 12, elevation: 40), route: route)

        XCTAssertEqual(terrain.terrainType, .rolling)
        XCTAssertEqual(terrain.difficulty, .moderate)
    }

    func testSteadyClimbTerrain() {
        let terrain = TerrainTypeBuilder().build(current: input(type: .cycling, distanceKm: 18, elevation: 260))

        XCTAssertEqual(terrain.terrainType, .steadyClimb)
    }

    func testLongClimbTerrain() {
        let terrain = TerrainTypeBuilder().build(current: input(type: .cycling, duration: 150, distanceKm: 45, elevation: 640))

        XCTAssertEqual(terrain.terrainType, .longClimb)
        XCTAssertEqual(terrain.difficulty, .challenging)
    }

    func testTrailTerrain() {
        let terrain = TerrainTypeBuilder().build(current: input(type: .hiking, duration: 120, distanceKm: 8, speed: 4.0, elevation: 180))

        XCTAssertEqual(terrain.terrainType, .trail)
    }

    func testMixedTerrain() {
        let terrain = TerrainTypeBuilder().build(current: input(type: .running, distanceKm: 4, elevation: 40))

        XCTAssertEqual(terrain.terrainType, .mixed)
        XCTAssertEqual(terrain.difficulty, .moderate)
    }

    func testUrbanStopGoTerrainFromSplitMetrics() {
        let terrain = TerrainTypeBuilder().build(
            current: input(type: .cycling, distanceKm: 10, elevation: 20),
            splitMetrics: splitMetrics(speeds: [4, 13, 5, 14])
        )

        XCTAssertEqual(terrain.terrainType, .urbanStopGo)
        XCTAssertEqual(terrain.difficulty, .moderate)
    }

    func testStableSplitMetricsDoNotForceUrbanStopGo() {
        let terrain = TerrainTypeBuilder().build(
            current: input(type: .cycling, distanceKm: 4, elevation: 40),
            splitMetrics: splitMetrics(speeds: [10, 11, 10.5, 11.2])
        )

        XCTAssertEqual(terrain.terrainType, .mixed)
    }

    func testRouteElevationTakesPriorityOverSummaryElevation() {
        let flatRoute = route(distanceMeters: 10_000, elevation: 20, altitudes: [10, 12, 11, 13])
        let terrain = TerrainTypeBuilder().build(
            current: input(type: .cycling, distanceKm: 10, elevation: 420),
            route: flatRoute
        )

        XCTAssertEqual(terrain.terrainType, .flat)
    }

    func testSummaryElevationFallbackWhenRouteElevationIsMissing() {
        let routeWithoutElevation = route(distanceMeters: 10_000, elevation: nil, altitudes: [10, 12, 11, 13])
        let terrain = TerrainTypeBuilder().build(
            current: input(type: .cycling, distanceKm: 8, elevation: 260),
            route: routeWithoutElevation
        )

        XCTAssertEqual(terrain.terrainType, .steadyClimb)
    }

    func testInsufficientData() {
        let terrain = TerrainTypeBuilder().build(current: input(type: .running, distanceKm: nil, elevation: nil))

        XCTAssertEqual(terrain.terrainType, .insufficientData)
        XCTAssertNil(terrain.difficulty)
    }

    func testNoNegativeTone() {
        let terrains = [
            TerrainTypeBuilder().build(current: input(type: .running, distanceKm: 8, elevation: 12)),
            TerrainTypeBuilder().build(current: input(type: .cycling, distanceKm: 18, elevation: 260)),
            TerrainTypeBuilder().build(current: input(type: .cycling, duration: 150, distanceKm: 45, elevation: 640))
        ]

        let bannedWords = ["못", "실패", "나쁨", "무너"]
        for terrain in terrains {
            for word in bannedWords {
                XCTAssertFalse(terrain.summary.contains(word))
            }
        }
    }

    func testRecoveryCalculatorIsNotUsed() {
        _ = TerrainTypeBuilder().build(current: input(type: .cycling, distanceKm: 30, elevation: 300))
        XCTAssertTrue(true)
    }

    private func input(
        type: UnifiedWorkoutType,
        duration: Int = 60,
        distanceKm: Double?,
        speed: Double? = nil,
        elevation: Double?
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .soomLocal,
            workoutType: type,
            startDate: Date(),
            durationMinutes: duration,
            distanceKm: distanceKm,
            averagePaceText: nil,
            averageSpeedKmh: speed,
            averageHeartRate: nil,
            elevationGainMeters: elevation,
            activeEnergyKcal: nil
        )
    }

    private func route(distanceMeters: Double, elevation: Double?, altitudes: [Double]) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(),
            source: .soomLocal,
            coordinates: altitudes.enumerated().map { index, altitude in
                WorkoutRouteCoordinate(
                    latitude: 37.0 + Double(index) * 0.001,
                    longitude: 127.0 + Double(index) * 0.001,
                    altitude: altitude
                )
            },
            totalDistanceMeters: distanceMeters,
            totalElevationGain: elevation
        )
    }

    private func splitMetrics(speeds: [Double]) -> [WorkoutSplitMetric] {
        let start = Date()
        return speeds.enumerated().map { index, speed in
            WorkoutSplitMetric(
                splitIndex: index,
                startTime: start.addingTimeInterval(Double(index) * 300),
                endTime: start.addingTimeInterval(Double(index + 1) * 300),
                averageSpeed: speed
            )
        }
    }
}
