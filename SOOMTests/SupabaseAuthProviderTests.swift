import XCTest
@testable import SOOM

final class SupabaseAuthProviderTests: XCTestCase {
    func testUnconfiguredProviderReturnsFutureRemoteAuthNotConfiguredWithoutNetwork() async {
        let provider = SupabaseAuthProvider(configuration: .empty)

        do {
            _ = try await provider.signInWithEmail("user@example.com")
            XCTFail("Unconfigured Supabase provider should not sign in")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConfiguredPlaceholderStillReturnsFutureRemoteAuthNotConfigured() async {
        let configuration = SupabaseAuthConfiguration(
            projectURL: URL(string: "https://example.supabase.co"),
            anonKey: "anon-placeholder"
        )
        let provider = SupabaseAuthProvider(configuration: configuration)

        do {
            _ = try await provider.signInWithEmail("user@example.com")
            XCTFail("Supabase SDK is intentionally not connected in preparation v1")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConfiguredClientProviderStillReturnsFutureRemoteAuthNotConfigured() async {
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            )
        )

        XCTAssertEqual(provider.clientState, .ready)

        do {
            _ = try await provider.signInWithEmail("user@example.com")
            XCTFail("Configured Supabase client should not enable auth calls in integration v1")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestMagicLinkUsesInjectedRequesterWithoutChangingSession() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let redirect = URL(string: "soom-dev://auth/callback")
        let requester = ProviderFakeEmailMagicLinkRequester()
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            emailRequester: requester,
            now: { fixedDate }
        )

        let result = try await provider.requestMagicLink(email: " USER@example.COM ", redirectTo: redirect)

        XCTAssertEqual(result.email, "user@example.com")
        XCTAssertEqual(result.redirectTo, redirect)
        XCTAssertEqual(result.requestedAt, fixedDate)
        XCTAssertEqual(requester.requests, [EmailAuthRequest(email: " USER@example.COM ", redirectTo: redirect)])
    }

    func testRequestMagicLinkRejectsInvalidEmailBeforeRequester() async {
        let requester = ProviderFakeEmailMagicLinkRequester()
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            emailRequester: requester
        )

        do {
            _ = try await provider.requestMagicLink(email: "invalid", redirectTo: nil)
            XCTFail("Invalid email should not request magic link")
        } catch let error as AuthError {
            XCTAssertEqual(error, .invalidEmail)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(requester.requests.isEmpty)
    }

    func testUnconfiguredRequestMagicLinkReturnsSafeError() async {
        let provider = SupabaseAuthProvider(configuration: .empty)

        do {
            _ = try await provider.requestMagicLink(email: "user@example.com", redirectTo: nil)
            XCTFail("Unconfigured Supabase provider should not request magic link")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderSignOutAlsoStaysFutureOnly() async {
        let provider = SupabaseAuthProvider(configuration: .empty)

        do {
            _ = try await provider.signOut()
            XCTFail("Remote sign out should stay future-only")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    func testProviderCanReturnReadOnlySessionSmokeSnapshot() async {
        let probe = SupabaseAuthSessionProbe(
            isConfigured: true,
            reader: ProviderFakeSessionReader(
                session: SupabaseAuthSessionProbe.SessionInfo(userId: "remote-user", email: "remote@example.com")
            ),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: probe
        )

        let snapshot = await provider.checkSessionStatus()

        XCTAssertEqual(snapshot.status, .signedIn)
        XCTAssertEqual(snapshot.userId, "remote-user")
        XCTAssertEqual(snapshot.email, "remote@example.com")
    }


    func testLoadRemoteSessionBridgesSignedInSnapshot() async {
        let userId = "44444444-4444-4444-4444-444444444444"
        let probe = SupabaseAuthSessionProbe(
            isConfigured: true,
            reader: ProviderFakeSessionReader(
                session: SupabaseAuthSessionProbe.SessionInfo(userId: userId, email: "remote@example.com")
            ),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: probe,
            sessionBridge: AuthSessionBridge(
                mapper: SupabaseAppUserMapper(now: { Date(timeIntervalSince1970: 1_800_000_100) })
            )
        )

        let session = await provider.loadRemoteSession()

        XCTAssertEqual(session?.sessionState, .signedIn)
        XCTAssertEqual(session?.currentUser?.id, UUID(uuidString: userId))
        XCTAssertEqual(session?.currentUser?.authProvider, .supabase)
        XCTAssertEqual(session?.currentUser?.email, "remote@example.com")
    }

    func testLoadRemoteSessionReturnsNilForSignedOutSnapshot() async {
        let probe = SupabaseAuthSessionProbe(
            isConfigured: true,
            reader: ProviderFakeSessionReader(session: nil),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: probe
        )

        let session = await provider.loadRemoteSession()

        XCTAssertNil(session)
    }

    func testPrepareAppleSignInRequestUsesFutureOAuthStrategy() {
        let provider = SupabaseAuthProvider(configuration: .empty)

        let request = provider.prepareAppleSignInRequest(nonce: "apple-nonce")

        XCTAssertEqual(request.requestedScopes, [.fullName, .email])
        XCTAssertEqual(request.nonce, "apple-nonce")
        XCTAssertEqual(request.redirectStrategy, .supabaseOAuthFuture)
    }

    func testHandleAppleCredentialReturnsSafeErrorWhenUnconfigured() async {
        let provider = SupabaseAuthProvider(configuration: .empty)
        let credential = AppleSignInCredential(
            userIdentifier: "apple-user",
            identityToken: "token",
            authorizationCode: "code",
            nonce: "raw-nonce"
        )

        do {
            _ = try await provider.handleAppleSignInCredential(credential)
            XCTFail("Unconfigured Supabase Apple exchange should fail safely")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHandleAppleCredentialUsesInjectedExchangerAndBridgesSession() async throws {
        let userId = "55555555-5555-5555-5555-555555555555"
        let exchanger = ProviderFakeAppleCredentialExchanger(
            snapshot: SupabaseAuthSessionSnapshot(
                isConfigured: true,
                hasSession: true,
                userId: userId,
                email: "apple@example.com",
                checkedAt: Date(timeIntervalSince1970: 1_800_000_000),
                status: .signedIn
            )
        )
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            appleCredentialExchanger: exchanger
        )
        let credential = AppleSignInCredential(
            userIdentifier: "apple-user",
            identityToken: "apple-id-token",
            authorizationCode: "code",
            nonce: "raw-nonce"
        )

        let session = try await provider.handleAppleSignInCredential(credential)

        XCTAssertEqual(exchanger.idTokens, ["apple-id-token"])
        XCTAssertEqual(exchanger.nonces, ["raw-nonce"])
        XCTAssertEqual(session.currentUser?.id, UUID(uuidString: userId))
        XCTAssertEqual(session.currentUser?.email, "apple@example.com")
        XCTAssertEqual(session.currentUser?.authProvider, .supabase)
    }


    func testHandleAppleCredentialMissingNonceFailsBeforeExchange() async {
        let exchanger = ProviderFakeAppleCredentialExchanger(
            snapshot: SupabaseAuthSessionSnapshot(
                isConfigured: true,
                hasSession: true,
                userId: "55555555-5555-5555-5555-555555555555",
                email: nil,
                checkedAt: Date(),
                status: .signedIn
            )
        )
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            appleCredentialExchanger: exchanger
        )

        do {
            _ = try await provider.handleAppleSignInCredential(
                AppleSignInCredential(
                    userIdentifier: "apple-user",
                    identityToken: "apple-id-token",
                    authorizationCode: "code"
                )
            )
            XCTFail("Missing Apple nonce should fail before Supabase exchange")
        } catch let error as AuthError {
            XCTAssertEqual(error, .appleCredentialMissing)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(exchanger.idTokens.isEmpty)
    }

    func testHandleAppleCredentialEmptyNonceFailsBeforeExchange() async {
        let exchanger = ProviderFakeAppleCredentialExchanger(
            snapshot: SupabaseAuthSessionSnapshot(
                isConfigured: true,
                hasSession: true,
                userId: "55555555-5555-5555-5555-555555555555",
                email: nil,
                checkedAt: Date(),
                status: .signedIn
            )
        )
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            appleCredentialExchanger: exchanger
        )

        do {
            _ = try await provider.handleAppleSignInCredential(
                AppleSignInCredential(
                    userIdentifier: "apple-user",
                    identityToken: "apple-id-token",
                    authorizationCode: "code",
                    nonce: "   "
                )
            )
            XCTFail("Empty Apple nonce should fail before Supabase exchange")
        } catch let error as AuthError {
            XCTAssertEqual(error, .appleCredentialMissing)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(exchanger.idTokens.isEmpty)
    }

    func testHandleAppleCredentialMissingTokenFailsBeforeExchange() async {
        let exchanger = ProviderFakeAppleCredentialExchanger(
            snapshot: SupabaseAuthSessionSnapshot(
                isConfigured: true,
                hasSession: true,
                userId: "55555555-5555-5555-5555-555555555555",
                email: nil,
                checkedAt: Date(),
                status: .signedIn
            )
        )
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            appleCredentialExchanger: exchanger
        )

        do {
            _ = try await provider.handleAppleSignInCredential(AppleSignInCredential(userIdentifier: "apple-user"))
            XCTFail("Missing Apple token should fail before Supabase exchange")
        } catch let error as AuthError {
            XCTAssertEqual(error, .appleCredentialMissing)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(exchanger.idTokens.isEmpty)
    }

}

private final class ProviderFakeAppleCredentialExchanger: SupabaseAppleCredentialExchanging {
    private let snapshot: SupabaseAuthSessionSnapshot
    private let error: Error?
    private(set) var idTokens: [String] = []
    private(set) var nonces: [String?] = []

    init(snapshot: SupabaseAuthSessionSnapshot, error: Error? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    func signInWithApple(idToken: String, nonce: String?) async throws -> SupabaseAuthSessionSnapshot {
        if let error { throw error }
        idTokens.append(idToken)
        nonces.append(nonce)
        return snapshot
    }
}

private final class ProviderFakeSessionReader: SupabaseAuthSessionReading {
    private let session: SupabaseAuthSessionProbe.SessionInfo?

    init(session: SupabaseAuthSessionProbe.SessionInfo?) {
        self.session = session
    }

    func readCurrentSession() async throws -> SupabaseAuthSessionProbe.SessionInfo? {
        session
    }
}

private final class ProviderFakeEmailMagicLinkRequester: SupabaseEmailMagicLinkRequesting {
    private(set) var requests: [EmailAuthRequest] = []
    var error: Error?

    func requestMagicLink(_ request: EmailAuthRequest) async throws {
        if let error { throw error }
        requests.append(request)
    }
}
