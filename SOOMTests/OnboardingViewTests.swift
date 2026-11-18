import XCTest
import SwiftUI
import Combine
import Supabase
@testable import SOOM

final class OnboardingViewTests: XCTestCase {
    func testStepsAreFiveStepsWithNonEmptyCopy() {
        let steps = OnboardingStep.all

        XCTAssertEqual(steps.count, 5)
        steps.forEach { step in
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.message.isEmpty)
            XCTAssertFalse(step.iconName.isEmpty)
        }
    }

    func testStepsHaveUniqueSequentialIds() {
        let steps = OnboardingStep.all

        XCTAssertEqual(steps.map(\.id), [0, 1, 2, 3, 4])
    }

    func testPermissionStepsSitBetweenExplanationSteps() {
        let steps = OnboardingStep.all

        XCTAssertEqual(steps.map(\.kind), [
            .explanation,
            .explanation,
            .healthKitPermission,
            .locationPermission,
            .explanation
        ])
    }

    func testLastStepIntroducesGuestModeWithoutForcingSignIn() {
        guard let lastStep = OnboardingStep.all.last else {
            return XCTFail("Expected at least one onboarding step")
        }

        XCTAssertEqual(lastStep.kind, .explanation)
        XCTAssertTrue(lastStep.message.contains("로그인") || lastStep.title.contains("로그인"))
    }

    func testPermissionStepsMentionThatSkippingIsSafe() {
        let permissionSteps = OnboardingStep.all.filter { $0.kind != .explanation }

        XCTAssertEqual(permissionSteps.count, 2)
        permissionSteps.forEach { step in
            XCTAssertTrue(
                step.message.contains("나중") || step.message.contains("언제든"),
                "Permission step '\(step.title)' should make clear skipping now is safe"
            )
        }
    }
}

@MainActor
private final class PrivacySelectionFakeService: AccountPrivacyServing {
    var viewerID: UUID?
    var receipt = AccountPrivacyReceipt(enabled:true,accountScope:nil,workoutDefault:nil,revision:0,shareMeasurements:false)
    var failSave = false
    var failLoad = false
    var switchDuringSave = false
    var saves = 0
    var fetches = 0
    var delaySave = false
    var delayLoad = false
    var responsePolicyVersion: Int?
    init(owner:UUID) { viewerID = owner }
    func fetch() async throws -> AccountPrivacyReceipt {
        fetches += 1
        if delayLoad { try await Task.sleep(nanoseconds:50_000_000) }
        if failLoad { throw CommunitySafetyError.unavailable }
        return receipt
    }
    func withdrawMeasurements(owner:UUID,profileRevision:Int64,measurementRevision:Int64) async throws -> AccountPrivacyReceipt {
        saves += 1
        if failSave {throw CommunitySafetyError.unavailable}
        if switchDuringSave {viewerID=UUID()}
        guard receipt.revision==profileRevision,receipt.measurementRevision==measurementRevision else {throw ProfileOnlyPrivacyError.changeNotConfirmed}
        receipt.shareMeasurements=false;receipt.measurementRevision=measurementRevision+1
        return receipt
    }
    func save(owner:UUID,scope:AccountAudience,defaultWorkout:FeedPostVisibility,expectedRevision:Int64,shareMeasurements:Bool) async throws -> AccountPrivacyReceipt {
        saves += 1
        if delaySave { try await Task.sleep(nanoseconds:50_000_000) }
        if switchDuringSave { viewerID = UUID() }
        if failSave { throw CommunitySafetyError.unavailable }
        receipt = .init(enabled:true,accountScope:scope,workoutDefault:defaultWorkout,revision:expectedRevision+1,shareMeasurements:shareMeasurements,
                        policyVersion:responsePolicyVersion ?? receipt.policyVersion)
        return receipt
    }
}
extension OnboardingViewTests {
    @MainActor func testConcurrentPrivacyRechecksShareOneReadAndResumeStillRevalidates() async {
        let owner = UUID(), service = PrivacySelectionFakeService(owner: UUID())
        service.viewerID = owner; service.delayLoad = true
        service.receipt = .init(enabled: true, accountScope: .privateAccount, workoutDefault: .followers, revision: 1)
        let model = AccountPrivacyModel(owner: owner, service: service, profileOnlyRules: false)
        async let first: Void = model.load()
        async let duplicate: Void = model.load()
        _ = await (first, duplicate)
        XCTAssertEqual(service.fetches, 1)
        XCTAssertTrue(model.canContinue)
        model.suspendSocialAccess()
        XCTAssertFalse(model.canContinue)
        await model.load()
        XCTAssertEqual(service.fetches, 2)
        XCTAssertTrue(model.canContinue)
        UserDefaults.standard.removeObject(forKey: "SOOM.workoutAudience.v1.\(owner.uuidString.lowercased())")
    }
    @MainActor func testNoPrivacyChoiceOrReadFailureNeverUnlocksAccount() async {
        let owner = UUID(); let service = PrivacySelectionFakeService(owner:owner)
        let model = AccountPrivacyModel(owner:owner,service:service, profileOnlyRules: false)
        XCTAssertFalse(model.canContinue); await model.load()
        XCTAssertFalse(model.canContinue); XCTAssertNil(model.selection)
        await model.save(); XCTAssertEqual(service.saves,0)
        service.failLoad = true; await model.load()
        XCTAssertFalse(model.canContinue); XCTAssertNil(model.receipt)
    }
    @MainActor func testExplicitPrivateChoiceAndIndependentMeasurementConsent() async {
        let owner = UUID(); defer { UserDefaults.standard.removeObject(forKey:"SOOM.workoutAudience.v1.\(owner.uuidString.lowercased())") }
        let service = PrivacySelectionFakeService(owner:owner); let model = AccountPrivacyModel(owner:owner,service:service, profileOnlyRules: false)
        await model.load(); model.selection = .privateAccount
        XCTAssertFalse(model.shareMeasurements)
        await model.save()
        XCTAssertTrue(model.canContinue)
        XCTAssertEqual(model.receipt?.workoutDefault,.followers)
        XCTAssertEqual(model.receipt?.shareMeasurements,false)
        XCTAssertEqual(UserDefaults.standard.string(forKey:"SOOM.workoutAudience.v1.\(owner.uuidString.lowercased())"),"followers")
    }
    @MainActor func testPrivacySaveFailureRequiresFreshReentry() async {
        let owner = UUID(); let service = PrivacySelectionFakeService(owner:owner); let model = AccountPrivacyModel(owner:owner,service:service, profileOnlyRules: false)
        await model.load(); model.selection = .publicAccount; service.failSave = true
        await model.save(); XCTAssertFalse(model.canContinue); XCTAssertNil(model.receipt)
        XCTAssertNotNil(model.errorMessage)
        service.failSave = false; await model.load()
        XCTAssertNil(model.selection); XCTAssertFalse(model.canContinue)
    }
    @MainActor func testAccountSwitchDuringSaveCannotUnlockOrPersistOtherAccount() async {
        let owner = UUID(); let service = PrivacySelectionFakeService(owner:owner); let model = AccountPrivacyModel(owner:owner,service:service, profileOnlyRules: false)
        await model.load(); model.selection = .publicAccount; service.switchDuringSave = true
        await model.save(); XCTAssertFalse(model.canContinue)
        XCTAssertNil(UserDefaults.standard.string(forKey:"SOOM.workoutAudience.v1.\(owner.uuidString.lowercased())"))
        await model.load(); XCTAssertFalse(model.canContinue); XCTAssertNil(model.receipt)
    }
    @MainActor func testInterruptedPrivacyTaskDoesNotAdoptSuccessfulRead() async {
        let owner = UUID(); let service = PrivacySelectionFakeService(owner:owner)
        service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1,shareMeasurements:true)
        let model = AccountPrivacyModel(owner:owner,service:service, profileOnlyRules: false)
        let task = Task { await model.load() }; task.cancel(); await task.value
        XCTAssertFalse(model.canContinue); XCTAssertNil(model.receipt)
    }
}

