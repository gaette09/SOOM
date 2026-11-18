import XCTest
import UserNotifications
import UIKit
import Supabase
@testable import SOOM

private final class BadgeAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    init(_ data: Data) { self.data = data }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return key == "badge-fixture" ? data : nil }
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; if key == "badge-fixture" { data = value } }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; if key == "badge-fixture" { data = nil } }
}

#if SOOM_PROFILE_SOCIAL_V2
private final class BadgeV2HTTPFixture: URLProtocol {
    static let lock = NSLock()
    static var mode = "count", owner = UUID()
    static var requests: [URLRequest] = []
    static func reset(_ mode: String, owner: UUID) { lock.lock(); defer { lock.unlock() }; Self.mode = mode; Self.owner = owner; requests = [] }
    static func snapshot() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); let mode = Self.mode, owner = Self.owner; Self.lock.unlock()
        guard let url = request.url, url.host == "badge-fixture.invalid" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let path = url.lastPathComponent
        let kind: String
        switch path {
        case "soom_notifications_v2": kind = "follow"
        case "soom_activity_social_inbox_candidate_v2": kind = "social"
        case "soom_activity_native_inbox_candidate_v2": kind = "native"
        default: client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        if mode == "switch-" + kind {
            Task { @MainActor [self] in
                CommunitySafetyStore.shared.setViewerID(UUID())
                emit(kind: kind, mode: mode, owner: owner)
            }
        } else { emit(kind: kind, mode: mode, owner: owner) }
    }
    private func emit(kind: String, mode: String, owner: UUID) {
        let denied = mode == "denied-" + kind, missingRPC = mode == "missing-rpc-" + kind
        let status = denied ? 403 : missingRPC ? 404 : 200
        var headers = ["Content-Type":"application/json"]
        var body: [String: Any] = [:]
        if denied || missingRPC { body = ["code": missingRPC ? "PGRST202" : "42501", "message":"synthetic denied"] }
        else if kind == "follow" {
            if mode != "missing-follow" { headers["Content-Range"] = "*/2005" }
        } else {
            body = ["version":2, "viewer_id":owner.uuidString, "release_ready":true, "rows":[],
                    "unread_count":kind == "social" ? 17 : 3,
                    "push_delivery":kind == "social" ? "unchanged_no_new_scope_push" : "candidate_disabled"]
            if kind == "native" { body["source_kind"] = "activity_native_v2"; body["backing"] = "native" }
            if mode == "missing-" + kind { body.removeValue(forKey: "unread_count") }
            if mode == "negative-" + kind { body["unread_count"] = -1 }
            if mode == "wrong-viewer-" + kind { body["viewer_id"] = UUID().uuidString }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class NotificationBadgeHTTPTests: XCTestCase {
    private func withRemote(_ mode: String, matchingViewer: Bool = true,
                            run: (SupabaseFeedRemoteClient, UUID) async throws -> Void) async throws {
        let owner = UUID(), now = Date()
        BadgeV2HTTPFixture.reset(mode, owner: owner)
        let user = User(id: owner, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, updatedAt: now)
        let auth = Session(accessToken: "synthetic-noncredential", tokenType: "bearer", expiresIn: 3600,
                           expiresAt: now.timeIntervalSince1970 + 3600, refreshToken: "synthetic-noncredential", user: user)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BadgeV2HTTPFixture.self]
        let network = URLSession(configuration: config); defer { network.invalidateAndCancel() }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let client = SupabaseClient(supabaseURL: URL(string: "https://badge-fixture.invalid")!, supabaseKey: "synthetic-noncredential",
            options: .init(auth: .init(storage: BadgeAuthStorage(try encoder.encode(auth)), storageKey: "badge-fixture", autoRefreshToken: false, emitLocalSessionAsInitialSession: true), global: .init(session: network)))
        _ = try await client.auth.session
        XCTAssertEqual(client.auth.currentSession?.user.id, owner)
        XCTAssertEqual(UIApplication.shared.applicationState, .active, "Run in the normal foreground test host; do not bypass the live adapter's activation boundary")
        let safety = CommunitySafetyStore.shared, oldViewer = safety.viewerID, oldVerified = safety.socialVerified
        let viewer = matchingViewer ? owner : UUID()
        safety.setViewerID(viewer); safety.setSocialVerified(true, owner: viewer)
        defer { safety.setViewerID(oldViewer); if let oldViewer { safety.setSocialVerified(oldVerified, owner: oldViewer) } }
        try await run(SupabaseFeedRemoteClient(client: client), owner)
    }
    func testSDKCountsExactFollowSocialAndNativeWithoutDoubleCounting() async throws {
        try await withRemote("count") { remote, _ in
            let count = try await remote.fetchUnreadNotificationCount(); XCTAssertEqual(count, 2025)
            let requests = BadgeV2HTTPFixture.snapshot(); XCTAssertEqual(requests.count, 3)
            XCTAssertEqual(requests.map { $0.url!.lastPathComponent }, ["soom_notifications_v2", "soom_activity_social_inbox_candidate_v2", "soom_activity_native_inbox_candidate_v2"])
            XCTAssertEqual(requests[0].httpMethod, "HEAD")
            XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Prefer")?.contains("count=exact") == true)
            let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "read_at" }?.value?.lowercased(), "is.null")
            let types = query.first { $0.name == "type" }?.value ?? ""
            XCTAssertTrue(types.contains("follow_request") && types.contains("follow_approved"))
            XCTAssertFalse(types.contains("comment") || types.contains("reaction"))
            for request in requests.dropFirst() {
                XCTAssertEqual(request.httpMethod, "POST")
                // A one-row inbox read returns an exact independent total, not a page count.
                var data = request.httpBody ?? Data()
                if data.isEmpty, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable {
                        let length = stream.read(&buffer, maxLength: buffer.count)
                        if length <= 0 { break }
                        data.append(contentsOf: buffer.prefix(length))
                    }
                }
                XCTAssertFalse(data.isEmpty, "Missing request body must not silently skip the limit assertion")
                let params = try JSONSerialization.jsonObject(with: data) as? [String: Int]
                XCTAssertEqual(params?["p_limit"], 1)
            }
        }
    }
    func testMissingOrNegativeCountNeverBecomesZeroOrPartialTotal() async throws {
        for (mode, calls) in [("missing-follow",1),("missing-social",2),("missing-native",3),("negative-social",2),("negative-native",3)] {
            try await withRemote(mode) { remote, _ in
                do { _ = try await remote.fetchUnreadNotificationCount(); XCTFail(mode) } catch {}
                XCTAssertEqual(BadgeV2HTTPFixture.snapshot().count, calls, mode)
            }
        }
    }
    func testDeniedOrMissingRPCNeverFallsBackToLegacyOrReturnsPartialCount() async throws {
        for (kind, calls) in [("follow",1),("social",2),("native",3)] {
            for prefix in ["denied-", "missing-rpc-"] {
                try await withRemote(prefix + kind) { remote, _ in
                    do { _ = try await remote.fetchUnreadNotificationCount(); XCTFail(prefix + kind) } catch {}
                    let requests = BadgeV2HTTPFixture.snapshot()
                    XCTAssertEqual(requests.count, calls)
                    XCTAssertFalse(requests.contains { $0.url?.path.hasSuffix("/notifications") == true })
                }
            }
        }
    }
    func testWrongViewerReceiptAndAccountSwitchRejectLateCounts() async throws {
        for (mode, calls) in [("wrong-viewer-social",2),("wrong-viewer-native",3),("switch-follow",1),("switch-social",2),("switch-native",3)] {
            try await withRemote(mode) { remote, _ in
                do { _ = try await remote.fetchUnreadNotificationCount(); XCTFail(mode) } catch {}
                XCTAssertEqual(BadgeV2HTTPFixture.snapshot().count, calls, mode)
            }
        }
    }
    func testCurrentAuthAndSafetyMismatchMakesNoCountRequest() async throws {
        try await withRemote("count", matchingViewer: false) { remote, _ in
            do { _ = try await remote.fetchUnreadNotificationCount(); XCTFail("Account mismatch") } catch {}
            XCTAssertTrue(BadgeV2HTTPFixture.snapshot().isEmpty)
        }
    }
}
#else
private final class BadgeHTTPFixture: URLProtocol {
    static let lock = NSLock()
    static var mode = "count"
    static var requests: [URLRequest] = []
    static func reset(_ mode: String) { lock.lock(); defer { lock.unlock() }; Self.mode = mode; requests = [] }
    static func snapshot() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true } // block every network request
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); let mode = Self.mode; Self.lock.unlock()
        guard request.url?.host == "badge-fixture.invalid" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let rpc = request.url!.path.hasSuffix("soom_notifications_v2")
        let unavailable = mode == "legacy" && rpc
        let denied = mode == "denied"
        let status = unavailable ? 404 : denied ? 403 : 200
        var headers = ["Content-Type": "application/json"]
        if !unavailable && !denied && mode != "missing" { headers["Content-Range"] = "*/2005" }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if unavailable || denied {
            let body = "{\"code\":\"\(unavailable ? "PGRST202" : "42501")\",\"message\":\"synthetic failure\"}"
            client?.urlProtocol(self, didLoad: Data(body.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class NotificationBadgeHTTPTests: XCTestCase {
    private func withRemote(_ mode: String, run: (SupabaseFeedRemoteClient, UUID) async throws -> Void) async throws {
        BadgeHTTPFixture.reset(mode)
        let now = Date(), owner = UUID()
        let user = User(id: owner, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, updatedAt: now)
        let auth = Session(accessToken: "synthetic-noncredential", tokenType: "bearer", expiresIn: 3600,
                           expiresAt: now.timeIntervalSince1970 + 3600, refreshToken: "synthetic-noncredential", user: user)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [BadgeHTTPFixture.self]
        let network = URLSession(configuration: configuration); defer { network.invalidateAndCancel() }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let client = SupabaseClient(supabaseURL: URL(string: "https://badge-fixture.invalid")!, supabaseKey: "synthetic-noncredential",
            options: .init(auth: .init(storage: BadgeAuthStorage(try encoder.encode(auth)), storageKey: "badge-fixture", autoRefreshToken: false, emitLocalSessionAsInitialSession: true), global: .init(session: network)))
        try await run(SupabaseFeedRemoteClient(client: client), owner)
    }
    func testSDKRequestsExactHeadUnreadCountBeyondPageWithoutFetchingRows() async throws {
        try await withRemote("count") { remote, _ in
            let count = try await remote.fetchUnreadNotificationCount(); XCTAssertEqual(count, 2005)
            let requests = BadgeHTTPFixture.snapshot(); XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.httpMethod, "HEAD")
            let query = requests.first?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
            XCTAssertEqual(query?.first(where: { $0.name == "read_at" })?.value?.lowercased(), "is.null", requests.first?.url?.absoluteString ?? "missing URL")
            XCTAssertTrue(requests.first?.value(forHTTPHeaderField: "Prefer")?.contains("count=exact") == true)
        }
    }
    func testMissingExactCountIsFailureNotZero() async throws {
        try await withRemote("missing") { remote, _ in
            do { _ = try await remote.fetchUnreadNotificationCount(); XCTFail("Missing count is not zero") } catch {}
            XCTAssertEqual(BadgeHTTPFixture.snapshot().count, 1)
        }
    }
    func testPermissionFailureDoesNotFallBackToAnotherQuery() async throws {
        try await withRemote("denied") { remote, _ in
            do { _ = try await remote.fetchUnreadNotificationCount(); XCTFail("Denied") } catch {}
            XCTAssertEqual(BadgeHTTPFixture.snapshot().count, 1)
        }
    }
    func testLegacyMissingRPCUsesOwnerScopedExactCount() async throws {
        try await withRemote("legacy") { remote, owner in
            let count = try await remote.fetchUnreadNotificationCount(); XCTAssertEqual(count, 2005)
            let requests = BadgeHTTPFixture.snapshot(); XCTAssertEqual(requests.count, 2)
            XCTAssertEqual(requests.last?.httpMethod, "HEAD")
            XCTAssertTrue(requests.last?.url?.absoluteString.lowercased().contains(owner.uuidString.lowercased()) == true)
        }
    }
}

#endif

@MainActor
private final class BadgeCountRemote: NotificationInboxFetching {
    var count = 4
    var calls = 0
    var fail = false
    var suspendNext = false
    var pending: CheckedContinuation<Int, Error>?
    func fetchUnreadNotificationCount() async throws -> Int {
        calls += 1
        if suspendNext {
            suspendNext = false
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        if fail { throw NotificationInboxError.upgradeRequired }
        return count
    }
    func fetchNotifications() async throws -> [NotificationDTO] { XCTFail("Use the exact count, not a page"); return [] }
    func markAllNotificationsAsRead() async throws { XCTFail("Counting must not mark read") }
}

@MainActor
final class NotificationBadgeTests: XCTestCase {
    func testExactCountBeyondPageAndRepeatedRefreshDoesNotIncrement() async {
        let remote = BadgeCountRemote(); remote.count = 2005
        var writes: [Int] = []
        let badge = NotificationBadgeStore { writes.append($0) }
        badge.bind(scope: "owner", fetcher: remote)
        await badge.refresh(); await badge.refresh(); await Task.yield()
        XCTAssertEqual(badge.count, 2005); XCTAssertEqual(writes.last, 2005)
    }
    func testFetchFailureAndNegativeDoNotEraseLastCount() async {
        let remote = BadgeCountRemote(); let badge = NotificationBadgeStore { _ in }
        badge.bind(scope: "owner", fetcher: remote); await badge.refresh()
        remote.fail = true; await badge.refresh(); XCTAssertEqual(badge.count, 4)
        remote.fail = false; remote.count = -1; await badge.refresh(); XCTAssertEqual(badge.count, 4)
    }
    func testReadDeleteRestoreAndOtherDeviceSnapshotReplaceCount() async {
        let remote = BadgeCountRemote(); let badge = NotificationBadgeStore { _ in }
        badge.bind(scope: "owner", fetcher: remote)
        for value in [4, 3, 2, 3, 0, 7] {
            remote.count = value; await badge.refresh(); XCTAssertEqual(badge.count, value)
        }
    }
    func testColdLaunchDoesNotClearOSBadgeBeforeSuccessfulFetch() async {
        var writes: [Int] = []; let remote = BadgeCountRemote(); remote.fail = true
        let badge = NotificationBadgeStore { writes.append($0) }
        badge.bind(scope: "owner", fetcher: remote); await badge.refresh(); await Task.yield()
        XCTAssertNil(badge.count); XCTAssertTrue(writes.isEmpty)
    }
    func testLogoutRejectsInFlightOldAccountCount() async {
        let remote = BadgeCountRemote(); remote.suspendNext = true
        var writes: [Int] = []; let badge = NotificationBadgeStore { writes.append($0) }
        badge.bind(scope: "old", fetcher: remote)
        let old = Task { await badge.refresh() }
        while remote.pending == nil { await Task.yield() }
        badge.bind(scope: nil, fetcher: nil)
        remote.pending?.resume(returning: 99); await old.value; await Task.yield()
        XCTAssertEqual(badge.count, 0); XCTAssertEqual(writes.last, 0); XCTAssertFalse(writes.contains(99))
    }
    func testAccountSwitchQueuesNewCountAfterOldFetch() async {
        let oldRemote = BadgeCountRemote(); oldRemote.suspendNext = true
        let newRemote = BadgeCountRemote(); newRemote.count = 2
        let badge = NotificationBadgeStore { _ in }
        badge.bind(scope: "old", fetcher: oldRemote)
        let old = Task { await badge.refresh() }
        while oldRemote.pending == nil { await Task.yield() }
        badge.bind(scope: "new", fetcher: newRemote); await badge.refresh()
        oldRemote.pending?.resume(returning: 99); await old.value
        XCTAssertEqual(badge.count, 2); XCTAssertEqual(newRemote.calls, 1)
    }
    func testBurstRefreshCoalescesAndRevalidatesAfterMutation() async {
        let remote = BadgeCountRemote(); remote.suspendNext = true
        let badge = NotificationBadgeStore { _ in }; badge.bind(scope: "owner", fetcher: remote)
        let first = Task { await badge.refresh() }
        while remote.pending == nil { await Task.yield() }
        for _ in 0..<10 { await badge.refresh() }
        remote.count = 1; remote.pending?.resume(returning: 4); await first.value
        XCTAssertEqual(remote.calls, 2); XCTAssertEqual(badge.count, 1)
    }
    func testCancelledOldViewTaskCannotDropNewAccountRefresh() async {
        let oldRemote = BadgeCountRemote(); oldRemote.suspendNext = true
        let newRemote = BadgeCountRemote(); newRemote.count = 2
        let badge = NotificationBadgeStore { _ in }
        badge.bind(scope: "old", fetcher: oldRemote)
        let old = Task { await badge.refresh() }
        while oldRemote.pending == nil { await Task.yield() }
        old.cancel(); badge.bind(scope: "new", fetcher: newRemote); await badge.refresh()
        oldRemote.pending?.resume(returning: 99); await old.value
        let deadline = Date().addingTimeInterval(1)
        while newRemote.calls == 0 && Date() < deadline { await Task.yield() }
        XCTAssertEqual(newRemote.calls, 1); XCTAssertEqual(badge.count, 2)
    }
    func testClosingReadAccessRejectsInFlightCountWithoutInventingZero() async {
        let remote = BadgeCountRemote(); let badge = NotificationBadgeStore { _ in }
        badge.bind(scope: "owner", fetcher: remote); await badge.refresh()
        remote.suspendNext = true; let old = Task { await badge.refresh() }
        while remote.pending == nil { await Task.yield() }
        badge.bind(scope: "owner", fetcher: nil)
        remote.pending?.resume(returning: 99); await old.value
        XCTAssertEqual(badge.count, 4)
    }
    func testDeniedIconWriteDoesNotChangeInboxCountOrLoop() async {
        let remote = BadgeCountRemote(); var writes = 0
        let badge = NotificationBadgeStore { _ in writes += 1; throw NotificationInboxError.upgradeRequired }
        badge.bind(scope: "owner", fetcher: remote); await badge.refresh()
        while writes == 0 { await Task.yield() }; await Task.yield()
        XCTAssertEqual(badge.count, 4); XCTAssertTrue(badge.iconUpdateFailed); XCTAssertEqual(writes, 1)
    }
    func testSlowOSWriteIsFollowedByLogoutZero() async {
        let remote = BadgeCountRemote(); var pending: CheckedContinuation<Void, Never>?
        var writes: [Int] = []
        let badge = NotificationBadgeStore { count in
            if count == 4 { await withCheckedContinuation { pending = $0 } }
            writes.append(count)
        }
        badge.bind(scope: "owner", fetcher: remote); await badge.refresh()
        while pending == nil { await Task.yield() }
        badge.bind(scope: nil, fetcher: nil); pending?.resume()
        while writes.count < 2 { await Task.yield() }
        XCTAssertEqual(writes, [4, 0])
    }
}

@MainActor
final class DeviceTokenReceiptHandlerTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: DeviceTokenStore!

    override func setUp() {
        super.setUp()
        let suiteName = "DeviceTokenReceiptHandlerTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = DeviceTokenStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testReceivedUpsertsWhenSignedInWithSupabase() async {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)
        let user = AppUser(displayName: "테스터", authProvider: .supabase)
        let didUpsert = expectation(description: "upsert called")
        registrar.onUpsert = { didUpsert.fulfill() }

        handler.received(tokenHex: "abc123", currentUser: user)

        await fulfillment(of: [didUpsert], timeout: 1)
        XCTAssertEqual(registrar.upsertCalls.first?.tokenHex, "abc123")
        XCTAssertEqual(registrar.upsertCalls.first?.userId, user.id)
    }

    func testReceivedCachesTokenEvenForGuest() {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)

        handler.received(tokenHex: "abc123", currentUser: AppUser(displayName: "게스트", authProvider: .local))

        XCTAssertEqual(store.cachedTokenHex, "abc123")
        XCTAssertTrue(registrar.upsertCalls.isEmpty)
    }

    func testReceivedSkipsUpsertWhenNoCurrentUser() {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)

        handler.received(tokenHex: "abc123", currentUser: nil)

        XCTAssertTrue(registrar.upsertCalls.isEmpty)
    }

    func testLoginStateChangedUpsertsCachedTokenAfterLoginConfirmed() async {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)
        handler.received(tokenHex: "abc123", currentUser: nil)
        let didUpsert = expectation(description: "upsert called")
        registrar.onUpsert = { didUpsert.fulfill() }

        handler.loginStateChanged(currentUser: AppUser(displayName: "테스터", authProvider: .supabase))

        await fulfillment(of: [didUpsert], timeout: 1)
        XCTAssertEqual(registrar.upsertCalls.first?.tokenHex, "abc123")
    }

    func testLoginStateChangedSkipsWhenNoCachedToken() {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)

        handler.loginStateChanged(currentUser: AppUser(displayName: "테스터", authProvider: .supabase))

        XCTAssertTrue(registrar.upsertCalls.isEmpty)
    }
}

