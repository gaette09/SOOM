import Foundation
import Supabase
import SwiftUI

protocol AppleGrantRegistering {
    func register(credential: AppleSignInCredential, expectedUserID: UUID) async throws
}

/// Ephemeral request only. Never persist or log this value.
struct AppleGrantRegistrationRequest: Encodable {
    let expectedUserID: UUID
    let authorizationCode: String
    let identityToken: String
    let rawNonce: String
    enum CodingKeys: String, CodingKey {
        case expectedUserID = "expected_user_id"
        case authorizationCode = "authorization_code"
        case identityToken = "identity_token"
        case rawNonce = "raw_nonce"
    }
    init(credential: AppleSignInCredential, expectedUserID: UUID) throws {
        guard let code = credential.authorizationCode,
              let token = credential.identityToken,
              let nonce = credential.nonce,
              credential.isReadyForFutureSupabaseExchange else {
            throw AuthError.appleCredentialMissing
        }
        self.expectedUserID = expectedUserID
        self.authorizationCode = code
        self.identityToken = token
        self.rawNonce = nonce
    }
}

struct SupabaseAppleGrantRegistrar: AppleGrantRegistering {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }
    private struct Response: Decodable { let status: String }
    func register(credential: AppleSignInCredential, expectedUserID: UUID) async throws {
        let request = try AppleGrantRegistrationRequest(credential: credential, expectedUserID: expectedUserID)
        guard client.auth.currentSession?.user.id == expectedUserID else { throw AuthError.sessionNotFound }
        let response: Response = try await client.functions.invoke("apple-grant", options: FunctionInvokeOptions(body: request))
        guard client.auth.currentSession?.user.id == expectedUserID, response.status == "stored" else {
            throw AuthError.sessionNotFound
        }
    }
}

/// Stores only a per-account readiness flag; no authorization code, nonce or token.
@MainActor
final class AppleGrantRegistrationState: ObservableObject {
    static let shared = AppleGrantRegistrationState()
    enum Status: String { case registered, needsRetry }
    private let defaults: UserDefaults
    @Published private var revision = 0
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    static func key(_ userID: UUID) -> String { "auth.appleGrantRegistration." + userID.uuidString.lowercased() }
    func status(for userID: UUID) -> Status? {
        defaults.string(forKey: Self.key(userID)).flatMap(Status.init(rawValue:))
    }
    func set(_ status: Status, for userID: UUID) {
        defaults.set(status.rawValue, forKey: Self.key(userID))
        revision += 1
    }
    func clear(_ userID: UUID) {
        defaults.removeObject(forKey: Self.key(userID))
        revision += 1
    }
}
