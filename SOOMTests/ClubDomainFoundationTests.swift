import XCTest
import Supabase
@testable import SOOM

@MainActor
final class ClubDomainFoundationTests: XCTestCase {
    func testDirectoryHTTPReadsRunConcurrentlyWithNoWritesOrRealCredentials() async throws {
        ClubDirectoryHTTPFixture.state.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClubDirectoryHTTPFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = SupabaseClient(supabaseURL: URL(string: "https://synthetic.soom.invalid")!, supabaseKey: "synthetic-fixture-key",
            options: .init(auth: .init(storage: ClubMetricNoAuthStorage(), autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
                global: .init(session: session)))
        let remote = SupabaseClubRemoteClient(client: client)
        let started = ProcessInfo.processInfo.systemUptime
        let payload = try await remote.fetchClubDirectory(currentUserID: "synthetic-user")
        XCTAssertTrue(payload.clubs.isEmpty)
        let state = ClubDirectoryHTTPFixture.state.snapshot()
        XCTAssertEqual(state.requests, 3)
        XCTAssertEqual(state.peak, 3, "Independent SDK reads should overlap rather than wait sequentially")
        let result: [String: Any] = ["fixture": true, "requestCount": state.requests, "peakConcurrentReads": state.peak,
            "perResponseDelayMilliseconds": 50, "endToEndMilliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1_000,
            "network": "URLProtocol fixture; no external network or production writes"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "club-directory-concurrency-fixture.json"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testClubDomainModelsInitialize() {
        let club = ClubDetail.soomRiders.club

        XCTAssertEqual(club.id, "soom-riders")
        XCTAssertEqual(club.name, "SOOM Riders")
        XCTAssertEqual(club.visibility, .open)
        XCTAssertTrue(club.isJoined)
        XCTAssertEqual(club.membershipState, .joined)
    }

    func testLocalClubServiceReturnsDirectory() async throws {
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)

        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(directory.joinedClubs.map(\.name), ["SOOM Riders", "Morning Runners"])
        XCTAssertEqual(directory.createdClubs.map(\.name), ["Recovery Crew"])
        XCTAssertEqual(directory.recommendedClubs.map(\.name), ["한강 라이더스", "초보 라이딩", "주말 러너스"])
    }

    func testFetchDetailReturnsScopedRankings() async throws {
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)

        let detail = try await service.fetchClubDetail(clubId: "soom-riders")
        let rankings = try await service.fetchRankings(clubId: "soom-riders", metric: .distance)

        XCTAssertEqual(detail.name, "SOOM Riders")
        XCTAssertTrue(rankings.allSatisfy { $0.clubId == "soom-riders" })
        XCTAssertEqual(rankings.first?.rank, 1)
    }

    func testJoinClubUpdatesMembershipStateAndDirectory() async throws {
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)

        try await service.joinClub(clubId: "hangang-riders")
        let detail = try await service.fetchClubDetail(clubId: "hangang-riders")
        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(detail.membershipState, .joined)
        XCTAssertTrue(directory.joinedClubs.contains { $0.id == "hangang-riders" })
        XCTAssertFalse(directory.recommendedClubs.contains { $0.id == "hangang-riders" })
    }

    func testJoinStatePersistsAcrossServiceReload() async throws {
        let persistence = makePersistence()
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails, persistence: persistence)

        try await service.joinClub(clubId: "hangang-riders")

        let reloadedService = InMemoryClubService(details: InMemoryClubService.seedDetails, persistence: persistence)
        let detail = try await reloadedService.fetchClubDetail(clubId: "hangang-riders")
        let directory = try await reloadedService.fetchClubDirectory()

