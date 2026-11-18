import XCTest
import Combine
import CoreGraphics
@testable import SOOM

/// No network, view hosting or persisted data. Exercises the real adapter/store/cache bridge.
@MainActor final class FeedSameBatchRegrantTests: XCTestCase {
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
        func wire(indices: [Int] = [0, 1], denying denied: Set<UUID> = [], version: String = "synthetic-v1") throws -> Data {
            let entries: [[String: Any]] = indices.map { index in
                let row = rows[index]
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
                        "object":["object_id":photos[index].uuidString,"version":version,"size":4]]]]
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
    private enum BoundaryFailure: Error { case decodeNotStarted, hostScopeChanged, sharedCacheBusy, ordinaryLateFailure }
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
    private func pixel(red: UInt8 = 32) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data([red, 96, 160, 255]) as CFData))
        return try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    func testSameBatchPartialDenialRegrantPreservesV2AfterTwoOldCompletions() async throws {
        executionTimeAllowance = 30
        guard safeSyntheticHost() else { return }
        let f = fixture(), store = FeedReturnBatchStore()
        let oldPixel = try pixel(), freshPixel = try pixel(red: 224)
        let cache = WorkoutPhotoImageCache.shared.pixels
        guard currentContext(f.context) != nil else { throw BoundaryFailure.hostScopeChanged }
        guard cache.inFlightCount == 0 else { throw BoundaryFailure.sharedCacheBusy }
        let owned = f.rows.indices.map { WorkoutPhotoPolicy.path(ownerID: f.rows[$0].ownerID, postID: f.sources[$0], photoID: f.photos[$0]) }
        defer { owned.forEach { cache.invalidateResource($0) } }
        let batchID = store.begin(context: f.context)
        func receipt(_ data: Data, indices: [Int]) async throws -> FeedReturnBatchPresentation {
            try await FeedReturnBatchAdapter(read: { _ in data }, current: { self.currentContext(f.context) })
                .load(cardIDs: indices.map { f.rows[$0].cardID }, loadedRows: f.rows, context: f.context, id: batchID)
        }
        let ready = try await receipt(f.wire(), indices: [0, 1])
        XCTAssertTrue(store.publish(ready, expectedID: batchID))
        let target = try XCTUnwrap(ready.grants[f.rows[0].cardID]), control = try XCTUnwrap(ready.grants[f.rows[1].cardID])
        let photo = try XCTUnwrap(target.photos.first), controlPhoto = try XCTUnwrap(control.photos.first)
        let v1 = try XCTUnwrap(target.photoObjects[photo.cacheKey]?.cacheVersionToken)
        let cv = try XCTUnwrap(control.photoObjects[controlPhoto.cacheKey]?.cacheVersionToken)
        let oldAuthority = FeedLinkedCardAuthority(context: f.context, batchID: batchID, grantID: target.id, row: target.row)
        let scope = SOOMMediaCacheScope(viewerID: f.context.viewerID, accountGeneration: f.context.accountGeneration, safetyRevision: f.context.safetyRevision)
        _ = try await cache.value(for: photo.cacheKey, scope: scope, requestOwner: "seed", variant: "seed", authorize: { v1 }, load: { (oldPixel, 4) })
        _ = try await cache.value(for: controlPhoto.cacheKey, scope: scope, requestOwner: "control", variant: "seed", authorize: { cv }, load: { (oldPixel, 4) })
        let gates = [DecodeGate(oldPixel), DecodeGate(oldPixel)]
        defer { gates.forEach { $0.release() } }
        var returnedOldSuccess = false, threwOldOrdinary = false
        let flights = gates.enumerated().map { index, gate in
            Task { @MainActor in
                try await cache.value(for: photo.cacheKey, scope: scope, requestOwner: "owner-\(index)", variant: "old-\(index)", authorize: {
                    guard self.currentContext(f.context) != nil, store.isCurrent(authority: oldAuthority, context: f.context) else { throw CancellationError() }
                    return v1
                }, load: {
                    let value = await gate.waitIgnoringCancellation()
                    if index == 1 { threwOldOrdinary = true; throw BoundaryFailure.ordinaryLateFailure }
                    returnedOldSuccess = true
                    return (value, 4)
                })
            }
        }
        var invalidated: [String] = [], callbackOldGrant = false, callbackRawMiss = false
        let observation = WorkoutPhotoImageCache.shared.resourceInvalidations.sink { key in
            invalidated.append(key)
            if key == photo.cacheKey {
                callbackOldGrant = store.isCurrent(authority: oldAuthority, context: f.context)
                callbackRawMiss = cache.residentValue(for: photo.cacheKey, scope: scope, version: v1, allowAlternateVariant: true) == nil
            }
        }
        defer { observation.cancel() }
        var report: [String: Any] = ["sameBatch": true, "merge": true, "tasksReaped": 0, "phaseFailure": NSNull()]
        var phase = "wait-old-loads"
        do {
            for _ in 0..<100 {
                if gates.allSatisfy({ $0.started }) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard gates.allSatisfy({ $0.started }) else { throw BoundaryFailure.decodeNotStarted }
            guard currentContext(f.context) != nil else { throw BoundaryFailure.hostScopeChanged }
            phase = "partial-denial"
            let denied = try await receipt(f.wire(indices: [0], denying: [target.row.cardID]), indices: [0])
            XCTAssertEqual(denied.requested, [target.row.cardID])
            XCTAssertTrue(store.publish(denied, expectedID: batchID, merging: true))
            let requested = Set(f.rows.map(\.cardID))
            XCTAssertEqual(store.presentation?.requested, requested)
            XCTAssertEqual(store.presentation?.grants[control.row.cardID]?.id, control.id)
            XCTAssertTrue(store.isCurrent(id: batchID, context: f.context))
            XCTAssertFalse(store.isCurrent(authority: oldAuthority, context: f.context))
            XCTAssertTrue(store.presentation?.denied.contains(target.row.cardID) == true)
            XCTAssertNil(store.presentation?.grants[target.row.cardID])
            let staleObject = Feed60PhotoResidentPolicy.object(batch: ready, photo: photo,
                viewerID: f.context.viewerID, generation: f.context.accountGeneration, safetyRevision: f.context.safetyRevision, returnEpoch: f.context.returnEpoch,
                isBatchCurrent: { store.isCurrent(id: $0, context: f.context) }, isGrantCurrent: { store.isCurrent(authority: $0, context: f.context) })
            XCTAssertNil(staleObject)
            XCTAssertEqual(invalidated, [photo.cacheKey])
            XCTAssertTrue(callbackOldGrant); XCTAssertTrue(callbackRawMiss)
            report["callbackOldGrantStillCurrent"] = callbackOldGrant
            report["callbackRawCacheAlreadyEmpty"] = callbackRawMiss
            report["batchStillCurrentOldGrantRejected"] = store.isCurrent(id: batchID, context: f.context) && !store.isCurrent(authority: oldAuthority, context: f.context)
            report["stalePhotoPolicyRejected"] = staleObject == nil
            phase = "partial-v2-regrant"
            let fresh = try await receipt(f.wire(indices: [0], version: "synthetic-v2"), indices: [0])
            XCTAssertTrue(store.publish(fresh, expectedID: batchID, merging: true))
            let grant = try XCTUnwrap(store.presentation?.grants[target.row.cardID])
            let v2 = try XCTUnwrap(grant.photoObjects[photo.cacheKey]?.cacheVersionToken)
            XCTAssertNotEqual(v1, v2); XCTAssertNotEqual(grant.id, target.id)
            let freshAuthority = FeedLinkedCardAuthority(context: f.context, batchID: batchID, grantID: grant.id, row: grant.row)
            XCTAssertTrue(store.isCurrent(authority: freshAuthority, context: f.context))
            XCTAssertFalse(store.isCurrent(authority: oldAuthority, context: f.context))
            XCTAssertFalse(store.presentation?.denied.contains(target.row.cardID) == true)
            XCTAssertEqual(store.presentation?.grants[control.row.cardID]?.id, control.id)
            XCTAssertEqual(store.presentation?.requested, requested)
            let freshObject = Feed60PhotoResidentPolicy.object(batch: store.presentation, photo: photo,
                viewerID: f.context.viewerID, generation: f.context.accountGeneration, safetyRevision: f.context.safetyRevision, returnEpoch: f.context.returnEpoch,
                isBatchCurrent: { store.isCurrent(id: $0, context: f.context) }, isGrantCurrent: { store.isCurrent(authority: $0, context: f.context) })
            XCTAssertEqual(freshObject?.cacheVersionToken, v2)
            // Reuse the ordinary-error owner's name. The old catch must not revoke the new resource epoch.
            let loadedV2 = try await cache.value(for: photo.cacheKey, scope: scope, requestOwner: "owner-1", variant: "new-v2", authorize: {
                guard self.currentContext(f.context) != nil, store.isCurrent(authority: freshAuthority, context: f.context) else { throw CancellationError() }
                return v2
            }, load: { (freshPixel, 4) })
            XCTAssertTrue(loadedV2 === freshPixel)
            phase = "release-both-old-completions"
            let failures = await drain(flights, gates: gates, cancel: false)
            report["tasksReaped"] = flights.count; report["lateFailures"] = failures
            report["oldSuccessClosureReturned"] = returnedOldSuccess; report["oldOrdinaryClosureThrew"] = threwOldOrdinary
            XCTAssertEqual(failures, 2); XCTAssertTrue(returnedOldSuccess); XCTAssertTrue(threwOldOrdinary)
            XCTAssertEqual(invalidated, [photo.cacheKey], "Late old error must not revoke v2")
            XCTAssertNil(cache.residentValue(for: photo.cacheKey, scope: scope, version: v1, allowAlternateVariant: true))
            let retainedV2 = cache.residentValue(for: photo.cacheKey, scope: scope, version: v2, variant: "new-v2")
            XCTAssertTrue(retainedV2 === freshPixel)
            XCTAssertNotNil(cache.residentValue(for: controlPhoto.cacheKey, scope: scope, version: cv, variant: "seed"))
            XCTAssertTrue(store.isCurrent(authority: freshAuthority, context: f.context))
            XCTAssertNotNil(currentContext(f.context))
            report["v2RetainedDistinctPixels"] = retainedV2 === freshPixel
            report["controlRetained"] = cache.residentValue(for: controlPhoto.cacheKey, scope: scope, version: cv, variant: "seed") != nil
            report["invalidationCount"] = invalidated.count
            report["continuationsReleased"] = gates.filter { $0.resumed }.count
            report["freshGrantValid"] = store.isCurrent(authority: freshAuthority, context: f.context)
            report["controlGrantIDPreserved"] = store.presentation?.grants[control.row.cardID]?.id == control.id
            report["requestedUnionPreserved"] = store.presentation?.requested == requested
            report["scopeAfterReap"] = currentContext(f.context) != nil
            observation.cancel()
            owned.forEach { cache.invalidateResource($0) }
            let targetAfterCleanup = cache.residentValue(for: photo.cacheKey, scope: scope, version: v2, allowAlternateVariant: true)
            let controlAfterCleanup = cache.residentValue(for: controlPhoto.cacheKey, scope: scope, version: cv, allowAlternateVariant: true)
            XCTAssertNil(targetAfterCleanup); XCTAssertNil(controlAfterCleanup)
            report["ownedCleanupResidentCount"] = [targetAfterCleanup, controlAfterCleanup].compactMap { $0 }.count
            record(report, name: "same batch regrant bridge result")
        } catch {
            report["phaseFailure"] = phase; report["error"] = String(describing: error)
            report["lateFailuresDuringCleanup"] = await drain(flights, gates: gates, cancel: true)
            report["tasksReaped"] = flights.count
            report["continuationsReleased"] = gates.filter { $0.resumed }.count
            observation.cancel(); owned.forEach { cache.invalidateResource($0) }
            record(report, name: "same batch regrant bridge failure")
            throw error
        }
    }
}
