import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class AuthViewModelTests: XCTestCase {
    func testLoadPublishesStoredLocalSession() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "로컬 사용자")
        let viewModel = AuthViewModel(store: store)

        viewModel.load()

        XCTAssertEqual(viewModel.session.currentUser?.displayName, "로컬 사용자")
        XCTAssertTrue(viewModel.session.isLocalOnly)
    }

    func testRepositoryBasedInitLoadsStoredLocalSession() {
        let store = makeStore()
        let repository = LocalAuthRepository(store: store)
        _ = repository.continueAsLocalUser(displayName: "Repository User")

        let viewModel = AuthViewModel(repository: repository)

        XCTAssertEqual(viewModel.session.currentUser?.displayName, "Repository User")
        XCTAssertTrue(viewModel.session.isLocalOnly)
    }

    func testContinueAsLocalUserCreatesSession() {
        let viewModel = AuthViewModel(store: makeStore())
        viewModel.displayNameText = "지완"

        viewModel.continueAsLocalUser()

        XCTAssertEqual(viewModel.session.currentUser?.displayName, "지완")
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUpdateDisplayNamePublishesUpdatedUser() async {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "이전 이름")
        let viewModel = AuthViewModel(store: store)
        viewModel.displayNameText = "새 이름"

        await viewModel.updateDisplayName()

        XCTAssertEqual(viewModel.session.currentUser?.displayName, "새 이름")
        XCTAssertEqual(viewModel.displayNameText, "새 이름")
    }

    func testInvalidDisplayNamePublishesError() async {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "SOOM 사용자")
        let viewModel = AuthViewModel(store: store)
        viewModel.displayNameText = "  "

        await viewModel.updateDisplayName()

        XCTAssertEqual(viewModel.session.sessionState, .error)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSignOutClearsSessionAndDisplayName() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "SOOM 사용자")
        let viewModel = AuthViewModel(store: store)

        viewModel.signOut()

        XCTAssertEqual(viewModel.session.sessionState, .signedOut)
        XCTAssertTrue(viewModel.displayNameText.isEmpty)
    }


    func testCheckRemoteSessionPromotesSignedInRemoteSessionWithoutDeletingLocalStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: .signedIn(user: remoteUser))
        )

        await viewModel.checkRemoteSession()

        XCTAssertEqual(viewModel.session.sessionState, .signedIn)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.session.currentUser?.email, "remote@example.com")
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testCheckRemoteSessionRunsOnMainActorAndPromotesRemoteSessionSafely() async {
        XCTAssertTrue(Thread.isMainThread)
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: .signedIn(user: remoteUser))
        )

        await viewModel.checkRemoteSession()

        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
    }

    func testCheckRemoteSessionFailureKeepsLocalSession() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: nil)
        )

        await viewModel.checkRemoteSession()

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }


    func testInitializeSessionRestoresRemoteSessionWhenAvailableWithoutMutatingLocalStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: .signedIn(user: remoteUser))
        )

        await viewModel.initializeSession()

        XCTAssertEqual(viewModel.session.sessionState, .signedIn)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.displayNameText, "remote")
        XCTAssertFalse(viewModel.isCheckingRemoteSession)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testInitializeSessionKeepsLocalWhenRemoteIsMissing() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: nil)
        )

        await viewModel.initializeSession()

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertFalse(viewModel.isCheckingRemoteSession)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }

    func testInitializeSessionWithLocalFirstPolicyDoesNotPromoteRemote() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: .signedIn(user: remoteUser)),
            restorePolicy: .localFirst
        )

        await viewModel.initializeSession()

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertFalse(viewModel.isCheckingRemoteSession)
    }

    func testDuplicateInitializeSessionCallsShareActiveRestoreTask() async {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "10101010-1010-1010-1010-101010101010")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let loader = CountingRemoteSessionLoader(session: .signedIn(user: remoteUser))
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: loader
        )

        async let first: Void = viewModel.initializeSession()
        async let second: Void = viewModel.initializeSession()
        _ = await (first, second)

        XCTAssertEqual(loader.loadCount, 1)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertFalse(viewModel.isCheckingRemoteSession)
    }

    func testAppleSignInSuccessPromotesRemoteSessionWithoutDeletingLocalStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            displayName: "apple",
            email: "apple@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            appleSignInHandler: { credential in
                XCTAssertEqual(credential.identityToken, "token")
                return .signedIn(user: remoteUser)
            }
        )

        await viewModel.signInWithAppleCredential(
            AppleSignInCredential(
                userIdentifier: "apple-user",
                identityToken: "token",
                authorizationCode: "code",
                nonce: "raw-nonce"
            )
        )

        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.session.currentUser?.email, "apple@example.com")
        XCTAssertFalse(viewModel.isAppleSignInInProgress)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testAppleSignInFailureKeepsLocalSession() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            appleSignInHandler: { _ in throw AuthError.appleCredentialMissing }
        )

        await viewModel.signInWithAppleCredential(
            AppleSignInCredential(userIdentifier: "apple-user")
        )

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertEqual(viewModel.errorMessage, AuthError.appleCredentialMissing.userMessage)
        XCTAssertFalse(viewModel.isAppleSignInInProgress)
    }

    func testSessionBridgedCallbackResultAppliesSignedInSessionWithoutMutatingLocalStore() {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            displayName: "magic",
            email: "magic@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(repository: LocalAuthRepository(store: store))

        viewModel.handleAuthCallbackResult(.sessionBridged(.signedIn(user: remoteUser)))

        XCTAssertEqual(viewModel.session.sessionState, .signedIn)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.session.currentUser?.email, "magic@example.com")
        XCTAssertEqual(viewModel.displayNameText, "magic")
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testIgnoredCallbackResultKeepsLocalSession() {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(repository: LocalAuthRepository(store: store))

        viewModel.handleAuthCallbackResult(.ignored)

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }

    func testFailedCallbackResultKeepsLocalSessionAndPublishesSoftError() {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(repository: LocalAuthRepository(store: store))

        viewModel.handleAuthCallbackResult(.failed("계정 연결 callback을 확인하지 못했어요."))

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertEqual(viewModel.errorMessage, "계정 연결 callback을 확인하지 못했어요.")
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }

    func testDisconnectRemoteAccountRestoresLocalFallbackWithoutDeletingStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        var signOutCallCount = 0
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSignOutHandler: {
                signOutCallCount += 1
                return .signedOut
            }
        )
        viewModel.applyRemoteSession(.signedIn(user: remoteUser))

        await viewModel.disconnectRemoteAccount()

        XCTAssertEqual(signOutCallCount, 1)
        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertEqual(viewModel.displayNameText, "Local User")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testDisconnectRemoteAccountCreatesLocalFallbackWhenNoLocalUserExists() async {
        let store = makeStore()
        let remoteUser = AppUser(
            id: UUID(uuidString: "14141414-1414-1414-1414-141414141414")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSignOutHandler: { .signedOut }
        )
        viewModel.applyRemoteSession(.signedIn(user: remoteUser))

        await viewModel.disconnectRemoteAccount()

        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertEqual(viewModel.session.currentUser?.displayName, "SOOM 사용자")
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .local)
        XCTAssertEqual(store.loadSession().currentUser?.id, viewModel.session.currentUser?.id)
    }

    func testDisconnectRemoteAccountFailureKeepsRemoteSessionAndPublishesSoftError() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "15151515-1515-1515-1515-151515151515")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSignOutHandler: {
                throw AuthError.unknown("계정 연결 해제를 완료하지 못했어요.")
            }
        )
        viewModel.applyRemoteSession(.signedIn(user: remoteUser))

        await viewModel.disconnectRemoteAccount()

        XCTAssertEqual(viewModel.session.currentUser?.id, remoteUser.id)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.errorMessage, "계정 연결 해제를 완료하지 못했어요.")
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testDeleteAccountForGuestUserClearsLocalSessionWithoutRemoteCall() async {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "게스트")
        var remoteDeleteCallCount = 0
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteAccountDeleteHandler: {
                remoteDeleteCallCount += 1
            }
        )

        let committed = await viewModel.deleteAccount()

        XCTAssertTrue(committed)
        XCTAssertEqual(remoteDeleteCallCount, 0)
        XCTAssertEqual(viewModel.session.sessionState, .signedOut)
        XCTAssertTrue(viewModel.displayNameText.isEmpty)
        XCTAssertEqual(store.loadSession().sessionState, .signedOut)
    }

    func testDeleteAccountForSupabaseUserCallsRemoteHandlerThenClearsSession() async {
        let store = makeStore()
        let remoteUser = AppUser(
            id: UUID(uuidString: "16161616-1616-1616-1616-161616161616")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        var remoteDeleteCallCount = 0
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteAccountDeleteHandler: {
                remoteDeleteCallCount += 1
            }
        )
        viewModel.applyRemoteSession(.signedIn(user: remoteUser))

        let committed = await viewModel.deleteAccount()

        XCTAssertTrue(committed)
        XCTAssertEqual(remoteDeleteCallCount, 1)
        XCTAssertEqual(viewModel.session.sessionState, .signedOut)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(store.loadSession().sessionState, .signedOut)
    }

    func testDeleteAccountForSupabaseUserFailurePreservesSessionAndPublishesError() async {
        let store = makeStore()
        let remoteUser = AppUser(
            id: UUID(uuidString: "17171717-1717-1717-1717-171717171717")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteAccountDeleteHandler: {
                throw AuthError.unknown("계정을 삭제하지 못했어요.")
            }
        )
        viewModel.applyRemoteSession(.signedIn(user: remoteUser))

        let committed = await viewModel.deleteAccount()

        XCTAssertFalse(committed)
        XCTAssertEqual(viewModel.session.currentUser?.id, remoteUser.id)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.errorMessage, "계정을 삭제하지 못했어요.")
    }

    func testDeleteAccountForSupabaseUserWithoutHandlerFailsSafely() async {
        let store = makeStore()
        let remoteUser = AppUser(
            id: UUID(uuidString: "18181818-1818-1818-1818-181818181818")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(repository: LocalAuthRepository(store: store))
        viewModel.applyRemoteSession(.signedIn(user: remoteUser))

        let committed = await viewModel.deleteAccount()

        XCTAssertFalse(committed)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.errorMessage, AuthError.futureRemoteAuthNotConfigured.userMessage)
    }

    func testViewModelDoesNotUseRecoveryCalculator() {
        let viewModel = AuthViewModel(store: makeStore())
        viewModel.continueAsLocalUser()

        XCTAssertTrue(viewModel.session.isLocalOnly)
    }

    func testConfirmedAppleRevocationEndsOnlineSessionAndPreservesLocalWorkout() async throws {
        for state in [AppleCredentialState.revoked, .notFound] {
            let store = makeStore()
            let localSession = store.continueAsLocalUser(displayName: "Local User")
            let appleUser = makeAppleUser()
            let schema = Schema([UnifiedWorkoutRecord.self])
            let container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration("AppleRevocationTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
            ])
            let context = container.mainContext
            let workout = UnifiedWorkoutRecord(
                sourceRaw: "soomLocal", workoutTypeRaw: "running",
                startDate: Date(timeIntervalSince1970: 1_800_000_000),
                endDate: Date(timeIntervalSince1970: 1_800_000_060),
                durationSeconds: 60, dataQualityRaw: "partial"
            )
            context.insert(workout)
            try context.save()
            var cleanedUserIDs: [UUID] = []
            let viewModel = AuthViewModel(
                repository: LocalAuthRepository(store: store),
                appleCredentialStateReader: { subject in
                    XCTAssertEqual(subject, "apple-subject")
                    return state
                },
                appleCredentialRevocationHandler: { cleanedUserIDs.append($0); return true }
            )
            viewModel.applyRemoteSession(.signedIn(user: appleUser))

            await viewModel.refreshAppleCredentialState()

            XCTAssertEqual(cleanedUserIDs, [appleUser.id])
            XCTAssertTrue(viewModel.session.isLocalOnly)
            XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
            XCTAssertFalse(viewModel.isAppleSignInInProgress)
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 1)
        }
    }

    func testAuthorizedTransferredAndUnknownAppleStatesKeepRemoteSession() async {
        for state in [AppleCredentialState.authorized, .transferred, .unknown] {
            let appleUser = makeAppleUser()
            var cleanupCount = 0
            let viewModel = AuthViewModel(
                repository: LocalAuthRepository(store: makeStore()),
                appleCredentialStateReader: { _ in state },
                appleCredentialRevocationHandler: { _ in cleanupCount += 1; return true }
            )
            viewModel.applyRemoteSession(.signedIn(user: appleUser))

            await viewModel.refreshAppleCredentialState()

            XCTAssertEqual(cleanupCount, 0)
            XCTAssertEqual(viewModel.session.currentUser?.id, appleUser.id)
            XCTAssertTrue(viewModel.session.isSignedIn)
        }
    }

    func testAppleCredentialLookupErrorsKeepRemoteSession() async {
        let appleUser = makeAppleUser()
        var cleanupCount = 0
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: makeStore()),
            appleCredentialStateReader: { _ in throw URLError(.notConnectedToInternet) },
            appleCredentialRevocationHandler: { _ in cleanupCount += 1; return true }
        )
        viewModel.applyRemoteSession(.signedIn(user: appleUser))

        await viewModel.refreshAppleCredentialState()

        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(viewModel.session.currentUser?.id, appleUser.id)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testOldRevocationResponseCannotSignOutReplacementAccount() async {
        let suspendedRead = SuspendedAppleCredentialRead(started: expectation(description: "Apple check started"))
        var cleanupCount = 0
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: makeStore()),
            appleCredentialStateReader: suspendedRead.read,
            appleCredentialRevocationHandler: { _ in cleanupCount += 1; return true }
        )
        viewModel.applyRemoteSession(.signedIn(user: makeAppleUser()))
        let check = Task { await viewModel.refreshAppleCredentialState() }
        await fulfillment(of: [suspendedRead.started], timeout: 1)
        let replacement = AppUser(displayName: "Other account", authProvider: .supabase)
        viewModel.applyRemoteSession(.signedIn(user: replacement))
        suspendedRead.resume(.revoked)
        await check.value

        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(viewModel.session.currentUser?.id, replacement.id)
        XCTAssertTrue(viewModel.session.isSignedIn)
    }

    func testOldRevocationResponseCannotSignOutNewSessionForSameAppleUser() async {
        let suspendedRead = SuspendedAppleCredentialRead(started: expectation(description: "Apple check started"))
        var cleanupCount = 0
        let user = makeAppleUser()
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: makeStore()),
            appleCredentialStateReader: suspendedRead.read,
            appleCredentialRevocationHandler: { _ in cleanupCount += 1; return true }
        )
        viewModel.applyRemoteSession(.signedIn(user: user))
        let check = Task { await viewModel.refreshAppleCredentialState() }
        await fulfillment(of: [suspendedRead.started], timeout: 1)
        viewModel.applyRemoteSession(.signedIn(user: user))
        suspendedRead.resume(.revoked)
        await check.value

        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(viewModel.session.currentUser?.id, user.id)
        XCTAssertTrue(viewModel.session.isSignedIn)
    }

    func testAppleLinkedMetadataWithoutSubjectSupportsGuidanceButSkipsCredentialLookup() async {
        var lookupCount = 0
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: makeStore()),
            appleCredentialStateReader: { _ in lookupCount += 1; return .revoked },
            appleCredentialRevocationHandler: { _ in XCTFail("Missing Apple subject must not clear a session"); return false }
        )
        viewModel.applyRemoteSession(.signedIn(user: AppUser(
            displayName: "Linked account", authProvider: .supabase, linkedAuthProviders: ["apple", "email"]
        )))

        XCTAssertTrue(viewModel.isCurrentAccountLinkedToApple)
        await viewModel.refreshAppleCredentialState()

        XCTAssertEqual(lookupCount, 0)
        XCTAssertTrue(viewModel.session.isSignedIn)
    }

    func testEmailOnlyAccountDoesNotTriggerAppleCredentialLookup() async {
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: makeStore()),
            appleCredentialStateReader: { _ in XCTFail("Email-only account must not query Apple"); return .revoked },
            appleCredentialRevocationHandler: { _ in XCTFail("Email-only account must not be disconnected"); return false }
        )
        viewModel.applyRemoteSession(.signedIn(user: AppUser(displayName: "Email account", authProvider: .supabase)))

        await viewModel.refreshAppleCredentialState()

        XCTAssertFalse(viewModel.isCurrentAccountLinkedToApple)
        XCTAssertTrue(viewModel.session.isSignedIn)
    }

    func testLateAccountDeletionCannotSignOutOrAuthorizeWipeForReplacementSession() async {
        for usesSameUser in [false, true] {
            let deletion = SuspendedAccountDeletion(started: expectation(description: "Deletion started"))
            let user = makeAppleUser()
            let viewModel = AuthViewModel(
                repository: LocalAuthRepository(store: makeStore()),
                remoteAccountDeleteHandler: deletion.delete
            )
            viewModel.applyRemoteSession(.signedIn(user: user))
            let task = Task { await viewModel.deleteAccount() }
            await fulfillment(of: [deletion.started], timeout: 1)
            let replacement = usesSameUser ? user : AppUser(displayName: "Replacement", authProvider: .supabase)
            viewModel.applyRemoteSession(.signedIn(user: replacement))
            deletion.complete()

            let shouldWipeLocalData = await task.value

            XCTAssertFalse(shouldWipeLocalData)
            XCTAssertEqual(viewModel.session.currentUser?.id, replacement.id)
            XCTAssertTrue(viewModel.session.isSignedIn)
            XCTAssertNil(viewModel.errorMessage)
        }
    }

    func testDeferredAppleRevocationCleanupKeepsViewAndSDKSessionAligned() async {
        let user = makeAppleUser()
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: makeStore()),
            appleCredentialStateReader: { _ in .revoked },
            appleCredentialRevocationHandler: { _ in false }
        )
        viewModel.applyRemoteSession(.signedIn(user: user))
        await viewModel.refreshAppleCredentialState()
        XCTAssertEqual(viewModel.session.currentUser?.id, user.id)
        XCTAssertTrue(viewModel.session.isSignedIn)
        XCTAssertFalse(viewModel.isRemoteSessionTransitionInProgress)
    }

    func testSuccessfulDeletionKeepsAuthenticationClosedUntilLocalCleanupFinishes() async {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "Guest")
        let viewModel = AuthViewModel(store: store)
        let shouldErase = await viewModel.deleteAccount()
        XCTAssertTrue(shouldErase)
        XCTAssertTrue(viewModel.isAccountDeletionInProgress)
        viewModel.continueAsLocalUser()
        XCTAssertNil(viewModel.session.currentUser)
        viewModel.finishAccountDeletion()
        viewModel.continueAsLocalUser()
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertFalse(viewModel.isRemoteSessionTransitionInProgress)
    }

    func testLocalActionsCannotDivergeFromAnInFlightAppleSDKExchange() async {
        let user = makeAppleUser()
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Guest")
        var viewModel: AuthViewModel!
        viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            appleSignInHandler: { _ in
                viewModel.signOut()
                viewModel.continueAsLocalUser()
                viewModel.load()
                XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
                return .signedIn(user: user)
            }
        )
        await viewModel.signInWithAppleCredential(.init(userIdentifier: "apple-subject"))
        XCTAssertEqual(viewModel.session.currentUser?.id, user.id)
        XCTAssertTrue(viewModel.session.isSignedIn)
    }

    private func makeAppleUser() -> AppUser {
        AppUser(displayName: "Apple account", authProvider: .supabase, appleUserIdentifier: "apple-subject", linkedAuthProviders: ["apple"])
    }

    func testRemoteDisplayNameSaveUpdatesRemoteSessionWithoutReplacingGuestIdentity() async {
        let store = makeStore()
        let guest = store.continueAsLocalUser(displayName: "Guest")
        let remoteUser = AppUser(displayName: "Remote", authProvider: .supabase)
        var capturedID: UUID?
        let subject = AuthViewModel(repository: LocalAuthRepository(store: store),
            remoteDisplayNameHandler: { userID, name in capturedID = userID; return name })
        subject.applyRemoteSession(.signedIn(user: remoteUser))
        subject.displayNameText = "  Saved remote name  "
        await subject.updateDisplayName()
        XCTAssertEqual(capturedID, remoteUser.id)
        XCTAssertEqual(subject.session.currentUser?.id, remoteUser.id)
        XCTAssertEqual(subject.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(subject.session.currentUser?.displayName, "Saved remote name")
        XCTAssertEqual(store.loadSession(), guest)
    }

    func testRemoteDisplayNameFailureRetainsAccountAndEditableInput() async {
        let store = makeStore()
        let user = AppUser(displayName: "Remote", authProvider: .supabase)
        let subject = AuthViewModel(repository: LocalAuthRepository(store: store),
            remoteDisplayNameHandler: { _, _ in throw URLError(.notConnectedToInternet) })
        subject.applyRemoteSession(.signedIn(user: user))
        subject.displayNameText = "Pending name"
        await subject.updateDisplayName()
        XCTAssertEqual(subject.session.currentUser, user)
        XCTAssertEqual(subject.displayNameText, "Pending name")
        XCTAssertNotNil(subject.errorMessage)
        XCTAssertNil(store.loadSession().currentUser)
    }

    func testLateRemoteNameResultCannotRenameReplacementAccount() async {
        let started = expectation(description: "name update started")
        var continuation: CheckedContinuation<String, Error>?
        let subject = AuthViewModel(repository: LocalAuthRepository(store: makeStore()),
            remoteDisplayNameHandler: { _, _ in
                try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
            })
        subject.applyRemoteSession(.signedIn(user: AppUser(displayName: "A", authProvider: .supabase)))
        subject.displayNameText = "Old account edit"
        let task = Task { await subject.updateDisplayName() }
        await fulfillment(of: [started], timeout: 2)
        let replacement = AppUser(displayName: "B", authProvider: .supabase)
        subject.applyRemoteSession(.signedIn(user: replacement))
        continuation?.resume(returning: "Old account edit")
        await task.value
        XCTAssertEqual(subject.session.currentUser, replacement)
    }

    func testSDKSessionTerminationRestoresGuestAndIgnoresStaleAccountEvents() {
        let store = makeStore()
        let guest = store.continueAsLocalUser(displayName: "Guest")
        let subject = AuthViewModel(store: store)
        let user = AppUser(displayName: "Remote", authProvider: .supabase)
        subject.applyRemoteSession(.signedIn(user: user))
        subject.remoteSessionDidEnd(expectedUserID: UUID())
        XCTAssertEqual(subject.session.currentUser, user)
        subject.remoteSessionDidEnd(expectedUserID: user.id)
        XCTAssertEqual(subject.session.currentUser, guest.currentUser)
        XCTAssertTrue(subject.session.isLocalOnly)
    }

    private func makeStore() -> AuthSessionStore {
        let suiteName = "AuthViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AuthSessionStore(userDefaults: defaults, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }
}


private struct FakeRemoteSessionLoader: RemoteAuthSessionLoading {
    let session: AuthSession?

    func loadRemoteSession() async -> AuthSession? {
        session
    }
}

private final class CountingRemoteSessionLoader: RemoteAuthSessionLoading {
    private(set) var loadCount = 0
    let session: AuthSession?

    init(session: AuthSession?) {
        self.session = session
    }

    func loadRemoteSession() async -> AuthSession? {
        loadCount += 1
        try? await Task.sleep(nanoseconds: 10_000_000)
        return session
    }
}

@MainActor
private final class SuspendedAppleCredentialRead {
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<AppleCredentialState, Error>?

    init(started: XCTestExpectation) { self.started = started }

    func read(_ subject: String) async throws -> AppleCredentialState {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func resume(_ state: AppleCredentialState) {
        continuation?.resume(returning: state)
        continuation = nil
    }
}

@MainActor
private final class SuspendedAccountDeletion {
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Error>?

    init(started: XCTestExpectation) { self.started = started }

    func delete() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func complete() {
        continuation?.resume()
        continuation = nil
    }
}


extension AuthViewModelTests {
    func testQueuedDeletionRejectsGuestToRemoteAccountSwitchAndSameAccountRelogin() async {
        for scenario in 0..<3 {
            let store = makeStore()
            let guest = store.continueAsLocalUser(displayName: "Guest")
            var remoteCalls: [UUID] = []
            let viewModel = AuthViewModel(
                repository: LocalAuthRepository(store: store),
                remoteAccountDeleteForUserHandler: { remoteCalls.append($0) }
            )
            let originalRemote = AppUser(displayName: "Original", authProvider: .supabase)
            if scenario != 0 { viewModel.applyRemoteSession(.signedIn(user: originalRemote)) }
            let confirmedTarget = viewModel.accountDeletionTarget
            // The confirmation has already queued its Task. A session change
            // on the same actor happens before that Task begins executing.
            let deletion = Task { await viewModel.deleteAccount(expectedTarget: confirmedTarget) }
            let replacement: AppUser
            if scenario == 0 {
                replacement = AppUser(id: guest.currentUser!.id, displayName: "New remote", authProvider: .supabase)
            } else if scenario == 1 {
                replacement = AppUser(displayName: "Different account", authProvider: .supabase)
            } else {
                replacement = originalRemote
            }
            viewModel.applyRemoteSession(.signedIn(user: replacement))

            let shouldErase = await deletion.value

            XCTAssertFalse(shouldErase)
            XCTAssertTrue(remoteCalls.isEmpty)
            XCTAssertEqual(viewModel.session.currentUser?.id, replacement.id)
            XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
            XCTAssertFalse(viewModel.isAccountDeletionInProgress)
            XCTAssertNotNil(viewModel.errorMessage)
        }
    }

    func testConfirmedDeletionPassesOriginalOwnerToScopedRemoteHandler() async {
        var receivedOwners: [UUID] = []
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: makeStore()),
            remoteAccountDeleteHandler: { XCTFail("The live scoped handler must take precedence") },
            remoteAccountDeleteForUserHandler: { receivedOwners.append($0) }
        )
        let owner = AppUser(displayName: "Owner", authProvider: .supabase)
        viewModel.applyRemoteSession(.signedIn(user: owner))
        let target = viewModel.accountDeletionTarget

        let shouldErase = await viewModel.deleteAccount(expectedTarget: target)

        XCTAssertTrue(shouldErase)
        XCTAssertEqual(receivedOwners, [owner.id])
        XCTAssertNil(viewModel.session.currentUser)
        XCTAssertTrue(viewModel.isAccountDeletionInProgress)
        viewModel.finishAccountDeletion()
    }
}