extension OnboardingViewTests {
    @MainActor func testDuplicatePrivacySaveCreatesOneConfirmedChoice() async {
        let owner=UUID(), service=PrivacySelectionFakeService(owner:UUID())
        service.viewerID=owner;service.delaySave=true
        let model=AccountPrivacyModel(owner:owner,service:service, profileOnlyRules: false)
        await model.load();model.selection = .privateAccount
        let first=Task{ await model.save() }
        await Task.yield();await model.save();await first.value
        XCTAssertEqual(service.saves,1);XCTAssertTrue(model.canContinue)
        XCTAssertEqual(model.receipt?.accountScope,.privateAccount)
        XCTAssertEqual(model.receipt?.shareMeasurements,false)
    }
}

@MainActor
final class LocalSocialAccessGateTests: XCTestCase {
    func testVerifiedReceiptLossOnOffFailureAndReconnectRequiresFreshRead() async {
        let owner=UUID(), state=CommunitySafetyStore(client:nil,viewerID:nil,requiresSocialVerification:true)
        state.setViewerID(owner)
        let service=PrivacySelectionFakeService(owner:owner)
        service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1)
        let model=AccountPrivacyModel(owner:owner,service:service,socialState:state, profileOnlyRules: false)
        await model.load();XCTAssertTrue(state.canUseSocial)
        service.receipt = .init(enabled:false,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1)
        await model.load();XCTAssertFalse(state.canUseSocial)
        service.failLoad=true;await model.load();XCTAssertFalse(state.canUseSocial)
        service.failLoad=false;service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1)
        await model.load();XCTAssertTrue(state.canUseSocial)
        model.setNetworkAvailable(false);XCTAssertFalse(state.canUseSocial);XCTAssertNil(model.receipt)
        model.selection = .publicAccount;await model.save();XCTAssertEqual(service.saves,0)
        model.setNetworkAvailable(true);XCTAssertFalse(state.canUseSocial)
        await model.load();XCTAssertTrue(state.canUseSocial)
    }
    func testUnselectedOrIncompleteOnboardingNeverGrantsSocialOrWritesChoice() async {
        let owner=UUID(),state=CommunitySafetyStore(client:nil,requiresSocialVerification:true)
        state.setViewerID(owner)
        let service=PrivacySelectionFakeService(owner:owner)
        let model=AccountPrivacyModel(owner:owner,service:service,socialState:state, profileOnlyRules: false)
        await model.load();XCTAssertFalse(state.canUseSocial);XCTAssertNil(model.selection)
        service.receipt = .init(enabled:true,accountScope:.privateAccount,workoutDefault:.followers,revision:1)
        model.setOnboardingComplete(false);await model.load();XCTAssertFalse(state.canUseSocial)
        await model.save();XCTAssertEqual(service.saves,0)
        model.setOnboardingComplete(true);XCTAssertFalse(state.canUseSocial)
        await model.load();XCTAssertTrue(state.canUseSocial)
    }
    func testLateReadAfterOfflineCannotUnlock() async {
        let owner=UUID(),state=CommunitySafetyStore(client:nil,requiresSocialVerification:true)
        state.setViewerID(owner)
        let service=PrivacySelectionFakeService(owner:owner);service.delayLoad=true
        service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1)
        let model=AccountPrivacyModel(owner:owner,service:service,socialState:state, profileOnlyRules: false)
        let flight=Task { await model.load() };await Task.yield();model.setNetworkAvailable(false)
        await flight.value;XCTAssertNil(model.receipt);XCTAssertFalse(state.canUseSocial)
    }
    func testLateReadAfterAccountAToBToARequiresNewVerification() async {
        let owner=UUID(),state=CommunitySafetyStore(client:nil,requiresSocialVerification:true)
        state.setViewerID(owner)
        let service=PrivacySelectionFakeService(owner:owner);service.delayLoad=true
        service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1)
        let model=AccountPrivacyModel(owner:owner,service:service,socialState:state, profileOnlyRules: false)
        let flight=Task { await model.load() };await Task.yield()
        state.setViewerID(UUID());state.setViewerID(owner)
        await flight.value;XCTAssertFalse(state.canUseSocial);XCTAssertNil(model.receipt)
        service.delayLoad=false;await model.load();XCTAssertTrue(state.canUseSocial)
    }
    func testUnverifiedSharingAndLegacyRejectionHaveSafeUserMessages() {
        XCTAssertTrue(CommunitySafetyError.isPolicyRejection(CommunitySafetyError.socialUnverified))
        let error=NSError(domain:"PostgREST",code:42501,userInfo:[NSLocalizedDescriptionKey:"New client required"])
        XCTAssertTrue(CommunitySafetyError.isPolicyRejection(error))
        XCTAssertTrue(CommunitySafetyError.message(for:error).contains("업데이트"))
        XCTAssertTrue(CommunitySafetyError.message(for:error).contains("원본"))
    }
}

