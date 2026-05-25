import XCTest
@testable import SOOM

final class SupabaseAuthSessionProbeTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

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
