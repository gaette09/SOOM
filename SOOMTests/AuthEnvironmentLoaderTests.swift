import XCTest
@testable import SOOM

final class AuthEnvironmentLoaderTests: XCTestCase {
    func testLoadsConcreteValuesFromInfoDictionary() {
        let loader = AuthEnvironmentLoader(infoDictionary: [
            "SOOMAuthEnvironment": "development",
            "SOOMSupabaseURL": "https://example.supabase.co",
            "SOOMSupabaseAnonKey": "anon-test-key",
            "SOOMAuthRedirectScheme": "soom-dev"
        ])

        let environment = loader.load()

        XCTAssertEqual(environment.environment, .development)
        XCTAssertEqual(environment.supabaseURL?.absoluteString, "https://example.supabase.co")
        XCTAssertTrue(environment.isSupabaseConfigured)
        XCTAssertTrue(environment.isRedirectConfigured)
    }

    func testBuildSettingPlaceholdersAreTreatedAsUnconfigured() {
        let loader = AuthEnvironmentLoader(infoDictionary: [
            "SOOMSupabaseURL": "$(SOOM_SUPABASE_URL)",
            "SOOMSupabaseAnonKey": "$(SOOM_SUPABASE_ANON_KEY)",
            "SOOMAuthRedirectScheme": "$(SOOM_AUTH_REDIRECT_SCHEME)"
        ])

        let environment = loader.load()

        XCTAssertEqual(environment.environment, .local)
        XCTAssertNil(environment.supabaseURL)
        XCTAssertFalse(environment.isSupabaseConfigured)
        XCTAssertFalse(environment.isRedirectConfigured)
    }

    func testLegacyEnvironmentStyleKeysAreSupported() {
        let loader = AuthEnvironmentLoader(infoDictionary: [
            "SOOM_SUPABASE_URL": "https://legacy.supabase.co",
            "SOOM_SUPABASE_ANON_KEY": "legacy-anon",
            "SOOM_AUTH_REDIRECT_SCHEME": "soom-legacy"
        ])

        let environment = loader.load()

        XCTAssertEqual(environment.supabaseURL?.absoluteString, "https://legacy.supabase.co")
        XCTAssertTrue(environment.isSupabaseConfigured)
        XCTAssertTrue(environment.isRedirectConfigured)
    }

    func testTruncatedXcconfigURLStaysUnconfigured() {
        // Reproduces the SOOM_LOCAL_SECRETS_SETUP.md incident: an
        // un-escaped "//" in an xcconfig value gets treated as a comment
        // start, truncating "https://real-project.supabase.co" down to
        // just "https:". URL(string:) parses that without error, so this
        // must be caught by isSupabaseConfigured, not left to crash later
        // in SupabaseClient(supabaseURL:).
        let loader = AuthEnvironmentLoader(infoDictionary: [
            "SOOMSupabaseURL": "https:",
            "SOOMSupabaseAnonKey": "anon-test-key"
        ])

        let environment = loader.load()

        XCTAssertNotNil(environment.supabaseURL)
        XCTAssertFalse(environment.isSupabaseConfigured)
    }

    func testLoaderDoesNotUseRecoveryCalculator() {
        let environment = AuthEnvironmentLoader(infoDictionary: [:]).load()

        XCTAssertEqual(environment.environment, .local)
    }
}