@MainActor
final class PushRegistrationUpgradeTests: XCTestCase {
    private func settle(_ predicate: @escaping ()->Bool) async {
        for _ in 0..<100 { if predicate() { return };try? await Task.sleep(nanoseconds:10_000_000) }
        XCTFail("Registration did not reach expected state")
    }
    private func fixture() -> (DeviceTokenStore,MockDeviceTokenRegistrar,PushRegistrationStatus) {
        let defaults=UserDefaults(suiteName:"PushUpgrade-\(UUID())")!
        return (DeviceTokenStore(userDefaults:defaults),MockDeviceTokenRegistrar(),PushRegistrationStatus())
    }
    func testPersistenceErrorIsVisibleAndRetryCanRecover() async {
        let(store,remote,status)=fixture();remote.upsertError=DeviceRegistrationError.accountChanged
        let handler=DeviceTokenReceiptHandler(store:store,registrar:remote,status:status)
        handler.received(tokenHex:"synthetic",currentUser:AppUser(displayName:"Test",authProvider:.supabase))
        await settle{status.state == .failed};XCTAssertEqual(remote.upsertCalls.count,1)
        remote.upsertError=nil;handler.retry();await settle{status.state == .registered}
        XCTAssertEqual(remote.upsertCalls.count,2)
    }
    func testDuplicateTokenWhileRegisteringIsOneRequest() async {
        let(store,remote,status)=fixture();remote.upsertDelayNanoseconds=30_000_000
        let handler=DeviceTokenReceiptHandler(store:store,registrar:remote,status:status);let user=AppUser(displayName:"Test",authProvider:.supabase)
        handler.received(tokenHex:"synthetic",currentUser:user);handler.received(tokenHex:"synthetic",currentUser:user)
        await settle{status.state == .registered};XCTAssertEqual(remote.upsertCalls.count,1)
    }
    func testSignOutSuppressesLateRegistrationCompletion() async {
        let(store,remote,status)=fixture();remote.upsertDelayNanoseconds=50_000_000
        let handler=DeviceTokenReceiptHandler(store:store,registrar:remote,status:status)
        handler.received(tokenHex:"synthetic",currentUser:AppUser(displayName:"Test",authProvider:.supabase))
        handler.loginStateChanged(currentUser:nil);try? await Task.sleep(nanoseconds:80_000_000)
        XCTAssertEqual(status.state,.signedOut)
    }
    func testLegacyServerIsNotReportedAsExtendedRegistrationSuccess() async {
        let(store,remote,status)=fixture();remote.upsertError=DeviceRegistrationError.extendedServiceUnavailable
        let handler=DeviceTokenReceiptHandler(store:store,registrar:remote,status:status)
        handler.received(tokenHex:"synthetic",currentUser:AppUser(displayName:"Test",authProvider:.supabase))
        await settle{status.state == .legacyRegistered}
        XCTAssertNotEqual(status.state,.registered)
    }
    func testAPNsFailureBeforeLoginIsNotLost() {
        let(store,remote,status)=fixture();let handler=DeviceTokenReceiptHandler(store:store,registrar:remote,status:status)
        handler.registrationFailed();handler.loginStateChanged(currentUser:AppUser(displayName:"Test",authProvider:.supabase))
        XCTAssertEqual(status.state,.apnsFailed);XCTAssertTrue(remote.upsertCalls.isEmpty)
    }
    func testAPNsFailureAndNoTokenRetryRemainVisible() {
        let(store,remote,status)=fixture();let handler=DeviceTokenReceiptHandler(store:store,registrar:remote,status:status)
        handler.loginStateChanged(currentUser:AppUser(displayName:"Test",authProvider:.supabase));handler.registrationFailed()
        XCTAssertEqual(status.state,.apnsFailed);handler.retry();XCTAssertEqual(status.state,.awaitingToken)
        XCTAssertTrue(remote.upsertCalls.isEmpty)
    }
}

