import XCTest
import Combine
@testable import SOOM

@MainActor final class AccountActivityOwnerTransitionTests: XCTestCase {
    let owner = UUID()
    final class Service: AccountActivityOwnerTransitionServing {
        var viewerID: UUID?
        var calls = 0
        var after: (() -> Void)?
        var value: AccountActivityOwnerAcceptance
        init(_ owner: UUID) {
            viewerID = owner
            value = .init(version: 1, viewer_id: owner, scope_revision: 1, account_scope: "public", accepted_projection_count: 2, release_ready: false)
        }
        func accept(revision: Int64) async throws -> AccountActivityOwnerAcceptance { calls += 1; after?(); return value }
    }
    func context(_ generation: Int = 1) -> AccountActivitySyncContext {
        .init(ownerID: owner, scopeID: owner.uuidString.lowercased(), generation: generation, retired: false)
    }
    func model(_ service: Service, fixture: Bool = true, current: (() -> AccountActivitySyncContext?)? = nil) -> AccountActivityOwnerTransitionModel {
        .init(owner: owner, privacy: .init(enabled: true, accountScope: .publicAccount, workoutDefault: .publicPost, revision: 1, shareMeasurements: true),
              service: service, currentContext: current ?? { self.context() }, fixture: fixture)
    }
    final class PreviewPrivacy: AccountPrivacyServing {
        let viewerID: UUID?
        init(_ owner: UUID) { viewerID = owner }
        func fetch() async throws -> AccountPrivacyReceipt { .init(enabled: false, accountScope: .publicAccount, workoutDefault: .publicPost, revision: 1, shareMeasurements: true) }
        func previewCapability() async throws -> AccountActivityPreviewCapability? {
            .init(version: 1, viewer_id: viewerID!, enabled: true, owner_rules_accepted: false,
                account_scope: .publicAccount, scope_revision: 1, share_measurements: true)
        }
        func save(owner: UUID, scope: AccountAudience, defaultWorkout: FeedPostVisibility, expectedRevision: Int64, shareMeasurements: Bool) async throws -> AccountPrivacyReceipt { throw CommunitySafetyError.unavailable }
    }
    func testPreviewReceiptOpensOnlyPreviewWhileLegacyContractsOff() async {
        let safety = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
        let m = AccountPrivacyModel(owner: owner, service: PreviewPrivacy(owner), socialState: safety, profileOnlyRules: false)
        await m.load()
        XCTAssertFalse(m.canContinue)
        XCTAssertFalse(safety.canUseSocial)
        XCTAssertTrue(safety.canUseActivityPreview)
        m.suspendSocialAccess()
        XCTAssertFalse(safety.canUseActivityPreview)
    }
    func testExplicitAcknowledgementRequired() async {
        let s = Service(owner); let m = model(s)
        await m.accept(); XCTAssertEqual(s.calls, 0)
        m.acknowledged = true; await m.accept()
        XCTAssertEqual(s.calls, 1); XCTAssertEqual(m.acceptedCount, 2)
    }
    func testProductionNotEnabledByUI() async {
        let s = Service(owner); let m = model(s, fixture: false)
        m.acknowledged = true; await m.accept(); XCTAssertEqual(s.calls, 0)
    }
    func testAccountGenerationChangeRejected() async {
        let s = Service(owner); var c = context(); let m = model(s, current: { c })
        s.after = { c = self.context(2) }; m.acknowledged = true; await m.accept()
        XCTAssertNil(m.acceptedCount); XCTAssertNotNil(m.errorMessage)
    }
    func testWrongOwnerAndServerReleaseRejected() async {
        let s = Service(owner); let m = model(s)
        s.value = .init(version: 1, viewer_id: UUID(), scope_revision: 1, account_scope: "public", accepted_projection_count: 2, release_ready: false)
        m.acknowledged = true; await m.accept(); XCTAssertNil(m.acceptedCount)
    }
}

