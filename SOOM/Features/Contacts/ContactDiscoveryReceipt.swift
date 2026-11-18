import Foundation

struct ContactDiscoveryReceipt: Decodable, Equatable {
    let version: Int
    let viewerID: UUID
    let noticeVersion: Int
    let consentReady: Bool
    let matchingReady: Bool
    let decision: String
    let discoverable: Bool
    let revision: Int64
    enum CodingKeys: String, CodingKey {
        case version, decision, discoverable, revision
        case viewerID = "viewer_id", noticeVersion = "notice_version"
        case consentReady = "consent_ready", matchingReady = "matching_ready"
    }
    enum Invalid: Error { case unsupported, accountChanged, malformed }
    func validate(expectedAccount: UUID, currentAccount: UUID?, requestedGeneration: Int,
                  currentGeneration: Int) throws {
        guard version == 1, noticeVersion == 1 else { throw Invalid.unsupported }
        guard viewerID == expectedAccount, currentAccount == expectedAccount,
              requestedGeneration == currentGeneration else { throw Invalid.accountChanged }
        guard revision >= 0, ["unseen", "deferred", "accepted", "revoked"].contains(decision),
              (!discoverable || decision == "accepted"), (!matchingReady || consentReady) else { throw Invalid.malformed }
    }
    var canOfferConnection: Bool { consentReady && matchingReady && decision == "unseen" }
}