private final class UpgradeInboxRemote: NotificationInboxFetching {
    var rows:[NotificationDTO]=[];var failFetch=false;var failRead=false;var failHide=false;var failRestore=false;var delay:UInt64=0
    var hideCalls=0;var hidden=Set<UUID>();var readBatches:[Int]=[];var failReadBatch:Int?
    func markNotificationsAsRead(ids:[UUID]) async throws { readBatches.append(ids.count);if failRead || failReadBatch == readBatches.count {throw NotificationInboxError.upgradeRequired} }
    func fetchNotifications() async throws -> [NotificationDTO] {
        if delay>0 { try? await Task.sleep(nanoseconds:delay) }
        if failFetch { throw NotificationInboxError.upgradeRequired };return rows.filter{!hidden.contains($0.id)}
    }
    func markAllNotificationsAsRead() async throws { if failRead { throw NotificationInboxError.upgradeRequired } }
    func hideNotification(id:UUID) async throws { hideCalls+=1;if delay>0 { try? await Task.sleep(nanoseconds:delay) };if failHide {throw NotificationInboxError.upgradeRequired};hidden.insert(id) }
    func restoreNotification(id:UUID) async throws { if failRestore { throw NotificationInboxError.upgradeRequired };hidden.remove(id) }
}
@MainActor
private final class ControlledInboxRemote: NotificationInboxFetching {
    var rows:[NotificationDTO]=[];var hidden=Set<UUID>()
    var suspendNext=false;var fetchCount=0
    var pending:[Int:CheckedContinuation<[NotificationDTO],Error>]=[:]
    var snapshots:[Int:[NotificationDTO]]=[:]
    func fetchNotifications() async throws -> [NotificationDTO] {
        fetchCount+=1;let key=fetchCount;let snapshot=rows.filter{!hidden.contains($0.id)}
        if suspendNext {
            suspendNext=false;snapshots[key]=snapshot
            return try await withCheckedThrowingContinuation { pending[key]=$0 }
        }
        return snapshot
    }
    func release(_ key:Int,fail:Bool=false) {
        let continuation=pending.removeValue(forKey:key)!
        if fail { continuation.resume(throwing:NotificationInboxError.upgradeRequired) }
        else { continuation.resume(returning:snapshots.removeValue(forKey:key)!) }
    }
    func markAllNotificationsAsRead() async throws {}
    func markNotificationsAsRead(ids:[UUID]) async throws {}
    func hideNotification(id:UUID) async throws { hidden.insert(id) }
    func restoreNotification(id:UUID) async throws { hidden.remove(id) }
}
@MainActor
final class NotificationInboxUpgradeTests: XCTestCase {
    private func fixture() -> (UpgradeInboxRemote,NotificationInboxModel,NotificationDTO) {
        let remote=UpgradeInboxRemote();let item=NotificationDTO(id:UUID(),recipientId:UUID(),actorId:UUID(),type:.followRequest,postId:nil,body:nil,readAt:nil,createdAt:Date());remote.rows=[item]
        return(remote,NotificationInboxModel(fetcher:remote,session:{"same-session"}),item)
    }
    func testLoadFailureIsErrorInsteadOfEmptySuccess() async {
        let(remote,model,_)=fixture();remote.failFetch=true;await model.load();XCTAssertNotNil(model.error);XCTAssertEqual(model.receiptRevision,0)
    }
    func testReadFailureDoesNotClearUnreadOrPublishSuccess() async {
        let(remote,model,_)=fixture();remote.failRead=true;await model.load()
        XCTAssertNil(model.items.first?.readAt);XCTAssertNotNil(model.error);XCTAssertEqual(model.receiptRevision,0)
        remote.failRead=false;await model.markRead();XCTAssertNotNil(model.items.first?.readAt);XCTAssertNil(model.error)
    }
    func testFailedHideKeepsOriginalRow() async {
        let(remote,model,item)=fixture();await model.load();remote.failHide=true;await model.hide(item)
        XCTAssertEqual(model.items.count,1);XCTAssertNotNil(model.error);XCTAssertNil(model.undoItem)
    }
    func testHideAndUndoPreserveRemoteOriginal() async {
        let(remote,model,item)=fixture();await model.load();await model.hide(item)
        XCTAssertTrue(model.items.isEmpty);XCTAssertEqual(remote.rows.count,1);await model.undoHide()
        XCTAssertEqual(model.items.map(\.id),[item.id]);XCTAssertNil(model.undoItem)
    }
    func testDuplicateHideWhilePendingSendsOneMutation() async {
        let(remote,model,item)=fixture();await model.load();remote.delay=40_000_000
        async let first:Void=model.hide(item);async let second:Void=model.hide(item);_ = await(first,second)
        XCTAssertEqual(remote.hideCalls,1)
    }
    func testAccountChangeDuringFetchCannotExposePriorRows() async {
        let remote=UpgradeInboxRemote();remote.rows=[.init(id:UUID(),recipientId:UUID(),actorId:nil,type:.comment,postId:UUID(),body:nil,readAt:nil,createdAt:Date())];remote.delay=40_000_000
        var account:String?="first";let model=NotificationInboxModel(fetcher:remote,session:{account})
        let load=Task{await model.load()};try? await Task.sleep(nanoseconds:5_000_000);account="second";model.reset();await load.value
        XCTAssertTrue(model.items.isEmpty);XCTAssertEqual(model.receiptRevision,0)
    }
    func testHistoryOverOneHundredKeepsAllRowsAndBoundsReadWrites() async {
        let remote=UpgradeInboxRemote();remote.rows=(0..<205).map { _ in .init(id:UUID(),recipientId:UUID(),actorId:nil,type:.comment,postId:UUID(),body:nil,readAt:nil,createdAt:Date()) }
        let model=NotificationInboxModel(fetcher:remote,session:{"same"});await model.load()
        XCTAssertEqual(model.items.count,205);XCTAssertEqual(remote.readBatches,[100,100,5]);XCTAssertTrue(model.items.allSatisfy{$0.readAt != nil})
    }
    func testPartialReadFailureAcknowledgesOnlyCompletedBatches() async {
        let remote=UpgradeInboxRemote();remote.rows=(0..<205).map { _ in .init(id:UUID(),recipientId:UUID(),actorId:nil,type:.comment,postId:UUID(),body:nil,readAt:nil,createdAt:Date()) };remote.failReadBatch=2
        let model=NotificationInboxModel(fetcher:remote,session:{"same"});await model.load()
        XCTAssertEqual(model.items.filter{$0.readAt != nil}.count,100);XCTAssertEqual(model.items.filter{$0.readAt == nil}.count,105);XCTAssertNotNil(model.error)
    }
    private func raceFixture() -> (ControlledInboxRemote,NotificationInboxModel,NotificationDTO) {
        let remote=ControlledInboxRemote();let item=NotificationDTO(id:UUID(),recipientId:UUID(),actorId:nil,type:.comment,postId:UUID(),body:nil,readAt:Date(),createdAt:Date());remote.rows=[item]
        return(remote,NotificationInboxModel(fetcher:remote,session:{"same"}),item)
    }
    func testSuccessfulHideRejectsSnapshotCapturedBeforeHide() async {
        let(remote,model,item)=raceFixture();await model.load();remote.suspendNext=true
        let old=Task{await model.load()};while remote.pending[2]==nil { await Task.yield() }
        await model.hide(item);XCTAssertTrue(remote.hidden.contains(item.id));XCTAssertTrue(model.items.isEmpty)
        remote.release(2);await old.value
        XCTAssertTrue(model.items.isEmpty);XCTAssertEqual(model.undoItem?.id,item.id);XCTAssertFalse(model.isLoading)
    }
    func testUndoDuringRefreshStartsFreshLoadAndRejectsHiddenSnapshot() async {
        let(remote,model,item)=raceFixture();await model.load();await model.hide(item);remote.suspendNext=true
        let old=Task{await model.load()};while remote.pending[2]==nil { await Task.yield() }
        await model.undoHide();XCTAssertEqual(remote.fetchCount,3);XCTAssertEqual(model.items.map(\.id),[item.id]);XCTAssertNil(model.undoItem)
        remote.release(2);await old.value
        XCTAssertEqual(model.items.map(\.id),[item.id]);XCTAssertFalse(model.isLoading)
    }
    func testStaleRefreshFailureCannotOverrideNewerHideOrLoadState() async {
        let(remote,model,item)=raceFixture();await model.load();remote.suspendNext=true
        let old=Task{await model.load()};while remote.pending[2]==nil { await Task.yield() }
        await model.hide(item);await model.load();remote.release(2,fail:true);await old.value
        XCTAssertTrue(model.items.isEmpty);XCTAssertNil(model.error);XCTAssertFalse(model.isLoading)
    }
    func testOldRefreshCannotEndNewRefreshLoadingAfterMutation() async {
        let(remote,model,item)=raceFixture();await model.load();remote.suspendNext=true
        let old=Task{await model.load()};while remote.pending[2]==nil { await Task.yield() }
        await model.hide(item);remote.suspendNext=true
        let latest=Task{await model.load()};while remote.pending[3]==nil { await Task.yield() }
        remote.release(2);await old.value;XCTAssertTrue(model.isLoading);XCTAssertTrue(model.items.isEmpty)
        remote.release(3);await latest.value;XCTAssertFalse(model.isLoading);XCTAssertTrue(model.items.isEmpty)
    }
    func testUnknownKindDoesNotBreakEntireInboxDecode() throws {
        let data=Data("{\"id\":\"a1500000-0000-4000-8000-000000000001\",\"recipient_id\":\"a1500000-0000-4000-8000-000000000002\",\"type\":\"future_kind\",\"created_at\":0}".utf8)
        let item=try JSONDecoder().decode(NotificationDTO.self,from:data);XCTAssertEqual(item.type,.unknown);XCTAssertNil(item.destination)
    }
    func testRequestAndApprovalTargetsDifferFromPost() {
        let(_,_,item)=fixture();XCTAssertEqual(item.destination,.requests)
        let approved=NotificationDTO(id:item.id,recipientId:item.recipientId,actorId:item.actorId,type:.followApproved,postId:nil,body:nil,readAt:nil,createdAt:Date());XCTAssertEqual(approved.destination,.profile(item.actorId!))
    }
}
@MainActor
final class NotificationPushScopeTests: XCTestCase {
    private let owner=UUID(uuidString:"a1500000-0000-4000-8000-000000000001")!
    private func payload() -> NotificationPushPayload {
        NotificationPushPayload(userInfo:["notification_id":UUID().uuidString,"recipient_id":owner.uuidString,"notification_type":"follow_request"])!
    }
    func testOtherAccountAndSignedOutCannotQueuePush() {
        let router=NotificationDeepLinkRouter();router.routePush(payload(),currentUserID:UUID());XCTAssertNil(router.pendingPush)
        router.routePush(payload(),currentUserID:nil);XCTAssertNil(router.pendingPush)
    }
    func testColdPushWaitsAndConsumesOnlyOnceForRecipient() {
        let router=NotificationDeepLinkRouter();router.routePush(payload(),currentUserID:owner);XCTAssertNotNil(router.pendingPush)
        XCTAssertEqual(router.consumePush(currentUserID:owner),.requests);XCTAssertNil(router.consumePush(currentUserID:owner))
    }
    func testAccountChangeOrRevocationClearsPendingRoutes() {
        let router=NotificationDeepLinkRouter();router.routePush(payload(),currentUserID:owner);router.routeToPost(id:UUID());router.clear()
        XCTAssertNil(router.pendingPush);XCTAssertNil(router.pendingPostId)
    }
    func testUnscopedLegacyOrUnknownPayloadDoesNotRoute() {
        XCTAssertNil(NotificationPushPayload(userInfo:["post_id":UUID().uuidString]))
        XCTAssertNil(NotificationPushPayload(userInfo:["notification_id":UUID().uuidString,"recipient_id":owner.uuidString,"notification_type":"unknown"]))
    }
}


