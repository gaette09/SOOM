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
    func upsert(tokenHex: String, userId: UUID) async throws {}
    func deleteToken(tokenHex: String) async throws {}
}

struct SupabaseDeviceTokenRegistrar: DeviceTokenRegistering {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func upsert(tokenHex: String, userId: UUID) async throws {
        let request = DeviceTokenUpsertDTO(userId: userId, token: tokenHex)
        try await client
            .from("device_tokens")
            .upsert(request, onConflict: "user_id,token")
            .execute()
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
