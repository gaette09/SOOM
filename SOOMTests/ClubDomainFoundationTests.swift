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

    func testRankOneNextGoalUsesMaintenanceCopy() {
        let summary = ClubMotivationSummary.defaultSummary(
            currentRank: 1,
            rankMovement: 0,
            contributionDistanceKm: 88,
            weeklyContributionCount: 4,
            activeMembersThisWeek: 24,
            newBadgesThisWeek: 2,
            completedChallengesThisWeek: 1,
            goalProgress: 0.72,
            motivationLine: "이번 주 기준을 잘 지키고 있어요."
        )

        XCTAssertNil(summary.nextRankTargetDistance)
        XCTAssertEqual(summary.nextGoalText, "지금은 기준을 지키는 중")
        XCTAssertFalse(summary.nextGoalText.contains("0위"))
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

    func testSupabaseClubServiceMapsClubRows() async throws {
        let remote = FakeSupabaseClubRemoteClient()
        remote.directoryPayload = SupabaseClubDirectoryPayload(
            clubs: [
                SupabaseClubRow(
                    id: "remote-riders",
                    name: "Remote Riders",
                    intro: "같은 리듬으로 움직이는 라이더",
                    purpose: "주 3회 움직임을 이어갑니다.",
                    sportFocus: "자전거",
                    visibility: "open",
                    ownerUserID: "owner-user",
                    createdAt: "2026-06-01T00:00:00Z",
                    updatedAt: "2026-06-01T00:00:00Z"
                )
            ],
            memberships: [
                SupabaseClubMemberRow(id: "member-current", clubID: "remote-riders", userID: "current-user", role: "member", joinedAt: nil)
            ],
            memberRows: [
                SupabaseClubMemberRow(id: "member-current", clubID: "remote-riders", userID: "current-user", role: "member", joinedAt: nil),
                SupabaseClubMemberRow(id: "member-other", clubID: "remote-riders", userID: "other-user", role: "member", joinedAt: nil)
            ]
        )
        let service = SupabaseClubService(remoteClient: remote, currentUserID: "current-user")

        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(directory.joinedClubs.count, 1)
        XCTAssertEqual(directory.joinedClubs.first?.name, "Remote Riders")
        XCTAssertEqual(directory.joinedClubs.first?.memberCount, 2)
        XCTAssertEqual(directory.joinedClubs.first?.membershipState, .joined)
        XCTAssertEqual(directory.joinedClubs.first?.sport, "자전거")
    }

    func testSupabaseClubServiceMapsOwnerMembershipState() async throws {
        let remote = FakeSupabaseClubRemoteClient()
        remote.detailPayload = SupabaseClubDetailPayload(
            club: SupabaseClubRow(
                id: "owned-club",
                name: "Owned Club",
                intro: "내가 만든 클럽",
                purpose: "기준을 함께 세웁니다.",
                sportFocus: "러닝",
                visibility: "private",
                ownerUserID: "current-user",
                createdAt: nil,
                updatedAt: nil
            ),
            membership: SupabaseClubMemberRow(id: "owner-row", clubID: "owned-club", userID: "current-user", role: "owner", joinedAt: nil),
            members: [],
            challenges: [],
            badges: []
        )
        let service = SupabaseClubService(remoteClient: remote, currentUserID: "current-user")

        let detail = try await service.fetchClubDetail(clubId: "owned-club")

        XCTAssertEqual(detail.membershipState, .owned)
        XCTAssertEqual(detail.privacy, .private)
        XCTAssertEqual(detail.summary.weeklyRank, 1)
    }

    func testClubServiceResolverReturnsFallbackWithoutRemoteClient() async throws {
        let fallback = InMemoryClubService()
        let service = ClubServiceResolver.makeService(
            remoteClient: nil,
            currentUserID: "current-user",
            fallback: fallback
        )

        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(directory.joinedClubs.map(\.name), ["SOOM Riders", "Morning Runners"])
    }

    func testSupabaseClubServiceCreateJoinLeaveRequestMapping() async throws {
        let remote = FakeSupabaseClubRemoteClient()
        remote.createdClubRow = SupabaseClubRow(
            id: "remote-created",
            name: "Night Riders",
            intro: "밤에도 리듬을 이어갑니다.",
            purpose: "밤에도 리듬을 이어갑니다.",
            sportFocus: "자전거",
            visibility: "private",
            ownerUserID: "current-user",
            createdAt: nil,
            updatedAt: nil
        )
        let service = SupabaseClubService(remoteClient: remote, currentUserID: "current-user")

        let club = try await service.createClub(input: ClubCreateInput(
            name: "Night Riders",
            purpose: "밤에도 리듬을 이어갑니다.",
            sportFocus: "자전거",
            visibility: .private
        ))
        try await service.joinClub(clubId: "remote-riders")
        try await service.leaveClub(clubId: "remote-riders")

        XCTAssertEqual(club.id, "remote-created")
        XCTAssertEqual(remote.createdClubRequests.first?.visibility, "private")
        XCTAssertEqual(remote.createdClubRequests.first?.ownerUserID, "current-user")
        XCTAssertEqual(remote.joinRequests.first?.role, "owner")
        XCTAssertEqual(remote.joinRequests.last?.role, "member")
        XCTAssertEqual(remote.leftClubIDs, ["remote-riders"])
    }

    func testFallbackClubServiceUsesLocalWhenRemoteFails() async throws {
        let failingRemote = FailingSupabaseClubRemoteClient()
        let service = FallbackClubService(
            primary: SupabaseClubService(remoteClient: failingRemote, currentUserID: "current-user"),
            fallback: InMemoryClubService()
        )

        let directory = try await service.fetchClubDirectory()
        let created = try await service.createClub(input: ClubCreateInput(
            name: "Fallback Club",
            purpose: "원격 연결이 어려워도 클럽 흐름을 이어갑니다.",
            sportFocus: "걷기",
            visibility: .open
        ))

        XCTAssertEqual(directory.joinedClubs.map(\.name), ["SOOM Riders", "Morning Runners"])
        XCTAssertEqual(created.name, "Fallback Club")
        XCTAssertEqual(created.membershipState, .owned)
    }

    func testRemoteClubMappingKeepsMotivationLayerFoundation() async throws {
        let remote = FakeSupabaseClubRemoteClient()
        remote.detailPayload = SupabaseClubDetailPayload(
            club: SupabaseClubRow(
                id: "remote-riders",
                name: "Remote Riders",
                intro: "같은 리듬으로 움직이는 라이더",
                purpose: "주 3회 움직임을 이어갑니다.",
                sportFocus: "자전거",
                visibility: "open",
                ownerUserID: "owner-user",
                createdAt: nil,
                updatedAt: nil
            ),
            membership: SupabaseClubMemberRow(id: "member-current", clubID: "remote-riders", userID: "current-user", role: "member", joinedAt: nil),
            members: [
                SupabaseClubMemberRow(id: "member-current", clubID: "remote-riders", userID: "current-user", role: "member", joinedAt: nil)
            ],
            challenges: [
                SupabaseClubChallengeRow(
                    id: "challenge-1",
                    clubID: "remote-riders",
                    title: "이번 주 3회 움직이기",
                    description: "클럽의 첫 리듬을 만듭니다.",
                    metricType: "workoutCount",
                    targetValue: 3,
                    startsAt: nil,
                    endsAt: nil
                )
            ],
            badges: [
                SupabaseClubBadgeRow(id: "badge-1", clubID: "remote-riders", title: "첫 기여", description: "첫 기록을 기다리는 중", rarity: "common")
            ]
        )
        let service = SupabaseClubService(remoteClient: remote, currentUserID: "current-user")

        let detail = try await service.fetchClubDetail(clubId: "remote-riders")

        XCTAssertFalse(detail.motivationSummary.motivationLine.isEmpty)
        XCTAssertFalse(detail.ranking.isEmpty)
        XCTAssertEqual(detail.challenges.first?.remainingLabel, "3회 운동 남음")
        XCTAssertEqual(detail.badges.first?.title, "첫 기여")
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

private final class FakeSupabaseClubRemoteClient: SupabaseClubRemoteClienting {
    var directoryPayload = SupabaseClubDirectoryPayload(clubs: [], memberships: [], memberRows: [])
    var detailPayload: SupabaseClubDetailPayload?
    var createdClubRow = SupabaseClubRow(
        id: "created-club",
        name: "Created Club",
        intro: nil,
        purpose: nil,
        sportFocus: nil,
        visibility: "open",
        ownerUserID: "current-user",
        createdAt: nil,
        updatedAt: nil
    )
    var createdClubRequests: [SupabaseClubInsertRequest] = []
    var joinRequests: [SupabaseClubMemberInsertRequest] = []
    var leftClubIDs: [String] = []

    func fetchClubDirectory(currentUserID: String) async throws -> SupabaseClubDirectoryPayload {
        directoryPayload
    }

    func fetchClubDetail(clubID: String, currentUserID: String) async throws -> SupabaseClubDetailPayload {
        if let detailPayload {
            return detailPayload
        }
        throw ClubServiceError.clubNotFound
    }

    func createClub(_ request: SupabaseClubInsertRequest) async throws -> SupabaseClubRow {
        createdClubRequests.append(request)
        return createdClubRow
    }

    func joinClub(_ request: SupabaseClubMemberInsertRequest) async throws {
        joinRequests.append(request)
    }

    func leaveClub(clubID: String, userID: String) async throws {
        leftClubIDs.append(clubID)
    }
}

private final class FailingSupabaseClubRemoteClient: SupabaseClubRemoteClienting {
    func fetchClubDirectory(currentUserID: String) async throws -> SupabaseClubDirectoryPayload {
        throw ClubSupabaseServiceError.unconfigured
    }

    func fetchClubDetail(clubID: String, currentUserID: String) async throws -> SupabaseClubDetailPayload {
        throw ClubSupabaseServiceError.unconfigured
    }

    func createClub(_ request: SupabaseClubInsertRequest) async throws -> SupabaseClubRow {
        throw ClubSupabaseServiceError.unconfigured
    }

    func joinClub(_ request: SupabaseClubMemberInsertRequest) async throws {
        throw ClubSupabaseServiceError.unconfigured
    }

    func leaveClub(clubID: String, userID: String) async throws {
        throw ClubSupabaseServiceError.unconfigured
    }
}