@MainActor
final class NotificationForegroundPresentationTests: XCTestCase {
    private let owner = UUID(uuidString: "a6500000-0000-4000-8000-000000000001")!
    private let other = UUID(uuidString: "a6500000-0000-4000-8000-000000000002")!
    private let visible: UNNotificationPresentationOptions = [.banner, .sound]

    private func payload(_ kind: String = "follow_request") -> [AnyHashable: Any] {
        ["notification_id": "a6500000-0000-4000-8000-000000000010",
         "recipient_id": owner.uuidString,
         "notification_type": kind,
         "post_id": "a6500000-0000-4000-8000-000000000020",
         "actor_id": other.uuidString]
    }

    func testForegroundRemotePushNeedsBoundAccountPolicy() {
        let delegate = AppDelegate()
        XCTAssertTrue(delegate.foregroundPresentationOptions(for: payload(), isRemotePush: true).isEmpty)
    }

    func testForegroundRemotePushUsesAuthoritativeBadgeRefresh() {
        let delegate = AppDelegate()
        var refreshes = 0
        delegate.onDidReceiveVisiblePush = { refreshes += 1 }
        delegate.shouldPresentRemotePush = { [owner] in $0.recipientID == owner }
        XCTAssertEqual(delegate.foregroundPresentationOptions(for: payload(), isRemotePush: true), visible)
        XCTAssertEqual(refreshes, 1)
        delegate.shouldPresentRemotePush = { _ in false }
        XCTAssertTrue(delegate.foregroundPresentationOptions(for: payload(), isRemotePush: true).isEmpty)
        XCTAssertEqual(refreshes, 1)
    }

    func testForegroundRemotePushForOtherAccountIsSuppressed() {
        let delegate = AppDelegate()
        delegate.shouldPresentRemotePush = { [other] in $0.recipientID == other }
        XCTAssertTrue(delegate.foregroundPresentationOptions(for: payload(), isRemotePush: true).isEmpty)
    }

    func testForegroundRemotePushAfterSignOutIsSuppressed() {
        let delegate = AppDelegate()
        var currentUserID: UUID? = owner
        delegate.shouldPresentRemotePush = { currentUserID == $0.recipientID }
        XCTAssertEqual(delegate.foregroundPresentationOptions(for: payload(), isRemotePush: true), visible)
        currentUserID = nil
        XCTAssertTrue(delegate.foregroundPresentationOptions(for: payload(), isRemotePush: true).isEmpty)
    }

    func testForegroundRemotePushAfterAccountSwitchReadsLatestAccount() {
        let delegate = AppDelegate()
        var currentUserID = owner
        delegate.shouldPresentRemotePush = { currentUserID == $0.recipientID }
        currentUserID = other
        XCTAssertTrue(delegate.foregroundPresentationOptions(for: payload(), isRemotePush: true).isEmpty)
        currentUserID = owner
        XCTAssertEqual(delegate.foregroundPresentationOptions(for: payload(), isRemotePush: true), visible)
    }

    func testForegroundRemotePushIsSuppressedWhenSocialGateCloses() {
        let delegate = AppDelegate()
        var canUseSocial = true
        delegate.shouldPresentRemotePush = { [owner] in canUseSocial && $0.recipientID == owner }
        canUseSocial = false
        XCTAssertTrue(delegate.foregroundPresentationOptions(for: payload(), isRemotePush: true).isEmpty)
    }

