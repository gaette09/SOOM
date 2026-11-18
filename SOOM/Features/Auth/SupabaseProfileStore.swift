import Foundation
import Supabase

protocol SupabaseProfileUpdating {
    func updateDisplayName(_ name: String, expectedUserID: UUID) async throws -> String
}

/// A narrow RPC atomically updates profiles and the Supabase Auth user's display
/// metadata; authentication credentials never enter an application table.
struct SupabaseProfileStore: SupabaseProfileUpdating {
    let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func updateDisplayName(_ name: String, expectedUserID: UUID) async throws -> String {
        guard client.auth.currentSession?.user.id == expectedUserID else { throw AuthError.sessionNotFound }
        struct Params: Encodable { let p_expected_user_id: UUID; let p_display_name: String }
        struct Row: Decodable { let display_name: String }
        let rows: [Row] = try await client.rpc("update_profile_display_name_v1", params: Params(
            p_expected_user_id: expectedUserID, p_display_name: name
        )).execute().value
        guard client.auth.currentSession?.user.id == expectedUserID, let saved = rows.first?.display_name else {
            throw AuthError.sessionNotFound
        }
        UserDefaults.standard.set(saved, forKey: Self.nameCacheKey(expectedUserID))
        return saved
    }

    func cachedDisplayName(expectedUserID: UUID) -> String? {
        guard client.auth.currentSession?.user.id == expectedUserID else { return nil }
        return UserDefaults.standard.string(forKey: Self.nameCacheKey(expectedUserID))
    }

    func readDisplayName(expectedUserID: UUID) async -> String? {
        guard client.auth.currentSession?.user.id == expectedUserID else { return nil }
        struct Row: Decodable { let display_name: String }
        let rows: [Row]? = try? await client.from("profiles").select("display_name")
            .eq("id", value: expectedUserID.uuidString).limit(1).execute().value
        guard client.auth.currentSession?.user.id == expectedUserID else { return nil }
        if let name = rows?.first?.display_name {
            UserDefaults.standard.set(name, forKey: Self.nameCacheKey(expectedUserID))
            return name
        }
        return UserDefaults.standard.string(forKey: Self.nameCacheKey(expectedUserID))
    }
    static func clearCachedName(userID: UUID) {
        UserDefaults.standard.removeObject(forKey: nameCacheKey(userID))
    }
    func readAvatarPath(expectedUserID: UUID) async -> String? {
        guard client.auth.currentSession?.user.id == expectedUserID else { return nil }
        struct Row: Decodable { let avatar_path: String? }
        guard let rows: [Row] = try? await client.from("profiles").select("avatar_path")
            .eq("id", value: expectedUserID.uuidString).limit(1).execute().value,
              client.auth.currentSession?.user.id == expectedUserID else { return nil }
        return rows.first?.avatar_path
    }

    func updateAvatar(_ data: Data?, expectedUserID: UUID) async throws -> String? {
        guard client.auth.currentSession?.user.id == expectedUserID else { throw ProfileAvatarError.accountChanged }
        let path = data.map { _ in expectedUserID.uuidString.lowercased() + "/" + UUID().uuidString.lowercased() + ".jpg" }
        do {
            if let data, let path {
                let safeData = try ProfileAvatarPolicy.sanitizedJPEG(from: data)
                _ = try await client.storage.from(ProfileAvatarPolicy.bucket).upload(path, data: safeData,
                    options: FileOptions(cacheControl: "0", contentType: "image/jpeg", upsert: false))
            }
            guard client.auth.currentSession?.user.id == expectedUserID else { throw ProfileAvatarError.accountChanged }
            struct Params: Encodable {
                let p_expected_user_id: UUID
                let p_avatar_path: String?
                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(p_expected_user_id, forKey: .p_expected_user_id)
                    try container.encode(p_avatar_path, forKey: .p_avatar_path)
                }
                enum CodingKeys: String, CodingKey { case p_expected_user_id, p_avatar_path }
            }
            struct Row: Decodable { let avatar_path: String? }
            let rows: [Row] = try await client.rpc("update_profile_avatar_v1", params: Params(
                p_expected_user_id: expectedUserID, p_avatar_path: path)).execute().value
            guard client.auth.currentSession?.user.id == expectedUserID else { throw ProfileAvatarError.accountChanged }
            guard let receipt = rows.first, receipt.avatar_path == path else { throw ProfileAvatarError.unavailable }
            return receipt.avatar_path
        } catch {
            // An ambiguous RPC timeout may already have attached the upload.
            // Cleanup is deferred to the server's transactional media outbox.
            if error is ProfileAvatarError { throw error }
            throw ProfileAvatarError.unavailable
        }
    }
    private static func nameCacheKey(_ userID: UUID) -> String {
        "auth.profileDisplayName." + userID.uuidString.lowercased()
    }
}
