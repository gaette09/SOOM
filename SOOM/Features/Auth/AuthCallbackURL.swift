import Foundation

struct AuthCallbackURL: Equatable {
    let url: URL
    let scheme: String
    let host: String?
    let path: String
    let provider: String?
    let isAuthCallback: Bool

    init(url: URL, environment: AuthEnvironment) {
        self.url = url
        self.scheme = url.scheme ?? ""
        self.host = url.host
        self.path = url.path
        self.provider = Self.providerValue(from: url)

        guard
            let expectedScheme = environment.redirectScheme?.lowercased(),
            AuthEnvironment.isConcreteValue(expectedScheme),
            scheme.lowercased() == expectedScheme
        else {
            self.isAuthCallback = false
            return
        }

        self.isAuthCallback = Self.matchesAuthCallbackPath(host: host, path: path)
    }

    private static func matchesAuthCallbackPath(host: String?, path: String) -> Bool {
        let normalizedHost = host?.lowercased()
        let normalizedPath = path.lowercased()

        if normalizedHost == "auth", normalizedPath == "/callback" {
            return true
        }

        return normalizedPath == "/auth/callback"
    }

    private static func providerValue(from url: URL) -> String? {
        let queryProvider = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == "provider" })?
            .value

        if AuthEnvironment.isConcreteValue(queryProvider) {
            return queryProvider
        }

        guard let fragment = url.fragment,
              let components = URLComponents(string: "callback?\(fragment)")
        else {
            return nil
        }

        return components.queryItems?
            .first(where: { $0.name.lowercased() == "provider" || $0.name.lowercased() == "type" })?
            .value
    }
}
