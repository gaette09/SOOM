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

    func testMissingEmailUsesValidUserIdDisplayNameFallback() {
        let userId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let mapper = SupabaseAppUserMapper(now: { self.fixedDate })
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: true,
            userId: userId.uuidString,
            email: nil,
            checkedAt: fixedDate,
            status: .signedIn
        )

        let user = mapper.map(snapshot: snapshot)

        XCTAssertEqual(user?.id, userId)
        XCTAssertEqual(user?.displayName, "SOOM 55555555")
        XCTAssertNil(user?.email)
        XCTAssertEqual(user?.authProvider, .supabase)
    }

    func testNonUUIDUserIdDoesNotMapUser() {
        let mapper = SupabaseAppUserMapper(now: { self.fixedDate })
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: true,
            userId: "remote-user-12345",
            email: "user@example.com",
            checkedAt: fixedDate,
            status: .signedIn
        )

        XCTAssertNil(mapper.map(snapshot: snapshot))
    }

    func testEmptyUserIdDoesNotMapUser() {
        let mapper = SupabaseAppUserMapper(now: { self.fixedDate })
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: true,
            userId: "   ",
            email: "user@example.com",
            checkedAt: fixedDate,
            status: .signedIn
        )

        XCTAssertNil(mapper.map(snapshot: snapshot))
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
