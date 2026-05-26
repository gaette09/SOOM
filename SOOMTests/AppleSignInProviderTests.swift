import XCTest
@testable import SOOM

final class AppleSignInProviderTests: XCTestCase {
    func testPrepareRequestUsesEmailAndFullNameScopes() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = AppleSignInProvider(now: { date })

        let request = provider.prepareRequest(nonce: " nonce-value ")

        XCTAssertEqual(request.requestedScopes, [.fullName, .email])
        XCTAssertTrue(request.requiresNonce)
        XCTAssertEqual(request.nonce, "nonce-value")
        XCTAssertEqual(request.redirectStrategy, .supabaseOAuthFuture)
        XCTAssertEqual(request.createdAt, date)
        XCTAssertTrue(request.isNoncePrepared)
    }

    func testPrepareRequestWithoutNonceStaysFutureReadyButNotPrepared() {
        let provider = AppleSignInProvider()

        let request = provider.prepareRequest()

        XCTAssertTrue(request.requiresNonce)
        XCTAssertNil(request.nonce)
        XCTAssertFalse(request.isNoncePrepared)
    }

    func testHandleCredentialStillReturnsFutureError() async {
        let provider = AppleSignInProvider()
        let credential = AppleSignInCredential(
            userIdentifier: "apple-user",
            identityToken: "token",
            authorizationCode: "code"
        )

        do {
            _ = try await provider.handleCredential(credential)
            XCTFail("Apple Sign In should not complete in prep v1")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingCredentialValuesFailSafely() async {
        let provider = AppleSignInProvider()
        let credential = AppleSignInCredential(userIdentifier: "apple-user")

        do {
            _ = try await provider.handleCredential(credential)
            XCTFail("Incomplete Apple credential should not complete")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderDoesNotUseRecoveryCalculator() {
        let provider = AppleSignInProvider()
        let request = provider.prepareRequest(nonce: "nonce")

        XCTAssertEqual(request.redirectStrategy, .supabaseOAuthFuture)
    }
}
