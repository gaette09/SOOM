import XCTest
import UIKit

/// Synthetic fixtures exercise the production card and feed lifetime. No real
/// account, health data, server response, or user video is used by these tests.
@MainActor
final class Feed60StabilityUITests: XCTestCase {
    private func launch(_ extra: [String: String] = [:]) -> XCUIApplication {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment = [
            "SOOM_SYNTHETIC_UI_TESTS": "1", "SOOM_PROJECTION_SUMMARY_QA": "1",
            "SOOM_FEED_ENRICHMENT_QA": "1", "SOOM_FEED_BATCH_QA": "1",
            "SOOM_PROFILE_PHOTO_QA": "1", "SOOM_FEED_BATCH_SMALL_PHOTOS": "1",
            "SOOM_FEED_LIFECYCLE_QA": "1"
        ].merging(extra) { _, new in new }
        app.launch()
        let start = app.buttons["reviewDemo.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 15))
        selectTab("soom.tab.feed", in: app)
        return app
    }

    private func selectTab(_ identifier: String, in app: XCUIApplication) {
        // ReviewDemo's cover can expose a background root bar. Match the
        // frontmost hittable tab and verify that exact control was selected.
        let tabs = app.buttons.matching(identifier: identifier)
        waitUntil { tabs.allElementsBoundByIndex.contains { $0.isHittable } }
        for _ in 0..<2 {
            let tab = tabs.allElementsBoundByIndex.last { $0.isHittable } ?? tabs.firstMatch
            let frame = tab.frame.intersection(app.frame)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            let selected = NSPredicate { _, _ in tab.exists && (tab.isSelected || tab.value as? String == "선택됨") }
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: nil)], timeout: 2) == .completed { return }
        }
        XCTFail("Frontmost tab did not become selected: " + identifier)
    }

    private func waitUntil(timeout: TimeInterval = 15, _ condition: @escaping () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout),
                       .completed, file: file, line: line)
    }

    private func count(_ key: String, in app: XCUIApplication) -> Int {
        let label = app.staticTexts["feed.lifecycle.probe"].firstMatch.label
        let field = label.split(separator: ";").first { $0.hasPrefix(key + "=") }
        return Int(field?.split(separator: "=").last ?? "") ?? -1
    }

    private func title(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "합성 대회 기록")).firstMatch
    }

    private func assertReady(in app: XCUIApplication) {
        waitUntil { self.title(in: app).exists && self.count("linkedReads", in: app) > 0 && self.count("linkedEntries", in: app) > 0 }
        XCTAssertTrue(app.staticTexts["feed.lifecycle.probe"].firstMatch.label.contains("ready"))
    }

    private func assertReadsRemain(_ expected: Int, in app: XCUIApplication, seconds: TimeInterval = 1) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.count("linkedReads", in: app) != expected
        }, object: nil)
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: seconds), .completed)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let probe = XCTAttachment(string: app.staticTexts["feed.lifecycle.probe"].firstMatch.label)
        probe.name = name + " counters"; probe.lifetime = .keepAlways; add(probe)
    }

    func test68ScrollPhaseReachesMapAndPausesMotionOnVersusOff() {
        for off in [false, true] {
            let app = launch(["SOOM_FEED_CARD_PREVIEW_V3_QA":"1", "SOOM_FEED68_SCROLL_QA":"1", "SOOM_FEED68_MOTION_OFF":off ? "1" : "0"])
            waitUntil { self.title(in: app).exists }
            app.swipeUp()
            let pager = app.scrollViews["workout.media.pager"].firstMatch
            XCTAssertTrue(pager.waitForExistence(timeout: 5)); pager.swipeRight()
            let route = app.descendants(matching: .any).matching(identifier:"feed.lifecycle.linkedRoute").firstMatch
            XCTAssertTrue(route.waitForExistence(timeout:10))
            func metric(_ key: String) -> Int {
                let label = app.staticTexts["feed68.scroll.probe"].firstMatch.label
                return Int(label.split(separator:";").first { $0.hasPrefix(key + "=") }?.split(separator:"=").last ?? "") ?? -1
            }
            if !off { waitUntil { metric("ticks") > 0 } }
            let start = app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.65))
            start.press(forDuration:0.05, thenDragTo:start.withOffset(CGVector(dx:0,dy:-60)))
            waitUntil { metric("scroll") > 0 && metric("route") > 0 }
            XCTAssertEqual(metric("illegal"),0,"No route ticks while real feed scroll phase is active")
            if off { XCTAssertEqual(metric("ticks"),0) }
            for offset in [-80.0, 80.0, -80.0, 80.0] {
                let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
                point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: offset)))
            }
            XCTAssertGreaterThan(metric("frames"), 0)
            XCTAssertEqual(metric("illegal"), 0)
            let frameLabel = app.staticTexts["feed68.scroll.probe"].firstMatch.label
            let frameAttachment = XCTAttachment(string: frameLabel)
            frameAttachment.name = "71 simulator display-link delivery motion " + (off ? "OFF" : "ON")
            frameAttachment.lifetime = .keepAlways; add(frameAttachment)
            print("SOOM71_FRAME_DELIVERY motion=\(off ? "OFF" : "ON") \(frameLabel)")
            capture(app, "68 real scroll phase map propagation motion " + (off ? "OFF" : "ON"))
            app.terminate()
        }
    }

    func testBatchProjectionShowsCardWithoutPerCardEnrichment() {
        let app = launch(["SOOM_FEED_CARD_PREVIEW_V3_QA": "1"]); defer { app.terminate() }
        waitUntil { self.title(in: app).exists }
        XCTAssertEqual(count("linkedReads", in: app), 0)
        XCTAssertEqual(count("linkedEntries", in: app), 0)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "합성 기기")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "합성 장소")).firstMatch.exists)
        app.swipeUp()
        let pager = app.scrollViews["workout.media.pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5)); pager.swipeRight()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "feed.lifecycle.linkedRoute").firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(count("linkedReads", in: app), 0)
        capture(app, "Batch projection keeps metadata and map with zero per-card enrichment")
    }

    func testCardOnlyPreviewKeepsTitleDeviceLocationAndMap() {
        let app = launch(); defer { app.terminate() }
        assertReady(in: app)
        XCTAssertTrue(title(in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "합성 기기")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "합성 장소")).firstMatch.exists)
        capture(app, "Card-only DTO keeps title device and location")
        app.swipeUp()
        let pager = app.scrollViews["workout.media.pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5)); pager.swipeRight()
        let route = app.descendants(matching: .any).matching(identifier: "feed.lifecycle.linkedRoute").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        capture(app, "Card-only geometry keeps existing map without telemetry snapshot")
    }

    func testLinkedMetadataSurvivesViewRecreationAndScrollButRevalidatesOnTabReturn() {
        let app = launch(); defer { app.terminate() }
        assertReady(in: app)
        let reads = count("linkedReads", in: app), initialHits = count("linkedHits", in: app)
        let batches = count("batch", in: app), loads = count("loads", in: app)
        XCTAssertGreaterThan(batches, 0)
        capture(app, "SYNTHETIC linked metadata before forced view reconstruction")
        for iteration in 1...3 {
            let recreate = app.buttons["feed.lifecycle.recreate"]
            XCTAssertTrue(recreate.waitForExistence(timeout: 5)); recreate.tap()
            assertReady(in: app)
            waitUntil { self.count("linkedHits", in: app) >= initialHits + iteration }
            assertReadsRemain(reads, in: app)
            XCTAssertEqual(count("batch", in: app), batches)
            XCTAssertEqual(count("loads", in: app), loads)
        }
        capture(app, "SYNTHETIC three feed view reconstructions reuse verified linked content")

        // Warm every row reached by this bounded path before comparing repeat
        // reads. First-time exposure of a different row is not a duplicate.
        app.swipeUp(); app.swipeUp(); app.swipeDown(); app.swipeDown()
        assertReady(in: app)
        let afterWarmScroll = count("linkedReads", in: app)
        app.swipeUp(); app.swipeUp(); app.swipeDown(); app.swipeDown()
        assertReady(in: app)
        assertReadsRemain(afterWarmScroll, in: app)
        capture(app, "SYNTHETIC repeated same-visit scroll preserves linked read count")

        selectTab("soom.tab.activity", in: app)
        selectTab("soom.tab.feed", in: app)
        assertReady(in: app)
        waitUntil { self.count("batch", in: app) > batches && self.count("linkedReads", in: app) > afterWarmScroll }
        XCTAssertEqual(count("loads", in: app), loads, "New authority must not require reloading the unchanged page")
        capture(app, "SYNTHETIC real tab return performs fresh authority and linked read")
    }

    func testPendingAndDeniedEpochNeverRestoresCachedLinkedMetadataOrRoute() {
        let app = launch(["SOOM_FEED_BATCH_HOLD_RETURN": "1", "SOOM_FEED_BATCH_DENY_AFTER_FIRST": "1"])
        defer { app.terminate() }
        assertReady(in: app)
        // Photos can finish before independently authorized linked geometry.
        // The shared pager correctly preserves that selected photo as route is
        // inserted at index zero. Explicitly select the real route page first.
        app.swipeUp()
        let pager = app.scrollViews["workout.media.pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5)); pager.swipeRight()
        let route = app.descendants(matching: .any).matching(identifier: "feed.lifecycle.linkedRoute").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10), "The test must first prove that the synthetic protected route rendered")
        waitUntil { route.value as? String == "재생 1회" }
        let reads = count("linkedReads", in: app)
        // Wait for the original animation to finish, then destroy and rebuild
        // the SwiftUI/hosting tree within the same authorized feed visit.
        let repeatFirst = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            route.value as? String != "재생 1회"
        }, object: nil)
        repeatFirst.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [repeatFirst], timeout: 5), .completed)
        capture(app, "SYNTHETIC protected route completes its first animation once")
        let recreate = app.buttons["feed.lifecycle.recreate"]
        XCTAssertTrue(recreate.waitForExistence(timeout: 5)); recreate.tap()
        assertReady(in: app)
        app.swipeUp()
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(route.frame.height, 100)
        XCTAssertGreaterThanOrEqual(route.frame.minY, 150)
        XCTAssertLessThanOrEqual(route.frame.maxY, app.frame.maxY - 100)
        XCTAssertEqual(route.value as? String, "재생 0회", "The rebuilt host must show the final route without starting another animation")
        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            route.value as? String != "재생 0회"
        }, object: nil)
        restarted.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [restarted], timeout: 2), .completed)
        assertReadsRemain(reads, in: app)
        capture(app, "SYNTHETIC fully visible reconstructed route keeps final frame without replay")
        selectTab("soom.tab.activity", in: app)
        selectTab("soom.tab.feed", in: app)
        let release = app.buttons["feed.lifecycle.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["feed.lifecycle.probe"].firstMatch.label.contains("pending"))
        XCTAssertFalse(title(in: app).exists)
        XCTAssertFalse(route.exists)
        assertReadsRemain(reads, in: app)
        capture(app, "SYNTHETIC pending new epoch hides cached title and route")
        release.tap()
        waitUntil { app.staticTexts["feed.lifecycle.probe"].firstMatch.label.contains("failed") }
        let leak = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.title(in: app).exists || route.exists }, object: nil)
        leak.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [leak], timeout: 3), .completed)
        assertReadsRemain(reads, in: app)
        capture(app, "SYNTHETIC denied new epoch cannot restore cached title or route")
    }

    func testFailedFreshBatchKeepsLinkedContentHiddenUntilManualRetry() {
        let app = launch(["SOOM_FEED_BATCH_FAIL_SECOND": "1"]); defer { app.terminate() }
        assertReady(in: app)
        let reads = count("linkedReads", in: app)
        selectTab("soom.tab.activity", in: app)
        selectTab("soom.tab.feed", in: app)
        waitUntil { app.staticTexts["feed.lifecycle.probe"].firstMatch.label.contains("failed") }
        XCTAssertFalse(title(in: app).exists)
        XCTAssertEqual(count("batch", in: app), 2)
        assertReadsRemain(reads, in: app)
        let automaticRetry = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.count("batch", in: app) != 2 }, object: nil)
        automaticRetry.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [automaticRetry], timeout: 2), .completed)
        let retry = app.buttons["feed.projection.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        assertReady(in: app)
        XCTAssertEqual(count("batch", in: app), 3)
        XCTAssertGreaterThan(count("linkedReads", in: app), reads)
        capture(app, "SYNTHETIC one manual fresh-batch retry restores linked content")
    }
    func testConfirmedCheerSurvivesFeedViewReconstructionWithoutStaleBatchRollback() {
        // live(row:) selects ProfileActivitySocialUIFixture.localFixture under
        // this Debug simulator flag. Its status/cheer_set transport and journal
        // are in memory; this test never invokes the Supabase social transport.
        let app = launch(["SOOM_PROFILE_SOCIAL_QA": "1"])
        defer { app.terminate() }
        assertReady(in: app)
        func visibleCheer() -> XCUIElement {
            let cheer = app.buttons["feed.projection.cheer"].firstMatch
            for _ in 0..<10 {
                if cheer.exists && cheer.isHittable && cheer.frame.maxY < app.frame.height - 100 { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.72))
                    .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.48)))
            }
            waitUntil { cheer.exists && cheer.isHittable && cheer.isEnabled }
            return cheer
        }
        var cheer = visibleCheer()
        let original = cheer.label
        XCTAssertTrue(["응원", "응원 취소"].contains(original), "The test must use the actual resolved cheer control")
        let changed = original == "응원" ? "응원 취소" : "응원"
        let batch = count("batch", in: app), loads = count("loads", in: app)
        cheer.tap()
        waitUntil { cheer.label == changed && cheer.isEnabled }
        capture(app, "SYNTHETIC actual cheer mutation confirmed before view reconstruction")

        // Recreate after both add and remove, so a hard-coded selected state
        // cannot satisfy the regression. Each mutation must finish first.
        for expected in [changed, original] {
            let recreate = app.buttons["feed.lifecycle.recreate"]
            XCTAssertTrue(recreate.waitForExistence(timeout: 5)); recreate.tap()
            assertReady(in: app)
            cheer = visibleCheer()
            waitUntil { cheer.label == expected && cheer.isEnabled }
            let rollback = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                cheer.exists && cheer.label != expected
            }, object: nil)
            rollback.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [rollback], timeout: 2), .completed)
            XCTAssertEqual(count("batch", in: app), batch, "Reconstruction must reuse the same batch, not hide stale-state rollback behind a fresh read")
            XCTAssertEqual(count("loads", in: app), loads)
            capture(app, "SYNTHETIC reconstructed feed preserves confirmed cheer " + expected)
            if expected == changed {
                cheer.tap()
                waitUntil { cheer.label == original && cheer.isEnabled }
            }
        }
    }

    private func paginationLaunch(_ extra: [String: String]) -> XCUIApplication {
        launch(["SOOM_FEED_PAGINATION_QA": "1", "SOOM_FEED_ENRICHMENT_QA": "0",
                "SOOM_PROFILE_PHOTO_QA": "0"].merging(extra) { _, new in new })
    }

    private func assertPageRequestsRemain(_ value: Int, in app: XCUIApplication, seconds: TimeInterval = 1) {
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.count("pageRequests", in: app) != value
        }, object: nil)
        unexpected.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: seconds), .completed)
    }

    private func paginationSmallScroll(_ app: XCUIApplication) {
        // Small increments stop immediately when row seven enters, before the
        // bottom sentinel. Full-screen flings could skip that evidence window.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.72))
        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)))
    }

    private func scrollUntilPageRequests(_ minimum: Int, in app: XCUIApplication) {
        for _ in 0..<80 {
            if count("pageRequests", in: app) >= minimum { break }
            paginationSmallScroll(app)
        }
        waitUntil { self.count("pageRequests", in: app) >= minimum }
    }

    func testPaginationPrefetchStartsBeforeFooterThenStopsAfterTwentyUniqueRows() {
        let app = paginationLaunch(["SOOM_FEED_PAGINATION_HOLD_SECOND": "1"])
        defer { app.terminate() }
        waitUntil { self.count("pageRows", in: app) == 8 && app.staticTexts["feed.lifecycle.probe"].firstMatch.label.contains("ready") }
        XCTAssertEqual(count("pageUnique", in: app), 8)
        XCTAssertEqual(count("pageMore", in: app), 1)
        assertPageRequestsRemain(0, in: app)
        capture(app, "SYNTHETIC initial eight rows do not prefetch from first viewport")

        scrollUntilPageRequests(1, in: app)
        waitUntil { self.count("pageHeld", in: app) == 1 }
        XCTAssertEqual(count("pageOffset", in: app), 8)
        XCTAssertEqual(count("pageRows", in: app), 8)
        XCTAssertEqual(count("pageUnique", in: app), 8)
        let ninth = app.descendants(matching: .any).matching(identifier: "feed.card.A9600000-0000-4000-8000-000000000009").firstMatch
        XCTAssertFalse(ninth.exists, "A held page must not fabricate or expose its ninth card")
        let footer = app.descendants(matching: .any).matching(identifier: "feed.nextPageBoundary").firstMatch
        let scrollFrame = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })?.frame ?? app.frame
        if footer.exists {
            XCTAssertTrue(footer.frame.intersection(scrollFrame).isEmpty,
                          "The next page must start while the footer is still outside the real scroll viewport")
        }
        assertPageRequestsRemain(1, in: app)
        capture(app, "SYNTHETIC actual near-tail visibility starts one held page before footer")
        let release = app.buttons["feed.pagination.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 5)); release.tap()
        waitUntil { self.count("pageRows", in: app) == 16 && self.count("pageHeld", in: app) == 0 }
        XCTAssertEqual(count("pageUnique", in: app), 16)
        assertPageRequestsRemain(1, in: app, seconds: 2)
        capture(app, "SYNTHETIC sixteen unique rows and no speculative page chain")

        scrollUntilPageRequests(2, in: app)
        waitUntil { self.count("pageRows", in: app) == 20 && self.count("pageMore", in: app) == 0 }
        XCTAssertEqual(count("pageUnique", in: app), 20)
        XCTAssertEqual(count("pageOffset", in: app), 16)
        XCTAssertEqual(count("pageRequests", in: app), 2)
        for _ in 0..<4 { app.swipeUp() }
        assertPageRequestsRemain(2, in: app, seconds: 2)
        capture(app, "SYNTHETIC twenty unique rows exhausted with no offset twenty request")
    }

    func testPaginationTransientRetryBudgetStopsThenOneManualRetryAppendsSamePage() {
        let app = paginationLaunch(["SOOM_FEED_PAGINATION_FAIL_SECOND_ONCE": "1"])
        defer { app.terminate() }
        waitUntil { self.count("pageRows", in: app) == 8 && app.staticTexts["feed.lifecycle.probe"].firstMatch.label.contains("ready") }
        assertPageRequestsRemain(0, in: app)
        scrollUntilPageRequests(1, in: app)
        waitUntil { self.count("pageRequests", in: app) == 3 && self.count("pageFailure", in: app) == 1 }
        let retry = app.buttons["이전 게시물 다시 불러오기"].firstMatch
        // Near-tail prefetch fails while the footer is still offscreen. A lazy
        // footer need not exist in AX until the user actually scrolls to it.
        XCTAssertEqual(count("pageRows", in: app), 8)
        XCTAssertEqual(count("pageUnique", in: app), 8)
        XCTAssertEqual(count("pageOffset", in: app), 8)
        assertPageRequestsRemain(3, in: app, seconds: 2)
        capture(app, "SYNTHETIC one failed page stops after three bounded transport attempts")
        for _ in 0..<12 {
            if retry.exists && retry.isHittable && retry.frame.maxY < app.frame.height - 100 { break }
            paginationSmallScroll(app)
        }
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.isHittable); retry.tap()
        waitUntil { self.count("pageRows", in: app) == 16 }
        XCTAssertEqual(count("pageUnique", in: app), 16)
        XCTAssertEqual(count("pageOffset", in: app), 8, "Failure must not advance the offset")
        XCTAssertEqual(count("pageRequests", in: app), 4)
        assertPageRequestsRemain(4, in: app, seconds: 2)
        capture(app, "SYNTHETIC one manual retry appends eight unique rows without skipping offset")
    }

}
