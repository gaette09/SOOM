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
        let configuration = SupabaseAuthConfiguration(projectURL: URL(string: "https://example.supabase.co"), anonKey: "anon-placeholder")

        XCTAssertTrue(configuration.isConfigured)
    }
}