    func testForegroundMalformedAndUnscopedRemotePushAreSuppressed() {
        let delegate = AppDelegate()
        delegate.shouldPresentRemotePush = { _ in true }
        for info in [[AnyHashable: Any](), ["post_id": other.uuidString], payload("unknown")] {
            XCTAssertTrue(delegate.foregroundPresentationOptions(for: info, isRemotePush: true).isEmpty)
        }
    }

    func testForegroundLocalNotificationPreservesExistingPresentation() {
        let delegate = AppDelegate()
        delegate.shouldPresentRemotePush = { _ in false }
        XCTAssertEqual(delegate.foregroundPresentationOptions(for: [:], isRemotePush: false), [.banner, .sound, .badge])
    }

    func testForegroundSupportedSocialKindsApplyTheSameAccountBoundary() {
        let delegate = AppDelegate()
        for kind in ["reaction", "comment", "follow_request", "follow_approved"] {
            delegate.shouldPresentRemotePush = { [owner] in $0.recipientID == owner }
            XCTAssertEqual(delegate.foregroundPresentationOptions(for: payload(kind), isRemotePush: true), visible)
            delegate.shouldPresentRemotePush = { [other] in $0.recipientID == other }
            XCTAssertTrue(delegate.foregroundPresentationOptions(for: payload(kind), isRemotePush: true).isEmpty)
        }
    }
}

@MainActor
final class PushLaunchCallbackTests: XCTestCase {
    func testTokenBeforeHandlerIsDeliveredExactlyOnceAndLatestRotationWins() {
        let delegate = AppDelegate(); var tokens: [Data] = []
        delegate.application(.shared, didRegisterForRemoteNotificationsWithDeviceToken: Data([1]))
        delegate.application(.shared, didRegisterForRemoteNotificationsWithDeviceToken: Data([2]))
        delegate.onDidReceiveDeviceToken = { tokens.append($0) }
        delegate.onDidReceiveDeviceToken = { tokens.append($0) }
        XCTAssertEqual(tokens, [Data([2])])
        delegate.application(.shared, didRegisterForRemoteNotificationsWithDeviceToken: Data([3]))
        XCTAssertEqual(tokens, [Data([2]), Data([3])])
    }
    func testFailureBeforeHandlerIsDeliveredOnceAndSuccessSupersedesFailure() {
        let delegate = AppDelegate(); var failures = 0
        delegate.application(.shared, didFailToRegisterForRemoteNotificationsWithError: CocoaError(.fileReadUnknown))
        delegate.onDidFailToRegister = { _ in failures += 1 }
        delegate.onDidFailToRegister = { _ in failures += 1 }
        XCTAssertEqual(failures, 1)
        let next = AppDelegate()
        next.application(.shared, didFailToRegisterForRemoteNotificationsWithError: CocoaError(.fileReadUnknown))
        next.application(.shared, didRegisterForRemoteNotificationsWithDeviceToken: Data([1]))
        next.onDidFailToRegister = { _ in XCTFail("Superseded failure") }
        var count = 0; next.onDidReceiveDeviceToken = { _ in count += 1 }
        XCTAssertEqual(count, 1)
    }
    func testLegacyAcknowledgementDeduplicatesUntilExplicitRetryOrAccountChange() async {
        let defaults = UserDefaults(suiteName: "LegacyOnce-\(UUID())")!
        let store = DeviceTokenStore(userDefaults: defaults), remote = MockDeviceTokenRegistrar(), status = PushRegistrationStatus()
        remote.upsertError = DeviceRegistrationError.extendedServiceUnavailable
        let handler = DeviceTokenReceiptHandler(store: store, registrar: remote, status: status)
        let user = AppUser(displayName: "Synthetic", authProvider: .supabase)
        handler.received(tokenHex: "synthetic", currentUser: user)
        let legacyDeadline = Date().addingTimeInterval(2)
        while status.state != .legacyRegistered && Date() < legacyDeadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(status.state, .legacyRegistered)
        handler.loginStateChanged(currentUser: user); handler.received(tokenHex: "synthetic", currentUser: user)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(remote.upsertCalls.count, 1)
        remote.upsertError = nil; handler.retry()
        let registeredDeadline = Date().addingTimeInterval(2)
        while status.state != .registered && Date() < registeredDeadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(status.state, .registered); XCTAssertEqual(remote.upsertCalls.count, 2)
        handler.loginStateChanged(currentUser: AppUser(displayName: "Next", authProvider: .supabase))
        for _ in 0..<100 { if status.state == .registered { break }; await Task.yield() }
        XCTAssertEqual(remote.upsertCalls.count, 3)
    }
}


extension NotificationInboxUpgradeTests {
    func testAcceptanceInboxReadsRetainRowsAndCoalesceOnlyLiveRequests() async {
        let remote = ControlledInboxRemote()
        let item = NotificationDTO(id: UUID(), recipientId: UUID(), actorId: nil, type: .comment,
            postId: UUID(), body: nil, readAt: Date(), createdAt: Date())
        remote.rows = [item]
        let model = NotificationInboxModel(fetcher: remote, session: { "acceptance-session" })
        await model.load(); XCTAssertEqual(remote.fetchCount, 1)
        for _ in 0..<100 { _ = model.items }
        XCTAssertEqual(remote.fetchCount, 1)
        remote.suspendNext = true
        let pull = Task { await model.load() }
        while remote.pending[2] == nil { await Task.yield() }
        await model.load(); XCTAssertEqual(remote.fetchCount, 2)
        XCTAssertEqual(model.items.map(\.id), [item.id])
        remote.release(2); await pull.value
        remote.suspendNext = true
        let failure = Task { await model.load() }
        while remote.pending[3] == nil { await Task.yield() }
        remote.release(3, fail: true); await failure.value
        XCTAssertEqual(model.items.map(\.id), [item.id]); XCTAssertNotNil(model.error)
        await model.load(); XCTAssertEqual(remote.fetchCount, 4); XCTAssertNil(model.error)
        model.reset(); XCTAssertTrue(model.items.isEmpty)
        await model.load(); XCTAssertEqual(remote.fetchCount, 5)
    }
}


