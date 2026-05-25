import XCTest
@testable import SOOM

final class AuthRepositoryTests: XCTestCase {
    func testLocalAuthRepositoryCreatesAndLoadsLocalUser() {
        let repository = makeRepository()

        let created = repository.continueAsLocalUser(displayName: "지완")
        let loaded = repository.loadSession()

        XCTAssertEqual(created.currentUser?.displayName, "지완")
        XCTAssertEqual(loaded.currentUser, created.currentUser)
        XCTAssertTrue(loaded.isLocalOnly)
    }

    func testLocalAuthRepositoryUpdatesDisplayName() {
        let repository = makeRepository()
        _ = repository.continueAsLocalUser(displayName: "이전 이름")

        let updated = repository.updateDisplayName("새 이름")

        XCTAssertEqual(updated.currentUser?.displayName, "새 이름")
        XCTAssertEqual(repository.loadSession().currentUser?.displayName, "새 이름")
    }

    func testLocalAuthRepositorySignOutClearsSession() {
        let repository = makeRepository()
        _ = repository.continueAsLocalUser(displayName: "SOOM 사용자")

        let signedOut = repository.signOut()

        XCTAssertEqual(signedOut.sessionState, .signedOut)
        XCTAssertNil(repository.loadSession().currentUser)
    }

    func testFutureAppleSignInReturnsUnsupportedProvider() async {
        let repository = makeRepository()

        do {
            _ = try await repository.signInWithApple()
            XCTFail("Apple sign in should stay unsupported in preparation v1")
        } catch let error as AuthError {
            XCTAssertEqual(error, .unsupportedProvider(.apple))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFutureGoogleSignInReturnsUnsupportedProvider() async {
        let repository = makeRepository()

        do {
            _ = try await repository.signInWithGoogle()
            XCTFail("Google sign in should stay unsupported in preparation v1")
        } catch let error as AuthError {
            XCTAssertEqual(error, .unsupportedProvider(.google))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFutureSupabaseEmailSignInReturnsNotConfigured() async {
        let repository = makeRepository()

        do {
            _ = try await repository.signInWithSupabaseEmail(email: "user@example.com")
            XCTFail("Supabase email sign in should stay unconfigured in preparation v1")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLocalRepositoryEmailMagicLinkRequestStaysUnsupported() async {
        let repository = makeRepository()

        do {
            _ = try await repository.requestEmailMagicLink(email: "user@example.com", redirectTo: nil)
            XCTFail("Local repository should not request remote email magic link")
        } catch let error as AuthError {
            XCTAssertEqual(error, .futureRemoteAuthNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRepositoryDoesNotUseRecoveryCalculator() {
        let repository = makeRepository()
        let session = repository.continueAsLocalUser(displayName: "SOOM 사용자")

        XCTAssertTrue(session.isLocalOnly)
    }

    private func makeRepository() -> LocalAuthRepository {
        let suiteName = "AuthRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AuthSessionStore(userDefaults: defaults, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        return LocalAuthRepository(store: store)
    }
}
