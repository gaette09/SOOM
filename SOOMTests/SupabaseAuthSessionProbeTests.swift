import Supabase
import XCTest
@testable import SOOM

final class SupabaseAuthSessionProbeTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testStartupSDKIdentityDoesNotRequestNetworkProfile() async throws {
        let now = Date()
        let user = User(id: UUID(), appMetadata: [:], userMetadata: ["full_name": .string("SDK name")],
                        aud: "authenticated", createdAt: now, updatedAt: now)
        // Synthetic credentials in memory only; URLProtocol blocks every request.
        let session = Session(accessToken: "synthetic-noncredential", tokenType: "bearer", expiresIn: 3600,
                              expiresAt: now.timeIntervalSince1970 + 3600, refreshToken: "synthetic-noncredential", user: user)
        let storage = StartupTestAuthStorage(data: try JSONEncoder().encode(session))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StartupNetworkBlocker.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        StartupNetworkBlocker.reset()
        let client = SupabaseClient(supabaseURL: URL(string: "https://startup-fixture.invalid")!,
            supabaseKey: "synthetic-noncredential", options: SupabaseClientOptions(
                auth: .init(storage: storage, storageKey: "startup-fixture", autoRefreshToken: false,
                            emitLocalSessionAsInitialSession: true),
                global: .init(session: network)))
        let info = try await SupabaseClientSessionReader(client: client, includesProfile: false).readCurrentSession()
        XCTAssertEqual(info?.userId, user.id.uuidString)
        XCTAssertEqual(info?.displayName, "SDK name")
        XCTAssertNil(info?.avatarPath)
        XCTAssertEqual(StartupNetworkBlocker.requestCount, 0)
    }

    func testStartupWithoutSDKSessionDoesNotInventOwner() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StartupNetworkBlocker.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        let client = SupabaseClient(supabaseURL: URL(string: "https://startup-empty.invalid")!,
            supabaseKey: "synthetic-noncredential", options: SupabaseClientOptions(
                auth: .init(storage: StartupTestAuthStorage(data: nil), storageKey: "startup-fixture",
                            autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
                global: .init(session: network)))
        let info = try await SupabaseClientSessionReader(client: client, includesProfile: false).readCurrentSession()
        XCTAssertNil(info)
    }


    func testUnconfiguredEnvironmentReturnsUnconfiguredSnapshot() async {
        let probe = SupabaseAuthSessionProbe(isConfigured: false, reader: nil, now: { self.fixedDate })

        let snapshot = await probe.checkSessionStatus()

        XCTAssertFalse(snapshot.isConfigured)
        XCTAssertFalse(snapshot.hasSession)
        XCTAssertEqual(snapshot.status, .unconfigured)
        XCTAssertEqual(snapshot.checkedAt, fixedDate)
    }

    func testReaderFailureReturnsFailedSnapshot() async {
        let reader = FakeSupabaseSessionReader(result: .failure(NSError(domain: "SupabaseAuthSessionProbeTests", code: 1)))
        let probe = SupabaseAuthSessionProbe(isConfigured: true, reader: reader, now: { self.fixedDate })

        let snapshot = await probe.checkSessionStatus()

        XCTAssertTrue(snapshot.isConfigured)
        XCTAssertFalse(snapshot.hasSession)
        XCTAssertEqual(snapshot.status, SupabaseAuthSessionSnapshot.Status.failed)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testNoCurrentSessionReturnsSignedOutSnapshot() async {
        let reader = FakeSupabaseSessionReader(result: .success(nil))
        let probe = SupabaseAuthSessionProbe(isConfigured: true, reader: reader, now: { self.fixedDate })

        let snapshot = await probe.checkSessionStatus()

        XCTAssertTrue(snapshot.isConfigured)
        XCTAssertFalse(snapshot.hasSession)
        XCTAssertEqual(snapshot.status, .signedOut)
        XCTAssertNil(snapshot.userId)
        XCTAssertNil(snapshot.email)
    }

    func testCurrentSessionReturnsSignedInSnapshot() async {
        let session = SupabaseAuthSessionProbe.SessionInfo(
            userId: "user-123",
            email: "user@example.com"
        )
        let reader = FakeSupabaseSessionReader(result: .success(session))
        let probe = SupabaseAuthSessionProbe(isConfigured: true, reader: reader, now: { self.fixedDate })

        let snapshot = await probe.checkSessionStatus()

        XCTAssertTrue(snapshot.isConfigured)
        XCTAssertTrue(snapshot.hasSession)
        XCTAssertEqual(snapshot.status, .signedIn)
        XCTAssertEqual(snapshot.userId, "user-123")
        XCTAssertEqual(snapshot.email, "user@example.com")
    }

    func testSessionProbeDoesNotReplaceLocalAuthSession() async {
        let defaults = UserDefaults(suiteName: "SupabaseAuthSessionProbeTests")!
        defaults.removePersistentDomain(forName: "SupabaseAuthSessionProbeTests")
        let store = AuthSessionStore(userDefaults: defaults)
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let reader = FakeSupabaseSessionReader(result: .success(nil))
        let probe = SupabaseAuthSessionProbe(isConfigured: true, reader: reader, now: { self.fixedDate })

        _ = await probe.checkSessionStatus()

        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testRestoredSessionCarriesAppleSubjectAndLinkedProviderMetadata() async {
        let info = SupabaseAuthSessionProbe.SessionInfo(
            userId: UUID().uuidString, email: "relay@example.com",
            appleUserIdentifier: "apple-subject", linkedAuthProviders: ["apple"]
        )
        let probe = SupabaseAuthSessionProbe(
            isConfigured: true, reader: FakeSupabaseSessionReader(result: .success(info))
        )

        let snapshot = await probe.checkSessionStatus()

        XCTAssertEqual(snapshot.appleUserIdentifier, "apple-subject")
        XCTAssertEqual(snapshot.linkedAuthProviders, ["apple"])
    }

    func testAppleSubjectComesFromAuthenticatedIdentityNotUserEditableMetadata() {
        let userID = UUID()
        let user = User(
            id: userID, appMetadata: ["providers": .array([.string("apple"), .string("email")])],
            userMetadata: ["sub": .string("untrusted-subject")], aud: "authenticated",
            createdAt: fixedDate, updatedAt: fixedDate,
            identities: [UserIdentity(
                id: "legacy-identity-id", identityId: UUID(), userId: userID,
                identityData: ["sub": .string("verified-apple-subject")], provider: "apple",
                createdAt: nil, lastSignInAt: nil, updatedAt: nil
            )]
        )

        let metadata = SupabaseAppleAccountMetadata(user: user)

        XCTAssertEqual(metadata.userIdentifier, "verified-apple-subject")
        XCTAssertEqual(metadata.providers, ["apple", "email"])
    }

    func testSessionProbeDoesNotUseRecoveryCalculator() async {
        let probe = SupabaseAuthSessionProbe(isConfigured: false, reader: nil, now: { self.fixedDate })

        let snapshot = await probe.checkSessionStatus()

        XCTAssertEqual(snapshot.status, .unconfigured)
    }
}

private final class FakeSupabaseSessionReader: SupabaseAuthSessionReading {
    private let result: Result<SupabaseAuthSessionProbe.SessionInfo?, Error>
    private(set) var readCount = 0

    init(result: Result<SupabaseAuthSessionProbe.SessionInfo?, Error>) {
        self.result = result
    }

    func readCurrentSession() async throws -> SupabaseAuthSessionProbe.SessionInfo? {
        readCount += 1
        return try result.get()
    }
}

private final class StartupTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    init(data: Data?) { self.data = data }
    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if key == "startup-fixture" { data = value }
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return key == "startup-fixture" ? data : nil
    }
    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if key == "startup-fixture" { data = nil }
    }
}

private final class StartupNetworkBlocker: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); defer { lock.unlock() }; count = 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
