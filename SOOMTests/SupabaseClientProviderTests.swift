import XCTest
@testable import SOOM

final class SupabaseClientProviderTests: XCTestCase {
    func testUnconfiguredEnvironmentDoesNotCreateClient() {
        let provider = SupabaseClientProvider(environment: .local)

        XCTAssertEqual(provider.state, .unconfigured)
        XCTAssertNil(provider.makeClient())
    }

    func testPlaceholderValuesDoNotCreateClient() {
        let environment = AuthEnvironment(
            environment: .development,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "$(SOOM_SUPABASE_ANON_KEY)",
            redirectScheme: "$(SOOM_AUTH_REDIRECT_SCHEME)"
        )
        let provider = SupabaseClientProvider(environment: environment)

        XCTAssertEqual(provider.state, .unconfigured)
        XCTAssertNil(provider.makeClient())
    }

    func testConfiguredMockValuesCreateClient() {
        let configuration = SupabaseAuthConfiguration(
            projectURL: URL(string: "https://example.supabase.co"),
            anonKey: "anon-test-key"
        )
        let provider = SupabaseClientProvider(configuration: configuration)

        XCTAssertEqual(provider.state, .ready)
        XCTAssertNotNil(provider.makeClient())
    }

    func testProviderDoesNotUseRecoveryCalculator() {
        let provider = SupabaseClientProvider(configuration: .empty)

        XCTAssertNil(provider.makeClient())
    }
}