        XCTAssertEqual(detail.membershipState, .joined)
        XCTAssertTrue(directory.joinedClubs.contains { $0.id == "hangang-riders" })
    }

    func testLeaveStatePersistsAcrossServiceReload() async throws {
        let persistence = makePersistence()
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails, persistence: persistence)

        try await service.leaveClub(clubId: "soom-riders")

        let reloadedService = InMemoryClubService(details: InMemoryClubService.seedDetails, persistence: persistence)
        let detail = try await reloadedService.fetchClubDetail(clubId: "soom-riders")
        let directory = try await reloadedService.fetchClubDirectory()

        XCTAssertEqual(detail.membershipState, .recommended)
        XCTAssertFalse(directory.joinedClubs.contains { $0.id == "soom-riders" })
        XCTAssertTrue(directory.recommendedClubs.contains { $0.id == "soom-riders" })
    }

    func testCreateClubAddsCreatedClub() async throws {
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)

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
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails, persistence: persistence)

        let club = try await service.createClub(input: ClubCreateInput(
            name: "Night Riders",
            purpose: "밤에도 무리하지 않고 리듬을 유지합니다.",
            sportFocus: "자전거",
            visibility: .private
        ))

        let reloadedService = InMemoryClubService(details: InMemoryClubService.seedDetails, persistence: persistence)
        let directory = try await reloadedService.fetchClubDirectory()
        let detail = try await reloadedService.fetchClubDetail(clubId: club.id)

        XCTAssertTrue(directory.createdClubs.contains { $0.id == club.id })
        XCTAssertEqual(detail.membershipState, .owned)
        XCTAssertEqual(detail.privacy, .private)
    }

    func testCorruptedClubPersistenceKeepsProductionDirectoryEmpty() async throws {
        let userDefaults = makeUserDefaults()
        userDefaults.set(Data("not-json".utf8), forKey: "club-test")
        let persistence = LocalClubPersistence(userDefaults: userDefaults, key: "club-test")
        let service = InMemoryClubService(persistence: persistence)

        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(directory, .empty)
    }

    func testRankingMetricSwitchReturnsExpectedEntries() async throws {
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)

        let sessionRankings = try await service.fetchRankings(clubId: "soom-riders", metric: .workoutCount)
        let distanceRankings = try await service.fetchRankings(clubId: "soom-riders", metric: .distance)

        XCTAssertEqual(sessionRankings.first?.metricType, .workoutCount)
        XCTAssertEqual(distanceRankings.first?.metricType, .distance)
        XCTAssertNotEqual(sessionRankings.map(\.id), distanceRankings.map(\.id))
    }

    func testChallengesExposeProgressFoundation() async throws {
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)

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
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)

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

    func testChallengeStateComputeReturnsActiveWhileOngoingAndUnderTarget() {
        let endsAt = Date(timeIntervalSince1970: 1_767_600_000)

        let state = ClubChallengeState.compute(currentValue: 2, targetValue: 10, endsAt: endsAt, now: endsAt.addingTimeInterval(-3_600))

        XCTAssertEqual(state, .active)
    }

    func testChallengeStateComputeReturnsExpiredOnceEndsAtHasPassed() {
        let endsAt = Date(timeIntervalSince1970: 1_767_600_000)

        let state = ClubChallengeState.compute(currentValue: 2, targetValue: 10, endsAt: endsAt, now: endsAt.addingTimeInterval(3_600))

        XCTAssertEqual(state, .expired)
    }

    func testChallengeStateComputeReturnsCompletedWhenTargetIsReached() {
        let endsAt = Date(timeIntervalSince1970: 1_767_600_000)

        let state = ClubChallengeState.compute(currentValue: 10, targetValue: 10, endsAt: endsAt, now: endsAt.addingTimeInterval(-3_600))

        XCTAssertEqual(state, .completed)
    }

    func testChallengeStateComputePrioritizesCompletedOverExpired() {
        // Reached the target before endsAt, but "now" happens to be past
        // endsAt too — completed should win, not flip to expired.
        let endsAt = Date(timeIntervalSince1970: 1_767_600_000)

        let state = ClubChallengeState.compute(currentValue: 10, targetValue: 10, endsAt: endsAt, now: endsAt.addingTimeInterval(3_600))

        XCTAssertEqual(state, .completed)
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
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)

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
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)

        try await service.joinClub(clubId: "hangang-riders")
        let detail = try await service.fetchClubDetail(clubId: "hangang-riders")

        XCTAssertEqual(detail.membershipState, .joined)
        XCTAssertGreaterThanOrEqual(detail.motivationSummary.currentRank, 0)
        XCTAssertFalse(detail.motivationSummary.nextRankTargetLabel.isEmpty)
    }

    func testClubsViewModelLoadsDirectoryAndOpensClub() async {
        let viewModel = ClubsViewModel(service: InMemoryClubService(details: InMemoryClubService.seedDetails))

        await viewModel.loadDirectory()
        await viewModel.openClub(clubId: "soom-riders")

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.directory.joinedClubs.count, 2)
        XCTAssertEqual(viewModel.selectedClub?.id, "soom-riders")
        XCTAssertFalse(viewModel.rankings.isEmpty)
        XCTAssertFalse(viewModel.challenges.isEmpty)
    }

    func testOpenClubReusesDetailChallengesInsteadOfRefetching() async {
        let spy = ChallengeFetchCountingClubService(wrapping: InMemoryClubService(details: InMemoryClubService.seedDetails))
        let viewModel = ClubsViewModel(service: spy)

        await viewModel.openClub(clubId: "soom-riders")

        // openClub should reuse detail.challenges from the fetchClubDetail
        // call it already made, not call fetchChallenges(clubId:) again —
        // that would re-fetch the whole club detail and recompute every
        // challenge's currentValue a second time.
        XCTAssertEqual(spy.fetchChallengesCallCount, 0)
        XCTAssertFalse(viewModel.challenges.isEmpty)
        XCTAssertEqual(viewModel.challenges.map(\.id), viewModel.selectedClub?.challenges.map(\.id))
    }

    func testClubsViewModelMarksLocalFallbackWhenServiceFallsBack() async {
        let viewModel = ClubsViewModel(service: InMemoryClubService(details: InMemoryClubService.seedDetails))
        viewModel.configure(service: FallbackClubService(
            primary: SupabaseClubService(remoteClient: FailingSupabaseClubRemoteClient(), currentUserID: "current-user"),
            fallback: InMemoryClubService(details: InMemoryClubService.seedDetails),
            onDidUseFallback: viewModel.markUsingLocalFallback
        ))

        await viewModel.loadDirectory()
        // markUsingLocalFallback hops to the main actor via Task {}; give it
        // a beat to land, matching this suite's existing async-settling
        // convention (see AuthViewModelTests' CountingRemoteSessionLoader).
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(viewModel.isShowingLocalFallbackData)
        XCTAssertEqual(viewModel.directory.joinedClubs.map(\.name), ["SOOM Riders", "Morning Runners"])
    }

    func testClubsViewModelDoesNotMarkLocalFallbackWhenPrimarySucceeds() async {
        let viewModel = ClubsViewModel(service: InMemoryClubService(details: InMemoryClubService.seedDetails))

        await viewModel.loadDirectory()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertFalse(viewModel.isShowingLocalFallbackData)
    }

    func testClubsViewModelResetsLocalFallbackFlagAtStartOfEachLoad() async {
        let viewModel = ClubsViewModel(service: InMemoryClubService(details: InMemoryClubService.seedDetails))
        viewModel.markUsingLocalFallback()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(viewModel.isShowingLocalFallbackData)

        await viewModel.loadDirectory()

        XCTAssertFalse(viewModel.isShowingLocalFallbackData)
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
        XCTAssertEqual(detail.summary.weeklyRank, 0)
    }

    func testClubServiceResolverReturnsFallbackWithoutRemoteClient() async throws {
        let fallback = InMemoryClubService(details: InMemoryClubService.seedDetails)
        let service = ClubServiceResolver.makeService(
            remoteClient: nil,
            currentUserID: "current-user",
            fallback: fallback
        )

        let directory = try await service.fetchClubDirectory()

        XCTAssertEqual(directory.joinedClubs.map(\.name), ["SOOM Riders", "Morning Runners"])
    }

    func testClubServiceResolverCallsOnDidUseFallbackWithoutRemoteClient() async throws {
        var fallbackUsedCount = 0
        let service = ClubServiceResolver.makeService(
            remoteClient: nil,
            currentUserID: "current-user",
            fallback: InMemoryClubService(details: InMemoryClubService.seedDetails),
            onDidUseFallback: { fallbackUsedCount += 1 }
        )

        _ = try await service.fetchClubDirectory()

        XCTAssertEqual(fallbackUsedCount, 1)
    }

    func testClubServiceResolverCallsOnDidUseFallbackWithoutCurrentUserID() async throws {
        var fallbackUsedCount = 0
        let service = ClubServiceResolver.makeService(
            remoteClient: FakeSupabaseClubRemoteClient(),
            currentUserID: nil,
            fallback: InMemoryClubService(details: InMemoryClubService.seedDetails),
            onDidUseFallback: { fallbackUsedCount += 1 }
        )

        _ = try await service.fetchClubDirectory()

        XCTAssertEqual(fallbackUsedCount, 1)
    }

    func testClubServiceResolverDoesNotCallOnDidUseFallbackWhenRemoteClientSucceeds() async throws {
        var fallbackUsedCount = 0
        let remote = FakeSupabaseClubRemoteClient()
        let service = ClubServiceResolver.makeService(
            remoteClient: remote,
            currentUserID: "current-user",
            fallback: InMemoryClubService(details: InMemoryClubService.seedDetails),
            onDidUseFallback: { fallbackUsedCount += 1 }
        )

        _ = try await service.fetchClubDirectory()

        XCTAssertEqual(fallbackUsedCount, 0)
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
            fallback: InMemoryClubService(details: InMemoryClubService.seedDetails)
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

    func testModerationRejectionNeverFallsBackToLocalClubCreation() async throws {
        for message in ["SOOM_CONTENT_REJECTED", "SOOM_TEXT_TOO_LONG", "SOOM_ACCOUNT_SUSPENDED"] {
            let remote = FakeSupabaseClubRemoteClient()
            remote.createError = ClubCreatePolicyRejection(description: message)
            let fallback = InMemoryClubService(details: InMemoryClubService.seedDetails)
            var fallbackCount = 0
            let service = FallbackClubService(
                primary: SupabaseClubService(remoteClient: remote, currentUserID: "current-user"),
                fallback: fallback,
                onDidUseFallback: { fallbackCount += 1 }
            )
            let input = ClubCreateInput(name: "Rejected Club", purpose: "수정할 소개", sportFocus: "걷기", visibility: .open)
            do {
                _ = try await service.createClub(input: input)
                XCTFail("Moderation must propagate")
            } catch { XCTAssertEqual(String(describing: error), message) }
            XCTAssertEqual(fallbackCount, 0)
            let directory = try await fallback.fetchClubDirectory()
            XCTAssertFalse(directory.createdClubs.contains { $0.name == input.name })
        }
    }

    func testClubCreateFormRetainsInputAndDisplaysServerRejection() async {
        let form = ClubCreateViewModel()
        form.name = "작성한 클럽"
        form.purpose = "수정할 소개"
        let dismiss = await form.submit { _ in throw ClubCreatePolicyRejection(description: "SOOM_CONTENT_REJECTED") }
        XCTAssertFalse(dismiss)
        XCTAssertEqual(form.name, "작성한 클럽")
        XCTAssertEqual(form.purpose, "수정할 소개")
        XCTAssertTrue(form.canCreate)
        XCTAssertNotNil(form.errorMessage)
        XCTAssertFalse(form.savedLocally)
    }

    func testClubCreateLocalFallbackStaysOpenWithExplicitLocalResult() async {
        let form = ClubCreateViewModel()
        form.name = "로컬 클럽"
        form.purpose = "연결이 안 되어 초안으로 저장"
        let service = InMemoryClubService(details: InMemoryClubService.seedDetails)
        let dismiss = await form.submit { try await service.createClub(input: $0) }
        XCTAssertFalse(dismiss)
        XCTAssertTrue(form.savedLocally)
        XCTAssertFalse(form.canCreate, "A completed local save must not be repeated by tapping again")
        XCTAssertNil(form.errorMessage)
    }

    func testConfirmedRemoteClubCreationCanDismissForm() async {
        let form = ClubCreateViewModel()
        form.name = "온라인 클럽"
        form.purpose = "함께 움직여요"
        let dismiss = await form.submit { input in
            ClubDomain(id: UUID().uuidString, name: input.name, intro: input.purpose,
                       purpose: input.purpose, sportFocus: input.sportFocus, visibility: .open,
                       ownerId: UUID().uuidString, memberCount: 1, createdAt: Date(),
                       isJoined: true, membershipState: .owned)
        }
        XCTAssertTrue(dismiss)
        XCTAssertFalse(form.savedLocally)
        XCTAssertFalse(form.canCreate)
    }

    func testFallbackClubServiceCallsOnDidUseFallbackWhenPrimaryFails() async throws {
        var fallbackUsedCount = 0
        let service = FallbackClubService(
            primary: SupabaseClubService(remoteClient: FailingSupabaseClubRemoteClient(), currentUserID: "current-user"),
            fallback: InMemoryClubService(details: InMemoryClubService.seedDetails),
            onDidUseFallback: { fallbackUsedCount += 1 }
        )

        _ = try await service.fetchClubDirectory()

        XCTAssertEqual(fallbackUsedCount, 1)
    }

    func testFallbackClubServiceDoesNotCallOnDidUseFallbackWhenPrimarySucceeds() async throws {
        var fallbackUsedCount = 0
        let remote = FakeSupabaseClubRemoteClient()
        let service = FallbackClubService(
            primary: SupabaseClubService(remoteClient: remote, currentUserID: "current-user"),
            fallback: InMemoryClubService(details: InMemoryClubService.seedDetails),
            onDidUseFallback: { fallbackUsedCount += 1 }
        )

        _ = try await service.fetchClubDirectory()

        XCTAssertEqual(fallbackUsedCount, 0)
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
        XCTAssertTrue(detail.ranking.isEmpty)
        XCTAssertEqual(detail.challenges.first?.remainingLabel, "3회 운동 남음")
        XCTAssertEqual(detail.badges.first?.title, "첫 기여")
    }

    func testChallengeProgressAggregatesRealMemberActivity() async throws {
        let remote = FakeSupabaseClubRemoteClient()
        remote.detailPayload = SupabaseClubDetailPayload(
            club: SupabaseClubRow(
                id: "remote-riders",
                name: "Remote Riders",
                intro: nil,
                purpose: nil,
                sportFocus: "자전거",
                visibility: "open",
                ownerUserID: "owner-user",
                createdAt: nil,
                updatedAt: nil
            ),
            membership: SupabaseClubMemberRow(id: "member-current", clubID: "remote-riders", userID: "current-user", role: "member", joinedAt: nil),
            members: [
                SupabaseClubMemberRow(id: "member-current", clubID: "remote-riders", userID: "current-user", role: "member", joinedAt: nil),
                SupabaseClubMemberRow(id: "member-other", clubID: "remote-riders", userID: "other-user", role: "member", joinedAt: nil)
            ],
            challenges: [
                SupabaseClubChallengeRow(
                    id: "challenge-distance",
                    clubID: "remote-riders",
                    title: "클럽 전체 100km",
                    description: nil,
                    metricType: "distance",
                    targetValue: 100,
                    startsAt: nil,
                    endsAt: nil
                ),
                SupabaseClubChallengeRow(
                    id: "challenge-count",
                    clubID: "remote-riders",
                    title: "클럽 전체 10회",
                    description: nil,
                    metricType: "workoutCount",
                    targetValue: 10,
                    startsAt: nil,
                    endsAt: nil
                ),
                SupabaseClubChallengeRow(
                    id: "challenge-consistency",
                    clubID: "remote-riders",
                    title: "매일 이어가기",
                    description: nil,
                    metricType: "consistency",
                    targetValue: 7,
                    startsAt: nil,
                    endsAt: nil
                )
            ],
            badges: []
        )
        remote.activitySummaries = [
            ClubMemberActivitySummary(userID: "current-user", totalDistanceMeters: 12_000, workoutCount: 3, totalDurationSeconds: 3_600, activeDayCount: 3),
            ClubMemberActivitySummary(userID: "other-user", totalDistanceMeters: 8_000, workoutCount: 2, totalDurationSeconds: 1_800, activeDayCount: 2)
        ]
        let service = SupabaseClubService(remoteClient: remote, currentUserID: "current-user")

        let detail = try await service.fetchClubDetail(clubId: "remote-riders")

        let distanceChallenge = try XCTUnwrap(detail.challenges.first { $0.id == "challenge-distance" })
        let countChallenge = try XCTUnwrap(detail.challenges.first { $0.id == "challenge-count" })
        let consistencyChallenge = try XCTUnwrap(detail.challenges.first { $0.id == "challenge-consistency" })

        XCTAssertEqual(distanceChallenge.currentValue, 20, accuracy: 0.001)
        XCTAssertEqual(countChallenge.currentValue, 5, accuracy: 0.001)
        XCTAssertEqual(consistencyChallenge.currentValue, 0, accuracy: 0.001)
    }

    func testChallengeProgressPassesChallengeEndsAtAsUntilBound() async throws {
        let formatter = ISO8601DateFormatter()
        let startsAt = Date(timeIntervalSince1970: 1_767_000_000)
        let endsAt = Date(timeIntervalSince1970: 1_767_600_000)
        let remote = FakeSupabaseClubRemoteClient()
        remote.detailPayload = SupabaseClubDetailPayload(
            club: SupabaseClubRow(
                id: "remote-riders",
                name: "Remote Riders",
                intro: nil,
                purpose: nil,
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
                    id: "challenge-distance",
                    clubID: "remote-riders",
                    title: "클럽 전체 100km",
                    description: nil,
                    metricType: "distance",
                    targetValue: 100,
                    startsAt: formatter.string(from: startsAt),
                    endsAt: formatter.string(from: endsAt)
                )
            ],
            badges: []
        )
        let service = SupabaseClubService(remoteClient: remote, currentUserID: "current-user")

        _ = try await service.fetchClubDetail(clubId: "remote-riders")

        // Bounding the query at the challenge's own endsAt (not "now") is
        // what stops an expired challenge from still accumulating activity
        // that happened after it ended.
        XCTAssertEqual(remote.lastFetchMemberActivitySummariesSince, startsAt)
        XCTAssertEqual(remote.lastFetchMemberActivitySummariesUntil, endsAt)
    }

    func testRankingFetchesActivitySummariesWithNoUpperBound() async throws {
        let remote = FakeSupabaseClubRemoteClient()
        remote.detailPayload = SupabaseClubDetailPayload(
            club: SupabaseClubRow(
                id: "remote-riders",
                name: "Remote Riders",
                intro: nil,
                purpose: nil,
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
            challenges: [],
            badges: []
        )
        let service = SupabaseClubService(remoteClient: remote, currentUserID: "current-user")

        _ = try await service.fetchRankings(clubId: "remote-riders", metric: .distance)

        // Ranking is always "this week up to now" — it must keep going
        // through the 2-arg convenience (until: nil), never a fixed cutoff.
        XCTAssertNil(remote.lastFetchMemberActivitySummariesUntil)
    }

    func testMakeChallengeMarksExpiredWhenEndsAtHasPassedAndTargetUnmet() async throws {
        let formatter = ISO8601DateFormatter()
        let startsAt = Date(timeIntervalSince1970: 1_767_000_000)
        let endsAt = Date(timeIntervalSince1970: 1_767_600_000)
        let remote = FakeSupabaseClubRemoteClient()
        remote.detailPayload = makeSingleChallengeDetailPayload(
            metricType: "workoutCount",
            targetValue: 10,
            startsAt: formatter.string(from: startsAt),
            endsAt: formatter.string(from: endsAt)
        )
        remote.activitySummaries = [
            ClubMemberActivitySummary(userID: "current-user", totalDistanceMeters: 0, workoutCount: 2, totalDurationSeconds: 0, activeDayCount: 1)
        ]
        let service = SupabaseClubService(
            remoteClient: remote,
            currentUserID: "current-user",
            now: { endsAt.addingTimeInterval(3_600) }
        )

        let detail = try await service.fetchClubDetail(clubId: "remote-riders")

        XCTAssertEqual(detail.challenges.first?.state, .expired)
    }

    func testMakeChallengeMarksCompletedEvenAfterEndsAtHasPassed() async throws {
        let formatter = ISO8601DateFormatter()
        let startsAt = Date(timeIntervalSince1970: 1_767_000_000)
        let endsAt = Date(timeIntervalSince1970: 1_767_600_000)
        let remote = FakeSupabaseClubRemoteClient()
        remote.detailPayload = makeSingleChallengeDetailPayload(
            metricType: "workoutCount",
            targetValue: 2,
            startsAt: formatter.string(from: startsAt),
            endsAt: formatter.string(from: endsAt)
        )
        remote.activitySummaries = [
            ClubMemberActivitySummary(userID: "current-user", totalDistanceMeters: 0, workoutCount: 2, totalDurationSeconds: 0, activeDayCount: 1)
        ]
        let service = SupabaseClubService(
            remoteClient: remote,
            currentUserID: "current-user",
            now: { endsAt.addingTimeInterval(3_600) }
        )

        let detail = try await service.fetchClubDetail(clubId: "remote-riders")

        // Target was reached before endsAt — completed must win even though
        // "now" is also past endsAt (see testChallengeStateComputePrioritizesCompletedOverExpired).
        XCTAssertEqual(detail.challenges.first?.state, .completed)
    }

    private func makeSingleChallengeDetailPayload(
        metricType: String,
        targetValue: Double,
        startsAt: String,
        endsAt: String
    ) -> SupabaseClubDetailPayload {
        SupabaseClubDetailPayload(
            club: SupabaseClubRow(
                id: "remote-riders",
                name: "Remote Riders",
                intro: nil,
                purpose: nil,
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
                    title: "테스트 챌린지",
                    description: nil,
                    metricType: metricType,
                    targetValue: targetValue,
                    startsAt: startsAt,
                    endsAt: endsAt
                )
            ],
            badges: []
        )
    }

    func testClubActiveDayCountUnionsDatesAcrossMembersInsteadOfSumming() {
        let day1 = Date(timeIntervalSince1970: 1_767_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let day3 = day1.addingTimeInterval(172_800)
        // memberA active on day1, day2; memberB active on day2, day3.
        let dates = [day1, day2, day2, day3]

        let count = SupabaseClubRemoteClient.activeDayCount(from: dates, calendar: Calendar(identifier: .gregorian))

        // The club was active on 3 distinct days (day1, day2, day3) — not 4,
        // which is what a naive sum of each member's own count would give.
        XCTAssertEqual(count, 3)
    }

    func testConsistencyChallengeProgressUsesClubWideActiveDayCount() async throws {
        let formatter = ISO8601DateFormatter()
        let startsAt = Date(timeIntervalSince1970: 1_767_000_000)
        let endsAt = Date(timeIntervalSince1970: 1_767_600_000)
        let remote = FakeSupabaseClubRemoteClient()
        remote.detailPayload = makeSingleChallengeDetailPayload(
            metricType: "consistency",
            targetValue: 7,
            startsAt: formatter.string(from: startsAt),
            endsAt: formatter.string(from: endsAt)
        )
        remote.clubActiveDayCount = 5
        let service = SupabaseClubService(remoteClient: remote, currentUserID: "current-user")

        let detail = try await service.fetchClubDetail(clubId: "remote-riders")
        let challenge = try XCTUnwrap(detail.challenges.first)

        XCTAssertEqual(challenge.currentValue, 5, accuracy: 0.001)
        // Bounded the same way distance/workoutCount are — the club-wide
        // query shouldn't count activity past the challenge's own endsAt.
        XCTAssertEqual(remote.lastFetchClubActiveDayCountSince, startsAt)
        XCTAssertEqual(remote.lastFetchClubActiveDayCountUntil, endsAt)
    }

    func testClubMigrationContainsSecurityDefinerHelpers() throws {
        let sql = try clubMigrationSQL()

        XCTAssertTrue(sql.contains("create or replace function public.is_club_member(target_club_id uuid)"))
        XCTAssertTrue(sql.contains("create or replace function public.is_club_owner(target_club_id uuid)"))
        XCTAssertTrue(sql.contains("create or replace function public.is_club_admin(target_club_id uuid)"))
        XCTAssertGreaterThanOrEqual(sql.components(separatedBy: "security definer").count - 1, 3)
        XCTAssertTrue(sql.contains("set search_path = public"))
    }

    func testClubMembersPolicyDoesNotDirectlySelfReferenceMembersTable() throws {
        let sql = try clubMigrationSQL()
        let policy = try sqlBlock(
            in: sql,
            from: "create policy \"club_members_select_scoped\"",
            to: "drop policy if exists \"club_members_insert_join_open\""
        )

        XCTAssertFalse(policy.contains("from public.club_members"))
        XCTAssertTrue(policy.contains("public.is_club_member(club_id)"))
        XCTAssertTrue(policy.contains("public.is_club_admin(club_id)"))
    }

    func testClubMigrationHasOwnerOnlyWritesAndDeletePolicy() throws {
        let sql = try clubMigrationSQL()

        XCTAssertTrue(sql.contains("create policy \"clubs_update_owner\""))
        XCTAssertTrue(sql.contains("using (owner_user_id = auth.uid())"))
        XCTAssertTrue(sql.contains("create policy \"clubs_delete_owner\""))
        XCTAssertTrue(sql.contains("create policy \"club_challenges_insert_owner\""))
        XCTAssertTrue(sql.contains("create policy \"club_challenges_update_owner\""))
        XCTAssertTrue(sql.contains("create policy \"club_challenges_delete_owner\""))
        XCTAssertTrue(sql.contains("create policy \"club_badges_insert_owner\""))
        XCTAssertTrue(sql.contains("create policy \"club_badges_update_owner\""))
        XCTAssertTrue(sql.contains("create policy \"club_badges_delete_owner\""))
    }

    func testClubMigrationHasUpdatedAtTriggerAndRollbackForHelpers() throws {
        let sql = try clubMigrationSQL()

        XCTAssertTrue(sql.contains("create or replace function public.set_updated_at()"))
        XCTAssertTrue(sql.contains("drop trigger if exists clubs_set_updated_at on public.clubs"))
        XCTAssertTrue(sql.contains("create trigger clubs_set_updated_at"))
        XCTAssertTrue(sql.contains("drop function if exists public.is_club_admin(uuid)"))
        XCTAssertTrue(sql.contains("drop function if exists public.is_club_owner(uuid)"))
        XCTAssertTrue(sql.contains("drop function if exists public.is_club_member(uuid)"))
    }

    func testNewInstallationAndLegacySampleMembershipsHaveNoProductionClubs() async throws {
        let persistence = makePersistence()
        persistence.saveMembershipState(.joined, for: "soom-riders")
        persistence.saveMembershipState(.joined, for: UUID().uuidString)
        let service = InMemoryClubService(persistence: persistence)
        let directory = try await service.fetchClubDirectory()
        XCTAssertEqual(directory, .empty)
        let viewModel = ClubsViewModel(service: service)
        await viewModel.loadDirectory()
        viewModel.markUsingLocalFallback()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(viewModel.shouldShowLocalFallbackBanner)
        XCTAssertNil(viewModel.detail(for: "soom-riders"))
        await viewModel.openClub(clubId: "soom-riders")
        XCTAssertNil(viewModel.selectedClub)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testProductionPersistenceRestoresOnlyAClubActuallyCreatedLocally() async throws {
        let persistence = makePersistence()
        let service = InMemoryClubService(persistence: persistence)
        let created = try await service.createClub(input: ClubCreateInput(
            name: "My Saved Club", purpose: "실제로 저장한 소개", sportFocus: "걷기", visibility: .private
        ))
        let reloaded = InMemoryClubService(persistence: persistence)
        let viewModel = ClubsViewModel(service: reloaded)
        await viewModel.loadDirectory()
        XCTAssertEqual(viewModel.directory.createdClubs.map(\.id), [created.id])
        XCTAssertTrue(viewModel.directory.joinedClubs.isEmpty)
        XCTAssertTrue(viewModel.directory.recommendedClubs.isEmpty)
        XCTAssertTrue(viewModel.shouldShowLocalFallbackBanner)
        let detail = try await reloaded.fetchClubDetail(clubId: created.id)
        XCTAssertTrue(detail.ranking.isEmpty)
        XCTAssertEqual(detail.weeklyRankText, "집계 전")
        XCTAssertEqual(detail.activeMembersThisWeek, 0)
    }

    func testRemoteUUIDCacheCannotReturnThroughFallbackOrAcknowledgeFailedMembershipChange() async throws {
        let detail = try await makeRealIDRemoteClub()
        let local = ClubDetail.localCreated(input: ClubCreateInput(name: "Saved Local", purpose: "저장된 초안", sportFocus: "걷기", visibility: .private))
        let fallback = InMemoryClubService(details: [detail, local])
        let service = FallbackClubService(
            primary: SupabaseClubService(remoteClient: FailingSupabaseClubRemoteClient(), currentUserID: "current-user"),
            fallback: fallback
        )
        let directory = try await service.fetchClubDirectory()
        XCTAssertEqual(directory.createdClubs.map(\.id), [local.id])
        XCTAssertTrue(directory.joinedClubs.isEmpty)
        let attempts: [() async throws -> Void] = [
            { _ = try await service.fetchClubDetail(clubId: detail.id) },
            { _ = try await service.fetchRankings(clubId: detail.id, metric: .distance) },
            { _ = try await service.fetchChallenges(clubId: detail.id) },
            { try await service.joinClub(clubId: detail.id) },
            { try await service.leaveClub(clubId: detail.id) }
        ]
        for attempt in attempts {
            do { try await attempt(); XCTFail("Remote failures must not be replaced by cached local success") }
            catch { XCTAssertEqual(error as? ClubSupabaseServiceError, .unconfigured) }
        }
        let retained = try await fallback.fetchClubDetail(clubId: detail.id)
        XCTAssertEqual(retained.membershipState, detail.membershipState)
    }

    func testFailedDirectoryAndDetailReloadDiscardPriorRemoteContent() async throws {
        let detail = try await makeRealIDRemoteClub()
        let service = MutableClubCacheTestService(wrapping: InMemoryClubService(details: [detail]))
        let viewModel = ClubsViewModel(service: service)
        await viewModel.loadDirectory()
        await viewModel.openClub(clubId: detail.id)
        XCTAssertEqual(viewModel.selectedClub?.id, detail.id)
        service.failure = ClubServiceError.clubNotFound
        await viewModel.openClub(clubId: detail.id)
        XCTAssertNil(viewModel.detail(for: detail.id))
        XCTAssertTrue(viewModel.rankings.isEmpty)
        await viewModel.loadDirectory()
        XCTAssertEqual(viewModel.directory, .empty)
        XCTAssertNil(viewModel.selectedClub)
    }

    func testLateDirectoryFromPreviousAccountCannotRestoreItsClubs() async throws {
        let detail = try await makeRealIDRemoteClub()
        let service = MutableClubCacheTestService(wrapping: InMemoryClubService(details: [detail]))
        let started = expectation(description: "Old account directory started")
        var resume: CheckedContinuation<Void, Never>?
        service.beforeDirectory = {
            await withCheckedContinuation { continuation in resume = continuation; started.fulfill() }
        }
        let viewModel = ClubsViewModel(service: service)
        let load = Task { await viewModel.loadDirectory() }
        await fulfillment(of: [started], timeout: 1)
        viewModel.configure(service: InMemoryClubService())
        await viewModel.loadDirectory()
        resume?.resume()
        await load.value
        XCTAssertEqual(viewModel.directory, .empty)
        XCTAssertNil(viewModel.detail(for: detail.id))
    }

    func testRemoteClubWithoutActivityDoesNotInventRankOrDefaultChallenges() async throws {
        let detail = try await makeRealIDRemoteClub()
        XCTAssertEqual(detail.weeklyRank, 0)
        XCTAssertTrue(detail.ranking.isEmpty)
        XCTAssertTrue(detail.challenges.isEmpty)
        XCTAssertTrue(detail.badges.isEmpty)
        XCTAssertTrue(detail.pulses.isEmpty)
        XCTAssertEqual(detail.motivationSummary.activeMembersThisWeek, 0)
        XCTAssertEqual(detail.motivationSummary.newBadgesThisWeek, 0)
    }

    private func makeRealIDRemoteClub() async throws -> ClubDetail {
        let remote = FakeSupabaseClubRemoteClient()
        let id = UUID().uuidString
        remote.detailPayload = SupabaseClubDetailPayload(
            club: SupabaseClubRow(id: id, name: "Real Remote", intro: nil, purpose: nil,
                sportFocus: "걷기", visibility: "open", ownerUserID: "other-user", createdAt: nil, updatedAt: nil),
            membership: SupabaseClubMemberRow(id: "membership", clubID: id, userID: "current-user", role: "member", joinedAt: nil),
            members: [SupabaseClubMemberRow(id: "membership", clubID: id, userID: "current-user", role: "member", joinedAt: nil)],
            challenges: [], badges: []
        )
        return try await SupabaseClubService(remoteClient: remote, currentUserID: "current-user").fetchClubDetail(clubId: id)
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

    private func clubMigrationSQL(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sqlURL = repoRoot.appendingPathComponent("supabase/club_foundation_v1.sql")
        return try String(contentsOf: sqlURL, encoding: .utf8)
    }

    private func sqlBlock(in sql: String, from startMarker: String, to endMarker: String) throws -> String {
        guard
            let startRange = sql.range(of: startMarker),
            let endRange = sql.range(of: endMarker, range: startRange.upperBound..<sql.endIndex)
        else {
            throw NSError(domain: "ClubDomainFoundationTests", code: 1)
        }
        return String(sql[startRange.lowerBound..<endRange.lowerBound])
    }
}

/// Wraps a real ClubService and counts fetchChallenges(clubId:) calls, so
/// tests can prove openClub(clubId:) stopped re-fetching challenges it
/// already got back from fetchClubDetail(clubId:).
private final class ChallengeFetchCountingClubService: ClubService {
    private let wrapped: ClubService
    private(set) var fetchChallengesCallCount = 0

    init(wrapping wrapped: ClubService) {
        self.wrapped = wrapped
    }

    func fetchClubDirectory() async throws -> ClubDirectorySnapshot {
        try await wrapped.fetchClubDirectory()
    }

    func fetchClubDetail(clubId: String) async throws -> ClubDetail {
        try await wrapped.fetchClubDetail(clubId: clubId)
    }

    func createClub(input: ClubCreateInput) async throws -> ClubDomain {
        try await wrapped.createClub(input: input)
    }

    func joinClub(clubId: String) async throws {
        try await wrapped.joinClub(clubId: clubId)
    }

    func leaveClub(clubId: String) async throws {
        try await wrapped.leaveClub(clubId: clubId)
    }

    func fetchRankings(clubId: String, metric: ClubRankingMetric) async throws -> [ClubRankingEntry] {
        try await wrapped.fetchRankings(clubId: clubId, metric: metric)
    }

    func fetchChallenges(clubId: String) async throws -> [ClubChallenge] {
        fetchChallengesCallCount += 1
        return try await wrapped.fetchChallenges(clubId: clubId)
    }
}

private struct ClubMetricNoAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
private final class ClubDirectoryHTTPFixture: URLProtocol {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0, peak = 0, requests = 0
        func reset() { lock.lock(); defer { lock.unlock() }; active = 0; peak = 0; requests = 0 }
        func begin() { lock.lock(); defer { lock.unlock() }; active += 1; requests += 1; peak = max(peak, active) }
        func finish() { lock.lock(); defer { lock.unlock() }; active -= 1 }
        func snapshot() -> (requests: Int, peak: Int) { lock.lock(); defer { lock.unlock() }; return (requests, peak) }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "synthetic.soom.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.begin()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("[]".utf8))
            Self.state.finish()
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
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
    var createError: Error?
    var directoryError: Error?
    var afterDirectorySnapshot: (() async -> Void)?
    var afterCreate: (() -> Void)?
    var joinRequests: [SupabaseClubMemberInsertRequest] = []
    var joinError: Error?
    var leftClubIDs: [String] = []

    func fetchClubDirectory(currentUserID: String) async throws -> SupabaseClubDirectoryPayload {
        let payload = directoryPayload
        let error = directoryError
        await afterDirectorySnapshot?()
        if let error { throw error }
        return payload
    }

    func fetchClubDetail(clubID: String, currentUserID: String) async throws -> SupabaseClubDetailPayload {
        if let detailPayload {
            return detailPayload
        }
        throw ClubServiceError.clubNotFound
    }

    func createClub(_ request: SupabaseClubInsertRequest) async throws -> SupabaseClubRow {
        createdClubRequests.append(request)
        if let createError { throw createError }
        afterCreate?()
        return createdClubRow
    }

    func joinClub(_ request: SupabaseClubMemberInsertRequest) async throws {
        joinRequests.append(request)
        if let joinError { throw joinError }
    }

    func leaveClub(clubID: String, userID: String) async throws {
        leftClubIDs.append(clubID)
    }

    var activitySummaries: [ClubMemberActivitySummary] = []
    private(set) var lastFetchMemberActivitySummariesSince: Date?
    private(set) var lastFetchMemberActivitySummariesUntil: Date?

    func fetchMemberActivitySummaries(memberIDs: [String], since: Date, until: Date?) async throws -> [ClubMemberActivitySummary] {
        lastFetchMemberActivitySummariesSince = since
        lastFetchMemberActivitySummariesUntil = until
        return activitySummaries
    }

    var clubActiveDayCount = 0
    private(set) var lastFetchClubActiveDayCountSince: Date?
    private(set) var lastFetchClubActiveDayCountUntil: Date?

    func fetchClubActiveDayCount(memberIDs: [String], since: Date, until: Date) async throws -> Int {
        lastFetchClubActiveDayCountSince = since
        lastFetchClubActiveDayCountUntil = until
        return clubActiveDayCount
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

    func fetchMemberActivitySummaries(memberIDs: [String], since: Date, until: Date?) async throws -> [ClubMemberActivitySummary] {
        throw ClubSupabaseServiceError.unconfigured
    }

    func fetchClubActiveDayCount(memberIDs: [String], since: Date, until: Date) async throws -> Int {
        throw ClubSupabaseServiceError.unconfigured
    }
}

private struct ClubCreatePolicyRejection: Error, CustomStringConvertible {
    let description: String
}

private final class MutableClubCacheTestService: ClubService {
    let wrapped: any ClubService
    var failure: Error?
    var beforeDirectory: (() async -> Void)?

    init(wrapping service: any ClubService) { wrapped = service }

    func fetchClubDirectory() async throws -> ClubDirectorySnapshot {
        await beforeDirectory?()
        if let failure { throw failure }
        return try await wrapped.fetchClubDirectory()
    }
    func fetchClubDetail(clubId: String) async throws -> ClubDetail {
        if let failure { throw failure }
        return try await wrapped.fetchClubDetail(clubId: clubId)
    }
    func createClub(input: ClubCreateInput) async throws -> ClubDomain { try await wrapped.createClub(input: input) }
    func joinClub(clubId: String) async throws { try await wrapped.joinClub(clubId: clubId) }
    func leaveClub(clubId: String) async throws { try await wrapped.leaveClub(clubId: clubId) }
    func fetchRankings(clubId: String, metric: ClubRankingMetric) async throws -> [ClubRankingEntry] {
        if let failure { throw failure }
        return try await wrapped.fetchRankings(clubId: clubId, metric: metric)
    }
    func fetchChallenges(clubId: String) async throws -> [ClubChallenge] {
        if let failure { throw failure }
        return try await wrapped.fetchChallenges(clubId: clubId)
    }
}

extension ClubDomainFoundationTests {
    func testUXMembershipFailurePreservesStateAndRetryConfirmsCompletion() async throws {
        let service = UXMembershipTestService()
        let model = ClubsViewModel(service: service)
        await model.loadDirectory()
        await model.openClub(clubId: "soom-riders")
        service.failWrite = true
        let failed = await model.leaveClub(clubId: "soom-riders")
        XCTAssertFalse(failed)
        XCTAssertEqual(model.detail(for: "soom-riders")?.membershipState, .joined)
        XCTAssertNotNil(model.membershipError)
        XCTAssertNil(model.membershipOperation)
        service.failWrite = false
        let retried = await model.leaveClub(clubId: "soom-riders")
        XCTAssertTrue(retried)
        XCTAssertEqual(model.detail(for: "soom-riders")?.membershipState, .recommended)
        XCTAssertNil(model.membershipError)
    }

    func testUXRepeatedMembershipTapDoesNotSendSecondWrite() async {
        let service = UXMembershipTestService()
        let started = expectation(description: "write started")
        var resume: CheckedContinuation<Void, Never>?
        service.beforeWrite = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let model = ClubsViewModel(service: service)
        let first = Task { await model.joinClub(clubId: "hangang-riders") }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(model.membershipOperation, "hangang-riders")
        let duplicate = await model.joinClub(clubId: "hangang-riders")
        XCTAssertFalse(duplicate)
        XCTAssertEqual(service.writeCount, 1)
        resume?.resume()
        let confirmed = await first.value
        XCTAssertTrue(confirmed)
        XCTAssertNil(model.membershipOperation)
    }

    func testUXConfirmedWriteWithReadFailureDoesNotInviteDuplicateMutation() async {
        let service = UXMembershipTestService()
        service.failReadsAfterWrite = true
        let model = ClubsViewModel(service: service)
        let confirmed = await model.joinClub(clubId: "hangang-riders")
        XCTAssertTrue(confirmed, "The membership write succeeded even though its refresh failed")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(service.writeCount, 1)
        service.failReadsAfterWrite = false
        await model.loadDirectory()
        await model.openClub(clubId: "hangang-riders")
        XCTAssertEqual(model.detail(for: "hangang-riders")?.membershipState, .joined)
        XCTAssertEqual(service.writeCount, 1, "Recovery retries reads, never a confirmed write")
    }

    func testUXOldAccountMutationCannotDismissNewAccountSheet() async {
        let service = UXMembershipTestService()
        let started = expectation(description: "old write started")
        var resume: CheckedContinuation<Void, Never>?
        service.beforeWrite = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let model = ClubsViewModel(service: service)
        let old = Task { await model.joinClub(clubId: "hangang-riders") }
        await fulfillment(of: [started], timeout: 2)
        model.configure(service: InMemoryClubService())
        resume?.resume()
        let stale = await old.value
        XCTAssertFalse(stale)
        XCTAssertNil(model.membershipOperation)
        XCTAssertEqual(model.directory, .empty)
    }

    func testUXManagementLabelMatchesAvailableActionAndConnectionStatesDiffer() {
        XCTAssertEqual(ClubMembershipState.owned.actionTitle, "관리 준비 중")
        XCTAssertEqual(ClubMembershipState.admin.actionTitle, "관리 준비 중")
        XCTAssertNotEqual(GoogleHealthConnectionPhase.loginRequired.title, GoogleHealthConnectionPhase.unavailable.title)
        XCTAssertNotEqual(GoogleHealthConnectionPhase.failed.title, GoogleHealthConnectionPhase.unavailable.title)
    }
}

private final class UXMembershipTestService: ClubService {
    let wrapped = InMemoryClubService(details: InMemoryClubService.seedDetails)
    var failWrite = false
    var failReadsAfterWrite = false
    var writeCount = 0
    var beforeWrite: (() async -> Void)?
    func fetchClubDirectory() async throws -> ClubDirectorySnapshot {
        if failReadsAfterWrite && writeCount > 0 { throw ClubServiceError.clubNotFound }
        return try await wrapped.fetchClubDirectory()
    }
    func fetchClubDetail(clubId: String) async throws -> ClubDetail {
        if failReadsAfterWrite && writeCount > 0 { throw ClubServiceError.clubNotFound }
        return try await wrapped.fetchClubDetail(clubId: clubId)
    }
    func createClub(input: ClubCreateInput) async throws -> ClubDomain { try await wrapped.createClub(input: input) }
    func joinClub(clubId: String) async throws {
        writeCount += 1; await beforeWrite?()
        if failWrite { throw ClubServiceError.clubNotFound }
        try await wrapped.joinClub(clubId: clubId)
    }
    func leaveClub(clubId: String) async throws {
        writeCount += 1; await beforeWrite?()
        if failWrite { throw ClubServiceError.clubNotFound }
        try await wrapped.leaveClub(clubId: clubId)
    }
    func fetchRankings(clubId: String, metric: ClubRankingMetric) async throws -> [ClubRankingEntry] { try await wrapped.fetchRankings(clubId: clubId, metric: metric) }
    func fetchChallenges(clubId: String) async throws -> [ClubChallenge] { try await wrapped.fetchChallenges(clubId: clubId) }
}

@MainActor
final class ClubCreationRefreshRegressionTests: XCTestCase {
    private let input = ClubCreateInput(name: "Synthetic Created Club", purpose: "Synthetic purpose", sportFocus: "걷기", visibility: .open)

    func testConfirmedCreationRefreshFailureShowsReadRetryWithoutDuplicateWrite() async throws {
        let service = ClubCreationRefreshTestService()
        service.failReads = true
        let model = ClubsViewModel(service: service)
        let form = ClubCreateViewModel(); form.name = input.name; form.purpose = input.purpose
        let dismiss = await form.submit { try await model.createClub(input: $0) }
        XCTAssertTrue(dismiss)
        XCTAssertTrue(service.stored)
        XCTAssertEqual(service.creationCount, 1)
        XCTAssertTrue(model.directory.createdClubs.isEmpty)
        XCTAssertTrue(model.errorMessage?.contains("클럽을 다시 만들 필요는 없어요") == true)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(form.canCreate)
        service.failReads = false
        await model.loadDirectory()
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [service.id])
        XCTAssertNil(model.errorMessage)
        let duplicate = await form.submit { try await model.createClub(input: $0) }
        XCTAssertFalse(duplicate)
        XCTAssertEqual(service.creationCount, 1)
    }

    func testLatePreCreationDirectorySnapshotCannotEraseCreatedClub() async throws {
        let service = ClubCreationRefreshTestService()
        let started = expectation(description: "old snapshot captured")
        var resume: CheckedContinuation<Void, Never>?
        service.afterDirectorySnapshot = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let model = ClubsViewModel(service: service)
        let old = Task { await model.loadDirectory() }
        await fulfillment(of: [started], timeout: 2)
        service.afterDirectorySnapshot = nil
        _ = try await model.createClub(input: input)
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [service.id])
        resume?.resume(); await old.value
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [service.id])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(service.creationCount, 1)
    }

    func testLatePreCreationDirectoryErrorCannotReplaceConfirmedResult() async throws {
        let service = ClubCreationRefreshTestService(); service.failReads = true
        let started = expectation(description: "old failing read captured")
        var resume: CheckedContinuation<Void, Never>?
        service.afterDirectorySnapshot = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let model = ClubsViewModel(service: service)
        let old = Task { await model.loadDirectory() }
        await fulfillment(of: [started], timeout: 2)
        service.afterDirectorySnapshot = nil; service.failReads = false
        _ = try await model.createClub(input: input)
        resume?.resume(); await old.value
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [service.id])
        XCTAssertNil(model.errorMessage)
    }

    func testCreationRefreshFromPreviousAccountCannotPopulateNewAccount() async throws {
        let service = ClubCreationRefreshTestService()
        let started = expectation(description: "old account refresh")
        var resume: CheckedContinuation<Void, Never>?
        service.afterDirectorySnapshot = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let model = ClubsViewModel(service: service)
        let creation = Task { try await model.createClub(input: input) }
        await fulfillment(of: [started], timeout: 2)
        let replacement = ClubCreationRefreshTestService()
        model.configure(service: replacement)
        resume?.resume()
        do { _ = try await creation.value; XCTFail("Old-account receipt cannot confirm the new account's sheet") }
        catch { XCTAssertEqual(error as? CommunitySafetyError, .accountChanged) }
        XCTAssertEqual(model.directory, .empty)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(replacement.creationCount, 0)
        XCTAssertEqual(service.creationCount, 1)
    }

    func testLocalSaveRefreshFailureIsExplicitlyLocalAndCannotRepeat() async {
        let service = ClubCreationRefreshTestService(id: "local-synthetic-created"); service.failReads = true
        let model = ClubsViewModel(service: service)
        let form = ClubCreateViewModel(); form.name = input.name; form.purpose = input.purpose
        let dismiss = await form.submit { try await model.createClub(input: $0) }
        XCTAssertFalse(dismiss)
        XCTAssertTrue(form.savedLocally)
        XCTAssertTrue(model.errorMessage?.hasPrefix("이 기기에 클럽을 저장했지만") == true)
        let duplicate = await form.submit { try await model.createClub(input: $0) }
        XCTAssertFalse(duplicate)
        XCTAssertEqual(service.creationCount, 1)
    }

    func testOldCreationRefreshCannotEndNewerReadLoadingState() async throws {
        let service = ClubCreationRefreshTestService()
        let creationStarted = expectation(description: "creation read")
        let newerStarted = expectation(description: "newer read")
        var resumeCreation: CheckedContinuation<Void, Never>?
        var resumeNewer: CheckedContinuation<Void, Never>?
        var reads = 0
        service.afterDirectorySnapshot = {
            reads += 1
            if reads == 1 { await withCheckedContinuation { resumeCreation = $0; creationStarted.fulfill() } }
            else { await withCheckedContinuation { resumeNewer = $0; newerStarted.fulfill() } }
        }
        let model = ClubsViewModel(service: service)
        let creation = Task { try await model.createClub(input: input) }
        await fulfillment(of: [creationStarted], timeout: 2)
        let newer = Task { await model.loadDirectory() }
        await fulfillment(of: [newerStarted], timeout: 2)
        resumeCreation?.resume(); _ = try await creation.value
        XCTAssertTrue(model.isLoading)
        resumeNewer?.resume(); await newer.value
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [service.id])
    }

    func testOldAccountCreationCannotDismissNewAccountPresentation() async {
        let service = ClubCreationRefreshTestService()
        let started = expectation(description: "old form refresh")
        var resume: CheckedContinuation<Void, Never>?
        service.afterDirectorySnapshot = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let model = ClubsViewModel(service: service)
        let form = ClubCreateViewModel(); form.name = input.name; form.purpose = input.purpose
        let creation = Task { await form.submit { try await model.createClub(input: $0) } }
        await fulfillment(of: [started], timeout: 2)
        model.configure(service: ClubCreationRefreshTestService())
        resume?.resume()
        let dismiss = await creation.value
        XCTAssertFalse(dismiss)
        XCTAssertFalse(form.savedLocally)
        XCTAssertNotNil(form.errorMessage)
        XCTAssertEqual(model.directory, .empty)
        XCTAssertEqual(service.creationCount, 1)
    }

    func testPureCreationWriteFailureRetainsFormAndNeverClaimsSuccess() async {
        let service = ClubCreationRefreshTestService(); service.failCreate = true
        let model = ClubsViewModel(service: service)
        let form = ClubCreateViewModel(); form.name = input.name; form.purpose = input.purpose
        let dismiss = await form.submit { try await model.createClub(input: $0) }
        XCTAssertFalse(dismiss)
        XCTAssertFalse(service.stored)
        XCTAssertNotNil(form.errorMessage)
        XCTAssertTrue(form.canCreate)
        XCTAssertEqual(form.name, input.name)
        XCTAssertEqual(form.purpose, input.purpose)
        XCTAssertFalse(form.savedLocally)
        XCTAssertEqual(service.creationCount, 1)
    }
}

