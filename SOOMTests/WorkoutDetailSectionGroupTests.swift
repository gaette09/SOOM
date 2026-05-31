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
    func testClubHomeStartsFromJoinedClubDirectory() {
        let directory = ClubDirectorySnapshot.mock()

        XCTAssertEqual(directory.joinedClubs.map(\.name), ["SOOM Riders", "Morning Runners"])
        XCTAssertEqual(directory.createdClubs.first?.name, "Recovery Crew")
        XCTAssertEqual(directory.recommendedClubs.count, 3)
    }

    func testClubDetailExposesScopedCompetitiveIdentity() {
        let detail = ClubDetail.soomRiders

        XCTAssertEqual(detail.name, "SOOM Riders")
        XCTAssertEqual(detail.intro, "빠르기보다 꾸준함을 쌓는 라이더 클럽")
        XCTAssertEqual(detail.sport, "자전거")
        XCTAssertEqual(detail.owner, "지환")
        XCTAssertEqual(detail.privacy, .open)
        XCTAssertEqual(detail.activeMembersThisWeek, 128)
        XCTAssertEqual(detail.memberCount, 412)
        XCTAssertEqual(detail.weeklyRank, 12)
        XCTAssertEqual(detail.goalPercentText, "73%")
    }

    func testClubDetailIdentityLayerAppearsBeforeRankingData() {
        let detail = ClubDetail.soomRiders

        XCTAssertTrue(detail.purpose.contains("주 3회"))
        XCTAssertTrue(detail.rules.contains("공개 피드 운동만 랭킹에 반영합니다."))
        XCTAssertEqual(Array(detail.identityTags.prefix(3)), ["꾸준함", "회복 라이딩", "초보 환영"])
    }

    func testMemberPreviewIncludesOwnerLeadersAndRecentMember() {
        let members = ClubDetail.soomRiders.memberPreview

        XCTAssertEqual(members.first?.name, "지환")
        XCTAssertEqual(members.first?.role, "운영자")
        XCTAssertTrue(members.contains { $0.role == "이번 주 1위" })
        XCTAssertTrue(members.contains { $0.role == "최근 합류" })
    }

    func testMembershipStateProvidesPlaceholderActions() {
        XCTAssertEqual(ClubDetail.soomRiders.membershipState.actionTitle, "가입됨")
        XCTAssertEqual(ClubDetail.recoveryCrew.membershipState.actionTitle, "관리")
        XCTAssertTrue(ClubDetail.MembershipState.recommended.placeholderTitle.contains("가입"))
    }

    func testWeeklyRankingHighlightsCurrentUser() {
        let currentUser = ClubDetail.soomRiders.ranking.first(where: \.isCurrentUser)

        XCTAssertEqual(currentUser?.rank, 12)
        XCTAssertEqual(currentUser?.name, "나")
        XCTAssertEqual(currentUser?.valueText(for: .distance), "42.6 km")
    }

    func testDifferentClubsCanHaveDifferentRankingsAndChallenges() {
        XCTAssertNotEqual(ClubDetail.soomRiders.weeklyRank, ClubDetail.morningRunners.weeklyRank)
        XCTAssertNotEqual(ClubDetail.soomRiders.challenges.first?.title, ClubDetail.morningRunners.challenges.first?.title)
    }

    func testEmptyClubDirectoryKeepsRecommendationsAndCreateEntryFoundation() {
        let directory = ClubDirectorySnapshot.mock(hasJoinedClubs: false)

        XCTAssertTrue(directory.joinedClubs.isEmpty)
        XCTAssertTrue(directory.createdClubs.isEmpty)
        XCTAssertEqual(directory.recommendedClubs.map(\.name), ["한강 라이더스", "초보 라이딩", "주말 러너스"])
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
        let states = Set(ClubDetail.soomRiders.badges.map(\.state))

        XCTAssertTrue(states.contains(.earned))
        XCTAssertTrue(states.contains(.inProgress))
        XCTAssertTrue(states.contains(.newThisWeek))
        XCTAssertTrue(states.contains(.rare))
    }
}
