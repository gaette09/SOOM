import XCTest
@testable import SOOM

final class SupabaseAuthProviderTests: XCTestCase {
    func testUnconfiguredProviderReturnsFutureRemoteAuthNotConfiguredWithoutNetwork() async {
        let provider = SupabaseAuthProvider(configuration: .empty)

        do {
            _ = try await provider.signInWithEmail("user@example.com")
            XCTFail("Unconfigured Supabase provider should not sign in")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConfiguredPlaceholderStillReturnsFutureRemoteAuthNotConfigured() async {
        let configuration = SupabaseAuthConfiguration(
            projectURL: URL(string: "https://example.supabase.co"),
            anonKey: "anon-placeholder"
        )
        let provider = SupabaseAuthProvider(configuration: configuration)

        do {
            _ = try await provider.signInWithEmail("user@example.com")
            XCTFail("Supabase SDK is intentionally not connected in preparation v1")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConfiguredClientProviderStillReturnsFutureRemoteAuthNotConfigured() async {
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            )
        )

        XCTAssertEqual(provider.clientState, .ready)

        do {
            _ = try await provider.signInWithEmail("user@example.com")
            XCTFail("Configured Supabase client should not enable auth calls in integration v1")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderSignOutAlsoStaysFutureOnly() async {
        let provider = SupabaseAuthProvider(configuration: .empty)

        do {
            _ = try await provider.signOut()
            XCTFail("Remote sign out should stay future-only")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    func testProviderCanReturnReadOnlySessionSmokeSnapshot() async {
        let probe = SupabaseAuthSessionProbe(
            isConfigured: true,
            reader: ProviderFakeSessionReader(
                session: SupabaseAuthSessionProbe.SessionInfo(userId: "remote-user", email: "remote@example.com")
            ),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: probe
        )

        let snapshot = await provider.checkSessionStatus()

        XCTAssertEqual(snapshot.status, .signedIn)
        XCTAssertEqual(snapshot.userId, "remote-user")
        XCTAssertEqual(snapshot.email, "remote@example.com")
    }

}

private final class ProviderFakeSessionReader: SupabaseAuthSessionReading {
    private let session: SupabaseAuthSessionProbe.SessionInfo?

    init(session: SupabaseAuthSessionProbe.SessionInfo?) {
        self.session = session
    }

    func readCurrentSession() async throws -> SupabaseAuthSessionProbe.SessionInfo? {
        session
    }
}
