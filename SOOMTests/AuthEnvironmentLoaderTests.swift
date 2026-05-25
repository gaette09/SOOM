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

    func testLoaderDoesNotUseRecoveryCalculator() {
        let environment = AuthEnvironmentLoader(infoDictionary: [:]).load()

        XCTAssertEqual(environment.environment, .local)
    }
}
