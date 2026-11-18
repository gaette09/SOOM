import XCTest
import SwiftUI
import UIKit
import CryptoKit
@testable import SOOM

private struct EarlyHostedAuth: AuthRepository {
    let value: AuthSession
    func loadSession() -> AuthSession { value }
    func continueAsLocalUser(displayName: String) -> AuthSession { .signedOut }
    func signOut() -> AuthSession { .signedOut }
    func updateDisplayName(_ displayName: String) -> AuthSession { value }
}
private final class EarlyHostedKeys: FeedDiskCacheKeyProvider, @unchecked Sendable {
    private let lock = NSLock(); private var value: SymmetricKey? = SymmetricKey(size: .bits256)
    func key(for viewerID: UUID, create: Bool) throws -> SymmetricKey? {
        lock.lock(); defer { lock.unlock() }; return value
    }
    func removeKey(for viewerID: UUID) throws { lock.lock(); defer { lock.unlock() }; value = nil }
}
@MainActor private final class EarlyHostedPrivacy: AccountPrivacyServing {
    let viewerID: UUID?
    var reads = 0
    var held = true
    init(_ id: UUID) { viewerID = id }
    func fetch() async throws -> AccountPrivacyReceipt {
        reads += 1
        while held { try await Task.sleep(for: .milliseconds(10)) }
        return .init(enabled: false, accountScope: nil, workoutDefault: nil, revision: 1, policyVersion: 2)
    }
    func previewCapability() async throws -> AccountActivityPreviewCapability? {
        reads += 1
        while held { try await Task.sleep(for: .milliseconds(10)) }
        return .init(version: 1, viewer_id: viewerID!, enabled: false, owner_rules_accepted: false,
                     account_scope: nil, scope_revision: 1, share_measurements: false)
    }
    func save(owner: UUID, scope: AccountAudience, defaultWorkout: FeedPostVisibility,
              expectedRevision: Int64, shareMeasurements: Bool) async throws -> AccountPrivacyReceipt {
        throw CommunitySafetyError.unavailable
    }
}

