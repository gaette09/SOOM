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

    func testConfiguredSignOutUsesInjectedRequester() async throws {
        let requester = ProviderFakeRemoteSignOutRequester()
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            remoteSignOutRequester: requester
        )

        let session = try await provider.signOut()

        XCTAssertEqual(requester.callCount, 1)
        XCTAssertEqual(session.sessionState, .signedOut)
    }

    func testOfflineLogoutCompletesWhenSDKAlreadyRemovedItsSession() async throws {
        let requester = ProviderFakeRemoteSignOutRequester(error: URLError(.notConnectedToInternet))
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(configuration: .init(
                projectURL: URL(string: "https://example.supabase.co"), anonKey: "synthetic-anon-key")),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: ProviderFakeSessionReader(session: nil)),
            remoteSignOutRequester: requester)
        let result = try await provider.signOut()
        XCTAssertEqual(result.sessionState, .signedOut)
        XCTAssertEqual(requester.callCount, 1)
    }

    func testConfiguredSignOutWithoutRequesterFailsSafely() async {
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil)
        )

        do {
            _ = try await provider.signOut()
            XCTFail("Configured provider without a sign-out requester should fail safely")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSignOutFailurePropagatesWithoutSessionMutation() async {
        let requester = ProviderFakeRemoteSignOutRequester(error: AuthError.unknown("계정 연결 해제를 완료하지 못했어요."))
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            remoteSignOutRequester: requester
        )

        do {
            _ = try await provider.signOut()
            XCTFail("Requester failure should propagate")
        } catch let error as AuthError {
            XCTAssertEqual(error, .unknown("계정 연결 해제를 완료하지 못했어요."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(requester.callCount, 1)
    }

    func testAppleRevocationClearsOnlyMatchingSupabaseSession() async {
        let currentID = UUID()
        let cleaner = ProviderFakeRemoteSignOutRequester()
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(configuration: .empty),
            sessionProbe: SupabaseAuthSessionProbe(
                isConfigured: true,
                reader: ProviderFakeSessionReader(session: .init(userId: currentID.uuidString, email: nil))
            ),
            accountDeletionSessionCleaner: cleaner
        )

        await provider.endSessionAfterAppleCredentialRevocation(expectedUserID: UUID())
        XCTAssertEqual(cleaner.callCount, 0)
        await provider.endSessionAfterAppleCredentialRevocation(expectedUserID: currentID)
        XCTAssertEqual(cleaner.callCount, 1)
    }

    func testAppleRevocationCleanupNetworkFailureDoesNotRestoreSDKSession() async {
        let currentID = UUID()
        let cleaner = ProviderFakeRemoteSignOutRequester(error: URLError(.notConnectedToInternet))
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(configuration: .empty),
            sessionProbe: SupabaseAuthSessionProbe(
                isConfigured: true,
                reader: ProviderFakeSessionReader(session: .init(userId: currentID.uuidString, email: nil))
            ),
            accountDeletionSessionCleaner: cleaner
        )

        await provider.endSessionAfterAppleCredentialRevocation(expectedUserID: currentID)

        XCTAssertEqual(cleaner.callCount, 1)
    }

    func testDeletingAccountRejectsCallbackBeforeItCanReplaceSDKSession() async throws {
        let snapshot = SupabaseAuthSessionSnapshot(
            isConfigured: true, hasSession: true, userId: UUID().uuidString,
            email: nil, checkedAt: Date(), status: .signedIn
        )
        let loader = ProviderFakeAuthCallbackSessionLoader(snapshot: snapshot)
        let cleaner = ProviderFakeRemoteSignOutRequester()
        var provider: SupabaseAuthProvider!
        let deleter = ProviderFakeAccountDeleter(onDelete: {
            do {
                _ = try await provider.handleAuthCallback(url: URL(string: "soom://auth/callback")!)
                XCTFail("A callback must not install another SDK session during deletion")
            } catch let error as AuthError {
                XCTAssertEqual(error, .sessionTransitionInProgress)
            }
            XCTAssertTrue(loader.urls.isEmpty)
            XCTAssertEqual(cleaner.callCount, 0)
        })
        provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(configuration: .init(
                projectURL: URL(string: "https://example.supabase.co"), anonKey: "anon-test-key"
            )),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            callbackSessionLoader: loader, accountDeleter: deleter,
            accountDeletionSessionCleaner: cleaner
        )

        try await provider.deleteAccount()

        XCTAssertTrue(loader.urls.isEmpty)
        XCTAssertEqual(cleaner.callCount, 1)
        _ = try await provider.handleAuthCallback(url: URL(string: "soom://auth/callback")!)
        XCTAssertEqual(loader.urls.count, 1, "The mutation gate must release after deletion")
    }

    func testRevocationProtectsExpectedAccountAndTokenCleanupThroughSDKTeardown() async {
        let currentID = UUID()
        let cleaner = ProviderFakeRemoteSignOutRequester()
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(configuration: .empty),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader:
                ProviderFakeSessionReader(session: .init(userId: currentID.uuidString, email: nil))),
            accountDeletionSessionCleaner: cleaner
        )
        var tokenCleanupCount = 0
        let wrongAccountResult = await provider.endSessionAfterAppleCredentialRevocation(
            expectedUserID: UUID(), beforeSignOut: { tokenCleanupCount += 1 }
        )
        XCTAssertFalse(wrongAccountResult)
        XCTAssertEqual(tokenCleanupCount, 0)
        let result = await provider.endSessionAfterAppleCredentialRevocation(
            expectedUserID: currentID,
            beforeSignOut: {
                tokenCleanupCount += 1
                XCTAssertEqual(cleaner.callCount, 0)
                do {
                    _ = try await provider.handleAuthCallback(url: URL(string: "soom://auth/callback")!)
                    XCTFail("Callback must be blocked throughout token cleanup")
                } catch let error as AuthError {
                    XCTAssertEqual(error, .sessionTransitionInProgress)
                } catch { XCTFail("Unexpected error: \(error)") }
            }
        )
        XCTAssertTrue(result)
        XCTAssertEqual(tokenCleanupCount, 1)
        XCTAssertEqual(cleaner.callCount, 1)
    }

    func testProviderDeleteAccountAlsoStaysFutureOnly() async {
        let provider = SupabaseAuthProvider(configuration: .empty)

        do {
            try await provider.deleteAccount()
            XCTFail("Remote account deletion should stay future-only")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConfiguredDeleteAccountClearsSDKSessionAfterDeletion() async throws {
        let deleter = ProviderFakeAccountDeleter()
        let sessionCleaner = ProviderFakeRemoteSignOutRequester(onSignOut: {
            XCTAssertEqual(deleter.callCount, 1, "Session cleanup must follow successful deletion")
        })
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            accountDeleter: deleter,
            accountDeletionSessionCleaner: sessionCleaner
        )

        try await provider.deleteAccount()

        XCTAssertEqual(deleter.callCount, 1)
        XCTAssertEqual(sessionCleaner.callCount, 1)
    }

    func testSuccessfulAccountDeletionStillCommitsWhenSessionCleanupRequestFails() async throws {
        let deleter = ProviderFakeAccountDeleter()
        let sessionCleaner = ProviderFakeRemoteSignOutRequester(error: AuthError.unknown("Offline after deletion"))
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            accountDeleter: deleter,
            accountDeletionSessionCleaner: sessionCleaner
        )

        // Returning success lets AuthViewModel commit local session removal
        // and Settings proceed to erase the user's local data.
        try await provider.deleteAccount()

        XCTAssertEqual(deleter.callCount, 1)
        XCTAssertEqual(sessionCleaner.callCount, 1)
    }

    func testConfiguredDeleteAccountWithoutDeleterFailsSafely() async {
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil)
        )

        do {
            try await provider.deleteAccount()
            XCTFail("Configured provider without an account deleter should fail safely")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeleteAccountFailurePropagatesWithoutClearingSDKSession() async {
        let deleter = ProviderFakeAccountDeleter(error: AuthError.unknown("계정을 삭제하지 못했어요."))
        let sessionCleaner = ProviderFakeRemoteSignOutRequester()
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(
                configuration: SupabaseAuthConfiguration(
                    projectURL: URL(string: "https://example.supabase.co"),
                    anonKey: "anon-test-key"
                )
            ),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            accountDeleter: deleter,
            accountDeletionSessionCleaner: sessionCleaner
        )

        do {
            try await provider.deleteAccount()
            XCTFail("Deleter failure should propagate")
        } catch let error as AuthError {
            XCTAssertEqual(error, .unknown("계정을 삭제하지 못했어요."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(deleter.callCount, 1)
        XCTAssertEqual(sessionCleaner.callCount, 0)
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


    func testHandleAuthCallbackLoadsSessionAndBridges() async throws {
        let callbackURL = URL(string: "soom-dev://auth/callback#access_token=token")!
        let loader = ProviderFakeAuthCallbackSessionLoader(
            snapshot: SupabaseAuthSessionSnapshot(
                isConfigured: true,
                hasSession: true,
                userId: "66666666-6666-6666-6666-666666666666",
                email: "magic@example.com",
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
            callbackSessionLoader: loader
        )

        let session = try await provider.handleAuthCallback(url: callbackURL)

        XCTAssertEqual(loader.urls, [callbackURL])
        XCTAssertEqual(session?.sessionState, .signedIn)
        XCTAssertEqual(session?.currentUser?.id, UUID(uuidString: "66666666-6666-6666-6666-666666666666"))
        XCTAssertEqual(session?.currentUser?.email, "magic@example.com")
        XCTAssertEqual(session?.currentUser?.authProvider, .supabase)
    }

    func testHandleAuthCallbackUnconfiguredReturnsSafeError() async {
        let provider = SupabaseAuthProvider(configuration: .empty)

        do {
            _ = try await provider.handleAuthCallback(url: URL(string: "soom-dev://auth/callback")!)
            XCTFail("Unconfigured Supabase callback should fail safely")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHandleAuthCallbackInvalidSnapshotFallsBackToProbe() async throws {
        let callbackURL = URL(string: "soom-dev://auth/callback#access_token=token")!
        let loader = ProviderFakeAuthCallbackSessionLoader(
            snapshot: SupabaseAuthSessionSnapshot(
                isConfigured: true,
                hasSession: true,
                userId: "not-a-uuid",
                email: "bad@example.com",
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
            callbackSessionLoader: loader
        )

        let session = try await provider.handleAuthCallback(url: callbackURL)

        XCTAssertNil(session)
        XCTAssertEqual(loader.urls, [callbackURL])
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


private final class ProviderFakeAuthCallbackSessionLoader: SupabaseAuthCallbackSessionLoading {
    private let snapshot: SupabaseAuthSessionSnapshot
    private let error: Error?
    private(set) var urls: [URL] = []

    init(snapshot: SupabaseAuthSessionSnapshot, error: Error? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    func loadSession(from url: URL) async throws -> SupabaseAuthSessionSnapshot {
        if let error { throw error }
        urls.append(url)
        return snapshot
    }
}

private final class ProviderFakeRemoteSignOutRequester: SupabaseRemoteSignOutRequesting {
    private let error: Error?
    private let onSignOut: (() -> Void)?
    private(set) var callCount = 0

    init(error: Error? = nil, onSignOut: (() -> Void)? = nil) {
        self.error = error
        self.onSignOut = onSignOut
    }

    func signOut() async throws {
        callCount += 1
        onSignOut?()
        if let error { throw error }
    }
}

private final class ProviderFakeAccountDeleter: SupabaseAccountDeleting {
    private let error: Error?
    private let onDelete: (() async throws -> Void)?
    private(set) var callCount = 0

    init(error: Error? = nil, onDelete: (() async throws -> Void)? = nil) {
        self.error = error
        self.onDelete = onDelete
    }

    func deleteAccount() async throws {
        callCount += 1
        if let error { throw error }
        try await onDelete?()
    }
}


extension SupabaseAuthProviderTests {
    func testExpectedDeletionRejectsReplacementOrMissingSDKSessionBeforeRequest() async {
        let expectedOwner = UUID()
        let replacement = SupabaseAuthSessionProbe.SessionInfo(userId: UUID().uuidString, email: nil)
        for current in [replacement, nil] {
            let deleter = ProviderFakeAccountDeleter()
            let cleaner = ProviderFakeRemoteSignOutRequester()
            let provider = SupabaseAuthProvider(
                clientProvider: SupabaseClientProvider(configuration: .init(
                    projectURL: URL(string: "https://example.supabase.co"), anonKey: "anon-test-key")),
                sessionProbe: SupabaseAuthSessionProbe(isConfigured: true,
                    reader: ProviderFakeSessionReader(session: current)),
                accountDeleter: deleter, accountDeletionSessionCleaner: cleaner
            )

            do {
                try await provider.deleteAccount(expectedUserID: expectedOwner)
                XCTFail("An old confirmation must not delete the currently authenticated replacement")
            } catch { XCTAssertEqual(error as? AuthError, .sessionNotFound) }
            XCTAssertEqual(deleter.callCount, 0)
            XCTAssertEqual(cleaner.callCount, 0)
        }
    }

    func testExpectedDeletionValidatesOwnerAndKeepsSDKMutationGateThroughRequest() async throws {
        let owner = UUID()
        let cleaner = ProviderFakeRemoteSignOutRequester()
        var provider: SupabaseAuthProvider!
        let deleter = ProviderFakeAccountDeleter(onDelete: {
            do {
                _ = try await provider.handleAuthCallback(url: URL(string: "soom://auth/callback")!)
                XCTFail("The validated account must remain fixed through the deletion request")
            } catch { XCTAssertEqual(error as? AuthError, .sessionTransitionInProgress) }
        })
        provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(configuration: .init(
                projectURL: URL(string: "https://example.supabase.co"), anonKey: "anon-test-key")),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true,
                reader: ProviderFakeSessionReader(session: .init(userId: owner.uuidString, email: nil))),
            accountDeleter: deleter, accountDeletionSessionCleaner: cleaner
        )

        try await provider.deleteAccount(expectedUserID: owner)

        XCTAssertEqual(deleter.callCount, 1)
        XCTAssertEqual(cleaner.callCount, 1)
    }
}

extension SupabaseAuthProviderTests {
    @MainActor
    func testAppleGrantRegistrarReceivesVerifiedSessionOwnerAndCredentialThenMarksRegistered() async throws {
        let owner = UUID()
        let state = AppleGrantRegistrationState.shared
        defer { state.clear(owner) }
        state.set(.needsRetry, for: owner)
        let registrar = ProviderFakeAppleGrantRegistrar()
        let credential = syntheticGrantCredential
        let provider = grantProvider(snapshot: grantSnapshot(owner), registrar: registrar)

        let result = try await provider.signInWithAppleCredential(credential)

        XCTAssertTrue(result.isSignedIn)
        XCTAssertEqual(result.currentUser?.authProvider, .supabase)
        XCTAssertEqual(result.currentUser?.id, owner)
        XCTAssertEqual(registrar.owners, [owner])
        XCTAssertEqual(registrar.credentials, [credential])
        XCTAssertEqual(state.status(for: owner), .registered)
    }

    @MainActor
    func testAppleGrantRegistrationFailureKeepsLoginAndMarksOnlyItsOwnerForRetry() async throws {
        let owner = UUID(), other = UUID()
        let state = AppleGrantRegistrationState.shared
        defer { state.clear(owner); state.clear(other) }
        state.set(.registered, for: other)
        let registrar = ProviderFakeAppleGrantRegistrar(error: URLError(.notConnectedToInternet))
        let provider = grantProvider(snapshot: grantSnapshot(owner), registrar: registrar)

        let result = try await provider.signInWithAppleCredential(syntheticGrantCredential)

        XCTAssertTrue(result.isSignedIn)
        XCTAssertEqual(result.currentUser?.id, owner)
        XCTAssertEqual(registrar.owners, [owner])
        XCTAssertEqual(state.status(for: owner), .needsRetry)
        XCTAssertEqual(state.status(for: other), .registered)
    }

    @MainActor
    func testFailedAppleExchangeNeverRegistersGrantOrChangesReadiness() async {
        let owner = UUID()
        let state = AppleGrantRegistrationState.shared
        defer { state.clear(owner) }
        let registrar = ProviderFakeAppleGrantRegistrar()
        let failure = AuthError.unknown("Synthetic exchange failure")
        let provider = grantProvider(snapshot: grantSnapshot(owner), registrar: registrar, exchangeError: failure)

        do {
            _ = try await provider.signInWithAppleCredential(syntheticGrantCredential)
            XCTFail("A failed exchange must not produce a logged-in session")
        } catch { XCTAssertEqual(error as? AuthError, failure) }

        XCTAssertTrue(registrar.owners.isEmpty)
        XCTAssertTrue(registrar.credentials.isEmpty)
        XCTAssertNil(state.status(for: owner))
    }

    @MainActor
    func testInvalidExchangedSessionsNeverReachAppleGrantRegistrar() async {
        let owner = UUID()
        let state = AppleGrantRegistrationState.shared
        defer { state.clear(owner) }
        let snapshots: [SupabaseAuthSessionSnapshot] = [
            .init(isConfigured: true, hasSession: false, userId: owner.uuidString, email: nil, checkedAt: Date(), status: .signedIn),
            .init(isConfigured: true, hasSession: true, userId: owner.uuidString, email: nil, checkedAt: Date(), status: .signedOut),
            .init(isConfigured: true, hasSession: true, userId: owner.uuidString, email: nil, checkedAt: Date(), status: .failed),
            .init(isConfigured: true, hasSession: true, userId: "synthetic-invalid-uuid", email: nil, checkedAt: Date(), status: .signedIn)
        ]
        for snapshot in snapshots {
            let registrar = ProviderFakeAppleGrantRegistrar()
            let provider = grantProvider(snapshot: snapshot, registrar: registrar)
            do {
                _ = try await provider.signInWithAppleCredential(syntheticGrantCredential)
                XCTFail("An invalid exchanged session must not authorize grant registration")
            } catch { XCTAssertEqual(error as? AuthError, .sessionNotFound) }
            XCTAssertTrue(registrar.owners.isEmpty)
            XCTAssertTrue(registrar.credentials.isEmpty)
        }
        XCTAssertNil(state.status(for: owner))
    }

    @MainActor
    func testInvalidAppleCredentialNeverReachesExchangeOrGrantRegistration() async {
        let owner = UUID()
        let state = AppleGrantRegistrationState.shared
        defer { state.clear(owner) }
        let exchanger = ProviderFakeAppleCredentialExchanger(snapshot: grantSnapshot(owner))
        let registrar = ProviderFakeAppleGrantRegistrar()
        let provider = SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(configuration: .init(
                projectURL: URL(string: "https://example.supabase.co"), anonKey: "synthetic-anon-key")),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            appleCredentialExchanger: exchanger, appleGrantRegistrar: registrar)
        do {
            _ = try await provider.signInWithAppleCredential(
                AppleSignInCredential(userIdentifier: "synthetic-apple-subject", identityToken: "synthetic-token", authorizationCode: "synthetic-code"))
            XCTFail("Missing nonce must fail before either remote dependency")
        } catch { XCTAssertEqual(error as? AuthError, .appleCredentialMissing) }
        XCTAssertTrue(exchanger.idTokens.isEmpty)
        XCTAssertTrue(registrar.owners.isEmpty)
        XCTAssertNil(state.status(for: owner))
    }

    private var syntheticGrantCredential: AppleSignInCredential {
        AppleSignInCredential(userIdentifier: "synthetic-apple-subject", identityToken: "synthetic-identity-token",
            authorizationCode: "synthetic-single-use-code", email: "fixture@example.test", fullName: "Synthetic User",
            nonce: "synthetic-raw-nonce", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func grantSnapshot(_ owner: UUID) -> SupabaseAuthSessionSnapshot {
        .init(isConfigured: true, hasSession: true, userId: owner.uuidString, email: "fixture@example.test",
            checkedAt: Date(timeIntervalSince1970: 1_800_000_000), status: .signedIn,
            appleUserIdentifier: "synthetic-apple-subject", linkedAuthProviders: ["apple"])
    }

    private func grantProvider(snapshot: SupabaseAuthSessionSnapshot, registrar: ProviderFakeAppleGrantRegistrar,
                               exchangeError: Error? = nil) -> SupabaseAuthProvider {
        SupabaseAuthProvider(
            clientProvider: SupabaseClientProvider(configuration: .init(
                projectURL: URL(string: "https://example.supabase.co"), anonKey: "synthetic-anon-key")),
            sessionProbe: SupabaseAuthSessionProbe(isConfigured: true, reader: nil),
            appleCredentialExchanger: ProviderFakeAppleCredentialExchanger(snapshot: snapshot, error: exchangeError),
            appleGrantRegistrar: registrar)
    }
}

private final class ProviderFakeAppleGrantRegistrar: AppleGrantRegistering {
    private let error: Error?
    private(set) var owners: [UUID] = []
    private(set) var credentials: [AppleSignInCredential] = []
    init(error: Error? = nil) { self.error = error }
    func register(credential: AppleSignInCredential, expectedUserID: UUID) async throws {
        owners.append(expectedUserID)
        credentials.append(credential)
        if let error { throw error }
    }
}
