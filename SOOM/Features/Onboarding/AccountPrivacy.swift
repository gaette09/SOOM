import Combine
import Network
import Foundation
import Supabase
import SwiftUI

enum AccountAudience: String, Codable, CaseIterable {
    case publicAccount = "public", privateAccount = "private"
    var title: String { self == .publicAccount ? "공개 계정" : "비공개 계정" }
    var defaultWorkout: FeedPostVisibility { self == .publicAccount ? .publicPost : .followers }
}
struct AccountPrivacyReceipt: Decodable, Equatable {
    let enabled: Bool
    let accountScope: AccountAudience?
    let workoutDefault: FeedPostVisibility?
    let revision: Int64
    var shareMeasurements: Bool? = nil
    /// Absent on a v1 response. Mutual must never be inferred from old columns.
    var policyVersion: Int? = nil
    var measurementRevision:Int64? = nil
    var isSelected: Bool {
        guard enabled, revision > 0, let accountScope, let workoutDefault else { return false }
        if policyVersion == 2 {
            return workoutDefault == (accountScope == .publicAccount ? .publicPost : .mutual)
        }
        guard policyVersion == nil || policyVersion == 1 else { return false }
        return workoutDefault != .mutual && !(accountScope == .privateAccount && workoutDefault == .publicPost)
    }
    enum CodingKeys: String, CodingKey {
        case enabled, revision, shareMeasurements = "share_measurements", accountScope = "account_scope", workoutDefault = "workout_default", policyVersion = "policy_version", measurementRevision = "measurement_revision"
    }
}
enum ApprovedFollowState: String, Codable { case none, pending, accepted }
struct ApprovedFollowReceipt: Decodable, Equatable {
    let userID: UUID
    let state: ApprovedFollowState
    let requestID: UUID?
    let accountScope: String
    var policyVersion:Int? = nil
    var followsViewer:Bool? = nil
    var edgeRevision:Int64? = nil
    var legacyPending:Bool? = nil
    enum CodingKeys: String, CodingKey {
        case userID = "user_id", state, requestID = "request_id", accountScope = "account_scope"
        case policyVersion = "policy_version", followsViewer = "follows_viewer"
        case edgeRevision = "revision", legacyPending = "legacy_pending"
    }
}
private struct ProfileFollowV2Envelope:Decodable {
    let version:Int,viewer_id:UUID,rows:[ApprovedFollowReceipt],release_ready:Bool
    func validated(viewer:UUID,allowed:Set<UUID>) throws -> [ApprovedFollowReceipt] {
        guard version==2,viewer_id==viewer,release_ready,
              Set(rows.map(\.userID)).count==rows.count,
              rows.allSatisfy({allowed.contains($0.userID) && $0.state != .pending && $0.requestID==nil
                  && ["public","private","unselected"].contains($0.accountScope)
                  && $0.followsViewer != nil && $0.legacyPending != nil
                  && ($0.edgeRevision ?? -1)>=0 && ($0.state != .accepted || ($0.edgeRevision ?? 0)>0)
                  && ($0.policyVersion==nil || $0.policyVersion==2)}) else {throw ProfileOnlyPrivacyError.invalidReceipt}
        return rows.map {row in var value=row;value.policyVersion=2;return value}
    }
}
struct IncomingFollowRequest: Decodable, Identifiable, Equatable {
    let userID: UUID, requestID: UUID
    let displayName: String
    let handle: String?, avatarPath: String?
    let state: ApprovedFollowState, createdAt: Date
    var id: UUID { requestID }
    func matches(search: String) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = term.hasPrefix("@") ? String(term.dropFirst()) : term
        return normalized.isEmpty || displayName.localizedCaseInsensitiveContains(normalized)
            || handle?.localizedCaseInsensitiveContains(normalized) == true
    }
    var profile: FeedProfileDTO { .init(id: userID, displayName: displayName, handle: handle, avatarPath: avatarPath) }
    enum CodingKeys: String, CodingKey {
        case userID = "user_id", requestID = "request_id", displayName = "display_name", handle,
             avatarPath = "avatar_path", state, createdAt = "created_at"
    }
}
@MainActor
protocol AccountPrivacyServing {
    var viewerID: UUID? { get }
    func fetch() async throws -> AccountPrivacyReceipt
    func withdrawMeasurements(owner: UUID, profileRevision: Int64, measurementRevision: Int64) async throws -> AccountPrivacyReceipt
    func previewCapability() async throws -> AccountActivityPreviewCapability?
    func save(owner: UUID, scope: AccountAudience, defaultWorkout: FeedPostVisibility, expectedRevision: Int64, shareMeasurements: Bool) async throws -> AccountPrivacyReceipt
}
extension AccountPrivacyServing {
    func withdrawMeasurements(owner:UUID,profileRevision:Int64,measurementRevision:Int64) async throws -> AccountPrivacyReceipt {throw CommunitySafetyError.unavailable}
    func previewCapability() async throws -> AccountActivityPreviewCapability? { nil }
}
@MainActor
struct SupabaseAccountPrivacyService: AccountPrivacyServing {
    let client: SupabaseClient
    let readPolicy: AccountActivityReadPolicy
    init(client:SupabaseClient,readPolicy:AccountActivityReadPolicy = .deployed) {
        self.client=client;self.readPolicy=readPolicy
    }
    var viewerID: UUID? { client.auth.currentSession?.user.id }
    func previewCapability() async throws -> AccountActivityPreviewCapability? {
        guard let owner = viewerID else { return nil }
        return try await AccountActivityPreviewService(client: client, owner: owner).capability()
    }
    func fetch() async throws -> AccountPrivacyReceipt {
        if readPolicy == .profileOnlyV2 {
            return try await SupabaseProfileOnlyPrivacyService(client: client).fetchProfileOnly().accountPrivacyReceipt()
        }
        let rows: [AccountPrivacyReceipt] = try await client.rpc("soom_privacy_v1").execute().value
        guard rows.count == 1, let first = rows.first else { throw CommunitySafetyError.unavailable }
        // A completion must not reactivate legacy snapshots on an old server.
        let ready = first.enabled ? try await SupabaseWorkoutSharedDetailService(client: client).enabled() : false
        return AccountPrivacyReceipt(enabled: ready, accountScope: first.accountScope,
            workoutDefault: first.workoutDefault, revision: first.revision, shareMeasurements: first.shareMeasurements)
    }
    func save(owner: UUID, scope: AccountAudience, defaultWorkout: FeedPostVisibility, expectedRevision: Int64, shareMeasurements: Bool) async throws -> AccountPrivacyReceipt {
        guard viewerID == owner else { throw CommunitySafetyError.accountChanged }
        if readPolicy == .profileOnlyV2 {
            let service = SupabaseProfileOnlyPrivacyService(client: client)
            let expectedContext = service.context
            let before = try await service.fetchProfileOnly()
            guard service.context == expectedContext, before.ownerID == owner,
                  before.revision == expectedRevision, before.shareMeasurements == shareMeasurements,
                  defaultWorkout == (scope == .publicAccount ? .publicPost : .mutual) else {
                throw FeedPostManagementError.changeNotConfirmed
            }
            let saved = try await service.saveProfileOnly(scope: scope, expectedRevision: expectedRevision)
            guard service.context == expectedContext, saved.shareMeasurements == before.shareMeasurements else {
                throw FeedPostManagementError.changeNotConfirmed
            }
            return try saved.accountPrivacyReceipt()
        }
        struct Params: Encodable { let p_owner: UUID; let p_scope: String; let p_default: String; let p_expected_revision: Int64; let p_share_measurements: Bool }
        let rows: [AccountPrivacyReceipt] = try await client.rpc("soom_set_privacy_v1", params: Params(p_owner: owner,
            p_scope: scope.rawValue, p_default: defaultWorkout.rawValue, p_expected_revision: expectedRevision, p_share_measurements: shareMeasurements)).execute().value
        guard viewerID == owner, rows.count == 1, let first = rows.first, first.isSelected,
              first.accountScope == scope, first.workoutDefault == defaultWorkout, first.shareMeasurements == shareMeasurements else { throw FeedPostManagementError.changeNotConfirmed }
        // Read back before unlocking the gate; a successful network write alone
        // cannot leave another account or a concurrent setting accepted locally.
        let current = try await fetch()
        guard viewerID == owner, current == first else { throw FeedPostManagementError.changeNotConfirmed }
        return current
    }
    func withdrawMeasurements(owner:UUID,profileRevision:Int64,measurementRevision:Int64) async throws -> AccountPrivacyReceipt {
        guard viewerID==owner,readPolicy == .profileOnlyV2 else {throw CommunitySafetyError.accountChanged}
        let receipt=try await SupabaseProfileOnlyPrivacyService(client:client).withdrawMeasurements(
            profileRevision:profileRevision,measurementRevision:measurementRevision)
        guard viewerID==owner else {throw CommunitySafetyError.accountChanged}
        return try receipt.accountPrivacyReceipt()
    }
    private func followContext() throws -> AccountActivityReadContext {
        let safety=CommunitySafetyStore.shared
        guard ProfileOnlyPrivacyReleaseGate.productionReady,let owner=viewerID else {throw ProfileOnlyPrivacyError.disabled}
        try safety.requireSocialAccess(viewerID:owner)
        return .init(viewerID:owner,generation:safety.accountGeneration,safetyRevision:safety.revision)
    }
    func states(_ ids: [UUID]) async throws -> [ApprovedFollowReceipt] {
        struct Params: Encodable { let p_ids: [UUID] }
        if readPolicy == .profileOnlyV2 {
            guard ids.count<=200 else {throw ProfileOnlyPrivacyError.invalidReceipt}
            let context=try followContext()
            let response:ProfileFollowV2Envelope=try await client.rpc("soom_follow_state_candidate_v2",params:Params(p_ids:ids)).execute().value
            guard try followContext()==context,!Task.isCancelled else {throw CommunitySafetyError.accountChanged}
            return try response.validated(viewer:context.viewerID,allowed:Set(ids))
        }
        return try await client.rpc("soom_follow_state_v1", params: Params(p_ids: ids)).execute().value
    }
    func request(_ owner: UUID, following: Bool, expectedRequest: UUID?, actor: UUID, expectedRevision:Int64? = nil) async throws -> ApprovedFollowReceipt {
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: actor)
        guard viewerID == actor else { throw CommunitySafetyError.accountChanged }
        if readPolicy == .profileOnlyV2 {
            guard expectedRequest==nil,let revision=expectedRevision,revision>=0,revision<Int64.max else {throw FeedPostManagementError.changeNotConfirmed}
            let context=try followContext()
            struct V2Params:Encodable {let p_actor:UUID,p_owner:UUID;let p_following:Bool;let p_expected_revision:Int64}
            let response:ProfileFollowV2Envelope=try await client.rpc("soom_request_follow_candidate_v2",
                params:V2Params(p_actor:actor,p_owner:owner,p_following:following,p_expected_revision:revision)).execute().value
            guard try followContext()==context,!Task.isCancelled else {throw CommunitySafetyError.accountChanged}
            let rows=try response.validated(viewer:actor,allowed:[owner])
            guard rows.count==1,let row=rows.first,row.state==(following ? .accepted : .none),
                  let resultingRevision=row.edgeRevision,(revision...revision+1).contains(resultingRevision) else {throw FeedPostManagementError.changeNotConfirmed}
            return row
        }
        struct Params: Encodable { let p_actor: UUID; let p_owner: UUID; let p_following: Bool; let p_expected_request: UUID? }
        let rows: [ApprovedFollowReceipt] = try await client.rpc("soom_request_follow_v1", params: Params(p_actor:actor,p_owner: owner,
            p_following: following, p_expected_request: expectedRequest)).execute().value
        guard viewerID == actor,rows.count == 1, let value = rows.first, value.userID == owner,
              following ? value.state != .none : value.state == .none else { throw FeedPostManagementError.changeNotConfirmed }
        return value
    }
    func incoming(after: IncomingFollowRequest? = nil) async throws -> [IncomingFollowRequest] {
        struct Params: Encodable { let p_after: Date?; let p_after_id: UUID?; let p_limit: Int }
        return try await client.rpc("soom_follow_requests_v1", params: Params(p_after: after?.createdAt,
            p_after_id: after?.userID, p_limit: 50)).execute().value
    }
    func review(_ request: IncomingFollowRequest, action: String, actor: UUID) async throws {
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: actor)
        guard viewerID == actor else { throw CommunitySafetyError.accountChanged }
        struct Params: Encodable { let p_actor: UUID; let p_follower: UUID; let p_request: UUID; let p_action: String }
        let approved: Bool = try await client.rpc("soom_review_follow_v1", params: Params(p_actor:actor,p_follower: request.userID,
            p_request: request.requestID, p_action: action)).execute().value
        guard viewerID == actor,approved == (action == "approve") else { throw FeedPostManagementError.changeNotConfirmed }
    }
}
/// Account-scoped, fresh-read gate. Unknown/failed/interrupted reads never
/// adopt a previous account's choice. Selection is not health-cloud consent.
@MainActor
enum FullWorkoutSharingConsent {
    static func key(owner: UUID) -> String { "SOOM.fullWorkoutSharing.completed.v1." + owner.uuidString.lowercased() }
    static func record(owner: UUID, revision: Int64, at date: Date = Date()) {
        UserDefaults.standard.set(["revision": NSNumber(value: revision), "date": date], forKey: key(owner: owner))
    }
    static func date(owner: UUID, revision: Int64) -> Date? {
        guard let value = UserDefaults.standard.dictionary(forKey: key(owner: owner)),
              (value["revision"] as? NSNumber)?.int64Value == revision else { return nil }
        return value["date"] as? Date
    }
}