private final class ClubCreationRefreshTestService: ClubService {
    let id: String
    var stored = false
    var failReads = false
    var failCreate = false
    var creationCount = 0
    var afterDirectorySnapshot: (() async -> Void)?
    init(id: String = "0c170000-0000-4000-8000-000000000001") { self.id = id }
    private func detail() -> ClubDetail {
        ClubDetail(summary: ClubSummary(id: id, name: "Synthetic Created Club", sport: "걷기", memberCount: 1,
            weeklyRank: 0, contributionText: "", goalPercent: 0, tagline: ""), name: "Synthetic Created Club",
            intro: "Synthetic", purpose: "Synthetic", sport: "걷기", owner: "Synthetic", privacy: .open,
            activeMembersThisWeek: 0, rules: [], memberPreview: [], identityTags: [], membershipState: .owned,
            memberCount: 1, weeklyRank: 0, rankMovement: 0, contributionDistanceKm: 0, goalProgress: 0,
            ranking: [], challenges: [], badges: [], pulses: [])
    }
    func fetchClubDirectory() async throws -> ClubDirectorySnapshot {
        let fail = failReads
        let snapshot = ClubDirectorySnapshot(joinedClubs: [], createdClubs: stored ? [detail()] : [], recommendedClubs: [])
        await afterDirectorySnapshot?()
        if fail { throw ClubServiceError.clubNotFound }
        return snapshot
    }
    func createClub(input: ClubCreateInput) async throws -> ClubDomain {
        creationCount += 1
        if failCreate { throw ClubServiceError.clubNotFound }
        stored = true; return detail().club
    }
    func fetchClubDetail(clubId: String) async throws -> ClubDetail { detail() }
    func joinClub(clubId: String) async throws {}
    func leaveClub(clubId: String) async throws {}
    func fetchRankings(clubId: String, metric: ClubRankingMetric) async throws -> [ClubRankingEntry] { [] }
    func fetchChallenges(clubId: String) async throws -> [ClubChallenge] { [] }
}

