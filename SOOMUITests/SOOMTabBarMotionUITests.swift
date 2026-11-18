import XCTest

@MainActor
final class SOOMTabBarMotionUITests: XCTestCase {
    private let tabs = ["feed", "activity", "record", "clubs", "profile"]

    private func launchDemo() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 8) {
            app.buttons["reviewDemo.start"].tap()
        }
        XCTAssertTrue(app.buttons["soom.tab.feed"].waitForExistence(timeout: 15))
        app.buttons["soom.tab.feed"].tap()
        return app
    }

    private func width(_ app: XCUIApplication) -> CGFloat { app.buttons["soom.tab.feed"].frame.width }

    private func expectWidth(_ app: XCUIApplication, _ expected: CGFloat, compact: Bool = false,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in
            compact ? self.width(app) < expected * 0.985 : abs(self.width(app) - expected) < 0.8
        }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5) == .completed,
                      "Tab bar width \(width(app)), expanded baseline \(expected), compact \(compact)", file: file, line: line)
        for name in tabs {
            let tab = app.buttons["soom.tab." + name]
            XCTAssertTrue(tab.isHittable, name, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tab.frame.width, 44, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44, file: file, line: line)
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func setReduceMotion(_ enabled: Bool) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        var reduce = settings.switches.matching(NSPredicate(format: "label IN %@", ["Reduce Motion", "동작 줄이기"])).firstMatch
        if !reduce.exists {
            let accessibility = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["Accessibility", "손쉬운 사용"])).firstMatch
            for _ in 0..<6 where !accessibility.isHittable { settings.swipeUp() }
            XCTAssertTrue(accessibility.isHittable)
            accessibility.tap()
            let motion = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["Motion", "동작"])).firstMatch
            XCTAssertTrue(motion.waitForExistence(timeout: 5))
            motion.tap()
            reduce = settings.switches.matching(NSPredicate(format: "label IN %@", ["Reduce Motion", "동작 줄이기"])).firstMatch
        }
        XCTAssertTrue(reduce.waitForExistence(timeout: 5))
        let expected = enabled ? "1" : "0"
        if reduce.value as? String != expected { reduce.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap() }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in reduce.value as? String == expected }, object: reduce)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    func testBothDirectionsJitterBounceTabsAndReturn() {
        setReduceMotion(false)
        let app = launchDemo()
        let expanded = width(app)
        capture(app, "01 Expanded navigation")
        app.swipeUp(velocity: .slow)
        capture(app, "02 Reading downward compact navigation")
        expectWidth(app, expanded, compact: true)

        // The gesture begins inside content, never over the floating controls.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
        let tiny = start.withOffset(CGVector(dx: 0, dy: 14))
        start.press(forDuration: 0.1, thenDragTo: tiny, withVelocity: .slow, thenHoldForDuration: 0.2)
        expectWidth(app, expanded, compact: true)
        capture(app, "03 Small reverse jitter remains compact")
        app.swipeDown(velocity: .slow)
        expectWidth(app, expanded)
        capture(app, "04 Reading upward restores navigation")

        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        expectWidth(app, expanded)
        capture(app, "05 Top rubber band remains expanded")
        for _ in 0..<9 { app.swipeUp(velocity: .fast) }
        expectWidth(app, expanded, compact: true)
        app.swipeUp(velocity: .fast)
        expectWidth(app, expanded, compact: true)
        capture(app, "06 Bottom rubber band remains compact")

        for tab in ["activity", "clubs", "profile", "feed"] {
            app.buttons["soom.tab." + tab].tap()
            expectWidth(app, expanded)
        }
        app.swipeUp(velocity: .slow)
        expectWidth(app, expanded, compact: true)
        XCUIDevice.shared.press(.home)
        app.activate()
        expectWidth(app, expanded)
        capture(app, "07 Foreground return restores navigation")


    }

    func testCompactRecordButtonOpensRecording() throws {
        // iOS 18 + this Xcode's XCTAutomationSupport crashes inside Mapbox logging.
        // Keep this separate from the scroll scenarios and report the platform limitation.
        try XCTSkipIf(ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26,
                      "iOS 18 XCTest/Mapbox Metal rendering crash; verified on iOS 26 separately")
        setReduceMotion(false)
        let app = launchDemo()
        let expanded = width(app)
        app.swipeUp(velocity: .slow)
        expectWidth(app, expanded, compact: true)
        app.buttons["soom.tab.record"].tap()
        XCTAssertTrue(app.buttons["record.manualWorkout"].waitForExistence(timeout: 8),
                      "Central record control opens the existing recording surface while compact")
        capture(app, "08 Compact record button opens recording")
    }

    func testSheetKeyboardAndDismissRestoreNavigation() {
        setReduceMotion(false)
        let app = launchDemo()
        let expanded = width(app)
        app.swipeUp(velocity: .slow)
        expectWidth(app, expanded, compact: true)
        app.buttons["soom.tab.profile"].tap()
        expectWidth(app, expanded)
        // The short default profile remains expanded; editing uses an existing sheet.
        let edit = app.buttons["profile.edit"]
        for _ in 0..<4 where !edit.isHittable { app.swipeDown() }
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture(app, "09 Profile sheet with keyboard")
        app.swipeDown()
        let cancel = app.buttons["취소"].firstMatch
        if cancel.isHittable { cancel.tap() }
        else { app.swipeDown(velocity: .fast) }
        expectWidth(app, expanded)
        capture(app, "10 Sheet dismissed expanded navigation")
    }

    func testReduceMotionKeepsNavigationExpanded() {
        setReduceMotion(true)
        defer { setReduceMotion(false) }
        let app = launchDemo()
        let expanded = width(app)
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        expectWidth(app, expanded)
        app.swipeDown(velocity: .slow)
        expectWidth(app, expanded)
        capture(app, "11 Reduce Motion navigation stays expanded")
    }
}