@MainActor
final class FeedNotificationNavigationTests: XCTestCase {
    func testReappearingSameRequestCannotReuseARevokedContext() async {
        let model=FeedNotificationNavigation(),item=FeedMockData.items[0]
        let request=FeedNotificationRequest(postID:item.id,opensComments:true)
        await model.resolve(request) { _ in item }
        XCTAssertNotNil(model.item)
        var calls=0
        await model.resolve(request,isCurrent:{false}) { _ in calls += 1;return item }
        XCTAssertNil(model.item);XCTAssertNil(model.readyRequestID);XCTAssertEqual(calls,0)
    }
    func testColdNativePushWaitsForVerificationAndConsumesOnce() throws {
        let owner=UUID(),router=NotificationDeepLinkRouter()
        let payload=try XCTUnwrap(NativeActivityPushPayload(userInfo:["source_kind":"activity_native_v1",
            "recipient_id":owner.uuidString,"event_id":UUID().uuidString,"card_id":UUID().uuidString,
            "comment_id":UUID().uuidString,"kind":"comment"]))
        router.pendingNativePush=payload
        XCTAssertNil(router.consumeNativePush(currentUserID:nil,canNavigate:false))
        XCTAssertNil(router.consumeNativePush(currentUserID:owner,canNavigate:false))
        XCTAssertEqual(router.pendingNativePush,payload)
        XCTAssertEqual(router.consumeNativePush(currentUserID:owner,canNavigate:true),payload)
        XCTAssertNil(router.consumeNativePush(currentUserID:owner,canNavigate:true))
        router.pendingNativePush=payload
        XCTAssertNil(router.consumeNativePush(currentUserID:UUID(),canNavigate:true))
        XCTAssertNil(router.pendingNativePush)
    }
    func testPreviewSummaryAndUnverifiedGateNeverOpenLegacyComments() {
        var item=FeedMockData.items[0]
        let context=AccountActivityReadContext(viewerID:UUID(),generation:2,safetyRevision:7)
        var unverified=FeedNotificationCardPresentation(item:item,context:context,opensComments:true)
        unverified.presentInitialComments(current:context,canUseSocial:false)
        XCTAssertFalse(unverified.commentsPresented)
        item.previewLegacySummary=true
        var preview=FeedNotificationCardPresentation(item:item,context:context,opensComments:true)
        preview.presentInitialComments(current:context,canUseSocial:true)
        XCTAssertFalse(preview.supportsLegacyComments)
        XCTAssertFalse(preview.commentsPresented)
    }
    func testClosingCommentsKeepsMatchingCardWithoutReopeningOnAppearance() {
        let item=FeedMockData.items[0]
        let context=AccountActivityReadContext(viewerID:UUID(),generation:2,safetyRevision:7)
        var presentation=FeedNotificationCardPresentation(item:item,context:context,opensComments:true)
        presentation.presentInitialComments(current:context,canUseSocial:true)
        XCTAssertTrue(presentation.commentsPresented)
        presentation.commentsPresented=false
        presentation.presentInitialComments(current:context,canUseSocial:true)
        XCTAssertFalse(presentation.commentsPresented)
        XCTAssertEqual(presentation.item.id,item.id)
        XCTAssertTrue(presentation.permits(context))
        XCTAssertFalse(presentation.permits(.init(viewerID:context.viewerID,generation:3,safetyRevision:7)))
    }
    func testReactionAndStaleContextsNeverAutoOpenComments() {
        let item=FeedMockData.items[0],context=AccountActivityReadContext(viewerID:UUID(),generation:2,safetyRevision:7)
        var reaction=FeedNotificationCardPresentation(item:item,context:context,opensComments:false)
        reaction.presentInitialComments(current:context,canUseSocial:true)
        XCTAssertFalse(reaction.commentsPresented)
        var comment=FeedNotificationCardPresentation(item:item,context:context,opensComments:true)
        comment.presentInitialComments(current:nil,canUseSocial:true)
        XCTAssertFalse(comment.commentsPresented)
        comment.presentInitialComments(current:context,canUseSocial:true)
        XCTAssertTrue(comment.commentsPresented)
    }
    func testResolutionChecksContextBeforeLookupAndAfterIgnoredCancellation() async {
        let model=FeedNotificationNavigation(),item=FeedMockData.items[0]
        var valid=false,calls=0
        await model.resolve(.init(postID:item.id,opensComments:true),isCurrent:{valid}) { _ in calls += 1;return item }
        XCTAssertEqual(calls,0)
        valid=true
        await model.resolve(.init(postID:item.id,opensComments:true),isCurrent:{valid}) { _ in
            calls += 1;valid=false;return item
        }
        XCTAssertEqual(calls,1);XCTAssertNil(model.item);XCTAssertNil(model.readyRequestID)
        XCTAssertFalse(model.isLoading)
    }
    func testCommentOpensOnlyOnceAfterMatchingCardBecomesVisible() async {
        let item = FeedMockData.items[0], model = FeedNotificationNavigation()
        let request = FeedNotificationRequest(postID: item.id, opensComments: true)
        var calls = 0
        await model.resolve(request) { _ in calls += 1; return item }
        XCTAssertNil(model.takeCommentsWhenVisible(postID: UUID()))
        XCTAssertEqual(model.takeCommentsWhenVisible(postID: item.id)?.id, item.id)
        XCTAssertNil(model.takeCommentsWhenVisible(postID: item.id))
        await model.resolve(request) { _ in calls += 1; return item }
        XCTAssertEqual(calls, 1)
        XCTAssertNil(model.takeCommentsWhenVisible(postID: item.id))
    }
    func testReactionOnlyRevealsCardAndNewCommentTapCanReopen() async {
        let item = FeedMockData.items[0], model = FeedNotificationNavigation()
        await model.resolve(.init(postID: item.id, opensComments: false)) { _ in item }
        XCTAssertEqual(model.item?.id, item.id)
        XCTAssertNil(model.takeCommentsWhenVisible(postID: item.id))
        await model.resolve(.init(postID: item.id, opensComments: true)) { _ in item }
        XCTAssertEqual(model.takeCommentsWhenVisible(postID: item.id)?.id, item.id)
    }
    func testMissingDeniedAndWrongIDNeverOpenComments() async {
        let model = FeedNotificationNavigation(), item = FeedMockData.items[0]
        await model.resolve(.init(postID: item.id, opensComments: true)) { _ in nil }
        XCTAssertTrue(model.failed); XCTAssertFalse(model.isLoading); XCTAssertNil(model.item)
        await model.resolve(.init(postID: UUID(), opensComments: true)) { _ in item }
        XCTAssertTrue(model.failed); XCTAssertNil(model.readyRequestID)
    }
    func testLatestTapWinsEvenWhenOlderLookupIgnoresCancellation() async {
        let model = FeedNotificationNavigation(), first = FeedMockData.items[0], second = FeedMockData.items[1]
        var suspended: CheckedContinuation<FeedItem?, Never>?
        let old = Task { await model.resolve(.init(postID: first.id, opensComments: true)) { _ in
            await withCheckedContinuation { suspended = $0 }
        } }
        while suspended == nil { await Task.yield() }
        await model.resolve(.init(postID: second.id, opensComments: false)) { _ in second }
        suspended?.resume(returning: first); await old.value
        XCTAssertEqual(model.item?.id, second.id); XCTAssertFalse(model.failed)
        XCTAssertNil(model.takeCommentsWhenVisible(postID: second.id))
    }
    func testSafetyClearDiscardsLateSuccessAndStopsLoading() async {
        let model = FeedNotificationNavigation(), item = FeedMockData.items[0]
        var suspended: CheckedContinuation<FeedItem?, Never>?
        let task = Task { await model.resolve(.init(postID: item.id, opensComments: true)) { _ in
            await withCheckedContinuation { suspended = $0 }
        } }
        while suspended == nil { await Task.yield() }
        model.clear(); suspended?.resume(returning: item); await task.value
        XCTAssertNil(model.item); XCTAssertNil(model.readyRequestID); XCTAssertFalse(model.isLoading)
    }
    func testCancelledLookupDoesNotRemainLoadingAndAllowsRetry() async {
        let model = FeedNotificationNavigation(), item = FeedMockData.items[0]
        let request = FeedNotificationRequest(postID: item.id, opensComments: true)
        var suspended: CheckedContinuation<FeedItem?, Never>?
        let task = Task { await model.resolve(request) { _ in await withCheckedContinuation { suspended = $0 } } }
        while suspended == nil { await Task.yield() }
        task.cancel(); suspended?.resume(returning: item); await task.value
        XCTAssertFalse(model.isLoading); XCTAssertNil(model.item)
        await model.resolve(request) { _ in item }
        XCTAssertEqual(model.item?.id, item.id)
    }
}


@MainActor private final class EventMock: EventNotificationServing {
    var prefs=EventPreferences(), calls=0, writes=0, receipts=[String](), fail=false
    var page=EventInboxPage(notifications:[],nextCursor:nil,badge:"omitted")
    var pause: CheckedContinuation<EventPreferences,Error>?
    var suspend=false
    var registrationWait=false
    var registrationPending:[CheckedContinuation<EventRegistration,Error>]=[]
    var capabilities:[EventRegistration]=[]
    func preferences() async throws -> EventPreferences {calls+=1;if suspend{return try await withCheckedThrowingContinuation{pause=$0}};if fail{throw EventNotificationError.unavailable};return prefs}
    func update(_ v:EventPreferences) async throws -> EventPreferences {writes+=1;if fail{throw EventNotificationError.unavailable};prefs=v;return v}
    func registration(token:String) async throws -> EventRegistration {calls+=1;if registrationWait {return try await withCheckedThrowingContinuation{registrationPending.append($0)}};return .init(registryId:UUID(),registrationId:UUID(),registrationEpoch:1)}
    func capability(_ r:EventRegistration) async throws {calls+=1;capabilities.append(r)}
    func receipt(_ p:EventPush,registration:EventRegistration,kind:String) async throws {receipts.append(kind);if fail{throw EventNotificationError.unavailable}}
    func inbox(after:UUID?) async throws -> EventInboxPage {calls+=1;if fail{throw EventNotificationError.unavailable};return page}
    func read(_ id:UUID) async throws -> String {writes+=1;return "2026-10-25T00:00:00Z"}
    func unread() async throws -> Int {0}
}
@MainActor final class EventNotificationTests:XCTestCase {
    private let user=UUID()
    private func payload(_ user:UUID)->[AnyHashable:Any] {
        ["aps":["alert":["title":"합성 이벤트","body":"검증"]],"notification_type":"event","soom_event_version":1,
         "event_category":"event","event_campaign_id":UUID().uuidString,"notification_id":UUID().uuidString,
         "event_delivery_id":UUID().uuidString,"recipient_id":user.uuidString,"event_destination":["kind":"none"]]
    }
    func testStrictPayloadRejectsURLVersionBadgeAndSocialSpoof() {
        let v=payload(user);XCTAssertNotNil(EventPush(userInfo:v));XCTAssertNil(NotificationPushPayload(userInfo:v))
        for (key,value) in [("soom_event_version",2 as Any),("soom_event_version",true as Any),("event_destination",["kind":"url","url":"https://example.com"] as Any),("post_id",UUID().uuidString as Any),("event_category","unknown" as Any)] {
            var invalid=v;invalid[key]=value;XCTAssertNil(EventPush(userInfo:invalid))
        }
        var bad=v;bad["aps"]=["alert":["title":"x","body":"y"],"badge":99];XCTAssertNil(EventPush(userInfo:bad))
    }
    func testDefaultGateMakesNoRequestsOrConsentWrites() async {
        let m=EventNotificationCenter(),s=EventMock();m.bind(user:user,service:s)
        await m.loadPreferences();await m.savePreferences();await m.registrationSucceeded(token:"synthetic",userID:user);await m.loadInbox()
        XCTAssertEqual(s.calls,0);XCTAssertEqual(s.writes,0);XCTAssertFalse(m.draft.eventConsent);XCTAssertFalse(m.draft.marketingConsent)
    }
    func testExplicitSaveOnlyAndDependencies() async {
        let m=EventNotificationCenter(enabled:true),s=EventMock();m.bind(user:user,service:s);await m.loadPreferences()
        XCTAssertEqual(s.writes,0);m.draft.marketingConsent=true;await m.savePreferences();XCTAssertEqual(s.writes,0)
        m.draft=EventPreferences();m.draft.eventConsent=true;await m.savePreferences();XCTAssertEqual(s.writes,1)
        m.draft.eventConsent=false;await m.savePreferences();XCTAssertFalse(m.preferences!.eventConsent)
    }
    func testConflictClearsUnsavedChoiceRequiresReload() async {
        let m=EventNotificationCenter(enabled:true),s=EventMock();m.bind(user:user,service:s);await m.loadPreferences();s.fail=true
        m.draft.eventConsent=true;await m.savePreferences();XCTAssertNil(m.preferences);XCTAssertFalse(m.draft.eventConsent)
        await m.savePreferences();XCTAssertEqual(s.writes,1);XCTAssertNotNil(m.error)
    }
    func testOldAccountPreferencesCannotOverwriteNewAccount() async {
        let m=EventNotificationCenter(enabled:true),s=EventMock();s.suspend=true;m.bind(user:user,service:s)
        let task=Task{await m.loadPreferences()};while s.pause==nil{await Task.yield()}
        m.bind(user:UUID(),service:EventMock());var old=EventPreferences();old.eventConsent=true;s.pause?.resume(returning:old);await task.value
        XCTAssertNil(m.preferences);XCTAssertFalse(m.draft.eventConsent);XCTAssertFalse(m.busy)
    }
    func testReceiptsIdempotentFailureNotRetriedAndForeignRecipientIgnored() async {
        let m=EventNotificationCenter(enabled:true),s=EventMock();m.bind(user:user,service:s)
        await m.registrationSucceeded(token:"synthetic",userID:user);let p=EventPush(userInfo:payload(user))!
        s.fail=true;await m.handle(p,tapped:false);await m.handle(p,tapped:false);await m.handle(p,tapped:true);await m.handle(p,tapped:true)
        await m.handle(EventPush(userInfo:payload(UUID()))!,tapped:true)
        XCTAssertEqual(s.receipts,["observed","tapped"]);XCTAssertTrue(m.showsInbox)
        m.bind(user:UUID(),service:EventMock());XCTAssertNil(m.currentRegistration);XCTAssertFalse(m.accepts(p))
    }
    func testColdTapDeferredUntilOwnedRegistrationAndClearedOnLogout() async {
        let m=EventNotificationCenter(enabled:true),s=EventMock(),p=EventPush(userInfo:payload(user))!
        await m.handle(p,tapped:true);m.bind(user:user,service:s);await m.registrationSucceeded(token:"synthetic",userID:user)
        XCTAssertEqual(s.receipts,["tapped"]);m.bind(user:nil,service:nil);XCTAssertFalse(m.showsInbox)
    }
    func testInboxRejectsForeignRowsAndNeverChangesSocialBadge() async {
        let m=EventNotificationCenter(enabled:true),s=EventMock();m.bind(user:user,service:s)
        s.page=EventInboxPage(notifications:[.init(id:UUID(),campaignId:UUID(),recipientId:UUID(),category:.event,title:"private",body:"x",destination:.init(kind:.none),createdAt:"x",readAt:nil)],nextCursor:nil,badge:"omitted")
        await m.loadInbox();XCTAssertTrue(m.items.isEmpty);XCTAssertNotNil(m.error);XCTAssertEqual(m.unreadCount,0)
        s.fail=true;await m.loadInbox();XCTAssertFalse(m.busy);XCTAssertNotNil(m.error)
    }
}


