import Foundation

@MainActor
final class EmailAuthViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case validating
        case sending
        case sent
        case failed
    }

    @Published var emailText: String
    @Published private(set) var state: State
    @Published private(set) var successMessage: String?
    @Published private(set) var errorMessage: String?

    private let redirectTo: URL?
    private let requestMagicLink: (String, URL?) async throws -> EmailAuthRequestResult

    init(environment: AuthEnvironment = AuthEnvironmentLoader().load()) {
        let provider = SupabaseAuthProvider(configuration: SupabaseAuthConfiguration.from(environment: environment))
        self.emailText = ""
        self.state = .idle
        self.redirectTo = EmailAuthRequest.redirectURL(from: environment)
        self.requestMagicLink = { email, redirectTo in
            try await provider.requestMagicLink(email: email, redirectTo: redirectTo)
        }
    }

    init(
        emailText: String = "",
        redirectTo: URL? = nil,
        requestMagicLink: @escaping (String, URL?) async throws -> EmailAuthRequestResult
    ) {
        self.emailText = emailText
        self.state = .idle
        self.redirectTo = redirectTo
        self.requestMagicLink = requestMagicLink
    }

    var isSending: Bool {
        state == .sending
    }

    func submit() async {
        state = .validating
        successMessage = nil
        errorMessage = nil

        let request = EmailAuthRequest(email: emailText, redirectTo: redirectTo)
        do {
            try request.validate()
            state = .sending
            let result = try await requestMagicLink(request.normalizedEmail, request.redirectTo)
            state = .sent
            emailText = result.email
            successMessage = "로그인 링크를 보냈어요. 메일함에서 SOOM 링크를 확인해주세요."
        } catch let error as AuthError {
            state = .failed
            errorMessage = error.userMessage
        } catch {
            state = .failed
            errorMessage = "로그인 링크를 보내지 못했어요. 잠시 후 다시 시도해주세요."
        }
    }
}