@MainActor
private final class LegacyReviewTestService: LegacyFollowerReviewServing {
    var viewerID: UUID?
    var available = true
    var failRead = false
    var holdRead = false
    var holdReview = false
    var readContinuation: CheckedContinuation<[LegacyFollowerCandidate], Never>?
    var reviewContinuation: CheckedContinuation<Void, Never>?
    var availabilityQueries = 0
    var candidateQueries = 0
    var writes: [(UUID, LegacyFollowerReviewAction)] = []
    var raw: [LegacyFollowerCandidate]
    var reviewed = Set<UUID>()
    var approved = Set<UUID>()
    init(owner: UUID, count: Int = 2) {
        viewerID = owner
        raw = (0..<count).map { index in .init(userID: UUID(), edgeID: UUID(), displayName: "Old follower \(index)",
            handle: nil, avatarPath: nil, followedAt: Date(timeIntervalSince1970: Double(100-index))) }
    }
    func legacyReviewEnabled(owner: UUID) async throws -> Bool { availabilityQueries += 1; return available }
    func legacyCandidates(owner: UUID, after: LegacyFollowerCandidate?) async throws -> [LegacyFollowerCandidate] {
        candidateQueries += 1
        if failRead { throw CommunitySafetyError.unavailable }
        if holdRead { return await withCheckedContinuation { readContinuation = $0 } }
        let offset = after.flatMap { value in raw.firstIndex(where: { $0.edgeID == value.edgeID }) }.map { $0 + 1 } ?? 0
        return Array(raw.dropFirst(offset).filter { !reviewed.contains($0.edgeID) }.prefix(50))
    }
    func reviewLegacy(_ candidate: LegacyFollowerCandidate, owner: UUID, action: LegacyFollowerReviewAction) async throws {
        if holdReview { await withCheckedContinuation { reviewContinuation = $0 } }
        writes.append((candidate.edgeID, action)); reviewed.insert(candidate.edgeID)
        if action == .approve { approved.insert(candidate.userID) }
    }
}

final class LegacyFollowerReviewTests: XCTestCase {
    @MainActor private func safety(_ owner: UUID) -> CommunitySafetyStore {
        let store = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
        store.setSocialVerified(true, owner: owner)
        return store
    }
    @MainActor func testCandidateReadDoesNotApproveAndOnlyExplicitSelectedCandidateChangesState() async {
        let owner = UUID(); let service = LegacyReviewTestService(owner: owner); let store = safety(owner)
        let model = LegacyFollowerReviewModel(owner: owner, service: service, safety: store)
        let originals = service.raw
        await model.load()
        XCTAssertEqual(model.candidates, originals); XCTAssertTrue(service.approved.isEmpty); XCTAssertTrue(service.writes.isEmpty)
        let unknown = LegacyFollowerCandidate(userID: UUID(), edgeID: UUID(), displayName: "Not listed", handle: nil, avatarPath: nil, followedAt: Date())
        await model.review(unknown, action: .approve); XCTAssertTrue(service.writes.isEmpty)
        await model.review(originals[0], action: .approve)
        XCTAssertEqual(service.approved, [originals[0].userID]); XCTAssertEqual(service.writes.count, 1)
        XCTAssertEqual(model.candidates, [originals[1]])
        await model.review(originals[0], action: .approve); XCTAssertEqual(service.writes.count, 1)
        await model.review(originals[1], action: .dismiss)
        XCTAssertEqual(service.writes.count, 2); XCTAssertEqual(service.approved.count, 1)
        XCTAssertEqual(service.raw, originals, "Dismiss/approve must preserve original raw graph")
        XCTAssertTrue(model.candidates.isEmpty)
    }
    @MainActor func testDisabledFeatureDoesNotQueryOrApproveRawGraph() async {
        let owner = UUID(); let service = LegacyReviewTestService(owner: owner); service.available = false
        let model = LegacyFollowerReviewModel(owner: owner, service: service, safety: safety(owner))
        await model.load(); await model.review(service.raw[0], action: .approve)
        XCTAssertFalse(model.enabled); XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertEqual(service.candidateQueries, 0); XCTAssertTrue(service.writes.isEmpty)
    }
    @MainActor func testUnverifiedSocialAndDifferentOwnerMakeNoCalls() async {
        let owner = UUID(); let service = LegacyReviewTestService(owner: owner); let store = safety(owner)
        store.setSocialVerified(false, owner: owner)
        let model = LegacyFollowerReviewModel(owner: owner, service: service, safety: store)
        await model.load(); await model.review(service.raw[0], action: .approve)
        XCTAssertEqual(service.availabilityQueries, 0); XCTAssertTrue(service.writes.isEmpty)
        store.setSocialVerified(true, owner: owner); service.viewerID = UUID()
        await model.load(); XCTAssertEqual(service.availabilityQueries, 0)
    }
    @MainActor func testReadFailureClearsOldCandidatesAndGrantsNoApproval() async {
        let owner = UUID(); let service = LegacyReviewTestService(owner: owner)
        let model = LegacyFollowerReviewModel(owner: owner, service: service, safety: safety(owner))
        await model.load(); XCTAssertFalse(model.candidates.isEmpty)
        service.failRead = true; await model.load()
        XCTAssertTrue(model.candidates.isEmpty); XCTAssertFalse(model.enabled); XCTAssertNotNil(model.errorMessage)
        await model.review(service.raw[0], action: .approve); XCTAssertTrue(service.writes.isEmpty)
    }
    @MainActor func testLateCandidateReadAfterRevisionChangeIsDiscarded() async throws {
        let owner = UUID(); let service = LegacyReviewTestService(owner: owner); let store = safety(owner)
        let model = LegacyFollowerReviewModel(owner: owner, service: service, safety: store)
        service.holdRead = true; let task = Task { await model.load() }
        for _ in 0..<100 where service.readContinuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(service.readContinuation)
        store.invalidateRelationships(); continuation.resume(returning: service.raw); await task.value
        XCTAssertTrue(model.candidates.isEmpty); XCTAssertFalse(model.enabled); XCTAssertFalse(model.loading)
    }
    @MainActor func testLateCandidateReadFromAccountABAIsDiscarded() async throws {
        let owner = UUID(); let service = LegacyReviewTestService(owner: owner); let store = safety(owner)
        let model = LegacyFollowerReviewModel(owner: owner, service: service, safety: store)
        service.holdRead = true; let task = Task { await model.load() }
        for _ in 0..<100 where service.readContinuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(service.readContinuation)
        store.setViewerID(UUID()); store.setViewerID(owner); store.setSocialVerified(true, owner: owner)
        continuation.resume(returning: service.raw); await task.value
        XCTAssertTrue(model.candidates.isEmpty); XCTAssertFalse(model.enabled)
    }
    @MainActor func testLateApprovalResponseCannotUnlockAfterSocialVerificationLost() async throws {
        let owner = UUID(); let service = LegacyReviewTestService(owner: owner); let store = safety(owner)
        let model = LegacyFollowerReviewModel(owner: owner, service: service, safety: store)
        await model.load(); service.holdReview = true
        let task = Task { await model.review(service.raw[0], action: .approve) }
        for _ in 0..<100 where service.reviewContinuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(service.reviewContinuation)
        store.setSocialVerified(false, owner: owner); continuation.resume(); await task.value
        XCTAssertFalse(store.canUseSocial); XCTAssertFalse(model.enabled); XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertTrue(model.busyIDs.isEmpty)
    }
    @MainActor func testHistoricCandidatePaginationUsesServerIdentityAndDoesNotFilterByAge() async {
        let owner = UUID(); let service = LegacyReviewTestService(owner: owner, count: 51)
        let model = LegacyFollowerReviewModel(owner: owner, service: service, safety: safety(owner))
        await model.load(); XCTAssertEqual(model.candidates.count, 50); XCTAssertTrue(model.hasMore)
        await model.load(reset: false); XCTAssertEqual(model.candidates.count, 51); XCTAssertFalse(model.hasMore)
        XCTAssertTrue(model.candidates.allSatisfy { $0.followedAt < Date(timeIntervalSince1970: 1000) })
        XCTAssertTrue(service.writes.isEmpty)
    }
}

