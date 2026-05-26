import XCTest
@testable import SOOM

final class AuthSessionBridgeTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_100)

    func testSignedInSnapshotBridgesToSignedInSession() {
        let bridge = AuthSessionBridge(mapper: SupabaseAppUserMapper(now: { self.fixedDate }))
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: true,
            userId: "22222222-2222-2222-2222-222222222222",
            email: "member@example.com",
            checkedAt: fixedDate,
            status: .signedIn
        )

        let session = bridge.bridge(snapshot: snapshot)

        XCTAssertEqual(session?.sessionState, .signedIn)
        XCTAssertFalse(session?.isLocalOnly ?? true)
        XCTAssertEqual(session?.currentUser?.authProvider, .supabase)
        XCTAssertEqual(session?.currentUser?.displayName, "member")
    }

    func testSignedOutSnapshotReturnsNilSoLocalSessionCanBePreserved() {
        let bridge = AuthSessionBridge(mapper: SupabaseAppUserMapper(now: { self.fixedDate }))
        let local = AuthSession.localOnly(user: AppUser(displayName: "Local", authProvider: .local, createdAt: fixedDate))
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: false,
            userId: nil,
            email: nil,
            checkedAt: fixedDate,
            status: .signedOut
        )

        let session = bridge.bridge(snapshot: snapshot, preserving: local)

        XCTAssertNil(session)
        XCTAssertTrue(local.isLocalOnly)
    }

    func testInvalidUserIdSignedInSnapshotReturnsNil() {
        let bridge = AuthSessionBridge(mapper: SupabaseAppUserMapper(now: { self.fixedDate }))
        let local = AuthSession.localOnly(user: AppUser(displayName: "Local", authProvider: .local, createdAt: fixedDate))
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: true,
            userId: "not-a-uuid",
            email: "member@example.com",
            checkedAt: fixedDate,
            status: .signedIn
        )

        let session = bridge.bridge(snapshot: snapshot, preserving: local)

        XCTAssertNil(session)
        XCTAssertTrue(local.isLocalOnly)
    }

    func testFailedAndUnconfiguredSnapshotsReturnNil() {
        let bridge = AuthSessionBridge(mapper: SupabaseAppUserMapper(now: { self.fixedDate }))
        let failed = SupabaseAuthSessionSnapshot(isConfigured: true, hasSession: false, userId: nil, email: nil, checkedAt: fixedDate, status: .failed)
        let unconfigured = SupabaseAuthSessionSnapshot(isConfigured: false, hasSession: false, userId: nil, email: nil, checkedAt: fixedDate, status: .unconfigured)

        XCTAssertNil(bridge.bridge(snapshot: failed))
        XCTAssertNil(bridge.bridge(snapshot: unconfigured))
    }

    func testBridgeDoesNotUseRecoveryCalculator() {
        let bridge = AuthSessionBridge(mapper: SupabaseAppUserMapper(now: { self.fixedDate }))
        let snapshot = SupabaseAuthSessionSnapshot(isConfigured: false, hasSession: false, userId: nil, email: nil, checkedAt: fixedDate, status: .unconfigured)

        XCTAssertNil(bridge.bridge(snapshot: snapshot))
    }
}