enum FeedPrivacyPreviewCheck: Sendable { case notRequested, allowed, denied, unavailable }

@MainActor
final class AccountPrivacyModel: ObservableObject {
    @Published private(set) var receipt: AccountPrivacyReceipt?
    @Published private(set) var busy = false
    /// Presentation only. Never grants access while server verification is pending.
    @Published private(set) var isCheckingSocialAccess = true
    @Published private(set) var earlyCacheVerification: FeedEarlyCachePresentationPolicy.Verification = .unresolved
    @Published private(set) var errorMessage: String?
    @Published var selection: AccountAudience?
    @Published var workoutSelection: FeedPostVisibility?
    @Published var shareMeasurements = false
    private let service: any AccountPrivacyServing
    private let owner: UUID
    private var receiptGeneration: Int?
    private var verifiedPolicyVersion: Int?
    private let profileOnlyRules: Bool
    private var operation = UUID()
    private var activeReceiptLoad: UUID?
    private let socialState: CommunitySafetyStore?
    private var networkAvailable = true
    private var onboardingComplete = true
    init(owner: UUID, service: any AccountPrivacyServing, socialState: CommunitySafetyStore? = nil, onboardingComplete: Bool = true, profileOnlyRules: Bool = ProfileOnlyPrivacyReleaseGate.productionReady) {
        self.owner = owner; self.service = service; self.socialState = socialState; self.onboardingComplete = onboardingComplete
        self.profileOnlyRules = profileOnlyRules
        isCheckingSocialAccess = onboardingComplete
    }
    func suspendSocialAccess() {
        earlyCacheVerification = .unavailable
        isCheckingSocialAccess = networkAvailable && onboardingComplete
        activeReceiptLoad = nil
        operation = UUID(); busy = false; receipt = nil
        if let socialState {
            // Suspension removes live authority immediately but is not evidence
            // of a server denial. The passive view is hidden while unavailable.
            socialState.withPendingDisplayCachePreserved(owner: owner) {
                _ = socialState.setActivityPreviewVerified(false, owner: owner, generation: socialState.accountGeneration, expectedRevision: socialState.revision)
                socialState.setSocialVerified(false, owner: owner)
            }
        }
    }
    func setNetworkAvailable(_ available: Bool) {
        if available && !networkAvailable { isCheckingSocialAccess = onboardingComplete }
        networkAvailable = available
        if !available { suspendSocialAccess() }
        if !available { errorMessage = "연결을 확인할 때까지 소셜 기능을 잠갔어요. 내 기록은 계속 사용할 수 있어요." }
    }
    func setOnboardingComplete(_ complete: Bool) {
        if complete && !onboardingComplete { isCheckingSocialAccess = networkAvailable }
        onboardingComplete = complete
        if !complete { suspendSocialAccess() }
    }
    private func publishSocialReceipt(verifiedPreviewGeneration: Int? = nil) {
        socialState?.setSocialVerified(networkAvailable && onboardingComplete && canContinue, owner: owner)
        if let generation = verifiedPreviewGeneration, let socialState {
            _ = socialState.setActivityPreviewVerified(true, owner: owner,
                generation: generation, expectedRevision: socialState.revision)
        }
        // End checking only after both independently validated grants are published.
        isCheckingSocialAccess = false
    }
    var canContinue: Bool { !busy && networkAvailable && onboardingComplete && service.viewerID == owner && (socialState == nil || receiptGeneration == socialState?.accountGeneration) && receipt?.isSelected == true }
    func load() async {
        guard activeReceiptLoad == nil else { return }
        let trace = LoadTrace("privacy-receipt")
        earlyCacheVerification = .checking
        isCheckingSocialAccess = networkAvailable && onboardingComplete
        if let socialState {
            socialState.withPendingDisplayCachePreserved(owner: owner) {
                _ = socialState.setActivityPreviewVerified(false, owner: owner, generation: socialState.accountGeneration, expectedRevision: socialState.revision)
                socialState.setSocialVerified(false, owner: owner)
            }
        }
        guard networkAvailable else { earlyCacheVerification = .unavailable; return }
        let generation = socialState?.accountGeneration
        let verificationRevision = socialState?.revision
        var verifiedLoad = false
        var verifiedPreview = false
        var previewOutcome: FeedPrivacyPreviewCheck = .notRequested
        let token = UUID(); operation = token; receipt = nil; selection = nil; workoutSelection = nil; shareMeasurements = false; busy = true; errorMessage = nil
        activeReceiptLoad = token
        defer { if activeReceiptLoad == token { activeReceiptLoad = nil } }
        defer {
            if operation == token {
                let current = verifiedLoad && !Task.isCancelled && networkAvailable && onboardingComplete
                    && service.viewerID == owner && socialState?.accountGeneration == generation
                    && socialState?.revision == verificationRevision
                if !current { receipt = nil; receiptGeneration = nil }
                busy = false
                // Publishing the legacy receipt can advance the safety revision and
                // reset preview authority. Publish it first, then bind the independently
                // verified capability to that exact resulting account/revision.
                let selected = current && canContinue
                if selected && previewOutcome != .denied, let socialState {
                    socialState.withPendingDisplayCachePreserved(owner: owner) {
                        publishSocialReceipt(verifiedPreviewGeneration: verifiedPreview ? generation : nil)
                    }
                } else {
                    // Native preview is an independent server grant. A valid
                    // preview-only account need not have a selected legacy
                    // social receipt; preserve the pre-existing publication rule.
                    // This does NOT authorize the early stale-cache presentation.
                    publishSocialReceipt(verifiedPreviewGeneration: current && verifiedPreview ? generation : nil)
                }
                if previewOutcome == .denied {
                    earlyCacheVerification = .denied
                    FeedStaleSummaryCache.shared.revokeAccountBoundary(viewerID: owner)
                } else if previewOutcome == .unavailable {
                    earlyCacheVerification = .unavailable
                } else {
                    earlyCacheVerification = selected ? .authorized : (current ? .denied : .unavailable)
                }
                if current && !selected { FeedStaleSummaryCache.shared.revokeAccountBoundary(viewerID: owner) }
                trace.mark(current ? "social-receipt-published" : "social-receipt-rejected")
            }
        }
        // Independent read-only requests share the captured account fence. The
        // capability result never publishes authority on its own; both original
        // revision checks below must still pass before the deferred publication.
        let previewRead = socialState == nil ? nil : Task { @MainActor [service, owner] in
            trace.mark("preview-request-start")
            do {
                guard let result = try await service.previewCapability() else {
                    trace.mark("preview-unavailable")
                    return FeedPrivacyPreviewCheck.unavailable
                }
                trace.mark("preview-response")
                return result.version == 1 && result.viewer_id == owner && result.enabled
                    ? FeedPrivacyPreviewCheck.allowed : FeedPrivacyPreviewCheck.denied
            } catch {
                trace.mark("preview-failed")
                return FeedPrivacyPreviewCheck.unavailable
            }
        }
        defer { previewRead?.cancel() }
        do {
            trace.mark("receipt-request-start")
            let value = try await service.fetch()
            trace.mark("service-response")
            guard operation == token, service.viewerID == owner, socialState?.accountGeneration == generation,
                  socialState?.revision == verificationRevision, !Task.isCancelled else { return }
            if (profileOnlyRules || verifiedPolicyVersion == 2) && value.policyVersion != 2 {
                throw ProfileOnlyPrivacyError.invalidReceipt
            }
            verifiedPolicyVersion = value.policyVersion
            receiptGeneration = generation
            receipt = value
            if let socialState {
                let outcome = await previewRead?.value ?? .notRequested
                guard operation == token, service.viewerID == owner, socialState.accountGeneration == generation,
                      socialState.revision == verificationRevision, !Task.isCancelled else { return }
                previewOutcome = outcome
                verifiedPreview = outcome == .allowed
            }
            verifiedLoad = true
            trace.mark("receipt-applied")
            if value.isSelected {
                selection = value.accountScope; workoutSelection = value.workoutDefault; shareMeasurements = value.shareMeasurements == true
                UserDefaults.standard.set(value.workoutDefault?.rawValue, forKey: "SOOM.workoutAudience.v1.\(owner.uuidString.lowercased())")
            }
            if !value.enabled { errorMessage = "공개범위 설정이 아직 준비되지 않았어요. 기록은 나만 볼 수 있게 보관합니다." }
        } catch {
            guard operation == token, service.viewerID == owner else { return }
            errorMessage = "공개범위를 확인하지 못했어요. 다시 시도해 주세요."
        }
    }
    var usesProfileOnlyRules: Bool { profileOnlyRules || verifiedPolicyVersion == 2 || receipt?.policyVersion == 2 }
    var canCompleteSharingSetup: Bool {
        guard networkAvailable, onboardingComplete, !busy, service.viewerID == owner,
              receipt?.enabled == true, let selection else { return false }
        if usesProfileOnlyRules { return receipt?.policyVersion == 2 }
        return selection == .privateAccount || workoutSelection == .publicPost || workoutSelection == .followers
    }
    /// Only this explicit completion action grants full measurements for newly
    /// prepared workout snapshots. Loading an old false receipt never grants it.
    @discardableResult
    func completeSharingSetup() async -> Bool {
        guard canCompleteSharingSetup else { return false }
        if usesProfileOnlyRules {
            let before = receipt
            workoutSelection = selection == .privateAccount ? .mutual : .publicPost
            await save(measurementConsent: before?.shareMeasurements == true)
            guard canContinue, receipt?.policyVersion == 2, let after = receipt,
                  after.revision == (before?.revision ?? 0) + 1,
                  after.shareMeasurements == before?.shareMeasurements else { return false }
            return true
        }
        if selection == .privateAccount { workoutSelection = .followers }
        let previousRevision = receipt?.revision ?? 0
        await save(measurementConsent: true)
        guard canContinue, service.viewerID == owner, let receipt,
              receipt.shareMeasurements == true, receipt.revision > previousRevision else { return false }
        FullWorkoutSharingConsent.record(owner: owner, revision: receipt.revision)
        return true
    }
    var canWithdrawMeasurements:Bool {
        canContinue && receipt?.policyVersion==2 && receipt?.shareMeasurements==true
            && (receipt?.measurementRevision ?? -1)>=0 && (receipt?.measurementRevision ?? Int64.max)<Int64.max
    }
    @discardableResult func withdrawMeasurements() async -> Bool {
        guard canWithdrawMeasurements,let before=receipt,let measurementRevision=before.measurementRevision else{return false}
        isCheckingSocialAccess=true;socialState?.setSocialVerified(false,owner:owner)
        let generation=socialState?.accountGeneration,token=UUID();operation=token;busy=true;errorMessage=nil
        defer {if operation==token {busy=false;publishSocialReceipt()}}
        do {
            let value=try await service.withdrawMeasurements(owner:owner,profileRevision:before.revision,measurementRevision:measurementRevision)
            guard operation==token,service.viewerID==owner,socialState?.accountGeneration==generation,!Task.isCancelled else{return false}
            guard value.policyVersion==2,value.isSelected,value.revision==before.revision,
                  value.accountScope==before.accountScope,value.workoutDefault==before.workoutDefault,
                  value.shareMeasurements==false,value.measurementRevision==measurementRevision+1 else {throw ProfileOnlyPrivacyError.changeNotConfirmed}
            self.receipt=value;receiptGeneration=generation;shareMeasurements=false
            CommunitySafetyStore.shared.invalidateRelationships()
            return true
        } catch {
            guard operation==token,service.viewerID==owner else{return false}
            receipt=nil;errorMessage="공유 중지 상태를 확인하지 못했어요. 공개범위를 다시 불러와 확인해 주세요."
            return false
        }
    }
    func save() async { await save(measurementConsent: shareMeasurements) }
    private func save(measurementConsent: Bool) async {
        guard networkAvailable, onboardingComplete, !busy, service.viewerID == owner, let selection, let receipt, receipt.enabled else { return }
        isCheckingSocialAccess = true
        socialState?.setSocialVerified(false, owner: owner)
        let generation = socialState?.accountGeneration
        let token = UUID(); operation = token; busy = true; errorMessage = nil
        defer { if operation == token { busy = false; publishSocialReceipt() } }
        do {
            let value = try await service.save(owner: owner, scope: selection, defaultWorkout: workoutSelection ?? selection.defaultWorkout,
                expectedRevision: receipt.revision, shareMeasurements: measurementConsent)
            guard operation == token, service.viewerID == owner, socialState?.accountGeneration == generation, !Task.isCancelled else { return }
            if receipt.policyVersion == 2 {
                guard value.policyVersion == 2, value.isSelected, value.accountScope == selection,
                      value.revision == receipt.revision + 1, value.shareMeasurements == receipt.shareMeasurements else {
                    throw FeedPostManagementError.changeNotConfirmed
                }
            }
            receiptGeneration = generation
            self.receipt = value
            shareMeasurements = value.shareMeasurements == true
            UserDefaults.standard.set(value.workoutDefault?.rawValue, forKey: "SOOM.workoutAudience.v1.\(owner.uuidString.lowercased())")
            CommunitySafetyStore.shared.invalidateRelationships()
        } catch {
            guard operation == token, service.viewerID == owner else { return }
            self.receipt = nil
            errorMessage = "저장을 확인하지 못했어요. 공개범위를 다시 불러온 뒤 선택해 주세요."
        }
    }
}
struct AccountPrivacySelectionView: View {
    @ObservedObject var model: AccountPrivacyModel
    var onCompletion: (() -> Void)? = nil
    var body: some View {
        if model.usesProfileOnlyRules {
            ProfileOnlyAccountPrivacySelectionContent(model: model, onCompletion: onCompletion)
        } else { legacyContent }
    }
    private var legacyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("계정 공개범위 설정").font(.title2.bold())
            Text("프로필과 운동을 볼 수 있는 사람을 계정 단위로 선택해 주세요.")
                .foregroundStyle(SOOMColor.secondaryInk)
            Text("계정 공개범위").font(.headline)
            ForEach(AccountAudience.allCases, id: \.rawValue) { scope in
                choice(title: scope.title,
                    detail: scope == .publicAccount ? "새 팔로우는 바로 성립해요." : "내가 승인한 팔로워만 운동을 볼 수 있어요.",
                    selected: model.selection == scope) {
                    model.selection = scope
                    model.workoutSelection = scope == .privateAccount ? .followers : .publicPost
                }
                .disabled(model.receipt?.accountScope == .privateAccount && scope == .publicAccount)
                .accessibilityIdentifier("privacy.choice.\(scope.rawValue)")
            }
            Text(model.selection == .privateAccount
                 ? "비공개 계정의 운동은 승인된 팔로워만 볼 수 있어요. 개별 운동을 전체공개로 바꾸는 기능은 제공하지 않아요."
                 : "공개 계정의 운동은 로그인한 사용자가 프로필에서 볼 수 있어요. 홈 피드에는 본인과 팔로잉의 운동만 표시돼요.")
                .font(.subheadline)
            Text("이전 기록은 본인 피드에 모두 표시되지만, 기존 공유 범위와 동의는 전환 확인 전까지 유지돼요.")
                .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
            VStack(alignment: .leading, spacing: 10) {
                Text("운동 상세도 함께 공유해요").font(.headline)
                Text("설정한 기본 공개범위는 완료 이후의 새 운동에 적용돼요. 공유되는 운동에는 경로, 측정 차트와 경로를 따라 움직이는 모션이 포함돼요. 본인 화면은 출발·도착 각각 반경 100m를 가려요. 공유 경로는 기존 반경 200m 보호를 유지해요. 보호 영역을 다시 지나는 구간도 숨겨져요.")
                Text("AI 해석, 회복과 과거 운동 비교는 본인만 볼 수 있어요. 기존 개인 전용 기록과 과거 측정자료는 자동으로 공개하지 않아요. 건강 기록 클라우드 저장 동의는 별도예요.")
                if model.receipt?.isSelected == true && model.receipt?.shareMeasurements != true {
                    Text("이전 설정은 그대로 보관되어 있어요. 아래 완료 버튼을 누르면 안내한 상세 공유에 동의합니다. 이전 운동은 자동으로 바뀌지 않으며, 기존 기록의 상세 공유 전환은 별도 확인이 필요해요.")
                        .accessibilityIdentifier("privacy.consent.transition")
                }
            }.font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("privacy.sharing.notice")
            if model.receipt?.accountScope == .privateAccount {
                Text("기존 비공개 계정은 유지됩니다.").font(.footnote)
            }
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(SOOMColor.warning)
            }
            Button {
                Task {
                    if await model.completeSharingSetup() { onCompletion?() }
                }
            } label: {
                HStack {
                    if model.busy { ProgressView() }
                    Text("설정 완료").font(.headline)
                }.frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent).disabled(!model.canCompleteSharingSetup)
            .accessibilityIdentifier("privacy.save")
            Text("완료하면 위 공개범위와 운동 상세 공유 내용에 동의합니다.")
                .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            Button("공개범위 다시 불러오기") { Task { await model.load() } }.disabled(model.busy)
        }.padding(SOOMLayout.screenPadding).background(SOOMColor.background)
    }
    private func choice(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16).background(SOOMColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}
