import XCTest
@testable import SOOM

final class SupabaseAppUserMapperTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_100)

    func testSignedInSnapshotMapsToSupabaseAppUser() {
        let userId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let mapper = SupabaseAppUserMapper(now: { self.fixedDate })
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: true,
            userId: userId.uuidString,
            email: " USER@example.COM ",
            checkedAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .signedIn
        )

        let user = mapper.map(snapshot: snapshot)

        XCTAssertEqual(user?.id, userId)
        XCTAssertEqual(user?.email, "user@example.com")
        XCTAssertEqual(user?.displayName, "user")
        XCTAssertEqual(user?.handle, "@user@example.com")
        XCTAssertEqual(user?.authProvider, .supabase)
        XCTAssertEqual(user?.createdAt, fixedDate)
    }

    func testMissingEmailUsesUserIdDisplayNameFallback() {
        let mapper = SupabaseAppUserMapper(now: { self.fixedDate })
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: true,
            userId: "remote-user-12345",
            email: nil,
            checkedAt: fixedDate,
            status: .signedIn
        )

        let user = mapper.map(snapshot: snapshot)

        XCTAssertEqual(user?.displayName, "Supabase remote-u")
        XCTAssertNil(user?.email)
        XCTAssertEqual(user?.authProvider, .supabase)
    }

    func testSignedOutSnapshotDoesNotMapUser() {
        let mapper = SupabaseAppUserMapper(now: { self.fixedDate })
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: false,
            userId: nil,
            email: nil,
            checkedAt: fixedDate,
            status: .signedOut
        )

        XCTAssertNil(mapper.map(snapshot: snapshot))
    }

    func testMapperDoesNotUseRecoveryCalculator() {
        let mapper = SupabaseAppUserMapper(now: { self.fixedDate })
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: false,
            hasSession: false,
            userId: nil,
            email: nil,
            checkedAt: fixedDate,
            status: .unconfigured
        )

        XCTAssertNil(mapper.map(snapshot: snapshot))
    }
}