@MainActor
final class ClubFallbackCreationRecoveryTests: XCTestCase {
    func testConfirmedInsertThenMembershipFailureNeverCreatesFallbackDuplicate() async throws {
        let remote = remote()
        remote.joinError = URLError(.networkConnectionLost)
        remote.afterCreate = { remote.directoryPayload = self.payload([remote.createdClubRow]) }
        let local = InMemoryClubService()
        let model = ClubsViewModel(service: resolver(remote, local: local))
        let form = form()
        let dismissed = await form.submit { try await model.createClub(input: $0) }
        XCTAssertTrue(dismissed)
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [createdID])
        XCTAssertEqual(remote.createdClubRequests.count, 1)
        XCTAssertEqual(remote.joinRequests.count, 1)
        let localDirectory = try await local.fetchClubDirectory()
        XCTAssertTrue(localDirectory.createdClubs.isEmpty)
        let repeated = await form.submit { try await model.createClub(input: $0) }
        XCTAssertFalse(repeated)
        XCTAssertEqual(remote.createdClubRequests.count, 1)
    }
    private let input = ClubCreateInput(name: "Synthetic Wrapper Club", purpose: "Synthetic recovery only", sportFocus: "걷기", visibility: .open)
    private let createdID = "0c170005-0000-4000-8000-000000000001"

    private func remote() -> FakeSupabaseClubRemoteClient {
        let remote = FakeSupabaseClubRemoteClient()
        remote.createdClubRow = row(id: createdID)
        remote.afterCreate = { [weak remote] in
            guard let remote else { return }
            remote.directoryPayload = self.payload([remote.createdClubRow])
            remote.directoryError = URLError(.notConnectedToInternet)
        }
        return remote
    }
    private func row(id: String) -> SupabaseClubRow {
        SupabaseClubRow(id: id, name: "Synthetic Wrapper Club", intro: nil, purpose: "Synthetic", sportFocus: "걷기", visibility: "open", ownerUserID: "current-user", createdAt: nil, updatedAt: nil)
    }
    private func payload(_ rows: [SupabaseClubRow]) -> SupabaseClubDirectoryPayload {
        SupabaseClubDirectoryPayload(clubs: rows, memberships: [], memberRows: [])
    }
    private func resolver(_ remote: FakeSupabaseClubRemoteClient, local: InMemoryClubService = InMemoryClubService()) -> any ClubService {
        ClubServiceResolver.makeService(remoteClient: remote, currentUserID: "current-user", fallback: local)
    }
    private func form() -> ClubCreateViewModel {
        let form = ClubCreateViewModel(); form.name = input.name; form.purpose = input.purpose
        return form
    }
    private func assertWarning(_ model: ClubsViewModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(model.errorMessage?.contains("클럽은 만들었지만") == true, file: file, line: line)
        XCTAssertTrue(model.errorMessage?.contains("클럽을 다시 만들 필요는 없어요") == true, file: file, line: line)
        XCTAssertFalse(model.isLoading, file: file, line: line)
    }

    func testEmptyLocalFallbackKeepsConfirmedReceiptWarningAndReadOnlyRetryUntilRecovery() async throws {
        let remote = remote(); let model = ClubsViewModel(service: resolver(remote)); let form = form()
        let dismiss = await form.submit { try await model.createClub(input: $0) }
        XCTAssertTrue(dismiss)
        XCTAssertTrue(model.directory.createdClubs.isEmpty)
        assertWarning(model)
        await model.loadDirectory() // Still offline: an empty fallback is not successful verification.
        assertWarning(model)
        XCTAssertTrue(model.directory.createdClubs.isEmpty)
        remote.directoryError = nil
        await model.loadDirectory()
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [createdID])
        XCTAssertNil(model.errorMessage)
        let repeatSubmit = await form.submit { try await model.createClub(input: $0) }
        XCTAssertFalse(repeatSubmit)
        XCTAssertEqual(remote.createdClubRequests.count, 1)
        XCTAssertEqual(remote.joinRequests.count, 1)
    }

    func testExistingLocalResultsSurviveRemoteCreateAndRepeatedFallbackRead() async throws {
        let remote = remote(); remote.directoryError = URLError(.notConnectedToInternet)
        let local = InMemoryClubService()
        let localClub = try await local.createClub(input: input)
        let model = ClubsViewModel(service: resolver(remote, local: local))
        await model.loadDirectory()
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [localClub.id])
        _ = try await model.createClub(input: input)
        assertWarning(model)
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [localClub.id])
        await model.loadDirectory()
        assertWarning(model)
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [localClub.id])
        remote.directoryError = nil; await model.loadDirectory()
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [createdID])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(remote.createdClubRequests.count, 1)
    }

    func testPreviouslyVerifiedRemoteResultsAreNotReplacedByLocalFallback() async throws {
        let remote = remote(); let priorID = "0c170005-0000-4000-8000-000000000002"
        remote.directoryPayload = payload([row(id: priorID)])
        let local = InMemoryClubService(); _ = try await local.createClub(input: input)
        let model = ClubsViewModel(service: resolver(remote, local: local))
        await model.loadDirectory()
        _ = try await model.createClub(input: input)
        assertWarning(model)
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [priorID])
        await model.loadDirectory()
        assertWarning(model)
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [priorID])
        remote.directoryError = nil; await model.loadDirectory()
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [createdID])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(remote.createdClubRequests.count, 1)
    }

    func testSuccessfulEmptyRemoteDirectoryIsDistinctFromFailedReadFallback() async throws {
        let remote = remote(); remote.afterCreate = nil
        let model = ClubsViewModel(service: resolver(remote)); let form = form()
        let dismiss = await form.submit { try await model.createClub(input: $0) }
        XCTAssertTrue(dismiss)
        XCTAssertEqual(model.directory, .empty)
        XCTAssertNotNil(model.errorMessage, "Confirmed insert missing from a successful read must be distinguished from save failure")
        await model.loadDirectory()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(remote.createdClubRequests.count, 1)
    }

    func testLatePreCreationFallbackCannotEraseRecoveredRemoteDirectory() async throws {
        let remote = remote(); remote.directoryError = URLError(.notConnectedToInternet)
        let started = expectation(description: "old remote failure captured")
        var resume: CheckedContinuation<Void, Never>?
        remote.afterDirectorySnapshot = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let model = ClubsViewModel(service: resolver(remote))
        let old = Task { await model.loadDirectory() }
        await fulfillment(of: [started], timeout: 2)
        remote.afterDirectorySnapshot = nil
        _ = try await model.createClub(input: input)
        assertWarning(model)
        remote.directoryError = nil; await model.loadDirectory()
        resume?.resume(); await old.value
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [createdID])
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(remote.createdClubRequests.count, 1)
    }

    func testPreviousAccountFallbackCompletionCannotDismissOrPopulateNewAccount() async {
        let remote = remote(); let started = expectation(description: "post-create failed remote read captured")
        var resume: CheckedContinuation<Void, Never>?
        remote.afterDirectorySnapshot = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let model = ClubsViewModel(service: resolver(remote)); let form = form()
        let creation = Task { await form.submit { try await model.createClub(input: $0) } }
        await fulfillment(of: [started], timeout: 2)
        let replacement = FakeSupabaseClubRemoteClient()
        model.configure(service: resolver(replacement))
        await model.loadDirectory()
        resume?.resume()
        let dismiss = await creation.value
        XCTAssertFalse(dismiss)
        XCTAssertEqual(model.directory, .empty)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(form.errorMessage)
        XCTAssertEqual(remote.createdClubRequests.count, 1)
        XCTAssertEqual(replacement.createdClubRequests.count, 0)
    }

    func testNewerReadDuringCreationRefreshRetainsWarningAndPriorRowsUntilRecovery() async throws {
        let remote = remote(); let priorID = "0c170005-0000-4000-8000-000000000004"
        remote.directoryPayload = payload([row(id: priorID)])
        let model = ClubsViewModel(service: resolver(remote))
        await model.loadDirectory()
        let started = expectation(description: "creation refresh captured after confirmed write")
        var resume: CheckedContinuation<Void, Never>?
        remote.afterDirectorySnapshot = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let creation = Task { try await model.createClub(input: input) }
        await fulfillment(of: [started], timeout: 2)
        remote.afterDirectorySnapshot = nil
        await model.loadDirectory()
        assertWarning(model)
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [priorID])
        remote.directoryError = nil; await model.loadDirectory()
        resume?.resume(); let receipt = try await creation.value
        XCTAssertEqual(receipt.id, createdID)
        XCTAssertEqual(model.directory.createdClubs.map(\.id), [createdID])
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(remote.createdClubRequests.count, 1)
    }

    func testPolicyRejectionDuringRecoveryClearsPreviouslyVerifiedRemoteRows() async throws {
        let remote = remote(); remote.directoryPayload = payload([row(id: "0c170005-0000-4000-8000-000000000003")])
        let model = ClubsViewModel(service: resolver(remote))
        await model.loadDirectory()
        _ = try await model.createClub(input: input)
        assertWarning(model)
        remote.directoryError = CommunitySafetyError.socialUnverified
        await model.loadDirectory()
        XCTAssertEqual(model.directory, .empty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(remote.createdClubRequests.count, 1)
    }
}


