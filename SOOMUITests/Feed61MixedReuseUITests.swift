import XCTest
import UIKit

/// Natural scrolling with production batch routing and isolated synthetic rows.
/// No forced feed recreation, real account, server response, or private route.
@MainActor
final class Feed61MixedReuseUITests: XCTestCase {
    func testMixed48RowsPreserveWarmCardsBelowVisibleBatchBoundary() { exercise(total: 48) }
    func testMixed80RowsPreserveWarmCardsAcrossVisibleBatchBoundary() { exercise(total: 80) }

    private func exercise(total: Int) {
        continueAfterFailure = false
        executionTimeAllowance = 600
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment = [
            "SOOM_SYNTHETIC_UI_TESTS": "1", "SOOM_PROJECTION_SUMMARY_QA": "1",
            "SOOM_FEED_BATCH_QA": "1", "SOOM_PROFILE_PHOTO_QA": "1",
            "SOOM_FEED_BATCH_SMALL_PHOTOS": "1", "SOOM_FEED_LIFECYCLE_QA": "1",
            "SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA": "1",
            "SOOM_FEED_MIXED_REUSE_QA": "1", "SOOM_FEED_MIXED_REUSE_COUNT": String(total)
        ]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["reviewDemo.start"].waitForExistence(timeout: 15))
        app.buttons["reviewDemo.start"].tap()
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 15))
        let tabs = app.buttons.matching(identifier: "soom.tab.feed")
        XCTAssertTrue(tabs.firstMatch.waitForExistence(timeout: 10))
        let tab = tabs.allElementsBoundByIndex.last { $0.isHittable } ?? tabs.firstMatch
        let frame = tab.frame.intersection(app.frame)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        wait { self.count("pageRows", app) == 8 && self.count("batch", app) > 0 }
        let first = app.otherElements["feed.card.A9611000-0000-4000-8000-000000000001"].firstMatch
        wait { first.exists && first.staticTexts["총 시간"].firstMatch.exists }
        let ownRoute = first.descendants(matching: .any).matching(identifier: "workout.card.routePreview").firstMatch
        XCTAssertTrue(ownRoute.waitForExistence(timeout: 15), "The owned fixture must render its real local route, not just a summary")
        capture(app, "mixed initial own real workout and batch")

        // Exercise real repository pages rather than injecting a preloaded array.
        for boundary in (total == 48 ? [48] : [48, 56, 80]) {
            for _ in 0..<60 {
                if count("pageRows", app) >= boundary { break }
                app.swipeUp(velocity: .fast)
            }
            wait { self.count("pageRows", app) >= boundary }
            XCTAssertEqual(count("pageUnique", app), count("pageRows", app))
            XCTAssertGreaterThan(count("granted", app), 0)
            capture(app, "mixed loaded prefix at boundary \(boundary)")
        }
        XCTAssertEqual(count("pageRows", app), total)
        wait { self.count("pageMore", app) == 0 }
        XCTAssertEqual(count("mixedRequests", app), total / 8 - 1)
        let requests = count("mixedRequests", app)
        returnToFirst(first, app)

        // Warm the same bounded path twice before measuring a repeated path.
        // This excludes first-time row authority/media work from repeat counts.
        for _ in 0..<2 {
            for _ in 0..<5 { app.swipeUp(velocity: .fast) }
            returnToFirst(first, app)
        }
        wait { self.count("inflight", app) == 0 }
        let avatarMisses = count("avatarMiss", app)
        let ownPlaceholders = count("ownPlaceholder", app)
        let foreignPlaceholders = count("foreignPlaceholder", app)
        XCTAssertGreaterThanOrEqual(ownPlaceholders, 0, "Placeholder instrumentation must be present")
        XCTAssertGreaterThanOrEqual(foreignPlaceholders, 0)
        let epoch = count("epoch", app)
        let batches = count("batch", app)
        let mapReplays = count("mapReplays", app)
        XCTAssertGreaterThan(mapReplays, 0, "The real route must have played before checking repeat suppression")
        capture(app, "mixed warmed bidirectional path")
        for _ in 0..<5 { app.swipeUp(velocity: .fast) }
        returnToFirst(first, app)
        XCTAssertEqual(count("pageRows", app), total)
        XCTAssertEqual(count("pageUnique", app), total)
        XCTAssertEqual(count("mixedRequests", app), requests, "Exhausted feed must not request another page")
        XCTAssertEqual(count("epoch", app), epoch, "Scrolling is not a new authorization epoch")
        XCTAssertEqual(count("batch", app), batches, "The same warmed path must not repeat its batch authorization")
        XCTAssertEqual(count("avatarMiss", app), avatarMisses, "Same authorized avatar must not be downloaded again")
        XCTAssertEqual(count("ownPlaceholder", app), ownPlaceholders, "Warmed own cards must not recreate the placeholder branch, including prefetch")
        XCTAssertEqual(count("foreignPlaceholder", app), foreignPlaceholders, "Warmed authorized foreign cards must not recreate the placeholder branch, including prefetch")
        XCTAssertEqual(count("mapReplays", app), mapReplays, "The same warmed routes must not restart their playback")
        capture(app, "mixed warm natural round trip completed")
    }

    private func returnToFirst(_ first: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<65 {
            if first.exists && first.frame.minY > 100 && first.frame.minY < app.frame.height / 2 { break }
            app.swipeDown(velocity: .fast)
        }
        wait { first.exists && first.staticTexts["총 시간"].firstMatch.exists && first.frame.minY > 100 && first.frame.minY < app.frame.height / 2 }
    }
    private func count(_ key: String, _ app: XCUIApplication) -> Int {
        let field = app.staticTexts["feed.lifecycle.probe"].firstMatch.label.split(separator: ";").first { $0.hasPrefix(key + "=") }
        return Int(field?.split(separator: "=").last ?? "") ?? -1
    }
    private func wait(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 20), .completed, file: file, line: line)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let counters = XCTAttachment(string: app.staticTexts["feed.lifecycle.probe"].firstMatch.label)
        counters.name = name + " counters"; counters.lifetime = .keepAlways; add(counters)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}