extension EventNotificationTests {
    func testRegistrationRaceOnlyCurrentLookupDeclaresCapability() async {
        let owner=UUID(),m=EventNotificationCenter(enabled:true),service=EventMock()
        m.bind(user:owner,service:service);service.registrationWait=true
        let first=Task{await m.registrationSucceeded(token:"synthetic-old",userID:owner)}
        while service.registrationPending.count<1{await Task.yield()}
        let second=Task{await m.registrationSucceeded(token:"synthetic-new",userID:owner)}
        while service.registrationPending.count<2{await Task.yield()}
        let current=EventRegistration(registryId:UUID(),registrationId:UUID(),registrationEpoch:2)
        service.registrationPending[1].resume(returning:current);await second.value
        service.registrationPending[0].resume(returning:.init(registryId:UUID(),registrationId:UUID(),registrationEpoch:1));await first.value
        XCTAssertEqual(m.currentRegistration,current);XCTAssertEqual(service.capabilities,[current])
    }
    func testCancelledRegistrationCannotAdvertiseCapability() async {
        let owner=UUID(),m=EventNotificationCenter(enabled:true),service=EventMock()
        m.bind(user:owner,service:service);service.registrationWait=true
        let task=Task{await m.registrationSucceeded(token:"synthetic",userID:owner)}
        while service.registrationPending.isEmpty{await Task.yield()};task.cancel()
        service.registrationPending[0].resume(returning:.init(registryId:UUID(),registrationId:UUID(),registrationEpoch:1));await task.value
        XCTAssertNil(m.currentRegistration);XCTAssertTrue(service.capabilities.isEmpty)
    }
    func testInboxDeduplicatesReadUsesServerCountWithoutSocialBadgeWrites() async {
        let owner=UUID(),m=EventNotificationCenter(enabled:true),service=EventMock()
        m.bind(user:owner,service:service)
        let row=EventInboxItem(id:UUID(),campaignId:UUID(),recipientId:owner,category:.event,title:"合成",body:"合成",destination:.init(kind:.none),createdAt:"2026-10-25T00:00:00Z",readAt:nil)
        service.page=EventInboxPage(notifications:[row,row],nextCursor:nil,badge:"omitted")
        await m.loadInbox();XCTAssertEqual(m.items.count,1)
        await m.select(row);let read=m.items.first?.readAt;await m.select(row)
        XCTAssertEqual(m.items.first?.readAt,read);XCTAssertEqual(m.unreadCount,0)
        XCTAssertNil(m.homeRequest);XCTAssertFalse(m.showsInbox)
    }
}

extension NotificationInboxUpgradeTests {
    func testLoadAndReadFailureContextsStayDistinctWithoutClearingUnread() async {
        let (remote, model, _) = fixture(); remote.failFetch = true
        await model.load(); XCTAssertEqual(model.failureContext, .load)
        remote.failFetch = false; remote.failRead = true
        await model.load(); XCTAssertEqual(model.failureContext, .read); XCTAssertNil(model.items.first?.readAt)
        remote.failRead = false; await model.markRead(); XCTAssertNil(model.failureContext); XCTAssertNotNil(model.items.first?.readAt)
    }
    func testHideAndUndoFailuresRemainAssociatedWithTheExactItem() async {
        let (remote, model, item) = fixture(); await model.load(); remote.failHide = true
        await model.hide(item); XCTAssertEqual(model.failureContext, .hide(item.id)); XCTAssertEqual(model.items.map(\.id), [item.id])
        remote.failHide = false; await model.hide(item); remote.failRestore = true
        await model.undoHide(); XCTAssertEqual(model.failureContext, .restore(item.id)); XCTAssertEqual(model.undoItem?.id, item.id)
        remote.failRestore = false; await model.undoHide(); XCTAssertNil(model.failureContext); XCTAssertEqual(model.items.map(\.id), [item.id])
        model.reset(); XCTAssertNil(model.failureContext)
    }
}

@MainActor
final class NotificationReplyMentionRoutingTests: XCTestCase {
    func testNewKindsDecodeRouteAndKeepReadState() throws {
        let post = UUID(), owner = UUID()
        for kind in [NotificationKind.reply, .mention] {
            let row = NotificationDTO(id: UUID(), recipientId: owner, actorId: UUID(), type: kind,
                postId: post, body: "테스트", readAt: nil, createdAt: Date())
            let decoded = try JSONDecoder().decode(NotificationDTO.self, from: JSONEncoder().encode(row))
            XCTAssertEqual(decoded.type, kind)
            XCTAssertEqual(decoded.destination, .post(post))
            XCTAssertEqual(decoded.read(at: Date()).type, kind)
            XCTAssertTrue(kind.showsBodyPreview)
            XCTAssertNotEqual(kind.inboxMessage, NotificationKind.unknown.inboxMessage)
        }
        XCTAssertTrue(NotificationKind.reply.opensComments)
        // A mention can be in the post body, so absent source metadata it opens the post.
        XCTAssertFalse(NotificationKind.mention.opensComments)
    }
    func testNewPushKindsRequirePostAndBoundRecipientAndConsumeOnce() {
        let owner = UUID(), post = UUID()
        for kind in ["reply", "mention"] {
            var wire: [AnyHashable: Any] = ["notification_id": UUID().uuidString,
                "recipient_id": owner.uuidString, "notification_type": kind]
            XCTAssertNil(NotificationPushPayload(userInfo: wire))
            wire["post_id"] = "invalid"
            XCTAssertNil(NotificationPushPayload(userInfo: wire))
            wire["post_id"] = post.uuidString
            let payload = NotificationPushPayload(userInfo: wire)!
            XCTAssertEqual(payload.destination, .post(post))
            let router = NotificationDeepLinkRouter()
            router.routePush(payload, currentUserID: UUID())
            XCTAssertNil(router.pendingPush)
            router.routePush(payload, currentUserID: owner)
            XCTAssertEqual(router.consumePush(currentUserID: owner), .post(post))
            XCTAssertNil(router.consumePush(currentUserID: owner))
            router.routePush(payload, currentUserID: owner)
            XCTAssertNil(router.consumePush(currentUserID: UUID()))
        }
    }
    func testMissingInboxPostFailsClosedAndLegacyKindsRemainValid() {
        for kind in [NotificationKind.reply, .mention] {
            let row = NotificationDTO(id: UUID(), recipientId: UUID(), actorId: UUID(), type: kind,
                postId: nil, body: nil, readAt: nil, createdAt: Date())
            XCTAssertNil(row.destination)
        }
        XCTAssertTrue(NotificationKind.comment.opensComments)
        XCTAssertFalse(NotificationKind.reaction.opensComments)
        XCTAssertFalse(NotificationKind.unknown.showsBodyPreview)
    }
}

