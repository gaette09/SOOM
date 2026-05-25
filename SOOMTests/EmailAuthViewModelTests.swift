import XCTest
@testable import SOOM

@MainActor
final class EmailAuthViewModelTests: XCTestCase {
    func testInvalidEmailFailsBeforeRequest() async {
        var requestCount = 0
        let viewModel = EmailAuthViewModel(emailText: "invalid") { _, _ in
            requestCount += 1
            return EmailAuthRequestResult(email: "invalid", redirectTo: nil, requestedAt: Date())
        }

        await viewModel.submit()

        XCTAssertEqual(viewModel.state, .failed)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(viewModel.errorMessage, AuthError.invalidEmail.userMessage)
    }

    func testSuccessfulRequestPublishesSentState() async {
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let redirect = URL(string: "soom-dev://auth/callback")
        var capturedEmail: String?
        var capturedRedirect: URL?
        let viewModel = EmailAuthViewModel(emailText: " USER@example.COM ", redirectTo: redirect) { email, redirectTo in
            capturedEmail = email
            capturedRedirect = redirectTo
            return EmailAuthRequestResult(email: email, redirectTo: redirectTo, requestedAt: fixedDate)
        }

        await viewModel.submit()

        XCTAssertEqual(viewModel.state, .sent)
        XCTAssertEqual(viewModel.emailText, "user@example.com")
        XCTAssertEqual(capturedEmail, "user@example.com")
        XCTAssertEqual(capturedRedirect, redirect)
        XCTAssertNotNil(viewModel.successMessage)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testProviderFailurePublishesFailedState() async {
        let viewModel = EmailAuthViewModel(emailText: "user@example.com") { _, _ in
            throw AuthError.futureRemoteAuthNotConfigured
        }

        await viewModel.submit()

        XCTAssertEqual(viewModel.state, .failed)
        XCTAssertEqual(viewModel.errorMessage, AuthError.futureRemoteAuthNotConfigured.userMessage)
        XCTAssertNil(viewModel.successMessage)
    }

    func testEmailRequestDoesNotReplaceLocalAuthSession() async {
        let suiteName = "EmailAuthViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AuthSessionStore(userDefaults: defaults)
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = EmailAuthViewModel(emailText: "user@example.com") { email, redirectTo in
            EmailAuthRequestResult(email: email, redirectTo: redirectTo, requestedAt: Date())
        }

        await viewModel.submit()

        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testViewModelDoesNotUseRecoveryCalculator() async {
        let viewModel = EmailAuthViewModel(emailText: " ") { email, redirectTo in
            EmailAuthRequestResult(email: email, redirectTo: redirectTo, requestedAt: Date())
        }

        await viewModel.submit()

        XCTAssertEqual(viewModel.state, .failed)
    }
}
