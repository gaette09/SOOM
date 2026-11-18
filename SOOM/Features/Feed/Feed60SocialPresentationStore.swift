import SwiftUI

/// Page-owned display overrides, never a write/read authorization. Nil lookup
/// means no override; unknown explicitly forbids fallback to older batch values.
@MainActor final class Feed60SocialPresentationStore: ObservableObject {
    enum Override: Equatable {
        case unknown
        case ready(ProfileActivitySocialStatus)
    }
    private struct Entry {
        let authority: FeedLinkedCardAuthority
        var value: Override
        var requestID: UUID?
        let order: UInt64
    }
    private struct Scope: Equatable {
        let context: FeedReturnBatchContext
        let batchID: UUID
        init(_ authority: FeedLinkedCardAuthority) {
            context = authority.context; batchID = authority.batchID
        }
    }
    static let maximumCount = 64
    @Published private(set) var revision = 0
    private var entries: [UUID: Entry] = [:]
    private var scope: Scope?
    // Evicting a mutation override must not resurrect stale grant.socialStatus.
    // After overflow, current-scope misses require a fresh read instead.
    private var overflowed = false
    private var sequence: UInt64 = 0
    var count: Int { entries.count }

    func resident(_ authority: FeedLinkedCardAuthority, isCurrent: () -> Bool) -> Override? {
        guard isCurrent(), scope == Scope(authority) else { return nil }
        if let entry = entries[authority.row.cardID], entry.authority == authority { return entry.value }
        return overflowed ? .unknown : nil
    }

    /// Call before refresh/mutation starts, including uncertain mutation replay.
    /// A later request supersedes every prior completion for this exact card.
    @discardableResult
    func begin(_ authority: FeedLinkedCardAuthority, isCurrent: () -> Bool) -> UUID? {
        guard isCurrent() else { return nil }
        if scope != Scope(authority) {
            entries.removeAll(); overflowed = false; scope = Scope(authority)
        }
        let token = UUID()
        sequence &+= 1
        entries[authority.row.cardID] = Entry(authority: authority, value: .unknown, requestID: token, order: sequence)
        if entries.count > Self.maximumCount,
           let oldest = entries.min(by: { $0.value.order < $1.value.order })?.key {
            entries.removeValue(forKey: oldest); overflowed = true
        }
        revision += 1
        return token
    }

    @discardableResult
    func markUnknown(_ authority: FeedLinkedCardAuthority, isCurrent: () -> Bool) -> UUID? {
        begin(authority, isCurrent: isCurrent)
    }

    /// nil status is a failed/ambiguous read, not a confirmed uncheered state.
    /// Consuming the token prevents duplicate or late responses from restoring it.
    @discardableResult
    func finish(_ authority: FeedLinkedCardAuthority, requestID: UUID,
                status: ProfileActivitySocialStatus?, isCurrent: () -> Bool) -> Bool {
        guard isCurrent(), scope == Scope(authority),
              var entry = entries[authority.row.cardID], entry.authority == authority,
              entry.requestID == requestID else { return false }
        entry.requestID = nil
        let valid = status.map { Self.matches($0, authority: authority) } ?? true
        entry.value = valid ? status.map(Override.ready) ?? .unknown : .unknown
        entries[authority.row.cardID] = entry
        revision += 1
        return valid
    }

    private static func matches(_ status: ProfileActivitySocialStatus, authority: FeedLinkedCardAuthority) -> Bool {
        let receipt = status.receipt
        return status.state == "ready" && status.cheer_count >= 0 && status.comment_count >= 0 &&
            receipt.viewer_id == authority.context.viewerID && receipt.card_id == authority.row.cardID &&
            receipt.owner_id == authority.row.ownerID && receipt.canonical_id == authority.row.canonicalID &&
            receipt.projection_revision == authority.row.revision
    }

    func retain(using batch: FeedReturnBatchPresentation) {
        guard batch.phase == .ready, scope?.batchID == batch.id, scope?.context == batch.context else {
            clear(); return
        }
        let before = entries.count
        entries = entries.filter { id, entry in
            guard !batch.denied.contains(id), let grant = batch.grants[id] else { return false }
            return grant.id == entry.authority.grantID && grant.row == entry.authority.row
        }
        if entries.count != before { revision += 1 }
    }

    /// Drop payloads under memory pressure but preserve the fact that this
    /// batch may contain older social values. Misses stay unknown until read.
    func purgeForMemoryPressure() {
        entries.removeAll()
        if scope != nil { overflowed = true }
        revision += 1
    }

    /// Epoch changes/account changes/complete invalidation call this. In-flight
    /// tokens are forgotten, so even noncooperative old responses cannot commit.
    func clear() {
        entries.removeAll(); scope = nil; overflowed = false; revision += 1
    }
}

private struct Feed60SocialPresentationStoreKey: EnvironmentKey {
    static let defaultValue: Feed60SocialPresentationStore? = nil
}
extension EnvironmentValues {
    var soomFeedSocialPresentationStore: Feed60SocialPresentationStore? {
        get { self[Feed60SocialPresentationStoreKey.self] }
        set { self[Feed60SocialPresentationStoreKey.self] = newValue }
    }
}

private struct Feed60SocialPresentationRevisionKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var soomFeedSocialPresentationRevision: Int {
        get { self[Feed60SocialPresentationRevisionKey.self] }
        set { self[Feed60SocialPresentationRevisionKey.self] = newValue }
    }
}