/// Personal content stays mounted; only social entry points require a fresh receipt.
@MainActor
final class SocialConnectivityMonitor: ObservableObject {
    @Published private(set) var isOnline: Bool? = nil
    private var monitor: NWPathMonitor?
    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "SOOM.SocialConnectivity"))
        self.monitor = monitor
    }
    deinit { monitor?.cancel() }
}
private struct AccountPrivacyModelKey: EnvironmentKey { static let defaultValue: AccountPrivacyModel? = nil }
extension EnvironmentValues {
    var soomAccountPrivacyModel: AccountPrivacyModel? {
        get { self[AccountPrivacyModelKey.self] }
        set { self[AccountPrivacyModelKey.self] = newValue }
    }
}
enum SocialLoginDestination: String, Hashable { case feed, clubs, googleHealth }
private struct SOOMRequestLoginKey: EnvironmentKey {
    static let defaultValue: ((SocialLoginDestination) -> Void)? = nil
}
private struct SOOMOpenActivitiesKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    var soomOpenActivities: (() -> Void)? {
        get { self[SOOMOpenActivitiesKey.self] }
        set { self[SOOMOpenActivitiesKey.self] = newValue }
    }
    var soomRequestLogin: ((SocialLoginDestination) -> Void)? {
        get { self[SOOMRequestLoginKey.self] }
        set { self[SOOMRequestLoginKey.self] = newValue }
    }
}

