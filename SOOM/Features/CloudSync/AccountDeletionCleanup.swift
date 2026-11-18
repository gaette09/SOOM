import Foundation
import SwiftData

/// Contains no tokens, names, paths, or health data. A missing remote acknowledgment
/// is deliberately different from permission to remove the local account copy.
struct AccountDeletionCleanupMarker: Codable, Equatable {
    enum Phase: String, Codable {
        case awaitingServerConfirmation
        case serverConfirmed
        case localRemovalApproved
    }
    let userID: UUID
    let phase: Phase
}

enum AccountDeletionCleanupError: Error {
    case anotherAccountPending, confirmationRequired, accountChanged, preferencePersistenceFailed
}

/// Retained for the process lifetime after marker completion so old view/store
/// instances cannot recreate a deleted account's files during departure callbacks.
final class AccountDeletionWriteFence: @unchecked Sendable {
    static let shared = AccountDeletionWriteFence()
    private let lock = NSLock()
    private var retiredUserIDs: Set<UUID> = []

    func retire(_ userID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        retiredUserIDs.insert(userID)
    }

    func isRetired(_ userID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return retiredUserIDs.contains(userID)
    }

    /// Hold this same lock across the complete synchronous file mutation. Once
    /// retire returns, all earlier writes have finished and later writes reject.
    /// The operation must not call this fence recursively.
    func withActiveScope<T>(_ userID: UUID?, operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if let userID, retiredUserIDs.contains(userID) { throw AccountDeletionCleanupError.accountChanged }
        return try operation()
    }
}

@MainActor
final class AccountDeletionCleanupCoordinator: ObservableObject {
    static let shared = AccountDeletionCleanupCoordinator()
    @Published private(set) var marker: AccountDeletionCleanupMarker?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCleaning = false
    @Published private(set) var deferredUnconfirmedCleanup = false

    private let markerURL: URL
    private let accountsDirectory: URL
    private let defaults: UserDefaults
    private let removeItem: (URL) throws -> Void
    private let writeData: (Data, URL) throws -> Void