@MainActor
private final class PrivacyConnectivityTestState: ObservableObject {
    @Published var online: Bool? = false
    @Published var unrelatedRevision = 0
}

private struct PrivacyConnectivityTestHost: View {
    @ObservedObject var state: PrivacyConnectivityTestState
    @ObservedObject var model: AccountPrivacyModel
    var body: some View {
        Text("Personal content \(state.unrelatedRevision) \(model.busy)")
            .modifier(AccountPrivacyConnectivityModifier(model: model, isOnline: state.online))
    }
}

@MainActor
final class AccountPrivacyConnectivityLifecycleTests: XCTestCase {
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 120_000_000)
    }

    func testOfflineMountedContentSettlesWithoutRepeatedModelPublications() async throws {
        let owner = UUID(), service = PrivacySelectionFakeService(owner: UUID())
        service.viewerID = owner
        let model = AccountPrivacyModel(owner: owner, service: service, profileOnlyRules: false)
        let state = PrivacyConnectivityTestState()
        var changes = 0
        let observation = model.objectWillChange.sink { changes += 1 }
        let host = UIHostingController(rootView: PrivacyConnectivityTestHost(state: state, model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; observation.cancel() }
        try await settle()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.canContinue)
        let settledChanges = changes
        XCTAssertGreaterThan(settledChanges, 0)
        for revision in 1...4 {
            state.unrelatedRevision = revision
            try await settle()
        }
        XCTAssertEqual(changes, settledChanges, "Redrawing personal content must not replay offline suspension")
        XCTAssertEqual(service.fetches, 0)
    }

    func testOnlineMountAndReconnectLoadOncePerTransitionDespiteRedraws() async throws {
        let owner = UUID(), service = PrivacySelectionFakeService(owner: UUID())
        service.viewerID = owner
        service.receipt = .init(enabled: false, accountScope: nil, workoutDefault: nil, revision: 0)
        let model = AccountPrivacyModel(owner: owner, service: service, profileOnlyRules: false)
        let state = PrivacyConnectivityTestState(); state.online = true
        let host = UIHostingController(rootView: PrivacyConnectivityTestHost(state: state, model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle()
        XCTAssertEqual(service.fetches, 1)
        for revision in 1...4 {
            state.unrelatedRevision = revision
            try await settle()
        }
        XCTAssertEqual(service.fetches, 1, "Model updates and parent redraws must not reload the same connectivity state")
        state.online = false; try await settle()
        XCTAssertNil(model.receipt); XCTAssertFalse(model.canContinue)
        XCTAssertEqual(service.fetches, 1)
        state.online = true; try await settle()
        XCTAssertEqual(service.fetches, 2)
        XCTAssertFalse(model.canContinue, "A disabled server policy remains closed after reconnect")
    }
}


extension OnboardingViewTests {
    @MainActor func testFullSharingCompletionRequiresVisiblePublicAudienceChoice() async {
        let owner = UUID(), service = PrivacySelectionFakeService(owner: UUID())
        service.viewerID = owner
        let model = AccountPrivacyModel(owner: owner, service: service, profileOnlyRules: false)
        await model.load(); model.selection = .publicAccount
        XCTAssertFalse(model.canCompleteSharingSetup)
        let incomplete = await model.completeSharingSetup(); XCTAssertFalse(incomplete); XCTAssertEqual(service.saves, 0)
        model.workoutSelection = .followers
        XCTAssertTrue(model.canCompleteSharingSetup)
        let completed = await model.completeSharingSetup()
        XCTAssertTrue(completed)
        XCTAssertEqual(service.saves, 1)
        XCTAssertEqual(model.receipt?.workoutDefault, .followers)
        XCTAssertEqual(model.receipt?.shareMeasurements, true)
        XCTAssertNotNil(FullWorkoutSharingConsent.date(owner: owner, revision: model.receipt!.revision))
        UserDefaults.standard.removeObject(forKey: FullWorkoutSharingConsent.key(owner: owner))
        UserDefaults.standard.removeObject(forKey: "SOOM.workoutAudience.v1.\(owner.uuidString.lowercased())")
    }
    @MainActor func testOldMeasurementConsentRemainsFalseUntilExplicitCompletion() async {
        let owner = UUID(), service = PrivacySelectionFakeService(owner: UUID())
        service.viewerID = owner
        service.receipt = .init(enabled: true, accountScope: .privateAccount, workoutDefault: .privatePost, revision: 7, shareMeasurements: false)
        let model = AccountPrivacyModel(owner: owner, service: service, profileOnlyRules: false)
        await model.load()
        XCTAssertEqual(service.saves, 0); XCTAssertFalse(model.shareMeasurements)
        XCTAssertEqual(model.receipt?.workoutDefault, .privatePost)
        await model.completeSharingSetup()
        XCTAssertEqual(service.saves, 1)
        XCTAssertEqual(model.receipt?.accountScope, .privateAccount)
        XCTAssertEqual(model.receipt?.workoutDefault, .followers)
        XCTAssertEqual(model.receipt?.shareMeasurements, true)
        XCTAssertNotNil(FullWorkoutSharingConsent.date(owner: owner, revision: model.receipt!.revision))
        UserDefaults.standard.removeObject(forKey: FullWorkoutSharingConsent.key(owner: owner))
        UserDefaults.standard.removeObject(forKey: "SOOM.workoutAudience.v1.\(owner.uuidString.lowercased())")
    }
    @MainActor func testDisabledContractCompletionCannotChangeExistingConsent() async {
        let owner = UUID(), service = PrivacySelectionFakeService(owner: UUID())
        service.viewerID = owner
        service.receipt = .init(enabled: false, accountScope: .privateAccount, workoutDefault: .followers, revision: 3, shareMeasurements: false)
        let model = AccountPrivacyModel(owner: owner, service: service, profileOnlyRules: false)
        await model.load(); model.selection = .privateAccount
        XCTAssertFalse(model.canCompleteSharingSetup)
        await model.completeSharingSetup()
        XCTAssertEqual(service.saves, 0); XCTAssertEqual(service.receipt.revision, 3)
        XCTAssertEqual(service.receipt.shareMeasurements, false)
    }
}

@MainActor
final class SocialVerificationPresentationTests: XCTestCase {
    func testInitialAndForegroundChecksStayNeutralAndKeepSocialClosedUntilReceipt() async {
        let owner = UUID(), safety = CommunitySafetyStore(client: nil, requiresSocialVerification: true)
        safety.setViewerID(owner)
        let service = PrivacySelectionFakeService(owner: owner); service.delayLoad = true
        service.receipt = .init(enabled: true, accountScope: .publicAccount, workoutDefault: .publicPost, revision: 1)
        let model = AccountPrivacyModel(owner: owner, service: service, socialState: safety, profileOnlyRules: false)
        XCTAssertTrue(model.isCheckingSocialAccess); XCTAssertFalse(safety.canUseSocial)
        let loading = Task { await model.load() }
        for _ in 0..<100 where service.fetches == 0 { await Task.yield() }
        XCTAssertTrue(model.isCheckingSocialAccess); XCTAssertFalse(safety.canUseSocial)
        await loading.value
        XCTAssertFalse(model.isCheckingSocialAccess); XCTAssertTrue(safety.canUseSocial)
        model.suspendSocialAccess()
        XCTAssertTrue(model.isCheckingSocialAccess); XCTAssertFalse(safety.canUseSocial); XCTAssertNil(model.receipt)
        await model.load()
        XCTAssertFalse(model.isCheckingSocialAccess); XCTAssertTrue(safety.canUseSocial)
    }
    func testConfirmedRestrictionAndFailureShowLockRatherThanEndlessChecking() async {
        let owner = UUID(), service = PrivacySelectionFakeService(owner: UUID())
        service.viewerID = owner
        let model = AccountPrivacyModel(owner: owner, service: service, profileOnlyRules: false)
        await model.load()
        XCTAssertFalse(model.isCheckingSocialAccess); XCTAssertFalse(model.canContinue)
        service.failLoad = true; await model.load()
        XCTAssertFalse(model.isCheckingSocialAccess); XCTAssertNotNil(model.errorMessage)
        model.setNetworkAvailable(false)
        XCTAssertFalse(model.isCheckingSocialAccess); XCTAssertFalse(model.canContinue)
        model.setNetworkAvailable(true)
        XCTAssertTrue(model.isCheckingSocialAccess); XCTAssertFalse(model.canContinue)
    }
    func testUnknownConnectivityDoesNotPublishOfflineLockOnMount() async throws {
        XCTAssertNil(SocialConnectivityMonitor().isOnline, "Actual NWPathMonitor adapter starts unknown, never false/offline")
        let owner = UUID(), service = PrivacySelectionFakeService(owner: UUID())
        service.viewerID = owner
        let model = AccountPrivacyModel(owner: owner, service: service, profileOnlyRules: false)
        let state = PrivacyConnectivityTestState(); state.online = nil
        let host = UIHostingController(rootView: PrivacyConnectivityTestHost(state: state, model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertTrue(model.isCheckingSocialAccess); XCTAssertNil(model.errorMessage); XCTAssertEqual(service.fetches, 0)
        state.online = false
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(model.isCheckingSocialAccess); XCTAssertNotNil(model.errorMessage); XCTAssertEqual(service.fetches, 0)
    }
}

@MainActor private final class ProfileOnlyPrivacyFixture: ProfileOnlyPrivacyServing {
    let owner = UUID()
    lazy var context: ProfileOnlyPrivacyContext? = .init(ownerID: owner, generation: 1)
    lazy var value = make()
    var fetchCalls = 0, saveCalls = 0
    var onSave: (() -> Void)?
    var onFetch: (() -> Void)?
    var savedScope: AccountAudience?
    var expectedRevision: Int64?
    var responseVersion = 2
    var changesMeasurementConsent = false
    func make(scope: AccountAudience = .privateAccount, revision: Int64 = 7, measurements: Bool = false, version: Int = 2) -> ProfileOnlyPrivacyReceipt {
        .init(version: version, ownerID: owner, enabled: true, scope: scope, revision: revision, shareMeasurements: measurements)
    }
    func fetchProfileOnly() async throws -> ProfileOnlyPrivacyReceipt {
        fetchCalls += 1; onFetch?(); return value
    }
    func saveProfileOnly(scope: AccountAudience, expectedRevision: Int64) async throws -> ProfileOnlyPrivacyReceipt {
        saveCalls += 1; savedScope = scope; self.expectedRevision = expectedRevision
        value = make(scope: scope, revision: expectedRevision + 1, measurements: changesMeasurementConsent, version: responseVersion)
        onSave?(); return value
    }
}

@MainActor final class ProfileOnlyPrivacyCandidateTests: XCTestCase {
    func testProductionGateMakesNoNetworkCalls() async {
        let f = ProfileOnlyPrivacyFixture(), unused = UUID()
        let m = ProfileOnlyPrivacyModel(owner: unused, service: f)
        await m.load()
        XCTAssertEqual(m.error, ProfileOnlyPrivacyReleaseGate.productionReady ? .accountChanged : .disabled); XCTAssertEqual(f.fetchCalls, 0); XCTAssertFalse(m.canSave)
    }
    func testScopeAloneDerivesPublicOrMutualAudience() {
        let f = ProfileOnlyPrivacyFixture()
        XCTAssertEqual(f.make(scope: .publicAccount).workoutAudience, .publicPost)
        XCTAssertEqual(f.make(scope: .privateAccount).workoutAudience, .mutual)
    }
    func testUnknownOrLegacyVersionCannotUnlockSettings() async {
        for version in [0, 1, 3] {
            let f = ProfileOnlyPrivacyFixture(); f.value = f.make(version: version)
            let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
            await m.load(); XCTAssertNil(m.receipt); XCTAssertFalse(m.canSave)
        }
    }
    func testExplicitPublicChoicePreservesMeasurementRefusalAndReadsBack() async {
        let f = ProfileOnlyPrivacyFixture(); let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        await m.load(); m.selection = .publicAccount
        let success = await m.save()
        XCTAssertTrue(success); XCTAssertEqual(f.savedScope, .publicAccount); XCTAssertEqual(f.expectedRevision, 7)
        XCTAssertEqual(f.fetchCalls, 2); XCTAssertEqual(m.receipt?.shareMeasurements, false)
        XCTAssertEqual(m.receipt?.workoutAudience, .publicPost)
    }
    func testMeasurementUpgradeInAudienceResponseFailsClosed() async {
        let f = ProfileOnlyPrivacyFixture(); let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        await m.load(); f.changesMeasurementConsent = true
        let success = await m.save()
        XCTAssertFalse(success); XCTAssertNil(m.receipt); XCTAssertEqual(m.error, .changeNotConfirmed)
    }
    func testAccountGenerationChangeDuringWriteCannotRestoreAccess() async {
        let f = ProfileOnlyPrivacyFixture(); let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        await m.load(); f.onSave = { f.context = .init(ownerID: f.owner, generation: 2) }
        let success = await m.save()
        XCTAssertFalse(success); XCTAssertNil(m.receipt); XCTAssertEqual(f.fetchCalls, 1)
    }
    func testSuspendDuringWriteDiscardsCompletion() async {
        let f = ProfileOnlyPrivacyFixture(); let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        await m.load(); f.onSave = { m.suspend() }
        let success = await m.save()
        XCTAssertFalse(success); XCTAssertNil(m.receipt); XCTAssertFalse(m.busy)
    }
    func testReadbackRaceDoesNotAdoptAnotherRevision() async {
        let f = ProfileOnlyPrivacyFixture(); let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        await m.load()
        f.onFetch = { f.value = f.make(scope: .publicAccount, revision: 9) }
        let success = await m.save()
        XCTAssertFalse(success); XCTAssertNil(m.receipt); XCTAssertEqual(m.error, .changeNotConfirmed)
    }
    func testAccountSwitchDuringLoadRejectsReceipt() async {
        let f = ProfileOnlyPrivacyFixture(); let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        f.onFetch = { f.context = .init(ownerID: UUID(), generation: 2) }
        await m.load(); XCTAssertNil(m.receipt); XCTAssertEqual(m.error, .accountChanged)
    }
    func testInvalidReceiptOwnerOrRevisionRejected() {
        let f = ProfileOnlyPrivacyFixture()
        XCTAssertThrowsError(try f.make().validate(owner: UUID()))
        XCTAssertThrowsError(try f.make(revision: 0).validate(owner: f.owner))
        XCTAssertThrowsError(try f.make(revision: Int64.max).validate(owner: f.owner))
    }
    func testPrivateSaveUsesMutualNotLegacyApprovedFollowers() async {
        let f = ProfileOnlyPrivacyFixture(); f.value = f.make(scope: .publicAccount)
        let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        await m.load(); m.selection = .privateAccount
        let success = await m.save()
        XCTAssertTrue(success); XCTAssertEqual(m.receipt?.workoutAudience, .mutual)
    }
    func testCancelledLoadDoesNotCallTransport() async {
        let f = ProfileOnlyPrivacyFixture(); let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        let task = Task { await m.load() }
        task.cancel(); await task.value
        XCTAssertEqual(f.fetchCalls, 0); XCTAssertNil(m.receipt)
    }
    func testExistingMeasurementConsentIsNotReissued() async {
        let f = ProfileOnlyPrivacyFixture(); f.value = f.make(measurements: true)
        f.changesMeasurementConsent = true
        let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        await m.load(); m.selection = .publicAccount
        let success = await m.save()
        XCTAssertTrue(success); XCTAssertEqual(m.receipt?.shareMeasurements, true)
    }
    func testUnknownWriteVersionRejectedBeforeReadback() async {
        let f = ProfileOnlyPrivacyFixture(); let m = ProfileOnlyPrivacyModel(fixtureOwner: f.owner, service: f)
        await m.load(); f.responseVersion = 3
        let success = await m.save()
        XCTAssertFalse(success); XCTAssertNil(m.receipt); XCTAssertEqual(f.fetchCalls, 1)
    }
}

@MainActor final class ProfileOnlyPrivacyIntegrationTests: XCTestCase {
    func testV2ConfiguredModelRejectsLegacyReadBeforeSocialUnlock() async {
        let owner=UUID(),service=PrivacySelectionFakeService(owner:UUID());service.viewerID=owner
        service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:2,shareMeasurements:false)
        let model=AccountPrivacyModel(owner:owner,service:service,profileOnlyRules:true)
        await model.load()
        XCTAssertNil(model.receipt);XCTAssertFalse(model.canContinue);XCTAssertNotNil(model.errorMessage)
        service.receipt.policyVersion=2
        await model.load()
        XCTAssertTrue(model.canContinue);XCTAssertEqual(model.receipt?.policyVersion,2)
    }

    func testLegacyMutualAndUnknownPolicyAreRejectedButExactV2IsAccepted() throws {
        let legacy=AccountPrivacyReceipt(enabled:true,accountScope:.privateAccount,workoutDefault:.mutual,revision:3)
        XCTAssertFalse(legacy.isSelected)
        var receipt=legacy; receipt.policyVersion=2; XCTAssertTrue(receipt.isSelected)
        receipt.policyVersion=3; XCTAssertFalse(receipt.isSelected)
        let data=Data(#"{"enabled":true,"account_scope":"public","workout_default":"public","revision":2}"#.utf8)
        let decoded=try JSONDecoder().decode(AccountPrivacyReceipt.self,from:data)
        XCTAssertNil(decoded.policyVersion);XCTAssertTrue(decoded.isSelected)
    }
    func testV2ScopeSavePreservesFalseMeasurementConsentAndDoesNotCreateConsentDate() async {
        let owner=UUID(), service=PrivacySelectionFakeService(owner:UUID())
        service.viewerID=owner
        service.receipt = .init(enabled:true,accountScope:.privateAccount,workoutDefault:.mutual,revision:4,shareMeasurements:false,policyVersion:2)
        let model=AccountPrivacyModel(owner:owner,service:service)
        await model.load();XCTAssertTrue(model.canContinue);XCTAssertTrue(model.usesProfileOnlyRules)
        model.selection = .publicAccount
        let saved=await model.completeSharingSetup()
        XCTAssertTrue(saved);XCTAssertEqual(service.saves,1)
        XCTAssertEqual(model.receipt?.workoutDefault,.publicPost)
        XCTAssertEqual(model.receipt?.shareMeasurements,false)
        XCTAssertNil(FullWorkoutSharingConsent.date(owner:owner,revision:5))
    }
    func testV2PublicToPrivateDerivesMutualAndKeepsExistingTrueMeasurementChoice() async {
        let owner=UUID(),service=PrivacySelectionFakeService(owner:UUID());service.viewerID=owner
        service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:8,shareMeasurements:true,policyVersion:2)
        let model=AccountPrivacyModel(owner:owner,service:service)
        await model.load();model.selection = .privateAccount
        let saved=await model.completeSharingSetup()
        XCTAssertTrue(saved);XCTAssertEqual(model.receipt?.workoutDefault,.mutual)
        XCTAssertEqual(model.receipt?.shareMeasurements,true)
        XCTAssertNil(FullWorkoutSharingConsent.date(owner:owner,revision:9))
    }
    func testDowngradedV1WriteResponseCannotUnlockV2Model() async {
        let owner=UUID(),service=PrivacySelectionFakeService(owner:UUID());service.viewerID=owner
        service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:2,shareMeasurements:false,policyVersion:2)
        let model=AccountPrivacyModel(owner:owner,service:service)
        await model.load();service.responsePolicyVersion=1;model.selection = .publicAccount
        let saved=await model.completeSharingSetup()
        XCTAssertFalse(saved);XCTAssertNil(model.receipt);XCTAssertFalse(model.canContinue)
    }
    func testUnselectedAndRolledBackReceiptCanMakeExplicitFirstSelection() async throws {
        for revision:Int64 in [0,12] {
            let fixture=ProfileOnlyPrivacyFixture()
            fixture.value = .init(version:2,ownerID:fixture.owner,enabled:true,scope:nil,revision:revision,shareMeasurements:false)
            let model=ProfileOnlyPrivacyModel(fixtureOwner:fixture.owner,service:fixture)
            await model.load();XCTAssertNotNil(model.receipt);XCTAssertFalse(model.canSave)
            model.selection = .publicAccount
            let saved=await model.save();XCTAssertTrue(saved)
            XCTAssertEqual(fixture.expectedRevision,revision)
            XCTAssertEqual(model.receipt?.revision,revision+1)
        }
    }
    func testUnselectedBridgeNeverUnlocksSocialAccess() throws {
        let value=ProfileOnlyPrivacyReceipt(version:2,ownerID:UUID(),enabled:true,scope:nil,revision:13,shareMeasurements:false)
        let bridge=try value.accountPrivacyReceipt()
        XCTAssertEqual(bridge.policyVersion,2);XCTAssertFalse(bridge.isSelected)
        XCTAssertNil(bridge.workoutDefault)
    }
    func testSDKUsesExactScopeOnlyRPCAndReadbackWithoutOwnerOrMeasurementArguments() async throws {
        let owner=UUID();ProfilePrivacyV2Wire.reset(owner:owner)
        let (client,session)=makeClient();defer{session.invalidateAndCancel()}
        let context=ProfileOnlyPrivacyContext(ownerID:owner,generation:3)
        let service=SupabaseProfileOnlyPrivacyService(syntheticClient:client,currentContext:{context})
        let before=try await service.fetchProfileOnly();XCTAssertEqual(before.revision,4)
        let result=try await service.saveProfileOnly(scope:.privateAccount,expectedRevision:4)
        XCTAssertEqual(result.scope,.privateAccount);XCTAssertEqual(result.revision,5)
        XCTAssertFalse(result.shareMeasurements)
        let calls=ProfilePrivacyV2Wire.snapshot()
        XCTAssertEqual(calls.map(\.0),["soom_profile_privacy_candidate_v2","soom_set_profile_privacy_candidate_v2","soom_profile_privacy_candidate_v2"])
        let body=try XCTUnwrap(JSONSerialization.jsonObject(with:calls[1].1) as? [String:Any])
        XCTAssertEqual(Set(body.keys),["p_scope","p_expected_revision","p_notice_version"])
        XCTAssertEqual(body["p_scope"] as? String,"private")
        XCTAssertEqual(body["p_notice_version"] as? String,"profile-only-mutual-v2")
    }
    func testSDKRejectsReleaseReadinessMismatchAndWrongOwner() async throws {
        let owner=UUID();ProfilePrivacyV2Wire.reset(owner:owner,releaseReady:true)
        let (client,session)=makeClient();defer{session.invalidateAndCancel()}
        let service=SupabaseProfileOnlyPrivacyService(syntheticClient:client,currentContext:{.init(ownerID:owner,generation:1)})
        do{_ = try await service.fetchProfileOnly();XCTFail()}catch{}
        ProfilePrivacyV2Wire.reset(owner:UUID())
        do{_ = try await service.fetchProfileOnly();XCTFail()}catch{}
    }
    func testSDKRejectsChangedReadbackAndDoesNotRetryWriteBlindly() async throws {
        let owner=UUID();ProfilePrivacyV2Wire.reset(owner:owner,readbackRace:true)
        let (client,session)=makeClient();defer{session.invalidateAndCancel()}
        let service=SupabaseProfileOnlyPrivacyService(syntheticClient:client,currentContext:{.init(ownerID:owner,generation:1)})
        do{_ = try await service.saveProfileOnly(scope:.privateAccount,expectedRevision:4);XCTFail()}catch{}
        XCTAssertEqual(ProfilePrivacyV2Wire.snapshot().filter{$0.0.contains("set_")}.count,1)
    }
    func testMeasurementWithdrawalPreservesProfileAndCannotEnableSharing() async {
        let owner=UUID(),f=PrivacySelectionFakeService(owner:UUID());f.viewerID=owner
        f.receipt = .init(enabled:true,accountScope:.privateAccount,workoutDefault:.mutual,revision:7,shareMeasurements:true,policyVersion:2,measurementRevision:3)
        let model=AccountPrivacyModel(owner:owner,service:f,profileOnlyRules:true)
        await model.load();XCTAssertTrue(model.canWithdrawMeasurements)
        let saved=await model.withdrawMeasurements();XCTAssertTrue(saved)
        XCTAssertEqual(model.receipt?.revision,7);XCTAssertEqual(model.receipt?.accountScope,.privateAccount)
        XCTAssertEqual(model.receipt?.measurementRevision,4);XCTAssertEqual(model.receipt?.shareMeasurements,false)
        XCTAssertFalse(model.canWithdrawMeasurements);XCTAssertEqual(f.saves,1)
    }
    func testWithdrawalFailureAndAccountChangeNeverClaimConfirmedOff() async {
        for switchAccount in [false,true] {
            let owner=UUID(),f=PrivacySelectionFakeService(owner:UUID());f.viewerID=owner
            f.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:7,shareMeasurements:true,policyVersion:2,measurementRevision:3)
            let model=AccountPrivacyModel(owner:owner,service:f,profileOnlyRules:true)
            await model.load();f.failSave = !switchAccount;f.switchDuringSave=switchAccount
            let saved=await model.withdrawMeasurements();XCTAssertFalse(saved);XCTAssertFalse(model.canContinue)
            if !switchAccount {XCTAssertNil(model.receipt);XCTAssertEqual(f.receipt.shareMeasurements,true)}
        }
    }
    func testWithdrawalSDKOnlySendsTwoRevisionCASFieldsAndReadback() async throws {
        let owner=UUID();ProfilePrivacyV2Wire.reset(owner:owner)
        let (client,session)=makeClient();defer{session.invalidateAndCancel()}
        let service=SupabaseProfileOnlyPrivacyService(syntheticClient:client,currentContext:{.init(ownerID:owner,generation:1)})
        let result=try await service.withdrawMeasurements(profileRevision:4,measurementRevision:9)
        XCTAssertEqual(result.revision,4);XCTAssertEqual(result.measurementRevision,10);XCTAssertFalse(result.shareMeasurements)
        let calls=ProfilePrivacyV2Wire.snapshot();XCTAssertEqual(calls.map(\.0),["soom_withdraw_measurements_candidate_v2","soom_profile_privacy_candidate_v2"])
        let body=try XCTUnwrap(JSONSerialization.jsonObject(with:calls[0].1) as? [String:Any])
        XCTAssertEqual(Set(body.keys),["p_expected_profile_revision","p_expected_measurement_revision"])
        XCTAssertEqual(body["p_expected_measurement_revision"] as? Int,9)
    }
    private func makeClient()->(SupabaseClient,URLSession) {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ProfilePrivacyV2Wire.self]
        let session=URLSession(configuration:config)
        let client=SupabaseClient(supabaseURL:URL(string:"https://profile-v2-fixture.invalid")!,supabaseKey:"synthetic-key",
            options:SupabaseClientOptions(auth:.init(storageKey:UUID().uuidString,autoRefreshToken:false),global:.init(session:session)))
        return(client,session)
    }
}