struct SocialAccessBoundary<Content: View>: View {
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.soomAccountPrivacyModel) private var model
    @State private var showingSettings = false
    @Environment(\.soomRequestLogin) private var requestLogin
    var loginDestination: SocialLoginDestination = .feed
    var allowActivityPreview: Bool = false
    var allowsEarlyFeedCache: Bool = false
    @ViewBuilder let content: () -> Content
    private var needsLogin: Bool { !ReviewDemoMode.isActive && authViewModel.session.currentUser?.authProvider != .supabase }
    var body: some View {
        Group {
            if let model, !needsLogin {
                RetainedSocialPresentation(model: model, safety: safety, allowActivityPreview: allowActivityPreview,
                    allowsEarlyFeedCache: allowsEarlyFeedCache, onSettings: { showingSettings = true }, content: content)
            } else if (safety.canUseSocial || (allowActivityPreview && safety.canUseActivityPreview)) && !needsLogin { content().id(safety.accountGeneration) }
            else {
                if let model, !needsLogin {
                    SocialAccessStatusView(model: model) { showingSettings = true }
                } else {
                    SocialAccessPromptLayout {
                    VStack(spacing: 16) {
                        Label("로그인하고 함께 운동해요", systemImage: "person.2").font(.title2.bold())
                        Text("클럽과 소셜 기능은 계정의 공개범위와 권한 확인이 필요해요. 내 운동과 기록 시작은 계속 사용할 수 있어요.")
                            .font(.body).multilineTextAlignment(.center)
                        Button { requestLogin?(loginDestination) } label: {
                            Text(loginDestination == .clubs ? "로그인하고 클럽 둘러보기" : "로그인하고 피드 둘러보기")
                                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                        }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("social.login")
                    }
                    }
                }
            }
        }.sheet(isPresented: $showingSettings) {
            if let model {
                NavigationStack {
                    ScrollView {
                        AccountPrivacySelectionView(model: model, onCompletion: { showingSettings = false })
                    }
                        .navigationTitle(model.usesProfileOnlyRules ? "프로필 공개범위" : "계정 · 새 운동 공개범위")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showingSettings = false } } }
                        .task { await model.load() }
                }
            }
        }
    }
}
/// A prior verified hierarchy can survive a same-account foreground check.
/// It is invisible, untouchable and absent from accessibility until the fresh
/// receipt allows access. Initial verification and final denial do not mount it.
private struct RetainedSocialPresentation<Content: View>: View {
    @ObservedObject var model: AccountPrivacyModel
    @ObservedObject var safety: CommunitySafetyStore
    let allowActivityPreview: Bool
    let allowsEarlyFeedCache: Bool
    let onSettings: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var verifiedGeneration: Int?
    private var allowed: Bool { safety.canUseSocial || (allowActivityPreview && safety.canUseActivityPreview) }
    var body: some View {
        ZStack {
            if allowed || (model.isCheckingSocialAccess && verifiedGeneration == safety.accountGeneration) {
                content().id(safety.accountGeneration)
                    .opacity(allowed ? 1 : 0)
                    .allowsHitTesting(allowed).disabled(!allowed)
                    .accessibilityHidden(!allowed)
            }
            if !allowed {
                NavigationStack {
                    if allowsEarlyFeedCache && (model.earlyCacheVerification == .checking || model.earlyCacheVerification == .unresolved) {
                        FeedEarlyCachePendingView(model: model, onSettings: onSettings)
                    } else {
                        SocialAccessStatusView(model: model, onSettings: onSettings)
                    }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SOOMColor.background).zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if allowed { verifiedGeneration = safety.accountGeneration } }
        .onChange(of: allowed) { _, value in
            if value { verifiedGeneration = safety.accountGeneration }
        }
        .onChange(of: safety.accountGeneration) { _, _ in verifiedGeneration = nil }
        .onChange(of: model.isCheckingSocialAccess) { _, checking in
            if !checking && !allowed { verifiedGeneration = nil }
        }
    }
}
/// Observes only the status placeholder; verification never mounts protected content.
struct SocialAccessStatusView: View {
    @ObservedObject var model: AccountPrivacyModel
    var onSettings: () -> Void
    var body: some View {
        SocialAccessPromptLayout {
        VStack(spacing: 16) {
            if model.isCheckingSocialAccess {
                SOOMSkeleton(layout: .row, label: "공개범위를 확인하는 중")
                    .accessibilityIdentifier("social.verifying")
            } else {
                Label("소셜 기능을 잠갔어요", systemImage: "lock").font(.headline)
                Text("공개범위를 확인한 뒤 피드와 공유를 사용할 수 있어요. 내 운동·지도·사진·분석과 기록 시작은 계속 사용할 수 있어요.")
                    .multilineTextAlignment(.center)
                Button(action: onSettings) {
                    Text("공개범위 확인 · 설정").frame(minHeight: 44)
                }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("social.lock.settings")
            }
        }
        }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(model.isCheckingSocialAccess ? "social.checking" : "social.locked")
    }
}
private struct SocialAccessPromptLayout<Content: View>: View {
    @Environment(\.soomBottomOverlayInset) private var bottomOverlayInset
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            content().fixedSize(horizontal: false, vertical: true)
                .padding().frame(maxWidth: .infinity)
                .padding(.top, 32)
                .padding(.bottom, bottomOverlayInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
private struct SocialAccessModifier: ViewModifier {
    func body(content: Content) -> some View { SocialAccessBoundary { content } }
}
extension View { func protectsSocialAccess() -> some View { modifier(SocialAccessModifier()) } }
/// React to connectivity transitions, not publisher subscription replay during
/// view updates. Replaying the current value mutates the observed model again
/// and can keep SwiftUI's update transaction running indefinitely at startup.
struct AccountPrivacyConnectivityModifier: ViewModifier {
    @ObservedObject var model: AccountPrivacyModel
    let isOnline: Bool?

    func body(content: Content) -> some View {
        content.onChange(of: isOnline, initial: true) { _, online in
            // NWPathMonitor has not provided a result yet; unknown is not offline.
            guard let online else { return }
            model.setNetworkAvailable(online)
            if online && !model.canContinue { Task { await model.load() } }
        }
    }
}

struct AccountPrivacyRootGate<Content: View>: View {
    let owner: UUID
    let onboardingComplete: Bool
    let content: () -> Content
    @StateObject private var model: AccountPrivacyModel
    @StateObject private var connectivity = SocialConnectivityMonitor()
    @Environment(\.scenePhase) private var scenePhase
    init(owner: UUID, onboardingComplete: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.owner = owner; self.content = content; self.onboardingComplete = onboardingComplete
        let service: any AccountPrivacyServing
        if let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() {
            service = SupabaseAccountPrivacyService(client: client)
        } else { service = UnavailableAccountPrivacyService() }
        _model = StateObject(wrappedValue: AccountPrivacyModel(owner: owner, service: service, socialState: .shared, onboardingComplete: onboardingComplete))
    }
    var body: some View {
        content().environment(\.soomAccountPrivacyModel, model)
            .task { connectivity.start() }
            .modifier(AccountPrivacyConnectivityModifier(model: model, isOnline: connectivity.isOnline))
            .onChange(of: onboardingComplete) { _, complete in
                model.setOnboardingComplete(complete)
                if complete { Task { await model.load() } }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
                else { model.suspendSocialAccess() }
            }

    }
}
@MainActor
protocol IncomingFollowServing {
    var viewerID: UUID? { get }
    func incoming(after: IncomingFollowRequest?) async throws -> [IncomingFollowRequest]
    func review(_ request: IncomingFollowRequest, action: String, actor: UUID) async throws
}
extension SupabaseAccountPrivacyService: IncomingFollowServing {}

struct FollowRequestsView: View {
    private let suppliedService: (any IncomingFollowServing)?
    init(service: (any IncomingFollowServing)? = nil) { suppliedService = service }
    @State private var rows: [IncomingFollowRequest] = []
    @State private var query = ""
    @State private var cursor: IncomingFollowRequest?
    @State private var error: String?
    @State private var loading = false
    @State private var busy = Set<UUID>()
    @State private var hasMore = false
    @State private var loadRequest = UUID()
    @ObservedObject private var safety = CommunitySafetyStore.shared
    var body: some View {
        SocialAccessBoundary {
        List {
            NavigationLink("기존 팔로워 확인") { LegacyFollowerReviewView(service: suppliedService as? any LegacyFollowerReviewServing) }
                .accessibilityIdentifier("follow.requests.legacy")
            if let error { Text(error).foregroundStyle(SOOMColor.warning) }
            if loading && rows.isEmpty { SOOMSkeleton(layout: .list, label: "팔로우 요청 불러오는 중") }
            ForEach(rows.filter { $0.matches(search: query) }) { request in
                VStack(alignment: .leading, spacing: 8) {
                    SOOMProfileLink(userID: request.userID, profile: request.profile) {
                        HStack(spacing: 12) {
                            SOOMAvatarView(userID: request.userID, avatarPath: request.avatarPath, size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.displayName).font(.headline)
                                if let handle = request.handle { Text(handle.hasPrefix("@") ? handle : "@" + handle).font(.caption).foregroundStyle(.secondary) }
                                Text(request.state == .pending ? "요청됨" : "승인된 팔로워").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(minHeight: 48)
                    }.buttonStyle(.plain).accessibilityLabel("\(request.displayName) 프로필 열기")
                    HStack {
                        if request.state == .pending {
                            Button("승인") { Task { await review(request, "approve") } }.accessibilityIdentifier("follow.requests.approve.\(request.userID)")
                            Button("거절") { Task { await review(request, "reject") } }.accessibilityIdentifier("follow.requests.reject.\(request.userID)")
                        } else { Button("팔로워 제거") { Task { await review(request, "remove") } }.accessibilityIdentifier("follow.requests.remove.\(request.userID)") }
                    }.buttonStyle(.bordered).disabled(busy.contains(request.id))
                }.padding(.vertical, 8)
            }
            if rows.filter({ $0.matches(search: query) }).isEmpty && !loading && error == nil {
                Text(query.isEmpty ? "팔로우 요청과 승인된 팔로워가 없어요." : "검색 결과가 없어요.")
            }
            if hasMore { Button("더 보기") { Task { await load(reset: false) } }.disabled(loading) }
            Button("새로고침") { Task { await load() } }.disabled(loading)
        }.navigationTitle("팔로우 요청 · 승인 관리")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "이름 또는 사용자 이름")
            .task(id: query) {
                if !query.isEmpty { do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return } }
                guard !Task.isCancelled else { return }
                await load()
            }
            .onChange(of: safety.accountGeneration) { _, _ in rows = []; error = nil; loadRequest = UUID(); loading = false }
             .onChange(of: safety.revision) { _, _ in
                rows = []; cursor = nil; hasMore = false; loadRequest = UUID(); loading = false
                if busy.isEmpty { Task { await load() } }
            }
    
        }
    }
    private func service() -> (any IncomingFollowServing)? {
        if let suppliedService { return suppliedService }
        return SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient().map { SupabaseAccountPrivacyService(client:$0) }
    }
    @MainActor private func load(reset: Bool = true) async {
        guard reset || !loading else { return }
        guard let service = service(), let viewer = service.viewerID, viewer == safety.viewerID else { rows = []; return }
        let generation = safety.accountGeneration, revision = safety.revision
        let token = UUID(); loadRequest = token
        loading = true; error = nil
        let selectedQuery = query
        if reset { rows = []; cursor = nil; hasMore = false }
        let initialMatchCount = rows.filter { $0.matches(search: selectedQuery) }.count
        defer { if loadRequest == token { loading = false } }
        do {
            repeat {
                let previousCursor = cursor
                let values = try await service.incoming(after: cursor)
                guard service.viewerID == viewer, safety.viewerID == viewer, safety.accountGeneration == generation,
                      safety.revision == revision, loadRequest == token, selectedQuery == query, !Task.isCancelled else { return }
                var ids = Set(rows.map(\.id)); rows += values.filter { ids.insert($0.id).inserted }
                cursor = values.last ?? cursor; hasMore = values.count == 50
                if hasMore, let previousCursor, cursor?.id == previousCursor.id { throw FeedPostManagementError.changeNotConfirmed }
            } while !selectedQuery.isEmpty && hasMore && rows.filter({ $0.matches(search: selectedQuery) }).count - initialMatchCount < 50

        } catch { guard safety.accountGeneration == generation, loadRequest == token, safety.revision == revision else { return }; rows = []; self.error = "현재 상태를 확인하지 못했어요. 다시 불러와 주세요." }
    }
    @MainActor private func review(_ request: IncomingFollowRequest, _ action: String) async {
        guard let service = service(), let viewer = service.viewerID, viewer == safety.viewerID, rows.contains(request), busy.insert(request.id).inserted else { return }
        let generation = safety.accountGeneration
        defer { busy.remove(request.id) }
        safety.invalidateRelationships()
        do {
            try await service.review(request, action: action,actor:viewer)
            guard service.viewerID == viewer, safety.viewerID == viewer, generation == safety.accountGeneration else { return }
            safety.invalidateRelationships()
            NotificationCenter.default.post(name: FeedFollowingStore.didChange, object: nil, userInfo: ["viewerID": viewer])
            await load()
        } catch { guard generation == safety.accountGeneration else { return }; await load(); self.error = "요청 변경을 확인하지 못했어요. 현재 상태를 다시 확인해 주세요." }
    }
}

@MainActor
private struct UnavailableAccountPrivacyService: AccountPrivacyServing {
    var viewerID: UUID? { nil }
    func fetch() async throws -> AccountPrivacyReceipt { throw CommunitySafetyError.unavailable }
    func save(owner: UUID, scope: AccountAudience, defaultWorkout: FeedPostVisibility, expectedRevision: Int64, shareMeasurements: Bool) async throws -> AccountPrivacyReceipt { throw CommunitySafetyError.unavailable }
}

struct AccountPrivacySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.soomAutomaticActivitySync) private var automaticSync
    @Environment(\.soomAccountPrivacyModel) private var rootModel
    @StateObject private var model: AccountPrivacyModel
    private let owner: UUID
    init(owner: UUID) {
        self.owner = owner
        let service: any AccountPrivacyServing
        if let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() { service = SupabaseAccountPrivacyService(client: client) }
        else { service = UnavailableAccountPrivacyService() }
        _model = StateObject(wrappedValue: AccountPrivacyModel(owner: owner, service: service))
    }
    var body: some View {
        ScrollView {
            VStack {
                AccountPrivacySelectionView(model: rootModel ?? model, onCompletion: { dismiss() })
                if let automaticSync {
                    AccountActivityAutomaticSyncStatusView(coordinator: automaticSync).padding()
                }
                if (rootModel ?? model).usesProfileOnlyRules {
                    WorkoutExistingDetailRefreshStatusView().padding()
                }
                if AccountActivityFeedReleaseGate.productionReady, !(rootModel ?? model).usesProfileOnlyRules,
                   let privacy = (rootModel ?? model).receipt, privacy.isSelected,
                   let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() {
                    NavigationLink("내 과거 운동 · 새 운동에 프로필 규칙 적용") {
                        AccountActivityOwnerTransitionDestination(owner: owner, privacy: privacy, client: client)
                    }.padding()
                }
            }
        }.navigationTitle((rootModel ?? model).usesProfileOnlyRules ? "프로필 공개범위" : "계정 · 새 운동 공개범위")
            .task { await (rootModel ?? model).load() }
    }
}

