import Foundation
import Supabase

struct HealthCloudRemoteRecord: Codable, Equatable, Sendable {
    let kind: String
    let recordKey: String
    let payloadJSON: String?
    let isDeleted: Bool
    let version: Int64
    let revision: Int64
    var accepted: Bool?
    enum CodingKeys: String, CodingKey {
        case kind, version, revision, accepted
        case recordKey = "record_key", payloadJSON = "payload_json", isDeleted = "is_deleted"
    }
    var payloadData: Data? { payloadJSON?.data(using: .utf8) }
}

struct HealthCloudMutation: Equatable {
    let kind: String
    let recordKey: String
    let payload: Data?
    let isDeleted: Bool
    let baseVersion: Int64
    let mutationID: UUID
}

@MainActor
protocol HealthCloudRemote {
    func push(_ mutation: HealthCloudMutation, expectedUserID: UUID) async throws -> HealthCloudRemoteRecord
    func pull(after revision: Int64, expectedUserID: UUID) async throws -> [HealthCloudRemoteRecord]
}

/// Uses only SOOM's shared authenticated Supabase client. The expected account
/// also travels in each RPC, so an SDK account switch cannot upload A's data as B.
@MainActor
struct SupabaseHealthCloudRemote: HealthCloudRemote {
    let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func push(_ mutation: HealthCloudMutation, expectedUserID: UUID) async throws -> HealthCloudRemoteRecord {
        try assertAccount(expectedUserID)
        struct Params: Encodable {
            let p_expected_user_id: UUID
            let p_kind: String
            let p_record_key: String
            let p_payload_json: String?
            let p_is_deleted: Bool
            let p_base_version: Int64
            let p_mutation_id: UUID
        }
        let rows: [HealthCloudRemoteRecord] = try await client.rpc("health_apply_v1", params: Params(
            p_expected_user_id: expectedUserID, p_kind: mutation.kind,
            p_record_key: mutation.recordKey,
            p_payload_json: mutation.payload.flatMap { String(data: $0, encoding: .utf8) },
            p_is_deleted: mutation.isDeleted, p_base_version: mutation.baseVersion,
            p_mutation_id: mutation.mutationID
        )).execute().value
        try assertAccount(expectedUserID)
        guard let result = rows.first else { throw HealthCloudError.invalidPayload }
        return result
    }

    func pull(after revision: Int64, expectedUserID: UUID) async throws -> [HealthCloudRemoteRecord] {
        try assertAccount(expectedUserID)
        struct Params: Encodable {
            let p_expected_user_id: UUID
            let p_after_revision: Int64
            let p_limit: Int
        }
        let rows: [HealthCloudRemoteRecord] = try await client.rpc("health_pull_v1", params: Params(
            p_expected_user_id: expectedUserID, p_after_revision: revision, p_limit: 200
        )).execute().value
        try assertAccount(expectedUserID)
        return rows
    }
    private func assertAccount(_ expected: UUID) throws {
        guard client.auth.currentSession?.user.id == expected else { throw HealthCloudError.accountChanged }
    }
}
