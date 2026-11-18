import XCTest
@testable import SOOM

final class AppleGrantRegistrationTests: XCTestCase {
    func testRequestRequiresFreshCodeWithoutChangingLoginCredentialValidity() throws {
        let credential = AppleSignInCredential(userIdentifier: "synthetic-subject", identityToken: "synthetic-token", nonce: "synthetic-nonce")
        XCTAssertTrue(credential.isReadyForSupabaseExchange)
        XCTAssertThrowsError(try AppleGrantRegistrationRequest(credential: credential, expectedUserID: UUID()))
    }

    func testRequestContainsOnlyBoundExchangeInputs() throws {
        let owner = UUID()
        let credential = AppleSignInCredential(userIdentifier: "synthetic-subject", identityToken: "synthetic-token",
            authorizationCode: "synthetic-code", email: "fixture@example.test", fullName: "Fixture",
            nonce: "synthetic-nonce")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            AppleGrantRegistrationRequest(credential: credential, expectedUserID: owner))) as? [String: String])
        XCTAssertEqual(Set(object.keys), ["expected_user_id", "authorization_code", "identity_token", "raw_nonce"])
        XCTAssertEqual(object["expected_user_id"]?.lowercased(), owner.uuidString.lowercased())
        XCTAssertEqual(object["raw_nonce"], "synthetic-nonce")
    }

    @MainActor
    func testRegistrationFlagsAreAccountScopedAndRemovalPreservesOtherAccount() throws {
        let suite = "AppleGrantRegistrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppleGrantRegistrationState(defaults: defaults)
        let a = UUID(), b = UUID()
        state.set(.registered, for: a)
        state.set(.needsRetry, for: b)
        XCTAssertEqual(AppleGrantRegistrationState(defaults: defaults).status(for: a), .registered)
        state.clear(a)
        XCTAssertNil(state.status(for: a))
        XCTAssertEqual(state.status(for: b), .needsRetry)
    }
}
