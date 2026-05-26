import XCTest
@testable import SOOM

final class AppleSignInCredentialTests: XCTestCase {
    func testCredentialNormalizesOptionalValues() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let credential = AppleSignInCredential(
            userIdentifier: " apple-user ",
            identityToken: " token ",
            authorizationCode: " code ",
            email: " user@example.com ",
            fullName: " SOOM User ",
            nonce: " nonce ",
            createdAt: date
        )

        XCTAssertEqual(credential.userIdentifier, "apple-user")
        XCTAssertEqual(credential.identityToken, "token")
        XCTAssertEqual(credential.authorizationCode, "code")
        XCTAssertEqual(credential.email, "user@example.com")
        XCTAssertEqual(credential.fullName, "SOOM User")
        XCTAssertEqual(credential.nonce, "nonce")
        XCTAssertEqual(credential.createdAt, date)
        XCTAssertTrue(credential.isReadyForFutureSupabaseExchange)
    }

    func testMissingIdentityTokenIsNotReadyForFutureExchange() {
        let credential = AppleSignInCredential(
            userIdentifier: "apple-user",
            identityToken: nil,
            authorizationCode: "code"
        )

        XCTAssertFalse(credential.hasIdentityToken)
        XCTAssertFalse(credential.isReadyForFutureSupabaseExchange)
    }

    func testMissingAuthorizationCodeIsNotReadyForFutureExchange() {
        let credential = AppleSignInCredential(
            userIdentifier: "apple-user",
            identityToken: "token",
            authorizationCode: nil
        )

        XCTAssertFalse(credential.hasAuthorizationCode)
        XCTAssertFalse(credential.isReadyForFutureSupabaseExchange)
    }

    func testEmptyUserIdentifierIsNotReadyForFutureExchange() {
        let credential = AppleSignInCredential(
            userIdentifier: " ",
            identityToken: "token",
            authorizationCode: "code"
        )

        XCTAssertEqual(credential.userIdentifier, "")
        XCTAssertFalse(credential.isReadyForFutureSupabaseExchange)
    }
}