@MainActor final class FeedEarlyCacheHostedViewTests: XCTestCase {
    /// Actual passive SwiftUI view, fake .supabase session and mounted isolated storage.
    /// No ReviewDemo bypass and no network-backed service is installed.
    func testHeldPrivacyRendersActualCachedJPEGWithinOneSecondThenHidesAfterFiveSeconds() async throws {
        try await runHostedTransition(width: 390, dynamicType: .large, colorScheme: .light, checkPixels: true)
    }
    func testAccessibilityDarkEarlyToLiveGeometryMatches() async throws {
        try await runHostedTransition(width: 390, dynamicType: .accessibility3, colorScheme: .dark, checkPixels: false)
    }
    func testWideDarkEarlyToLiveGeometryMatches() async throws {
        try await runHostedTransition(width: 844, dynamicType: .large, colorScheme: .dark, checkPixels: false)
    }
    private func runHostedTransition(width: CGFloat, dynamicType: DynamicTypeSize,
                                     colorScheme: ColorScheme, checkPixels: Bool) async throws {
        let hostHeight: CGFloat = checkPixels ? 844 : 1800
        let viewer = UUID(), card = UUID(), directory = FileManager.default.temporaryDirectory.appendingPathComponent("early-hosted-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try HealthAccountStorageController(baseDirectory: directory.appendingPathComponent("health"),
            inMemory: true, monitorNetwork: false, automaticallySync: false)
        try storage.switchAccount(userID: viewer)
        let auth = AuthViewModel(repository: EarlyHostedAuth(value: .signedIn(user: AppUser(id: viewer,
            displayName: "Synthetic hosted viewer", email: nil, authProvider: .supabase, createdAt: Date()))))
        let safety = CommunitySafetyStore(client: nil, viewerID: viewer, requiresSocialVerification: true)
        let privacy = EarlyHostedPrivacy(viewer)
        let model = AccountPrivacyModel(owner: viewer, service: privacy, socialState: safety, onboardingComplete: true, profileOnlyRules: true)
        let request = Task { await model.load() }
        defer { request.cancel(); privacy.held = false }
        for _ in 0..<100 { if privacy.reads == 2 { break }; await Task.yield() }
        XCTAssertEqual(privacy.reads, 2); XCTAssertFalse(safety.canUseSocial)
        XCTAssertEqual(auth.session.currentUser?.authProvider, .supabase)
        let jpeg = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { c in
            UIColor(red: 1, green: 0, blue: 1, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.jpegData(compressionQuality: 0.9))
        let clock = FeedDiskCacheClock.current()
        var snapshot = FeedStaleSummarySnapshot(id: card, ownerID: UUID(), canonicalID: UUID(), sport: "running",
            activityAt: "2020-01-01T00:00:00Z", durationSeconds: 60, distanceMeters: 100, projectionRevision: 1,
            title: "Synthetic cached first text", author: "Synthetic cached author", metrics: [],
            validatedAt: clock.wallDate, validatedUptime: clock.uptime,
            photoVersions: ["fixture-photo":"v1"], photoOrder: ["fixture-photo"], photos: ["fixture-photo":jpeg])
        snapshot.layout = FeedStaleSummaryLayout(width: Double(width), height: 650, dynamicType: String(describing: dynamicType),
            environment: FeedStaleSummaryLayout.environment(locale: "en_US", direction: String(describing: LayoutDirection.leftToRight),
                weight: String(describing: Optional<LegibilityWeight>.some(.regular))), contentRevision: snapshot.layoutRevision)
        // Learn chrome from an actual prior FeedView layout. No fixed estimate.
        var calibratedChrome: CGFloat?
        let calibration = FeedView(audience: .home, streak: .init(weekCount: 1, activityCount: 1), isLoading: true)
            .environmentObject(auth).environmentObject(storage).environment(\.scenePhase, .active)
            .environment(\.dynamicTypeSize, dynamicType).environment(\.colorScheme, colorScheme).environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.layoutDirection, .leftToRight).environment(\.legibilityWeight, .regular)
            .frame(width: width, height: hostHeight)
            .environment(\.feedChromeGeometryObserver, { name, rect in
                if name == "live-chrome-intrinsic" { calibratedChrome = rect.height }
            })
        let calibrationHost = UIHostingController(rootView: calibration)
        let calibrationWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: hostHeight))
        calibrationWindow.rootViewController = calibrationHost; calibrationWindow.makeKeyAndVisible()
        calibrationHost.loadViewIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let learnedHeight = try XCTUnwrap(calibratedChrome)
        calibrationWindow.isHidden = true; calibrationWindow.rootViewController = nil
        snapshot.chromeLayout = FeedChromeLayout(width: Double(width), dynamicType: String(describing: dynamicType),
            environment: FeedStaleSummaryLayout.environment(locale: "en_US", direction: String(describing: LayoutDirection.leftToRight),
                weight: String(describing: Optional<LegibilityWeight>.some(.regular))), height: Double(learnedHeight))
        let keys = EarlyHostedKeys(), diskPolicy = FeedDiskCachePolicy(maximumAge: 86_400)
        let disk = FeedEncryptedDiskCache(directory: directory.appendingPathComponent("cache"), keys: keys, policy: diskPolicy)
        let ds = FeedDiskCacheScope(viewerID: viewer, generation: 0, policyVersion: 1)
        let token = try await disk.activate(ds, authenticatedViewerID: viewer)
        try await disk.save(payload: JSONEncoder().encode([snapshot]), token: token, verifiedAt: clock)
        let cache = FeedStaleSummaryCache(maximumAge: 86_400, displayGrace: 5, observeSafety: false, disk: disk)
        var measuredFrames: [String: CGRect] = [:]
        let view = FeedEarlyCachePendingView(model: model, onSettings: {}, cache: cache, safety: safety)
            .environmentObject(auth).environmentObject(storage).environment(\.scenePhase, .active)
            .environment(\.dynamicTypeSize, dynamicType).environment(\.colorScheme, colorScheme).environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.layoutDirection, .leftToRight).environment(\.legibilityWeight, .regular)
            .frame(width: width, height: hostHeight)
            .environment(\.feedChromeGeometryObserver, { name, rect in measuredFrames[name] = rect })
        let host = UIHostingController(rootView: AnyView(view))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: hostHeight))
        window.rootViewController = host
        let start = ProcessInfo.processInfo.systemUptime
        window.makeKeyAndVisible(); host.loadViewIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        if checkPixels {
            var firstPixelUptime: Double?
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(20))
                if magentaPixels(host.view) > 500 { firstPixelUptime = ProcessInfo.processInfo.systemUptime; break }
            }
            let first = try XCTUnwrap(firstPixelUptime, "Real decoded JPEG must be visible, not merely present in cache")
            let milliseconds = (first - start) * 1000
            print("EARLY_HOSTED_FIRST_JPEG_MS=\(milliseconds)")
            XCTAssertLessThan(milliseconds, 1000, "Isolated host target; not a full launch or real-network result")
        } else {
            // Large accessibility chrome may move media beyond the viewport.
            // This case measures layout, not first-photo latency.
            for _ in 0..<100 {
                if measuredFrames["early-card-\(card)"] != nil { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNotNil(measuredFrames["early-card-\(card)"])
        }
        XCTAssertTrue(LoadTimingRecorder.shared.snapshot().contains { $0.category == "feed-early-passive" && $0.phase == "first-cached-card-mounted" && $0.recordedUptime >= start })
        XCTAssertEqual(model.earlyCacheVerification, .checking)
        XCTAssertFalse(safety.canUseSocial, "Displaying pixels must not create authority")
        let remaining = max(0, 5.4 - (ProcessInfo.processInfo.systemUptime - start))
        try await Task.sleep(for: .seconds(remaining))
        if checkPixels { XCTAssertLessThan(magentaPixels(host.view), 20, "Held privacy must not extend the five-second preview") }
        let expiredScope = FeedStaleSummaryScope(viewerID: viewer, generation: safety.accountGeneration,
            safetyRevision: safety.revision, policyVersion: 1)
        XCTAssertTrue(cache.allSnapshots(scope: expiredScope).isEmpty, "All environments obey the five-second deadline")
        XCTAssertEqual(privacy.reads, 2, "Only the two injected privacy reads are used; no retries")
        // Baseline geometry comparison: actual FeedView, not a guessed header height.
        // This local draft has no media/profile URLs and installs no service fetchers.
        let example = FeedMockData.items[0]
        let item = FeedItem(id: card, authorName: "Synthetic live author", authorHandle: nil,
            authorId: viewer, isLocalDraft: true, createdAt: Date(), itemType: example.itemType,
            visibility: .privateOnly, cardData: example.cardData, caption: nil, activityContext: "Synthetic live card")
        let liveItems = [item] + (0..<11).map { _ in
            FeedItem(id: UUID(), authorName: "Synthetic live author", authorHandle: nil,
                authorId: viewer, isLocalDraft: true, createdAt: item.createdAt.addingTimeInterval(-1), itemType: example.itemType,
                visibility: .privateOnly, cardData: example.cardData, caption: nil, activityContext: "Synthetic scroll fixture")
        }
        let live = FeedView(audience: .home, items: liveItems, streak: .init(weekCount: 1, activityCount: 1))
            .environmentObject(auth).environmentObject(storage).environment(\.scenePhase, .active)
            .environment(\.dynamicTypeSize, dynamicType).environment(\.colorScheme, colorScheme).environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.layoutDirection, .leftToRight).environment(\.legibilityWeight, .regular)
            .frame(width: width, height: hostHeight)
            .environment(\.feedChromeGeometryObserver, { name, rect in measuredFrames[name] = rect })
        host.rootView = AnyView(live.environment(\.feedChromeTestCache, cache).environment(\.feedChromeTestSafety, safety))
        try await Task.sleep(for: .milliseconds(350))
        let earlyFrame = try XCTUnwrap(measuredFrames["early-card-\(card)"])
        let liveFrame = try XCTUnwrap(measuredFrames["live-first-card-group"])
        let delta = liveFrame.minY - earlyFrame.minY
        print("EARLY_TO_LIVE_BASELINE_FIRST_CARD_Y width=\(width) type=\(dynamicType) scheme=\(colorScheme) early=\(earlyFrame.minY) live=\(liveFrame.minY) delta=\(delta)")
        XCTAssertTrue(delta.isFinite)
        XCTAssertEqual(liveFrame.minY, earlyFrame.minY, accuracy: 0.5,
            "Same measured chrome reservation must preserve first-card Y across the actual view transition")
        // Programmatic position validation, not gesture latency/FPS measurement.
        // Wait for UIKit's live hierarchy commit, not only SwiftUI geometry.
        for _ in 0..<50 {
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            if allScrollViews(host.view).contains(where: {
                $0.bounds.height >= hostHeight * 0.5 && $0.contentSize.height > $0.bounds.height + 100
            }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let scrollTree = allScrollViews(host.view)
        print("SCROLL_FIXTURE_INPUT width=\(width) type=\(dynamicType) hostHeight=\(hostHeight) hostBounds=\(host.view.bounds) cards=\(liveItems.count) local=\(liveItems.filter(\.isLocalDraft).count) group=\(liveFrame) sharedViewer=\(CommunitySafetyStore.shared.viewerID != nil) sharedGeneration=\(CommunitySafetyStore.shared.accountGeneration) sharedRevision=\(CommunitySafetyStore.shared.revision)")
        for (index, scroll) in scrollTree.enumerated() {
            print("SCROLL_TREE index=\(index) class=\(String(describing: type(of: scroll))) frame=\(scroll.frame) bounds=\(scroll.bounds) content=\(scroll.contentSize) adjustedInset=\(scroll.adjustedContentInset) enabled=\(scroll.isScrollEnabled) hidden=\(scroll.isHidden) alpha=\(scroll.alpha) offset=\(scroll.contentOffset) global=\(scroll.convert(scroll.bounds, to: nil))")
        }
        let scrollCandidates = scrollTree.filter {
            $0.isScrollEnabled && $0.bounds.height >= hostHeight * 0.5 &&
            $0.contentSize.height + $0.adjustedContentInset.top + $0.adjustedContentInset.bottom > $0.bounds.height + 100
        }.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
        let outer = try XCTUnwrap(scrollCandidates.first, "Find scrollable full-viewport feed, not nested header")
        XCTAssertGreaterThan(outer.bounds.height, learnedHeight,
            "The chosen scroller must not be the reserved chrome region")
        let previousOffset = outer.contentOffset
        let target = CGPoint(x: previousOffset.x, y: previousOffset.y + 80)
        outer.setContentOffset(target, animated: false)
        try await Task.sleep(for: .milliseconds(150))
        let scrolledFrame = try XCTUnwrap(measuredFrames["live-first-card-group"])
        XCTAssertEqual(outer.contentOffset.y - previousOffset.y, 80, accuracy: 0.5)
        XCTAssertEqual(scrolledFrame.minY - liveFrame.minY, -80, accuracy: 1,
            "First-card global position must follow the outer feed scroll")
        let savedOffset = outer.contentOffset
        let cacheRevision = cache.revision
        cache.captureLayout(cardID: card, scope: expiredScope, width: Double(width), height: 651,
            dynamicType: String(describing: dynamicType),
            environment: FeedStaleSummaryLayout.environment(locale: "en_US", direction: String(describing: LayoutDirection.leftToRight),
                weight: String(describing: Optional<LegibilityWeight>.some(.regular))))
        XCTAssertGreaterThan(cache.revision, cacheRevision)
        // DEBUG cache injection is an Environment value. Re-evaluate the same
        // live hierarchy to exercise the metadata update without changing identity.
        host.rootView = AnyView(live.environment(\.feedChromeTestCache, cache).environment(\.feedChromeTestSafety, safety))
        try await Task.sleep(for: .milliseconds(150))
        let currentOuter = try XCTUnwrap(allScrollViews(host.view).filter {
            $0.isScrollEnabled && $0.bounds.height >= hostHeight * 0.5 &&
            $0.contentSize.height + $0.adjustedContentInset.top + $0.adjustedContentInset.bottom > $0.bounds.height + 100
        }.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
        XCTAssertEqual(currentOuter.contentOffset.y, savedOffset.y, accuracy: 0.5,
            "Metadata update must not reset the feed scroll offset")
        XCTAssertEqual(measuredFrames["live-first-card-group"]?.minY ?? .infinity,
            scrolledFrame.minY, accuracy: 1)
        print("EARLY_TO_LIVE_SCROLL_POSITION width=\(width) type=\(dynamicType) offset=\(savedOffset.y) preserved=\(currentOuter.contentOffset.y)")
        // Fixed-environment programmatic checks do not prove gesture smoothness/FPS.

    }
    private func allScrollViews(_ view: UIView) -> [UIScrollView] {
        let own = (view as? UIScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { allScrollViews($0) }
    }
    private func magentaPixels(_ view: UIView) -> Int {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard let cg = image.cgImage else { return 0 }
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        guard let ctx = CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8,
            bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return stride(from: 0, to: bytes.count, by: 4).reduce(0) { n, i in
            n + (bytes[i] > 200 && bytes[i+1] < 70 && bytes[i+2] > 200 ? 1 : 0)
        }
    }
}
