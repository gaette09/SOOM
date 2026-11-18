import Foundation
import CryptoKit
import Security
#if canImport(Darwin)
import Darwin
#endif

/// The caller supplies ONLY a previously authorized, allowlisted feed summary
/// and photo payload. This store is not authorization and is disabled unless
/// explicitly instantiated by the reviewed candidate policy.
protocol FeedDiskCacheKeyProvider: Sendable {
    func key(for viewerID: UUID, create: Bool) throws -> SymmetricKey?
    func removeKey(for viewerID: UUID) throws
}

struct FeedDiskCacheScope: Codable, Equatable, Sendable {
    let viewerID: UUID
    let generation: Int
    let policyVersion: Int
    let safetyRevision: Int

    init(viewerID: UUID, generation: Int, policyVersion: Int, safetyRevision: Int = 0) {
        self.viewerID = viewerID; self.generation = generation
        self.policyVersion = policyVersion; self.safetyRevision = safetyRevision
    }
}

struct FeedDiskCacheClock: Codable, Equatable, Sendable {
    let wallDate: Date
    let uptime: TimeInterval
    let bootID: String

    static func current() -> Self {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        let ok = sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0
        // Unknown boot identity cannot restore persisted data.
        return .init(wallDate: Date(), uptime: ProcessInfo.processInfo.systemUptime,
                     bootID: ok ? "\(boot.tv_sec):\(boot.tv_usec)" : "")
    }
}

struct FeedDiskCachePolicy: Sendable {
    /// No production default. Values must be chosen by the caller's policy.
    let maximumAge: TimeInterval
    let maximumFileBytes: Int
    let maximumTotalBytes: Int
    let maximumClockSkew: TimeInterval
    init(maximumAge: TimeInterval, maximumFileBytes: Int = 8 * 1024 * 1024,
         maximumTotalBytes: Int = 16 * 1024 * 1024, maximumClockSkew: TimeInterval = 1) {
        precondition(maximumAge.isFinite && maximumAge > 0)
        precondition(maximumFileBytes > 1024 && maximumTotalBytes >= maximumFileBytes)
        precondition(maximumClockSkew.isFinite && maximumClockSkew >= 0)
        self.maximumAge = maximumAge; self.maximumFileBytes = maximumFileBytes
        self.maximumTotalBytes = maximumTotalBytes; self.maximumClockSkew = maximumClockSkew
    }
}

/// A durable privacy tombstone, separate from process-local request counters.
/// All instances in this process share a lock; no actor hop is needed at logout.
/// The app must complete revoke BEFORE declaring an account transition complete.
final class FeedDiskCacheBoundary: @unchecked Sendable {
    private static let lock = NSLock()
    private static var unavailableDirectories = Set<String>()
    let directory: URL
    init(directory: URL) { self.directory = directory }

