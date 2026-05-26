import Foundation
import CryptoKit
import Security
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

final class AppleSignInProvider {
    private let now: () -> Date
    private let nonceCharacters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func makeNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(length).description
            }

            for random in randoms where remainingLength > 0 {
                if random < UInt8(nonceCharacters.count) {
                    result.append(nonceCharacters[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    func prepareRequest(nonce: String? = nil) -> AppleSignInRequest {
        let rawNonce = normalized(nonce) ?? makeNonce()
        return AppleSignInRequest(
            requestedScopes: [.fullName, .email],
            requiresNonce: true,
            nonce: rawNonce,
            redirectStrategy: .supabaseOAuthFuture,
            createdAt: now()
        )
    }

    func handleCredential(_ credential: AppleSignInCredential) throws -> AppleSignInCredential {
        guard credential.isReadyForSupabaseExchange else {
            throw AuthError.appleCredentialMissing
        }

        return credential
    }

    func hashedNonce(_ nonce: String) -> String {
        let inputData = Data(nonce.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    static func string(from data: Data?) -> String? {
        guard let data else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

#if canImport(AuthenticationServices)
    func configure(_ request: ASAuthorizationAppleIDRequest, rawNonce: String) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce(rawNonce)
    }

    func credential(from authorization: ASAuthorization, rawNonce: String) throws -> AppleSignInCredential {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.appleCredentialMissing
        }

        return try credential(from: appleCredential, rawNonce: rawNonce)
    }

    func credential(from appleCredential: ASAuthorizationAppleIDCredential, rawNonce: String) throws -> AppleSignInCredential {
        let fullName = appleCredential.fullName.map { components -> String? in
            let formatter = PersonNameComponentsFormatter()
            let value = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } ?? nil

        let credential = AppleSignInCredential(
            userIdentifier: appleCredential.user,
            identityToken: Self.string(from: appleCredential.identityToken),
            authorizationCode: Self.string(from: appleCredential.authorizationCode),
            email: appleCredential.email,
            fullName: fullName,
            nonce: rawNonce,
            createdAt: now()
        )

        return try handleCredential(credential)
    }
#endif

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