@MainActor final class NativeActivityPushRoutingTests: XCTestCase {
    func payload() -> [AnyHashable:Any] {
        ["source_kind":"activity_native_v1","recipient_id":UUID().uuidString,"event_id":UUID().uuidString,"card_id":UUID().uuidString,"comment_id":UUID().uuidString,"kind":"comment"]
    }
    func testNativeParserRejectsLegacyMissingRecipientAndUnknownKind() {
        let p=payload();XCTAssertNotNil(NativeActivityPushPayload(userInfo:p))
        for key in ["recipient_id","event_id","card_id","comment_id"] {var v=p;v[key]=nil;XCTAssertNil(NativeActivityPushPayload(userInfo:v))}
        var legacy=p;legacy["post_id"]=UUID().uuidString;XCTAssertNil(NativeActivityPushPayload(userInfo:legacy))
        var bad=p;bad["kind"]="owner";XCTAssertNil(NativeActivityPushPayload(userInfo:bad))
        var huge=p;huge["extra"]=String(repeating:"a",count:4000);XCTAssertNil(NativeActivityPushPayload(userInfo:huge))
    }
    func testV2NativePayloadPreservesIdentifiersWithoutLegacyRouteOrPermission() throws {
        var info = payload()
        info["source_kind"] = "activity_native_v2"
        let parsed = try XCTUnwrap(NativeActivityPushPayload(userInfo: info))
        XCTAssertEqual(parsed.recipientID.uuidString, info["recipient_id"] as? String)
        XCTAssertEqual(parsed.eventID.uuidString, info["event_id"] as? String)
        XCTAssertEqual(parsed.cardID.uuidString, info["card_id"] as? String)
        XCTAssertEqual(parsed.commentID.uuidString, info["comment_id"] as? String)
        let router = NotificationDeepLinkRouter()
        router.routeNativePush(parsed, currentUserID: UUID(), previewAllowed: true)
        XCTAssertNil(router.pendingNativePush)
        router.routeNativePush(parsed, currentUserID: parsed.recipientID, previewAllowed: false)
        XCTAssertNil(router.pendingNativePush)
        router.routeNativePush(parsed, currentUserID: parsed.recipientID, previewAllowed: true)
        XCTAssertEqual(router.pendingNativePush, parsed)
        XCTAssertNil(router.pendingPostId)
        XCTAssertNil(router.pendingPush)
        router.clear()
        XCTAssertNil(router.pendingNativePush)
        var legacy = info
        legacy["post_id"] = UUID().uuidString
        XCTAssertNil(NativeActivityPushPayload(userInfo: legacy))
        var unknown = info
        unknown["source_kind"] = "activity_native_v3"
        XCTAssertNil(NativeActivityPushPayload(userInfo: unknown))
        XCTAssertTrue(AppDelegate().foregroundPresentationOptions(for: info, isRemotePush: true).isEmpty)
    }
    func testNativeRouteRequiresOwnerPreviewAndClearsOnAccountReset() {
        let p=NativeActivityPushPayload(userInfo:payload())!;let router=NotificationDeepLinkRouter()
        router.routeNativePush(p,currentUserID:UUID(),previewAllowed:true);XCTAssertNil(router.pendingNativePush)
        router.routeNativePush(p,currentUserID:p.recipientID,previewAllowed:false);XCTAssertNil(router.pendingNativePush)
        router.routeNativePush(p,currentUserID:p.recipientID,previewAllowed:true);XCTAssertEqual(router.pendingNativePush,p);XCTAssertNil(router.pendingPostId);XCTAssertNil(router.pendingPush)
        router.clear();XCTAssertNil(router.pendingNativePush)
    }
    func testNativeForegroundIsSuppressedWithoutServerRead() {
        let app=AppDelegate();XCTAssertTrue(app.foregroundPresentationOptions(for:payload(),isRemotePush:true).isEmpty)
    }
}

@MainActor final class NativeActivityColdStartTests: XCTestCase {
    func payload() -> NativeActivityPushPayload {
        NativeActivityPushPayload(userInfo:["source_kind":"activity_native_v1","recipient_id":UUID().uuidString,"event_id":UUID().uuidString,"card_id":UUID().uuidString,"comment_id":UUID().uuidString,"kind":"comment"])!
    }
    func testResumeOnlyAfterFreshPreviewPermissionAndConsumeOnce() {
        let p=payload(),r=NotificationDeepLinkRouter(),now=Date()
        r.routeNativePush(p,currentUserID:p.recipientID,previewAllowed:false,generation:2,now:now)
        r.resumeNativePush(currentUserID:p.recipientID,generation:2,previewAllowed:false,now:now);XCTAssertNil(r.pendingNativePush)
        r.clearLegacy()
        r.resumeNativePush(currentUserID:p.recipientID,generation:2,previewAllowed:true,now:now);XCTAssertEqual(r.pendingNativePush,p)
        r.pendingNativePush=nil
        r.resumeNativePush(currentUserID:p.recipientID,generation:2,previewAllowed:true,now:now);XCTAssertNil(r.pendingNativePush)
    }
    func testAccountGenerationExpiryAndResetRejectDeferredTap() {
        let p=payload(),now=Date()
        for mode in 0..<4 {
            let r=NotificationDeepLinkRouter()
            r.routeNativePush(p,currentUserID:p.recipientID,previewAllowed:false,generation:2,now:now)
            if mode==3 {r.clear()}
            r.resumeNativePush(currentUserID:mode==0 ? UUID():p.recipientID,generation:mode==1 ? 3:2,
                previewAllowed:true,now:mode==2 ? now.addingTimeInterval(120):now)
            XCTAssertNil(r.pendingNativePush)
            r.resumeNativePush(currentUserID:p.recipientID,generation:2,previewAllowed:true,now:now)
            XCTAssertNil(r.pendingNativePush)
        }
    }
}

@MainActor private final class LegacyPreviewReadStub: LegacyInboxPreviewReading {
    var rows: [NotificationDTO] = []
    var fail = false
    var onRead: (() -> Void)?
    var calls = 0
    func readLegacyInboxPreview(owner: UUID) async throws -> [NotificationDTO] {
        calls += 1; onRead?()
        if fail { throw NotificationInboxError.upgradeRequired }
        return rows
    }
}
@MainActor final class LegacyInboxPreviewReadTests: XCTestCase {
    private func row(owner: UUID) -> NotificationDTO {
        .init(id: UUID(), recipientId: owner, actorId: nil, type: .comment, postId: UUID(), body: nil, readAt: nil, createdAt: Date())
    }
    func testReadOnlyLoadPreservesUnreadAndClearsOnFailure() async {
        let owner = UUID(), stub = LegacyPreviewReadStub()
        stub.rows = [row(owner: owner)]
        let model = LegacyInboxPreviewModel(reader: stub, context: { .init(viewerID: owner, generation: 1, safetyRevision: 1) })
        await model.load()
        XCTAssertEqual(model.rows.count, 1); XCTAssertNil(model.rows.first?.readAt)
        stub.fail = true
        await model.load()
        XCTAssertTrue(model.rows.isEmpty); XCTAssertNotNil(model.error)
    }
    func testOtherRecipientAndStaleRevisionAreRejected() async {
        let owner = UUID(), stub = LegacyPreviewReadStub()
        var revision = 1
        let model = LegacyInboxPreviewModel(reader: stub, context: { .init(viewerID: owner, generation: 1, safetyRevision: revision) })
        stub.rows = [row(owner: UUID())]
        await model.load(); XCTAssertTrue(model.rows.isEmpty); XCTAssertNotNil(model.error)
        stub.rows = [row(owner: owner)]; stub.onRead = { revision += 1 }
        await model.load(); XCTAssertTrue(model.rows.isEmpty)
    }
    func testOversizedAndDuplicatePagesFailClosed() async {
        let owner = UUID(), stub = LegacyPreviewReadStub()
        let model = LegacyInboxPreviewModel(reader: stub, context: { .init(viewerID: owner, generation: 1, safetyRevision: 1) })
        stub.rows = (0..<101).map { _ in row(owner: owner) }
        await model.load()
        XCTAssertTrue(model.rows.isEmpty); XCTAssertNotNil(model.error)
        let repeated = row(owner: owner); stub.rows = [repeated, repeated]
        await model.load()
        XCTAssertTrue(model.rows.isEmpty); XCTAssertNotNil(model.error)
    }
    func testAccountGenerationAndIdentitySwitchDiscardResponses() async {
        let owner = UUID(), stub = LegacyPreviewReadStub()
        var context = AccountActivityReadContext(viewerID: owner, generation: 1, safetyRevision: 1)
        let model = LegacyInboxPreviewModel(reader: stub, context: { context })
        stub.rows = [row(owner: owner)]
        stub.onRead = { context = .init(viewerID: owner, generation: 2, safetyRevision: 1) }
        await model.load(); XCTAssertTrue(model.rows.isEmpty)
        context = .init(viewerID: owner, generation: 1, safetyRevision: 1)
        stub.onRead = { context = .init(viewerID: UUID(), generation: 1, safetyRevision: 1) }
        await model.load(); XCTAssertTrue(model.rows.isEmpty)
    }
    func testResetDuringReadDiscardsResultAndMissingContextMakesNoRequest() async {
        let owner = UUID(), stub = LegacyPreviewReadStub()
        stub.rows = [row(owner: owner)]
        var context: AccountActivityReadContext? = .init(viewerID: owner, generation: 1, safetyRevision: 1)
        let model = LegacyInboxPreviewModel(reader: stub, context: { context })
        stub.onRead = { model.reset() }
        await model.load(); XCTAssertTrue(model.rows.isEmpty)
        let calls = stub.calls; context = nil
        await model.load(); XCTAssertEqual(stub.calls, calls)
    }
}

@MainActor final class LegacyInboxPreviewNavigationTests: XCTestCase {
    func testReadOnlyTargetRequiresFreshRecipientReceiptAndNeverMarksRead() async {
        let owner = UUID(), post = UUID(), stub = LegacyPreviewReadStub()
        var current: AccountActivityReadContext? = .init(viewerID: owner, generation: 1, safetyRevision: 1)
        let model = LegacyInboxPreviewModel(reader: stub, context: { current })
        let notification = NotificationDTO(id: UUID(), recipientId: owner, actorId: nil, type: .comment, postId: post, body: nil, readAt: nil, createdAt: Date())
        stub.rows = [notification]; await model.load()
        XCTAssertEqual(model.readOnlyPostID(for: notification), post)
        XCTAssertNil(model.rows.first?.readAt)
        let unrelated = NotificationDTO(id: UUID(), recipientId: owner, actorId: nil, type: .comment, postId: post, body: nil, readAt: nil, createdAt: Date())
        XCTAssertNil(model.readOnlyPostID(for: unrelated))
        current = .init(viewerID: owner, generation: 1, safetyRevision: 2)
        XCTAssertNil(model.readOnlyPostID(for: notification))
        current = .init(viewerID: UUID(), generation: 2, safetyRevision: 2)
        XCTAssertNil(model.readOnlyPostID(for: notification))
        current = .init(viewerID: owner, generation: 1, safetyRevision: 1)
        model.reset(); XCTAssertNil(model.readOnlyPostID(for: notification))
    }
    func testNonPostAndMissingPostNotificationsDoNotNavigate() async {
        let owner = UUID(), stub = LegacyPreviewReadStub()
        let model = LegacyInboxPreviewModel(reader: stub, context: { .init(viewerID: owner, generation: 1, safetyRevision: 1) })
        for kind in [NotificationKind.followRequest, .followApproved, .unknown, .comment] {
            let row = NotificationDTO(id: UUID(), recipientId: owner, actorId: UUID(), type: kind, postId: kind == .comment ? nil : UUID(), body: nil, readAt: nil, createdAt: Date())
            stub.rows = [row]; await model.load()
            XCTAssertNil(model.readOnlyPostID(for: row))
        }
    }
}