/// C1 diagnostic only. Completion means the fixed observation window elapsed,
/// NOT that feed rendering, pagination, accessibility or reuse passed.
@MainActor
final class Feed61NativeInputC1DiagnosticUITests: XCTestCase {
    func testDefaultDiagnosticsLaunchThenWait300Seconds() async {
        continueAfterFailure = false
        executionTimeAllowance = 360
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment = [
            "SOOM_SYNTHETIC_UI_TESTS": "1", "SOOM_PROJECTION_SUMMARY_QA": "1",
            "SOOM_FEED_BATCH_QA": "1", "SOOM_PROFILE_PHOTO_QA": "1",
            "SOOM_FEED_BATCH_SMALL_PHOTOS": "1", "SOOM_FEED_LIFECYCLE_QA": "1",
            "SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA": "1",
            "SOOM_FEED_MIXED_REUSE_QA": "1", "SOOM_FEED_MIXED_REUSE_COUNT": "48"
        ]
        let windowElapsed = expectation(description: "C1 diagnostic 300-second timer only")
        app.launch()
        let ready = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        print("C1_READY utc=\(ISO8601DateFormatter().string(from: ready)) uptime=\(uptime) window_seconds=300 diagnostic_not_feed_pass=true")
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            windowElapsed.fulfill()
        }
        await fulfillment(of: [windowElapsed], timeout: 315)
        print("C1_WINDOW_ENDED utc=\(ISO8601DateFormatter().string(from: Date())) uptime=\(ProcessInfo.processInfo.systemUptime) diagnostic_not_feed_pass=true")
        // No app query, gesture, screenshot or terminate after launch.
        // Parent owns external exact-bundle cleanup and outcome interpretation.
        withExtendedLifetime(app) {}
    }
}
