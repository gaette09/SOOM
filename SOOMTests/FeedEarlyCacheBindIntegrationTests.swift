import XCTest
import CryptoKit
import UIKit
@testable import SOOM

private final class EarlyBindKeys: FeedDiskCacheKeyProvider, @unchecked Sendable {
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
@MainActor private final class EarlyBindPrivacyService: AccountPrivacyServing {
    let viewerID: UUID?
    var held = true
    var started = 0
    init(_ viewer: UUID) { viewerID = viewer }
    func fetch() async throws -> AccountPrivacyReceipt {
        started += 1
        while held { try Task.checkCancellation(); await Task.yield() }
        return .init(enabled: true, accountScope: .publicAccount, workoutDefault: .publicPost,
                     revision: 1, policyVersion: 2)
    }
    func previewCapability() async throws -> AccountActivityPreviewCapability? {
        started += 1
        while held { try Task.checkCancellation(); await Task.yield() }
        return .init(version: 1, viewer_id: viewerID!, enabled: true, owner_rules_accepted: true,
                     account_scope: .publicAccount, scope_revision: 1, share_measurements: false)
    }
    func save(owner: UUID, scope: AccountAudience, defaultWorkout: FeedPostVisibility,
              expectedRevision: Int64, shareMeasurements: Bool) async throws -> AccountPrivacyReceipt {
        throw CommunitySafetyError.unavailable
    }
}

/// Run serially on the synthetic test host. Never mutate a signed-in real viewer.
@MainActor final class FeedEarlyCacheBindIntegrationTests: XCTestCase {
    func testColdBindHeldPrivacyThenApprovalPreservesRealEncryptedCacheAndRelationshipChangeRevokes() async throws {
        let safety = CommunitySafetyStore.shared
        let originalViewer = safety.viewerID
        guard originalViewer == nil || originalViewer == ReviewDemoMode.userID else {
            throw XCTSkip("Never reset a real signed-in viewer")
        }
        // The reserved built-in demo identity is synthetic. No other existing
        // viewer may be reset by this fixture, even when a test flag is present.
        if originalViewer == ReviewDemoMode.userID { safety.setViewerID(nil) }
        defer {
            if originalViewer == ReviewDemoMode.userID { safety.configureForDemo() }
            else { safety.setViewerID(nil) }
        }
        let viewer = UUID(), cardID = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("soom-early-bind-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys = EarlyBindKeys()
        let diskPolicy = FeedDiskCachePolicy(maximumAge: 86_400)
        let seed = FeedEncryptedDiskCache(directory: directory, keys: keys, policy: diskPolicy)
        let savedClock = FeedDiskCacheClock.current()
        let photo = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.jpegData(compressionQuality: 0.8))
        let snapshot = FeedStaleSummarySnapshot(id: cardID, ownerID: UUID(), canonicalID: UUID(),
            sport: "running", activityAt: "2020-01-01T00:00:00Z", durationSeconds: 60,
            distanceMeters: 100, projectionRevision: 1, title: "Synthetic cached title",
            author: "Synthetic author", metrics: [], validatedAt: savedClock.wallDate,
            validatedUptime: savedClock.uptime, photoVersions: ["synthetic-photo":"v1"], photoOrder: ["synthetic-photo"], photos: ["synthetic-photo":photo])
        let persistedScope = FeedDiskCacheScope(viewerID: viewer, generation: 0, policyVersion: 1)
        let token = try await seed.activate(persistedScope, authenticatedViewerID: viewer)
        try await seed.save(payload: JSONEncoder().encode([snapshot]), token: token, verifiedAt: savedClock)
        // A restarted cache actor has no activeScope. Initial bind's clear/logout
        // must not revoke a prior encrypted snapshot before its viewer is restored.
        let disk = FeedEncryptedDiskCache(directory: directory, keys: keys, policy: diskPolicy)
        let cache = FeedStaleSummaryCache(maximumAge: 86_400, displayGrace: 5, observeSafety: true, disk: disk)
        defer {
            safety.setViewerID(nil)
            UserDefaults.standard.removeObject(forKey: "SOOM.workoutAudience.v1.\(viewer.uuidString.lowercased())")
            try? FileManager.default.removeItem(at: directory)
        }
        safety.configure(client: nil)
        safety.setViewerID(viewer)
        let service = EarlyBindPrivacyService(viewer)
        let model = AccountPrivacyModel(owner: viewer, service: service, socialState: safety,
                                        onboardingComplete: true, profileOnlyRules: true)
        let request = Task { await model.load() }
        defer { service.held = false; request.cancel() }
        for _ in 0..<1000 { if service.started == 2 { break }; await Task.yield() }
        XCTAssertEqual(service.started, 2)
        XCTAssertFalse(safety.canUseSocial)
        XCTAssertEqual(model.earlyCacheVerification, .checking)
        let before = FeedStaleSummaryScope(viewerID: viewer, generation: safety.accountGeneration,
                                          safetyRevision: safety.revision, policyVersion: 1)
        cache.beginEarlyDisplay(scope: before)
        await cache.restore(viewerID: viewer, generation: before.generation, safetyRevision: before.safetyRevision)
        XCTAssertEqual(cache.snapshot(cardID: cardID, scope: before)?.title, "Synthetic cached title",
                       "Initial configure/bind/pending verification must not erase the prior disk cache")
        let restoredPhoto = try XCTUnwrap(cache.snapshot(cardID: cardID, scope: before)?.photos["synthetic-photo"])
        XCTAssertEqual(restoredPhoto, photo)
        XCTAssertNotNil(UIImage(data: restoredPhoto), "Cold restored bytes must be a decodable photograph")
        let beforeApproval = Date(), beforeApprovalUptime = ProcessInfo.processInfo.systemUptime
        service.held = false; await request.value
        XCTAssertTrue(safety.canUseSocial)
        XCTAssertEqual(model.earlyCacheVerification, .authorized)
        let after = FeedStaleSummaryScope(viewerID: viewer, generation: safety.accountGeneration,
                                         safetyRevision: safety.revision, policyVersion: 1)
        XCTAssertNotEqual(before.safetyRevision, after.safetyRevision)
        XCTAssertNotNil(cache.snapshot(cardID: cardID, scope: after), "Approval rebind preserves display-only bytes")
        cache.beginDisplayWindow(scope: after, returnEpoch: 777, now: beforeApproval.addingTimeInterval(4), uptime: beforeApprovalUptime + 4)
        XCTAssertNil(cache.snapshot(cardID: cardID, scope: after, now: beforeApproval.addingTimeInterval(6), uptime: beforeApprovalUptime + 6))
        safety.invalidateRelationships()
        XCTAssertEqual(cache.count, 0, "Non-verification changes keep destructive invalidation")
        _ = try await seed.activate(persistedScope, authenticatedViewerID: viewer)
        let revoked = try await seed.load(persistedScope, authenticatedViewerID: viewer)
        XCTAssertNil(revoked, "Relationship change durably fences the encrypted snapshot")
    }
}
