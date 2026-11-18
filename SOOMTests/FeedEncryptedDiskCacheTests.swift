import XCTest
import CryptoKit
@testable import SOOM

private final class SyntheticDiskKeys: FeedDiskCacheKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: SymmetricKey] = [:]
    func key(for viewerID: UUID, create: Bool) throws -> SymmetricKey? {
        lock.lock(); defer { lock.unlock() }
        if let key = values[viewerID] { return key }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256); values[viewerID] = key; return key
    }
    func removeKey(for viewerID: UUID) throws { lock.lock(); defer { lock.unlock() }; values[viewerID] = nil }
}
private final class SyntheticDiskClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = FeedDiskCacheClock(wallDate: Date(timeIntervalSince1970: 1000), uptime: 100, bootID: "synthetic-boot")
    func get() -> FeedDiskCacheClock { lock.lock(); defer { lock.unlock() }; return value }
    func set(wall: Double, uptime: Double, boot: String = "synthetic-boot") {
        lock.lock(); defer { lock.unlock() }
        value = .init(wallDate: Date(timeIntervalSince1970: wall), uptime: uptime, bootID: boot)
    }
}

final class FeedEncryptedDiskCacheTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("soom-synthetic-disk-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func scope(_ viewer: UUID = UUID(), generation: Int = 1, policy: Int = 1) -> FeedDiskCacheScope {
        .init(viewerID: viewer, generation: generation, policyVersion: policy)
    }
    private func store(_ dir: URL, _ keys: SyntheticDiskKeys, _ clock: SyntheticDiskClock,
                       total: Int = 16384) -> FeedEncryptedDiskCache {
        .init(directory: dir, keys: keys,
            policy: .init(maximumAge: 5, maximumFileBytes: 8192, maximumTotalBytes: total), clock: { clock.get() })
    }
    func testEncryptedRoundTripAndAuthenticatedColdRestore() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
        let cache = store(dir, keys, clock), payload = Data("SYNTHETIC-TEXT-AND-PHOTO-BYTES".utf8)
        let token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
        try await cache.save(payload: payload, token: token, verifiedAt: clock.get())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.pathExtension == "sealed" })
        XCTAssertNil(try Data(contentsOf: file).range(of: payload))
        let restarted = store(dir, keys, clock)
        let beforeAuth = try await restarted.load(s, authenticatedViewerID: s.viewerID)
        XCTAssertNil(beforeAuth)
        _ = try await restarted.activate(s, authenticatedViewerID: s.viewerID)
        let loaded = try await restarted.load(s, authenticatedViewerID: s.viewerID)
        XCTAssertEqual(loaded, payload)
        let otherViewer = try await restarted.load(s, authenticatedViewerID: UUID())
        XCTAssertNil(otherViewer)
    }
    func testHardExpiryCannotBeExtendedByResaveOrOfflineRestart() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
        let cache = store(dir, keys, clock), verified = clock.get()
        let token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
        try await cache.save(payload: Data([1]), token: token, verifiedAt: verified)
        clock.set(wall: 1004, uptime: 104)
        try await cache.save(payload: Data([2]), token: token, verifiedAt: verified)
        clock.set(wall: 1005, uptime: 105)
        let result = try await cache.load(s, authenticatedViewerID: s.viewerID)
        XCTAssertNil(result)
        do { try await cache.save(payload: Data([3]), token: token, verifiedAt: verified); XCTFail("Extended TTL") } catch { }
    }
    func testDenyTombstoneRejectsLateWriteAndPurgesBytes() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
        let cache = store(dir, keys, clock), token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
        try await cache.save(payload: Data([1]), token: token, verifiedAt: clock.get())
        try await cache.invalidate(s)
        do { try await cache.save(payload: Data([2]), token: token, verifiedAt: clock.get()); XCTFail("Late write") } catch { }
        let loaded = try await cache.load(s, authenticatedViewerID: s.viewerID)
        XCTAssertNil(loaded); XCTAssertNil(try keys.key(for: s.viewerID, create: false))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasSuffix(".sealed") })
    }
    func testAccountSwitchLogoutAndGenerationCannotRestoreOldData() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), a = scope(), b = scope()
        let cache = store(dir, keys, clock), old = try await cache.activate(a, authenticatedViewerID: a.viewerID)
        try await cache.save(payload: Data([1]), token: old, verifiedAt: clock.get())
        let new = try await cache.activate(b, authenticatedViewerID: b.viewerID)
        let wrong = try await cache.load(a, authenticatedViewerID: a.viewerID)
        XCTAssertNil(wrong); XCTAssertNil(try keys.key(for: a.viewerID, create: false))
        do { try await cache.save(payload: Data([2]), token: old, verifiedAt: clock.get()); XCTFail("Old account") } catch { }
        try await cache.save(payload: Data([3]), token: new, verifiedAt: clock.get())
        try await cache.logout()
        XCTAssertNil(try keys.key(for: b.viewerID, create: false))
        do { try await cache.save(payload: Data([4]), token: new, verifiedAt: clock.get()); XCTFail("Logged out") } catch { }
        _ = try await cache.activate(scope(a.viewerID, generation: 2), authenticatedViewerID: a.viewerID)
        let oldGeneration = try await cache.load(a, authenticatedViewerID: a.viewerID)
        XCTAssertNil(oldGeneration)
    }
    func testClockRollbackDriftAndRebootFailClosed() async throws {
        for change in [(999.0, 101.0, "synthetic-boot"), (1004.0, 101.0, "synthetic-boot"), (1001.0, 1.0, "new-boot"), (1001.0, 101.0, "")] {
            let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
            let cache = store(dir, keys, clock), token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
            try await cache.save(payload: Data([1]), token: token, verifiedAt: clock.get())
            clock.set(wall: change.0, uptime: change.1, boot: change.2)
            let loaded = try await cache.load(s, authenticatedViewerID: s.viewerID)
            XCTAssertNil(loaded)
        }
    }
    func testCorruptionAndDifferentPolicyFailClosed() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
        let cache = store(dir, keys, clock), token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
        try await cache.save(payload: Data([1]), token: token, verifiedAt: clock.get())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.pathExtension == "sealed" })
        var bytes = try Data(contentsOf: file); bytes[bytes.count / 2] ^= 0xFF; try bytes.write(to: file)
        let corrupted = try await cache.load(s, authenticatedViewerID: s.viewerID)
        XCTAssertNil(corrupted)
        try await cache.save(payload: Data([2]), token: token, verifiedAt: clock.get())
        let restarted = store(dir, keys, clock), changed = scope(s.viewerID, policy: 2)
        _ = try await restarted.activate(changed, authenticatedViewerID: changed.viewerID)
        let wrongPolicy = try await restarted.load(changed, authenticatedViewerID: changed.viewerID)
        XCTAssertNil(wrongPolicy)
    }
    func testDurableEpochAllowsColdRuntimeRevisionChange() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
        let cache = store(dir, keys, clock)
        let token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
        try await cache.save(payload: Data([1]), token: token, verifiedAt: clock.get())
        let restarted = store(dir, keys, clock)
        let revised = FeedDiskCacheScope(viewerID: s.viewerID, generation: s.generation,
                                        policyVersion: s.policyVersion, safetyRevision: 1)
        _ = try await restarted.activate(revised, authenticatedViewerID: revised.viewerID)
        let loaded = try await restarted.load(revised, authenticatedViewerID: revised.viewerID)
        XCTAssertEqual(loaded, Data([1]))
    }
    func testSynchronousLogoutTombstoneSurvivesWithoutAsyncCleanup() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
        let cache = store(dir, keys, clock)
        let token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
        try await cache.save(payload: Data([1]), token: token, verifiedAt: clock.get())
        XCTAssertTrue(cache.revokeBoundarySynchronously(viewerID: s.viewerID))
        // Model SIGKILL immediately after the synchronous hook: no actor logout,
        // no file deletion and no further work from the original process.
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasSuffix(".sealed") })
        let restarted = store(dir, keys, clock)
        let next = FeedDiskCacheScope(viewerID: s.viewerID, generation: 99, policyVersion: 1, safetyRevision: 88)
        _ = try await restarted.activate(next, authenticatedViewerID: s.viewerID)
        let restored = try await restarted.load(next, authenticatedViewerID: s.viewerID)
        XCTAssertNil(restored)
        do { try await cache.save(payload: Data([2]), token: token, verifiedAt: clock.get()); XCTFail("Late save crossed durable logout") } catch { }
    }
    func testTombstoneWriteFailureCryptoErasesAndLatchesClosed() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
        let cache = store(dir, keys, clock)
        let token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
        try await cache.save(payload: Data([1]), token: token, verifiedAt: clock.get())
        let marker = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.pathExtension == "epoch" })
        try FileManager.default.removeItem(at: marker)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
        XCTAssertTrue(cache.revokeBoundarySynchronously(viewerID: s.viewerID))
        XCTAssertNil(try keys.key(for: s.viewerID, create: false))
        do { _ = try await cache.load(s, authenticatedViewerID: s.viewerID); XCTFail("Failed disk must latch closed") } catch { }
        do { _ = try await cache.activate(s, authenticatedViewerID: s.viewerID); XCTFail("Latch cannot be reset by activation") } catch { }
    }
    func testCorruptDurableMarkerCannotRestoreOrSave() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
        let cache = store(dir, keys, clock)
        let token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
        try await cache.save(payload: Data([1]), token: token, verifiedAt: clock.get())
        let marker = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.pathExtension == "epoch" })
        try Data("invalid".utf8).write(to: marker)
        do { _ = try await cache.load(s, authenticatedViewerID: s.viewerID); XCTFail("Corruption must fail closed") } catch { }
        do { try await cache.save(payload: Data([2]), token: token, verifiedAt: clock.get()); XCTFail("Corrupt marker cannot save") } catch { }
    }
    func testEightMiBPhotoJSONCanBeEncryptedWithinProductionCandidateQuota() async throws {
        struct Summary: Codable, Equatable { let title: String; let photos: [String: Data] }
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock(), s = scope()
        let cache = FeedEncryptedDiskCache(directory: dir, keys: keys,
            policy: .init(maximumAge: 5, maximumFileBytes: 24 * 1024 * 1024,
                          maximumTotalBytes: 24 * 1024 * 1024), clock: { clock.get() })
        let summary = Summary(title: "SYNTHETIC", photos: ["synthetic-photo": Data(repeating: 0xAA, count: 8 * 1024 * 1024)])
        let payload = try JSONEncoder().encode([summary])
        let token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
        try await cache.save(payload: payload, token: token, verifiedAt: clock.get())
        let loaded = try await cache.load(s, authenticatedViewerID: s.viewerID)
        XCTAssertEqual(try JSONDecoder().decode([Summary].self, from: XCTUnwrap(loaded)), [summary])
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
        let total = try files.reduce(0) { try $0 + $1.resourceValues(forKeys: [.fileSizeKey]).fileSize! }
        XCTAssertLessThanOrEqual(total, 24 * 1024 * 1024)
    }
    func testOversizedPayloadAndGlobalQuota() async throws {
        let dir = try directory(), keys = SyntheticDiskKeys(), clock = SyntheticDiskClock()
        for _ in 0..<4 {
            let s = scope(), cache = store(dir, keys, clock, total: 8192)
            let token = try await cache.activate(s, authenticatedViewerID: s.viewerID)
            do { try await cache.save(payload: Data(repeating: 1, count: 4097), token: token, verifiedAt: clock.get()); XCTFail("Oversized") } catch { }
            try await cache.save(payload: Data(repeating: 2, count: 3000), token: token, verifiedAt: clock.get())
        }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
        let total = try files.reduce(0) { try $0 + $1.resourceValues(forKeys: [.fileSizeKey]).fileSize! }
        XCTAssertLessThanOrEqual(total, 8192)
    }
}

