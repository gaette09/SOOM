import XCTest
@testable import SOOM

final class WorkoutGrowthMetricsBuilderTests: XCTestCase {
    private let builder = WorkoutGrowthMetricsBuilder()

    func testDistanceImprovementBuildsImprovedMetric() {
        let current = makeInput(distance: 12, duration: 60, speed: 12)
        let recent = [
            makeInput(daysAgo: 7, distance: 8, duration: 52, speed: 9.2),
            makeInput(daysAgo: 5, distance: 9, duration: 54, speed: 10)
        ]

        let metrics = builder.build(current: current, recent: recent)
        let distance = metric(.distance, in: metrics)

        XCTAssertEqual(distance?.trend, .improved)
        XCTAssertTrue(distance?.comparisonText.contains("최근 평균보다") == true)
    }

    func testSpeedImprovementBuildsImprovedMetric() {
        let current = makeInput(type: .cycling, distance: 32, duration: 70, speed: 27.4)
        let recent = [
            makeInput(type: .cycling, daysAgo: 7, distance: 24, duration: 62, speed: 23),
            makeInput(type: .cycling, daysAgo: 4, distance: 25, duration: 64, speed: 23.4)
        ]

        let metrics = builder.build(current: current, recent: recent)
        let speed = metric(.speed, in: metrics)

        XCTAssertEqual(speed?.trend, .improved)
        XCTAssertTrue(speed?.valueText.contains("km/h") == true)
    }

    func testPaceImprovementBuildsImprovedMetricForRunning() {
        let current = makeInput(type: .running, distance: 10, duration: 48, speed: nil)
        let recent = [
            makeInput(type: .running, daysAgo: 8, distance: 10, duration: 55, speed: nil),
            makeInput(type: .running, daysAgo: 5, distance: 8, duration: 45, speed: nil)
        ]

        let metrics = builder.build(current: current, recent: recent)
        let pace = metric(.pace, in: metrics)

        XCTAssertEqual(pace?.trend, .improved)
        XCTAssertTrue(pace?.valueText.contains("/km") == true)
    }

    func testInsufficientDataReturnsSafeBaselineMetrics() {
        let current = makeInput(distance: 6, duration: 34, speed: 10.6)

        let metrics = builder.build(current: current, recent: [])

        XCTAssertEqual(metrics.count, 3)
        XCTAssertTrue(metrics.allSatisfy { $0.trend == .insufficientData })
    }

    func testHeartRateEfficiencyIsIncludedOnlyWhenHeartRateExists() {
        let current = makeInput(distance: 20, duration: 60, speed: 20, heartRate: 132)
        let recent = [
            makeInput(daysAgo: 7, distance: 16, duration: 60, speed: 16, heartRate: 140),
            makeInput(daysAgo: 5, distance: 18, duration: 64, speed: 17, heartRate: 138)
        ]

        let metrics = builder.build(current: current, recent: recent)

        XCTAssertNotNil(metric(.heartRateEfficiency, in: metrics))
    }

    func testCopyAvoidsNegativeEvaluationWords() {
        let current = makeInput(distance: 4, duration: 50, speed: 4.8)
        let recent = [
            makeInput(daysAgo: 3, distance: 12, duration: 60, speed: 12),
            makeInput(daysAgo: 5, distance: 10, duration: 55, speed: 11)
        ]

        let metrics = builder.build(current: current, recent: recent)
        let copy = metrics.map(\.comparisonText).joined(separator: " ")

        XCTAssertFalse(copy.contains("못"))
        XCTAssertFalse(copy.contains("나쁨"))
        XCTAssertFalse(copy.contains("실패"))
    }

    private func metric(
        _ type: WorkoutGrowthMetricType,
        in metrics: [WorkoutGrowthMetric]
    ) -> WorkoutGrowthMetric? {
        metrics.first { $0.metricType == type }
    }

    private func makeInput(
        type: UnifiedWorkoutType = .cycling,
        daysAgo: Int = 0,
        distance: Double,
        duration: Int,
        speed: Double?,
        heartRate: Double? = nil
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .appleHealthKit,
            workoutType: type,
            startDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date(),
            durationMinutes: duration,
            distanceKm: distance,
            averagePaceText: nil,
            averageSpeedKmh: speed,
            averageHeartRate: heartRate,
            elevationGainMeters: 80,
            activeEnergyKcal: 420
        )
    }
}
