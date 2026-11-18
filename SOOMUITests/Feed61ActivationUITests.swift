import XCTest
import UIKit

/// Exercises production policy routing with synthetic ReviewDemo data only.
/// The legacy capability is deliberately true under deployed profileOnlyV2.
@MainActor
final class Feed61ActivationUITests: XCTestCase {
    func testLegacyPreviewCapabilityDoesNotDisableProfileOnlyBatchAndResidentHistory() {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment = [
            "SOOM_SYNTHETIC_UI_TESTS": "1",
            "SOOM_PROJECTION_SUMMARY_QA": "1",
            "SOOM_FEED_ENRICHMENT_QA": "1",
            "SOOM_FEED_BATCH_QA": "1",
            "SOOM_PROFILE_PHOTO_QA": "1",
            "SOOM_FEED_BATCH_SMALL_PHOTOS": "1",
            "SOOM_FEED_LIFECYCLE_QA": "1",
            "SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA": "1"
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["reviewDemo.start"].waitForExistence(timeout: 15))
        app.buttons["reviewDemo.start"].tap()
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 15))
        let tabs = app.buttons.matching(identifier: "soom.tab.feed")
        XCTAssertTrue(tabs.firstMatch.waitForExistence(timeout: 10))
        let tab = tabs.allElementsBoundByIndex.last { $0.isHittable } ?? tabs.firstMatch
        let frame = tab.frame.intersection(app.frame)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        func count(_ key: String) -> Int {
            let field = probe.label.split(separator: ";").first { $0.hasPrefix(key + "=") }
            return Int(field?.split(separator: "=").last ?? "") ?? -1
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            count("batch") > 0 && probe.label.contains("ready") && count("linkedEntries") > 0
        }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 20)
        let evidence = XCTAttachment(string: probe.label)
        evidence.name = "SYNTHETIC legacy capability true production batch routing"
        evidence.lifetime = .keepAlways
        add(evidence)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "SYNTHETIC profile-only feed legacy capability true"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(result, .completed,
                       "Legacy preview capability must not disable profile-only batch authority and resident linked content")
        let reads = count("linkedReads")
        XCTAssertGreaterThan(reads, 0)
        let recreate = app.buttons["feed.lifecycle.recreate"]
        XCTAssertTrue(recreate.waitForExistence(timeout: 5))
        recreate.tap()
        let reused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            count("linkedHits") > 0 && count("linkedEntries") > 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reused], timeout: 10), .completed)
        XCTAssertEqual(count("linkedReads"), reads,
                       "Rehosting within the same authority must reuse the verified resident entry")
    }
}
