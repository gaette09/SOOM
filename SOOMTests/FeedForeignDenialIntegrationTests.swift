import XCTest
import Combine
import CoreGraphics
@testable import SOOM

/// No network, view hosting or persisted data. Exercises the real adapter/store/cache bridge.
@MainActor final class FeedForeignDenialIntegrationTests: XCTestCase {
    @MainActor private final class DecodeGate {
        let image: CGImage
        private(set) var started = false
        private(set) var resumed = false
        private var continuation: CheckedContinuation<CGImage, Never>?
        init(_ image: CGImage) { self.image = image }
        func waitIgnoringCancellation() async -> CGImage {
            started = true
            if resumed { return image }
            return await withCheckedContinuation { continuation = $0 }
        }
        func release() {
            guard !resumed else { return }
            resumed = true; continuation?.resume(returning: image); continuation = nil
        }
    }
    private struct Fixture {
        let context: FeedReturnBatchContext
        let rows: [AccountActivityFeedRow]
        let sources: [UUID]
        let photos: [UUID]
        func wire(denying denied: Set<UUID> = []) throws -> Data {
            let entries: [[String: Any]] = rows.enumerated().map { index, row in
                if denied.contains(row.cardID) { return ["card_id": row.cardID.uuidString, "allowed": false] }
                let path = WorkoutPhotoPolicy.path(ownerID: row.ownerID, postID: sources[index], photoID: photos[index])
                let summary: [String: Any] = ["card_id":row.cardID.uuidString,"canonical_id":row.canonicalID.uuidString,
                    "owner_id":row.ownerID.uuidString,"sport":row.sport,"activity_at":row.activityAt,
                    "duration_seconds":row.durationSeconds,"distance_meters":row.distanceMeters ?? 0,"revision":row.revision]
                let metadata: [String: Any] = ["version":2,"viewer_id":context.viewerID.uuidString,
                    "card_id":row.cardID.uuidString,"owner_id":row.ownerID.uuidString,"canonical_id":row.canonicalID.uuidString,
                    "projection_revision":row.revision,"profile_revision":1,"backing":"legacy",
                    "source_id":sources[index].uuidString,"bucket":"workout-photos","release_ready":true,
                    "rows":[["id":photos[index].uuidString,"card_id":row.cardID.uuidString,"storage_path":path,"sort_order":0,
                        "object":["object_id":photos[index].uuidString,"version":"synthetic-v1","size":4]]]]
                return ["card_id":row.cardID.uuidString,"allowed":true,"summary":summary,"author":NSNull(),
                    "author_revision":NSNull(),"avatar":NSNull(),"photos":metadata,"social":NSNull(),"social_revision":NSNull()]
            }
            return try JSONSerialization.data(withJSONObject:["version":2,"viewer_id":context.viewerID.uuidString,
                "scope":"home","account_generation":context.accountGeneration,"safety_revision":context.safetyRevision,
                "return_epoch":context.returnEpoch,"release_ready":true,"rows":entries,
                "needs_page_reload":false,"has_more":false,"membership_revision":String(repeating:"a",count:64)])
        }
    }
    private func safeSyntheticHost() -> Bool {
        guard ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
              ProcessInfo.processInfo.environment["SOOM_SKELETON_QA"] == "1",
              ProcessInfo.processInfo.environment["SOOM_SKELETON_STYLE"] == "value",
              ReviewDemoMode.isActive, ReviewDemoController.shared.runtime != nil else {
            XCTFail("Explicit isolated synthetic app-host configuration required"); return false
        }
        let currentKeys = ["SOOMSupabaseURL", "SOOMSupabaseAnonKey"]
        let legacyKeys = ["SOOM_SUPABASE_URL", "SOOM_SUPABASE_ANON_KEY"]
        guard currentKeys.allSatisfy({ (Bundle.main.object(forInfoDictionaryKey: $0) as? String) == "" }),
              legacyKeys.allSatisfy({ key in
                  guard let value = Bundle.main.object(forInfoDictionaryKey: key) else { return true }
                  return (value as? String) == ""
              }) else {
            XCTFail("Current service keys must be empty strings; legacy keys must be absent or empty strings"); return false
        }
        let environment = AuthEnvironmentLoader().load()
        guard environment.supabaseURL == nil, environment.supabaseAnonKey == nil,
              !environment.isSupabaseConfigured,
              !SupabaseAuthConfiguration.from(environment: environment).isConfigured else {
            XCTFail("Loaded host service configuration must be empty"); return false
        }
        guard SupabaseClientProvider(environment: environment).makeClient() == nil else {
            XCTFail("Configured real client is not permitted"); return false
        }
        return true
    }
    private enum BoundaryFailure: Error { case decodeNotStarted, hostScopeChanged, sharedCacheBusy }
    private func record(_ value: [String: Any], name: String) {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func drain(_ flights: [Task<CGImage, Error>], gates: [DecodeGate], cancel: Bool) async -> Int {
        gates.forEach { $0.release() }
        if cancel { flights.forEach { $0.cancel() } }
        var errors = 0
        for flight in flights { do { _ = try await flight.value } catch { errors += 1 } }
        return errors
    }
    private func fixture() -> Fixture {
        let safety = CommunitySafetyStore.shared
        let context = FeedReturnBatchContext(viewerID: ReviewDemoMode.userID,
            accountGeneration: safety.accountGeneration, safetyRevision: safety.revision, returnEpoch: 3)
        let rows = (0..<2).map { _ in AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(),
            sport: "running", activityAt: "2026-01-01T00:00:00Z", durationSeconds: 60, distanceMeters: 100,
            revision: 1, readPolicy: .profileOnlyV2) }
        return .init(context: context, rows: rows, sources: [UUID(), UUID()], photos: [UUID(), UUID()])
    }
    private func currentContext(_ expected: FeedReturnBatchContext) -> FeedReturnBatchContext? {
        let safety = CommunitySafetyStore.shared
        guard ReviewDemoMode.isActive, safety.viewerID == expected.viewerID,
              safety.accountGeneration == expected.accountGeneration, safety.revision == expected.safetyRevision else { return nil }
        return expected
    }
    private func pixel() throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data([32, 96, 160, 255]) as CFData))
        return try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    func testAdapterDenialPublishRevokesSharedPixelsAndRejectsTwoLateDecodes() async throws {
        executionTimeAllowance = 30
        guard safeSyntheticHost() else { return }
        let f = fixture(), store = FeedReturnBatchStore(), image = try pixel()
        let cache = WorkoutPhotoImageCache.shared.pixels
        guard currentContext(f.context) != nil else { throw BoundaryFailure.hostScopeChanged }
        guard cache.inFlightCount == 0 else { throw BoundaryFailure.sharedCacheBusy }
        let ownedResources = f.rows.indices.map { WorkoutPhotoPolicy.path(ownerID: f.rows[$0].ownerID, postID: f.sources[$0], photoID: f.photos[$0]) }
        defer { ownedResources.forEach { cache.invalidateResource($0) } }
        let id = store.begin(context: f.context), data = try f.wire()
        let adapter = FeedReturnBatchAdapter(read: { _ in data }, current: { self.currentContext(f.context) })
        let ready = try await adapter.load(cardIDs: f.rows.map(\.cardID), loadedRows: f.rows, context: f.context, id: id)
        XCTAssertTrue(store.publish(ready, expectedID: id))
        let target = try XCTUnwrap(ready.grants[f.rows[0].cardID]), control = try XCTUnwrap(ready.grants[f.rows[1].cardID])
        let photo = try XCTUnwrap(target.photos.first), controlPhoto = try XCTUnwrap(control.photos.first)
        let object = try XCTUnwrap(target.photoObjects[photo.cacheKey]), controlObject = try XCTUnwrap(control.photoObjects[controlPhoto.cacheKey])
        let version = try XCTUnwrap(object.cacheVersionToken), controlVersion = try XCTUnwrap(controlObject.cacheVersionToken)
        let authority = FeedLinkedCardAuthority(context: f.context, batchID: id, grantID: target.id, row: target.row)
        let scope = SOOMMediaCacheScope(viewerID: f.context.viewerID, accountGeneration: f.context.accountGeneration, safetyRevision: f.context.safetyRevision)
        _ = try await cache.value(for: photo.cacheKey, scope: scope, requestOwner: "seed", variant: "seed", authorize: { version }, load: { (image, 4) })
        _ = try await cache.value(for: controlPhoto.cacheKey, scope: scope, requestOwner: "control", variant: "seed", authorize: { controlVersion }, load: { (image, 4) })
        let gates = [DecodeGate(image), DecodeGate(image)]
        defer { gates.forEach { $0.release() } }
        let flights = gates.enumerated().map { index, gate in
            Task { @MainActor in
                try await cache.value(for: photo.cacheKey, scope: scope, requestOwner: "late-owner-\(index)", variant: "late-variant-\(index)", authorize: {
                    guard self.currentContext(f.context) != nil, store.isCurrent(authority: authority, context: f.context) else { throw CancellationError() }
                    return version
                }, load: { let pixels = await gate.waitIgnoringCancellation(); return (pixels, 4) })
            }
        }
        var report: [String: Any] = ["started": 0, "lateErrors": 0, "tasksReaped": 0,
            "quietStartup": true, "scopeBeforeSeed": true, "phaseFailure": NSNull()]
        var phase = "waiting-for-both-decodes"
        do {
        for _ in 0..<100 {
            if gates.allSatisfy({ $0.started }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        report["started"] = gates.filter { $0.started }.count
        guard gates.allSatisfy({ $0.started }) else { throw BoundaryFailure.decodeNotStarted }
        guard currentContext(f.context) != nil else { throw BoundaryFailure.hostScopeChanged }
        report["scopeBeforeDenial"] = true
        phase = "adapter-denial-then-store-publish"
        var invalidated: [String] = [], observerSawPreCommit = false
        let deniedID = store.begin(context: f.context)
        let observer = WorkoutPhotoImageCache.shared.resourceInvalidations.sink { key in
            invalidated.append(key)
            // Revoke callback precedes presentation assignment. This is the original ordering.
            if key == photo.cacheKey { observerSawPreCommit = store.presentation?.id == deniedID && store.presentation?.phase == .pending }
        }
        defer { observer.cancel() }
        let denialData = try f.wire(denying: [target.row.cardID])
        let denialAdapter = FeedReturnBatchAdapter(read: { _ in denialData }, current: { self.currentContext(f.context) })
        let denied = try await denialAdapter.load(cardIDs: f.rows.map(\.cardID), loadedRows: f.rows, context: f.context, id: deniedID)
        XCTAssertTrue(store.publish(denied, expectedID: deniedID))
        report["realInvalidations"] = invalidated.filter { $0 == photo.cacheKey }.count
        report["observerSawPreCommitPending"] = observerSawPreCommit
        report["oldAuthorityRejected"] = !store.isCurrent(authority: authority, context: f.context)
        report["targetResidentMiss"] = cache.residentValue(for: photo.cacheKey, scope: scope, version: version, variant: "seed", allowAlternateVariant: true) == nil
        report["controlPreserved"] = cache.residentValue(for: controlPhoto.cacheKey, scope: scope, version: controlVersion, variant: "seed") != nil
        XCTAssertEqual(invalidated, [photo.cacheKey]); XCTAssertTrue(observerSawPreCommit)
        if case .denied? = store.presentation?.cardAccess(rowID: target.row.cardID) {} else { XCTFail("Denied card remained authorized") }
        XCTAssertFalse(store.isCurrent(authority: authority, context: f.context))
        XCTAssertFalse(store.publish(ready, expectedID: id), "Old batch cannot restore its grant")
        XCTAssertNil(cache.residentValue(for: photo.cacheKey, scope: scope, version: version, variant: "seed", allowAlternateVariant: true))
        XCTAssertNotNil(cache.residentValue(for: controlPhoto.cacheKey, scope: scope, version: controlVersion, variant: "seed"))
        XCTAssertNotNil(currentContext(f.context))
        phase = "releasing-and-reaping-late-decodes"
        let lateErrors = await drain(flights, gates: gates, cancel: false)
        report["lateErrors"] = lateErrors; report["tasksReaped"] = flights.count
        XCTAssertEqual(lateErrors, 2, "Both late pixels must be rejected")
        XCTAssertTrue(gates.allSatisfy { $0.resumed })
        XCTAssertNotNil(currentContext(f.context))
        XCTAssertNil(cache.residentValue(for: photo.cacheKey, scope: scope, version: version, allowAlternateVariant: true))
        XCTAssertNotNil(cache.residentValue(for: controlPhoto.cacheKey, scope: scope, version: controlVersion, variant: "seed"))
        report["scopeAfterReap"] = currentContext(f.context) != nil
        report["continuationsReleased"] = gates.filter { $0.resumed }.count
        report["targetAfterLateResidentMiss"] = cache.residentValue(for: photo.cacheKey, scope: scope, version: version, allowAlternateVariant: true) == nil
        report["controlAfterLatePreserved"] = cache.residentValue(for: controlPhoto.cacheKey, scope: scope, version: controlVersion, variant: "seed") != nil
        observer.cancel()
        ownedResources.forEach { cache.invalidateResource($0) }
        report["ownedCleanupResidentCount"] = [
            cache.residentValue(for: photo.cacheKey, scope: scope, version: version, allowAlternateVariant: true),
            cache.residentValue(for: controlPhoto.cacheKey, scope: scope, version: controlVersion, variant: "seed", allowAlternateVariant: true)
        ].compactMap { $0 }.count
        record(report, name: "foreign denial bridge result")
        } catch {
            report["phaseFailure"] = phase
            report["error"] = String(describing: error)
            report["lateErrorsDuringFailureCleanup"] = await drain(flights, gates: gates, cancel: true)
            report["tasksReaped"] = flights.count
            report["continuationsReleased"] = gates.filter { $0.resumed }.count
            ownedResources.forEach { cache.invalidateResource($0) }
            record(report, name: "foreign denial bridge failure")
            throw error
        }
    }
    /// Diagnostic boundary: pruning bookkeeping is not a blanket physical cache revoke.
    func testPrunedMetadataDenialClosesAuthorityWithoutClaimingPhysicalRevoke() async throws {
        executionTimeAllowance = 30
        guard safeSyntheticHost() else { return }
        let f = fixture(), store = FeedReturnBatchStore(), image = try pixel()
        let cache = WorkoutPhotoImageCache.shared.pixels
        guard currentContext(f.context) != nil else { throw BoundaryFailure.hostScopeChanged }
        guard cache.inFlightCount == 0 else { throw BoundaryFailure.sharedCacheBusy }
        let ownedResources = f.rows.indices.map { WorkoutPhotoPolicy.path(ownerID: f.rows[$0].ownerID, postID: f.sources[$0], photoID: f.photos[$0]) }
        defer { ownedResources.forEach { cache.invalidateResource($0) } }
        let id = store.begin(context: f.context), data = try f.wire()
        let reader = FeedReturnBatchAdapter(read: { _ in data }, current: { self.currentContext(f.context) })
        let ready = try await reader.load(cardIDs: f.rows.map(\.cardID), loadedRows: f.rows, context: f.context, id: id)
        XCTAssertTrue(store.publish(ready, expectedID: id))
        let grant = try XCTUnwrap(ready.grants[f.rows[0].cardID]), photo = try XCTUnwrap(grant.photos.first)
        let object = try XCTUnwrap(grant.photoObjects[photo.cacheKey]), version = try XCTUnwrap(object.cacheVersionToken)
        let scope = SOOMMediaCacheScope(viewerID: f.context.viewerID, accountGeneration: f.context.accountGeneration, safetyRevision: f.context.safetyRevision)
        _ = try await cache.value(for: photo.cacheKey, scope: scope, requestOwner: "prune-seed", variant: "seed", authorize: { version }, load: { (image, 4) })
        _ = store.targets(loadedRows: [f.rows[1]]) // Actual metadata pruning, not a cache API.
        let next = store.begin(context: f.context), denialData = try f.wire(denying: [grant.row.cardID])
        let denied = try await FeedReturnBatchAdapter(read: { _ in denialData }, current: { self.currentContext(f.context) })
            .load(cardIDs: f.rows.map(\.cardID), loadedRows: f.rows, context: f.context, id: next)
        var revoked = 0
        let observation = WorkoutPhotoImageCache.shared.resourceInvalidations.sink { if $0 == photo.cacheKey { revoked += 1 } }
        defer { observation.cancel() }
        XCTAssertTrue(store.publish(denied, expectedID: next))
        XCTAssertEqual(revoked, 0, "Pruned metadata cannot name the old resource for physical revocation")
        XCTAssertNotNil(cache.residentValue(for: photo.cacheKey, scope: scope, version: version, variant: "seed"))
        let oldAuthority = FeedLinkedCardAuthority(context: f.context, batchID: id, grantID: grant.id, row: grant.row)
        XCTAssertFalse(store.isCurrent(authority: oldAuthority, context: f.context))
        XCTAssertNil(Feed60PhotoResidentPolicy.object(batch: ready, photo: photo,
            viewerID: f.context.viewerID, generation: f.context.accountGeneration, safetyRevision: f.context.safetyRevision, returnEpoch: f.context.returnEpoch,
            isBatchCurrent: { store.isCurrent(id: $0, context: f.context) },
            isGrantCurrent: { store.isCurrent(authority: $0, context: f.context) }))
        // This intentionally documents a limitation, not proof of visible stale pixels.
    }

}
