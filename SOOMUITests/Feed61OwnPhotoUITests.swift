import XCTest
import UIKit

/// Uses the SAME mixed fixture and production batch routing as the scroll tests.
/// The first row is an actual isolated Demo workout, with its local legacy photo.
@MainActor
final class Feed61OwnPhotoUITests: XCTestCase {
    func testBatchAuthorizedOwnedLegacyPhotoPublishesActualFeedPixels() {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment = [
            "SOOM_SYNTHETIC_UI_TESTS": "1", "SOOM_PROJECTION_SUMMARY_QA": "1",
            "SOOM_FEED_BATCH_QA": "1", "SOOM_PROFILE_PHOTO_QA": "1",
            "SOOM_FEED_BATCH_SMALL_PHOTOS": "1", "SOOM_FEED_LIFECYCLE_QA": "1",
            "SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA": "1", "SOOM_FEED_OWN_PHOTO_GRANT_QA": "1",
            "SOOM_FEED_MIXED_REUSE_QA": "1", "SOOM_FEED_MIXED_REUSE_COUNT": "48"
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
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let field = probe.label.split(separator: ";").first { $0.hasPrefix("batch=") }
            return (Int(field?.split(separator: "=").last ?? "") ?? 0) > 0 && probe.label.contains("ready")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        let own = app.otherElements["feed.card.A9611000-0000-4000-8000-000000000001"].firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 10))
        XCTAssertTrue(own.staticTexts["총 시간"].firstMatch.waitForExistence(timeout: 10))
        let pager = own.descendants(matching: .any).matching(identifier: "workout.media.pager").firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        // Keep the own card's horizontal pager on-screen, without navigating to
        // a foreign row or accidentally swiping the vertical feed.
        for _ in 0..<3 {
            if pager.frame.minY >= 150 && pager.frame.maxY <= app.frame.maxY - 100 { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.50))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertGreaterThanOrEqual(pager.frame.minY, 150)
        XCTAssertLessThanOrEqual(pager.frame.maxY, app.frame.maxY - 100)
        let route = own.descendants(matching: .any).matching(identifier: "workout.card.routePreview").firstMatch
        XCTAssertTrue(route.exists, "The first owned row must retain its real local route")
        pager.swipeLeft()
        let selectedPhoto = own.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "2페이지 중 2페이지")).firstMatch
        XCTAssertTrue(selectedPhoto.waitForExistence(timeout: 10), "The local seeded photo must be the selected own-card page")
        // Restrict to the OWN card, not any decode probe elsewhere in the feed.
        // This production overlay exists only when displayedImage is non-nil.
        let pixels = own.staticTexts.matching(identifier: "workout.photo.decodeProbe")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "kind=feed;")).firstMatch
        let displayed = pixels.waitForExistence(timeout: 20)
        let counters = XCTAttachment(string: probe.label + "\nownedPhotoPixels=" + (displayed ? pixels.label : "absent"))
        counters.name = "SYNTHETIC same-batch owned legacy photo pixel proof"; counters.lifetime = .keepAlways; add(counters)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "SYNTHETIC owned photo selected under current batch"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertTrue(displayed, "Current exact batch photo authority must reach the owned card instead of the untyped local metadata path")
        let dimensions = pixels.label.split(separator: ";").dropFirst().compactMap { Int($0.split(separator: "=").last ?? "") }
        XCTAssertEqual(dimensions.count, 2)
        XCTAssertTrue(dimensions.allSatisfy { $0 > 0 }, "Prove decoded pixels, not a placeholder or metadata-only page")
    }

    func testForegroundDenialCannotRestorePreviouslyDisplayedOwnedLegacyPhoto() {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment = [
            "SOOM_SYNTHETIC_UI_TESTS": "1", "SOOM_PROJECTION_SUMMARY_QA": "1",
            "SOOM_FEED_BATCH_QA": "1", "SOOM_PROFILE_PHOTO_QA": "1",
            "SOOM_FEED_BATCH_SMALL_PHOTOS": "1", "SOOM_FEED_LIFECYCLE_QA": "1",
            "SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA": "1", "SOOM_FEED_OWN_PHOTO_GRANT_QA": "1", "SOOM_FEED_BATCH_DENY_AFTER_FIRST": "1",
            "SOOM_FEED_MIXED_REUSE_QA": "1", "SOOM_FEED_MIXED_REUSE_COUNT": "48"
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
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let field = probe.label.split(separator: ";").first { $0.hasPrefix("batch=") }
            return (Int(field?.split(separator: "=").last ?? "") ?? 0) > 0 && probe.label.contains("ready")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        let own = app.otherElements["feed.card.A9611000-0000-4000-8000-000000000001"].firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 10))
        XCTAssertTrue(own.staticTexts["총 시간"].firstMatch.waitForExistence(timeout: 10))
        let pager = own.descendants(matching: .any).matching(identifier: "workout.media.pager").firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        // Keep the own card's horizontal pager on-screen, without navigating to
        // a foreign row or accidentally swiping the vertical feed.
        for _ in 0..<3 {
            if pager.frame.minY >= 150 && pager.frame.maxY <= app.frame.maxY - 100 { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.50))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertGreaterThanOrEqual(pager.frame.minY, 150)
        XCTAssertLessThanOrEqual(pager.frame.maxY, app.frame.maxY - 100)
        let route = own.descendants(matching: .any).matching(identifier: "workout.card.routePreview").firstMatch
        XCTAssertTrue(route.exists, "The first owned row must retain its real local route")
        pager.swipeLeft()
        let selectedPhoto = own.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "2페이지 중 2페이지")).firstMatch
        XCTAssertTrue(selectedPhoto.waitForExistence(timeout: 10), "The local seeded photo must be the selected own-card page")
        // Restrict to the OWN card, not any decode probe elsewhere in the feed.
        // This production overlay exists only when displayedImage is non-nil.
        let pixels = own.staticTexts.matching(identifier: "workout.photo.decodeProbe")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "kind=feed;")).firstMatch
        let displayed = pixels.waitForExistence(timeout: 20)
        let counters = XCTAttachment(string: probe.label + "\nownedPhotoPixels=" + (displayed ? pixels.label : "absent"))
        counters.name = "SYNTHETIC same-batch owned legacy photo pixel proof"; counters.lifetime = .keepAlways; add(counters)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "SYNTHETIC owned photo selected under current batch"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertTrue(displayed, "Current exact batch photo authority must reach the owned card instead of the untyped local metadata path")
        let dimensions = pixels.label.split(separator: ";").dropFirst().compactMap { Int($0.split(separator: "=").last ?? "") }
        XCTAssertEqual(dimensions.count, 2)
        XCTAssertTrue(dimensions.allSatisfy { $0 > 0 }, "Prove decoded pixels, not a placeholder or metadata-only page")
        func batchCount() -> Int {
            let field = probe.label.split(separator: ";").first { $0.hasPrefix("batch=") }
            return Int(field?.split(separator: "=").last ?? "") ?? -1
        }
        let firstBatch = batchCount()
        XCTAssertEqual(firstBatch, 1, "Warm exactly the initial authorized batch before revocation")
        XCUIDevice.shared.press(.home)
        app.activate()
        // A denied member invalidates the whole loaded prefix. The existing
        // bounded reload retries once, then ends failed/closed, not ready.
        let revoked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            batchCount() >= 2 && probe.label.contains("failed")
        }, object: nil)
        let revokedResult = XCTWaiter.wait(for: [revoked], timeout: 20)
        let returnEvidence = XCTAttachment(string: probe.label)
        returnEvidence.name = "SYNTHETIC foreground denial completed batch state"
        returnEvidence.lifetime = .keepAlways; add(returnEvidence)
        XCTAssertEqual(revokedResult, .completed)
        // SwiftUI exposes the outer feed.card identifier on this same node;
        // the pending branch ID is not a second nested accessibility element.
        // Assert the observed denied branch INSIDE this exact owned card.
        let pendingRetry = own.buttons["feed.projection.retry"].firstMatch
        XCTAssertTrue(pendingRetry.waitForExistence(timeout: 10), "The denied owned card must be masked, not fall back to local content")
        XCTAssertTrue(own.staticTexts["운동 요약을 확인할 수 없어요"].firstMatch.exists)
        let branchEvidence = XCTAttachment(string: own.debugDescription)
        branchEvidence.name = "SYNTHETIC exact owned denied branch accessibility"
        branchEvidence.lifetime = .keepAlways; add(branchEvidence)
        XCTAssertFalse(pixels.exists)
        XCTAssertFalse(own.staticTexts["총 시간"].firstMatch.exists)
        XCTAssertFalse(route.exists)
        let leak = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pixels.exists || own.staticTexts["총 시간"].firstMatch.exists || route.exists
        }, object: nil)
        leak.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [leak], timeout: 3), .completed)
        let deniedEvidence = XCTAttachment(string: probe.label)
        deniedEvidence.name = "SYNTHETIC fresh foreground denial masks owned local photo"; deniedEvidence.lifetime = .keepAlways; add(deniedEvidence)
        let deniedScreen = XCTAttachment(screenshot: app.screenshot())
        deniedScreen.name = "SYNTHETIC owned card remains masked after denial"; deniedScreen.lifetime = .keepAlways; add(deniedScreen)

    }

    func testCurrentBatchWithoutOwnedPhotoEnvelopeNeverFallsBackToLocalPhoto() {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment = [
            "SOOM_SYNTHETIC_UI_TESTS": "1", "SOOM_PROJECTION_SUMMARY_QA": "1",
            "SOOM_FEED_BATCH_QA": "1", "SOOM_PROFILE_PHOTO_QA": "1",
            "SOOM_FEED_BATCH_SMALL_PHOTOS": "1", "SOOM_FEED_LIFECYCLE_QA": "1",
            "SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA": "1", "SOOM_FEED_OWN_PHOTO_GRANT_QA": "0",
            "SOOM_FEED_MIXED_REUSE_QA": "1", "SOOM_FEED_MIXED_REUSE_COUNT": "48"
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
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let field = probe.label.split(separator: ";").first { $0.hasPrefix("batch=") }
            return (Int(field?.split(separator: "=").last ?? "") ?? 0) > 0 && probe.label.contains("ready")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        let own = app.otherElements["feed.card.A9611000-0000-4000-8000-000000000001"].firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 10))
        XCTAssertTrue(own.staticTexts["총 시간"].firstMatch.waitForExistence(timeout: 10))
        let pager = own.descendants(matching: .any).matching(identifier: "workout.media.pager").firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        // Keep the own card's horizontal pager on-screen, without navigating to
        // a foreign row or accidentally swiping the vertical feed.
        for _ in 0..<3 {
            if pager.frame.minY >= 150 && pager.frame.maxY <= app.frame.maxY - 100 { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.50))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertGreaterThanOrEqual(pager.frame.minY, 150)
        XCTAssertLessThanOrEqual(pager.frame.maxY, app.frame.maxY - 100)
        let route = own.descendants(matching: .any).matching(identifier: "workout.card.routePreview").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10), "Absent photo authority must not hide an otherwise allowed local route")
        XCTAssertTrue(own.staticTexts["총 시간"].firstMatch.exists)
        let pixels = own.staticTexts.matching(identifier: "workout.photo.decodeProbe").firstMatch
        let photoPage = own.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@", "2페이지 중")).firstMatch
        XCTAssertFalse(photoPage.exists, "Null photo envelope must mean no photo page, not unknown local metadata")
        XCTAssertFalse(pixels.exists)
        pager.swipeLeft()
        let leak = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in pixels.exists || photoPage.exists }, object: nil)
        leak.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [leak], timeout: 3), .completed)
        XCTAssertTrue(route.exists)
        XCTAssertTrue(own.staticTexts["총 시간"].firstMatch.exists)
        let evidence = XCTAttachment(string: probe.label)
        evidence.name = "SYNTHETIC allowed owned row null photo envelope never uses seeded local photo"; evidence.lifetime = .keepAlways; add(evidence)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "SYNTHETIC own route and metrics remain without unauthorized photo page"; screen.lifetime = .keepAlways; add(screen)
    }

}