@MainActor
final class ClubInitialDirectoryFailureTests: XCTestCase {
    func testDeniedRemoteCreateNeverBecomesSuccessfulLocalSave() async throws {
        for failure: Error in [CommunitySafetyError.signInRequired, CommunitySafetyError.accountChanged,
            PostgrestError(code: "42501", message: "permission denied")] {
            let remote = FakeSupabaseClubRemoteClient(); remote.createError = failure
            let local = InMemoryClubService()
            let service = FallbackClubService(primary: SupabaseClubService(remoteClient: remote, currentUserID: "current-user"), fallback: local)
            let form = ClubCreateViewModel(); form.name = "Synthetic denied"; form.purpose = "Synthetic only"
            let closed = await form.submit { try await service.createClub(input: $0) }
            XCTAssertFalse(closed)
            XCTAssertFalse(form.savedLocally, "Permission/account failures must not masquerade as offline creation")
            XCTAssertNotNil(form.errorMessage)
            XCTAssertTrue(form.canCreate)
            let stored = try await local.fetchClubDirectory()
            XCTAssertTrue(stored.createdClubs.isEmpty)
            XCTAssertEqual(remote.createdClubRequests.count, 1)
        }
    }

    func testInitialDeniedDirectoryRemainsEmptyAndExplainsAccessFailure() async {
        let remote = FakeSupabaseClubRemoteClient()
        remote.directoryError = PostgrestError(code: "42501", message: "permission denied")
        let local = InMemoryClubService(details: InMemoryClubService.seedDetails)
        let model = ClubsViewModel(service: FallbackClubService(primary: SupabaseClubService(remoteClient: remote, currentUserID: "current-user"), fallback: local))
        await model.loadDirectory()
        XCTAssertEqual(model.directory, .empty)
        XCTAssertTrue(model.errorMessage?.contains("접근 권한") == true)
        XCTAssertFalse(model.isShowingLocalFallbackData)
        XCTAssertFalse(model.isLoading)
        remote.directoryError = nil
        await model.loadDirectory()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.directory, .empty, "An authoritative empty response is distinct from a read failure")
    }
}


