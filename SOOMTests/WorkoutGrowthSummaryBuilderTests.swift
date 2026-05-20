import XCTest
@testable import SOOM

final class WorkoutGrowthSummaryBuilderTests: XCTestCase {
    private let builder = WorkoutGrowthSummaryBuilder()

    func testDistanceIncreaseBuildsEnduranceSummary() {
        let previous = makeWorkout(daysAgo: 2, distanceMeters: 10_000, duration: 3_200)
        let current = makeWorkout(daysAgo: 0, distanceMeters: 12_000, duration: 3_600)

        let summary = builder.build(current: current, recentWorkouts: [current, previous])

        XCTAssertEqual(summary.improvementType, .endurance)
        XCTAssertFalse(summary.comparisonText.isEmpty)
        XCTAssertFalse(summary.motivationText.isEmpty)
    }

    func testPaceImprovementBuildsPaceSummary() {
        let previous = makeWorkout(daysAgo: 2, distanceMeters: 10_000, duration: 3_000)
        let current = makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 2_850)

        let summary = builder.build(current: current, recentWorkouts: [current, previous])

        XCTAssertEqual(summary.improvementType, .pace)
        XCTAssertTrue(summary.comparisonText.contains(current.formattedPace))
        XCTAssertFalse(summary.motivationText.isEmpty)
    }

    func testIncreasedWorkoutFrequencyBuildsConsistencySummary() {
        let current = makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 3_000)
        let previous = makeWorkout(daysAgo: 1, distanceMeters: 10_000, duration: 3_000)
        let third = makeWorkout(daysAgo: 2, sport: .bike, distanceMeters: 25_000, duration: 3_600)

        let summary = builder.build(current: current, recentWorkouts: [current, previous, third])

        XCTAssertEqual(summary.improvementType, .consistency)
        XCTAssertTrue(summary.comparisonText.contains("이번 주"))
        XCTAssertFalse(summary.motivationText.isEmpty)
    }

    func testInsufficientComparisonDataBuildsNoneSummary() {
        let current = makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 3_000)

        let summary = builder.build(current: current, recentWorkouts: [current])

        XCTAssertEqual(summary.improvementType, .none)
        XCTAssertFalse(summary.comparisonText.isEmpty)
        XCTAssertFalse(summary.motivationText.isEmpty)
    }

    func testSummaryUsesWorkoutGrowthOnlyWithoutRecoveryScore() {
        let previous = makeWorkout(daysAgo: 2, distanceMeters: 10_000, duration: 3_000)
        let current = makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 2_850)

        let summary = builder.build(current: current, recentWorkouts: [current, previous])

        XCTAssertEqual(summary.workoutId, current.id)
        XCTAssertEqual(summary.improvementType, .pace)
        XCTAssertFalse(summary.title.isEmpty)
    }

    private func makeWorkout(
        daysAgo: Int,
        sport: WorkoutSport = .run,
        distanceMeters: Double,
        duration: TimeInterval
    ) -> Workout {
        Workout(
            id: UUID(),
            sport: sport,
            title: sport == .bike ? "테스트 라이딩" : "테스트 러닝",
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate,
            distanceMeters: distanceMeters,
            duration: duration,
            activeCalories: 420,
            avgHeartRate: 148,
            maxHeartRate: 172,
            avgPower: sport == .bike ? 180 : nil,
            elevationGain: sport == .bike ? 120 : 30,
            cadence: sport == .run ? 174 : 88,
            effort: 6,
            source: "테스트",
            route: [],
            splits: [],
            samples: makeSamples(durationMinutes: Int(duration / 60)),
            zones: [],
            achievements: [],
            aiSummary: "테스트 운동입니다."
        )
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 7)) ?? Date()
    }

    private func makeSamples(durationMinutes: Int) -> [WorkoutSample] {
        (0..<9).map { index in
            WorkoutSample(
                minute: Double(index) / 8.0 * Double(durationMinutes),
                heartRate: 142 + index,
                paceSeconds: 300,
                power: nil
            )
        }
    }
}
