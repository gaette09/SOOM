import XCTest
@testable import SOOM

@MainActor
final class ClubDomainFoundationTests: XCTestCase {
    func testClubDomainModelsInitialize() {
        let club = ClubDetail.soomRiders.club

        XCTAssertEqual(club.id, "soom-riders")
        XCTAssertEqual(club.name, "SOOM Riders")
        XCTAssertEqual(club.visibility, .open)
        XCTAssertTrue(club.isJoined)
        XCTAssertEqual(club.membershipState, .joined)
    }

    func testLocalClubServiceReturnsDirectory() async throws {
        let service = InMemoryClubService()

        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(directory.joinedClubs.map(\.name), ["SOOM Riders", "Morning Runners"])
        XCTAssertEqual(directory.createdClubs.map(\.name), ["Recovery Crew"])
        XCTAssertEqual(directory.recommendedClubs.map(\.name), ["한강 라이더스", "초보 라이딩", "주말 러너스"])
    }

    func testFetchDetailReturnsScopedRankings() async throws {
        let service = InMemoryClubService()

        let detail = try await service.fetchClubDetail(clubId: "soom-riders")
        let rankings = try await service.fetchRankings(clubId: "soom-riders", metric: .distance)

        XCTAssertEqual(detail.name, "SOOM Riders")
        XCTAssertTrue(rankings.allSatisfy { $0.clubId == "soom-riders" })
        XCTAssertEqual(rankings.first?.rank, 1)
    }

    func testJoinClubUpdatesMembershipStateAndDirectory() async throws {
        let service = InMemoryClubService()

        try await service.joinClub(clubId: "hangang-riders")
        let detail = try await service.fetchClubDetail(clubId: "hangang-riders")
        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(detail.membershipState, .joined)
        XCTAssertTrue(directory.joinedClubs.contains { $0.id == "hangang-riders" })
        XCTAssertFalse(directory.recommendedClubs.contains { $0.id == "hangang-riders" })
    }

    func testJoinStatePersistsAcrossServiceReload() async throws {
        let persistence = makePersistence()
        let service = InMemoryClubService(persistence: persistence)

        try await service.joinClub(clubId: "hangang-riders")

        let reloadedService = InMemoryClubService(persistence: persistence)
        let detail = try await reloadedService.fetchClubDetail(clubId: "hangang-riders")
        let directory = try await reloadedService.fetchClubDirectory()

        XCTAssertEqual(detail.membershipState, .joined)
        XCTAssertTrue(directory.joinedClubs.contains { $0.id == "hangang-riders" })
    }

    func testLeaveStatePersistsAcrossServiceReload() async throws {
        let persistence = makePersistence()
        let service = InMemoryClubService(persistence: persistence)

        try await service.leaveClub(clubId: "soom-riders")

        let reloadedService = InMemoryClubService(persistence: persistence)
        let detail = try await reloadedService.fetchClubDetail(clubId: "soom-riders")
        let directory = try await reloadedService.fetchClubDirectory()

        XCTAssertEqual(detail.membershipState, .recommended)
        XCTAssertFalse(directory.joinedClubs.contains { $0.id == "soom-riders" })
        XCTAssertTrue(directory.recommendedClubs.contains { $0.id == "soom-riders" })
    }

    func testCreateClubAddsCreatedClub() async throws {
        let service = InMemoryClubService()

        let club = try await service.createClub(input: ClubCreateInput(
            name: "Night Riders",
            purpose: "밤에도 무리하지 않고 리듬을 유지합니다.",
            sportFocus: "자전거",
            visibility: .private
        ))
        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(club.name, "Night Riders")
        XCTAssertEqual(club.membershipState, .owned)
        XCTAssertTrue(directory.createdClubs.contains { $0.id == club.id })
    }

    func testCreateClubPersistsAcrossServiceReload() async throws {
        let persistence = makePersistence()
        let service = InMemoryClubService(persistence: persistence)

        let club = try await service.createClub(input: ClubCreateInput(
            name: "Night Riders",
            purpose: "밤에도 무리하지 않고 리듬을 유지합니다.",
            sportFocus: "자전거",
            visibility: .private
        ))

        let reloadedService = InMemoryClubService(persistence: persistence)
        let directory = try await reloadedService.fetchClubDirectory()
        let detail = try await reloadedService.fetchClubDetail(clubId: club.id)

        XCTAssertTrue(directory.createdClubs.contains { $0.id == club.id })
        XCTAssertEqual(detail.membershipState, .owned)
        XCTAssertEqual(detail.privacy, .private)
    }

