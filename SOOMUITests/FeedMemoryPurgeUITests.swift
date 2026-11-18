import XCTest

/// Separate synthetic asset-cardinality experiment; not the strict48/80 tests.
@MainActor final class FeedMemoryPurgeUITests: XCTestCase {
    func testSelectedPhotoAndCardPositionSurviveMemoryWarning() { exercise(groups: 2) }
    private func exercise(groups: Int) {
        continueAfterFailure = false
        executionTimeAllowance = 600
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment = [
            "SOOM_SYNTHETIC_UI_TESTS": "1", "SOOM_PROJECTION_SUMMARY_QA": "1",
            "SOOM_FEED_BATCH_QA": "1", "SOOM_PROFILE_PHOTO_QA": "1",
            "SOOM_FEED_LIFECYCLE_QA": "1",
            "SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA": "1",
            "SOOM_FEED_MIXED_REUSE_QA": "1", "SOOM_FEED_MIXED_REUSE_COUNT": "16",
            "SOOM_UNIQUE_PHOTO_GROUPS": String(groups), "SOOM_MEMORY_PURGE_QA": "1"
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
        capture(app, "unique initial counters")
        for ordinal in [2, 6] {
            let id = String(format: "feed.card.A9611000-0000-4000-8000-%012d", ordinal)
            let card = app.otherElements[id].firstMatch
            let pager = card.descendants(matching: .any).matching(identifier: "workout.media.pager").firstMatch
            for _ in 0..<30 {
                if pager.exists && pager.isHittable && pager.frame.minY >= 150 && pager.frame.maxY <= app.frame.maxY - 100 { break }
                let moveDown = pager.exists && pager.frame.minY < 150
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: moveDown ? 0.50 : 0.72))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: moveDown ? 0.72 : 0.50))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(pager.isHittable, "Target media row must be reachable naturally")
            XCTAssertGreaterThanOrEqual(pager.frame.minY, 150)
            XCTAssertLessThanOrEqual(pager.frame.maxY, app.frame.maxY - 100)
            for slot in 1...4 {
                wait { card.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "4페이지 중 \(slot)페이지")).firstMatch.exists }
                wait { card.staticTexts["workout.photo.decodeProbe"].firstMatch.exists }
                capture(app, "unique row \(ordinal) slot \(slot)")
                if slot < 4 { pager.swipeLeft(velocity: .slow) }
            }
            for _ in 0..<3 { pager.swipeRight(velocity: .slow) }
            wait { card.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "4페이지 중 1페이지")).firstMatch.exists }
        }
        for _ in 0..<20 {
            if count("pageRows", app) == 16 { break }
            app.swipeUp(velocity: .slow)
        }
        wait { self.count("pageRows", app) == 16 && self.count("pageMore", app) == 0 }
        XCTAssertEqual(count("pageUnique", app), 16)
        XCTAssertEqual(count("mixedRequests", app), 1)
        XCTAssertEqual(count("pageFailure", app), 0)
        capture(app, "unique final counters")
        let targetID = "feed.card.A9611000-0000-4000-8000-000000000006"
        let target = app.otherElements[targetID].firstMatch
        let pager = target.descendants(matching: .any).matching(identifier: "workout.media.pager").firstMatch
        for _ in 0..<40 {
            if pager.exists && pager.isHittable && pager.frame.minY >= 150 && pager.frame.maxY <= app.frame.maxY - 100 { break }
            let moveDown = pager.exists && pager.frame.minY < 150
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: moveDown ? 0.50 : 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: moveDown ? 0.72 : 0.50))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(pager.isHittable)
        XCTAssertGreaterThanOrEqual(pager.frame.minY, 150)
        XCTAssertLessThanOrEqual(pager.frame.maxY, app.frame.maxY - 100)
        wait { target.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "4페이지 중 1페이지")).firstMatch.exists }
        pager.swipeLeft(velocity: .slow); pager.swipeLeft(velocity: .slow)
        wait { target.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "4페이지 중 3페이지")).firstMatch.exists }
        wait { target.staticTexts["workout.photo.decodeProbe"].firstMatch.exists && self.count("inflight", app) == 0 }
        let beforeCard = target.frame, beforePager = pager.frame
        let beforeInvalidations = count("invalidations", app)
        XCTAssertGreaterThanOrEqual(beforeInvalidations, 0)
        XCTAssertGreaterThanOrEqual(beforeInvalidations, 0)
        let button = app.buttons["feed.memoryPurge.once"].firstMatch
        XCTAssertTrue(button.isHittable)
        XCTAssertEqual(button.value as? String, "issued=0;published=0")
        position(targetID, beforeCard, beforePager, "memory pre position")
        capture(app, "memory pre purge")
        button.tap() // Exactly one existing NotificationCenter memory-warning post.
        // No scroll, selection change or corrective gesture after this point.
        wait { button.value as? String == "issued=1;published=1" }
        wait { self.count("invalidations", app) > beforeInvalidations && self.count("inflight", app) == 0 }
        XCTAssertTrue(target.exists)
        XCTAssertTrue(target.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "4페이지 중 3페이지")).firstMatch.exists)
        XCTAssertTrue(target.staticTexts["workout.photo.decodeProbe"].firstMatch.exists)
        let afterCard = target.frame, afterPager = pager.frame
        for (a, b) in [(beforeCard.minX,afterCard.minX),(beforeCard.minY,afterCard.minY),
                       (beforeCard.width,afterCard.width),(beforeCard.height,afterCard.height),
                       (beforePager.minX,afterPager.minX),(beforePager.minY,afterPager.minY),
                       (beforePager.width,afterPager.width),(beforePager.height,afterPager.height)] {
            XCTAssertLessThanOrEqual(abs(a - b), 2, "No position restoration allowed; fixed 2pt tolerance")
        }
        XCTAssertEqual(count("pageRows", app),16); XCTAssertEqual(count("pageUnique", app),16)
        XCTAssertEqual(count("pageFailure", app),0); XCTAssertEqual(count("mixedRequests", app),1)
        position(targetID, afterCard, afterPager, "memory post position")
        capture(app, "memory post purge")

    }
    private func position(_ id: String, _ card: CGRect, _ pager: CGRect, _ name: String) {
        let value: [String: Any] = ["cardID": id, "selection": "4페이지 중 3페이지",
            "card": [card.minX,card.minY,card.width,card.height],
            "pager": [pager.minX,pager.minY,pager.width,pager.height], "tolerancePoints": 2]
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func count(_ key: String, _ app: XCUIApplication) -> Int {
        let label = app.staticTexts["feed.lifecycle.probe"].firstMatch.label
        return Int(label.split(separator: ";").first(where: { $0.hasPrefix(key + "=") })?.dropFirst(key.count + 1) ?? "") ?? -1
    }
    private func wait(_ predicate: @escaping () -> Bool) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: 15), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let counters = XCTAttachment(string: app.staticTexts["feed.lifecycle.probe"].firstMatch.label)
        counters.name = name; counters.lifetime = .keepAlways; add(counters)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = name + " screen"; screen.lifetime = .keepAlways; add(screen)
    }
}