#if DEBUG
/// Explicitly opened from the local DEMO banner. No session, network client,
/// production launch argument or real account is replaced by this fixture.
@MainActor
final class PrivacyLocalQAService: ObservableObject, AccountPrivacyServing, IncomingFollowServing, ProfileSocialServing, ProfileSearchServing, LegacyFollowerReviewServing {
    static let privateID = UUID(uuidString: "D3200000-0000-4000-8000-000000000001")!
    static let publicID = UUID(uuidString: "D3200000-0000-4000-8000-000000000002")!
    var viewerID: UUID? { ReviewDemoMode.isActive ? ReviewDemoMode.userID : nil }
    @Published var receipt = AccountPrivacyReceipt(enabled:true,accountScope:nil,workoutDefault:nil,revision:0,shareMeasurements:false)
    @Published var failLoad = false
    #if DEBUG && targetEnvironment(simulator)
    var holdNextNavigationFetch = false
    @Published private(set) var navigationFetchHeld = false
    private var navigationFetchContinuation: CheckedContinuation<Void, Never>?
    func releaseNavigationFetch() {
        let continuation = navigationFetchContinuation; navigationFetchContinuation = nil
        navigationFetchHeld = false; continuation?.resume()
    }
    #endif
    var nextFetchDelayNanoseconds: UInt64 = 0
    @Published var failNextSave = false
    @Published var writes = 0
    static let legacyID = UUID(uuidString: "D3200000-0000-4000-8000-000000000003")!
    static let legacyDismissID = UUID(uuidString: "D3200000-0000-4000-8000-000000000004")!
    private var legacyRows: [LegacyFollowerCandidate] = []
    private var reviewedEdges = Set<UUID>()
    private var outgoing: [UUID: ApprovedFollowReceipt] = [:]
    private var requests: [IncomingFollowRequest] = []
    init() {
        legacyRows = [Self.legacyID, Self.legacyDismissID].enumerated().map { index, id in
            .init(userID: id, edgeID: UUID(), displayName: index == 0 ? "기존 팔로워 샘플" : "보류할 기존 팔로워", handle: nil, avatarPath: nil, followedAt: Date(timeIntervalSince1970: Double(2-index)))
        }
        for (id,name) in [(Self.privateID,"비공개 샘플"),(Self.publicID,"공개 샘플")] {
            requests.append(.init(userID:id,requestID:UUID(),displayName:name,handle:nil,avatarPath:nil,state:.pending,createdAt:Date()))
        }
    }
    private func validate(_ actor: UUID? = nil) throws {
        guard let viewerID, actor == nil || actor == viewerID else { throw CommunitySafetyError.accountChanged }
    }
    func previewCapability() async throws -> AccountActivityPreviewCapability? {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive,
           ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1",
           ProcessInfo.processInfo.environment["SOOM_DETAIL_REVALIDATION_QA"] == "1" {
            try validate()
            return .init(version: 1, viewer_id: ReviewDemoMode.userID, enabled: true,
                owner_rules_accepted: true, account_scope: .publicAccount, scope_revision: receipt.revision,
                share_measurements: false)
        }
        #endif
        return nil
    }
    func fetch() async throws -> AccountPrivacyReceipt {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, holdNextNavigationFetch,
           ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1",
           ProcessInfo.processInfo.environment["SOOM_DETAIL_REVALIDATION_QA"] == "1" {
            holdNextNavigationFetch = false
            await withCheckedContinuation { continuation in
                navigationFetchContinuation = continuation; navigationFetchHeld = true
            }
        }
        #endif

        let delay = nextFetchDelayNanoseconds; nextFetchDelayNanoseconds = 0
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        if failLoad { throw CommunitySafetyError.unavailable }; try validate(); return receipt
    }
    func save(owner:UUID,scope:AccountAudience,defaultWorkout:FeedPostVisibility,expectedRevision:Int64,shareMeasurements:Bool) async throws -> AccountPrivacyReceipt {
        try validate(owner)
        try await Task.sleep(nanoseconds:300_000_000)
        try validate(owner)
        if failNextSave { failNextSave=false;throw CommunitySafetyError.unavailable }
        guard receipt.revision == expectedRevision,
              receipt.policyVersion == 2 || !(receipt.accountScope == .privateAccount && scope == .publicAccount),
              !(scope == .privateAccount && defaultWorkout == .publicPost) else { throw FeedPostManagementError.changeNotConfirmed }
        if receipt.policyVersion == 2 {
            guard defaultWorkout == (scope == .privateAccount ? .mutual : .publicPost),
                  shareMeasurements == receipt.shareMeasurements else { throw FeedPostManagementError.changeNotConfirmed }
        }
        writes += 1
        receipt = .init(enabled:true,accountScope:scope,workoutDefault:defaultWorkout,revision:expectedRevision+1,
                        shareMeasurements:shareMeasurements,policyVersion:receipt.policyVersion,measurementRevision:receipt.measurementRevision)
        return try await fetch()
    }
    func withdrawMeasurements(owner:UUID,profileRevision:Int64,measurementRevision:Int64) async throws -> AccountPrivacyReceipt {
        try validate(owner)
        guard receipt.policyVersion==2,receipt.revision==profileRevision,receipt.measurementRevision==measurementRevision else {throw ProfileOnlyPrivacyError.changeNotConfirmed}
        receipt.shareMeasurements=false;receipt.measurementRevision=measurementRevision+1
        return receipt
    }
    func legacyReviewEnabled(owner: UUID) async throws -> Bool { try validate(owner); return true }
    func legacyCandidates(owner: UUID, after: LegacyFollowerCandidate?) async throws -> [LegacyFollowerCandidate] {
        try validate(owner); return after == nil ? legacyRows.filter { !reviewedEdges.contains($0.edgeID) } : []
    }
    func reviewLegacy(_ candidate: LegacyFollowerCandidate, owner: UUID, action: LegacyFollowerReviewAction) async throws {
        try validate(owner)
        try await Task.sleep(nanoseconds: 150_000_000)
        try validate(owner)
        guard legacyRows.contains(candidate), !reviewedEdges.contains(candidate.edgeID) else { throw FeedPostManagementError.changeNotConfirmed }
        reviewedEdges.insert(candidate.edgeID)
        if action == .approve {
            requests.append(.init(userID:candidate.userID,requestID:UUID(),displayName:candidate.displayName,handle:candidate.handle,avatarPath:nil,state:.accepted,createdAt:Date()))
        }
    }
    func incoming(after:IncomingFollowRequest?) async throws -> [IncomingFollowRequest] {
        try validate(); return after == nil ? requests : []
    }
    func review(_ request:IncomingFollowRequest,action:String,actor:UUID) async throws {
        try validate(actor)
        try await Task.sleep(nanoseconds:150_000_000)
        try validate(actor)
        guard let index=requests.firstIndex(where:{$0.requestID == request.requestID && $0.userID == request.userID}) else { throw FeedPostManagementError.changeNotConfirmed }
        if action == "approve" {
            requests[index] = .init(userID:request.userID,requestID:request.requestID,displayName:request.displayName,handle:request.handle,avatarPath:nil,state:.accepted,createdAt:request.createdAt)
        } else if action == "reject" || action == "remove" { requests.remove(at:index) }
        else { throw CommunitySafetyError.invalidDetails }
    }
    func summary(ownerID:UUID) async throws -> SocialSummary {
        try validate();return .init(postCount:0,followerCount:requests.filter{$0.state == .accepted}.count,followingCount:outgoing.values.filter{$0.state == .accepted}.count)
    }
    func people(ownerID:UUID,kind:SocialPeopleKind,after:SocialPerson?,limit:Int) async throws -> [SocialPerson] {
        try validate();guard after == nil else { return [] }
        return [Self.privateID,Self.publicID].map { id in
            let state = outgoing[id]?.state ?? .none
            return .init(id:id,displayName:id == Self.privateID ? "비공개 샘플" : "공개 샘플",handle:nil,avatarPath:nil,followedAt:Date(timeIntervalSince1970:1),isFollowing:state == .accepted,followsViewer:false,approvedState:state,approvedAccountScope:id == Self.privateID ? "private" : "public")
        }
    }
    func setFollowing(_ enabled:Bool,userID:UUID) async throws -> Bool {
        try validate()
        try await Task.sleep(nanoseconds:150_000_000)
        try validate()
        let state:ApprovedFollowState = enabled ? (userID == Self.publicID ? .accepted : .pending) : .none
        if outgoing[userID]?.state != state {
            outgoing[userID] = .init(userID:userID,state:state,requestID:state == .none ? nil : UUID(),accountScope:userID == Self.privateID ? "private" : "public")
        }
        return enabled
    }
    func search(query:String,after:ProfileSearchPerson?,limit:Int) async throws -> [ProfileSearchPerson] {
        try validate()
        let rows = (0..<25).map { i in ProfileSearchPerson(id:UUID(uuidString:String(format:"D3300000-0000-4000-8000-%012d",i))!,displayName:String(format:"비공개 검색 샘플 %02d",i),handle:"private_sample_\(i)",avatarPath:nil) }
        return rows.filter { ($0.displayName.contains(query) || $0.handle?.contains(query) == true) && (after == nil || $0.displayName > after!.displayName) }.prefix(limit).map{$0}
    }
}