private final class ProfilePrivacyV2Wire: URLProtocol, @unchecked Sendable {
    private static let lock=NSLock()
    private static var measurementRevision:Int64=9
    private static var owner=UUID(),revision:Int64=4,scope="public",releaseReady=false,readbackRace=false
    private static var calls:[(String,Data)]=[]
    static func reset(owner:UUID,releaseReady:Bool=false,readbackRace:Bool=false) {
        lock.lock();defer{lock.unlock()};self.owner=owner;revision=4;measurementRevision=9;scope="public";self.releaseReady=releaseReady;self.readbackRace=readbackRace;calls=[]
    }
    static func snapshot()->[(String,Data)] {lock.lock();defer{lock.unlock()};return calls}
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        guard request.url?.host == "profile-v2-fixture.invalid" else {client?.urlProtocol(self,didFailWithError:URLError(.unsupportedURL));return}
        var body=request.httpBody ?? Data()
        if let stream=request.httpBodyStream {stream.open();defer{stream.close()};var bytes=[UInt8](repeating:0,count:1024);while stream.hasBytesAvailable {let n=stream.read(&bytes,maxLength:bytes.count);if n<=0{break};body.append(contentsOf:bytes.prefix(n))}}
        let name=request.url!.lastPathComponent
        Self.lock.lock();Self.calls.append((name,body))
        if name == "soom_set_profile_privacy_candidate_v2" {Self.revision += 1;Self.scope="private"}
        else if name == "soom_withdraw_measurements_candidate_v2" {Self.measurementRevision += 1}
        else if Self.readbackRace && Self.revision>4 {Self.revision += 1}
        let object:[String:Any] = ["version":2,"owner_id":Self.owner.uuidString,"enabled":true,"account_scope":Self.scope,
            "revision":Self.revision,"share_measurements":false,"measurement_revision":Self.measurementRevision,"release_ready":Self.releaseReady]
        Self.lock.unlock()
        let data=try! JSONSerialization.data(withJSONObject:object)
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
