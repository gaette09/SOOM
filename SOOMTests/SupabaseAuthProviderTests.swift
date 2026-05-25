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
}