@MainActor
final class PrivacyLocalQAFeedRemote: ObservableObject, FeedPostRemoteManaging {
    @Published var allowed = true
    private var openedPostID: UUID?
    var sessionUserID:UUID? { ReviewDemoMode.isActive ? ReviewDemoMode.userID : nil }
    func fetchPost(id:UUID,viewerID:UUID) async throws -> FeedItem? {
        guard sessionUserID == viewerID else { throw CommunitySafetyError.accountChanged }
        openedPostID = id
        return allowed ? try await ReviewDemoCommunityStore.shared.fetchPost(id:id,viewerID:viewerID) : nil
    }
    func setBookmark(postID:UUID,viewerID:UUID,isSaved:Bool) async throws { guard allowed else { throw FeedPostManagementError.contentUnavailable };try await ReviewDemoCommunityStore.shared.setBookmark(postID:postID,viewerID:viewerID,isSaved:isSaved) }
    func editPost(id:UUID,ownerID:UUID,title:String,description:String) async throws { throw CommunitySafetyError.invalidTarget }
    func setVisibility(postID:UUID,ownerID:UUID,visibility:FeedPostVisibility) async throws { throw CommunitySafetyError.invalidTarget }
    func deletePost(id:UUID,ownerID:UUID) async throws { throw CommunitySafetyError.invalidTarget }
    func revoke() {
        allowed=false
        if let id=openedPostID { ReviewDemoCommunityStore.shared.denyPostForLocalQA(id) }
        CommunitySafetyStore.shared.invalidateRelationships()
    }
}

struct PrivacyLocalQAView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service:PrivacyLocalQAService
    @StateObject private var model:AccountPrivacyModel
    @State private var showingSelection=true
    @State private var showingLocalGateQA=false
    @StateObject private var tabBarVisibility=SOOMTabBarVisibility()
    init() {
        let service=PrivacyLocalQAService()
        _service=StateObject(wrappedValue:service)
        _model=StateObject(wrappedValue:AccountPrivacyModel(owner:ReviewDemoMode.userID,service:service,profileOnlyRules:false))
    }
    var body:some View {
        NavigationStack {
            Group {
                if showingSelection {
                    ScrollView {
                        Text("로컬 합성 QA · 실제 계정/서버 미사용").font(.caption)
                        #if targetEnvironment(simulator)
                        NavigationLink("프로필 규칙 v2 체험") { ProfileOnlyPrivacyLocalQAView() }
                            .accessibilityIdentifier("qa.profileOnly.open")
                        #endif
                        Button("다음 저장 실패 체험") { service.failNextSave=true }.accessibilityIdentifier("qa.privacy.fail")
                        Button("기존 상세 공유 꺼짐 체험") {
                            service.receipt = .init(enabled: true, accountScope: .publicAccount,
                                workoutDefault: .followers, revision: 4, shareMeasurements: false)
                            Task { await model.load() }
                        }.accessibilityIdentifier("qa.privacy.legacyConsent")
                        AccountPrivacySelectionView(model:model)
                    }
                } else {
                    List {
                        Text("서버 재조회 확인: \(service.receipt.accountScope?.title ?? "미선택") · 저장 \(service.writes)회").accessibilityIdentifier("qa.privacy.saved")
                        Text("경로·차트 동의: \(service.receipt.shareMeasurements == true ? "켜짐" : "꺼짐")")
                        Button("선택 화면 다시 열기") { showingSelection=true;Task{await model.load()} }.accessibilityIdentifier("qa.privacy.reentry")
                        Button("개인 기능 · 소셜 잠금 QA") { showingLocalGateQA=true }.accessibilityIdentifier("qa.localAccess")
                        NavigationLink("받은 요청 체험") { FollowRequestsView(service:service) }.accessibilityIdentifier("qa.requests")
                        NavigationLink("팔로우 · 취소 체험") { ProfileSocialPeopleView(ownerID:ReviewDemoMode.userID,kind:.followers,service:service) }.accessibilityIdentifier("qa.outgoing")
                        NavigationLink("비공개 사용자 검색 체험") { ProfileSearchView(service:service) }.accessibilityIdentifier("qa.search")
                        NavigationLink("권한 회수 · 공통 상세 체험") { PrivacyLocalQARevocationView() }.accessibilityIdentifier("qa.revocation")
                    }
                }
            }.navigationTitle("공개범위 로컬 QA")
                .toolbar { ToolbarItem(placement:.cancellationAction){Button("QA 닫기"){dismiss()}.accessibilityIdentifier("qa.close")} }
                .task { await model.load() }
                .onChange(of:model.canContinue) { _,ready in if ready { showingSelection=false } }
        }.environmentObject(tabBarVisibility)
        .fullScreenCover(isPresented:$showingLocalGateQA) { LocalAccessGateQAView() }
    }
}
struct PrivacyLocalQARevocationView: View {
    @StateObject private var remote=PrivacyLocalQAFeedRemote()
    var body:some View {
        Group {
            if let item=ReviewDemoCommunityStore.shared.items.first(where:{$0.permittedSharedDetail != nil && $0.authorId != ReviewDemoMode.userID}) {
                FeedItemDetailView(item:item,remote:remote)
            } else { Text("합성 피어 없음") }
        }.overlay(alignment:.topTrailing) {
            Button("5초 후 권한 회수") { Task { try? await Task.sleep(nanoseconds:5_000_000_000);remote.revoke() } }
                .accessibilityIdentifier("qa.revoke").padding(12).background(.regularMaterial,in:Capsule()).padding(8)
        }
    }
}

