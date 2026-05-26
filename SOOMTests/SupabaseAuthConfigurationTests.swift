import XCTest
@testable import SOOM

final class SupabaseAuthConfigurationTests: XCTestCase {
    func testEmptyConfigurationIsNotConfigured() {
        let configuration = SupabaseAuthConfiguration.empty

        XCTAssertFalse(configuration.isConfigured)
    }

    func testMissingAnonKeyIsNotConfigured() {
        let configuration = SupabaseAuthConfiguration(projectURL: URL(string: "https://example.supabase.co"), anonKey: nil)

        XCTAssertFalse(configuration.isConfigured)
    }

    func testBlankAnonKeyIsNotConfigured() {
        let configuration = SupabaseAuthConfiguration(projectURL: URL(string: "https://example.supabase.co"), anonKey: "   ")

        XCTAssertFalse(configuration.isConfigured)
    }

    func testProjectURLAndAnonKeyMarkConfigurationReady() {
        let configuration = SupabaseAuthConfiguration(projectURL: URL(string: "https://example.supabase.co"), anonKey: "anon-test-key")

        XCTAssertTrue(configuration.isConfigured)
    }

    func testPlaceholderAnonKeyIsNotConfigured() {
        let configuration = SupabaseAuthConfiguration(projectURL: URL(string: "https://example.supabase.co"), anonKey: "anon-placeholder")

        XCTAssertFalse(configuration.isConfigured)
    }
    func testBuildsFromConfiguredAuthEnvironment() {
        let environment = AuthEnvironment(
            environment: .development,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "anon-test-key",
            redirectScheme: "soom-dev"
        )

        let configuration = SupabaseAuthConfiguration.from(environment: environment)

        XCTAssertTrue(configuration.isConfigured)
        XCTAssertEqual(configuration.projectURL?.absoluteString, "https://example.supabase.co")
        XCTAssertEqual(configuration.anonKey, "anon-test-key")
    }

    func testPlaceholderEnvironmentBuildsEmptyConfiguration() {
        let environment = AuthEnvironment(
            environment: .development,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "$(SOOM_SUPABASE_ANON_KEY)",
            redirectScheme: "$(SOOM_AUTH_REDIRECT_SCHEME)"
        )

        let configuration = SupabaseAuthConfiguration.from(environment: environment)

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertNil(configuration.projectURL)
        XCTAssertNil(configuration.anonKey)
    }

}
