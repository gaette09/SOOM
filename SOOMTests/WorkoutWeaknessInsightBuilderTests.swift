import XCTest
@testable import SOOM

final class WorkoutWeaknessInsightBuilderTests: XCTestCase {
    private let builder = WorkoutWeaknessInsightBuilder()

    func testLatePaceDropBuildsPacingInsight() {
        let current = makeWorkout(
            daysAgo: 0,
            distanceMeters: 10_000,
            duration: 3_200,
            effort: 6,
            samples: makeSamples(earlyPace: 300, latePace: 345, earlyHeartRate: 145, lateHeartRate: 151)
        )
        let previous = makeWorkout(daysAgo: 2, distanceMeters: 10_000, duration: 3_100)

        let insight = builder.build(current: current, recentWorkouts: [current, previous])

        XCTAssertEqual(insight.insightType, .pacing)
        XCTAssertFalse(insight.shortInsight.isEmpty)
        XCTAssertFalse(insight.suggestion.isEmpty)
    }

    func testHighRecoveryLoadBuildsRecoveryInsight() {
        let current = makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 3_100, effort: 9)
        let recentHardOne = makeWorkout(daysAgo: 1, distanceMeters: 9_000, duration: 2_900, effort: 8)
        let recentHardTwo = makeWorkout(daysAgo: 2, distanceMeters: 8_000, duration: 2_700, effort: 7)

        let insight = builder.build(current: current, recentWorkouts: [current, recentHardOne, recentHardTwo])

        XCTAssertEqual(insight.insightType, .recovery)
        XCTAssertTrue(insight.suggestion.contains("회복"))
    }

    func testIrregularWorkoutGapsBuildsConsistencyInsight() {
        let current = makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 3_100, effort: 5)
        let first = makeWorkout(daysAgo: 1, sport: .bike, distanceMeters: 20_000, duration: 3_600, effort: 5)
        let second = makeWorkout(daysAgo: 2, sport: .swim, distanceMeters: 2_000, duration: 2_400, effort: 4)
        let third = makeWorkout(daysAgo: 8, sport: .bike, distanceMeters: 21_000, duration: 3_700, effort: 5)

        let insight = builder.build(current: current, recentWorkouts: [current, first, second, third])

        XCTAssertEqual(insight.insightType, .consistency)
        XCTAssertTrue(insight.shortInsight.contains("간격"))
    }

    func testInsufficientDataBuildsNoneInsight() {
        let current = makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 3_100, samples: [])

        let insight = builder.build(current: current, recentWorkouts: [current])

        XCTAssertEqual(insight.insightType, .none)
        XCTAssertFalse(insight.suggestion.isEmpty)
    }

    func testInsightUsesWorkoutDataWithoutRecoveryScore() {
        let current = makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 3_100, effort: 9)
        let previous = makeWorkout(daysAgo: 1, distanceMeters: 9_000, duration: 2_900, effort: 8)

        let insight = builder.build(current: current, recentWorkouts: [current, previous])

        XCTAssertEqual(insight.insightType, .recovery)
        XCTAssertFalse(insight.title.isEmpty)
    }

    func testInsightCopyAvoidsNegativeJudgementWords() {
        let current = makeWorkout(
            daysAgo: 0,
            distanceMeters: 10_000,
            duration: 3_200,
            samples: makeSamples(earlyPace: 300, latePace: 345, earlyHeartRate: 145, lateHeartRate: 151)
        )
        let previous = makeWorkout(daysAgo: 2, distanceMeters: 10_000, duration: 3_100)

        let insight = builder.build(current: current, recentWorkouts: [current, previous])
        let copy = [insight.title, insight.shortInsight, insight.suggestion].joined(separator: " ")

        XCTAssertFalse(copy.contains("못"))
        XCTAssertFalse(copy.contains("실패"))
        XCTAssertFalse(copy.contains("나쁨"))
        XCTAssertFalse(copy.contains("부족"))
    }

    private func makeWorkout(
        daysAgo: Int,
        sport: WorkoutSport = .run,
        distanceMeters: Double,
        duration: TimeInterval,
        avgHeartRate: Int = 148,
        effort: Int = 6,
        samples: [WorkoutSample]? = nil
    ) -> Workout {
        Workout(
            id: UUID(),
            sport: sport,
            title: sport == .bike ? "테스트 라이딩" : "테스트 러닝",
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate,
            distanceMeters: distanceMeters,
            duration: duration,
            activeCalories: 420,
            avgHeartRate: avgHeartRate,
            maxHeartRate: avgHeartRate + 22,
            avgPower: sport == .bike ? 180 : nil,
            elevationGain: sport == .bike ? 120 : 30,
            cadence: sport == .run ? 174 : 88,
            effort: effort,
            source: "테스트",
            route: [],
            splits: [],
            samples: samples ?? makeSamples(earlyPace: 300, latePace: 304, earlyHeartRate: 144, lateHeartRate: 150),
            zones: [],
            achievements: [],
            aiSummary: "테스트 운동입니다."
        )
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 7)) ?? Date()
    }

    private func makeSamples(
        earlyPace: Double,
        latePace: Double,
        earlyHeartRate: Int,
        lateHeartRate: Int
    ) -> [WorkoutSample] {
        (0..<9).map { index in
            let isLate = index >= 6
            let pace = isLate ? latePace : earlyPace
            let heartRate = isLate ? lateHeartRate : earlyHeartRate
            return WorkoutSample(
                minute: Double(index) * 5,
                heartRate: heartRate + index % 2,
                paceSeconds: pace,
                power: nil
            )
        }
    }
}
