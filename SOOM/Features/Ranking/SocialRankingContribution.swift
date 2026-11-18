import Foundation
import Supabase

/// Separate from posting. A registration failure must never re-post or turn an
/// already public post into a local draft. Caller preserves the same intent.
@MainActor
struct SocialRankingContributionClient {
    let client: SupabaseClient
    let viewer: UUID
    let generation: Int
    let safetyRevision: Int
    enum Result: Equatable { case registered; case pending; case unavailable }
    private func allowed() -> Bool {
        let safety = CommunitySafetyStore.shared
        return SocialRankingReleaseGate.productionReady && safety.canUseSocial && safety.viewerID == viewer
            && safety.accountGeneration == generation && safety.revision == safetyRevision
            && client.auth.currentSession?.user.id == viewer
    }
    func registerPublished(_ intent: SocialRankingContribution, store: SocialRankingRetryStore) async -> Result {
        guard allowed(), store.ownerID == viewer else { return .unavailable }
        do { try store.save(intent) } catch { return .pending }
        let result = await register(intent)
        if case .registered = result {
            guard allowed() else { return .unavailable }
            do { try store.remove(intent) } catch { return .pending }
        }
        return result
    }
    func register(_ intent: SocialRankingContribution) async -> Result {
        guard allowed(), !Task.isCancelled else { return .unavailable }
        struct Post: Decodable { let id: UUID; let source_workout_id: UUID?; let visibility: String }
        struct Params: Encodable { let p_canonical_id: UUID; let p_source_ids: [UUID]; let p_post_id: UUID }
        struct Receipt: Decodable { let version: Int; let canonical_id: UUID; let post_id: UUID; let accepted: Bool }
        do {
            let posts: [Post] = try await client.from("feed_posts")
                .select("id,source_workout_id,visibility").eq("user_id", value: viewer)
                .eq("source_workout_id", value: intent.canonicalID).execute().value
            guard allowed(), !Task.isCancelled else { return .unavailable }
            guard posts.count == 1, let post = posts.first, post.visibility == "public", post.source_workout_id == intent.canonicalID else { return .unavailable }
            let receipt: Receipt = try await client.rpc("soom_register_ranking_contribution_v1", params: Params(p_canonical_id: intent.canonicalID, p_source_ids: intent.sourceIDs, p_post_id: post.id)).execute().value
            guard allowed(), !Task.isCancelled else { return .unavailable }
            guard receipt.version == 1, receipt.accepted, receipt.canonical_id == intent.canonicalID, receipt.post_id == post.id else { return .pending }
            return .registered
        } catch {
            // No automatic retry, re-publication, deletion, or visibility change.
            return allowed() && !Task.isCancelled ? .pending : .unavailable
        }
    }
}

@MainActor
final class SocialRankingPublicationContext { var intent: SocialRankingContribution? }
