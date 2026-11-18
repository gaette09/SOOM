import Foundation
import Supabase

/// Read-only profile authority. This never authorizes legacy detail or mutations.
struct AccountActivityProfilePhotoAuthority: Codable, Equatable {
    let cardID: UUID
    let ownerID: UUID
    let sourceID: UUID
    let bucket: String
    let projectionRevision: Int64
    let profileRevision: Int64

    func permits(_ photo: WorkoutPhotoReference, cardID: UUID, ownerID: UUID, revision: Int64) -> Bool {
        self.cardID == cardID && self.ownerID == ownerID && projectionRevision == revision &&
        profileRevision > 0 && ["workout-photos", "activity-photos-candidate"].contains(bucket) &&
        photo.storagePath == WorkoutPhotoPolicy.path(ownerID: ownerID, postID: sourceID, photoID: photo.id)
    }
}

struct AccountActivityProfilePhotoEnvelope: Decodable {
    let version: Int
    let viewer_id: UUID
    let card_id: UUID
    let owner_id: UUID
    let canonical_id: UUID
    let projection_revision: Int64
    let profile_revision: Int64
    let backing: String
    let source_id: UUID
    let bucket: String
    let release_ready: Bool
    let rows: [AccountActivityPhotoMetadata]

    func validated(viewerID: UUID, cardID: UUID, ownerID: UUID, canonicalID: UUID,
                   revision: Int64) throws -> [WorkoutPhotoReference] {
        guard version == 2, release_ready, viewer_id == viewerID, card_id == cardID,
              owner_id == ownerID, canonical_id == canonicalID, projection_revision == revision,
              revision > 0, profile_revision > 0, rows.count <= 6,
              Set(rows.map(\.id)).count == rows.count,
              (backing == "legacy" && bucket == "workout-photos") ||
                (backing == "native" && bucket == "activity-photos-candidate" && source_id == cardID)
        else { throw AccountActivityInteractionError.invalidResponse }
        let authority = AccountActivityProfilePhotoAuthority(cardID: cardID, ownerID: ownerID,
            sourceID: source_id, bucket: bucket, projectionRevision: revision, profileRevision: profile_revision)
        return try rows.enumerated().map { index, row in
            let photo = WorkoutPhotoReference(id: row.id, storagePath: row.storage_path,
                nativeCardID: backing == "native" ? cardID : nil, profileAuthority: authority)
            guard row.card_id == cardID, row.sort_order == index,
                  authority.permits(photo, cardID: cardID, ownerID: ownerID, revision: revision)
            else { throw AccountActivityInteractionError.invalidResponse }
            return photo
        }
    }
}

@MainActor
struct AccountActivityProfilePhotoAdapter {
    let read: (UUID) async throws -> AccountActivityProfilePhotoEnvelope
    let context: () -> AccountActivityInteractionContext

    init(client: SupabaseClient, context: @escaping () -> AccountActivityInteractionContext) {
        self.context = context
        self.read = { cardID in
            struct Params: Encodable { let p_card_id: UUID }
            return try await client.rpc("soom_activity_profile_photos_candidate_v2",
                params: Params(p_card_id: cardID)).execute().value
        }
    }
    init(read: @escaping (UUID) async throws -> AccountActivityProfilePhotoEnvelope,
         context: @escaping () -> AccountActivityInteractionContext) {
        self.read = read; self.context = context
    }
    func load(row: AccountActivityFeedRow) async throws -> [WorkoutPhotoReference] {
        let before = context()
        guard row.readPolicy == .profileOnlyV2, row.readPolicy.productionReady,
              let viewer = before.viewerID, before.storageScopeID == viewer.uuidString.lowercased(),
              !AccountDeletionWriteFence.shared.isRetired(viewer), !Task.isCancelled
        else { throw AccountActivityInteractionError.accountChanged }
        let envelope = try await read(row.cardID)
        guard !Task.isCancelled, context() == before, !AccountDeletionWriteFence.shared.isRetired(viewer)
        else { throw AccountActivityInteractionError.accountChanged }
        return try envelope.validated(viewerID: viewer, cardID: row.cardID, ownerID: row.ownerID,
            canonicalID: row.canonicalID, revision: row.revision)
    }
}
