import XCTest
@testable import SOOM

final class ClimbInsightBuilderTests: XCTestCase {
    private let builder = ClimbInsightBuilder()

    func testSteadyClimbBuildsStableInsight() {
        let input = makeInput(
            type: .cycling,
            durationMinutes: 95,
            distanceKm: 24,
            averageSpeedKmh: 24,
            elevationGainMeters: 420
        )

        let insight = builder.build(current: input)

        XCTAssertEqual(insight.climbType, .steadyClimb)
        XCTAssertEqual(insight.trend, .stable)
        XCTAssertTrue(insight.metricRows.contains { $0.title == "상승고도" && $0.valueText == "420m" })
        XCTAssertTrue(insight.isVisible)
    }

    func testRollingTerrainBuildsRollingInsight() {
        let input = makeInput(
            type: .cycling,
            durationMinutes: 80,
            distanceKm: 60,
            averageSpeedKmh: 28,
            elevationGainMeters: 210
        )

        let insight = builder.build(current: input)

        XCTAssertEqual(insight.climbType, .rollingTerrain)
        XCTAssertEqual(insight.trend, .stable)
        XCTAssertTrue(insight.summary.contains("오르내림"))
    }

    func testElevationFatigueHeuristicUsesGentleRhythmTone() {
        let input = makeInput(
            type: .cycling,
            durationMinutes: 180,
            distanceKm: 42,
            averageSpeedKmh: 14.5,
            elevationGainMeters: 720
        )

        let insight = builder.build(current: input)

        XCTAssertEqual(insight.climbType, .elevationFatigue)
        XCTAssertEqual(insight.trend, .lighter)
        assertNoNegativeTone(in: insight)
    }

    func testStrongFinishUsesSplitSpeedStability() {
        let input = makeInput(
            type: .cycling,
            durationMinutes: 120,
            distanceKm: 45,
            averageSpeedKmh: 24,
            elevationGainMeters: 500
        )
        let metrics = [
            makeSplitMetric(index: 0, speed: 20),
            makeSplitMetric(index: 1, speed: 19.8)
        ]

        let insight = builder.build(current: input, splitMetrics: metrics)

        XCTAssertEqual(insight.climbType, .strongFinish)
        XCTAssertEqual(insight.trend, .improving)
        XCTAssertTrue(insight.metricRows.contains { $0.title == "후반 속도 유지" })
    }

    func testHikingClimbUsesElevationAndPaceFlow() {
        let input = makeInput(
            type: .hiking,
            durationMinutes: 160,
            distanceKm: 8,
            averageSpeedKmh: nil,
            elevationGainMeters: 520
        )

        let insight = builder.build(current: input)

        XCTAssertNotEqual(insight.climbType, .insufficientData)
        XCTAssertTrue(insight.metricRows.contains { $0.title == "평균 경사" })
    }

    func testFlatRouteIsHiddenAsInsufficientData() {
        let input = makeInput(
            type: .cycling,
            durationMinutes: 60,
            distanceKm: 30,
            averageSpeedKmh: 30,
            elevationGainMeters: 35
        )

        let insight = builder.build(current: input)

        XCTAssertEqual(insight.climbType, .insufficientData)
        XCTAssertFalse(insight.isVisible)
    }

    func testRouteElevationOverridesInputElevation() {
        let id = UUID()
        let input = makeInput(
            id: id,
            type: .cycling,
            durationMinutes: 70,
            distanceKm: 30,
            averageSpeedKmh: 25,
            elevationGainMeters: 20
        )
        let route = WorkoutRoute(
            workoutId: id,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.0, longitude: 127.0),
                WorkoutRouteCoordinate(latitude: 37.1, longitude: 127.1)
            ],
            totalDistanceMeters: 30_000,
            totalElevationGain: 360
        )

        let insight = builder.build(current: input, route: route)

        XCTAssertEqual(insight.climbType, .steadyClimb)
        XCTAssertTrue(insight.metricRows.contains { $0.valueText == "360m" })
    }

    func testBuilderDoesNotUseRecoveryCalculator() {
        let input = makeInput(
            type: .cycling,
            durationMinutes: 90,
            distanceKm: 30,
            averageSpeedKmh: 24,
            elevationGainMeters: 350
        )

        let insight = builder.build(current: input)

        XCTAssertNotEqual(insight.climbType, .insufficientData)
    }

    private func makeInput(
        id: UUID = UUID(),
        type: UnifiedWorkoutType,
        durationMinutes: Int,
        distanceKm: Double?,
        averageSpeedKmh: Double?,
        elevationGainMeters: Double?
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: id,
            source: .appleHealthKit,
            workoutType: type,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            averagePaceText: nil,
            averageSpeedKmh: averageSpeedKmh,
            averageHeartRate: nil,
            elevationGainMeters: elevationGainMeters,
            activeEnergyKcal: nil
        )
    }

    private func makeSplitMetric(index: Int, speed: Double? = nil, cadence: Double? = nil) -> WorkoutSplitMetric {
        let start = Date(timeIntervalSince1970: 1_800_000_000 + Double(index * 1_800))
        return WorkoutSplitMetric(
            splitIndex: index,
            startTime: start,
            endTime: start.addingTimeInterval(1_800),
            averageSpeed: speed,
            averageCadence: cadence
        )
    }

    private func assertNoNegativeTone(in insight: ClimbInsight) {
        let text = ([insight.title, insight.summary] + insight.metricRows.flatMap { [$0.title, $0.valueText, $0.detailText] }).joined(separator: " ")
        ["못", "실패", "나쁨", "잘못", "위험", "무너"].forEach { word in
            XCTAssertFalse(text.contains(word), "Unexpected negative tone: \(word)")
        }
    }
}
