import Foundation
import Supabase

protocol DeviceTokenRegistering {
    func upsert(tokenHex: String, userId: UUID) async throws
    func deleteToken(tokenHex: String) async throws
}

private struct DeviceTokenUpsertDTO: Encodable, Equatable {
    let userId: UUID
    let token: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case token
    }
}

/// Used when SupabaseClientProvider can't produce a client (e.g. missing
/// environment config) — device token registration silently no-ops rather
/// than crashing the app over a non-critical feature.
struct NoopDeviceTokenRegistrar: DeviceTokenRegistering {
    func upsert(tokenHex: String, userId: UUID) async throws { throw DeviceRegistrationError.accountChanged }
    func deleteToken(tokenHex: String) async throws {}
}

struct SupabaseDeviceTokenRegistrar: DeviceTokenRegistering {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func upsert(tokenHex: String, userId: UUID) async throws {
        let session = try await client.auth.session
        guard session.user.id == userId, !Task.isCancelled else { throw DeviceRegistrationError.accountChanged }
        struct Registration: Encodable { let p_actor: UUID; let p_token: String;let p_environment:String }
        #if DEBUG
        let environment="development"
        #else
        let environment="production"
        #endif
        do {
            let saved:Bool = try await client.rpc("soom_register_push_v2", params: Registration(p_actor: userId, p_token: tokenHex,p_environment:environment)).execute().value
            guard saved else { throw DeviceRegistrationError.accountChanged }
            await EventNotificationCenter.shared.registrationSucceeded(token:tokenHex,userID:userId)
        } catch let error as PostgrestError where error.code == "PGRST202" {
            // Old server remains usable, but never claim extended delivery ready.
            guard !Task.isCancelled else { throw CancellationError() }
            try await client.from("device_tokens").upsert(DeviceTokenUpsertDTO(userId: userId, token: tokenHex), onConflict: "user_id,token").execute()
            throw DeviceRegistrationError.extendedServiceUnavailable
        }
    }

    /// Scoped to the current session's user (not the userId this token was
    /// registered under) so this only ever deletes a row RLS already lets
    /// the caller touch — must be called before the session is torn down.
    func deleteToken(tokenHex: String) async throws {
        let session = try await client.auth.session
        try await client
            .from("device_tokens")
            .delete()
            .eq("user_id", value: session.user.id)
            .eq("token", value: tokenHex)
            .execute()
    }
}