    func revoke(viewerID: UUID) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        do { try persist(UUID(), viewerID: viewerID) }
        catch { Self.unavailableDirectories.insert(directory.standardizedFileURL.path); throw error }
    }
    fileprivate func withEpoch<T>(viewerID: UUID, create: Bool,
                                  _ body: (UUID?) throws -> T) throws -> T {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard !Self.unavailableDirectories.contains(directory.standardizedFileURL.path) else {
            throw FeedEncryptedDiskCache.Failure.unavailable
        }
        let url = marker(viewerID)
        let epoch: UUID?
        if FileManager.default.fileExists(atPath: url.path) {
            // Malformed/unreadable markers fail closed; never mint over corruption.
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8), let value = UUID(uuidString: text) else {
                throw FeedEncryptedDiskCache.Failure.unavailable
            }
            epoch = value
        } else if create {
            let value = UUID(); try persist(value, viewerID: viewerID); epoch = value
        } else { epoch = nil }
        return try body(epoch)
    }
    private func marker(_ viewer: UUID) -> URL {
        let hash = SHA256.hash(data: Data(viewer.uuidString.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".epoch")
    }
    private func persist(_ value: UUID, viewerID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        let target = marker(viewerID)
        try Data(value.uuidString.utf8).write(to: target, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
        #endif
        // Do not report a durable logout before both the marker and rename are synced.
        for url in [target, directory] {
            let fd = open(url.path, O_RDONLY)
            guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            let result = fsync(fd), code = errno
            close(fd)
            guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
        }
        var url = directory; var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try url.setResourceValues(flags)
    }
}

actor FeedEncryptedDiskCache {
    struct WriteToken: Equatable, Sendable {
        fileprivate let scope: FeedDiskCacheScope
        fileprivate let epoch: UUID
        fileprivate let durableEpoch: UUID
    }
    private struct Envelope: Codable {
        let formatVersion: Int
        let scope: FeedDiskCacheScope
        let durableEpoch: UUID
        let verifiedAt: FeedDiskCacheClock
        let payload: Data
    }
    enum Failure: Error { case invalidScope, missingKey, oversized, superseded, unavailable }
    private let directory: URL
    nonisolated let boundary: FeedDiskCacheBoundary
    private var activeDurableEpoch: UUID?
    private let keys: any FeedDiskCacheKeyProvider
    private let policy: FeedDiskCachePolicy
    private let clock: @Sendable () -> FeedDiskCacheClock
    private var activeScope: FeedDiskCacheScope?
    private var epoch = UUID()
    private(set) var loadDiagnostic = "idle"

    init(directory: URL, keys: any FeedDiskCacheKeyProvider, policy: FeedDiskCachePolicy,
         clock: @escaping @Sendable () -> FeedDiskCacheClock = { FeedDiskCacheClock.current() },
         boundary: FeedDiskCacheBoundary? = nil) {
        self.boundary = boundary ?? FeedDiskCacheBoundary(directory: directory)
        self.directory = directory; self.keys = keys; self.policy = policy; self.clock = clock
    }

    /// Must be called synchronously before logout/account replacement. Returns
    /// false only if neither durable tombstone nor crypto-erasure could complete.
    /// Auth should still log out; the caller must not claim durable cleanup then.
    nonisolated func revokeBoundarySynchronously(viewerID: UUID) -> Bool {
        do { try boundary.revoke(viewerID: viewerID); return true }
        catch {
            do { try keys.removeKey(for: viewerID); return true }
            catch { return false }
        }
    }

    /// Call only after auth/session has resolved. Switching accounts or safety
    /// generations removes the previous disk entry and fences outstanding work.
    func activate(_ scope: FeedDiskCacheScope, authenticatedViewerID: UUID?) throws -> WriteToken {
        guard authenticatedViewerID == scope.viewerID else { throw Failure.invalidScope }
        if let previous = activeScope, previous != scope {
            epoch = UUID(); activeScope = nil; activeDurableEpoch = nil
            try boundary.revoke(viewerID: previous.viewerID)
            var removalError: Error?
            do { try removeFile(previous.viewerID) } catch { removalError = error }
            try keys.removeKey(for: previous.viewerID)
            if let removalError { throw removalError }
        }
        let persisted = try boundary.withEpoch(viewerID: scope.viewerID, create: true) { $0 }
        guard let persisted else { throw Failure.unavailable }
        activeScope = scope; activeDurableEpoch = persisted
        return WriteToken(scope: scope, epoch: epoch, durableEpoch: persisted)
    }

    func currentToken(for scope: FeedDiskCacheScope) -> WriteToken? {
        guard activeScope == scope, let activeDurableEpoch else { return nil }
        return .init(scope: scope, epoch: epoch, durableEpoch: activeDurableEpoch)
    }

    /// Encoding/encryption/write occur without suspension in this actor. A
    /// token captured before deny/logout cannot write after its tombstone.
    func save(payload: Data, token: WriteToken, verifiedAt: FeedDiskCacheClock) throws {
        guard activeScope == token.scope, token.epoch == epoch else { throw Failure.superseded }
        try boundary.withEpoch(viewerID: token.scope.viewerID, create: false) { current in
        guard current == token.durableEpoch else { throw Failure.superseded }
        guard isFresh(verifiedAt, now: clock()) else { throw Failure.unavailable }
        guard payload.count <= policy.maximumFileBytes / 2 else { throw Failure.oversized }
        try prepareDirectory()
        guard let key = try keys.key(for: token.scope.viewerID, create: true) else { throw Failure.missingKey }
        let envelope = Envelope(formatVersion: 2, scope: token.scope, durableEpoch: token.durableEpoch, verifiedAt: verifiedAt, payload: payload)
        let plaintext = try JSONEncoder().encode(envelope)
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad(token.scope.viewerID))
        guard let combined = sealed.combined, combined.count <= policy.maximumFileBytes else { throw Failure.oversized }
        try combined.write(to: file(token.scope.viewerID), options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                              ofItemAtPath: file(token.scope.viewerID).path)
        #endif
        var url = file(token.scope.viewerID)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try enforceQuota()
        }
    }

    /// A cached payload is a bounded display hint, never a current server grant.
    /// Unknown boot, reboot, clock changes, expiration and auth mismatch fail closed.
    func load(_ scope: FeedDiskCacheScope, authenticatedViewerID: UUID?) throws -> Data? {
        guard authenticatedViewerID == scope.viewerID, activeScope == scope else { loadDiagnostic = "auth-scope"; return nil }
        return try boundary.withEpoch(viewerID: scope.viewerID, create: false) { durableEpoch in
        guard let durableEpoch, durableEpoch == activeDurableEpoch else { loadDiagnostic = "durable-revoked"; return nil }
        let url = file(scope.viewerID)
        guard FileManager.default.fileExists(atPath: url.path) else { loadDiagnostic = "no-file"; return nil }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let bytes = attributes[.size] as? NSNumber, bytes.intValue <= policy.maximumFileBytes,
                  let key = try keys.key(for: scope.viewerID, create: false) else {
                loadDiagnostic = "size-or-key"; try removeFile(scope.viewerID); return nil
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key,
                                             authenticating: aad(scope.viewerID))
            let value = try JSONDecoder().decode(Envelope.self, from: plaintext)
            guard value.formatVersion == 2, value.durableEpoch == durableEpoch,
                  value.scope.viewerID == scope.viewerID, value.scope.policyVersion == scope.policyVersion,
                  value.payload.count <= policy.maximumFileBytes / 2,
                  isFresh(value.verifiedAt, now: clock()) else {
                loadDiagnostic = value.durableEpoch != durableEpoch ? "durable-revoked" : "expired-or-policy-format"
                try removeFile(scope.viewerID); return nil
            }
            loadDiagnostic = "loaded"
            return value.payload
        } catch {
            // Corruption/key loss never permits plaintext fallback.
            loadDiagnostic = "decrypt-or-file-error-\((error as NSError).code)"
            try? removeFile(scope.viewerID)
            return nil
        }
        }
    }

    func invalidate(_ scope: FeedDiskCacheScope) throws {
        guard activeScope == scope else { return }
        epoch = UUID() // Tombstone first, even if file removal fails.
        try boundary.revoke(viewerID: scope.viewerID)
        activeDurableEpoch = try boundary.withEpoch(viewerID: scope.viewerID, create: false) { $0 }
        var removalError: Error?
        do { try removeFile(scope.viewerID) } catch { removalError = error }
        try keys.removeKey(for: scope.viewerID) // Crypto-erasure also fences restart.
        if let removalError { throw removalError }
    }
    func logout() throws {
        let previous = activeScope
        epoch = UUID(); activeScope = nil; activeDurableEpoch = nil
        if let previous {
            try boundary.revoke(viewerID: previous.viewerID)
            // Delete key even when ciphertext cleanup fails: crypto-erasure.
            var removalError: Error?
            do { try removeFile(previous.viewerID) } catch { removalError = error }
            try keys.removeKey(for: previous.viewerID)
            if let removalError { throw removalError }
        }
    }
    private func isFresh(_ verified: FeedDiskCacheClock, now: FeedDiskCacheClock) -> Bool {
        guard !verified.bootID.isEmpty, verified.bootID == now.bootID,
              verified.uptime.isFinite, now.uptime.isFinite else { return false }
        let monotonicAge = now.uptime - verified.uptime
        let wallAge = now.wallDate.timeIntervalSince(verified.wallDate)
        return wallAge.isFinite && monotonicAge >= 0 && wallAge >= 0 &&
            monotonicAge < policy.maximumAge && wallAge < policy.maximumAge &&
            abs(monotonicAge - wallAge) <= policy.maximumClockSkew
    }
    private func aad(_ viewer: UUID) -> Data { Data(("soom.feed.cache.v1:" + viewer.uuidString.lowercased()).utf8) }
    private func file(_ viewer: UUID) -> URL {
        let hash = SHA256.hash(data: Data(viewer.uuidString.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".sealed")
    }
    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    private func removeFile(_ viewer: UUID) throws {
        let url = file(viewer)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func enforceQuota() throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            .filter { $0.pathExtension == "sealed" }
        var values = try urls.map { url -> (URL, Int, Date) in
            let v = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = values.reduce(0) { $0 + $1.1 }
        while total > policy.maximumTotalBytes, !values.isEmpty {
            let oldest = values.removeFirst(); try FileManager.default.removeItem(at: oldest.0); total -= oldest.1
        }
    }
}

/// Keychain adapter is inert until the cache is explicitly used. This task's
/// tests inject in-memory keys and never touch a real account's Keychain.
struct FeedDiskCacheKeychain: FeedDiskCacheKeyProvider {
    let service: String
    init(service: String = "app.soom.feed-bounded-cache.v1") { self.service = service }
    private func query(_ viewer: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: viewer.uuidString.lowercased(), kSecAttrSynchronizable as String: false]
    }
    func key(for viewerID: UUID, create: Bool) throws -> SymmetricKey? {
        var q = query(viewerID); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256)
        var add = query(viewerID)
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        if added == errSecDuplicateItem { return try self.key(for: viewerID, create: false) }
        guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        return key
    }
    func removeKey(for viewerID: UUID) throws {
        let status = SecItemDelete(query(viewerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
