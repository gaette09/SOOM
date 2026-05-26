import XCTest
@testable import SOOM

final class AuthCallbackHandlerTests: XCTestCase {
    private let environment = AuthEnvironment(
        environment: .development,
        supabaseURL: URL(string: "https://example.supabase.co"),
        supabaseAnonKey: "anon-test-key",
        redirectScheme: "soom-dev"
    )

    func testIgnoredNonAuthURLDoesNotInvokeSessionHandler() async {
        let sessionHandler = FakeAuthCallbackSessionHandler(session: nil)
        let handler = AuthCallbackHandler(environment: environment, sessionHandler: sessionHandler)

        let result = await handler.handle(url: URL(string: "soom-dev://settings/profile")!)

        XCTAssertEqual(result, .ignored)
        XCTAssertTrue(sessionHandler.handledURLs.isEmpty)
    }

    func testHandledCallbackWithoutRemoteSession() async {
        let sessionHandler = FakeAuthCallbackSessionHandler(session: nil)
        let handler = AuthCallbackHandler(environment: environment, sessionHandler: sessionHandler)
        let url = URL(string: "soom-dev://auth/callback")!

        let result = await handler.handle(url: url)

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(sessionHandler.handledURLs, [url])
    }

    func testSessionBridgedCallback() async {
        let user = AppUser(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let session = AuthSession.signedIn(user: user)
        let sessionHandler = FakeAuthCallbackSessionHandler(session: session)
        let handler = AuthCallbackHandler(environment: environment, sessionHandler: sessionHandler)

        let result = await handler.handle(url: URL(string: "soom-dev://auth/callback")!)

        XCTAssertEqual(result, .sessionBridged(session))
    }

    func testFailedCallbackKeepsFailureLocalFriendly() async {
        let sessionHandler = FakeAuthCallbackSessionHandler(error: AuthError.futureRemoteAuthNotConfigured)
        let handler = AuthCallbackHandler(environment: environment, sessionHandler: sessionHandler)

        let result = await handler.handle(url: URL(string: "soom-dev://auth/callback")!)

        if case .failed(let message) = result {
            XCTAssertTrue(message.contains("로컬 사용자"))
        } else {
            XCTFail("Expected failed callback result")
        }
    }

    func testCallbackHandlerDoesNotUseRecoveryCalculator() async {
        let sessionHandler = FakeAuthCallbackSessionHandler(session: nil)
        let handler = AuthCallbackHandler(environment: environment, sessionHandler: sessionHandler)

        let result = await handler.handle(url: URL(string: "soom-dev://auth/callback")!)

        XCTAssertEqual(result, .handled)
    }
}

private final class FakeAuthCallbackSessionHandler: AuthCallbackSessionHandling {
    private let session: AuthSession?
    private let error: Error?
    private(set) var handledURLs: [URL] = []

    init(session: AuthSession? = nil, error: Error? = nil) {
        self.session = session
        self.error = error
    }

    func handleAuthCallback(url: URL) async throws -> AuthSession? {
        handledURLs.append(url)
        if let error { throw error }
        return session
    }
}
