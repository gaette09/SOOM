import XCTest
@testable import SOOM

final class EmailAuthRequestTests: XCTestCase {
    func testValidEmailNormalizesAndValidates() throws {
        let request = EmailAuthRequest(email: "  USER@example.COM ")

        XCTAssertTrue(request.isValid)
        XCTAssertEqual(request.normalizedEmail, "user@example.com")
        XCTAssertNoThrow(try request.validate())
    }

    func testEmptyEmailIsInvalid() {
        let request = EmailAuthRequest(email: "   ")

        XCTAssertFalse(request.isValid)
        XCTAssertThrowsError(try request.validate())
    }

    func testBasicInvalidEmailFormatIsRejected() {
        let invalidEmails = ["user", "user@", "@example.com", "user@example", "user example@test.com"]

        for email in invalidEmails {
            XCTAssertFalse(EmailAuthRequest(email: email).isValid, email)
        }
    }

    func testRedirectIsOptionalAndCanBeDerivedFromEnvironment() {
        let localRequest = EmailAuthRequest(email: "user@example.com")
        let environment = AuthEnvironment(
            environment: .development,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "anon-test-key",
            redirectScheme: "soom-dev"
        )

        XCTAssertNil(localRequest.redirectTo)
        XCTAssertEqual(EmailAuthRequest.redirectURL(from: environment), URL(string: "soom-dev://auth/callback"))
    }

    func testPlaceholderRedirectDoesNotCreateURL() {
        let environment = AuthEnvironment(redirectScheme: "$(SOOM_AUTH_REDIRECT_SCHEME)")

        XCTAssertNil(EmailAuthRequest.redirectURL(from: environment))
    }

    func testReplaceMeRedirectDoesNotCreateURL() {
        let environment = AuthEnvironment(redirectScheme: "replace_me_redirect_scheme")

        XCTAssertNil(EmailAuthRequest.redirectURL(from: environment))
    }

    func testRequestDoesNotUseRecoveryCalculator() {
        let request = EmailAuthRequest(email: "user@example.com")

        XCTAssertTrue(request.isValid)
    }
}