@MainActor final class AccountPrivacyPreviewPublicationTests: XCTestCase {
    private final class Service: AccountPrivacyServing {
        var viewerID: UUID?
        var failFetch = false, failCapability = false
        var selected = true
        var capabilityOwner: UUID?
        var afterFetch: (() -> Void)?, afterCapability: (() -> Void)?
        init(_ owner: UUID) { viewerID = owner; capabilityOwner = owner }
        func fetch() async throws -> AccountPrivacyReceipt {
            if failFetch { throw CommunitySafetyError.unavailable }
            afterFetch?()
            return .init(enabled: selected, accountScope: .publicAccount, workoutDefault: .publicPost, revision: 1, shareMeasurements: true)
        }
        func previewCapability() async throws -> AccountActivityPreviewCapability? {
            if failCapability { throw CommunitySafetyError.unavailable }
            let cap = AccountActivityPreviewCapability(version: 1, viewer_id: capabilityOwner!, enabled: true, owner_rules_accepted: true,
                account_scope: .publicAccount, scope_revision: 1, share_measurements: true)
            afterCapability?(); return cap
        }
        func save(owner: UUID, scope: AccountAudience, defaultWorkout: FeedPostVisibility, expectedRevision: Int64, shareMeasurements: Bool) async throws -> AccountPrivacyReceipt { throw CommunitySafetyError.unavailable }
    }
    func testSelectedPublicReceiptPublishesBothIndependentRightsAndReloads() async {
        let owner = UUID(), service = Service(UUID())
        service.viewerID = owner; service.capabilityOwner = owner
        let safety = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
        let model = AccountPrivacyModel(owner: owner, service: service, socialState: safety, profileOnlyRules: false)
        await model.load()
        XCTAssertTrue(model.canContinue); XCTAssertTrue(safety.canUseSocial); XCTAssertTrue(safety.canUseActivityPreview)
        let receipt = AccountActivityReadContext(viewerID: owner, generation: safety.accountGeneration, safetyRevision: safety.revision)
        var item = FeedMockData.items[0]
        item.previewLegacyReadContext = receipt; item.previewLegacySummary = true
        XCTAssertEqual(safety.filtered([item]).first?.previewLegacyReadContext, receipt)
        XCTAssertTrue(safety.canUseActivityPreview, "Summary transport must retain its independently verified right after social publication")
        await model.load()
        XCTAssertTrue(safety.canUseSocial); XCTAssertTrue(safety.canUseActivityPreview)
    }
    func testCapabilityFailureDoesNotGrantPreviewAndFetchFailureGrantsNeither() async {
        let owner = UUID(), safety = CommunitySafetyStore(client: nil, requiresSocialVerification: true)
        safety.setViewerID(owner)
        let service = Service(owner)
        let checked = AccountPrivacyModel(owner: owner, service: service, socialState: safety, profileOnlyRules: false)
        service.failCapability = true; await checked.load()
        XCTAssertTrue(safety.canUseSocial); XCTAssertFalse(safety.canUseActivityPreview)
        service.failCapability = false; service.failFetch = true; await checked.load()
        XCTAssertFalse(safety.canUseSocial); XCTAssertFalse(safety.canUseActivityPreview)
    }
    func testLateCapabilityWithChangedAccountRevisionOrSuspensionCannotGrant() async {
        for change in 0..<3 {
            let owner = UUID(), service = Service(UUID())
            service.viewerID = owner; service.capabilityOwner = owner
            let safety = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
            let model = AccountPrivacyModel(owner: owner, service: service, socialState: safety, profileOnlyRules: false)
            service.afterCapability = {
                if change == 0 { service.viewerID = UUID(); safety.configure(client: nil) }
                else if change == 1 { safety.setSocialVerified(true, owner: owner) }
                else { model.suspendSocialAccess() }
            }
            await model.load()
            XCTAssertFalse(model.canContinue); XCTAssertFalse(safety.canUseActivityPreview)
            XCTAssertFalse(safety.canUseSocial)
        }
    }
    func testCheckingEndsOnlyAfterBothGrantsIncludingPreviewOnlyAndFailure() async {
        for outcome in 0..<3 {
            let owner = UUID(), service = Service(UUID())
            service.viewerID = owner; service.capabilityOwner = owner
            service.selected = outcome != 1; service.failFetch = outcome == 2
            let safety = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
            let model = AccountPrivacyModel(owner: owner, service: service, socialState: safety, profileOnlyRules: false)
            var finished: [(Bool, Bool)] = []
            let token = model.$isCheckingSocialAccess.dropFirst().sink { checking in
                if !checking { finished.append((safety.canUseSocial, safety.canUseActivityPreview)) }
            }
            await model.load()
            XCTAssertEqual(finished.count, 1)
            XCTAssertEqual(finished.first?.0, outcome == 0)
            XCTAssertEqual(finished.first?.1, outcome != 2)
            withExtendedLifetime(token) {}
        }
    }
    func testRecheckingStartsBeforePreviewRevocationPublishes() async {
        let owner = UUID(), service = Service(UUID())
        service.viewerID = owner; service.capabilityOwner = owner
        let safety = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
        let model = AccountPrivacyModel(owner: owner, service: service, socialState: safety, profileOnlyRules: false)
        await model.load()
        var revokedWhileChecking: [Bool] = []
        let token = safety.$previewVerified.dropFirst().sink { granted in
            if !granted { revokedWhileChecking.append(model.isCheckingSocialAccess) }
        }
        model.suspendSocialAccess(); await model.load(); await model.load()
        XCTAssertFalse(revokedWhileChecking.isEmpty)
        XCTAssertTrue(revokedWhileChecking.allSatisfy { $0 })
        withExtendedLifetime(token) {}
    }
    func testWrongCapabilityOwnerNeverGrantsPreview() async {
        let owner = UUID(), service = Service(UUID())
        service.viewerID = owner
        let safety = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
        let model = AccountPrivacyModel(owner: owner, service: service, socialState: safety, profileOnlyRules: false)
        await model.load()
        XCTAssertTrue(safety.canUseSocial); XCTAssertFalse(safety.canUseActivityPreview)
    }
}