#if canImport(UIKit)
@MainActor final class FeedStaleDiskIntegrationTests: XCTestCase {
    func testApprovedBundlePolicyIsEnabledWithoutTestOverrides() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SOOMFeedStaleCacheEnabled") as? Bool, true)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SOOMFeedCacheStorageSeconds") as? Double, 86_400)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SOOMFeedCacheDisplaySeconds") as? Double, 5)
        XCTAssertEqual(FeedStaleSummaryCache.configuredMaximumAge, 86_400)
        XCTAssertEqual(FeedStaleSummaryCache.configuredDisplayGrace, 5)
    }

    private func fixture() throws -> (URL, FeedEncryptedDiskCache, FeedStaleSummaryScope, FeedStaleSummarySnapshot) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("soom-synthetic-integration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let scope = FeedStaleSummaryScope(viewerID: UUID(), generation: 1, safetyRevision: 0, policyVersion: 1)
        let row = FeedStaleSummarySnapshot(id: UUID(), ownerID: UUID(), canonicalID: UUID(), sport: "running",
            activityAt: "2026-11-18T00:00:00Z", durationSeconds: 60, distanceMeters: 100,
            projectionRevision: 1, title: "SYNTHETIC", author: "SYNTHETIC", metrics: [],
            validatedAt: Date(), validatedUptime: ProcessInfo.processInfo.systemUptime,
            photoVersions: [:], photoOrder: [], photos: [:])
        let disk = FeedEncryptedDiskCache(directory: url, keys: SyntheticDiskKeys(), policy: .init(maximumAge: 5))
        return (url, disk, scope, row)
    }
    private func seed(_ disk: FeedEncryptedDiskCache, _ scope: FeedStaleSummaryScope, _ row: FeedStaleSummarySnapshot) async throws {
        let diskScope = FeedDiskCacheScope(viewerID: scope.viewerID, generation: 0,
                                          policyVersion: scope.policyVersion, safetyRevision: 0)
        let token = try await disk.activate(diskScope, authenticatedViewerID: scope.viewerID)
        try await disk.save(payload: JSONEncoder().encode([row]), token: token,
            verifiedAt: .init(wallDate: row.validatedAt, uptime: row.validatedUptime, bootID: FeedDiskCacheClock.current().bootID))
    }
    func testColdRestoreShowsOnlyBoundedSummaryAndWrongScopeSeesNothing() async throws {
        let (_, disk, scope, row) = try fixture()
        try await seed(disk, scope, row)
        let memory = FeedStaleSummaryCache(maximumAge: 5, observeSafety: false, disk: disk)
        await memory.restore(viewerID: scope.viewerID, generation: scope.generation, safetyRevision: scope.safetyRevision)
        XCTAssertEqual(memory.allSnapshots(scope: scope), [row])
        let wrong = FeedStaleSummaryScope(viewerID: UUID(), generation: 1, safetyRevision: 0, policyVersion: 1)
        XCTAssertTrue(memory.allSnapshots(scope: wrong).isEmpty)
        XCTAssertTrue(memory.allSnapshots(scope: scope, now: Date().addingTimeInterval(6),
                                           uptime: ProcessInfo.processInfo.systemUptime + 6).isEmpty)
    }
    func testClearCannotBeUndoneByPendingRestore() async throws {
        let (_, disk, scope, row) = try fixture()
        try await seed(disk, scope, row)
        let memory = FeedStaleSummaryCache(maximumAge: 5, observeSafety: false, disk: disk)
        let pending = Task { await memory.restore(viewerID: scope.viewerID, generation: 1, safetyRevision: 0) }
        await Task.yield()
        memory.clear()
        await pending.value
        XCTAssertEqual(memory.count, 0)
        XCTAssertTrue(memory.allSnapshots(scope: scope).isEmpty)
    }
    func testExpiredOldCardDoesNotPreventFreshCardPersistenceAndRestore() async throws {
        let (_, disk, scope, old) = try fixture()
        let memory = FeedStaleSummaryCache(maximumAge: 5, observeSafety: false, disk: disk)
        let context = FeedReturnBatchContext(viewerID: scope.viewerID, accountGeneration: 1,
                                            safetyRevision: 0, returnEpoch: 1)
        func batch(_ row: AccountActivityFeedRow) -> FeedReturnBatchPresentation {
            let grant = FeedReturnCardGrant(id: row.cardID, row: row, author: nil, authorRevision: nil,
                avatarObject: nil, photos: [], photoObjects: [:], photosAvailable: false, socialStatus: nil)
            return .init(id: UUID(), context: context, phase: .ready, grants: [row.cardID: grant])
        }
        memory.accept(batch(old.row), now: Date().addingTimeInterval(-6),
                      uptime: ProcessInfo.processInfo.systemUptime - 6)
        let fresh = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(), sport: "running",
            activityAt: "2026-11-18T00:01:00Z", durationSeconds: 120, distanceMeters: 200,
            revision: 1, readPolicy: .profileOnlyV2)
        memory.accept(batch(fresh))
        let diskScope = FeedDiskCacheScope(viewerID: scope.viewerID, generation: 0, policyVersion: 1, safetyRevision: 0)
        var persisted: [FeedStaleSummarySnapshot] = []
        for _ in 0..<100 {
            if let bytes = try await disk.load(diskScope, authenticatedViewerID: scope.viewerID) {
                persisted = try JSONDecoder().decode([FeedStaleSummarySnapshot].self, from: bytes)
                if persisted.map(\.id) == [fresh.cardID] { break }
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(persisted.map(\.id), [fresh.cardID])
        let restored = FeedStaleSummaryCache(maximumAge: 5, observeSafety: false, disk: disk)
        await restored.restore(viewerID: scope.viewerID, generation: 1, safetyRevision: 0)
        XCTAssertEqual(restored.allSnapshots(scope: scope).map(\.id), [fresh.cardID])
    }
    func testDisabledCandidateDoesNotReadDisk() async throws {
        let (_, disk, scope, row) = try fixture()
        try await seed(disk, scope, row)
        let memory = FeedStaleSummaryCache(maximumAge: nil, observeSafety: false, disk: disk)
        await memory.restore(viewerID: scope.viewerID, generation: 1, safetyRevision: 0)
        XCTAssertFalse(memory.enabled)
        XCTAssertEqual(memory.count, 0)
    }
}
#endif
