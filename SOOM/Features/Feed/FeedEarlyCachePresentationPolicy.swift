import Foundation

/// Display-only state machine. This type cannot issue card/media/detail authority.
/// Transport session and mounted storage must independently confirm this scope.
struct FeedEarlyCachePresentationPolicy {
    struct Scope: Equatable {
        let viewerID: UUID
        let accountGeneration: Int
        let durableEpoch: String
        let policyVersion: Int
    }
    enum Verification: Equatable {
        case unresolved
        case checking
        case authorized
        case denied
        case unavailable
    }
    struct Entry: Equatable {
        let id: UUID
        let scope: Scope
        let startedUptime: TimeInterval
    }
    private(set) var entry: Entry?
    private(set) var verification: Verification = .unresolved
    private(set) var revoked = false
    let storageMaximumAge: TimeInterval = 86_400
    let displayMaximumAge: TimeInterval = 5

    /// Only a real feed entry may call this. onAppear/retry/privacy events reuse
    /// the entry ID; they must not generate new IDs to extend stale exposure.
    mutating func begin(id: UUID, scope: Scope, authenticatedViewer: UUID?, mountedViewer: UUID?,
                        uptime: TimeInterval) -> Bool {
        guard authenticatedViewer == scope.viewerID, mountedViewer == scope.viewerID,
              scope.accountGeneration >= 0, !scope.durableEpoch.isEmpty, scope.policyVersion > 0,
              uptime.isFinite, uptime >= 0 else { return false }
        if let entry {
            // Repeated mounts never reset a deadline, including after expiry/denial.
            return entry.id == id && entry.scope == scope && !revoked
        }
        entry = .init(id: id, scope: scope, startedUptime: uptime)
        verification = .unresolved
        return !revoked
    }
    mutating func update(_ state: Verification, scope: Scope) {
        guard entry?.scope == scope, !revoked else { return }
        verification = state
        if state == .denied { revoked = true }
    }
    /// Caller must ALSO synchronously erase/fence persistent cache and live grants.
    /// New pending callbacks cannot undo this tombstone.
    mutating func revoke() { revoked = true; verification = .denied }

    func permits(scope: Scope, authenticatedViewer: UUID?, mountedViewer: UUID?,
                 isActiveFeed: Bool, uptime: TimeInterval, cachedAge: TimeInterval,
                 persistedEpoch: String, layoutMatches: Bool) -> Bool {
        guard let entry, entry.scope == scope, !revoked, isActiveFeed,
              authenticatedViewer == scope.viewerID, mountedViewer == scope.viewerID,
              persistedEpoch == scope.durableEpoch, layoutMatches,
              verification == .unresolved || verification == .checking,
              uptime.isFinite, cachedAge.isFinite,
              cachedAge >= 0, cachedAge < storageMaximumAge else { return false }
        let elapsed = uptime - entry.startedUptime
        return elapsed.isFinite && elapsed >= 0 && elapsed < displayMaximumAge
    }
    var deadlineUptime: TimeInterval? { entry.map { $0.startedUptime + displayMaximumAge } }
}
