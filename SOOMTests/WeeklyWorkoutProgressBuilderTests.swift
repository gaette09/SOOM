import XCTest
@testable import SOOM

final class WeeklyWorkoutProgressBuilderTests: XCTestCase {
    private let builder = WeeklyWorkoutProgressBuilder()

    func testIncreasedWorkoutCountBuildsImprovingProgress() {
        let currentWeek = [
            makeWorkout(daysAgo: 0, distanceMeters: 8_000, duration: 2_400),
            makeWorkout(daysAgo: 1, distanceMeters: 6_000, duration: 1_900),
            makeWorkout(daysAgo: 3, sport: .bike, distanceMeters: 28_000, duration: 3_600)
        ]
        let previousWeek = [
            makeWorkout(daysAgo: 8, distanceMeters: 7_000, duration: 2_100)
        ]

        let progress = builder.build(workouts: currentWeek + previousWeek, referenceDate: baseDate)

        XCTAssertEqual(progress.trendType, .improving)
        XCTAssertEqual(progress.workoutCount, 3)
        XCTAssertTrue(progress.progressSummary.contains("꾸준"))
    }

    func testDistanceIncreaseBuildsImprovingProgress() {
        let currentWeek = [
            makeWorkout(daysAgo: 0, distanceMeters: 12_000, duration: 3_600),
            makeWorkout(daysAgo: 2, distanceMeters: 9_000, duration: 2_700)
        ]
        let previousWeek = [
            makeWorkout(daysAgo: 8, distanceMeters: 7_000, duration: 2_100),
            makeWorkout(daysAgo: 10, distanceMeters: 6_000, duration: 1_900)
        ]

        let progress = builder.build(workouts: currentWeek + previousWeek, referenceDate: baseDate)

        XCTAssertEqual(progress.trendType, .improving)
        XCTAssertTrue(progress.progressSummary.contains("멀리"))
        XCTAssertEqual(progress.totalDistanceKm, 21.0, accuracy: 0.01)
    }

    func testInsufficientDataBuildsInsufficientDataProgress() {
        let progress = builder.build(workouts: [], referenceDate: baseDate)

        XCTAssertEqual(progress.trendType, .insufficientData)
        XCTAssertEqual(progress.workoutCount, 0)
        XCTAssertEqual(progress.totalDistanceKm, 0, accuracy: 0.01)
        XCTAssertFalse(progress.motivationText.isEmpty)
    }

    func testTotalDistanceAndDurationAreCalculatedFromCurrentWeekOnly() {
        let currentWeek = [
            makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 3_000),
            makeWorkout(daysAgo: 2, distanceMeters: 5_000, duration: 1_500)
        ]
        let previousWeek = [
            makeWorkout(daysAgo: 8, distanceMeters: 40_000, duration: 7_200)
        ]

        let progress = builder.build(workouts: currentWeek + previousWeek, referenceDate: baseDate)

        XCTAssertEqual(progress.workoutCount, 2)
        XCTAssertEqual(progress.totalDistanceKm, 15.0, accuracy: 0.01)
        XCTAssertEqual(progress.totalDurationMinutes, 75)
        XCTAssertTrue(progress.averagePaceOrSpeedText.contains("평균"))
    }

    func testWeeklyProgressUsesWorkoutDataOnlyWithoutRecoveryScore() {
        let workouts = [
            makeWorkout(daysAgo: 0, distanceMeters: 12_000, duration: 3_600),
            makeWorkout(daysAgo: 2, distanceMeters: 9_000, duration: 2_700),
            makeWorkout(daysAgo: 8, distanceMeters: 7_000, duration: 2_100)
        ]

        let progress = builder.build(workouts: workouts, referenceDate: baseDate)

        XCTAssertFalse(progress.progressSummary.isEmpty)
        XCTAssertFalse(progress.motivationText.isEmpty)
        XCTAssertGreaterThan(progress.totalDurationMinutes, 0)
    }


    func testBuildFromWorkoutGrowthInputsCalculatesWeeklyProgress() {
        let inputs = [
            makeGrowthInput(daysAgo: 0, type: .running, distanceKm: 10, durationMinutes: 50),
            makeGrowthInput(daysAgo: 2, type: .running, distanceKm: 5, durationMinutes: 25),
            makeGrowthInput(daysAgo: 8, type: .running, distanceKm: 7, durationMinutes: 40)
        ]

        let progress = builder.build(inputs: inputs, referenceDate: baseDate)

        XCTAssertEqual(progress.workoutCount, 2)
        XCTAssertEqual(progress.totalDistanceKm, 15.0, accuracy: 0.01)
        XCTAssertEqual(progress.totalDurationMinutes, 75)
        XCTAssertTrue(progress.averagePaceOrSpeedText.contains("/km"))
    }

    func testBuildFromCyclingGrowthInputsUsesSpeedText() {
        let inputs = [
            makeGrowthInput(daysAgo: 0, type: .cycling, distanceKm: 30, durationMinutes: 60),
            makeGrowthInput(daysAgo: 2, type: .cycling, distanceKm: 20, durationMinutes: 40)
        ]

        let progress = builder.build(inputs: inputs, referenceDate: baseDate)

        XCTAssertTrue(progress.averagePaceOrSpeedText.contains("km/h"))
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
            samples: [],
            zones: [],
            achievements: [],
            aiSummary: "테스트 운동입니다."
        )
    }



    private func makeGrowthInput(
        daysAgo: Int,
        type: UnifiedWorkoutType,
        distanceKm: Double?,
        durationMinutes: Int
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .appleHealthKit,
            workoutType: type,
            startDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate,
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            averagePaceText: nil,
            averageSpeedKmh: nil,
            averageHeartRate: 148,
            elevationGainMeters: 64,
            activeEnergyKcal: 420
        )
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 7)) ?? Date()
    }
}