extension ClubInitialDirectoryFailureTests {
    func testReadRetryRecoversConfirmedLocalReceiptWithoutAnotherCreate() async throws {
        let remote = FakeSupabaseClubRemoteClient()
        remote.directoryError = PostgrestError(code: "42501", message: "permission denied")
        remote.createError = URLError(.notConnectedToInternet)
        let local = InMemoryClubService()
        let model = ClubsViewModel(service: FallbackClubService(primary: SupabaseClubService(remoteClient: remote, currentUserID: "current-user"), fallback: local))
        await model.loadDirectory()
        let form = ClubCreateViewModel(); form.name = "Synthetic local receipt"; form.purpose = "Synthetic only"
        let closed = await form.submit { try await model.createClub(input: $0) }
        XCTAssertFalse(closed); XCTAssertTrue(form.savedLocally)
        XCTAssertTrue(model.directory.createdClubs.isEmpty)
        remote.directoryError = URLError(.notConnectedToInternet)
        await model.loadDirectory()
        XCTAssertEqual(model.directory.createdClubs.count, 1)
        XCTAssertTrue(model.shouldShowLocalFallbackBanner)
        XCTAssertNotNil(model.errorMessage, "Local receipt recovery is not remote directory recovery")
        XCTAssertEqual(remote.createdClubRequests.count, 1)
        XCTAssertTrue(remote.joinRequests.isEmpty)
    }
}

