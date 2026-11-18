import Foundation
import Supabase

/// Installed only after both candidate contracts pass release verification.
/// Lookup absence does not silently turn a native card into a legacy post.
@MainActor enum AccountActivityPhotoProviderFactory {
    static func make(client: SupabaseClient, storage: HealthAccountStorageController,
                     safety: CommunitySafetyStore) -> (any WorkoutPhotoManaging)? {
        guard AccountActivityFeedReleaseGate.productionReady,
              AccountActivityInteractionReleaseGate.productionReady,
              let owner = storage.userID, !AccountDeletionWriteFence.shared.isRetired(owner), client.auth.currentSession?.user.id == owner else { return nil }
        let current = { AccountActivityInteractionContext(viewerID: safety.canUseSocial ? client.auth.currentSession?.user.id : nil,
            generation: safety.accountGeneration, safetyRevision: safety.revision, storageScopeID: storage.scopeID) }
        let transport = SupabaseAccountActivityInteractionTransport(client: client)
        let reader = AccountActivityInteractionAdapter(transport: transport, context: current)
        let writer = AccountActivityPhotoMutationAdapter(reader: reader, transport: transport,
            storage: SupabaseAccountActivityPhotoStorageTransport(client: client), context: current)
        return AccountActivityWorkoutPhotoProvider(reader: reader, writer: writer, legacy: WorkoutPhotoService(client: client)) { workoutID, requestedOwner in
            let before = current()
            guard !AccountDeletionWriteFence.shared.isRetired(owner), requestedOwner == owner, before.viewerID == owner, storage.userID == owner,
                  before.storageScopeID == owner.uuidString.lowercased() else { throw AccountActivityPhotoEditError.contextChanged }
            struct Params: Encodable { let p_canonical_id: UUID }
            struct Envelope: Decodable { let version: Int; let viewer_id: UUID; let row: AccountActivityStageLookup?; let release_ready: Bool }
            let result: Envelope = try await client.rpc("soom_activity_owner_lookup_candidate_v1", params: Params(p_canonical_id: workoutID)).execute().value
            guard !AccountDeletionWriteFence.shared.isRetired(owner), current() == before, result.version == 1, result.viewer_id == owner, result.release_ready else { throw AccountActivityPhotoEditError.contextChanged }
            guard let row = result.row, row.owner_id == owner, row.canonical_id == workoutID,
                  row.source_ids.contains(workoutID), !row.deleted else { throw AccountActivityPhotoEditError.blocked }
            struct StatusParams: Encodable { let p_card_id: UUID }
            struct Status: Decodable { let version: Int; let card_id: UUID; let backing: String; let state: String; let release_ready: Bool }
            let status: Status = try await client.rpc("soom_activity_interaction_status_candidate_v1", params: StatusParams(p_card_id: row.card_id)).execute().value
            guard !AccountDeletionWriteFence.shared.isRetired(owner), current() == before, status.version == 1, status.card_id == row.card_id, status.release_ready else { throw AccountActivityPhotoEditError.contextChanged }
            if status.backing == "native", status.state == "native_ready" { return .native(cardID: row.card_id, ownerID: owner) }
            if status.backing == "legacy", status.state == "legacy_linked" {
                let receipt: AccountActivityLegacyDetailReceipt? = try await client.rpc("soom_activity_legacy_detail_candidate_v1", params: StatusParams(p_card_id: row.card_id)).execute().value
                guard !AccountDeletionWriteFence.shared.isRetired(owner), current() == before, let receipt, receipt.version == 1, receipt.cardID == row.card_id, receipt.releaseReady else { throw AccountActivityPhotoEditError.blocked }
                let posts = try await SupabaseWorkoutRecordRemote(client: client).linkedPosts(workoutID: workoutID, ownerID: owner)
                guard !AccountDeletionWriteFence.shared.isRetired(owner), current() == before,
                      posts.sorted(by: { $0.createdAt < $1.createdAt }).first?.id == receipt.legacyPostID else { throw AccountActivityPhotoEditError.blocked }
                // Existing service resolves the same owner/source relation and
                // selects its oldest post. The exact resolved identity must agree.
                return .legacy(cardID: row.card_id, postID: receipt.legacyPostID)
            }
            throw AccountActivityPhotoEditError.blocked
        }
    }
}
