import XCTest
@testable import SOOM

final class WorkoutDetailSectionGroupTests: XCTestCase {
    func testOrderedGroupsFollowWorkoutDetailReadingFlow() {
        XCTAssertEqual(
            WorkoutDetailSectionGroup.ordered.map(\.id),
            [.core, .growth, .sensorData, .recovery]
        )
    }

    func testGroupPrioritiesIncreaseWithReadingOrder() {
        let priorities = WorkoutDetailSectionGroup.ordered.map(\.priority)

        XCTAssertEqual(priorities, priorities.sorted())
        XCTAssertEqual(Set(priorities).count, priorities.count)
    }

    func testGroupTitlesStayShortAndScannable() {
        let titles = WorkoutDetailSectionGroup.ordered.map(\.title)

        XCTAssertEqual(titles, ["오늘 핵심", "성장 흐름", "운동 데이터", "회복 해석"])
        XCTAssertTrue(titles.allSatisfy { $0.count <= 6 })
    }

    func testGroupsAreFutureReadyWithoutEnablingCollapse() {
        XCTAssertTrue(WorkoutDetailSectionGroup.ordered.allSatisfy { !$0.isCollapsibleReady })
    }
}

final class ClubUIFoundationTests: XCTestCase {
    func testMockClubStatusExposesOnlineCompetitiveIdentity() {
        let snapshot = ClubDashboardSnapshot.mock

        XCTAssertEqual(snapshot.name, "SOOM Riders")
        XCTAssertEqual(snapshot.memberCount, 412)
        XCTAssertEqual(snapshot.weeklyRank, 12)
        XCTAssertEqual(snapshot.goalPercentText, "73%")
    }

    func testWeeklyRankingHighlightsCurrentUser() {
        let currentUser = ClubDashboardSnapshot.mock.ranking.first(where: \.isCurrentUser)

        XCTAssertEqual(currentUser?.rank, 12)
        XCTAssertEqual(currentUser?.name, "나")
        XCTAssertEqual(currentUser?.valueText(for: .distance), "42.6 km")
    }

    func testChallengeProgressFormatting() {
        let challenge = ClubChallenge(
            title: "클럽 전체 1,000km",
            progress: 730,
            target: 1_000,
            unit: "km",
            subtitle: "함께 채우는 주간 거리"
        )

        XCTAssertEqual(challenge.progressRatio, 0.73, accuracy: 0.001)
        XCTAssertEqual(challenge.progressText, "730 / 1000km")
    }

    func testBadgeStatesKeepCalmAchievementCategories() {
        let states = Set(ClubDashboardSnapshot.mock.badges.map(\.state))

        XCTAssertTrue(states.contains(.earned))
        XCTAssertTrue(states.contains(.inProgress))
        XCTAssertTrue(states.contains(.newThisWeek))
        XCTAssertTrue(states.contains(.rare))
    }
}