@MainActor
final class ClubRequestFailureClassificationTests: XCTestCase {
    private func exercise(_ error: Error) async -> (ClubCreateViewModel, FakeSupabaseClubRemoteClient, InMemoryClubService) {
        let remote = FakeSupabaseClubRemoteClient(); remote.createError = error
        let local = InMemoryClubService()
        let service = FallbackClubService(primary: SupabaseClubService(remoteClient: remote, currentUserID: "current-user"), fallback: local)
        let form = ClubCreateViewModel(); form.name = "Synthetic draft"; form.purpose = "Synthetic only"
        let closed = await form.submit { try await service.createClub(input: $0) }
        XCTAssertFalse(closed)
        XCTAssertEqual(form.name, "Synthetic draft")
        XCTAssertEqual(form.purpose, "Synthetic only")
        XCTAssertFalse(form.isSubmitting)
        return (form, remote, local)
    }

    func testPermissionDenialIsNotReportedAsConnectionFailure() async {
        let (form, _, local) = await exercise(PostgrestError(code: "42501", message: "private backend detail"))
        XCTAssertTrue(form.errorMessage?.contains("권한") == true)
        XCTAssertFalse(form.errorMessage?.contains("연결 상태") == true)
        XCTAssertFalse(form.errorMessage?.contains("private backend detail") == true)
        XCTAssertFalse(form.savedLocally)
        XCTAssertTrue(form.canCreate)
        let localSnapshot = try? await local.fetchClubDirectory()
        XCTAssertTrue(localSnapshot?.createdClubs.isEmpty == true)
    }