    init(markerURL: URL? = nil, accountsDirectory: URL? = nil,
         defaults: UserDefaults = .standard,
         removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
         writeData: @escaping (Data, URL) throws -> Void = { data, url in
             try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
         }) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.markerURL = markerURL ?? support.appendingPathComponent("SOOM/account-deletion-cleanup.json")
        self.accountsDirectory = accountsDirectory ?? support.appendingPathComponent("HealthAccounts", isDirectory: true)
        self.defaults = defaults
        self.removeItem = removeItem
        self.writeData = writeData
    }

    var blocksAppAccess: Bool {
        errorMessage != nil || (marker != nil && !deferredUnconfirmedCleanup)
    }

    /// Must run before opening any account ModelContainer. Only a previously
    /// confirmed deletion or an explicit local-only choice authorizes disk erasure.
    @discardableResult
    func prepareBeforeOpeningStorage() -> Bool {
        do {
            marker = try loadMarker()
            errorMessage = nil
            if let marker, marker.phase != .awaitingServerConfirmation {
                if marker.phase == .serverConfirmed { AccountDeletionWriteFence.shared.retire(marker.userID) }
                try eraseClosedScope(marker.userID)
                try complete(userID: marker.userID)
            }
            return true
        } catch {
            errorMessage = "이전 계정의 기기 정리를 마치지 못했어요. 기록을 다른 계정에 연결하지 않고 보관 중입니다. 다시 시도해 주세요."
            return false
        }
    }

    func begin(userID: UUID) throws {
        let previous = try loadMarker()
        guard previous == nil || (previous?.userID == userID && previous?.phase == .awaitingServerConfirmation) else {
            throw AccountDeletionCleanupError.anotherAccountPending
        }
        try save(.init(userID: userID, phase: .awaitingServerConfirmation))
    }

    func confirmServerDeletion(userID: UUID) throws {
        guard let marker, marker.userID == userID else { throw AccountDeletionCleanupError.accountChanged }
        guard marker.phase == .awaitingServerConfirmation || marker.phase == .serverConfirmed else {
            throw AccountDeletionCleanupError.confirmationRequired
        }
        try save(.init(userID: userID, phase: .serverConfirmed))
        AccountDeletionWriteFence.shared.retire(userID)
    }

    func approveLocalRemoval(userID: UUID) throws {
        guard marker?.userID == userID, marker?.phase == .awaitingServerConfirmation else {
            throw AccountDeletionCleanupError.accountChanged
        }
        try save(.init(userID: userID, phase: .localRemovalApproved))
    }

    func preserveAndContinue() {
        guard marker?.phase == .awaitingServerConfirmation else { return }
        deferredUnconfirmedCleanup = true
        errorMessage = nil
    }

    func showPendingCleanup() { deferredUnconfirmedCleanup = false }

    /// The normal Settings flow already erases the mounted stores. Keep the
    /// durable marker until every store and file has reported success.
    func complete(userID: UUID) throws {
        guard marker?.userID == userID, marker?.phase != .awaitingServerConfirmation else {
            throw AccountDeletionCleanupError.confirmationRequired
        }
        // Mounted SQLite stores must stay linked, but candidate journals contain
        // private drafts/media and must be erased before completion is recorded.
        for name in ["native-comment-pending-v1.json", "native-photo-pending-v1.json"] {
            try removeIfPresent(scopeDirectory(userID).appendingPathComponent(name))
        }
        try erasePreferences(userID)
        if FileManager.default.fileExists(atPath: markerURL.path) { try removeItem(markerURL) }
        marker = nil
        errorMessage = nil
        deferredUnconfirmedCleanup = false
    }

    /// A runtime retry clears models through the open container, never unlinks
    /// SQLite files that may still be cached. Root is gated throughout this call.
    func eraseMountedScope(using storage: HealthAccountStorageController) {
        guard let marker, marker.phase != .awaitingServerConfirmation, !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }
        let previousUserID = storage.userID
        do {
            try storage.switchAccount(userID: marker.userID)
            try storage.setCloudConsent(false)
            try storage.eraseCurrentScopeData(expectedUserID: marker.userID, retireScope: marker.phase == .serverConfirmed)
            let directory = scopeDirectory(marker.userID)
            try removeIfPresent(directory.appendingPathComponent("feed_share_drafts.json"))
            try removeIfPresent(directory.appendingPathComponent("active-workout.json"))
            try erasePreferences(marker.userID)
            try storage.switchAccount(userID: previousUserID)
            try complete(userID: marker.userID)
        } catch {
            errorMessage = "남은 기기 데이터를 정리하지 못했어요. 다시 시도할 수 있으며, 앱을 다시 열어도 정리를 이어갑니다."
        }
    }

    private func eraseClosedScope(_ userID: UUID) throws {
        try removeIfPresent(scopeDirectory(userID))
        try erasePreferences(userID)
    }

    private func scopeDirectory(_ userID: UUID) -> URL {
        // A decoded UUID determines the only removable directory; no file path
        // from the marker or signed-in replacement account is accepted.
        accountsDirectory.appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
    }

    private func erasePreferences(_ userID: UUID) throws {
        let id = userID.uuidString.lowercased()
        TrainingSettingsStore(userDefaults: defaults, userID: userID).resetAll()
        defaults.removeObject(forKey: "soom.morningCheckIn.skippedDate." + id)
        defaults.removeObject(forKey: "soom.club.local.persistence.v1." + id)
        defaults.removeObject(forKey: "healthCloudConsentOffered." + id)
        defaults.removeObject(forKey: "auth.profileDisplayName." + id)
        defaults.removeObject(forKey: AppleGrantRegistrationState.key(userID))
        // Retain the durable cleanup marker if scoped preference removal cannot
        // be flushed; otherwise a process termination could strand old settings.
        guard defaults.synchronize() else { throw AccountDeletionCleanupError.preferencePersistenceFailed }
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try removeItem(url) }
    }

    private func loadMarker() throws -> AccountDeletionCleanupMarker? {
        guard FileManager.default.fileExists(atPath: markerURL.path) else { return nil }
        return try JSONDecoder().decode(AccountDeletionCleanupMarker.self, from: Data(contentsOf: markerURL))
    }

    private func save(_ value: AccountDeletionCleanupMarker) throws {
        try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeData(JSONEncoder().encode(value), markerURL)
        var url = markerURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
        marker = value
        errorMessage = nil
        deferredUnconfirmedCleanup = false
    }
}
