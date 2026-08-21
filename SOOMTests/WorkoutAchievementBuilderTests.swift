import XCTest
@testable import SOOM

final class WorkoutAchievementBuilderTests: XCTestCase {
    private func makeEffort(durationMinutes: Int, speed: Double) -> WorkoutBestEffort {
        WorkoutBestEffort(
            durationMinutes: durationMinutes,
            averageMetersPerSecond: speed,
            routeCoordinate: WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0)
        )
    }

    func testTopRankProducesAchievement() {
        let today = [makeEffort(durationMinutes: 5, speed: 5.0)]
        // Today's 5.0 beats 3.0 and 2.0, loses to nothing -> rank 1.
        let history: [Int: [Double]] = [5: [3.0, 2.0]]

        let achievements = WorkoutAchievementBuilder.build(
            todayEfforts: today,
            historicalEffortsByDuration: history,
            workoutType: .running
        )

        XCTAssertEqual(achievements.count, 1)
        XCTAssertEqual(achievements.first?.rank, 1)
        XCTAssertEqual(achievements.first?.durationMinutes, 5)
        XCTAssertTrue(achievements.first?.isPaceBased ?? false)
    }

    func testBelowThresholdRankIsExcluded() {
        let today = [makeEffort(durationMinutes: 5, speed: 3.0)]
        // Today's 3.0 loses to 5.0, 4.5, 4.0, 3.5 -> rank 5, outside top-3.
        let history: [Int: [Double]] = [5: [5.0, 4.5, 4.0, 3.5]]

        let achievements = WorkoutAchievementBuilder.build(
            todayEfforts: today,
            historicalEffortsByDuration: history,
            workoutType: .running
        )

        XCTAssertTrue(achievements.isEmpty)
    }

    func testInsufficientHistoryHidesAchievement() {
        let today = [makeEffort(durationMinutes: 5, speed: 5.0)]
        // Only 1 historical entry — below minimumHistoryCount (2).
        let history: [Int: [Double]] = [5: [3.0]]

        let achievements = WorkoutAchievementBuilder.build(
            todayEfforts: today,
            historicalEffortsByDuration: history,
            workoutType: .running
        )

        XCTAssertTrue(achievements.isEmpty)
    }

    func testCapsAtMaximumMarkersPreferringBetterRanks() {
        let today = [
            makeEffort(durationMinutes: 1, speed: 5.0),  // rank 1
            makeEffort(durationMinutes: 5, speed: 4.0),  // rank 2
            makeEffort(durationMinutes: 10, speed: 3.0)  // rank 3
        ]
        let history: [Int: [Double]] = [
            1: [3.0, 2.0],
            5: [4.5, 3.0],
            10: [3.5, 3.2]
        ]

        let achievements = WorkoutAchievementBuilder.build(
            todayEfforts: today,
            historicalEffortsByDuration: history,
            workoutType: .cycling
        )

        XCTAssertEqual(achievements.count, WorkoutAchievementConfig.maximumMarkers)
        XCTAssertEqual(achievements.map(\.rank), [1, 2])
    }

    func testSpeedFormattingForNonPaceSport() {
        let today = [makeEffort(durationMinutes: 5, speed: 10.0)] // 36 km/h
        let history: [Int: [Double]] = [5: [8.0, 7.0]]

        let achievements = WorkoutAchievementBuilder.build(
            todayEfforts: today,
            historicalEffortsByDuration: history,
            workoutType: .cycling
        )

        XCTAssertEqual(achievements.first?.valueText, "36.0 km/h")
        XCTAssertFalse(achievements.first?.isPaceBased ?? true)
    }
}
