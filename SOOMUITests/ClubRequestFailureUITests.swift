import XCTest

@MainActor
final class ClubRequestFailureUITests: XCTestCase {
    private func check(_ scenario: String, expected: String, canRetry: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_UX_CLUB_STATE"] = scenario
        app.launch()
        defer { app.terminate() }
        let demo = app.buttons["reviewDemo.start"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15)); demo.tap()
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 15))
        let clubs = app.buttons["soom.tab.clubs"]
        XCTAssertTrue(clubs.waitForExistence(timeout: 8)); clubs.tap()
        let create = app.buttons["clubs.create.open"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 8)); create.tap()
        let name = app.textFields["club.create.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8)); name.tap(); name.typeText("Synthetic club")
        let purpose = app.textFields["club.create.purpose"]
        purpose.tap(); purpose.typeText("Synthetic only\n")
        let submit = app.buttons["club.create.submit"]
        for _ in 0..<4 { if submit.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(submit.isHittable); submit.tap()
        let error = app.staticTexts["club.create.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(error.label.contains(expected), error.label)
        XCTAssertFalse(error.label.contains("연결 상태"))
        XCTAssertFalse(app.buttons["club.create.localConfirm"].exists)
        XCTAssertEqual(submit.isEnabled, canRetry)
        XCTAssertEqual(name.value as? String, "Synthetic club")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Synthetic Club - " + scenario
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testPermissionErrorKeepsInputAndExplainsAccess() {
        check("create_permission_denied", expected: "권한", canRetry: true)
    }
    func testServerErrorDoesNotPretendNetworkOrLocalSuccess() {
        check("create_server_schema", expected: "서버", canRetry: true)
    }
    func testUncertainCreationRequiresReadBeforeRepeatedSubmit() {
        check("create_timeout", expected: "목록", canRetry: false)
    }
}