/// Synthetic controls drive the same model, RootTabView and boundaries. No real session changes.
struct LocalAccessGateQAView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service: PrivacyLocalQAService
    @StateObject private var model: AccountPrivacyModel
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @EnvironmentObject private var router: NotificationDeepLinkRouter
    @State private var onboarding = true
    init() {
        let service = PrivacyLocalQAService()
        service.receipt = AccountPrivacyReceipt(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1,shareMeasurements:false)
        _service = StateObject(wrappedValue: service)
        _model = StateObject(wrappedValue: AccountPrivacyModel(owner: ReviewDemoMode.userID, service: service, socialState: .shared, profileOnlyRules: false))
    }
    var body: some View {
        RootTabView().environment(\.soomAccountPrivacyModel, model)
            .safeAreaInset(edge: .top) {
                VStack {
                    HStack { Text("합성 소셜 상태 · 내 기록 원본 유지").font(.caption);Button("QA 종료") { safety.configureForDemo();dismiss() } }
                    HStack {
                        Button("서버 off") {
                            service.receipt = .init(enabled:false,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1,shareMeasurements:false)
                            Task { await model.load() }
                        }.accessibilityIdentifier("gate.off")
                        Button("조회 실패") { service.failLoad=true;Task { await model.load() } }.accessibilityIdentifier("gate.failure")
                        Button("재확인") {
                            service.nextFetchDelayNanoseconds = 2_000_000_000
                            Task { await model.load() }
                        }.accessibilityIdentifier("gate.verifyDelayed")
                        Button("오프라인") { model.setNetworkAvailable(false) }.accessibilityIdentifier("gate.offline")
                        Button("5초 끊기") { Task { try? await Task.sleep(nanoseconds:5_000_000_000);model.setNetworkAvailable(false) } }.accessibilityIdentifier("gate.delayOffline")
                    }
                    HStack {
                        Button("재연결") {
                            service.failLoad=false
                            service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1,shareMeasurements:false)
                            model.setNetworkAvailable(true);model.setOnboardingComplete(onboarding)
                            Task { await model.load() }
                        }.accessibilityIdentifier("gate.reconnect")
                        Button("계정 교체") {
                            safety.setViewerID(PrivacyLocalQAService.privateID);safety.setViewerID(ReviewDemoMode.userID)
                            model.suspendSocialAccess()
                        }.accessibilityIdentifier("gate.account")
                        Button("안내 미완료") { onboarding=false;model.setOnboardingComplete(false) }.accessibilityIdentifier("gate.onboarding")
                        Button("딥링크") { router.routeToPost(id:UUID()) }.accessibilityIdentifier("gate.deeplink")
                    }.font(.caption)
                    HStack {
                        Button("공개범위 미선택 QA") {
                            service.receipt = .init(enabled: true, accountScope: nil, workoutDefault: nil, revision: 0, shareMeasurements: false)
                            Task { await model.load() }
                        }.accessibilityIdentifier("gate.unselected")
                        Button("다음 저장 실패 QA") { service.failNextSave = true }
                            .accessibilityIdentifier("gate.failNextSave")
                    }.font(.caption)
                }.padding(4).background(.regularMaterial)
            }
            .task { await model.load() }

    }
}
#endif

// MARK: - Profile-only candidate contract (not a legacy receipt upgrade)

/// Explicit build opt-in only. Server readiness, version, owner and revision are
/// still verified for every lease; a build flag never grants data authority.
/// Distribution must record this compilation condition beside the server digest.
enum ProfileOnlyPrivacyReleaseGate {
    #if SOOM_PROFILE_ONLY_V2
    static let productionReady = true
    #else
    static let productionReady = false
    #endif
}
enum ProfileOnlyPrivacyError: Error, Equatable {
    case disabled, invalidReceipt, accountChanged, changeNotConfirmed
}
struct ProfileOnlyPrivacyContext: Equatable {
    let ownerID: UUID
    let generation: Int
}
struct ProfileOnlyPrivacyReceipt: Decodable, Equatable {
    let version: Int
    let ownerID: UUID
    let enabled: Bool
    let scope: AccountAudience?
    let revision: Int64
    let shareMeasurements: Bool
    var releaseReady: Bool? = nil
    var measurementRevision:Int64? = nil
    var workoutAudience: FeedPostVisibility? {
        scope.map { $0 == .publicAccount ? .publicPost : .mutual }
    }
    enum CodingKeys: String, CodingKey {
        case version, enabled, revision, scope = "account_scope"
        case ownerID = "owner_id", shareMeasurements = "share_measurements", releaseReady = "release_ready", measurementRevision = "measurement_revision"
    }
    func validate(owner: UUID, allowUnselected: Bool = false) throws {
        guard version == 2, enabled, ownerID == owner, revision >= 0, revision < Int64.max else {
            throw ProfileOnlyPrivacyError.invalidReceipt
        }
        guard (scope != nil && revision > 0) || (allowUnselected && scope == nil && revision >= 0) else {
            throw ProfileOnlyPrivacyError.invalidReceipt
        }
    }
    func accountPrivacyReceipt() throws -> AccountPrivacyReceipt {
        try validate(owner: ownerID, allowUnselected: true)
        return .init(enabled: enabled, accountScope: scope, workoutDefault: workoutAudience,
                     revision: revision, shareMeasurements: shareMeasurements, policyVersion: 2, measurementRevision:measurementRevision)
    }
}
/// This candidate write deliberately has no per-workout or measurement-consent
/// argument. Changing the audience must not create/upgrade a health/GPS receipt.
@MainActor protocol ProfileOnlyPrivacyServing {
    var context: ProfileOnlyPrivacyContext? { get }
    func fetchProfileOnly() async throws -> ProfileOnlyPrivacyReceipt
    func saveProfileOnly(scope: AccountAudience, expectedRevision: Int64) async throws -> ProfileOnlyPrivacyReceipt
}
@MainActor final class ProfileOnlyPrivacyModel: ObservableObject {
    @Published private(set) var receipt: ProfileOnlyPrivacyReceipt?
    @Published private(set) var busy = false
    @Published private(set) var error: ProfileOnlyPrivacyError?
    @Published var selection: AccountAudience?
    private let service: any ProfileOnlyPrivacyServing
    private let owner: UUID
    private let fixture: Bool
    private var operation = UUID()
    private var verifiedContext: ProfileOnlyPrivacyContext?
    init(owner: UUID, service: any ProfileOnlyPrivacyServing) {
        self.owner = owner; self.service = service; fixture = false
    }
    #if DEBUG
    init(fixtureOwner: UUID, service: any ProfileOnlyPrivacyServing) {
        owner = fixtureOwner; self.service = service; fixture = true
    }
    #endif
    var canSave: Bool {
        (fixture || ProfileOnlyPrivacyReleaseGate.productionReady) && !busy && selection != nil
            && receipt != nil && verifiedContext != nil && service.context == verifiedContext
    }
    /// Call on logout, network suspension, or relationship-policy invalidation.
    /// Late responses cannot repopulate a receipt after suspension.
    func suspend() {
        operation = UUID(); receipt = nil; verifiedContext = nil; selection = nil; busy = false
    }
    private func context() throws -> ProfileOnlyPrivacyContext {
        guard fixture || ProfileOnlyPrivacyReleaseGate.productionReady else { throw ProfileOnlyPrivacyError.disabled }
        guard let context = service.context, context.ownerID == owner, context.generation >= 0 else {
            throw ProfileOnlyPrivacyError.accountChanged
        }
        return context
    }
    private func check(_ context: ProfileOnlyPrivacyContext, token: UUID) throws {
        guard !Task.isCancelled, operation == token, service.context == context else {
            throw ProfileOnlyPrivacyError.accountChanged
        }
    }
    func load() async {
        guard !busy else { return }
        suspend(); let token = operation; busy = true; error = nil
        defer { if operation == token { busy = false } }
        do {
            let current = try context()
            try check(current, token: token)
            let value = try await service.fetchProfileOnly()
            try check(current, token: token); try value.validate(owner: owner, allowUnselected: true)
            receipt = value; selection = value.scope; verifiedContext = current
        } catch {
            guard operation == token else { return }
            receipt = nil; verifiedContext = nil
            self.error = (error as? ProfileOnlyPrivacyError) ?? .invalidReceipt
        }
    }
    @discardableResult func save() async -> Bool {
        guard canSave, let before = receipt, let selected = selection, let current = verifiedContext else { return false }
        let token = UUID(); operation = token; busy = true; error = nil
        // Fail closed throughout the write/readback interval.
        receipt = nil; verifiedContext = nil
        defer { if operation == token { busy = false } }
        do {
            try check(current, token: token)
            let written = try await service.saveProfileOnly(scope: selected, expectedRevision: before.revision)
            try check(current, token: token); try written.validate(owner: owner)
            guard written.scope == selected, written.revision == before.revision + 1,
                  written.shareMeasurements == before.shareMeasurements else {
                throw ProfileOnlyPrivacyError.changeNotConfirmed
            }
            let confirmed = try await service.fetchProfileOnly()
            try check(current, token: token); try confirmed.validate(owner: owner)
            guard confirmed == written else { throw ProfileOnlyPrivacyError.changeNotConfirmed }
            receipt = confirmed; selection = confirmed.scope; verifiedContext = current
            return true
        } catch {
            guard operation == token else { return false }
            receipt = nil; verifiedContext = nil
            self.error = (error as? ProfileOnlyPrivacyError) ?? .changeNotConfirmed
            return false
        }
    }
}

