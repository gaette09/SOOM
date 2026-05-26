import XCTest
@testable import SOOM

final class AuthCallbackURLTests: XCTestCase {
    private let environment = AuthEnvironment(
        environment: .development,
        supabaseURL: URL(string: "https://example.supabase.co"),
        supabaseAnonKey: "anon-test-key",
        redirectScheme: "soom-dev"
    )

    func testValidHostPathCallbackURL() {
        let callbackURL = AuthCallbackURL(
            url: URL(string: "soom-dev://auth/callback?provider=email")!,
            environment: environment
        )

        XCTAssertTrue(callbackURL.isAuthCallback)
        XCTAssertEqual(callbackURL.scheme, "soom-dev")
        XCTAssertEqual(callbackURL.host, "auth")
        XCTAssertEqual(callbackURL.path, "/callback")
        XCTAssertEqual(callbackURL.provider, "email")
    }

    func testValidPathOnlyCallbackURL() {
        let callbackURL = AuthCallbackURL(
            url: URL(string: "soom-dev:/auth/callback#type=magiclink")!,
            environment: environment
        )

        XCTAssertTrue(callbackURL.isAuthCallback)
        XCTAssertEqual(callbackURL.provider, "magiclink")
    }

    func testInvalidSchemeIsNotCallback() {
        let callbackURL = AuthCallbackURL(
            url: URL(string: "other://auth/callback")!,
            environment: environment
        )

        XCTAssertFalse(callbackURL.isAuthCallback)
    }

    func testInvalidPathIsNotCallback() {
        let callbackURL = AuthCallbackURL(
            url: URL(string: "soom-dev://auth/other")!,
            environment: environment
        )

        XCTAssertFalse(callbackURL.isAuthCallback)
    }

    func testPlaceholderRedirectSchemeIsInvalid() {
        let placeholderEnvironment = AuthEnvironment(redirectScheme: "$(SOOM_AUTH_REDIRECT_SCHEME)")
        let callbackURL = AuthCallbackURL(
            url: URL(string: "soom-dev://auth/callback")!,
            environment: placeholderEnvironment
        )

        XCTAssertFalse(callbackURL.isAuthCallback)
    }

    func testCallbackURLDoesNotUseRecoveryCalculator() {
        let callbackURL = AuthCallbackURL(
            url: URL(string: "soom-dev://auth/callback")!,
            environment: environment
        )

        XCTAssertTrue(callbackURL.isAuthCallback)
    }
}
