import Foundation

/// Local orchestration only. No Contacts access or network operation is performed here.
/// Production must remain unavailable until consent, matching and deletion are implemented.
struct ContactDiscoveryCapabilities: Equatable {
    let consentStorage: Bool
    let verifiedIdentityMatching: Bool
    let optInDiscoverability: Bool
    let deleteAndStop: Bool
    let abuseProtection: Bool
    var ready: Bool {
        consentStorage && verifiedIdentityMatching && optInDiscoverability && deleteAndStop && abuseProtection
    }
    static let unavailable = Self(consentStorage: false, verifiedIdentityMatching: false,
        optInDiscoverability: false, deleteAndStop: false, abuseProtection: false)
}

enum ContactDiscoveryPermission: Equatable {
    case notDetermined, denied, restricted, limited, authorized
    var permitsSelectedContacts: Bool { self == .limited || self == .authorized }
}

enum ContactDiscoveryPromptOrigin: Equatable { case firstLogin, existingAccountUpdate, settings }
enum ContactDiscoveryDecision: Equatable { case unseen, deferred, accepted, revoked }
enum ContactDiscoveryPhase: Equatable { case idle, awaitingOSPermission, readyToSync, syncing, connected, deletionPending }

struct ContactDiscoveryConsentState: Equatable {
    let accountID: UUID
    let noticeVersion: Int
    private(set) var decision: ContactDiscoveryDecision = .unseen
    private(set) var phase: ContactDiscoveryPhase = .idle
    private(set) var operationID: UUID?
    private(set) var generation = 0

    func shouldPresent(origin: ContactDiscoveryPromptOrigin, currentAccountID: UUID?,
                       capabilities: ContactDiscoveryCapabilities) -> Bool {
        guard currentAccountID == accountID, capabilities.ready, phase != .deletionPending else { return false }
        return origin == .settings || decision == .unseen
    }

    mutating func deferPrompt() {
        guard decision == .unseen else { return }
        decision = .deferred
    }

    /// Explicit in-app user choice only; not an OS permission or a server receipt.
    mutating func accept(currentAccountID: UUID?, capabilities: ContactDiscoveryCapabilities) -> Bool {
        guard currentAccountID == accountID, capabilities.ready, phase == .idle else { return false }
        decision = .accepted
        phase = .awaitingOSPermission
        return true
    }

    mutating func resolvePermission(_ permission: ContactDiscoveryPermission) {
        guard decision == .accepted, phase == .awaitingOSPermission else { return }
        phase = permission.permitsSelectedContacts ? .readyToSync : .idle
    }

    mutating func startSync(currentAccountID: UUID?, permission: ContactDiscoveryPermission,
                            capabilities: ContactDiscoveryCapabilities) -> UUID? {
        guard currentAccountID == accountID, capabilities.ready, decision == .accepted,
              phase == .readyToSync, permission.permitsSelectedContacts else { return nil }
        let id = UUID()
        operationID = id
        phase = .syncing
        return id
    }

    /// Caller must provide a validated server consent/sync receipt, not merely HTTP success.
    mutating func finishSync(operation: UUID, requestGeneration: Int,
                             currentAccountID: UUID?, receiptValidated: Bool) {
        guard currentAccountID == accountID, requestGeneration == generation,
              operation == operationID, phase == .syncing, decision == .accepted else { return }
        operationID = nil
        phase = receiptValidated ? .connected : .readyToSync
    }

    /// Stops new access immediately. Never claims server deletion has already happened.
    mutating func revoke() {
        generation += 1
        operationID = nil
        decision = .revoked
        phase = .deletionPending
    }

    mutating func finishDeletion(currentAccountID: UUID?, requestGeneration: Int,
                                 receiptValidated: Bool) {
        guard currentAccountID == accountID, requestGeneration == generation,
              phase == .deletionPending, receiptValidated else { return }
        phase = .idle
    }
}
