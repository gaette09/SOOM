import XCTest
import SwiftUI
import UIKit
import Combine
@testable import SOOM

/// Actual mounted foreign cached pixels. No product hooks, injected invalidations or private view inspection.
@MainActor final class FeedMountedForeignDenialTests: XCTestCase {
    private enum Failure: Error { case inactiveHost, busyCache, timeout, renderFailed, badPattern, changedScope, rejectedPublish }
    @MainActor private final class Callbacks {
        var nonnil = 0
        var nils = 0
        var hasImage = false
        func receive(_ image: UIImage?) {
            hasImage = image != nil
            if image == nil { nils += 1 } else { nonnil += 1 }
        }
    }
    @MainActor private struct PhotoHost: View {
        @ObservedObject var store: FeedReturnBatchStore
        let context: FeedReturnBatchContext
        let photo: WorkoutPhotoReference
        let size: WorkoutPhotoDecodeSize
        let presentationID: UUID
        let callbacks: Callbacks
        var body: some View {
            ZStack {
                Color.white
                WorkoutPhotoImage(photo: photo, allowsFeedPresentationReuse: true, decodeSize: size,
                                  onImageLoaded: { callbacks.receive($0) })
                    .frame(width: 240, height: 240)
            }
            .ignoresSafeArea()
            .environment(\.soomFeedPhotoPresentationID, presentationID)
            .environment(\.soomFeedIsActive, true)
            .environment(\.soomFeedRevalidationRevision, context.returnEpoch)
            .environment(\.soomFeedReturnBatch, store.presentation)
            .environment(\.soomFeedBatchIsCurrent, { id in store.isCurrent(id: id, context: context) })
            .environment(\.soomFeedCardGrantIsCurrent, { authority in store.isCurrent(authority: authority, context: context) })
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

    private func pattern() throws -> CGImage {
        let width = 240, height = 240
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            let magenta = ((x / 30) + (y / 30)) % 2 == 0
            bytes[i] = magenta ? 255 : 0
            bytes[i + 1] = magenta ? 0 : 255
            bytes[i + 2] = magenta ? 255 : 0
        } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func raster(_ window: UIWindow, name: String) throws -> (magenta: Double, green: Double, magentaPixels: Int, greenPixels: Int, totalPixels: Int) {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1; format.opaque = true
        var rendered = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard rendered else { throw Failure.renderFailed }
        let png = try XCTUnwrap(image.pngData())
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let cg = try XCTUnwrap(image.cgImage), w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        guard drawn, w == 300, h == 300 else { throw Failure.renderFailed }
        var magenta = 0, green = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = bytes[i], g = bytes[i + 1], b = bytes[i + 2]
            if r > 200 && g < 60 && b > 200 { magenta += 1 }
            if r < 60 && g > 200 && b < 60 { green += 1 }
        }
        return (Double(magenta) / Double(w * h), Double(green) / Double(w * h), magenta, green, w * h)
    }
    private func report(_ value: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let a = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testMountedCachedForeignPhotoDisappearsAfterActualStoreDenial() async throws {
        executionTimeAllowance = 30
        guard safeSyntheticHost() else { return }
        let runtime = try XCTUnwrap(ReviewDemoController.shared.runtime)
        guard UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { throw Failure.inactiveHost }
        let f = fixture(), store = FeedReturnBatchStore(), callbacks = Callbacks()
        guard currentContext(f.context) != nil else { throw Failure.changedScope }
        let cache = WorkoutPhotoImageCache.shared.pixels
        guard cache.inFlightCount == 0 else { throw Failure.busyCache }
        let id = store.begin(context: f.context), wire = try f.wire()
        let adapter = FeedReturnBatchAdapter(read: { _ in wire }, current: { self.currentContext(f.context) })
        let ready = try await adapter.load(cardIDs: f.rows.map(\.cardID), loadedRows: f.rows, context: f.context, id: id)
        guard store.publish(ready, expectedID: id) else { throw Failure.rejectedPublish }
        let grant = try XCTUnwrap(ready.grants[f.rows[0].cardID]), photo = try XCTUnwrap(grant.photos.first)
        let object = try XCTUnwrap(grant.photoObjects[photo.cacheKey]), version = try XCTUnwrap(object.cacheVersionToken)
        let authority = FeedLinkedCardAuthority(context: f.context, batchID: id, grantID: grant.id, row: grant.row)
        let scope = SOOMMediaCacheScope(viewerID: f.context.viewerID, accountGeneration: f.context.accountGeneration, safetyRevision: f.context.safetyRevision)
        let size = try XCTUnwrap(WorkoutPhotoDecodeSize.feed(maximumWidth: 240, height: 240, displayScale: 1))
        let pixels = try pattern()
        defer { cache.invalidateResource(photo.cacheKey) }
        _ = try await cache.value(for: photo.cacheKey, scope: scope, requestOwner: "mounted-denial-seed",
            variant: size.cacheVariant, authorize: { version }, load: { (pixels, pixels.bytesPerRow * pixels.height) })
        // No demo bytes exist at this fresh synthetic path. Normal loader success therefore requires cache reuse.
        XCTAssertNil(ReviewDemoPhotoStore.shared.bytes(for: photo))
        XCTAssertNotNil(cache.residentValue(for: photo.cacheKey, scope: scope, version: version, variant: size.cacheVariant))
        let previousKeyWindow = scene.windows.first(where: { $0.isKeyWindow })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        let host = UIHostingController(rootView: AnyView(PhotoHost(store: store, context: f.context, photo: photo,
            size: size, presentationID: UUID(), callbacks: callbacks).environmentObject(runtime.auth)))
        window.rootViewController = host
        window.makeKeyAndVisible()
        func detachOwnedWindow() {
            window.isHidden = true; window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        defer { detachOwnedWindow() }
        var invalidations = 0
        let observer = WorkoutPhotoImageCache.shared.resourceInvalidations.sink { key in
            if key == photo.cacheKey { invalidations += 1 }
        }
        defer { observer.cancel() }
        var result: [String: Any] = ["phaseFailure": NSNull(), "syntheticCachedPhoto": true, "directPublisherSend": false,
            "preMinimumEachColorFraction": 0.20, "postMaximumEachColorFraction": 0.002,
            "lateObservationMilliseconds": 300]
        var phase = "mount-cache-hit"
        do {
            for _ in 0..<100 where !callbacks.hasImage { try await Task.sleep(for: .milliseconds(20)) }
            guard callbacks.hasImage, callbacks.nonnil > 0 else { throw Failure.timeout }
            try await Task.sleep(for: .milliseconds(100))
            guard currentContext(f.context) != nil, store.isCurrent(authority: authority, context: f.context) else { throw Failure.changedScope }
            guard host.view.window === window, !window.isHidden, window.isKeyWindow,
                  scene.activationState == .foregroundActive else { throw Failure.inactiveHost }
            result["mountedForegroundKeyWindow"] = true
            result["preCurrentGrant"] = store.isCurrent(authority: authority, context: f.context)
            result["preWindowFrame"] = [Double(window.frame.minX), Double(window.frame.minY), Double(window.frame.width), Double(window.frame.height)]
            phase = "before-raster"
            let pre = try raster(window, name: "mounted foreign before denial")
            result["preMagentaFraction"] = pre.magenta; result["preGreenFraction"] = pre.green
            result["preMagentaPixels"] = pre.magentaPixels; result["preGreenPixels"] = pre.greenPixels
            result["preTotalPixels"] = pre.totalPixels; result["preRenderSucceeded"] = true
            guard pre.magenta > 0.20, pre.green > 0.20 else { throw Failure.badPattern }
            let loadedBefore = callbacks.nonnil, clearedBefore = callbacks.nils
            let deniedWire = try f.wire(denying: [grant.row.cardID])
            let deniedAdapter = FeedReturnBatchAdapter(read: { _ in deniedWire }, current: { self.currentContext(f.context) })
            let denied = try await deniedAdapter.load(cardIDs: f.rows.map(\.cardID), loadedRows: f.rows, context: f.context, id: id)
            // No begin here: the old receipt remains current until actual publish/revoke, not a pending pre-hide.
            guard callbacks.hasImage, store.isCurrent(authority: authority, context: f.context) else { throw Failure.changedScope }
            phase = "actual-denial-publish"
            guard store.publish(denied, expectedID: id) else { throw Failure.rejectedPublish }
            let synchronousClear = !callbacks.hasImage && callbacks.nils > clearedBefore
            XCTAssertTrue(synchronousClear); XCTAssertEqual(invalidations, 1)
            XCTAssertFalse(store.isCurrent(authority: authority, context: f.context))
            XCTAssertNil(cache.residentValue(for: photo.cacheKey, scope: scope, version: version, variant: size.cacheVariant, allowAlternateVariant: true))
            phase = "post-denial-render"
            try await Task.sleep(for: .milliseconds(300))
            guard host.view.window === window, !window.isHidden, window.isKeyWindow,
                  scene.activationState == .foregroundActive else { throw Failure.inactiveHost }
            let post = try raster(window, name: "mounted foreign after denial")
            result["postMagentaFraction"] = post.magenta; result["postGreenFraction"] = post.green
            result["postMagentaPixels"] = post.magentaPixels; result["postGreenPixels"] = post.greenPixels
            result["postTotalPixels"] = post.totalPixels; result["postRenderSucceeded"] = true
            result["postWindowFrame"] = [Double(window.frame.minX), Double(window.frame.minY), Double(window.frame.width), Double(window.frame.height)]
            result["postMountedForegroundKeyWindow"] = true
            result["nonnullCallbacksBeforeDenial"] = loadedBefore
            result["nonnullCallbacksAfterDenial"] = callbacks.nonnil
            result["nilCallbacksBeforeDenial"] = clearedBefore
            result["nilCallbacksAfterDenial"] = callbacks.nils
            XCTAssertLessThan(post.magenta, 0.002); XCTAssertLessThan(post.green, 0.002)
            XCTAssertFalse(callbacks.hasImage); XCTAssertEqual(callbacks.nonnil, loadedBefore)
            XCTAssertNotNil(currentContext(f.context))
            result["normalCacheHitCallback"] = loadedBefore > 0
            result["synchronousCallbackClear"] = synchronousClear
            result["realInvalidations"] = invalidations
            result["oldGrantRejected"] = !store.isCurrent(authority: authority, context: f.context)
            result["residentMiss"] = cache.residentValue(for: photo.cacheKey, scope: scope, version: version, variant: size.cacheVariant, allowAlternateVariant: true) == nil
            result["noLaterNonnil"] = callbacks.nonnil == loadedBefore && !callbacks.hasImage
            result["scopeUnchanged"] = currentContext(f.context) != nil
            host.rootView = AnyView(Color.clear)
            try await Task.sleep(for: .milliseconds(80))
            detachOwnedWindow()
            observer.cancel(); cache.invalidateResource(photo.cacheKey)
            result["windowDetached"] = window.rootViewController == nil && window.isHidden
            result["previousKeyWindowRestored"] = previousKeyWindow.map { $0.isKeyWindow } ?? !window.isKeyWindow
            XCTAssertTrue(previousKeyWindow.map { $0.isKeyWindow } ?? !window.isKeyWindow)
            result["ownedResidentAfterCleanup"] = cache.residentValue(for: photo.cacheKey, scope: scope, version: version, variant: size.cacheVariant, allowAlternateVariant: true) != nil
            XCTAssertTrue(window.rootViewController == nil && window.isHidden)
            XCTAssertNil(cache.residentValue(for: photo.cacheKey, scope: scope, version: version, variant: size.cacheVariant, allowAlternateVariant: true))
            try report(result, name: "mounted foreign denial result")
        } catch {
            host.rootView = AnyView(Color.clear)
            try? await Task.sleep(for: .milliseconds(80))
            detachOwnedWindow()
            observer.cancel(); cache.invalidateResource(photo.cacheKey)
            result["phaseFailure"] = phase; result["error"] = String(describing: error)
            try? report(result, name: "mounted foreign denial failure")
            throw error
        }
    }
}
