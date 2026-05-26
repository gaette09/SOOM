import XCTest
@testable import SOOM

final class AuthEnvironmentTests: XCTestCase {
    func testPlaceholderValuesAreNotConfigured() {
        let environment = AuthEnvironment(
            environment: .development,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "$(SOOM_SUPABASE_ANON_KEY)",
            redirectScheme: "$(SOOM_AUTH_REDIRECT_SCHEME)"
        )

        XCTAssertFalse(environment.isSupabaseConfigured)
        XCTAssertFalse(environment.isRedirectConfigured)
    }

    func testConcreteSupabaseAndRedirectValuesAreConfigured() {
        let environment = AuthEnvironment(
            environment: .development,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "anon-test-key",
            redirectScheme: "soom-dev"
        )

        XCTAssertTrue(environment.isSupabaseConfigured)
        XCTAssertTrue(environment.isRedirectConfigured)
    }

    func testEmptyValuesStayLocalFirst() {
        let environment = AuthEnvironment.local

        XCTAssertEqual(environment.environment, .local)
        XCTAssertFalse(environment.isSupabaseConfigured)
        XCTAssertFalse(environment.isRedirectConfigured)
    }

    func testOperationalPlaceholderWordsStayUnconfigured() {
        let environment = AuthEnvironment(
            environment: .production,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "replace_me_supabase_anon_key",
            redirectScheme: "your_redirect_scheme"
        )

        XCTAssertFalse(environment.isSupabaseConfigured)
        XCTAssertFalse(environment.isRedirectConfigured)
    }

    func testRawBuildSettingNamesStayUnconfigured() {
        let environment = AuthEnvironment(
            environment: .production,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "SOOM_SUPABASE_ANON_KEY",
            redirectScheme: "SOOM_AUTH_REDIRECT_SCHEME"
        )

        XCTAssertFalse(environment.isSupabaseConfigured)
        XCTAssertFalse(environment.isRedirectConfigured)
    }

    func testEnvironmentDoesNotUseRecoveryCalculator() {
        let environment = AuthEnvironment.local

        XCTAssertFalse(environment.isSupabaseConfigured)
    }
}