    func testMissingSDKSessionNeverBecomesLocalCreation() async {
        let (form, _, local) = await exercise(Supabase.AuthError.sessionMissing)
        XCTAssertTrue(form.errorMessage?.contains("로그인") == true)
        XCTAssertFalse(form.savedLocally)
        let localSnapshot = try? await local.fetchClubDirectory()
        XCTAssertTrue(localSnapshot?.createdClubs.isEmpty == true)
    }

    func testServerSchemaFailureNeverBecomesLocalCreation() async {
        for code in ["42P01", "42703", "42P17", "PGRST204"] {
            let (form, _, local) = await exercise(PostgrestError(code: code, message: "private schema body"))
            XCTAssertTrue(form.errorMessage?.contains("서버") == true, code)
            XCTAssertFalse(form.errorMessage?.contains("연결 상태") == true, code)
            XCTAssertFalse(form.savedLocally, code)
            XCTAssertFalse(form.errorMessage?.contains("private schema body") == true)
            let localSnapshot = try? await local.fetchClubDirectory()
        XCTAssertTrue(localSnapshot?.createdClubs.isEmpty == true)
        }
    }

    func testUncertainCreateRetainsDraftAndDoesNotInviteDuplicateSubmission() async {
        let remote = FakeSupabaseClubRemoteClient(); remote.createError = URLError(.timedOut)
        let local = InMemoryClubService()
        let service = FallbackClubService(primary: SupabaseClubService(remoteClient: remote, currentUserID: "current-user"), fallback: local)
        let form = ClubCreateViewModel(); form.name = "Synthetic timeout"; form.purpose = "Synthetic only"
        let first = await form.submit { try await service.createClub(input: $0) }
        XCTAssertFalse(first)
        XCTAssertFalse(form.savedLocally)
        XCTAssertTrue(form.errorMessage?.contains("목록") == true)
        XCTAssertFalse(form.canCreate)
        _ = await form.submit { try await service.createClub(input: $0) }
        XCTAssertEqual(remote.createdClubRequests.count, 1)
        let localSnapshot = try? await local.fetchClubDirectory()
        XCTAssertTrue(localSnapshot?.createdClubs.isEmpty == true)
    }

    func testActualOfflineSaveRemainsExplicitlyLocal() async {
        let (form, _, local) = await exercise(URLError(.notConnectedToInternet))
        XCTAssertTrue(form.savedLocally)
        let localSnapshot = try? await local.fetchClubDirectory()
        XCTAssertEqual(localSnapshot?.createdClubs.count, 1)
    }

    func testServerDirectoryFailureIsNotHiddenBehindEmptyLocalFallback() async {
        let remote = FakeSupabaseClubRemoteClient(); remote.directoryError = PostgrestError(code: "42P01", message: "private relation")
        let model = ClubsViewModel(service: FallbackClubService(primary: SupabaseClubService(remoteClient: remote, currentUserID: "current-user"), fallback: InMemoryClubService()))
        await model.loadDirectory()
        XCTAssertTrue(model.directory.createdClubs.isEmpty)
        XCTAssertTrue(model.errorMessage?.contains("서버") == true)
        XCTAssertFalse(model.isShowingLocalFallbackData)
        XCTAssertFalse(model.isLoading)
    }
}