import Supabase

@MainActor final class PreviewSummaryRealTransportTests: XCTestCase {
    private let owner = UUID(uuidString: "fa480000-0000-4000-8000-000000000001")!
    private final class PrivacyService: AccountPrivacyServing {
        let actual: SupabaseAccountPrivacyService
        var duringCapability: (() async throws -> Void)?
        var viewerID: UUID? { actual.viewerID }
        init(_ client: SupabaseClient) { actual = .init(client: client, readPolicy: .approvedFollowersV1) }
        func fetch() async throws -> AccountPrivacyReceipt { try await actual.fetch() }
        func previewCapability() async throws -> AccountActivityPreviewCapability? {
            try await duringCapability?()
            return try await actual.previewCapability()
        }
        func save(owner: UUID, scope: AccountAudience, defaultWorkout: FeedPostVisibility, expectedRevision: Int64, shareMeasurements: Bool) async throws -> AccountPrivacyReceipt { throw CommunitySafetyError.unavailable }
    }
    private func sdk() async throws -> SupabaseClient {
        PreviewSummaryHTTP.reset()
        let now = Date(), user = User(id: owner, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: Date(), updatedAt: Date())
        let session = Session(accessToken: "synthetic-noncredential", tokenType: "bearer", expiresIn: 3600, expiresAt: now.timeIntervalSince1970 + 3600, refreshToken: "synthetic-noncredential", user: user)
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [PreviewSummaryHTTP.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://summary48.invalid")!, supabaseKey: "synthetic-noncredential", options: .init(
            auth: .init(storage: PreviewSummaryStorage(data: try JSONEncoder().encode(session)), storageKey: "summary48", autoRefreshToken: false, emitLocalSessionAsInitialSession: true), global: .init(session: URLSession(configuration: cfg))))
        _ = try await SupabaseClientSessionReader(client: client, includesProfile: false).readCurrentSession()
        return client
    }
    func testSelectedPublicActualSDKSummaryRequestReturnsFilteredDisplayItem() async throws {
        let client = try await sdk(), safety = CommunitySafetyStore.shared
        let previous = safety.viewerID
        safety.setViewerID(owner); safety.configure(client: client)
        defer { safety.configure(client: nil); safety.setViewerID(previous) }
        let model = AccountPrivacyModel(owner: owner, service: PrivacyService(client), socialState: safety, profileOnlyRules: false)
        await model.load()
        XCTAssertTrue(model.canContinue); XCTAssertTrue(safety.canUseActivityPreview)
        let items = try await SupabaseFeedRemoteClient(client: client).previewLegacyHome(.init(viewerID: owner, scope: .home, ownerID: nil, before: nil, limit: 8))
        XCTAssertEqual(PreviewSummaryHTTP.summaryCalls, 2, "Initial summary and independent receipt revalidation")
        XCTAssertEqual(items.count, 1); XCTAssertTrue(items.first?.previewLegacySummary == true)
        let visible = safety.filtered(items)
        XCTAssertEqual(visible.count, 1); XCTAssertEqual(visible.first?.workoutDistanceMeters, 10000)
        XCTAssertEqual(visible.first?.workoutDurationSeconds, 3600)
        XCTAssertEqual(visible.first?.visibility, .publicFeed)
    }
    func testBlockedListRevisionDuringPrivacyLoadStopsSummaryUntilFreshLoad() async throws {
        let client = try await sdk(), safety = CommunitySafetyStore.shared
        let previous = safety.viewerID
        safety.setViewerID(owner); safety.configure(client: client)
        defer { safety.configure(client: nil); safety.setViewerID(previous) }
        let service = PrivacyService(client)
        service.duringCapability = { try await safety.refreshBlockedUsers() }
        let model = AccountPrivacyModel(owner: owner, service: service, socialState: safety, profileOnlyRules: false)
        await model.load()
        XCTAssertFalse(model.canContinue); XCTAssertFalse(safety.canUseSocial); XCTAssertFalse(safety.canUseActivityPreview)
        do {
            _ = try await SupabaseFeedRemoteClient(client: client).previewLegacyHome(.init(viewerID: owner, scope: .home, ownerID: nil, before: nil, limit: 8))
            XCTFail("Stale privacy receipt must not authorize a summary")
        } catch {}
        XCTAssertEqual(PreviewSummaryHTTP.summaryCalls, 0)
        // A fresh explicit load recovers after the unrelated block-list revision settles.
        service.duringCapability = nil; await model.load()
        XCTAssertTrue(safety.canUseActivityPreview)
        let items = try await SupabaseFeedRemoteClient(client: client).previewLegacyHome(.init(viewerID: owner, scope: .home, ownerID: nil, before: nil, limit: 8))
        XCTAssertEqual(items.count, 1); XCTAssertEqual(PreviewSummaryHTTP.summaryCalls, 2)
    }
}
private final class PreviewSummaryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock(); private var data: Data?
    init(data: Data) { self.data = data }
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; if key == "summary48" { data = value } }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return key == "summary48" ? data : nil }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; if key == "summary48" { data = nil } }
}
private final class PreviewSummaryHTTP: URLProtocol {
    private static let lock = NSLock()
    private static var summaryCount = 0
    static var summaryCalls: Int { lock.lock(); defer { lock.unlock() }; return summaryCount }
    static func reset() { lock.lock(); summaryCount = 0; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "summary48.invalid" else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        let body: String
        switch request.url?.lastPathComponent {
        case "soom_privacy_v1": body = #"[{"enabled":true,"account_scope":"public","workout_default":"public","revision":1,"share_measurements":true}]"#
        case "soom_shared_detail_enabled_v1", "soom_full_detail_consent_ready_v1": body = "true"
        case "soom_activity_preview_status_v1": body = #"{"version":1,"viewer_id":"fa480000-0000-4000-8000-000000000001","enabled":true,"owner_rules_accepted":true,"account_scope":"public","scope_revision":1,"share_measurements":true}"#
        case "user_follows", "feed_posts": body = "[]"
        case "soom_list_blocked_users": body = #"[{"blocked_user_id":"fa480000-0000-4000-8000-000000000099","display_name":"Synthetic blocked","blocked_at":"2026-11-01T00:00:00Z"}]"#
        case "soom_legacy_public_summary_preview_v1":
            Self.lock.lock(); Self.summaryCount += 1; Self.lock.unlock()
            body = #"[{"post_id":"fa480000-0000-4000-8000-000000000011","owner_id":"fa480000-0000-4000-8000-000000000002","sport":"cycling","activity_at":"2026-11-01T00:00:00Z","duration_seconds":3600,"distance_meters":10000}]"#
        default: client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
