import XCTest
@testable import SOOM

final class NotificationRecommendationPolicyTests: XCTestCase {
    private let owner = UUID()
    private func person(_ id: UUID = UUID(), following: Bool = false, pending: Bool = false) -> SocialPerson {
        SocialPerson(id: id, displayName: "합성 사용자", handle: nil, avatarPath: nil,
                     followedAt: Date(), isFollowing: following, followsViewer: true,
                     approvedState: pending ? .pending : .none, approvedAccountScope: "private")
    }
    func testNoSelfOrExistingFollowingAndDeduplicates() {
        let candidate = person()
        let result = NotificationRecommendationPolicy.candidates(
            [person(owner), person(following: true), candidate, candidate],
            ownerID: owner, hidden: [], blocked: [])
        XCTAssertEqual(result.map(\.id), [candidate.id])
    }
    func testHiddenAndBlockedAreExcluded() {
        let hidden = person(), blocked = person(), visible = person()
        XCTAssertEqual(NotificationRecommendationPolicy.candidates([hidden, blocked, visible], ownerID: owner,
            hidden: [hidden.id], blocked: [blocked.id]).map(\.id), [visible.id])
    }
    func testPendingKeepsCancelRequestAndNeverUnfollow() {
        let pending = person(pending: true)
        let result = NotificationRecommendationPolicy.candidates([pending], ownerID: owner, hidden: [], blocked: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.actionTitle(viewerID: owner), "요청 취소")
    }
    func testPrivatePersonRequestsApproval() {
        XCTAssertEqual(person().actionTitle(viewerID: owner), "팔로우 요청")
    }
    func testEmptyOrFailedReadCannotFabricateRecommendations() {
        XCTAssertTrue(NotificationRecommendationPolicy.candidates([], ownerID: owner, hidden: [], blocked: []).isEmpty)
    }
    func testHideDoesNotMutateRelationshipAndNewScopeHasNoHiddenIDs() {
        let row = person()
        XCTAssertTrue(NotificationRecommendationPolicy.candidates([row], ownerID: owner, hidden: [row.id], blocked: []).isEmpty)
        XCTAssertFalse(row.isFollowing)
        XCTAssertEqual(NotificationRecommendationPolicy.candidates([row], ownerID: UUID(), hidden: [], blocked: []).count, 1)
    }
}

@MainActor
private final class RecommendationTestService: ProfileSocialServing {
    var viewerID: UUID?
    var rows: [SocialPerson] = []
    var failRead = false
    var holdWrite = false
    var writeCalls: [Bool] = []
    var continuation: CheckedContinuation<Void, Never>?
    init(owner: UUID) { viewerID = owner }
    func summary(ownerID: UUID) async throws -> SocialSummary {
        if failRead { throw CommunitySafetyError.unavailable }
        return SocialSummary(postCount: 0, followerCount: rows.count, followingCount: 0)
    }
    func people(ownerID: UUID, kind: SocialPeopleKind, after: SocialPerson?, limit: Int) async throws -> [SocialPerson] {
        if failRead { throw CommunitySafetyError.unavailable }
        return after == nil ? rows : []
    }
    func setFollowing(_ enabled: Bool, userID: UUID) async throws -> Bool {
        writeCalls.append(enabled)
        if holdWrite { await withCheckedContinuation { continuation = $0 } }
        for index in rows.indices where rows[index].id == userID {
            rows[index].approvedState = enabled ? .pending : ApprovedFollowState.none
            rows[index].isFollowing = false
        }
        return enabled
    }
}

@MainActor
final class NotificationRecommendationInteractionTests: XCTestCase {
    private func row(pending: Bool = false) -> SocialPerson {
        SocialPerson(id: UUID(), displayName: "합성 후보", handle: nil, avatarPath: nil,
                     followedAt: Date(), isFollowing: false, followsViewer: true,
                     approvedState: pending ? .pending : ApprovedFollowState.none, approvedAccountScope: "private")
    }
    func testRepeatedTapOnlyWritesOnceAndPendingIsRefetched() async {
        let owner = UUID(), person = row()
        let service = RecommendationTestService(owner: owner); service.rows = [person]; service.holdWrite = true
        let safety = CommunitySafetyStore(client: nil, viewerID: owner)
        let model = ProfileSocialModel(ownerID: owner, service: service, safety: safety)
        await model.load(kind: .followers)
        let task = Task { await model.toggle(person) }
        for _ in 0..<10000 {
            if service.continuation != nil { break }
            await Task.yield()
        }
        guard service.continuation != nil else {
            task.cancel(); XCTFail("합성 쓰기가 시작되지 않았어요"); return
        }
        await model.toggle(person)
        XCTAssertEqual(service.writeCalls, [true])
        service.continuation?.resume(); await task.value
        XCTAssertEqual(model.people.first?.approvedState, .pending)
        XCTAssertTrue(model.busyIDs.isEmpty)
    }
    func testPendingCancellationSendsFalseAndRetainsFollowerCandidate() async {
        let owner = UUID(), person = row(pending: true)
        let service = RecommendationTestService(owner: owner); service.rows = [person]
        let model = ProfileSocialModel(ownerID: owner, service: service,
            safety: CommunitySafetyStore(client: nil, viewerID: owner))
        await model.load(kind: .followers); await model.toggle(person)
        XCTAssertEqual(service.writeCalls, [false])
        XCTAssertEqual(model.people.first?.approvedState, ApprovedFollowState.none)
        XCTAssertEqual(model.people.count, 1)
    }
    func testReadFailureThenRetryDoesNotWriteRelationships() async {
        let owner = UUID(); let service = RecommendationTestService(owner: owner)
        service.rows = [row()]; service.failRead = true
        let model = ProfileSocialModel(ownerID: owner, service: service,
            safety: CommunitySafetyStore(client: nil, viewerID: owner))
        await model.load(kind: .followers)
        XCTAssertTrue(model.people.isEmpty); XCTAssertNotNil(model.errorMessage)
        service.failRead = false; await model.load(kind: .followers)
        XCTAssertEqual(model.people.count, 1); XCTAssertNil(model.errorMessage)
        XCTAssertTrue(service.writeCalls.isEmpty)
    }
    func testAccountSwitchDuringWriteRejectsReturnedOldAccountRows() async {
        let owner = UUID(), person = row()
        let service = RecommendationTestService(owner: owner); service.rows = [person]; service.holdWrite = true
        let safety = CommunitySafetyStore(client: nil, viewerID: owner)
        let model = ProfileSocialModel(ownerID: owner, service: service, safety: safety)
        await model.load(kind: .followers)
        let task = Task { await model.toggle(person) }
        for _ in 0..<10000 {
            if service.continuation != nil { break }
            await Task.yield()
        }
        guard service.continuation != nil else {
            task.cancel(); XCTFail("합성 쓰기가 시작되지 않았어요"); return
        }
        safety.setViewerID(UUID())
        service.continuation?.resume(); await task.value
        XCTAssertTrue(model.people.isEmpty)
        await model.toggle(person)
        XCTAssertEqual(service.writeCalls.count, 1)
    }
}