/// The v2 transport has no measurement-consent, owner-override or per-card
/// audience arguments. A successful scope change must read back exactly.
@MainActor struct SupabaseProfileOnlyPrivacyService: ProfileOnlyPrivacyServing {
    private let client: SupabaseClient
    private let current: () -> ProfileOnlyPrivacyContext?
    private let synthetic: Bool
    init(client: SupabaseClient) {
        self.client = client; synthetic = false
        current = {
            let safety = CommunitySafetyStore.shared
            guard let owner = client.auth.currentSession?.user.id, safety.viewerID == owner else { return nil }
            return .init(ownerID: owner, generation: safety.accountGeneration)
        }
    }
    #if DEBUG
    init(syntheticClient: SupabaseClient, currentContext: @escaping () -> ProfileOnlyPrivacyContext?) {
        client = syntheticClient; current = currentContext; synthetic = true
    }
    #endif
    var context: ProfileOnlyPrivacyContext? { current() }
    private func lease() throws -> ProfileOnlyPrivacyContext {
        guard synthetic || ProfileOnlyPrivacyReleaseGate.productionReady else { throw ProfileOnlyPrivacyError.disabled }
        guard let context, context.generation >= 0, !Task.isCancelled else { throw ProfileOnlyPrivacyError.accountChanged }
        return context
    }
    private func validate(_ value: ProfileOnlyPrivacyReceipt, lease: ProfileOnlyPrivacyContext, allowUnselected: Bool) throws {
        guard !Task.isCancelled, context == lease else { throw ProfileOnlyPrivacyError.accountChanged }
        try value.validate(owner: lease.ownerID, allowUnselected: allowUnselected)
        guard value.releaseReady == !synthetic else { throw ProfileOnlyPrivacyError.disabled }
    }
    func fetchProfileOnly() async throws -> ProfileOnlyPrivacyReceipt {
        let expected = try lease()
        let value: ProfileOnlyPrivacyReceipt = try await client.rpc("soom_profile_privacy_candidate_v2").execute().value
        try validate(value, lease: expected, allowUnselected: true)
        return value
    }
    func withdrawMeasurements(profileRevision:Int64,measurementRevision:Int64) async throws -> ProfileOnlyPrivacyReceipt {
        let expected=try lease()
        guard profileRevision>0,measurementRevision>=0,measurementRevision<Int64.max else {throw ProfileOnlyPrivacyError.invalidReceipt}
        struct Params:Encodable {let p_expected_profile_revision:Int64,p_expected_measurement_revision:Int64}
        let value:ProfileOnlyPrivacyReceipt=try await client.rpc("soom_withdraw_measurements_candidate_v2",
            params:Params(p_expected_profile_revision:profileRevision,p_expected_measurement_revision:measurementRevision)).execute().value
        try validate(value,lease:expected,allowUnselected:false)
        guard value.revision==profileRevision,!value.shareMeasurements,value.measurementRevision==measurementRevision+1 else {throw ProfileOnlyPrivacyError.changeNotConfirmed}
        let confirmed=try await fetchProfileOnly()
        try validate(confirmed,lease:expected,allowUnselected:false)
        guard confirmed==value else {throw ProfileOnlyPrivacyError.changeNotConfirmed}
        return confirmed
    }
    func saveProfileOnly(scope: AccountAudience, expectedRevision: Int64) async throws -> ProfileOnlyPrivacyReceipt {
        let expected = try lease()
        guard expectedRevision >= 0, expectedRevision < Int64.max - 1 else { throw ProfileOnlyPrivacyError.invalidReceipt }
        struct Params: Encodable {
            let p_scope: String
            let p_expected_revision: Int64
            let p_notice_version = "profile-only-mutual-v2"
        }
        let value: ProfileOnlyPrivacyReceipt = try await client.rpc("soom_set_profile_privacy_candidate_v2",
            params: Params(p_scope: scope.rawValue, p_expected_revision: expectedRevision)).execute().value
        try validate(value, lease: expected, allowUnselected: false)
        guard value.scope == scope, value.revision == expectedRevision + 1 else { throw ProfileOnlyPrivacyError.changeNotConfirmed }
        let confirmed = try await fetchProfileOnly()
        try validate(confirmed, lease: expected, allowUnselected: false)
        guard confirmed == value else { throw ProfileOnlyPrivacyError.changeNotConfirmed }
        return confirmed
    }
}

private struct ProfileOnlyAccountPrivacySelectionContent: View {
    @ObservedObject var model: AccountPrivacyModel
    @State private var confirmingWithdrawal=false
    var onCompletion: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("프로필 공개범위").font(.title2.bold())
            Text("운동은 저장하면 자동으로 반영돼요. 누가 볼 수 있는지는 프로필에서만 선택해요.")
                .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            ForEach(AccountAudience.allCases, id: \.rawValue) { scope in
                Button {
                    model.selection = scope
                    model.workoutSelection = scope == .publicAccount ? .publicPost : .mutual
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: model.selection == scope ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(scope.title).font(.headline)
                            Text(scope == .publicAccount
                                 ? "나를 팔로우한 사람의 피드에 운동이 표시돼요. 로그인한 사용자는 내 프로필에서도 볼 수 있어요."
                                 : "서로 팔로우한 사람만 내 운동을 볼 수 있어요. 나만 팔로우하거나 상대만 팔로우하면 표시되지 않아요.")
                                .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(16).background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).disabled(model.busy)
                    .accessibilityIdentifier("privacy.choice.\(scope.rawValue)")
                    .accessibilityValue(model.selection == scope ? "선택됨" : "선택 안 됨")
            }
            Text("공개범위 변경은 내 기존 운동과 앞으로 저장할 운동의 요약에 적용돼요. 차단한 계정에는 표시하지 않아요.")
                .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
            VStack(alignment: .leading, spacing: 8) {
                Text("측정·경로 공유는 별도예요").font(.headline)
                Text("운동 사진은 프로필 공개범위에 따라 보여요. 심박·경로의 기존 공유 동의와 건강 기록 클라우드 저장 동의는 별도로 유지돼요. AI 해석과 회복 정보는 본인만 볼 수 있어요.")
                    .font(.footnote)
                Text(model.receipt == nil ? "기존 측정 공유 선택: 확인 필요" : (model.receipt?.shareMeasurements == true ? "기존 측정 공유 선택: 켜짐" : "기존 측정 공유 선택: 꺼짐"))
                    .font(.caption).accessibilityIdentifier("privacy.profileOnly.measurements")
                if model.receipt?.shareMeasurements==true {
                    Button(role: .destructive) { confirmingWithdrawal = true } label: {
                        Text("기존 측정·경로 공유 중지").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.contentShape(Rectangle())
                        .disabled(!model.canWithdrawMeasurements).accessibilityIdentifier("privacy.measurements.withdraw")
                }
            }.foregroundStyle(SOOMColor.secondaryInk).padding(16)
                .background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 16))
            if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(SOOMColor.warning) }
            Button {
                Task { if await model.completeSharingSetup() { onCompletion?() } }
            } label: {
                HStack { if model.busy { ProgressView() }; Text("공개범위 저장").font(.headline) }
                    .frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent).disabled(!model.canCompleteSharingSetup)
                .accessibilityIdentifier("privacy.save")
            Button("공개범위 다시 불러오기") { Task { await model.load() } }.disabled(model.busy)
        }.padding(SOOMLayout.screenPadding).background(SOOMColor.background)
            .alert("측정·경로 공유를 중지할까요?", isPresented: $confirmingWithdrawal) {
                Button("공유 중지",role:.destructive) {Task {await model.withdrawMeasurements()}}
                Button("취소",role:.cancel) {}
            } message: {
                Text("운동 요약의 프로필 공개범위와 원본 기록은 유지됩니다. 기존에 공유하던 상세 측정·경로는 더 이상 다른 사람에게 제공하지 않아요.")
            }
    }
}

#if DEBUG && targetEnvironment(simulator)
private struct ProfileOnlyPrivacyLocalQAView: View {
    @StateObject private var service: PrivacyLocalQAService
    @StateObject private var model: AccountPrivacyModel
    init() {
        let service=PrivacyLocalQAService()
        service.receipt = .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,
                               revision:1,shareMeasurements:false,policyVersion:2)
        _service=StateObject(wrappedValue:service)
        _model=StateObject(wrappedValue:AccountPrivacyModel(owner:ReviewDemoMode.userID,service:service))
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                Text("합성 데이터 · 서버와 건강 원본 미사용").font(.caption)
                Text("저장 \(service.writes)회 · revision \(service.receipt.revision)")
                    .accessibilityIdentifier("qa.profileOnly.saved")
                Button("다음 저장 실패 체험") {service.failNextSave=true}
                    .accessibilityIdentifier("qa.profileOnly.fail")
                Button("기존 측정 공유 상태 체험") {
                    service.receipt.shareMeasurements=true;service.receipt.measurementRevision=9
                    Task {await model.load()}
                }.accessibilityIdentifier("qa.profileOnly.measurementsOn")
                AccountPrivacySelectionView(model:model)
            }
        }.navigationTitle("프로필 규칙 v2 QA").task {await model.load()}
    }
}
#endif