    func testCorruptedClubPersistenceFallsBackToSeedData() async throws {
        let userDefaults = makeUserDefaults()
        userDefaults.set(Data("not-json".utf8), forKey: "club-test")
        let persistence = LocalClubPersistence(userDefaults: userDefaults, key: "club-test")
        let service = InMemoryClubService(persistence: persistence)

        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(directory.joinedClubs.map(\.name), ["SOOM Riders", "Morning Runners"])
        XCTAssertEqual(directory.createdClubs.map(\.name), ["Recovery Crew"])
    }

    func testRankingMetricSwitchReturnsExpectedEntries() async throws {
        let service = InMemoryClubService()

        let sessionRankings = try await service.fetchRankings(clubId: "soom-riders", metric: .workoutCount)
        let distanceRankings = try await service.fetchRankings(clubId: "soom-riders", metric: .distance)

        XCTAssertEqual(sessionRankings.first?.metricType, .workoutCount)
        XCTAssertEqual(distanceRankings.first?.metricType, .distance)
        XCTAssertNotEqual(sessionRankings.map(\.id), distanceRankings.map(\.id))
    }

    func testChallengesExposeProgressFoundation() async throws {
        let service = InMemoryClubService()

        let challenges = try await service.fetchChallenges(clubId: "soom-riders")

        XCTAssertFalse(challenges.isEmpty)
        XCTAssertTrue(challenges.allSatisfy { $0.targetValue > 0 })
        XCTAssertTrue(challenges.allSatisfy { $0.progressRatio >= 0 && $0.progressRatio <= 1 })
    }

    func testClubMotivationSummaryInitializesAndCalculatesDelta() {
        let summary = ClubDetail.soomRiders.motivationSummary

        XCTAssertEqual(summary.currentRank, 12)
        XCTAssertEqual(summary.previousRank, 18)
        XCTAssertEqual(summary.rankDelta, 6)
        XCTAssertEqual(summary.rankMovementLabel, "지난주보다 6계단 상승")
        XCTAssertEqual(summary.weeklyContributionDistance, 42.6)
        XCTAssertEqual(summary.contributionPercent, 0.08)
        XCTAssertEqual(summary.nextRankTargetDistance, 3.4)
        XCTAssertTrue(summary.motivationLine.contains("클럽 거리의 8%"))
    }

    func testClubDetailExposesMotivationSummary() async throws {
        let service = InMemoryClubService()

        let detail = try await service.fetchClubDetail(clubId: "soom-riders")

        XCTAssertEqual(detail.motivationSummary.currentRank, detail.weeklyRank)
        XCTAssertEqual(detail.motivationSummary.activeMembersThisWeek, 42)
        XCTAssertEqual(detail.motivationSummary.newBadgesThisWeek, 8)
        XCTAssertEqual(detail.motivationSummary.completedChallengesThisWeek, 2)
    }

    func testChallengeRemainingActionCopyExists() {
        let challenge = ClubDetail.soomRiders.challenges[0]

        XCTAssertEqual(challenge.remainingLabel, "1회 운동 남음")
        XCTAssertTrue(challenge.nextActionLine.contains("한 번"))
    }

    func testCreateClubReturnsDefaultMotivationState() async throws {
        let service = InMemoryClubService()

        let club = try await service.createClub(input: ClubCreateInput(
            name: "Quiet Miles",
            purpose: "조용히 거리를 쌓는 클럽",
            sportFocus: "러닝",
            visibility: .open
        ))
        let detail = try await service.fetchClubDetail(clubId: club.id)

        XCTAssertEqual(detail.motivationSummary, .emptyNewClub)
        XCTAssertTrue(detail.motivationSummary.motivationLine.contains("랭킹이 만들어지는 중"))
    }

    func testJoinClubKeepsDefaultMotivationStateForRecommendedClub() async throws {
        let service = InMemoryClubService()

        try await service.joinClub(clubId: "hangang-riders")
        let detail = try await service.fetchClubDetail(clubId: "hangang-riders")

        XCTAssertEqual(detail.membershipState, .joined)
        XCTAssertGreaterThanOrEqual(detail.motivationSummary.currentRank, 0)
        XCTAssertFalse(detail.motivationSummary.nextRankTargetLabel.isEmpty)
    }

    func testClubsViewModelLoadsDirectoryAndOpensClub() async {
        let viewModel = ClubsViewModel(service: InMemoryClubService())

        await viewModel.loadDirectory()
        await viewModel.openClub(clubId: "soom-riders")

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.directory.joinedClubs.count, 2)
        XCTAssertEqual(viewModel.selectedClub?.id, "soom-riders")
        XCTAssertFalse(viewModel.rankings.isEmpty)
        XCTAssertFalse(viewModel.challenges.isEmpty)
    }

    private func makePersistence() -> LocalClubPersistence {
        LocalClubPersistence(userDefaults: makeUserDefaults(), key: "club-test")
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "club-domain-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
