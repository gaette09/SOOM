import XCTest
@testable import SOOM

final class AppleSignInProviderTests: XCTestCase {
    func testPrepareRequestUsesEmailFullNameScopesAndProvidedNonce() {
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

    func testPrepareRequestWithoutNonceGeneratesPreparedNonce() {
        let provider = AppleSignInProvider()

        let request = provider.prepareRequest()

        XCTAssertTrue(request.requiresNonce)
        XCTAssertEqual(request.nonce?.count, 32)
        XCTAssertTrue(request.isNoncePrepared)
    }

    func testMakeNonceCreatesRequestedLength() {
        let provider = AppleSignInProvider()

        let nonce = provider.makeNonce(length: 48)

        XCTAssertEqual(nonce.count, 48)
    }

    func testHashedNonceUsesSHA256Hex() {
        let provider = AppleSignInProvider()

        XCTAssertEqual(
            provider.hashedNonce("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testStringFromDataTrimsUTF8() {
        XCTAssertEqual(AppleSignInProvider.string(from: Data(" token ".utf8)), "token")
        XCTAssertNil(AppleSignInProvider.string(from: Data()))
    }

    func testHandleCredentialReturnsCompleteCredential() throws {
        let provider = AppleSignInProvider()
        let credential = AppleSignInCredential(
            userIdentifier: "apple-user",
            identityToken: "token",
            authorizationCode: "code",
            nonce: "raw-nonce"
        )

        let prepared = try provider.handleCredential(credential)

        XCTAssertEqual(prepared.identityToken, "token")
        XCTAssertEqual(prepared.nonce, "raw-nonce")
    }

    func testMissingCredentialValuesFailSafely() {
        let provider = AppleSignInProvider()
        let credential = AppleSignInCredential(userIdentifier: "apple-user")

        do {
            _ = try provider.handleCredential(credential)
            XCTFail("Incomplete Apple credential should not complete")
        } catch let error as AuthError {
            XCTAssertEqual(error, .appleCredentialMissing)
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
