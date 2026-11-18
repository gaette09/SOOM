import XCTest
import UIKit

/// Run on an erased simulator, or uninstall app.soom.prototype before this test.
/// Synthetic fixtures require an explicit Debug simulator-only launch flag;
/// ordinary launches and every Release build keep the entry closed.
@MainActor
final class ReviewDemoUITests: XCTestCase {
    private func assertActivityFinalWorkoutClearsFloatingTabs(largeText:Bool) {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=XCUIApplication()
        app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        if largeText {app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]}
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"]="1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"]="missing"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"]="1"
        app.launch();defer{app.terminate()}
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:5){tap(app.buttons["reviewDemo.start"],in:app)}
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.today"],in:app)
        // The calculation fixture itself is intentionally read-only. Opening
        // and cancelling its real input route installs this synthetic row,
        // so the production deleted-record guard remains enforced.
        openSimpleEffort(in:app);tap(app.buttons["effort.cancel"],in:app)
        XCTAssertTrue(app.buttons["effort.cancel"].waitForNonExistence(timeout:8))
        let finalRow=app.buttons["activity.load.workout.D2F85654-F4D9-5602-93AB-53DE487AB46C"]
        let tab=app.buttons["soom.tab.activity"]
        XCTAssertTrue(tab.waitForExistence(timeout:5))
        for _ in 0..<16 {
            if finalRow.exists && finalRow.frame.maxY < tab.frame.minY-8 {break}
            app.swipeUp()
        }
        XCTAssertTrue(finalRow.exists);XCTAssertTrue(finalRow.isHittable)
        XCTAssertGreaterThanOrEqual(finalRow.frame.height,44)
        XCTAssertLessThan(finalRow.frame.maxY,tab.frame.minY-8,"Final row must clear the overlay, not just report isHittable")
        capture(app,name:largeText ? "SYNTHETIC last activity row clears floating tabs at maximum text" : "SYNTHETIC last activity row clears floating tabs")
        // A physical coordinate tap catches overlay interception that an
        // accessibility activation alone can miss.
        finalRow.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        let effort=app.buttons["effort.open"]
        reveal(effort,in:app);XCTAssertTrue(effort.waitForExistence(timeout:8))
        capture(app,name:largeText ? "SYNTHETIC last activity row opens detail at maximum text" : "SYNTHETIC last activity row opens detail")
    }
    func testActivityFinalWorkoutClearsFloatingTabsAndCoordinateTapOpensDetail() {
        assertActivityFinalWorkoutClearsFloatingTabs(largeText:false)
    }
    func testActivityFinalWorkoutClearsFloatingTabsAtMaximumText() {
        assertActivityFinalWorkoutClearsFloatingTabs(largeText:true)
    }

    private func assertAutomaticScoreComparisonWithoutManualRatings(large:Bool) throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=detailFixtureApp(gesture:true);defer{app.terminate()}
        selectEffortFixture("자동 점수 범위",in:app)
        if large {tap(app.switches["큰 글자"],in:app)}
        openEffort(in:app)
        let summary=app.staticTexts["effort.range.summary"]
        let foundSummary=summary.waitForExistence(timeout:5)
        if !foundSummary {
            capture(app,name:"SYNTHETIC missing comparison summary actual card")
            let hierarchy=XCTAttachment(string:app.debugDescription);hierarchy.name="SYNTHETIC comparison card hierarchy";hierarchy.lifetime = .keepAlways;add(hierarchy)
        }
        XCTAssertTrue(foundSummary);XCTAssertTrue(summary.label.contains("자동 7개/수정 0개"))
        XCTAssertTrue(summary.label.contains("점수 추정 범위"));XCTAssertTrue(summary.label.contains("낮은 신뢰"))
        XCTAssertFalse(app.staticTexts["effort.range.empty"].exists)
        capture(app,name:large ? "SYNTHETIC automatic reference maximum text no manual requirement" : "SYNTHETIC automatic reference seven scores zero manual inputs")
        try assertEffortGestureOwnsParent(in:app,hasRange:true,name:large ? "automatic comparison maximum text" : "automatic comparison no manual ratings")
        tap(app.buttons["effort.cancel"],in:app)
    }
    func testAutomaticScoreComparisonWithoutManualRatings() throws {try assertAutomaticScoreComparisonWithoutManualRatings(large:false)}
    func testAutomaticScoreComparisonMaximumText() throws {try assertAutomaticScoreComparisonWithoutManualRatings(large:true)}

    func testUnreviewedAutomaticScoresRenderDailyPointsWithoutInventingTrendOrRest() {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"]="1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"]="baseline";app.launchEnvironment["SOOM_ACTIVITY_UNREVIEWED_QA"]="1"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"]="1"
        app.launch();defer{app.terminate()}
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:5){tap(app.buttons["reviewDemo.start"],in:app)}
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.today"],in:app)
        let weekValue=app.staticTexts["activity.week.value"]
        XCTAssertTrue(weekValue.waitForExistence(timeout:10))
        if weekValue.label == "—" { tap(app.buttons["activity.week.previousWeek"],in:app) }
        XCTAssertNotEqual(weekValue.label,"—")
        XCTAssertEqual(app.staticTexts["activity.week.state"].label,"계산된 기록 부분합")
        capture(app,name:"SYNTHETIC unreviewed weekly partial before preserved daily detail")
        uxTap(app.buttons["activity.load.review"],in:app)
        uxTap(app.buttons["activity.load.dailyDetails"],in:app)
        let metric=app.staticTexts["activity.load.metric"],value=app.staticTexts["activity.load.value"]
        XCTAssertTrue(value.waitForExistence(timeout:10));XCTAssertNotEqual(value.label,"—")
        XCTAssertEqual(metric.label,"일별 기록 부하")
        XCTAssertTrue(app.staticTexts["activity.load.state"].label.contains("누락 미확인"))
        XCTAssertTrue(app.staticTexts["activity.load.inputSources"].label.contains("자동 추정 52개"))
        XCTAssertFalse(app.staticTexts["activity.load.inputNeeded"].exists)
        capture(app,name:"SYNTHETIC unreviewed automatic scores visible without approving rest or trend")
        uxTap(app.buttons["activity.load.day"],in:app)
        let score=app.staticTexts.matching(NSPredicate(format:"identifier BEGINSWITH %@","activity.load.sessionScore.")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout:5));XCTAssertTrue(score.label.contains("7.5 / 10"));XCTAssertTrue(score.label.contains("초기 추정"))
        uxReveal(app.buttons["activity.load.confirmDay"], in: app)
        XCTAssertTrue(app.buttons["activity.load.confirmDay"].exists,"The projection must not silently approve the date")
        capture(app,name:"SYNTHETIC individual automatic score source and AU remain distinct")
        tap(app.buttons["닫기"],in:app)
        app.swipeUp();capture(app,name:"SYNTHETIC grey daily known points before complete trend")
        let recent=app.staticTexts["activity.load.workoutScore.D2F85654-F4D9-5602-93AB-53DE487AB46C"]
        reveal(recent,in:app);XCTAssertTrue(recent.label.contains("초기 추정 7.5 / 10"))
        capture(app,name:"SYNTHETIC recent workout shows already calculated score")
    }

    func testMissingAutomaticBaselineUsesInitialProductEstimateWithoutForcedSetup() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"]="1";app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"]="baseline";app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"]="1"
        app.launch();defer{app.terminate()};if app.buttons["reviewDemo.start"].waitForExistence(timeout:5){tap(app.buttons["reviewDemo.start"],in:app)}
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.today"],in:app)
        let initial=app.staticTexts["activity.load.initialEstimate"]
        XCTAssertTrue(initial.waitForExistence(timeout:10));XCTAssertTrue(initial.isHittable)
        XCTAssertNotEqual(app.staticTexts["activity.load.value"].label,"—")
        XCTAssertFalse(app.staticTexts["activity.load.baselineNeeded"].exists)
        XCTAssertFalse(app.staticTexts["activity.load.inputNeeded"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","activity.load.enterIntensity.")).firstMatch.exists)
        capture(app,name:"SYNTHETIC HR first automatic product prior no forced baseline or FTP")
    }
    func testMissingHRUsesExplicitSameSportHistoryAndLabelsInitialEstimate() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"]="1";app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"]="history";app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"]="1"
        app.launch();defer{app.terminate()};if app.buttons["reviewDemo.start"].waitForExistence(timeout:5){tap(app.buttons["reviewDemo.start"],in:app)}
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.today"],in:app)
        XCTAssertTrue(app.staticTexts["activity.load.initialEstimate"].waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["activity.load.inputNeeded"].exists)
        XCTAssertTrue(app.staticTexts["activity.load.inputSources"].label.contains("사용자 수정 4개"))
        capture(app,name:"SYNTHETIC no HR same sport explicit history initial estimate one graph")
        // Select an actual workout date; the default summary is a later rest day.
        app.swipeUp()
        let title=app.staticTexts["잠정 참고 부하 차트"];XCTAssertTrue(title.waitForExistence(timeout:5))
        let window=app.staticTexts["activity.load.window"].label
        let format=DateFormatter();format.locale=Locale(identifier:"en_US_POSIX");format.timeZone=TimeZone(identifier:"Asia/Seoul");format.dateFormat="yyyy.MM.dd"
        let start=format.date(from:"2026."+String(window.prefix(5)))!,target=format.date(from:"2026.10.24")!
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=format.timeZone!
        let index=calendar.dateComponents([.day],from:start,to:target).day!;XCTAssertTrue((0...10).contains(index))
        let point=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:16+CGFloat(index)/10*(app.frame.width-60),dy:title.frame.minY+120))
        point.press(forDuration:0.25,thenDragTo:point.withOffset(CGVector(dx:2,dy:0)))
        app.swipeDown()
        tap(app.buttons["activity.load.day"],in:app)
        XCTAssertTrue(app.staticTexts.matching(identifier:"초기 추정 · 낮은 신뢰").firstMatch.waitForExistence(timeout:5))
        let evidence=app.staticTexts.matching(NSPredicate(format:"identifier BEGINSWITH %@", "activity.load.sessionEvidence.")).firstMatch
        XCTAssertTrue(evidence.exists);XCTAssertTrue(evidence.label.contains("앞선 같은 종목 직접 입력"));XCTAssertTrue(evidence.label.contains("현재 운동 측정 아님"))
        capture(app,name:"SYNTHETIC history fallback low confidence provenance in selected day")
    }
    func testStoredHeartRateEvidenceAutomaticallyEntersOneGraphWithoutManualInput() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"]="1";app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"]="stored";app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"]="1"
        app.launch();defer{app.terminate()};if app.buttons["reviewDemo.start"].waitForExistence(timeout:5){tap(app.buttons["reviewDemo.start"],in:app)}
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.today"],in:app)
        let value=app.staticTexts["activity.load.value"];XCTAssertTrue(value.waitForExistence(timeout:10));XCTAssertNotEqual(value.label,"—")
        XCTAssertFalse(app.staticTexts["activity.load.inputNeeded"].exists)
        XCTAssertTrue(app.staticTexts["activity.load.inputSources"].label.contains("자동 추정 52개"))
        capture(app,name:"SYNTHETIC stored heart rate projects automatically into one graph")
    }
    func testActivityR03AccessibleChartAndMaximumTextNavigation() {
        let app=XCUIApplication()
        app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"]="1";app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"]="1"
        app.launch();defer{app.terminate()}
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:5){tap(app.buttons["reviewDemo.start"],in:app)}
        for name in ["feed","activity","record","clubs","profile"] {
            let tab=app.buttons["soom.tab."+name]
            XCTAssertTrue(tab.waitForExistence(timeout:5));XCTAssertTrue(tab.isHittable)
            XCTAssertGreaterThanOrEqual(tab.frame.height,44);XCTAssertLessThanOrEqual(tab.frame.height,110)
            XCTAssertFalse(tab.label.isEmpty);XCTAssertGreaterThanOrEqual(tab.frame.minX,0);XCTAssertLessThanOrEqual(tab.frame.maxX,app.frame.width)
        }
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.today"],in:app)
        XCTAssertTrue(app.staticTexts["activity.load.value"].waitForExistence(timeout:10))
        capture(app,name:"R03 maximum text compact native labelled tab targets")
        let chartDay=app.buttons["activity.load.chart.day.2026-10-27"]
        for _ in 0..<8 { if chartDay.exists {break};app.swipeUp() }
        XCTAssertTrue(chartDay.exists)
        XCTAssertTrue(chartDay.label.contains("2026-10-27"));XCTAssertTrue((chartDay.value as? String ?? "").contains("AU"))
        capture(app,name:"R03 accessible chart date value source and state")
        tap(app.buttons["soom.tab.profile"],in:app);tap(app.buttons["soom.tab.activity"],in:app)
        XCTAssertTrue(app.buttons["activity.section.today"].exists)
    }
    @MainActor private final class EffortGestureCaptureTimer: NSObject {
        weak var owner: XCTestCase?
        let name: String
        let enabled: Bool
        private var count = 0
        init(owner: XCTestCase, name: String, enabled: Bool) { self.owner = owner; self.name = name; self.enabled = enabled }
        @objc func capture(_ timer: Timer) {
            guard enabled, count < 4 else { timer.invalidate(); return }
            count += 1
            let frame = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            frame.name = "SYNTHETIC gesture action sample " + name + " " + String(count)
            frame.lifetime = .keepAlways; owner?.add(frame)
        }
    }
    private func revealEffortElement(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 5)
        let scroll = app.scrollViews["effort.scroll"]
        XCTAssertTrue(scroll.exists)
        for _ in 0..<16 {
            let viewport = scroll.frame.intersection(app.frame)
            if element.exists && element.isHittable && element.frame.minY >= viewport.minY - 1 && element.frame.maxY <= viewport.maxY + 1 { return }
            let upwards = !element.exists || element.frame.midY > viewport.midY
            // Use the real viewport; a fixed screen fraction can hit the fixed footer at large type.
            let x = viewport.minX + 6
            let start = CGPoint(x: x, y: viewport.minY + viewport.height * (upwards ? 0.8 : 0.2))
            let end = CGPoint(x: x, y: viewport.minY + viewport.height * (upwards ? 0.2 : 0.8))
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: start.x, dy: start.y)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: end.x, dy: end.y)))
        }
        capture(app, name: "SYNTHETIC effort viewport target unavailable")
        XCTAssertTrue(element.exists && element.isHittable, "Expected an interactive element in the real effort scroll viewport")
        if element.exists {
            let viewport = scroll.frame.intersection(app.frame)
            XCTAssertGreaterThanOrEqual(element.frame.minY, viewport.minY - 1)
            XCTAssertLessThanOrEqual(element.frame.maxY, viewport.maxY + 1)
        }
    }
    private func effortGestureMetrics(_ slider: XCUIElement) throws -> [String: Double] {
        let text = try XCTUnwrap(slider.value as? String)
        let expression = try NSRegularExpression(pattern: "(hatch|drag|pans|restored|maxY|maxScroll|cancelled)=(-?[0-9.]+)")
        let source = text as NSString
        return Dictionary(uniqueKeysWithValues: expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            (source.substring(with: $0.range(at: 1)), Double(source.substring(with: $0.range(at: 2)))!)
        })
    }
    private func assertEffortGestureOwnsParent(in app: XCUIApplication, hasRange: Bool, name: String) throws {
        print("SOOM_GESTALT_UI_CURRENT_V3 persistent-expanded-reference")
        let slider = app.descendants(matching: .any)["effort.slider"].firstMatch
        revealEffortElement(slider, in: app)
        XCTAssertTrue((slider.value as? String ?? "").contains("빗금 숨김"))
        let expansion = app.buttons["effort.expansion"]
        revealEffortElement(expansion, in: app); expansion.tap()
        revealEffortElement(slider, in: app)
        XCTAssertTrue((slider.value as? String ?? "").contains("펼침"))
        XCTAssertTrue((slider.value as? String ?? "").contains(hasRange ? "빗금 표시" : "빗금 숨김"), "Expanded real reference remains visible without a drag")
        XCTAssertEqual(try effortGestureMetrics(slider)["hatch"], hasRange ? 1 : 0)
        capture(app, name: "SYNTHETIC " + name + " expanded ticks before drag persistent reference")
        let before = app.staticTexts["effort.value"].label
        let origin = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.48))
        let sampler = EffortGestureCaptureTimer(owner: self, name: name, enabled: hasRange)
        let captureTimer = Timer(timeInterval: 0.55, target: sampler,
            selector: #selector(EffortGestureCaptureTimer.capture(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(captureTimer, forMode: .common)
        defer { captureTimer.invalidate() }
        print("SOOM_GESTURE_CAPTURE_BEGIN|" + name + "|" + String(Date().timeIntervalSince1970))
        origin.press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.58)), withVelocity: .slow, thenHoldForDuration: 1.2)
        print("SOOM_GESTURE_CAPTURE_END|" + name + "|" + String(Date().timeIntervalSince1970))
        captureTimer.invalidate()
        XCTAssertNotEqual(app.staticTexts["effort.value"].label, before)
        let metrics = try effortGestureMetrics(slider)
        print("SOOM_GESTURE_METRICS|" + name + "|" + String(describing: metrics))
        XCTAssertEqual(metrics["drag"], 1)
        XCTAssertGreaterThan(try XCTUnwrap(metrics["pans"]), 0)
        XCTAssertEqual(metrics["pans"], metrics["restored"])
        XCTAssertLessThanOrEqual(try XCTUnwrap(metrics["maxY"]), 1.0, "Modal/score global position must stay fixed while adjusting")
        XCTAssertLessThanOrEqual(try XCTUnwrap(metrics["maxScroll"]), 1.0, "Ancestor scroll cannot consume the same drag")
        if hasRange { XCTAssertGreaterThanOrEqual(try XCTUnwrap(metrics["hatch"]), 1, "The real rendered hatch branch must appear during the coordinate drag") }
        else { XCTAssertEqual(metrics["hatch"], 0, "No personal range must be invented") }
        XCTAssertTrue((slider.value as? String ?? "").contains(hasRange ? "빗금 표시" : "빗금 숨김"))
        capture(app, name: "SYNTHETIC " + name + " released reference retained parents restored " + (slider.value as? String ?? ""))
        // A vertical swipe outside the score surface must scroll again after release.
        let scroll = app.scrollViews["effort.scroll"]
        let scrollBefore = scroll.value as? String ?? ""
        let scoreBeforeOutsideScroll = app.staticTexts["effort.value"].label
        let viewport = scroll.frame.intersection(app.frame)
        let geometry = scrollBefore.split(separator: " ").reduce(into: [String: Double]()) { result, field in
            let pair = field.split(separator: "=")
            if pair.count == 2, let value = Double(pair[1]) { result[String(pair[0])] = value }
        }
        let room = max(0, (geometry["content"] ?? 0) - (geometry["viewport"] ?? 0))
        let upwards = (geometry["offset"] ?? 0) <= room / 2
        let start = CGPoint(x: viewport.minX + 6, y: viewport.minY + viewport.height * (upwards ? 0.8 : 0.2))
        let end = CGPoint(x: start.x, y: viewport.minY + viewport.height * (upwards ? 0.2 : 0.8))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: start.x, dy: start.y)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: end.x, dy: end.y)))
        if room > 2 {
            XCTAssertNotEqual(scroll.value as? String ?? "", scrollBefore, "Scrollable content must recover after adjustment")
        } else {
            XCTAssertLessThanOrEqual(geometry["content"] ?? .infinity, (geometry["viewport"] ?? 0) + 2,
                                     "Compact content may fit without an artificial scroll")
            XCTAssertEqual(app.staticTexts["effort.value"].label, scoreBeforeOutsideScroll)
        }
        capture(app, name: "SYNTHETIC " + name + " outside scroll restored")
    }
    func testEffortDiagonalCoordinateDragShowsRealHatchAndKeepsSheetStill() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = detailFixtureApp(gesture: true); defer { app.terminate() }
        selectEffortFixture("평소 범위", in: app); openEffort(in: app)
        try assertEffortGestureOwnsParent(in: app, hasRange: true, name: "detail range normal")
        tap(app.buttons["effort.cancel"], in: app); openEffort(in: app)
        XCTAssertTrue((app.descendants(matching: .any)["effort.slider"].firstMatch.value as? String ?? "").contains("빗금 숨김"))
        tap(app.buttons["effort.cancel"], in: app)
        selectEffortFixture("없음", in: app); openEffort(in: app)
        XCTAssertTrue(app.staticTexts["effort.range.empty"].exists)
        XCTAssertTrue(app.staticTexts["effort.range.empty"].label.contains("비교 자료가 부족"))
        try assertEffortGestureOwnsParent(in: app, hasRange: false, name: "detail range unavailable")
        tap(app.buttons["effort.cancel"], in: app)
    }
    func testEffortScoreDragWorksAgainAfterBackgroundAndForeground() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = detailFixtureApp(gesture: true); defer { app.terminate() }
        selectEffortFixture("평소 범위", in: app); openEffort(in: app)
        try assertEffortGestureOwnsParent(in: app, hasRange: true, name: "detail foreground recovery")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["effort.cancel"].waitForExistence(timeout: 10))
        let slider = app.descendants(matching: .any)["effort.slider"].firstMatch
        revealEffortElement(slider, in: app)
        if (slider.value as? String ?? "").contains("접힘") {
            let expansion = app.buttons["effort.expansion"]; revealEffortElement(expansion, in: app); expansion.tap()
            revealEffortElement(slider, in: app)
        }
        let before = app.staticTexts["effort.value"].label
        let oldHatch = try XCTUnwrap(effortGestureMetrics(slider)["hatch"])
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.48)).press(forDuration: 0.1,
            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.58)), withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertNotEqual(app.staticTexts["effort.value"].label, before, "A recognizer disabled during inactivity must accept a new adjustment")
        let metrics = try effortGestureMetrics(slider)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(metrics["hatch"]), oldHatch)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(metrics["hatch"]),1)
        XCTAssertEqual(metrics["drag"], 1); XCTAssertEqual(metrics["pans"], metrics["restored"])
        XCTAssertLessThanOrEqual(try XCTUnwrap(metrics["maxY"]), 1); XCTAssertLessThanOrEqual(try XCTUnwrap(metrics["maxScroll"]), 1)
        XCTAssertTrue((slider.value as? String ?? "").contains("빗금 표시"))
        print("SOOM_GESTURE_METRICS|foreground returned|" + String(describing: metrics))
        capture(app, name: "SYNTHETIC foreground returned score changed parents restored")
        tap(app.buttons["effort.cancel"], in: app)
    }
    func testEffortDiagonalCoordinateDragAtMaximumTextRestoresParentGestures() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = detailFixtureApp(gesture: true); defer { app.terminate() }
        selectEffortFixture("평소 범위", in: app)
        tap(app.switches["큰 글자"], in: app); openEffort(in: app)
        try assertEffortGestureOwnsParent(in: app, hasRange: true, name: "detail range maximum text")
        XCTAssertEqual(app.staticTexts["effort.range.status"].label, "평소 범위 이상", "Short visible status must retain its full accessibility name")
        tap(app.buttons["effort.cancel"], in: app)
    }
    func testActivityDirectEntrySharesExclusiveGestureAndDoesNotInventHatching() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"] = "1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"] = "missing"; app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
        app.launchEnvironment["SOOM_EFFORT_GESTURE_QA"] = "1"
        app.launch(); defer { app.terminate() }
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 5) { tap(app.buttons["reviewDemo.start"], in: app) }
        tap(app.buttons["soom.tab.activity"], in: app); tap(app.buttons["activity.section.today"], in: app)
        openSimpleEffort(in: app)
        let hasRange = app.staticTexts["effort.range.summary"].exists
        try assertEffortGestureOwnsParent(in: app, hasRange: hasRange, name: "activity direct entry")
        tap(app.buttons["effort.cancel"], in: app)
    }
    func testEffortThinRestExpansionAndPersistentEligibleReference() {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=detailFixtureApp();defer{app.terminate()}
        selectEffortFixture("평소 범위",in:app);openEffort(in:app)
        let slider=app.descendants(matching:.any)["effort.slider"].firstMatch
        XCTAssertTrue((slider.value as? String ?? "").contains("접힘"))
        XCTAssertTrue((slider.value as? String ?? "").contains("빗금 숨김"))
        let compact=slider.frame.height;capture(app,name:"Effort thin initial ticks no hatching")
        tap(app.buttons["effort.expansion"],in:app)
        XCTAssertTrue((slider.value as? String ?? "").contains("펼침"));XCTAssertGreaterThan(slider.frame.height,compact+40)
        XCTAssertTrue((slider.value as? String ?? "").contains("빗금 표시"));capture(app,name:"SYNTHETIC expanded eligible reference before drag")
        slider.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.5)).press(forDuration:0.1,thenDragTo:slider.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)),withVelocity:.slow,thenHoldForDuration:1)
        XCTAssertTrue((slider.value as? String ?? "").contains("펼침"));XCTAssertTrue((slider.value as? String ?? "").contains("빗금 표시"))
        capture(app,name:"SYNTHETIC release retains expanded eligible reference")
        let value=app.staticTexts["effort.value"].label
        let start=slider.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.1,thenDragTo:start.withOffset(CGVector(dx:0,dy:-65)))
        XCTAssertEqual(app.staticTexts["effort.value"].label,value,"Vertical scroll must not change intensity")
        tap(app.buttons["effort.expansion"],in:app)
        XCTAssertTrue((slider.value as? String ?? "").contains("접힘"));XCTAssertEqual(slider.frame.height,compact,accuracy:2)
        tap(app.buttons["effort.cancel"],in:app);openEffort(in:app)
        XCTAssertTrue((slider.value as? String ?? "").contains("접힘"));XCTAssertTrue((slider.value as? String ?? "").contains("빗금 숨김"))
        tap(app.buttons["effort.cancel"],in:app)
    }
    func testMapProfileDragSpacingAndButtonCollapseRestoresTop() {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"]="1"
        app.launch();defer{app.terminate()}
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:5){tap(app.buttons["reviewDemo.start"],in:app)}
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.workouts"],in:app)
        let card=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@ AND label CONTAINS %@","DEMO ·","강변 라이딩")).firstMatch
        reveal(card,in:app);tap(card,in:app)
        let profile=app.buttons["workout.card.authorProfile"]
        XCTAssertTrue(profile.waitForExistence(timeout:10));XCTAssertTrue(profile.isHittable)
        capture(app,name:"Map profile drag starts in initial sheet")
        let start=profile.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.1,thenDragTo:start.withOffset(CGVector(dx:0,dy:-220)),withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertTrue(app.buttons["workout.detail.collapse"].waitForExistence(timeout:5))
        XCTAssertFalse(app.navigationBars["프로필"].exists,"Sheet drag must cancel profile navigation")
        XCTAssertGreaterThanOrEqual(profile.frame.minY-app.buttons["workout.detail.collapse"].frame.maxY,16)
        capture(app,name:"Map expanded title to profile spacing after author drag")
        app.swipeUp();app.swipeUp()
        tap(app.buttons["workout.detail.collapse"],in:app)
        let state=app.staticTexts["detail.sheet.geometry"]
        XCTAssertTrue(NSPredicate(format:"label CONTAINS %@","sheet=standard").evaluate(with:state))
        XCTAssertTrue(profile.isHittable);XCTAssertTrue(state.label.contains("saved=0"))
        capture(app,name:"Map collapse button resets body to profile top")
        let fast=profile.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        fast.press(forDuration:0.05,thenDragTo:fast.withOffset(CGVector(dx:0,dy:-220)),withVelocity:.fast,thenHoldForDuration:0)
        XCTAssertTrue(app.buttons["workout.detail.collapse"].waitForExistence(timeout:5))
        let down=profile.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        down.press(forDuration:0.1,thenDragTo:down.withOffset(CGVector(dx:0,dy:220)),withVelocity:.slow,thenHoldForDuration:0)
        XCTAssertTrue(app.buttons["상세 정보 시트"].waitForExistence(timeout:5),"Expanded top-of-scroll drag remains available")
        XCTAssertTrue(profile.waitForExistence(timeout:5));tap(profile,in:app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:8),"An ordinary author tap still opens the profile")
    }

    func testActivityUnifiedOverrideKeepsOneGraphAndPersonalRange() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"] = "1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"] = "mixed"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
        app.launch(); defer { app.terminate() }
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 5) { tap(app.buttons["reviewDemo.start"], in: app) }
        tap(app.buttons["soom.tab.activity"], in: app);tap(app.buttons["activity.section.today"], in: app)
        XCTAssertTrue(app.staticTexts["activity.load.value"].waitForExistence(timeout: 12))
        XCTAssertNotEqual(app.staticTexts["activity.load.value"].label,"—")
        XCTAssertFalse(app.staticTexts["activity.load.state"].label.contains("보류"))
        XCTAssertTrue(app.staticTexts["activity.load.state"].label.contains("범위"))
        capture(app,name:"Unified automatic estimate and user override one grey graph with range")
        tap(app.buttons["activity.load.day"],in:app)
        XCTAssertTrue(app.navigationBars["날짜별 기록"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","내 과거 부하 범위")).firstMatch.exists)
        capture(app,name:"Unified same-unit raw value provenance and personal range")
        tap(app.buttons["닫기"],in:app)
        tap(app.buttons["이전 7일"],in:app)
        XCTAssertFalse(app.staticTexts["activity.load.state"].label.contains("보류"),"A manual override must not reset history")
    }


    private func weeklyReferenceApp(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"] = "1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"] = "missing"
        app.launchEnvironment["SOOM_WEEKLY_PARTIAL_QA"] = "1"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
        app.launchEnvironment["SOOM_SIMPLE_EFFORT_QA"] = "1"
        app.launchEnvironment["SOOM_SIMPLE_EFFORT_QA_SESSION"] = UUID().uuidString
        app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 8) { uxTap(app.buttons["reviewDemo.start"], in: app) }
        uxTap(app.buttons["soom.tab.activity"], in: app); uxTap(app.buttons["activity.section.today"], in: app)
        return app
    }
    private func assertWeeklyReference(large: Bool) {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = weeklyReferenceApp(large: large); defer { app.terminate() }
        let value = app.staticTexts["activity.week.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 10)); XCTAssertEqual(value.label, "105.4")
        XCTAssertEqual(app.staticTexts["activity.week.state"].label, "계산된 기록 부분합")
        XCTAssertTrue(app.staticTexts["activity.week.counts"].label.contains("계산된 운동 1개"))
        XCTAssertTrue(app.staticTexts["activity.week.counts"].label.contains("확인이 필요한 운동 1개"))
        XCTAssertTrue(app.staticTexts["activity.week.previous"].label.contains("124 AU"))
        XCTAssertFalse(app.buttons["activity.week.nextWeek"].isEnabled)
        XCTAssertGreaterThan(value.frame.width, 60); XCTAssertLessThanOrEqual(value.frame.maxX, app.frame.maxX)
        capture(app, name: "SYNTHETIC weekly 124bpm 1020seconds partial105point4 " + (large ? "maximum text" : "standard"))
        uxReveal(app.buttons["activity.week.previousWeek"], in: app); uxTap(app.buttons["activity.week.previousWeek"], in: app)
        XCTAssertEqual(value.label, "124")
        uxTap(app.buttons["activity.week.nextWeek"], in: app); XCTAssertEqual(value.label, "105.4")
        uxReveal(app.buttons["activity.week.detail"], in: app); uxTap(app.buttons["activity.week.detail"], in: app)
        XCTAssertTrue(app.navigationBars["주간 운동 상세"].waitForExistence(timeout: 5))
        let known = app.buttons["activity.week.workout.D4110000-0000-4000-8000-000000000001"]
        let missing = app.buttons["activity.week.workout.D4120000-0000-4000-8000-000000000002"]
        uxReveal(missing, in: app); XCTAssertTrue(missing.isHittable); XCTAssertGreaterThanOrEqual(missing.frame.height, 44)
        XCTAssertTrue(missing.label.contains("확인 필요"))
        uxReveal(known, in: app); XCTAssertTrue(known.label.contains("105.4 AU")); XCTAssertTrue(known.label.contains("6.2 / 10"))
        capture(app, name: "SYNTHETIC weekly independent workout AU and missing record " + (large ? "maximum text" : "standard"))
        uxTap(known, in: app)
        XCTAssertTrue(app.navigationBars["운동 상세"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["기록이 삭제되었어요"].exists)
        uxReveal(app.buttons["effort.open"], in: app)
        openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "6.2 / 10")
        XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        capture(app, name: "SYNTHETIC weekly workout opens original persisted detail initial6point2")
        tap(app.buttons["effort.cancel"], in: app)
        app.navigationBars["운동 상세"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["activity.week.value"].waitForExistence(timeout: 8))
        if large {
            uxReveal(app.buttons["activity.week.detail"], in: app); uxTap(app.buttons["activity.week.detail"], in: app)
            uxReveal(missing, in: app); uxTap(missing, in: app)
            XCTAssertTrue(app.navigationBars["운동 상세"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.staticTexts["기록이 삭제되었어요"].exists)
            uxReveal(app.buttons["effort.open"], in: app); openEffort(in: app)
            XCTAssertEqual(app.staticTexts["effort.value"].label, "선택 전")
            XCTAssertFalse(app.buttons["effort.save"].isEnabled)
            capture(app, name: "SYNTHETIC last weekly missing-score workout reachable maximum text")
            tap(app.buttons["effort.cancel"], in: app)
            app.navigationBars["운동 상세"].buttons.element(boundBy: 0).tap()
        }
        uxReveal(app.buttons["activity.load.dailyDetails"], in: app); uxTap(app.buttons["activity.load.dailyDetails"], in: app)
        uxReveal(app.buttons["activity.load.day"], in: app); uxTap(app.buttons["activity.load.day"], in: app)
        XCTAssertTrue(app.navigationBars["날짜별 기록"].waitForExistence(timeout: 5))
        let subtotal = app.descendants(matching: .any)["activity.load.computedSubtotal"].firstMatch
        uxReveal(subtotal, in: app); XCTAssertTrue(subtotal.exists)
        uxReveal(app.buttons["activity.load.confirmDay"], in: app)
        XCTAssertTrue(app.buttons["activity.load.confirmDay"].exists)
        capture(app, name: "SYNTHETIC strict daily unknown with separate computed105point4 retained")
        uxTap(app.buttons["닫기"], in: app)
    }
    func testWeeklyPartialReferenceKeepsValidLoadAndStrictDailyReview() { assertWeeklyReference(large: false) }
    func testWeeklyPartialReferenceAtMaximumTextAndLastWorkoutTouch() { assertWeeklyReference(large: true) }

    func testWeeklyLargeTotalAtMaximumTextPreservesReadableDigits() {
        continueAfterFailure = false; executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"] = "1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"] = "baseline"
        app.launchEnvironment["SOOM_ACTIVITY_UNREVIEWED_QA"] = "1"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
        app.launch(); defer { app.terminate() }
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 8) { tap(app.buttons["reviewDemo.start"], in: app) }
        tap(app.buttons["soom.tab.activity"], in: app); tap(app.buttons["activity.section.today"], in: app)
        let value = app.staticTexts["activity.week.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        if value.label == "—" { uxTap(app.buttons["activity.week.previousWeek"], in: app) }
        XCTAssertEqual(value.label, "1,323.8")
        uxReveal(value, in: app)
        for _ in 0..<8 {
            let viewport = uxViewport(app)
            if viewport.contains(value.frame) { break }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewport.midX, dy: viewport.midY))
            start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 100)))
        }
        XCTAssertTrue(uxViewport(app).contains(value.frame), "Every large digit must be on screen before capture")
        XCTAssertGreaterThan(value.frame.width, 100)
        XCTAssertLessThanOrEqual(value.frame.maxX, app.frame.maxX - 12)
        XCTAssertGreaterThanOrEqual(value.frame.minX, 12)
        capture(app, name: "SYNTHETIC weekly1323point8 digits at maximum text")
        let chart = app.descendants(matching: .any)["activity.week.chart"].firstMatch
        uxReveal(chart, in: app)
        capture(app, name: "SYNTHETIC weekly chart seven weekdays readable at maximum text")
    }

    func testLegacyZeroStaysVisibleUntilExplicitIntegerChoiceAndClearRestoresAutomatic() {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = detailFixtureApp(legacyZero: true); defer { app.terminate() }
        openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.state"].label, "기존 입력")
        XCTAssertEqual(app.staticTexts["effort.value"].label, "기존 0점 · 보존")
        XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        XCTAssertTrue(app.staticTexts["effort.source.label"].label.contains("기존 입력 보존"))
        capture(app, name: "SYNTHETIC legacy explicit zero remains primary despite automatic7point5")
        tap(app.buttons["effort.cancel"], in: app); openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "기존 0점 · 보존")
        XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        chooseEffortStep(7, in: app); XCTAssertEqual(app.staticTexts["effort.value"].label, "7 / 10")
        tap(app.buttons["effort.save"], in: app); openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "7 / 10")
        tap(app.buttons["effort.clear"], in: app); openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "7.5 / 10")
        XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        chooseEffortStep(1, in: app); tap(app.buttons["effort.save"], in: app); openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "1 / 10")
        chooseEffortStep(10, in: app); XCTAssertEqual(app.staticTexts["effort.value"].label, "10 / 10")
        tap(app.buttons["effort.cancel"], in: app); openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "1 / 10")
        capture(app, name: "SYNTHETIC legacy zero explicit integer transition and cancelled ten preserves one")
        tap(app.buttons["effort.cancel"], in: app)
    }

    func testAutomaticDecimalSourceManualSaveNeutralClearAndRestore() {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = simpleEffortApp(automatic: true); defer { app.terminate() }
        openSimpleEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "7.5 / 10")
        XCTAssertTrue(app.staticTexts["effort.source.label"].label.contains("7.5 / 10"))
        XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        chooseEffortStep(7, in: app); uxTap(app.buttons["effort.save"], in: app)
        let workout = app.buttons["activity.load.workout.D2F85654-F4D9-5602-93AB-53DE487AB46C"]
        uxReveal(workout, in: app); uxTap(workout, in: app); openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "7 / 10")
        XCTAssertTrue(app.buttons["effort.clear"].isHittable); XCTAssertGreaterThanOrEqual(app.buttons["effort.clear"].frame.height, 44)
        capture(app, name: "SYNTHETIC saved manual seven neutral reset action and source")
        uxTap(app.buttons["effort.clear"], in: app); openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "7.5 / 10")
        XCTAssertTrue(app.staticTexts["effort.source.label"].label.contains("7.5 / 10"))
        XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        capture(app, name: "SYNTHETIC automatic7point5 preserved after explicit manual reset")
        uxTap(app.buttons["effort.cancel"], in: app)
    }

    private func assertIntegrationLogoCapsules(large: Bool) {
        continueAfterFailure = false; executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        defer { app.terminate() }
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 8) { uxTap(app.buttons["reviewDemo.start"], in: app) }
        uxTap(app.buttons["soom.tab.profile"], in: app); uxTap(app.buttons["profile.settings"], in: app)
        uxTap(app.buttons["settings.integrations"], in: app)
        capture(app, name: "SYNTHETIC integration logo capsules " + (large ? "maximum text" : "standard"))
        for (id, title, explanation) in [("googleHealth", "Google Health", "Google 계정을 연결"), ("appleHealth", "Apple 건강", "이 iPhone의 Apple 건강"), ("stravaArchive", "Strava ZIP", "계정 자동 연동은 제공하지"), ("samsungHealth", "Samsung Health", "Android 앱에서 제공할 예정")] {
            let capsule = app.buttons["integrations." + id]
            uxReveal(capsule, in: app); XCTAssertTrue(capsule.isHittable); XCTAssertGreaterThanOrEqual(capsule.frame.height, 44)
            XCTAssertTrue((capsule.value as? String ?? "").contains("지원 방식"))
            uxTap(capsule, in: app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", explanation)).firstMatch.exists)
            XCTAssertTrue(app.staticTexts["integrations.detail.status"].exists)
            capture(app, name: "SYNTHETIC integration support detail " + id + (large ? " maximum text" : ""))
            app.navigationBars[title].buttons.element(boundBy: 0).tap()
        }
        let file = app.buttons["integrations.workoutFile"]
        uxReveal(file, in: app); XCTAssertTrue(file.isHittable)
        capture(app, name: "SYNTHETIC integration back and scroll preserved without OAuth or permissions")
    }
    func testIntegrationLogoCapsulesKeepSupportRoutesAndBack() { assertIntegrationLogoCapsules(large: false) }
    func testIntegrationLogoCapsulesMaximumTextAndScroll() { assertIntegrationLogoCapsules(large: true) }
    private func simpleEffortApp(automatic:Bool=false, productPrior:Bool=false)->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"]="1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA_MODE"]="missing";app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"]="1"
        app.launchEnvironment["SOOM_SIMPLE_EFFORT_QA"]="1";app.launchEnvironment["SOOM_SIMPLE_EFFORT_QA_SESSION"]=UUID().uuidString
        if automatic || productPrior {app.launchEnvironment["SOOM_SCORE_EDITOR_QA"]="1"}
        if productPrior {app.launchEnvironment["SOOM_SCORE_EDITOR_QA_MODE"]="product"}
        app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:5){tap(app.buttons["reviewDemo.start"],in:app)}
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.today"],in:app)
        uxTap(app.buttons["activity.load.dailyDetails"], in: app)
        uxTap(app.buttons["activity.load.review"], in: app)
        return app
    }
    private func openSimpleEffort(in app:XCUIApplication) {
        let entry=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","activity.load.enterIntensity.")).firstMatch
        if !entry.exists {
            let review = app.buttons["activity.load.review"]
            uxTap(review, in: app)
        }
        uxTap(entry,in:app)
        XCTAssertTrue(app.buttons["effort.cancel"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["effort.title"].label,"운동강도")
        XCTAssertFalse(app.textFields["effort.duration"].exists);XCTAssertFalse(app.switches["effort.durationReviewed"].exists)
        XCTAssertFalse(app.buttons["effort.confirmScore"].exists);XCTAssertFalse(app.buttons["effort.zero"].exists)
    }
    func testActivityMissingEstimateOffersExplicitIntensityInputWithoutZero() {
        continueAfterFailure=false;executionTimeAllowance=150
        let app=simpleEffortApp();defer{app.terminate()}
        XCTAssertTrue(app.staticTexts["activity.load.value"].waitForExistence(timeout:12));XCTAssertEqual(app.staticTexts["activity.load.value"].label,"—")
        capture(app,name:"Missing estimate stays unknown with simple step entry")
        openSimpleEffort(in:app);XCTAssertEqual(app.staticTexts["effort.value"].label,"선택 전");XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        capture(app,name:"Simple workout detail control reused directly no extra inputs")
        tap(app.buttons["effort.cancel"],in:app);openSimpleEffort(in:app);XCTAssertEqual(app.staticTexts["effort.value"].label,"선택 전");XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        tap(app.buttons["effort.cancel"],in:app)
    }
    private func chooseEffortStep(_ step:Int,in app:XCUIApplication) {
        let slider=app.descendants(matching:.any)["effort.slider"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout:5))
        let width=slider.frame.width
        // Aim at the actual integer tick in the stable expanded touch track;
        // a raw 60% coordinate is step 6.5+, which correctly selects seven.
        let x=22+CGFloat(step-1)/9*max(1,width-44)
        dragEffort(to:x/width,in:app)
    }
    func testSimpleStepsSaveToGraphAndReuseTheSameWorkoutDetailEditor() {
        continueAfterFailure=false;executionTimeAllowance=240
        let app=simpleEffortApp();defer{app.terminate()};openSimpleEffort(in:app)
        chooseEffortStep(6,in:app);XCTAssertEqual(app.staticTexts["effort.value"].label,"6 / 10");XCTAssertTrue(app.buttons["effort.save"].isEnabled)
        capture(app,name:"Simple integer six chosen without time confirmation")
        tap(app.buttons["effort.save"],in:app);XCTAssertTrue(app.buttons["effort.cancel"].waitForNonExistence(timeout:8))
        // Virtual date rows are accessibility-only and their y coordinates
        // are not chart plot points. Scroll the real plot fully above the tabs.
        app.swipeUp()
        let chartTitle=app.staticTexts["잠정 참고 부하 차트"]
        uxReveal(chartTitle, in: app)
        XCTAssertTrue(chartTitle.waitForExistence(timeout:5))
        // Saving on a later calendar day advances the synthetic fixture's
        // asOf. Derive the target from the visible window rather than assuming
        // that the first x-axis day will always be October20.
        let window=app.staticTexts["activity.load.window"].label
        let first=String(window.prefix(5))
        let format=DateFormatter();format.locale=Locale(identifier:"en_US_POSIX");format.timeZone=TimeZone(identifier:"Asia/Seoul");format.dateFormat="yyyy.MM.dd"
        let windowStart=format.date(from:"2026."+first)!
        let workoutDay=format.date(from:"2026.10.24")!
        var cal=Calendar(identifier:.gregorian);cal.timeZone=format.timeZone!
        let dayIndex=cal.dateComponents([.day],from:windowStart,to:workoutDay).day!
        XCTAssertTrue((0...10).contains(dayIndex),"Workout date must be inside visible synthetic chart window: "+window)
        let point=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:16+CGFloat(dayIndex)/10*(app.frame.width-60),dy:chartTitle.frame.minY+120))
        point.press(forDuration:0.25,thenDragTo:point.withOffset(CGVector(dx:2,dy:0)))
        app.swipeDown()
        let total=app.staticTexts["activity.load.dailyTotal"]
        let updated=NSPredicate(format:"exists == true AND label CONTAINS %@","180")
        let result=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:updated,object:total)],timeout:8)
        capture(app,name:"Simple graph after save before total assertion")
        XCTAssertEqual(result,.completed,"Six times recorded thirty minutes, no extra time input; actual: " + (total.exists ? total.label : "missing"))
        capture(app,name:"Simple selected intensity immediately updates the one graph daily total")
        let workout=app.buttons["activity.load.workout.D2F85654-F4D9-5602-93AB-53DE487AB46C"]
        uxReveal(workout, in: app)
        for _ in 0..<12 {
            let viewport = uxViewport(app)
            if viewport.contains(workout.frame) { break }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewport.minX + 12, dy: viewport.midY))
            start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: workout.frame.maxY > viewport.maxY ? -100 : 100)))
        }
        XCTAssertTrue(uxViewport(app).contains(workout.frame), "The whole workout row must scroll above the floating tabs")
        XCTAssertLessThanOrEqual(workout.frame.maxY, app.buttons["soom.tab.activity"].frame.minY - 8)
        capture(app, name: "SYNTHETIC entire saved workout row visible above floating tabs before actual tap")
        uxTap(workout, in: app)
        uxReveal(app.buttons["effort.open"],in:app);XCTAssertTrue(app.buttons["effort.open"].label.contains("6 / 10"));openEffort(in:app)
        XCTAssertEqual(app.staticTexts["effort.title"].label,"운동강도");XCTAssertEqual(app.staticTexts["effort.value"].label,"6 / 10")
        XCTAssertFalse(app.textFields["effort.duration"].exists);XCTAssertFalse(app.switches["effort.durationReviewed"].exists)
        capture(app,name:"Identical simple editor reached from original workout detail")
        chooseEffortStep(4,in:app);XCTAssertEqual(app.staticTexts["effort.value"].label,"4 / 10");tap(app.buttons["effort.save"],in:app)
        XCTAssertTrue(app.buttons["effort.open"].label.contains("4 / 10"));openEffort(in:app);tap(app.buttons["effort.clear"],in:app)
        XCTAssertTrue(app.buttons["effort.open"].waitForExistence(timeout:8));XCTAssertTrue(app.buttons["effort.open"].label.contains("입력하기"))
    }
    func testInitialProductEditorLabelsLowConfidenceAndNeverImplicitlyStoresRoundedOverride() {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=simpleEffortApp(productPrior:true);defer{app.terminate()};openSimpleEffort(in:app)
        XCTAssertTrue(app.staticTexts["effort.initialEstimate"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["effort.value"].label,"7.5 / 10");XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        capture(app,name:"SYNTHETIC product prior existing shared 1 to 10 editor no extra questions")
        tap(app.buttons["effort.cancel"],in:app);openSimpleEffort(in:app)
        XCTAssertEqual(app.staticTexts["effort.value"].label,"7.5 / 10");XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        chooseEffortStep(6,in:app);XCTAssertEqual(app.staticTexts["effort.value"].label,"6 / 10")
        XCTAssertTrue(app.buttons["effort.save"].isEnabled)
        capture(app,name:"SYNTHETIC explicit manual integer six overrides initial product suggestion")
        tap(app.buttons["effort.cancel"],in:app)
    }
    func testSimpleOpeningAutomaticDecimalNeverSelectsOrSavesARoundedStep() {
        continueAfterFailure=false;executionTimeAllowance=150
        let app=simpleEffortApp(automatic:true);defer{app.terminate()};openSimpleEffort(in:app)
        XCTAssertEqual(app.staticTexts["effort.value"].label,"7.5 / 10");XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        let slider=app.descendants(matching:.any)["effort.slider"].firstMatch
        XCTAssertEqual(slider.label,"운동강도");XCTAssertTrue((slider.value as? String ?? "").contains("7.5"))
        capture(app,name:"Simple automatic proposal preserved internally no decimal input or implicit selection")
        tap(app.buttons["effort.cancel"],in:app);openSimpleEffort(in:app);XCTAssertEqual(app.staticTexts["effort.value"].label,"7.5 / 10");XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        chooseEffortStep(6,in:app);XCTAssertEqual(app.staticTexts["effort.value"].label,"6 / 10");XCTAssertTrue(app.buttons["effort.save"].isEnabled)
        tap(app.buttons["effort.cancel"],in:app)
    }

    func testActivityR03LargeTextCanReachRawValuesAndExplanation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages","(ko)","-AppleLocale","ko_KR","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"] = "1"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
        app.launch()
        defer { app.terminate() }
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        tap(app.buttons["soom.tab.activity"], in: app); tap(app.buttons["activity.section.today"], in: app)
        XCTAssertTrue(app.staticTexts["activity.load.value"].waitForExistence(timeout: 12))
        capture(app, name: "R03 accessible large text summary")
        tap(app.buttons["activity.load.day"], in: app)
        XCTAssertTrue(app.navigationBars["날짜별 기록"].waitForExistence(timeout: 8))
        capture(app, name: "R03 large text scrollable exact values")
        tap(app.buttons["닫기"], in: app)
    }

    func testActivityR03LoadsRealComputedFixtureAndSelectableDateWithoutFetch() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_ACTIVITY_LOAD_QA"] = "1"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
        app.launch()
        defer { app.terminate() }
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.today"], in: app)
        XCTAssertTrue(app.staticTexts["activity.load.value"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.staticTexts["activity.load.value"].label, "60")
        XCTAssertTrue(app.staticTexts["activity.load.state"].label.contains("범위보다 높음"))
        capture(app, name: "R03 computed main 60 AU grey design")
        tap(app.buttons["activity.load.day"], in: app)
        XCTAssertTrue(app.navigationBars["날짜별 기록"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "59.951")).firstMatch.exists)
        capture(app, name: "R03 raw values and daily completeness distinction")
        tap(app.buttons["닫기"], in: app)
        tap(app.buttons["이전 7일"], in: app)
        XCTAssertEqual(app.staticTexts["activity.load.value"].label, "55")
        capture(app, name: "R03 selected historical date within range")
        tap(app.buttons["다음 7일"], in: app)
        XCTAssertEqual(app.staticTexts["activity.load.value"].label, "60")
        let probe = app.descendants(matching: .any)["activity.load.dashboard"].firstMatch
        let before = probe.value as? String
        XCTAssertTrue(before?.contains("snapshot-load-count=") == true)
        app.swipeUp(); app.swipeDown()
        tap(app.buttons["activity.section.workouts"], in: app)
        tap(app.buttons["activity.section.today"], in: app)
        XCTAssertEqual(app.staticTexts["activity.load.value"].label, "60")
        XCTAssertEqual(probe.value as? String, before, "Scroll and sub-tab return must not re-read the snapshot")
    }

    func testCommentReferenceLayoutAndReplyComposer() {
        let app = uxLaunch(environment: ["SOOM_NOTIFICATION_CARD_QA": "1"])
        defer { app.terminate() }
        tap(app.buttons["알림"], in: app)
        tap(app.descendants(matching: .any)["notifications.row.D3700000-0000-4000-8000-000000000001"].firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["댓글"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.textFields["feed.comment.input"].exists || app.textViews["feed.comment.input"].exists)
        XCTAssertTrue(app.buttons["댓글 보내기"].exists)
        XCTAssertTrue(app.buttons["🔥 입력"].exists)
        capture(app, name: "SYNTHETIC Instagram reference comment sheet")
        let reply = app.buttons["답글 달기"].firstMatch
        if reply.waitForExistence(timeout: 3) {
            tap(reply, in: app)
            XCTAssertTrue(app.buttons["답글 취소"].exists)
            capture(app, name: "SYNTHETIC reply composer selected target")
            let input = app.textFields["feed.comment.input"].exists ? app.textFields["feed.comment.input"] : app.textViews["feed.comment.input"]
            input.typeText("함께 달려요")
            tap(app.buttons["댓글 보내기"], in: app)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "함께 달려요")).firstMatch.waitForExistence(timeout: 5))
            capture(app, name: "SYNTHETIC threaded reply saved locally")
            let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed.comment.delete.")).firstMatch
            XCTAssertTrue(delete.exists)
            XCTAssertGreaterThanOrEqual(delete.frame.width, 44)
            XCTAssertGreaterThanOrEqual(delete.frame.height, 44)
            tap(delete, in: app)
            XCTAssertTrue(app.staticTexts["이 댓글을 삭제할까요?"].waitForExistence(timeout: 3))
            capture(app, name: "SYNTHETIC small X delete requires confirmation")
            tap(app.buttons["취소"], in: app)
            XCTAssertTrue(delete.exists)
        }
    }

    func testNativeInboxReadHideUndoAndIndependentComments() {
        let app = uxLaunch(environment: ["SOOM_NATIVE_INBOX_QA":"1", "SOOM_NATIVE_COMMENT_QA":"1", "SOOM_PROJECTION_SUMMARY_QA":"1"])
        defer { app.terminate() }
        scrollToInboxHeader(app)
        tap(app.buttons["알림"], in: app)
        let row = app.buttons["notifications.native.row.A1100000-0000-0000-0000-000000000001"]
        uxReveal(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        capture(app, name: "SYNTHETIC native activity inbox no legacy post identifier")
        row.press(forDuration: 1)
        tap(app.buttons["읽음으로 표시"], in: app)
        row.press(forDuration: 1)
        tap(app.buttons["알림 숨기기"], in: app)
        let undo = app.buttons["notifications.native.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        capture(app, name: "SYNTHETIC native inbox hide with undo")
        tap(undo, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        tap(row, in: app)
        XCTAssertTrue(app.navigationBars["댓글"].waitForExistence(timeout: 8))
        capture(app, name: "SYNTHETIC native inbox opens independently authorized comments")
        tap(app.buttons["닫기"], in: app)
        XCTAssertTrue(app.navigationBars["운동 기록"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["거리"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["댓글 보기"].waitForExistence(timeout: 5))
        capture(app, name: "SYNTHETIC native notification comments dismissed keeps same workout card")
        tap(app.buttons["댓글 보기"], in: app)
        XCTAssertTrue(app.navigationBars["댓글"].waitForExistence(timeout: 5))
        let input = app.textFields["feed.comment.input"]
        tap(input, in: app); input.typeText("프로필 이동 뒤에도 운동 유지")
        tap(app.buttons["댓글 보내기"], in: app)
        XCTAssertTrue(app.staticTexts["프로필 이동 뒤에도 운동 유지"].waitForExistence(timeout: 8))
        tap(app.buttons.matching(identifier: "댓글 작성자 프로필").firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.navigationBars["댓글"].exists)
        capture(app, name: "SYNTHETIC comment dismissed before independent profile push")
        tap(app.navigationBars["프로필"].buttons.element(boundBy: 0), in: app)
        XCTAssertTrue(app.navigationBars["운동 기록"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["거리"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["댓글"].exists)


    }

    func testProjectionDeep238RowsPreserveCompletedVerification() { verifyDeepProjectionScroll(own: false, reconcile: false, delay: "0") }
    func testProjectionDeep238RowsWithOwnReconciliationPreserveCompletedVerification() { verifyDeepProjectionScroll(own: true, reconcile: true, delay: "0") }
    func testProjectionDeep238RowsWithSlowStagesMakeForwardProgress() { verifyDeepProjectionScroll(own: false, reconcile: false, delay: "600") }
    private func verifyDeepProjectionScroll(own: Bool, reconcile: Bool, delay: String) {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROJECTION_DEEP_QA":"1",
            "SOOM_PROJECTION_DEEP_OWN_QA":own ? "1":"0", "SOOM_PROJECTION_RECONCILE_QA":reconcile ? "1":"0", "SOOM_PROJECTION_DELAY_MS":delay])
        defer { app.terminate() }
        let first = app.otherElements["feed.card.A9540000-0000-4000-8000-000000001000"].firstMatch
        uxReveal(first, in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.staticTexts["총 시간"].firstMatch.waitForExistence(timeout: 15))
        let initial = first.value as? String
        capture(app, name: "SYNTHETIC 238 stable rows first verified")
        for _ in 0..<14 { app.swipeUp() }
        capture(app, name: "SYNTHETIC 238 rows deep past dates")
        for _ in 0..<14 { app.swipeDown() }
        uxReveal(first, in: app)
        XCTAssertTrue(first.staticTexts["총 시간"].firstMatch.waitForExistence(timeout: 15))
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "deep238-final-hierarchy"; tree.lifetime = .keepAlways; add(tree)
        capture(app, name: "SYNTHETIC 238 rows returned first")
        XCTAssertEqual(first.value as? String, initial, "Returning to a completed row in the same visit must not restart its verification")
    }

    func testOwnProjectionReusesActivityRoutePhotosAchievementsAndManagement() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROJECTION_OWN_PARITY_QA":"1"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        let title = app.staticTexts["DEMO · 공원 러닝"].firstMatch
        uxReveal(title, in: app)
        let badge = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "최근 3개월 중")).firstMatch
        uxReveal(badge, in: app)
        XCTAssertTrue(badge.waitForExistence(timeout: 12))
        let activityBadge = badge.label
        capture(app, name: "SYNTHETIC Activity own summary and badge")
        let indicator = app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "3페이지 중 1페이지")).firstMatch
        uxReveal(indicator, in: app)
        XCTAssertTrue(indicator.exists)
        capture(app, name: "SYNTHETIC Activity exact own route plus photo2 and achievement")
        tap(app.buttons["soom.tab.feed"], in: app)
        let feed = app.otherElements["feed.card.A9110000-0000-4000-8000-000000000777"].firstMatch
        uxReveal(feed, in: app)
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        capture(app, name: "SYNTHETIC Feed same own summary and header")
        let feedBadge = feed.staticTexts[activityBadge].firstMatch
        uxReveal(feedBadge, in: app)
        XCTAssertTrue(feedBadge.waitForExistence(timeout: 12))
        let feedIndicator = feed.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "3페이지 중 1페이지")).firstMatch
        uxReveal(feedIndicator, in: app)
        XCTAssertTrue(feedIndicator.exists)
        let pager = feed.descendants(matching: .any)["workout.media.pager"].firstMatch
        XCTAssertEqual(pager.frame.height, 260, accuracy: 1)
        capture(app, name: "SYNTHETIC Feed same own route plus photo2 and achievement")
        let menu = feed.buttons["기록 더보기"].firstMatch
        uxReveal(menu, in: app); tap(menu, in: app)
        tap(app.buttons["기록 수정"], in: app)
        XCTAssertTrue(app.navigationBars["기록 수정"].waitForExistence(timeout: 8))
        capture(app, name: "SYNTHETIC shared own card preserves record management")
        let titleField = app.textViews["workout.edit.title"]
        tap(titleField, in: app); titleField.typeText("53수정검증")
        tap(app.navigationBars["기록 수정"].buttons["저장"], in: app)
        let changed = feed.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "53수정검증")).firstMatch
        uxReveal(changed, in: app)
        XCTAssertTrue(changed.waitForExistence(timeout: 10), "Local mutation must refresh own presentation even when remote summary revision is unchanged")
        capture(app, name: "SYNTHETIC same-revision local edit refreshes own feed title")
    }

    func testProjectionPendingRowsDoNotOverlapAndScrollDoesNotReloadVerifiedRows() {
        verifyProjectionPendingRows(large: false)
    }
    func testProjectionPendingRowsAtAccessibilityTextDoNotOverlap() {
        verifyProjectionPendingRows(large: true)
    }
    private func verifyProjectionPendingRows(large: Bool) {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROJECTION_LOADING_QA":"1", "SOOM_PROJECTION_LARGE_QA": large ? "1" : "0"])
        defer { app.terminate() }
        let id = "A9110000-0000-4000-8000-000000000777"
        let ready = app.otherElements["feed.card." + id].firstMatch
        uxReveal(app.staticTexts["총 시간"].firstMatch, in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 8))
        XCTAssertEqual(ready.value as? String, "검증 요청 1")
        let pending = app.otherElements["feed.card.A9110000-0000-4000-8000-000000000778"].firstMatch
        app.swipeUp()
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        let skeleton = pending.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "공개 범위 확인 중")).firstMatch
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "pending-real-hierarchy"; tree.lifetime = .keepAlways; add(tree)
        capture(app, name: "SYNTHETIC pending rows before geometry assertions")
        XCTAssertTrue(skeleton.exists)
        XCTAssertGreaterThanOrEqual(skeleton.frame.minY, pending.frame.minY - 1)
        XCTAssertLessThanOrEqual(skeleton.frame.maxY, pending.frame.maxY + 1)
        XCTAssertLessThanOrEqual(ready.frame.maxY, pending.frame.minY + 1)
        XCTAssertEqual(pending.frame.minX, ready.frame.minX, accuracy: 1, "Loading uses the same full card width, not an extra screen inset")
        XCTAssertEqual(pending.frame.maxX, ready.frame.maxX, accuracy: 1, "Loading and ready card horizontal bounds agree")
        capture(app, name: "SYNTHETIC ready card and pending row bounded without overlap")
        for _ in 0..<3 { app.swipeUp(); app.swipeDown() }
        uxReveal(ready, in: app)
        XCTAssertEqual(ready.value as? String, "검증 요청 1", "Scroll is not a new authorization epoch")
        capture(app, name: "SYNTHETIC repeated scroll keeps same verification lease")
        XCUIDevice.shared.press(.home); app.activate()
        uxReveal(ready, in: app)
        let refreshed = NSPredicate(format: "value != %@", "검증 요청 1")
        expectation(for: refreshed, evaluatedWith: ready)
        waitForExpectations(timeout: 10)
        capture(app, name: "SYNTHETIC foreground requires new verification")
    }

    func testProjectionUsesTheExistingActivityWorkoutCardLayout() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_NATIVE_COMMENT_QA":"1"])
        defer { app.terminate() }
        let card = app.staticTexts["총 시간"].firstMatch
        uxReveal(card, in: app)
        XCTAssertTrue(card.exists)
        XCTAssertTrue(app.staticTexts["거리"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["총 시간"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["기록된 거리"].exists)
        capture(app, name: "SYNTHETIC projection reuses activity WorkoutRecordCard")
        let cheer = app.buttons["feed.projection.cheer"]
        uxReveal(cheer, in: app)
        XCTAssertTrue(cheer.exists)
        XCTAssertFalse(cheer.isEnabled, "Native-only records do not invent legacy reaction support")
        let comments = app.buttons["feed.projection.comments"]
        XCTAssertTrue(comments.exists)
        XCTAssertEqual(comments.value as? String ?? "", "", "An empty thread must not invent a badge")
        XCTAssertFalse(app.staticTexts["댓글 보기"].exists)
        XCTAssertFalse(app.staticTexts["운동 상세"].exists)
        capture(app, name: "SYNTHETIC restored icon-only social controls with verified recent-comment badge")
        uxReveal(app.buttons["댓글 보기"], in: app)
        tap(app.buttons["댓글 보기"], in: app)
        XCTAssertTrue(app.navigationBars["댓글"].waitForExistence(timeout: 8))
        let input = app.textFields["feed.comment.input"]
        tap(input, in: app); input.typeText("댓글 배지 확인")
        tap(app.buttons["댓글 보내기"], in: app)
        XCTAssertTrue(app.staticTexts["댓글 배지 확인"].waitForExistence(timeout: 8))
        tap(app.buttons["닫기"], in: app)
        expectation(for: NSPredicate(format: "value == %@", "최근 댓글 있음"), evaluatedWith: comments)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["댓글"].exists)
        capture(app, name: "SYNTHETIC shared card retained after comments dismissal")
    }

    func testProjectionSummaryOpensExistingReadonlyDetailTwiceAndAfterForeground() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_NATIVE_COMMENT_QA":"1"])
        defer { app.terminate() }
        for attempt in 0..<2 {
            uxReveal(app.buttons["러닝 기록"].firstMatch, in: app)
            tap(app.buttons["러닝 기록"].firstMatch, in: app)
            XCTAssertTrue(app.navigationBars["운동 상세"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["5.00 km"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["30분 0초"].firstMatch.exists)
            XCTAssertFalse(app.buttons["workout.card.open.photo"].exists)
            XCTAssertFalse(app.buttons["게시물 삭제"].exists)
            capture(app, name: "SYNTHETIC projection summary existing readonly detail \(attempt)")
            if attempt == 0 {
                XCUIDevice.shared.press(.home)
                app.activate()
                XCTAssertTrue(app.navigationBars["운동 상세"].waitForExistence(timeout: 8))
                XCTAssertTrue(app.staticTexts["5.00 km"].firstMatch.waitForExistence(timeout: 5))
            }
            tap(app.navigationBars["운동 상세"].buttons.element(boundBy: 0), in: app)
            XCTAssertTrue(app.buttons["댓글 보기"].waitForExistence(timeout: 5))
        }
    }

    // Actual card tap -> openLegacy -> production navigation helper -> summary destination.
    // Only authorization setup and the nil transport result are synthetic.
    func testDetail68FreshUnlinkedTapShowsSummaryWithoutLegacyError() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_NATIVE_COMMENT_QA":"1", "SOOM_PROJECTION_UNLINKED_DETAIL_QA":"1", "SOOM_PROFILE_SOCIAL_QA":"1"])
        defer { app.terminate() }
        uxReveal(app.buttons["러닝 기록"].firstMatch, in: app)
        tap(app.buttons["러닝 기록"].firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["운동 상세"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["5.00 km"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["30분 0초"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["운동 상세를 열지 못했어요. 잠시 후 다시 시도해 주세요."].exists)
        XCTAssertFalse(app.buttons["게시물 삭제"].exists)
        capture(app, name: "SYNTHETIC verified nil actual openLegacy tap preserves summary")
    }

    func testOwnRemoteLegacyWithoutSnapshotOrLocalSourceShowsExistingSummaryDetail() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_NATIVE_COMMENT_QA":"1", "SOOM_PROJECTION_LEGACY_NO_DETAIL_QA":"1"])
        defer { app.terminate() }
        uxReveal(app.buttons["러닝 기록"].firstMatch, in: app)
        tap(app.buttons["러닝 기록"].firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["운동 상세"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["5.00 km"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["30분 0초"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["운동 상세 공유를 기다리고 있어요"].exists)
        XCTAssertFalse(app.buttons["게시물 삭제"].exists)
        capture(app, name: "SYNTHETIC own remote legacy missing snapshot and local source retains summary detail")
        tap(app.navigationBars["운동 상세"].buttons.element(boundBy: 0), in: app)
        XCTAssertTrue(app.buttons["댓글 보기"].waitForExistence(timeout: 5))
    }

    func testNativeProjectionPhotoRendersLocalJPEGWithoutStorage() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_NATIVE_PHOTO_QA":"1"])
        defer { app.terminate() }
        let photo = app.buttons["workout.card.open.photo"].firstMatch
        uxReveal(photo, in: app)
        XCTAssertTrue(photo.exists)
        XCTAssertFalse(app.staticTexts["사진을 불러올 수 없어요"].exists)
        capture(app, name: "SYNTHETIC native JPEG pixels with no Storage request")
        tap(photo, in: app)
        XCTAssertTrue(app.buttons["workout.photo.close"].waitForExistence(timeout: 5))
        capture(app, name: "SYNTHETIC projection photo uses existing full screen gallery")
        tap(app.buttons["workout.photo.close"], in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        uxReveal(app.buttons["러닝 기록"].firstMatch, in: app)
        tap(app.buttons["러닝 기록"].firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["운동 상세"].waitForExistence(timeout: 8))
        uxReveal(photo, in: app)
        XCTAssertTrue(photo.exists)
        tap(photo, in: app)
        XCTAssertTrue(app.buttons["workout.photo.close"].waitForExistence(timeout: 5))
        capture(app, name: "SYNTHETIC same authorized native photo in existing detail gallery")
        tap(app.buttons["workout.photo.close"], in: app)
    }

    func testNextPageAndAuthorizedCardsDoNotWaitForOptionalSummary() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1",
            "SOOM_FEED_BATCH_QA":"1", "SOOM_FEED_BATCH_SMALL_PHOTOS":"1", "SOOM_FEED_LIFECYCLE_QA":"1",
            "SOOM_FEED_MIXED_REUSE_QA":"1", "SOOM_FEED_MIXED_REUSE_COUNT":"48",
            "SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA":"1", "SOOM_FEED_SLOW_SUMMARY_QA":"1"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let release = app.buttons["feed.summary.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 15), "Optional summary must really be suspended")
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        func count(_ key: String) -> Int {
            let raw = probe.label.components(separatedBy: ";").first { $0.hasPrefix(key + "=") }
            return Int(raw?.components(separatedBy: "=").last ?? "") ?? -1
        }
        let first = app.otherElements["feed.card.A9611000-0000-4000-8000-000000000001"].firstMatch
        XCTAssertTrue(first.staticTexts["총 시간"].firstMatch.waitForExistence(timeout: 15))
        capture(app, name: "Primary real card while optional summary is held")
        let next = app.otherElements["feed.card.A9611000-0000-4000-8000-000000000009"].firstMatch
        // Prefetch may append rows before they enter the viewport. Authorization
        // is intentionally viewport-limited; never wait for an offscreen grant.
        for _ in 0..<24 {
            if next.exists && next.frame.minY >= 120 && next.frame.maxY < app.frame.maxY - 90 { break }
            app.swipeUp(velocity: .slow)
        }
        let position = XCTAttachment(string: "target=" + String(describing: next.frame) + ";screen=" + String(describing: app.frame) + ";" + probe.label)
        position.name = "Actual next-page viewport and held summary"; position.lifetime = .keepAlways; add(position)
        XCTAssertTrue(next.exists && next.frame.intersects(app.frame), "The target must enter the viewport before expecting authorization")
        XCTAssertTrue(next.staticTexts["총 시간"].firstMatch.waitForExistence(timeout: 15), "Next-page text needs fresh authorization, not just loaded row metadata")
        XCTAssertGreaterThanOrEqual(count("pageRows"), 16)
        XCTAssertEqual(count("pageUnique"), count("pageRows"))
        XCTAssertEqual(count("summaryHeld"), 1, "Page and fresh grant must finish before the slow summary")
        XCTAssertLessThanOrEqual(count("batch"), 3, "Near-viewport new rows should be authorized in small groups, not one RPC each")
        capture(app, name: "Next page real card before releasing optional summary")
        tap(release, in: app)
        let done = NSPredicate { _, _ in count("summaryHeld") == 0 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: done, evaluatedWith: nil)], timeout: 15), .completed)
    }

    func testAppSwitcherReturnKeepsOwnLocalRecordWhileForeignAuthorizationWaits() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1",
            "SOOM_FEED_BATCH_QA":"1", "SOOM_FEED_BATCH_SMALL_PHOTOS":"1", "SOOM_FEED_LIFECYCLE_QA":"1",
            "SOOM_FEED_BATCH_HOLD_RETURN":"1", "SOOM_FEED_MIXED_REUSE_QA":"1",
            "SOOM_FEED_MIXED_REUSE_COUNT":"48", "SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA":"1"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let own = app.otherElements["feed.card.A9611000-0000-4000-8000-000000000001"].firstMatch
        XCTAssertTrue(own.staticTexts["총 시간"].firstMatch.waitForExistence(timeout: 15))
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        func count(_ key: String) -> Int {
            let raw = probe.label.components(separatedBy: ";").first { $0.hasPrefix(key + "=") }
            return Int(raw?.components(separatedBy: "=").last ?? "") ?? -1
        }
        let inactive = count("inactiveEvents"), background = count("backgroundEvents")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 1.0)
        let switcher = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        switcher.name = "Actual app-switcher gesture before returning"; switcher.lifetime = .keepAlways; add(switcher)
        app.activate()
        let release = app.buttons["feed.lifecycle.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 15), "Fresh authorization must still be required after system interruption")
        XCTAssertGreaterThan(count("inactiveEvents"), inactive, "The gesture must cause a real lifecycle interruption")
        XCTAssertTrue(probe.label.contains("pending"))
        let local = app.otherElements["feed.own.localPending.A9611000-0000-4000-8000-000000000001"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 10))
        XCTAssertTrue(local.staticTexts["총 시간"].firstMatch.exists, "Owner-local content must remain visible while remote permission is held")
        XCTAssertFalse(local.buttons["workout.card.open.photo"].firstMatch.exists, "Local fallback cannot inherit remote photo authority")
        let counters = XCTAttachment(string: "before inactive=\(inactive) background=\(background); after " + probe.label)
        counters.name = "App-switcher lifecycle and pending local display"; counters.lifetime = .keepAlways; add(counters)
        capture(app, name: "Own local card retained while protected remote content waits")
        tap(release, in: app)
        let ready = NSPredicate { _, _ in probe.label.contains("ready") && !local.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 15), .completed)
        XCTAssertTrue(own.staticTexts["총 시간"].firstMatch.exists)
    }

    func testInitialRefreshJoinDoesNotOrphanHeldAuthorization() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1",
            "SOOM_FEED_BATCH_QA":"1", "SOOM_FEED_BATCH_SMALL_PHOTOS":"1", "SOOM_FEED_LIFECYCLE_QA":"1",
            "SOOM_FEED_BATCH_HOLD_RETURN":"1", "SOOM_FEED_BATCH_HOLD_FIRST":"1"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let release = app.buttons["feed.lifecycle.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 15))
        tap(app.buttons["feed.lifecycle.joinInitial"], in: app)
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        XCTAssertTrue(probe.label.contains("pending"))
        tap(release, in: app)
        let photo = app.buttons["workout.card.open.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "The original response must publish without another refresh or pull gesture")
        let ready = NSPredicate { _, _ in probe.label.contains("ready") && probe.label.components(separatedBy: ";").contains("held=0") }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 15), .completed)
        XCTAssertTrue(probe.label.components(separatedBy: ";").contains("loads=1"))
        XCTAssertTrue(probe.label.components(separatedBy: ";").contains("batch=1"))
        capture(app, name: "SYNTHETIC initial authorization survives concurrent refresh join")
    }

    func testFeedFreshBatchTabReturnRetainsContentAndPixelCache() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1",
            "SOOM_FEED_BATCH_QA":"1", "SOOM_FEED_BATCH_SMALL_PHOTOS":"1", "SOOM_FEED_LIFECYCLE_QA":"1", "SOOM_FEED_BATCH_HOLD_RETURN":"1"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let photo = app.buttons["workout.card.open.photo"].firstMatch
        uxReveal(photo, in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        func count(_ key: String) -> Int {
            let raw = probe.label.components(separatedBy: ";").first { $0.hasPrefix(key + "=") }
            return Int(raw?.components(separatedBy: "=").last ?? "") ?? -1
        }
        let pixelsReady = NSPredicate { _, _ in count("batch") > 0 && count("pixels") == 4 && count("inflight") == 0 && count("avatarVisible") > 0 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: pixelsReady, evaluatedWith: nil)], timeout: 15), .completed)
        func recordProbe(_ name: String) {
            let attachment = XCTAttachment(string: probe.label)
            attachment.name = "SYNTHETIC cache measurements " + name; attachment.lifetime = .keepAlways; add(attachment)
        }
        recordProbe("initial")
        XCTAssertEqual(count("evictions"), 0)
        XCTAssertGreaterThan(count("cost"), 0, "Cache byte count must parse as a positive ASCII integer")
        XCTAssertLessThanOrEqual(count("cost"), 32 * 1024 * 1024)
        let avatarMiss = count("avatarMiss")
        XCTAssertGreaterThan(avatarMiss, 0)
        let loads = count("loads"), batches = count("batch"), pixels = count("pixels")
        XCTAssertGreaterThan(batches, 0, "This test must enter fresh batch authorization, not legacy fixture fallback")
        XCTAssertEqual(loads, 1, "Initial callbacks must join one page load")
        for index in 1...2 {
            tap(app.buttons["soom.tab.activity"], in: app)
            tap(app.buttons["soom.tab.feed"], in: app)
            let release = app.buttons["feed.lifecycle.release"]
            XCTAssertTrue(release.waitForExistence(timeout: 10))
            XCTAssertTrue(probe.label.contains("ready"))
            XCTAssertTrue(photo.exists, "Foreground tab return must retain the already-authorized card while refresh is held")
            XCTAssertGreaterThan(count("avatarVisible"), 0, "The existing avatar stays visible during in-place revalidation")
            tap(release, in: app)
            let committed = NSPredicate { _, _ in count("held") == 0 && probe.label.contains("ready") }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: committed, evaluatedWith: nil)], timeout: 15), .completed)
            XCTAssertTrue(photo.waitForExistence(timeout: 15))
            let avatarReady = NSPredicate { _, _ in count("avatarVisible") > 0 }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: avatarReady, evaluatedWith: nil)], timeout: 10), .completed)
            recordProbe("return \(index)")
            XCTAssertEqual(count("avatarMiss"), avatarMiss)
            XCTAssertGreaterThanOrEqual(count("avatarHit"), index)
            XCTAssertEqual(count("loads"), loads)
            XCTAssertEqual(count("batch"), batches + index)
        }
        let reused = NSPredicate { _, _ in count("hits") >= 2 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: reused, evaluatedWith: nil)], timeout: 10), .completed)
        recordProbe("before photo reuse assertion")
        XCTAssertEqual(count("pixels"), pixels, "Same object version reuses decoded pixels only after fresh authorization")
        tap(app.buttons["soom.tab.activity"], in: app)
        XCUIDevice.shared.press(.home); app.activate()
        tap(app.buttons["soom.tab.feed"], in: app)
        let release = app.buttons["feed.lifecycle.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        XCTAssertTrue(probe.label.contains("pending"))
        XCTAssertFalse(photo.exists)
        XCTAssertEqual(count("avatarVisible"), 0)
        tap(release, in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        XCTAssertEqual(count("batch"), batches + 3)
        XCTAssertEqual(count("loads"), loads)
        capture(app, name: "SYNTHETIC batch request counters after tab and hidden background returns")
    }

    func testStoredOldCacheDisappearsAfterDisplayGraceWhileServerIsHeld() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1",
            "SOOM_FEED_BATCH_QA":"1", "SOOM_FEED_BATCH_SMALL_PHOTOS":"1", "SOOM_FEED_LIFECYCLE_QA":"1",
            "SOOM_FEED_BATCH_HOLD_RETURN":"1",
            "SOOM_STALE_TEST_AGE_SECONDS":"7200"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let photo = app.buttons["workout.card.open.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        let stored = NSPredicate { _, _ in probe.label.contains("cacheLayouts=1;") && !probe.label.contains("staleBytes=0;") }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: stored, evaluatedWith: nil)], timeout: 15), .completed)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["feed.lifecycle.release"].waitForExistence(timeout: 10))
        let cached = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "feed.stale.summary.", "러닝 기록")).firstMatch
        XCTAssertTrue(cached.waitForExistence(timeout: 3))
        let expired = NSPredicate { _, _ in !cached.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: expired, evaluatedWith: nil)], timeout: 8), .completed)
        XCTAssertFalse(photo.exists)
        XCTAssertTrue(probe.label.contains("staleCount=1;"), "Display expiry does not turn a 5-second grace into a 5-second storage TTL")
        XCTAssertTrue(probe.label.contains("held=1;"))
        capture(app, name: "SYNTHETIC grace expires while old encrypted snapshot remains stored and server is held")
        tap(app.buttons["feed.lifecycle.release"], in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
    }

    func testStaleDiskPhotosSurviveColdAppRelaunchWithoutNewGrant() {
        assertColdCachedLayout(extra: [:])
    }
    func testStaleDiskPhotosKeepAccessibilityHeightAfterColdRelaunch() {
        assertColdCachedLayout(extra: ["SOOM_PROJECTION_LARGE_QA":"1"])
    }
    func testStaleDiskTextOnlyCardKeepsHeightAfterColdRelaunch() {
        assertColdCachedLayout(extra: ["SOOM_STALE_TEXT_ONLY_QA":"1"])
    }
    private func assertColdCachedLayout(extra: [String: String]) {
        let hasPhotos = extra["SOOM_STALE_TEXT_ONLY_QA"] != "1"
        var env = ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1",
            "SOOM_FEED_BATCH_QA":"1", "SOOM_FEED_BATCH_SMALL_PHOTOS":"1", "SOOM_FEED_LIFECYCLE_QA":"1",
            "SOOM_STALE_STORAGE_SECONDS":"86400", "SOOM_STALE_DISPLAY_SECONDS":"15",
            "SOOM_STALE_TEST_AGE_SECONDS":"7200"]
        env.merge(extra) { _, value in value }
        var app = uxLaunch(environment: env)
        tap(app.buttons["soom.tab.feed"], in: app)
        if hasPhotos { uxReveal(app.buttons["workout.card.open.photo"].firstMatch, in: app) }
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        let stored = NSPredicate { _, _ in
            let raw = probe.label.components(separatedBy: ";").first { $0.hasPrefix("staleBytes=") }?.components(separatedBy: "=").last ?? "0"
            return (!hasPhotos || (Int(raw) ?? 0) > 0) && probe.label.contains("disk=saved-") && probe.label.contains("cacheLayouts=1;")
        }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: stored, evaluatedWith: nil)], timeout: 15), .completed, probe.label)
        let savedEvidence = XCTAttachment(string: probe.label); savedEvidence.name = "cold cache first process saved state"; savedEvidence.lifetime = .keepAlways; add(savedEvidence)
        // Flush the optional background file write before terminating the process.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.terminate()
        env["SOOM_FEED_BATCH_HOLD_RETURN"] = "1"; env["SOOM_FEED_BATCH_HOLD_FIRST"] = "1"
        app = uxLaunch(environment: env)
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        XCTAssertTrue(app.buttons["feed.lifecycle.release"].waitForExistence(timeout: 15))
        let cached = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "feed.stale.summary.", "러닝 기록")).firstMatch
        XCTAssertTrue(cached.waitForExistence(timeout: 8))
        XCTAssertEqual(app.images["저장된 운동 사진"].firstMatch.exists, hasPhotos)
        XCTAssertFalse(app.buttons["workout.card.open.photo"].firstMatch.exists)
        let restoredProbe = app.staticTexts["feed.lifecycle.probe"]
        XCTAssertTrue(restoredProbe.label.contains("granted=0"))
        func height(_ key: String) -> Double {
            Double(restoredProbe.label.components(separatedBy: ";").first { $0.hasPrefix(key + "=") }?.components(separatedBy: "=").last ?? "") ?? -1
        }
        XCTAssertGreaterThan(height("liveHeight"), 44)
        XCTAssertEqual(height("cachedHeight"), height("liveHeight"), accuracy: 0.5,
            "Actual rendered cached outer height must match the persisted verified card geometry")
        capture(app, name: "SYNTHETIC two-hour-old sealed text and photos restore during 15-second grace before fresh grant")
        tap(app.buttons["feed.lifecycle.release"], in: app)
        if hasPhotos { XCTAssertTrue(app.buttons["workout.card.open.photo"].firstMatch.waitForExistence(timeout: 15)) }
        else { XCTAssertTrue(app.buttons["러닝 기록"].firstMatch.waitForExistence(timeout: 15)) }
        XCTAssertFalse(cached.exists)
    }

    func testStaleSummaryAndPhotoShownWhileFreshReturnHeldThenRevoked() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1",
            "SOOM_FEED_BATCH_QA":"1", "SOOM_FEED_BATCH_SMALL_PHOTOS":"1", "SOOM_FEED_LIFECYCLE_QA":"1",
            "SOOM_FEED_BATCH_HOLD_RETURN":"1", "SOOM_FEED_BATCH_DENY_AFTER_FIRST":"1", "SOOM_STALE_CACHE_SECONDS":"60"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let photo = app.buttons["workout.card.open.photo"].firstMatch
        uxReveal(photo, in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        func count(_ key: String) -> Int {
            Int(probe.label.components(separatedBy: ";").first { $0.hasPrefix(key + "=") }?.components(separatedBy: "=").last ?? "") ?? -1
        }
        let stored = NSPredicate { _, _ in count("staleCount") > 0 && count("staleBytes") > 0 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: stored, evaluatedWith: nil)], timeout: 15), .completed)
        XCUIDevice.shared.press(.home)
        app.activate()
        let release = app.buttons["feed.lifecycle.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        let cached = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "feed.stale.summary.", "러닝 기록")).firstMatch
        XCTAssertTrue(cached.waitForExistence(timeout: 8))
        XCTAssertTrue(app.images["저장된 운동 사진"].firstMatch.exists)
        XCTAssertFalse(photo.exists, "Display-only cached photo must not grant gallery entry")
        capture(app, name: "SYNTHETIC stale summary and pixels while server return is held")
        tap(release, in: app)
        let cleared = NSPredicate { _, _ in count("staleCount") == 0 && !cached.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: cleared, evaluatedWith: nil)], timeout: 10), .completed)
        XCTAssertFalse(photo.exists)
        capture(app, name: "SYNTHETIC server denial removes cached text and photos")
    }

    func testFeedFreshBatchDenialCannotRestoreCachedPhotos() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1",
            "SOOM_FEED_BATCH_QA":"1", "SOOM_FEED_BATCH_SMALL_PHOTOS":"1", "SOOM_FEED_LIFECYCLE_QA":"1", "SOOM_FEED_BATCH_HOLD_RETURN":"1",
            "SOOM_FEED_BATCH_DENY_AFTER_FIRST":"1"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let photo = app.buttons["workout.card.open.photo"].firstMatch
        uxReveal(photo, in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        func count(_ key: String) -> Int {
            Int(probe.label.components(separatedBy: ";").first { $0.hasPrefix(key + "=") }?.components(separatedBy: "=").last ?? "") ?? -1
        }
        let avatarReady = NSPredicate { _, _ in count("avatarVisible") > 0 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: avatarReady, evaluatedWith: nil)], timeout: 10), .completed)
        let batchValue = probe.label.components(separatedBy: ";").first { $0.hasPrefix("batch=") }?.components(separatedBy: "=").last
        XCTAssertGreaterThan(Int(batchValue ?? "") ?? -1, 0, "Denial must exercise batch RPC fixture, not legacy fallback")
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["soom.tab.feed"], in: app)
        let release = app.buttons["feed.lifecycle.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        XCTAssertTrue(probe.label.contains("ready"))
        XCTAssertTrue(photo.exists)
        XCTAssertGreaterThan(count("avatarVisible"), 0)
        tap(release, in: app)
        let denied = NSPredicate { _, _ in probe.label.contains("failed") }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: denied, evaluatedWith: nil)], timeout: 10), .completed)
        XCTAssertEqual(count("avatarVisible"), 0)
        let reappeared = expectation(for: NSPredicate { _, _ in photo.exists || count("avatarVisible") > 0 }, evaluatedWith: nil)
        reappeared.isInverted = true
        wait(for: [reappeared], timeout: 5)
        capture(app, name: "SYNTHETIC fresh batch denial never exposes cached photo")
    }

    func testFeedBatchOfflineFailureWaitsForOneManualRetry() {
        let app = uxLaunch(environment: ["SOOM_PROFILE_PHOTO_QA":"1", "SOOM_FEED_BATCH_QA":"1",
            "SOOM_FEED_BATCH_SMALL_PHOTOS":"1", "SOOM_FEED_LIFECYCLE_QA":"1", "SOOM_FEED_BATCH_FAIL_SECOND":"1"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let photo = app.buttons["workout.card.open.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        func count(_ key: String) -> Int {
            Int(probe.label.components(separatedBy: ";").first { $0.hasPrefix(key + "=") }?.components(separatedBy: "=").last ?? "") ?? -1
        }
        XCTAssertEqual(count("batch"), 1)
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["soom.tab.feed"], in: app)
        let failed = NSPredicate { _, _ in probe.label.contains("failed") }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: failed, evaluatedWith: nil)], timeout: 10), .completed)
        XCTAssertFalse(photo.exists)
        XCTAssertEqual(count("avatarVisible"), 0)
        XCTAssertEqual(count("batch"), 2)
        let automaticRetry = expectation(for: NSPredicate { _, _ in count("batch") != 2 }, evaluatedWith: nil)
        automaticRetry.isInverted = true
        wait(for: [automaticRetry], timeout: 2)
        let retry = app.buttons["feed.projection.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        tap(retry, in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        XCTAssertEqual(count("batch"), 3, "Exactly one user-requested fresh batch recovers the card")
        XCTAssertEqual(count("loads"), 1, "A retry must not reload the unchanged page")
        XCTAssertTrue(probe.label.contains("ready"))
        capture(app, name: "SYNTHETIC offline failure recovered by one explicit row retry")
    }

    func testFeedLargePhotoCacheEvictionRemainsBoundedAfterFreshReturn() {
        let app = uxLaunch(environment: ["SOOM_PROFILE_PHOTO_QA":"1", "SOOM_FEED_BATCH_QA":"1",
            "SOOM_FEED_LIFECYCLE_QA":"1", "SOOM_FEED_BATCH_HOLD_RETURN":"1"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let photo = app.buttons["workout.card.open.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let probe = app.staticTexts["feed.lifecycle.probe"].firstMatch
        func count(_ key: String) -> Int {
            Int(probe.label.components(separatedBy: ";").first { $0.hasPrefix(key + "=") }?.components(separatedBy: "=").last ?? "") ?? -1
        }
        let settled = NSPredicate { _, _ in count("pixels") >= 4 && count("inflight") == 0 && count("entries") == 4 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: settled, evaluatedWith: nil)], timeout: 15), .completed)
        let before = count("pixels"), loads = count("loads")
        XCTAssertEqual(count("entries"), 4, "Display-sized pixels for all four photos fit the unchanged 32 MiB budget")
        XCTAssertEqual(count("evictions"), 0)
        XCTAssertGreaterThan(count("cost"), 0, "Cache byte count must parse as a positive ASCII integer")
        XCTAssertLessThanOrEqual(count("cost"), 32 * 1024 * 1024)
        let initial = XCTAttachment(string: probe.label); initial.name = "SYNTHETIC display-sized large image initial"; initial.lifetime = .keepAlways; add(initial)
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["soom.tab.feed"], in: app)
        let release = app.buttons["feed.lifecycle.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        // Since build 68, a same-foreground tab return retains its current
        // authorization while revalidating. Background/detail suspension and
        // explicit denial are covered by the separate fail-closed tests.
        XCTAssertTrue(photo.exists)
        XCTAssertGreaterThan(count("avatarVisible"), 0)
        tap(release, in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let refilled = NSPredicate { _, _ in count("hits") >= 4 && count("inflight") == 0 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: refilled, evaluatedWith: nil)], timeout: 15), .completed)
        XCTAssertGreaterThan(count("cost"), 0, "Cache byte count must parse as a positive ASCII integer")
        XCTAssertLessThanOrEqual(count("cost"), 32 * 1024 * 1024)
        XCTAssertEqual(count("entries"), 4)
        XCTAssertEqual(count("pixels"), before, "Fresh authority must reuse all four resident photo variants")
        XCTAssertEqual(count("evictions"), 0)
        XCTAssertEqual(count("loads"), loads)
        let final = XCTAttachment(string: probe.label); final.name = "SYNTHETIC all four photo variants reused after fresh authority"; final.lifetime = .keepAlways; add(final)
        tap(photo, in: app)
        let close = app.buttons["workout.photo.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        let galleryPixels = app.staticTexts.matching(identifier: "workout.photo.decodeProbe")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "kind=full;")).firstMatch
        XCTAssertTrue(galleryPixels.waitForExistence(timeout: 15))
        let galleryEvidence = XCTAttachment(string: galleryPixels.label)
        galleryEvidence.name = "SYNTHETIC full gallery pixel dimensions ASCII"; galleryEvidence.lifetime = .keepAlways; add(galleryEvidence)
        let dimensions = galleryPixels.label.components(separatedBy: ";").dropFirst().compactMap { Int($0.components(separatedBy: "=").last ?? "") }
        XCTAssertEqual(dimensions.max(), 2048, "Gallery must never receive the feed thumbnail variant")
        capture(app, name: "SYNTHETIC gallery retains full resolution with separate feed variants")
        tap(close, in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(count("cost"), 32 * 1024 * 1024)
    }

    func test72MapAndPhotoDetailKeepsMediaToggleAndSameMovableLayer() {
        continueAfterFailure = false
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROJECTION_OWN_PARITY_QA":"1"])
        defer { app.terminate() }
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        let running = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "DEMO ·", "공원 러닝")).firstMatch
        uxReveal(running, in: app); tap(running, in: app)
        let toggle = app.buttons["운동 사진 보기"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        tap(toggle, in: app)
        let mapToggle = app.buttons["지도로 전환"].firstMatch
        XCTAssertTrue(mapToggle.waitForExistence(timeout: 5))
        let photo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.detail.heroPhoto.")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        let handle = app.buttons["상세 정보 시트"]
        XCTAssertTrue(handle.exists)
        capture(app, name: "72 existing photo-plus-map detail retains map inset and shared layer")
        tap(handle, in: app)
        let collapse = app.buttons["상세 정보 접기"].firstMatch
        XCTAssertTrue(collapse.waitForExistence(timeout: 5)); tap(collapse, in: app)
        XCTAssertTrue(mapToggle.waitForExistence(timeout: 5)); tap(mapToggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workout.detail.routePlayback"].exists)
        tap(app.buttons["뒤로가기"].firstMatch, in: app)
        XCTAssertTrue(app.buttons["soom.tab.feed"].waitForExistence(timeout: 5))
    }

    func test72PhotoOnlyDetailHasMovableLayerWithoutMapAndRetainsGallery() {
        continueAfterFailure = false
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1", "SOOM_PROFILE_NAVIGATION_QA":"1"])
        defer { app.terminate() }
        let title = app.buttons["러닝 기록"].firstMatch
        uxReveal(title, in: app); tap(title, in: app)
        let hero = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.detail.heroPhoto.")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["workout.detail.heroMediaToggle"].exists)
        XCTAssertFalse(app.buttons["workout.detail.routePlayback"].exists)
        let handle = app.buttons["상세 정보 시트"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        capture(app, name: "72 photo-only detail uses same media sheet without map")
        let initialY = handle.frame.minY
        let dragStart = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        dragStart.press(forDuration: 0.1, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: 190)))
        let lowered = NSPredicate { _, _ in handle.exists && handle.frame.minY > initialY + 40 }
        expectation(for: lowered, evaluatedWith: nil); waitForExpectations(timeout: 5)
        capture(app, name: "72 photo-only downward drag enlarges photo viewport")
        let lowerStart = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        lowerStart.press(forDuration: 0.1, thenDragTo: lowerStart.withOffset(CGVector(dx: 0, dy: -190)))
        let raised = NSPredicate { _, _ in handle.exists && handle.frame.minY <= initialY + 20 }
        expectation(for: raised, evaluatedWith: nil); waitForExpectations(timeout: 5)
        tap(handle, in: app)
        let collapse = app.buttons["상세 정보 접기"].firstMatch
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        tap(collapse, in: app)
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let image = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.detail.heroPhoto.")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        tap(image, in: app)
        XCTAssertTrue(app.buttons["workout.photo.close"].waitForExistence(timeout: 5))
        tap(app.buttons["workout.photo.close"], in: app)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(handle.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["게시물 삭제"].exists)
        tap(app.buttons["뒤로가기"].firstMatch, in: app)
        XCTAssertTrue(app.buttons["댓글 보기"].waitForExistence(timeout: 5))
    }

    func testProfilePolicyLegacyPhotosWithoutSnapshotSurviveDetailAndForeground() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1", "SOOM_PROFILE_NAVIGATION_QA":"1"])
        defer { app.terminate() }
        func assertPhotoPixels(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
            // Button metadata exists even while an image is a skeleton. Inspect
            // actual fixture pixels, not just the button or page count.
            func saturatedFraction() -> Double {
                guard let image = app.screenshot().image.cgImage else { return 0 }
                let width = image.width, height = image.height
                let scaleX = CGFloat(width) / app.frame.width, scaleY = CGFloat(height) / app.frame.height
                let visible = element.frame.intersection(app.frame).insetBy(dx: 8, dy: 8)
                guard visible.width > 10, visible.height > 10 else { return 0 }
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
                }
                guard drawn else { return 0 }
                var saturated = 0, total = 0
                for y in stride(from: max(0, Int(visible.minY * scaleY)), to: min(height, Int(visible.maxY * scaleY)), by: 8) {
                    for x in stride(from: max(0, Int(visible.minX * scaleX)), to: min(width, Int(visible.maxX * scaleX)), by: 8) {
                        let i = (y * width + x) * 4, r = Int(bytes[i]), g = Int(bytes[i+1]), b = Int(bytes[i+2])
                        if max(r,g,b) - min(r,g,b) > 80 { saturated += 1 }
                        total += 1
                    }
                }
                return total > 0 ? Double(saturated) / Double(total) : 0
            }
            let ready = NSPredicate { _, _ in saturatedFraction() > 0.35 }
            XCTAssertTrue(expectation(for: ready, evaluatedWith: nil).isInverted == false)
            waitForExpectations(timeout: 8)
            XCTAssertGreaterThan(saturatedFraction(), 0.35, "Synthetic photo must render instead of a skeleton", file: file, line: line)
        }
        let photo = app.buttons["workout.card.open.photo"].firstMatch
        uxReveal(photo, in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 8))
        let indicator = app.staticTexts.matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "운동 사진", "4페이지")).firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertTrue((indicator.value as? String ?? "").contains("4페이지"))
        XCTAssertFalse(app.staticTexts["사진을 불러올 수 없어요"].exists)
        assertPhotoPixels(photo)
        capture(app, name: "Profile policy four original-source photos without legacy detail authority")
        app.swipeUp(); app.swipeDown()
        uxReveal(photo, in: app)
        XCTAssertTrue(photo.exists)
        XCTAssertFalse(app.staticTexts["사진을 불러올 수 없어요"].exists)
        capture(app, name: "Profile policy photos retained after scroll reappearance")
        tap(photo, in: app)
        XCTAssertTrue(app.buttons["workout.photo.close"].waitForExistence(timeout: 5))
        app.swipeLeft()
        capture(app, name: "Profile policy synthetic photo gallery second image")
        tap(app.buttons["workout.photo.close"], in: app)
        for attempt in 0..<2 {
            uxReveal(app.buttons["러닝 기록"].firstMatch, in: app)
            tap(app.buttons["러닝 기록"].firstMatch, in: app)
            let detailPhoto = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.detail.heroPhoto.")).firstMatch
            XCTAssertTrue(detailPhoto.waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["사진 4"].waitForExistence(timeout: 5))
            assertPhotoPixels(detailPhoto)
            capture(app, name: "Profile policy actual detail photo pixels \(attempt)")
            XCTAssertFalse(app.buttons["게시물 삭제"].exists)
            if attempt == 0 {
                XCUIDevice.shared.press(.home); app.activate()
                XCTAssertTrue(detailPhoto.waitForExistence(timeout: 8))
                XCTAssertFalse(app.staticTexts["사진을 불러올 수 없어요"].exists)
                assertPhotoPixels(detailPhoto)
            }
            tap(detailPhoto, in: app)
            XCTAssertTrue(app.buttons["workout.photo.close"].waitForExistence(timeout: 5))
            capture(app, name: "Profile policy readonly detail gallery and foreground \(attempt)")
            tap(app.buttons["workout.photo.close"], in: app)
            tap(app.buttons["뒤로가기"].firstMatch, in: app)
            XCTAssertTrue(app.buttons["댓글 보기"].waitForExistence(timeout: 5))
        }
        let author = app.buttons["데모 운동 기록 프로필 보기"].firstMatch
        uxReveal(author, in: app); tap(author, in: app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout: 8))
        tap(app.buttons["profile.tab.gallery"].firstMatch, in: app)
        let galleryItem = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.gallery.item.")).firstMatch
        XCTAssertTrue(galleryItem.waitForExistence(timeout: 8))
        uxReveal(galleryItem, in: app); assertPhotoPixels(galleryItem)
        capture(app, name: "Profile gallery uses profile-policy photos without a detail snapshot")
        let probe = app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@", "profile.navigation.probe.")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 8))
        let instance = probe.label.components(separatedBy:";").first
        let galleryY = galleryItem.frame.minY
        for visit in 0..<2 {
            tap(galleryItem, in: app)
            let profileDetailPhoto = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.detail.heroPhoto.")).firstMatch
            XCTAssertTrue(profileDetailPhoto.waitForExistence(timeout: 8))
            assertPhotoPixels(profileDetailPhoto)
            if visit == 0 {
                XCUIDevice.shared.press(.home); app.activate()
                XCTAssertTrue(profileDetailPhoto.waitForExistence(timeout: 8))
                assertPhotoPixels(profileDetailPhoto)
                capture(app, name: "Gallery-owned detail stays open after fresh foreground photo checks")
            }
            tap(app.buttons["뒤로가기"].firstMatch, in: app)
            XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout: 5))
            XCTAssertTrue(galleryItem.waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["profile.tab.gallery"].isSelected)
            XCTAssertEqual(probe.label.components(separatedBy:";").first, instance)
            XCTAssertEqual(galleryItem.frame.minY, galleryY, accuracy: 4)
        }
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(galleryItem.waitForExistence(timeout: 8))
        uxReveal(galleryItem, in: app); assertPhotoPixels(galleryItem)
        capture(app, name: "Profile gallery reauthorizes photos after foreground")

    }

    func testNativeProjectionCommentsUseIndependentIdentity() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_NATIVE_COMMENT_QA":"1"])
        defer { app.terminate() }
        uxReveal(app.buttons["댓글 보기"], in: app)
        capture(app, name: "SYNTHETIC native projection summary with connected comments")
        tap(app.buttons["댓글 보기"], in: app)
        XCTAssertTrue(app.navigationBars["댓글"].waitForExistence(timeout: 8))
        let input = app.textFields["feed.comment.input"]
        tap(input, in: app); input.typeText("새 운동 댓글 확인")
        tap(app.buttons["댓글 보내기"], in: app)
        XCTAssertTrue(app.staticTexts["새 운동 댓글 확인"].waitForExistence(timeout: 8))
        capture(app, name: "SYNTHETIC native projection comments no legacy post ID")
    }

    func testProjectionSummaryAndInboxRecommendations() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA": "1"])
        defer { app.terminate() }
        let summary = app.staticTexts["댓글과 사진 연결 준비 중"]
        uxReveal(summary, in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["댓글과 사진 연결 준비 중"].waitForExistence(timeout: 8))
        capture(app, name: "SYNTHETIC projection summary without invented legacy post")
        scrollToInboxHeader(app)
        tap(app.buttons["알림"], in: app)
        let heading = app.staticTexts["추천"]
        for _ in 0..<12 {
            if app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notifications.recommendations.follow.")).firstMatch.isHittable || app.staticTexts["notifications.recommendations.empty"].isHittable { break }
            app.swipeUp()
        }
        let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notifications.recommendations.follow.")).firstMatch
        XCTAssertTrue(candidate.exists || app.staticTexts["notifications.recommendations.empty"].exists || heading.exists)
        capture(app, name: "SYNTHETIC inbox recommendations without external follow action")
    }

    func testInboxTargetsOpenIndependentlyWithoutExpandingHome() {
        let app = uxLaunch(environment: ["SOOM_NOTIFICATION_CARD_QA": "1"])
        defer { app.terminate() }
        let target = app.descendants(matching: .any)["feed.card.D3600000-0000-4000-8000-000000000010"].firstMatch
        let card = app.descendants(matching: .any)["feed.notification.card.D3600000-0000-4000-8000-000000000010"].firstMatch
        let commentID = "notifications.open.D3700000-0000-4000-8000-000000000001"
        let reactionID = "notifications.open.D3700000-0000-4000-8000-000000000002"
        let missingID = "notifications.open.D3700000-0000-4000-8000-000000000003"
        tap(app.buttons["알림"], in: app)
        XCTAssertTrue(app.navigationBars["알림"].waitForExistence(timeout:8))
        XCTAssertEqual(app.sheets.count,0,"Inbox must be a full navigation page")
        tap(app.buttons["notifications.settings"],in:app)
        XCTAssertTrue(app.navigationBars["알림 설정"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["push.permission.status"].exists)
        tap(app.navigationBars["알림 설정"].buttons.element(boundBy:0),in:app)
        tap(app.buttons[commentID], in: app)
        XCTAssertTrue(app.navigationBars["댓글"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["댓글 보내기"].exists)
        capture(app, name: "Inbox page opens comments above matching authorized card")
        tap(app.buttons["닫기"], in: app)
        XCTAssertTrue(card.waitForExistence(timeout:8))
        XCTAssertTrue(app.navigationBars["알림의 운동"].exists)
        XCTAssertFalse(target.exists, "A nonfollowing notification target must not enter the home timeline")
        XCTAssertFalse(app.navigationBars["댓글"].exists)
        capture(app, name: "Closing notification comments retains target card outside home")
        tap(app.navigationBars["알림의 운동"].buttons.element(boundBy:0),in:app)
        XCTAssertTrue(app.navigationBars["알림"].waitForExistence(timeout:8))
        tap(app.buttons[reactionID], in: app)
        XCTAssertTrue(card.waitForExistence(timeout:10))
        XCTAssertFalse(app.navigationBars["댓글"].exists)
        tap(app.navigationBars["알림의 운동"].buttons.element(boundBy:0),in:app)
        tap(app.buttons[commentID], in: app)
        XCTAssertTrue(app.navigationBars["댓글"].waitForExistence(timeout:10))
        let input=app.textFields["feed.comment.input"]
        tap(input,in:app); input.typeText("알림 프로필 독립 이동 확인")
        tap(app.buttons["댓글 보내기"],in:app)
        XCTAssertTrue(app.staticTexts["알림 프로필 독립 이동 확인"].waitForExistence(timeout:8))
        let author=app.buttons.matching(identifier:"댓글 작성자 프로필").firstMatch
        tap(author,in:app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:10))
        XCTAssertFalse(app.navigationBars["댓글"].exists)
        capture(app,name:"Legacy comment sheet dismissed before independent profile page")
        tap(app.navigationBars["프로필"].buttons.element(boundBy:0),in:app)
        XCTAssertTrue(card.waitForExistence(timeout:8));XCTAssertFalse(app.navigationBars["댓글"].exists)
        tap(app.navigationBars["알림의 운동"].buttons.element(boundBy:0),in:app)
        tap(app.buttons[missingID],in:app)
        let unavailable=app.staticTexts["운동 카드를 열 수 없어요"].waitForExistence(timeout:10)
        capture(app,name:"Missing notification card has recoverable state")
        XCTAssertTrue(unavailable)
        XCTAssertFalse(app.navigationBars["댓글"].exists)
        tap(app.navigationBars["알림의 운동"].buttons.element(boundBy:0),in:app)
        tap(app.navigationBars["알림"].buttons.element(boundBy:0),in:app)
        XCTAssertTrue(app.staticTexts["feed.home.scope"].waitForExistence(timeout:8))
        XCTAssertFalse(target.exists)
        capture(app,name:"Inbox back restores unchanged home membership")
    }

    private func scrollToInboxHeader(_ app: XCUIApplication) {
        for _ in 0..<30 {
            if app.buttons["알림"].exists && app.buttons["알림"].isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(app.buttons["알림"].isHittable)
    }

    func testEventInboxUnavailableIsSeparateFromSocialInbox() {
        let app=uxLaunch();defer{app.terminate()}
        tap(app.buttons["알림"],in:app)
        tap(app.buttons["notifications.events"],in:app)
        XCTAssertTrue(app.navigationBars["이벤트 알림"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["event.error"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["이벤트 알림이 없어요"].exists)
        capture(app,name:"Event feature off unavailable separate from social inbox")
    }
    private func detailFixtureApp(healthKit: Bool = false, gesture: Bool = false, sparse: Bool = false, legacyZero: Bool = false) -> XCUIApplication {
        let app=XCUIApplication()
        app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1"
        app.launchEnvironment["SOOM_DETAIL_MOTION_QA"]="1"
        if healthKit { app.launchEnvironment["SOOM_HEALTH_DETAIL_QA"]="1" }
        if gesture { app.launchEnvironment["SOOM_EFFORT_GESTURE_QA"]="1" }
        if sparse { app.launchEnvironment["SOOM_EFFORT_SPARSE_QA"]="1" }
        if legacyZero { app.launchEnvironment["SOOM_EFFORT_LEGACY_ZERO_QA"]="1" }
        app.launch()
        XCTAssertTrue(app.buttons["fixture.menu"].waitForExistence(timeout:15))
        return app
    }
    private func selectEffortFixture(_ title: String, in app:XCUIApplication) {
        XCTAssertTrue(app.buttons["effort.cancel"].waitForNonExistence(timeout:5))
        let menu=app.buttons["fixture.menu"]
        menu.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        tap(app.buttons["fixture."+title],in:app)
    }
    private func openEffort(in app:XCUIApplication) {
        XCTAssertTrue(app.buttons["effort.cancel"].waitForNonExistence(timeout:5))
        let open=app.buttons["effort.open"]
        for _ in 0..<10 {
            if open.isHittable { break }
            if open.frame.maxY < 200 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(open.isHittable);tap(open,in:app)
        XCTAssertTrue(app.buttons["effort.cancel"].waitForExistence(timeout:5))
    }
    private func dragEffort(to fraction:CGFloat, in app:XCUIApplication) {
        let slider=app.descendants(matching:.any)["effort.slider"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout:5))
        let start=slider.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.1,thenDragTo:slider.coordinate(withNormalizedOffset:CGVector(dx:fraction,dy:0.5)))
    }
    func testEffortReferenceCenteredWedgeWithSparseAndEligibleHistory() throws {
        continueAfterFailure = false; executionTimeAllowance = 240
        for scenario in ["없음", "비교 1개", "평소 범위"] {
            let app = detailFixtureApp(gesture: true, sparse: scenario == "비교 1개")
            defer { app.terminate() }
            if scenario != "비교 1개" { selectEffortFixture(scenario, in: app) }
            openEffort(in: app)
            let slider = app.descendants(matching: .any)["effort.slider"].firstMatch
            XCTAssertTrue((slider.value as? String ?? "").contains("접힘"))
            XCTAssertTrue((slider.value as? String ?? "").contains("빗금 숨김"))
            for tick in 1...10 { XCTAssertTrue(app.staticTexts["effort.tick.\(tick)"].exists) }
            let character = app.descendants(matching: .any)["effort.character"].firstMatch
            XCTAssertEqual(character.frame.midX, app.frame.midX, accuracy: 3)
            XCTAssertLessThan(character.frame.maxY, app.staticTexts["effort.state"].frame.minY)
            XCTAssertEqual(app.staticTexts["effort.question"].label, "운동이 어땠나요?")
            XCTAssertEqual(app.staticTexts["effort.range.summary"].exists, scenario == "평소 범위")
            XCTAssertEqual(app.staticTexts["effort.range.empty"].exists, scenario != "평소 범위")
            let restWidth = app.staticTexts["effort.tick.10"].frame.midX - app.staticTexts["effort.tick.1"].frame.midX
            captureDetail(app, name: "SYNTHETIC reference compact " + scenario)
            tap(app.buttons["effort.expansion"], in: app)
            XCTAssertTrue((slider.value as? String ?? "").contains(scenario == "평소 범위" ? "빗금 표시" : "빗금 숨김"))
            XCTAssertGreaterThan(app.staticTexts["effort.tick.10"].frame.midX - app.staticTexts["effort.tick.1"].frame.midX, restWidth)
            captureDetail(app, name: "SYNTHETIC reference expanded " + scenario)
            for score in [1, 7, 10] {
                chooseEffortStep(score, in: app)
                XCTAssertEqual(app.staticTexts["effort.value"].label, "\(score) / 10")
                XCTAssertTrue((slider.value as? String ?? "").contains("펼침"))
                XCTAssertTrue((slider.value as? String ?? "").contains(scenario == "평소 범위" ? "빗금 표시" : "빗금 숨김"))
                captureDetail(app, name: "SYNTHETIC reference settled \(scenario) score \(score)")
            }
            tap(app.buttons["effort.cancel"], in: app); openEffort(in: app)
            XCTAssertEqual(app.staticTexts["effort.value"].label, scenario == "없음" ? "선택 전" : "7 / 10")
            XCTAssertTrue((slider.value as? String ?? "").contains("접힘"))
            tap(app.buttons["effort.cancel"], in: app)
        }
    }

    func testEffortColorStagesAndAlwaysNumberedTicks() {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = detailFixtureApp(); defer { app.terminate() }
        openEffort(in: app)
        XCTAssertLessThan(app.staticTexts["effort.title"].frame.maxY, app.staticTexts["effort.question"].frame.minY)
        XCTAssertLessThan(app.staticTexts["effort.question"].frame.maxY, app.staticTexts["effort.state"].frame.minY)
        XCTAssertTrue(app.staticTexts["effort.range.empty"].exists)
        captureDetail(app, name: "Effort new empty no invented range")
        tap(app.buttons["effort.cancel"], in: app)
        selectEffortFixture("평소 범위", in: app); openEffort(in: app)
        for (fraction, name) in [(0.12, "low"), (0.5, "middle"), (0.95, "high")] {
            dragEffort(to: fraction, in: app)
            let slider = app.descendants(matching: .any)["effort.slider"].firstMatch
            XCTAssertTrue((slider.value as? String ?? "").contains("10 중"))
            XCTAssertTrue(app.staticTexts["effort.value"].label.contains("/ 10"))
            for tick in 1...10 { XCTAssertTrue(app.staticTexts["effort.tick.\(tick)"].exists, "Every effort step must keep its numeric label") }
            // Let the time-based color transition settle before each actual capture.
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            captureDetail(app, name: "SOOM color and numbered wedge " + name)
            if name == "high" {
                XCTAssertEqual(app.staticTexts["effort.range.status"].label, "평소 범위 이상")
                XCTAssertEqual(app.buttons["effort.save"].value as? String, "운동 강도 10 / 10")
                let badge = app.staticTexts["effort.range.status"].frame
                XCTAssertGreaterThanOrEqual(badge.minX, 0); XCTAssertLessThanOrEqual(badge.maxX, app.frame.width)
            }
        }
        let slider = app.descendants(matching: .any)["effort.slider"].firstMatch
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 0.2,
            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.6)
        captureDetail(app, name: "Effort expanded drag released")
        tap(app.buttons["effort.cancel"], in: app)
        selectEffortFixture("심박 9퍼센트", in: app)
        let zone = element("detail.hrZone.2", in: app); reveal(zone, in: app)
        XCTAssertTrue(zone.label.contains("9 퍼센트"))
        captureDetail(app, name: "Zones proportional zero nine ninety-one percent")
    }

    func testDetailEffortMissingCancelSuccessAndExistingAppleFixtures() throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=detailFixtureApp()
        captureDetail(app,name:"Detail white original section order")
        openEffort(in:app)
        XCTAssertEqual(app.buttons["effort.save"].label, "저장")
        XCTAssertGreaterThanOrEqual(app.buttons["effort.cancel"].frame.minY, app.buttons["effort.save"].frame.maxY)
        XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        captureDetail(app,name:"Effort empty unselected approved SOOM character")
        dragEffort(to:0.85,in:app)
        XCTAssertTrue(app.buttons["effort.save"].isEnabled)
        captureDetail(app,name:"Effort continuous high preview before confirmation")
        tap(app.buttons["effort.cancel"],in:app)
        openEffort(in:app)
        XCTAssertFalse(app.buttons["effort.save"].isEnabled)
        dragEffort(to:0.68,in:app);tap(app.buttons["effort.save"],in:app)
        XCTAssertTrue(app.buttons["effort.open"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["SOOM에서 확인 · 이 기기에 저장"].exists)
        captureDetail(app,name:"Effort confirmed local fixture save")
        for source in ["Apple 기록","Apple 추정","SOOM 저장값"] {
            selectEffortFixture(source,in:app);openEffort(in:app)
            XCTAssertFalse(app.buttons["effort.save"].isEnabled)
            captureDetail(app,name:"Effort preloaded " + source)
            dragEffort(to:0.92,in:app);tap(app.buttons["effort.cancel"],in:app)
            openEffort(in:app)
            XCTAssertEqual(app.staticTexts["effort.value"].label,source == "SOOM 저장값" ? "4 / 10" : "선택 전")
            tap(app.buttons["effort.cancel"],in:app)
        }
        app.terminate()
    }

    func testEffortReferenceGuideVisibleWithoutChangingSelection() {
        continueAfterFailure = false; executionTimeAllowance = 120
        let app = detailFixtureApp(); defer { app.terminate() }
        selectEffortFixture("평소 범위", in: app); openEffort(in: app)
        let slider = app.descendants(matching: .any)["effort.slider"].firstMatch
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.5)).press(forDuration: 0.8)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "7 / 10")
        XCTAssertEqual(app.staticTexts["effort.range.status"].label, "평소 범위 이상")
        captureDetail(app, name: "SOOM redesigned effort seven reference match")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 0.8,
            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "7 / 10")
        captureDetail(app, name: "SOOM redesigned effort seven after expansion returns")
        let guide = app.buttons["effort.guide"].firstMatch
        reveal(guide, in: app); tap(guide, in: app)
        let explanation = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "내 입력 점수 범위는 최근 21일")).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        // Scroll inside the sheet viewport, away from its fixed action buttons
        // and the disclosure toggle; an app-wide press/drag can toggle it again.
        for _ in 0..<6 {
            if explanation.exists && explanation.isHittable { break }
            app.scrollViews["effort.scroll"].swipeUp()
        }
        XCTAssertTrue(explanation.isHittable)
        XCTAssertTrue(explanation.label.contains("최소 5개"))
        XCTAssertTrue(explanation.label.contains("가운데 50%"))
        captureDetail(app, name: "SOOM redesigned effort guide personal range basis")
        tap(app.buttons["effort.cancel"], in: app)
    }

    func testNextDetailForegroundRestoresPersonalScrollChartsAndTab() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = nextLifecycleFixture()
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        let running = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "DEMO ·", "공원 러닝")).firstMatch
        reveal(running, in: app); tap(running, in: app)
        if app.buttons["상세 정보 시트"].isHittable { tap(app.buttons["상세 정보 시트"], in: app) }
        let charts = app.staticTexts["detail.charts.heading"]
        reveal(charts, in: app)
        let before = charts.frame.minY
        captureDetail(app, name: "Next personal detail before background")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(charts.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["detail.charts.toggle"].exists)
        XCTAssertLessThan(abs(charts.frame.minY - before), 24)
        captureDetail(app, name: "Next personal same detail scroll and chart after foreground")
        app.terminate()
    }

    func testNextDetailFreshPrivacyReceiptPreservesSharedNavigationAndDisclosure() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = nextLifecycleFixture()
        tap(app.buttons["soom.tab.feed"], in: app)
        let title = app.staticTexts["회복 친화 라이딩"].firstMatch
        reveal(title, in: app); tap(title, in: app)
        XCTAssertTrue(app.buttons["feed.post.bookmark"].waitForExistence(timeout: 10))
        if app.buttons["상세 정보 시트"].isHittable { tap(app.buttons["상세 정보 시트"], in: app) }
        let charts = app.staticTexts["detail.charts.heading"]
        reveal(charts, in: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        captureDetail(app, name: "Next shared detail verified before background")
        XCTAssertTrue(charts.isHittable)
        // A center drag can land on the chart's value-selection surface.
        // Establish an actual content offset using its outer scroll gutter.
        for _ in 0..<6 {
            let state = app.staticTexts["detail.sheet.geometry"].label
            let current = state.components(separatedBy: "scroll=").last?.components(separatedBy: " ").first ?? "0"
            if (Int(current.replacingOccurrences(of: ",", with: "")) ?? 0) > 100 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.72)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.42)))
        }
        let before = charts.frame.minY
        let beforeState = app.staticTexts["detail.sheet.geometry"].label
        let offset = beforeState.components(separatedBy: "scroll=").last?.components(separatedBy: " ").first ?? "0"
        XCTAssertGreaterThan(Int(offset.replacingOccurrences(of: ",", with: "")) ?? 0, 100, "Fixture must exercise a real nonzero scroll restoration: \(beforeState)")
        XCUIDevice.shared.press(.home); app.activate()
        captureDetail(app, name: "Next fresh receipt pending hides shared content")
        XCTAssertTrue(charts.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["detail.charts.toggle"].exists)
        captureDetail(app, name: "Next shared detail restored before scroll assertion")
        let afterState = app.staticTexts["detail.sheet.geometry"].label
        let afterOffset = afterState.components(separatedBy: "scroll=").last?.components(separatedBy: " ").first ?? "0"
        XCTAssertLessThan(abs((Int(afterOffset.replacingOccurrences(of: ",", with: "")) ?? 0) - (Int(offset.replacingOccurrences(of: ",", with: "")) ?? 0)), 3,
            "Gesture ownership must follow the restored scroll offset too")
        let attachment = XCTAttachment(string: "Before: \(beforeState)\nAfter: \(afterState)\nchartY before=\(before) after=\(charts.frame.minY)")
        attachment.name = "shared-detail-lifecycle-geometry"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertLessThan(abs(charts.frame.minY - before), 32)
        captureDetail(app, name: "Next shared detail after fresh synthetic privacy receipt")
        app.terminate()
    }

    func testNextDetailFailedFreshReceiptHidesSharedContentAndKeepsPersonalTab() throws {
        continueAfterFailure = false; executionTimeAllowance = 120
        let app = nextLifecycleFixture(failOnReturn: true)
        defer { app.terminate() }
        tap(app.buttons["soom.tab.feed"], in: app)
        let title = app.staticTexts["회복 친화 라이딩"].firstMatch
        reveal(title, in: app); tap(title, in: app)
        XCTAssertTrue(app.buttons["feed.post.bookmark"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["social.locked"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["feed.post.bookmark"].exists)
        captureDetail(app, name: "Fresh failure recovery viewport before action assertion")
        let recoveryTree = XCTAttachment(string: app.debugDescription)
        recoveryTree.name = "fresh-failure-recovery-hierarchy"; recoveryTree.lifetime = .keepAlways; add(recoveryTree)
        let settings = app.buttons["social.lock.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable, "The recovery action must remain above the tab bar")
        XCTAssertLessThan(settings.frame.maxY, app.buttons["soom.tab.feed"].frame.minY)
        captureDetail(app, name: "Next failed fresh receipt hides protected detail")
        tap(settings, in: app)
        XCTAssertTrue(app.navigationBars["계정 · 새 운동 공개범위"].waitForExistence(timeout: 5))
        tap(app.buttons["닫기"], in: app)
        tap(app.buttons["soom.tab.activity"], in: app)
        XCTAssertTrue(app.buttons["activity.section.workouts"].waitForExistence(timeout: 10))
        app.terminate()
    }

    private func nextLifecycleFixture(failOnReturn: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
        app.launchEnvironment["SOOM_DETAIL_REVALIDATION_QA"] = "1"
        if failOnReturn { app.launchEnvironment["SOOM_DETAIL_REVALIDATION_FAIL"] = "1" }
        app.launch()
        XCTAssertTrue(app.buttons["soom.tab.activity"].waitForExistence(timeout: 15))
        return app
    }
    func testDetailEffortFailureRetainsDraftRetryAndAccessibilityPreview() throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=detailFixtureApp();selectEffortFixture("저장 실패",in:app);openEffort(in:app)
        dragEffort(to:0.82,in:app)
        let value=app.staticTexts["effort.value"].label
        tap(app.buttons["effort.save"],in:app)
        XCTAssertTrue(app.staticTexts["effort.error"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["effort.value"].label,value)
        captureDetail(app,name:"Effort save failure retains draft and enabled retry")
        tap(app.buttons["effort.save"],in:app)
        XCTAssertTrue(app.buttons["effort.open"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["effort.cancel"].waitForNonExistence(timeout:5))
        app.switches["모션 줄이기"].firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        app.switches["큰 글자"].firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertEqual(app.switches["모션 줄이기"].firstMatch.value as? String,"1")
        XCTAssertEqual(app.switches["큰 글자"].firstMatch.value as? String,"1")
        captureDetail(app,name:"Detail enabled accessibility3 and reduced motion preview")
        openEffort(in:app)
        XCTAssertGreaterThanOrEqual(app.staticTexts["effort.value"].frame.height,28)
        captureDetail(app,name:"Effort Reduce Motion preview and accessibility large text")
        let largeSlider = app.descendants(matching: .any)["effort.slider"].firstMatch
        for _ in 0..<12 {
            if largeSlider.isHittable && largeSlider.frame.maxY < app.buttons["effort.save"].frame.minY - 12 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.43)))
        }
        XCTAssertTrue(largeSlider.isHittable)
        XCTAssertLessThan(largeSlider.frame.maxY, app.buttons["effort.save"].frame.minY)
        captureDetail(app, name: "Effort large slider before vertical gesture")
        let beforeScrollValue = app.staticTexts["effort.value"].label
        let beforeScrollY = largeSlider.frame.minY
        let beforeSaveY = app.buttons["effort.save"].frame.minY
        // Revealing the whole slider can already reach the bottom of this
        // large-text sheet. Scroll back toward its known offscreen header.
        largeSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.15)).press(forDuration: 0.05,
            thenDragTo: largeSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.55)),
            withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(app.buttons["effort.save"].exists, "Content scrolling must keep the sheet open")
        XCTAssertEqual(app.buttons["effort.save"].frame.minY, beforeSaveY, accuracy: 1, "Scroll the content, not the sheet")
        XCTAssertEqual(app.staticTexts["effort.value"].label, beforeScrollValue, "Vertical scrolling must not edit effort")
        XCTAssertGreaterThan(largeSlider.frame.minY, beforeScrollY, "Vertical swipe on scale must scroll toward the header")
        dragEffort(to: 0.62, in: app)
        captureDetail(app, name: "Effort accessibility3 Reduce Motion reachable slider and fixed save cancel")
        let save=app.buttons["effort.save"]
        for _ in 0..<6 {if save.isHittable {break};app.swipeUp()}
        XCTAssertTrue(save.isHittable)
        XCTAssertGreaterThanOrEqual(save.frame.height,44)
        tap(app.buttons["effort.cancel"],in:app)
        XCTAssertTrue(app.buttons["effort.cancel"].waitForNonExistence(timeout:5))
        let heart=app.staticTexts["detail.charts.heading"]
        reveal(heart, in: app)
        let heartTitle=app.staticTexts["심박수"].firstMatch
        reveal(heartTitle, in: app)
        captureDetail(app,name:"Detail accessibility3 expanded heart chart")
        let splits=app.staticTexts["detail.splits.heading"]
        reveal(splits, in: app)
        reveal(element("detail.split.구간 1", in: app), in: app)
        let firstSplit = element("detail.split.구간 1", in: app)
        for _ in 0..<10 {
            if firstSplit.frame.maxY < app.frame.height - 50 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.72)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.48)))
        }
        XCTAssertLessThan(firstSplit.frame.maxY, app.frame.height - 35)
        captureDetail(app,name:"Detail accessibility3 split text reflow")
        app.terminate()
    }
    func testDetailChartsAndSplitsRemainVisibleWithoutAccordion() throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=detailFixtureApp(); defer { app.terminate() }
        let heart=app.staticTexts["detail.charts.heading"]
        reveal(heart, in: app); XCTAssertTrue(heart.isHittable)
        XCTAssertFalse(app.buttons["detail.charts.toggle"].exists)
        captureDetail(app,name:"Detail always visible measured heart chart")
        let splits=app.staticTexts["detail.splits.heading"]
        reveal(splits, in: app); XCTAssertTrue(splits.isHittable)
        XCTAssertFalse(app.buttons["detail.splits.toggle"].exists)
        captureDetail(app,name:"Detail always visible compact splits")
    }

    func testDetailNativeMapNavigationAndEffortEntryRemainAvailable() throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:10) {tap(app.buttons["reviewDemo.start"],in:app)}
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.workouts"],in:app)
        let running=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@ AND label CONTAINS %@","DEMO ·","공원 러닝")).firstMatch
        reveal(running,in:app)
        XCTAssertFalse(app.staticTexts["본인 피드에 자동 표시 · 공개 범위는 계정에서 관리"].exists)
        tap(running,in:app)
        XCTAssertTrue(app.buttons["workout.detail.more"].waitForExistence(timeout:10))
        captureDetail(app,name:"Native detail original map and navigation preserved")
        if app.buttons["상세 정보 시트"].isHittable {tap(app.buttons["상세 정보 시트"],in:app)}
        openEffort(in:app)
        dragEffort(to:0.55,in:app)
        captureDetail(app,name:"Native detail white effort sheet medium contrast")
        tap(app.buttons["effort.cancel"],in:app)
        XCTAssertTrue(app.buttons["effort.cancel"].waitForNonExistence(timeout:5))
        captureDetail(app,name:"Native detail returned to same summary position")
        app.terminate()
    }

    func testDetailNormalNavigationLayoutMapStatusBar() throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=XCUIApplication()
        app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"]="1"
        app.launch()
        XCTAssertFalse(app.staticTexts["reviewDemo.banner"].exists)
        tap(app.buttons["soom.tab.activity"],in:app);tap(app.buttons["activity.section.workouts"],in:app)
        let running=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@ AND label CONTAINS %@","DEMO ·","공원 러닝")).firstMatch
        reveal(running,in:app);tap(running,in:app)
        XCTAssertTrue(app.buttons["workout.detail.more"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["detail.root.geometry"].label.contains("map=1"))
        captureDetail(app,name:"Normal navigation synthetic map status bar standard")
        if app.buttons["상세 정보 시트"].isHittable {tap(app.buttons["상세 정보 시트"],in:app)}
        captureDetail(app,name:"Normal navigation synthetic expanded white body")
        let collapse=app.buttons["상세 정보 접기"].firstMatch
        collapse.tap()
        captureDetail(app,name:"Normal navigation explicit collapse tap state")
        print("COLLAPSE QA:",app.staticTexts["detail.sheet.geometry"].label)
        let back=app.buttons["workout.detail.back"]
        let tapVisible=NSPredicate { _,_ in app.staticTexts["detail.sheet.geometry"].label.contains("sheet=standard") }
        expectation(for:tapVisible,evaluatedWith:nil);waitForExpectations(timeout:5)
        captureDetail(app,name:"Normal navigation collapse button tap restores map")
        tap(app.buttons["상세 정보 시트"],in:app)
        let start=collapse.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.1,thenDragTo:start.withOffset(CGVector(dx:0,dy:280)))
        let visible=NSPredicate { _,_ in !app.staticTexts["detail.sheet.geometry"].label.contains("sheet=expanded") }
        expectation(for:visible,evaluatedWith:nil);waitForExpectations(timeout:5)
        captureDetail(app,name:"Normal navigation detail collapsed map remains edge to edge")
        print("BACK QA:",app.buttons.matching(NSPredicate(format:"label == %@","뒤로가기")).allElementsBoundByIndex.map { "\($0.identifier) frame=\($0.frame) hittable=\($0.isHittable)" })
        back.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(app.buttons["soom.tab.feed"].waitForExistence(timeout:5))
        tap(app.buttons["soom.tab.feed"],in:app)
        XCTAssertTrue(app.staticTexts["detail.root.geometry"].label.contains("map=0"))
        captureDetail(app,name:"Normal navigation returns to ordinary feed bounds")
        app.terminate()
    }

    func testDetailEffortSpectrumSlowDragAndSettledThumb() throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=detailFixtureApp();openEffort(in:app)
        let slider=app.descendants(matching:.any)["effort.slider"].firstMatch
        let left=slider.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.5))
        let right=slider.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5))
        left.press(forDuration:0.8,thenDragTo:right,withVelocity:.slow,thenHoldForDuration:1.0)
        captureDetail(app,name:"Effort fixed spectrum high selected filled thumb after slow drag")
        right.press(forDuration:0.8,thenDragTo:left,withVelocity:.slow,thenHoldForDuration:1.0)
        captureDetail(app,name:"Effort fixed spectrum low selected filled thumb after slow drag")
        tap(app.buttons["effort.cancel"],in:app);app.terminate()
    }

    private func captureDetail(_ app:XCUIApplication,name:String) {
        // Wait for the explicitly authored 0.42s transition to settle before
        // checking typography; transition behavior is kept in the test recording.
        Thread.sleep(forTimeInterval:0.65)
        capture(app,name:name)
    }
    func testVisibleCardRouteAutoplaysOnceWithoutManualControl() async throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:10) {tap(app.buttons["reviewDemo.start"],in:app)}
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout:10))
        tap(app.buttons["soom.tab.feed"],in:app)
        let previews=app.descendants(matching:.any).matching(identifier:"workout.card.routePreview")
        func fullyVisiblePreview() -> XCUIElement? {
            previews.allElementsBoundByIndex.first {
                $0.frame.height > 100 && $0.frame.minY >= 170 && $0.frame.maxY <= app.frame.maxY - 120
            }
        }
        for _ in 0..<16 {
            if fullyVisiblePreview() != nil {break}
            app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.75)).press(forDuration:0.01,
                thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)))
        }
        let preview=try XCTUnwrap(fullyVisiblePreview(),"Route must lie inside the real viewport, not a prefetched offscreen host")
        let played=NSPredicate { _,_ in (preview.value as? String)=="재생 1회" }
        let firstPlayback=expectation(for:played,evaluatedWith:nil);await fulfillment(of:[firstPlayback],timeout:12)
        XCTAssertFalse(app.buttons["workout.card.routePlayback"].exists)
        capture(app,name:"Readability visible card route automatically plays once without button")
        try await Task.sleep(for:.seconds(5))
        XCTAssertEqual(preview.value as? String,"재생 1회","Completed animation must never loop")
        app.terminate()
    }

    func testReadabilityOwnerMenuMeasurementsAndCompactProfile() throws {
        continueAfterFailure=false; executionTimeAllowance=240
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:10) {tap(app.buttons["reviewDemo.start"],in:app)}
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout:10))
        selectGateTab("soom.tab.profile", in: app)
        let edit=app.buttons["profile.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout:8));XCTAssertGreaterThanOrEqual(edit.frame.height,44)
        XCTAssertTrue(app.buttons["profile.social.posts"].exists)
        XCTAssertTrue(app.buttons["profile.social.followers"].exists)
        XCTAssertTrue(app.buttons["profile.social.following"].exists)
        XCTAssertFalse(app.buttons["기기 연결"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label MATCHES %@","[0-9]+개의 운동")).firstMatch.exists)
        capture(app,name:"Readability compact profile aligned identity edit and social counts")
        // The demo is a full-screen cover over another root bar. Select the
        // visible bar and verify selection before testing activity children.
        let activityTabs = app.buttons.matching(identifier: "soom.tab.activity").allElementsBoundByIndex
        print("SOOM_GESTALT_QA_ACTIVITY_TABS|" + String(activityTabs.count) + "|" + activityTabs.map { "hittable=\($0.isHittable),selected=\($0.isSelected),frame=\($0.frame)" }.joined(separator: ";"))
        selectGateTab("soom.tab.activity", in: app)
        tap(app.buttons["activity.section.workouts"],in:app)
        let running=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@ AND label CONTAINS %@","DEMO ·","공원 러닝")).firstMatch
        reveal(running,in:app)
        XCTAssertFalse(app.staticTexts["본인 피드에 자동 표시 · 공개 범위는 계정에서 관리"].exists)
        capture(app,name:"Owner workout card without automatic-feed explanatory footer")
        tap(running,in:app)
        let more=app.buttons["workout.detail.more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["댓글 보기"].exists)
        XCTAssertFalse(app.descendants(matching:.any)["workout.source.evidence"].exists)
        XCTAssertFalse(app.buttons["이미지로 공유하기"].exists)
        capture(app,name:"Readability elevated map controls and lower scale")
        let hierarchy=XCTAttachment(string:app.debugDescription);hierarchy.name="Readability share readiness hierarchy";hierarchy.lifetime = .keepAlways;add(hierarchy)
        tap(more,in:app)
        XCTAssertTrue(app.buttons["이미지로 공유하기"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["피드에 공유하기"].exists)
        XCTAssertTrue(app.buttons["기록 수정"].exists)
        XCTAssertTrue(app.buttons["기록 삭제"].exists)
        capture(app,name:"Readability image share and record management without manual publication")
        tap(app.buttons["이미지로 공유하기"],in:app)
        XCTAssertTrue(app.navigationBars["공유하기"].waitForExistence(timeout:8))
        XCTAssertFalse(app.navigationBars["피드에 공유하기"].exists)
        tap(app.buttons["공유 카드 닫기"],in:app)
        if app.buttons["상세 정보 시트"].isHittable {tap(app.buttons["상세 정보 시트"],in:app)}
        let measured=app.staticTexts["심박수"].firstMatch
        for _ in 0..<10 {if measured.isHittable {break};app.swipeUp()}
        XCTAssertTrue(measured.isHittable)
        capture(app,name:"Readability larger measured time charts near core metrics")
        let growth=app.buttons["성장 흐름 자세히 보기"]
        for _ in 0..<18 {if growth.isHittable {break};app.swipeUp()}
        XCTAssertTrue(growth.isHittable);capture(app,name:"Readability growth key summary collapsed")
        tap(growth,in:app);XCTAssertTrue(app.buttons["성장 흐름 접기"].exists)
        capture(app,name:"Readability growth details explicitly expanded")
        app.terminate()
    }

    func testGeneralDemoEntryIsClosedAndURLCannotEnableIt() {
        continueAfterFailure = false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launch()
        XCTAssertTrue(app.buttons["soom.tab.profile"].waitForExistence(timeout:15))
        XCTAssertFalse(app.buttons["reviewDemo.start"].exists)
        app.open(URL(string:"soom://demo")!)
        XCTAssertFalse(app.buttons["reviewDemo.exit"].exists)
        XCTAssertFalse(app.buttons["reviewDemo.start"].exists)
        tap(app.buttons["soom.tab.profile"],in:app)
        let settings=app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout:5));tap(settings,in:app)
        XCTAssertFalse(app.buttons["reviewDemo.start"].exists)
        capture(app,name:"Readability ordinary product entry closed without test fixture flag")
        app.terminate()
    }

    func testPersonalLocalScreensAndRecordingRemainAvailableWhenSocialUnverified() throws {
        continueAfterFailure=false;executionTimeAllowance=240
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"];app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:10){tap(app.buttons["reviewDemo.start"],in:app)}
        XCTAssertTrue(app.buttons["reviewDemo.privacyQA"].waitForExistence(timeout:10))
        tap(app.buttons["reviewDemo.privacyQA"],in:app)
        tap(app.buttons["privacy.choice.public"],in:app)
        tap(app.buttons["privacy.save"],in:app)
        tap(app.buttons["qa.localAccess"],in:app)
        for state in ["gate.off","gate.failure","gate.offline","gate.account","gate.onboarding"] {
            tap(app.buttons[state],in:app)
            selectGateTab("soom.tab.feed", in: app)
            // Verification is a single accessibility element on the skeleton, not a StaticText.
            let status = state == "gate.account"
                ? app.descendants(matching: .any)["social.verifying"].firstMatch
                : app.staticTexts["소셜 기능을 잠갔어요"].firstMatch
            XCTAssertTrue(status.waitForExistence(timeout:8))
            tap(app.buttons["gate.deeplink"],in:app)
            XCTAssertTrue(status.exists)
            XCTAssertFalse(app.buttons["댓글 보기"].isHittable)
            selectGateTab("soom.tab.activity", in: app)
            XCTAssertTrue(app.buttons["activity.section.workouts"].waitForExistence(timeout:8))
            if state == "gate.off" {
                tap(app.buttons["activity.section.workouts"],in:app)
                tap(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","DEMO ·")).firstMatch,in:app)
                XCTAssertTrue(app.buttons["workout.detail.more"].waitForExistence(timeout:10))
                capture(app,name:"LocalGate own14 native detail remains available while server flag off")
                tap(app.buttons["뒤로가기"],in:app)
            }
            selectGateTab("soom.tab.profile", in: app)
            XCTAssertTrue(app.staticTexts["프로필"].firstMatch.waitForExistence(timeout:8))
            let personalChart=app.staticTexts["최근 12주 거리"].firstMatch
            for _ in 0..<8 { if personalChart.isHittable { break };app.swipeUp() }
            XCTAssertTrue(personalChart.isHittable)
            capture(app,name:"LocalGate personal profile analysis available \(state)")
            if state != "gate.onboarding" { tap(app.buttons["gate.reconnect"],in:app) }
        }
        selectGateTab("soom.tab.record", in: app)
        let launch=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","운동 시작,")).firstMatch
        XCTAssertTrue(launch.waitForExistence(timeout:10));capture(app,name:"LocalGate personal recording launch without onboarding or social permission")
        let circle=launch.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        circle.press(forDuration:0.2,thenDragTo:circle.withOffset(CGVector(dx:0,dy:-174)))
        XCTAssertTrue(app.staticTexts["coach.caption"].waitForExistence(timeout:10))
        capture(app,name:"LocalGate active personal recording while social locked and onboarding incomplete")
        tap(app.buttons["일시정지"],in:app);tap(app.buttons["종료"],in:app);tap(app.buttons["운동 종료"],in:app)
        XCTAssertTrue(app.staticTexts["기록 종료"].waitForExistence(timeout:6))
        app.terminate()
    }

    func testSocialDisconnectClearsPeerDetailCommentsAndDeepLinkBeforeReconnect() throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"];app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:10){tap(app.buttons["reviewDemo.start"],in:app)}
        tap(app.buttons["reviewDemo.privacyQA"],in:app);tap(app.buttons["privacy.choice.public"],in:app);tap(app.buttons["privacy.workout.public"],in:app);tap(app.buttons["privacy.save"],in:app)
        tap(app.buttons["qa.localAccess"],in:app)
        selectGateTab("soom.tab.feed", in: app)
        let peers=app.staticTexts.matching(identifier:"회복 친화 라이딩")
        for _ in 0..<10 { if peers.allElementsBoundByIndex.contains(where: { $0.isHittable }) { break };app.swipeUp() }
        tap(try XCTUnwrap(peers.allElementsBoundByIndex.first { $0.isHittable }),in:app)
        XCTAssertTrue(app.buttons["feed.post.bookmark"].waitForExistence(timeout:10))
        capture(app,name:"LocalGate permitted peer detail before disconnect")
        tap(app.buttons["gate.delayOffline"],in:app)
        XCTAssertFalse(app.buttons["댓글 보기"].exists)
        let locked=app.staticTexts["소셜 기능을 잠갔어요"]
        XCTAssertTrue(locked.waitForExistence(timeout:12))
        let gone=NSPredicate { _,_ in !app.navigationBars["댓글"].isHittable && !app.buttons["feed.post.bookmark"].isHittable }
        expectation(for:gone,evaluatedWith:nil);waitForExpectations(timeout:8)
        XCTAssertFalse(app.buttons["댓글 보기"].isHittable)
        capture(app,name:"LocalGate disconnect clears peer cache and open comments")
        tap(app.buttons["gate.deeplink"],in:app);XCTAssertFalse(app.buttons["feed.post.bookmark"].isHittable)
        tap(app.buttons["gate.reconnect"],in:app)
        let restored=app.segmentedControls.matching(identifier:"feed.audience")
        let freshFeed=NSPredicate { _,_ in restored.allElementsBoundByIndex.contains { $0.isHittable } }
        expectation(for:freshFeed,evaluatedWith:nil);waitForExpectations(timeout:10)
        capture(app,name:"LocalGate reconnect opens fresh feed without prior detail or comments")
        XCTAssertFalse(app.buttons["댓글 보기"].isHittable)
        tap(app.buttons["gate.account"],in:app);XCTAssertTrue(app.staticTexts["공개범위를 확인하는 중"].waitForExistence(timeout:8));XCTAssertFalse(app.buttons["feed.post.bookmark"].isHittable)
        app.terminate()
    }

    private func visibleGateButton(_ identifier:String,in app:XCUIApplication) -> XCUIElement {
        let values=app.buttons.matching(identifier:identifier)
        let visible=NSPredicate { _,_ in values.allElementsBoundByIndex.contains { $0.isHittable } }
        expectation(for:visible,evaluatedWith:nil);waitForExpectations(timeout:10)
        return values.allElementsBoundByIndex.last { $0.isHittable } ?? values.firstMatch
    }

    private func selectGateTab(_ identifier: String, in app: XCUIApplication) {
        // The QA full-screen cover exposes two root bars to XCTest. Choose the
        // frontmost bar and verify selection before asserting its child UI.
        for _ in 0..<2 {
            let tab = visibleGateButton(identifier, in: app)
            let frame = tab.frame.intersection(app.frame)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            if identifier == "soom.tab.record" { return }
            // Recheck the exact frontmost tab we tapped. Re-enumerating the
            // duplicate QA bars mid-transition can select a background bar or
            // ask a disappearing element for an invalid activation point.
            let selected = NSPredicate { _, _ in
                tab.exists && (tab.isSelected || tab.value as? String == "선택됨")
            }
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: nil)], timeout: 2) == .completed { return }
        }
        capture(app, name: "QA frontmost tab failed to select " + identifier)
        XCTFail("The frontmost QA tab must become selected: " + identifier)
    }

    func testGuestLocalRecordingBeforeOnboardingWithoutSocialPermission() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"];app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        XCTAssertTrue(app.buttons["onboarding.optional"].waitForExistence(timeout:12),"Actual guest entry on incomplete-onboarding simulator")
        selectGateTab("soom.tab.feed", in: app)
        XCTAssertTrue(app.staticTexts["소셜 기능을 잠갔어요"].waitForExistence(timeout:6))
        selectGateTab("soom.tab.record", in: app)
        let launch=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","운동 시작,")).firstMatch
        XCTAssertTrue(launch.waitForExistence(timeout:10))
        capture(app,name:"LocalGate actual guest recording before onboarding completion")
        app.terminate()
    }

    func testPrivacySelectionFailureExplicitChoiceAndReentry() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"];app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:10){tap(app.buttons["reviewDemo.start"],in:app)}
        guard app.buttons["reviewDemo.privacyQA"].waitForExistence(timeout:10) else { throw XCTSkip("Debug disposable DEMO required") }
        tap(app.buttons["reviewDemo.privacyQA"],in:app)
        let save=app.buttons["privacy.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // A deliberately disabled action need not be hittable; inspect visibility
        // and its disabled state without requiring it to accept an interaction.
        for _ in 0..<7 {
            if save.frame.height > 0 && app.frame.contains(save.frame) { break }
            app.swipeUp()
        }
        XCTAssertTrue(save.exists && save.frame.height > 0 && app.frame.intersects(save.frame))
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(app.staticTexts["qa.privacy.saved"].exists)
        capture(app,name:"Privacy01 explicit signup selection and independent consent")
        tap(app.buttons["다음 저장 실패 체험"],in:app)
        tap(app.buttons["privacy.choice.public"],in:app)
        reveal(app.buttons["privacy.workout.public"],in:app);tap(app.buttons["privacy.workout.public"],in:app)
        reveal(save,in:app);tap(save,in:app)
        let failure=app.staticTexts["저장을 확인하지 못했어요. 공개범위를 다시 불러온 뒤 선택해 주세요."]
        XCTAssertTrue(failure.waitForExistence(timeout:6));XCTAssertFalse(app.staticTexts["qa.privacy.saved"].exists)
        capture(app,name:"Privacy02 failed write never unlocks")
        tap(app.buttons["공개범위 다시 불러오기"],in:app)
        tap(app.buttons["privacy.choice.private"],in:app)
        tap(save,in:app)
        XCTAssertTrue(app.staticTexts["qa.privacy.saved"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["qa.privacy.saved"].label.contains("비공개 계정"))
        XCTAssertTrue(app.staticTexts["qa.privacy.saved"].label.contains("저장 1회"))
        XCTAssertTrue(app.staticTexts["경로·차트 동의: 켜짐"].exists)
        capture(app,name:"Privacy03 explicit private choice confirmed once")
        tap(app.buttons["qa.privacy.reentry"],in:app)
        XCTAssertTrue(app.buttons["privacy.choice.private"].waitForExistence(timeout:6))
        XCTAssertFalse(app.buttons["privacy.choice.public"].isEnabled)
        XCTAssertFalse(app.switches["privacy.measurements"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["privacy.workout.private.fixed"].exists)
        capture(app,name:"Privacy04 selected account reentry preserves ceiling and no extra consent")
        tap(app.buttons["qa.close"],in:app)
        // A new disposable session has no guessed signup choice.
        tap(app.buttons["reviewDemo.privacyQA"],in:app)
        reveal(save,in:app);XCTAssertFalse(save.isEnabled)
        capture(app,name:"Privacy05 interrupted unselected signup remains gated")
        tap(app.buttons["qa.close"],in:app)
    }

    func testPrivacyVisibleChoicesAndExplicitFullSharingConsent() throws {
        continueAfterFailure = false; executionTimeAllowance = 150
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]; app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        enterSyntheticDemo(app)
        XCTAssertTrue(app.buttons["reviewDemo.privacyQA"].waitForExistence(timeout: 10))
        tap(app.buttons["reviewDemo.privacyQA"], in: app)
        tap(app.buttons["privacy.choice.public"], in: app)
        let all = app.buttons["privacy.workout.public"], followers = app.buttons["privacy.workout.followers"]
        XCTAssertTrue(all.exists); XCTAssertTrue(followers.exists)
        XCTAssertFalse(app.buttons["privacy.workout.scope"].exists)
        XCTAssertFalse(app.switches["privacy.measurements"].exists)
        reveal(all, in: app); capture(app, name: "PrivacyFull public account visible workout choices")
        reveal(followers, in: app); tap(followers, in: app)
        let save = app.buttons["privacy.save"]; reveal(save, in: app)
        XCTAssertEqual(save.label, "설정 완료"); XCTAssertTrue(save.isEnabled)
        capture(app, name: "PrivacyFull sharing notice and clear completion action")
        tap(save, in: app)
        XCTAssertTrue(app.staticTexts["qa.privacy.saved"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["경로·차트 동의: 켜짐"].exists)
        tap(app.buttons["qa.privacy.reentry"], in: app)
        tap(app.buttons["qa.privacy.legacyConsent"], in: app)
        let transition = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "이전 설정은 그대로 보관되어 있어요.")).firstMatch
        reveal(transition, in: app); XCTAssertTrue(transition.exists)
        capture(app, name: "PrivacyFull existing false consent needs explicit completion")
        let privateChoice = app.buttons["privacy.choice.private"]
        for _ in 0..<5 { if privateChoice.isHittable { break }; app.swipeDown() }
        tap(privateChoice, in: app)
        let fixed = app.staticTexts["새 운동은 승인된 팔로워만 볼 수 있어요"]
        reveal(fixed, in: app); XCTAssertTrue(fixed.exists)
        XCTAssertFalse(app.buttons["privacy.workout.public"].exists)
        XCTAssertFalse(app.buttons["privacy.workout.followers"].exists)
        XCTAssertFalse(app.switches["privacy.measurements"].exists)
        capture(app, name: "PrivacyFull private account fixed approved followers")
        reveal(save, in: app); tap(save, in: app)
        XCTAssertTrue(app.staticTexts["qa.privacy.saved"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["qa.privacy.saved"].label.contains("비공개 계정"))
        tap(app.buttons["qa.close"], in: app)
    }

    func testLegacyFollowerRequiresExplicitConfirmationAndPreservesDismissedRelationship() throws {
        continueAfterFailure = false; executionTimeAllowance = 150
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]; app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        let demoEntry = app.buttons["reviewDemo.start"]
        XCTAssertTrue(demoEntry.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(demoEntry.frame.height, 44)
        XCTAssertTrue(demoEntry.isHittable)
        capture(app, name: "Legacy guest demo entry remains separate from navigation title")
        tap(demoEntry, in: app)
        XCTAssertTrue(app.buttons["reviewDemo.privacyQA"].waitForExistence(timeout: 10))
        tap(app.buttons["reviewDemo.privacyQA"], in: app); tap(app.buttons["privacy.choice.public"], in: app)
        let followers = app.buttons["privacy.workout.followers"]; reveal(followers, in: app)
        XCTAssertTrue(app.buttons["privacy.workout.public"].exists)
        XCTAssertFalse(app.buttons["privacy.workout.scope"].exists)
        XCTAssertFalse(app.switches["privacy.measurements"].exists)
        capture(app, name: "Privacy visible public and approved follower choices with full detail notice")
        tap(followers, in: app); reveal(app.buttons["privacy.save"], in: app); tap(app.buttons["privacy.save"], in: app)
        tap(app.buttons["qa.requests"], in: app); tap(app.buttons["follow.requests.legacy"], in: app)
        let approvedID = "D3200000-0000-4000-8000-000000000003", dismissedID = "D3200000-0000-4000-8000-000000000004"
        let select = app.buttons["legacy.follow.select." + approvedID]
        XCTAssertTrue(select.waitForExistence(timeout: 8)); reveal(select, in: app)
        capture(app, name: "Legacy01 preserved raw followers awaiting owner review")
        tap(select, in: app)
        let confirmations = app.alerts.buttons.matching(identifier: "legacy.follow.confirm")
        XCTAssertTrue(confirmations.firstMatch.waitForExistence(timeout: 3)); capture(app, name: "Legacy confirmation includes explicit approval and cancel"); tap(app.alerts.buttons["취소"], in: app)
        XCTAssertTrue(select.waitForExistence(timeout: 3))
        tap(select, in: app)
        // iOS26 exposes the native alert action as nested buttons with one ID.
        // Select a hittable action in the current alert, never an inactive wrapper.
        let activeApproval = NSPredicate { _, _ in confirmations.allElementsBoundByIndex.contains { $0.isHittable } }
        expectation(for: activeApproval, evaluatedWith: nil); waitForExpectations(timeout: 5)
        let approval = try XCTUnwrap(confirmations.allElementsBoundByIndex.first { $0.isHittable })
        tap(approval, in: app)
        let dismiss = app.buttons["legacy.follow.dismiss." + dismissedID]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 8)); reveal(dismiss, in: app)
        capture(app, name: "Legacy02 individual confirmed approval removes only approved candidate")
        tap(dismiss, in: app)
        XCTAssertTrue(app.staticTexts["legacy.follow.empty"].waitForExistence(timeout: 8))
        capture(app, name: "Legacy03 dismissal preserves raw graph and completes candidate review")
        app.navigationBars["기존 팔로워 확인"].buttons.element(boundBy: 0).tap()
        let accepted = app.buttons["follow.requests.remove." + approvedID]
        XCTAssertTrue(accepted.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["follow.requests.remove." + dismissedID].exists)
        capture(app, name: "Legacy04 approved follower enters existing accepted management")
        app.terminate()
    }

    func testApprovedFollowRequestsOutgoingCancelAndPrivateProfileSearch() throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"];app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:10){tap(app.buttons["reviewDemo.start"],in:app)}
        guard app.buttons["reviewDemo.privacyQA"].waitForExistence(timeout:10) else {throw XCTSkip("Debug demo required")}
        tap(app.buttons["reviewDemo.privacyQA"],in:app);tap(app.buttons["privacy.choice.public"], in: app); tap(app.buttons["privacy.workout.public"], in: app); tap(app.buttons["privacy.save"], in: app)
        tap(app.buttons["qa.requests"],in:app)
        let privateID="D3200000-0000-4000-8000-000000000001",publicID="D3200000-0000-4000-8000-000000000002"
        let approve=app.buttons["follow.requests.approve."+privateID]
        XCTAssertTrue(approve.waitForExistence(timeout:8));tap(approve,in:app)
        let remove=app.buttons["follow.requests.remove."+privateID]
        XCTAssertTrue(remove.waitForExistence(timeout:8));capture(app,name:"Follow01 private incoming approved without followback")
        tap(remove,in:app)
        let reject=app.buttons["follow.requests.reject."+publicID]
        XCTAssertTrue(reject.waitForExistence(timeout:8));tap(reject,in:app)
        XCTAssertTrue(app.staticTexts["팔로우 요청과 승인된 팔로워가 없어요."].waitForExistence(timeout:8))
        capture(app,name:"Follow02 rejection and follower removal confirmed")
        app.navigationBars.buttons.element(boundBy:0).tap()
        tap(app.buttons["qa.outgoing"],in:app)
        let action=app.buttons["profile.social.action."+privateID],pub=app.buttons["profile.social.action."+publicID]
        XCTAssertTrue(action.waitForExistence(timeout:8));XCTAssertTrue(action.label.hasSuffix("팔로우 요청"))
        tap(action,in:app)
        let pending=NSPredicate{_,_ in action.exists && action.label.hasSuffix("요청 취소")}
        expectation(for:pending,evaluatedWith:nil);waitForExpectations(timeout:8)
        capture(app,name:"Follow03 private outgoing pending grants no accepted following")
        tap(action,in:app)
        let cancelled=NSPredicate{_,_ in action.exists && action.label.hasSuffix("팔로우 요청")}
        expectation(for:cancelled,evaluatedWith:nil);waitForExpectations(timeout:8)
        tap(pub,in:app)
        let accepted=NSPredicate{_,_ in pub.exists && pub.label.hasSuffix("팔로우해제")}
        expectation(for:accepted,evaluatedWith:nil);waitForExpectations(timeout:8)
        capture(app,name:"Follow04 cancelled private request and public immediate acceptance")
        app.navigationBars.buttons.element(boundBy:0).tap()
        tap(app.buttons["qa.search"],in:app)
        let search=app.searchFields.firstMatch;XCTAssertTrue(search.waitForExistence(timeout:6));search.tap();search.typeText("private_sample")
        XCTAssertTrue(app.staticTexts["비공개 검색 샘플 00"].waitForExistence(timeout:8))
        capture(app,name:"Search01 private basic profile discoverable without workout access")
        search.typeText("\n")
        for _ in 0..<12 { if app.buttons["더 보기"].isHittable { break }; app.collectionViews.firstMatch.swipeUp() }
        let more=app.buttons["더 보기"];reveal(more,in:app);tap(more,in:app)
        let last=app.staticTexts["비공개 검색 샘플 24"];reveal(last,in:app);XCTAssertTrue(last.exists)
        capture(app,name:"Search02 private profiles keyset pagination")
        app.terminate()
    }

    func testPermissionRevocationHidesNativeRouteChartsMediaAndOpenComments() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"];app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout:10){tap(app.buttons["reviewDemo.start"],in:app)}
        guard app.buttons["reviewDemo.privacyQA"].waitForExistence(timeout:10) else {throw XCTSkip("Debug demo required")}
        tap(app.buttons["reviewDemo.privacyQA"],in:app);tap(app.buttons["privacy.choice.private"],in:app);tap(app.buttons["privacy.save"],in:app)
        tap(app.buttons["qa.revocation"],in:app)
        capture(app,name:"Diagnostic revocation detail entry")
        let diagnostic=XCTAttachment(string:app.debugDescription);diagnostic.name="Revocation detail hierarchy";diagnostic.lifetime = .keepAlways;add(diagnostic)
        XCTAssertFalse(app.buttons["댓글 보기"].exists)
        XCTAssertTrue(app.buttons["feed.post.bookmark"].exists)
        capture(app,name:"Revoke01 common native peer detail initially authorized")
        tap(app.buttons["qa.revoke"],in:app)
        XCTAssertTrue(app.staticTexts["기록을 표시할 수 없어요"].waitForExistence(timeout:12))
        let closed=NSPredicate { _,_ in !app.navigationBars["댓글"].exists && !app.staticTexts["좋은 리듬이에요! 함께 응원해요."].isHittable }
        expectation(for:closed,evaluatedWith:nil);waitForExpectations(timeout:6)
        XCTAssertFalse(app.staticTexts["좋은 리듬이에요! 함께 응원해요."].isHittable)
        XCTAssertFalse(app.staticTexts["회복 친화 라이딩"].isHittable)
        XCTAssertFalse(app.staticTexts["심박수"].isHittable)
        XCTAssertFalse(app.staticTexts["파워"].isHittable)
        XCTAssertFalse(app.buttons["댓글 보기"].isHittable)
        XCTAssertFalse(app.buttons["feed.post.bookmark"].isHittable)
        XCTAssertFalse(app.buttons["workout.detail.more"].isHittable)
        capture(app,name:"Revoke02 permission loss removes media charts and dismisses open comments")
        tap(app.buttons["다시 시도"],in:app)
        XCTAssertTrue(app.staticTexts["기록을 표시할 수 없어요"].waitForExistence(timeout:6))
        XCTAssertFalse(app.buttons["댓글 보기"].isHittable)
        app.terminate()
    }

    func testSelectedSavedRouteAndIndoorShareTemplates() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        guard app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10) else { throw XCTSkip("Disposable demo required") }
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        let running = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "DEMO ·", "공원 러닝")).firstMatch
        reveal(running, in: app); tap(running, in: app)
        func openComposer() {
            tap(app.buttons["workout.detail.more"].firstMatch, in: app)
            let action = app.buttons["이미지로 공유하기"]
            XCTAssertTrue(action.waitForExistence(timeout: 5)); tap(action, in: app)
            XCTAssertTrue(app.buttons["공유 카드 닫기"].waitForExistence(timeout: 10))
        }
        openComposer()
        let selection = app.staticTexts["share.card.selection"]
        XCTAssertTrue(selection.waitForExistence(timeout: 10))
        XCTAssertTrue(selection.label.contains("1 / 4"), "Persisted outdoor route makes the course template eligible")
        capture(app, name: "Route 01 selected saved workout actual GPS preview")
        let carousel = element("share.card.carousel", in: app)
        carousel.swipeLeft(); carousel.swipeLeft()
        let routeSelected = NSPredicate { _, _ in selection.exists && selection.label.contains("코스 카드") }
        expectation(for: routeSelected,evaluatedWith: nil); waitForExpectations(timeout: 6)
        capture(app, name: "Route 02 course uses masked saved GPS")
        tap(app.buttons["공유 카드 닫기"], in: app)
        openComposer()
        XCTAssertTrue(selection.label.contains("1 / 4"))
        capture(app, name: "Route 03 reopened selected workout keeps correct geometry")
        tap(app.buttons["공유 카드 닫기"], in: app)
        // Re-enter the workout list independently of the expanded map sheet.
        // This also verifies that a previous outdoor share cannot leak its route
        // into a newly selected indoor workout after application re-entry.
        app.terminate()
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10))
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        let swimming = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "DEMO ·", "아침 수영")).firstMatch
        reveal(swimming, in: app); tap(swimming, in: app)
        openComposer()
        XCTAssertTrue(selection.waitForExistence(timeout: 10))
        XCTAssertTrue(selection.label.contains("1 / 3"), "Indoor workout cannot offer a route template")
        capture(app, name: "Route 04 indoor metrics only without invented GPS")
        carousel.swipeLeft(); carousel.swipeLeft()
        let nonroute = NSPredicate { _, _ in selection.exists && selection.label.contains("클럽 카드") && selection.label.contains("3 / 3") }
        expectation(for: nonroute,evaluatedWith: nil); waitForExpectations(timeout: 6)
        capture(app, name: "Route 05 indoor carousel omits course template")
        tap(app.buttons["공유 카드 닫기"], in: app)
    }

    func testProfileSocialCountsPeopleAndOutgoingFollowActions() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        guard app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10) else { throw XCTSkip("Disposable demo required") }
        tap(app.buttons["soom.tab.profile"], in: app)
        let followers = element("profile.social.followers", in: app)
        reveal(followers, in: app)
        XCTAssertTrue(followers.isEnabled)
        capture(app, name: "Social 01 actual profile counts")
        tap(followers, in: app)
        XCTAssertTrue(app.navigationBars["팔로워"].waitForExistence(timeout: 10))
        let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.social.action."))
        let first = try XCTUnwrap(actions.allElementsBoundByIndex.first { $0.isHittable })
        let targetID = first.identifier
        if first.label.hasSuffix("팔로우해제") { tap(first, in: app) }
        let followBack = app.buttons[targetID]
        let incoming = NSPredicate { _, _ in followBack.exists && followBack.label.hasSuffix("팔로우") }
        expectation(for: incoming, evaluatedWith: nil); waitForExpectations(timeout: 8)
        capture(app, name: "Social 02 incoming only offers follow back")
        tap(followBack, in: app)
        let outgoing = NSPredicate { _, _ in app.buttons[targetID].exists && app.buttons[targetID].label.hasSuffix("팔로우해제") }
        expectation(for: outgoing, evaluatedWith: nil); waitForExpectations(timeout: 8)
        capture(app, name: "Social 03 outgoing relationship confirmed")
        tap(app.buttons[targetID], in: app)
        expectation(for: incoming, evaluatedWith: nil); waitForExpectations(timeout: 8)
        capture(app, name: "Social 04 unfollow preserves incoming")
        let profiles = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "프로필 열기"))
        tap(try XCTUnwrap(profiles.allElementsBoundByIndex.first { $0.isHittable }), in: app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("profile.social.followers", in: app).waitForExistence(timeout: 10))
        capture(app, name: "Social 05 people row opens profile")
        tap(app.buttons["soom.tab.feed"], in: app)
        XCTAssertTrue(app.buttons["검색"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.segmentedControls["feed.audience"].exists)
        capture(app, name: "Social 06 profile-policy unified feed restored without retired audience selector")
    }

    func testCleanInstallReviewerCanExploreMutateImportAndExitDemo() {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        defer { capture(app, name: "Final screen") }

        XCTAssertTrue(app.buttons["reviewDemo.start"].waitForExistence(timeout: 20),
                      "A fresh installation must expose Try Demo without completing onboarding.")
        XCTAssertTrue(app.buttons["soom.tab.feed"].exists, "Personal tabs remain available before optional onboarding")
        capture(app, name: "01 Clean installation optional onboarding")
        tap(app.buttons["reviewDemo.start"], in: app)
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["DEMO · 샘플 데이터"].exists)

        tap(app.buttons["soom.tab.feed"], in: app)
        reveal(element("feed.workout.article", in: app), in: app)
        XCTAssertFalse(element("feed.loadError", in: app).exists)
        capture(app, name: "02 Populated demo feed")
        tap(app.buttons["기록 저장"].firstMatch, in: app)
        XCTAssertTrue(app.buttons["저장 취소"].firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "03 Feed bookmark applied")
        tap(app.buttons["저장 취소"].firstMatch, in: app)

        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        // A current-day sample keeps the default month populated, including day one.
        // Parent accessibility identifiers propagate through SwiftUI cards.
        // The summary button retains its visible sample title.
        let sampleWorkout = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DEMO ·")).firstMatch
        reveal(sampleWorkout, in: app)
        XCTAssertFalse(element("activity.calendar.loadError", in: app).exists)
        capture(app, name: "04 Sample workout history")
        tap(sampleWorkout, in: app)
        XCTAssertTrue(app.buttons["workout.detail.more"].waitForExistence(timeout: 10))
        capture(app, name: "05 Real workout detail")
        tap(app.buttons["뒤로가기"], in: app)

        tap(app.buttons["soom.tab.clubs"], in: app)
        tap(app.buttons["SOOM Riders"].firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["SOOM Riders"].waitForExistence(timeout: 10))
        capture(app, name: "06 Sample club detail")
        tap(app.navigationBars.firstMatch.buttons.element(boundBy: 0), in: app)

        tap(app.buttons["soom.tab.profile"], in: app)
        XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["profile.login"].exists)
        capture(app, name: "07 Demo profile")

        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        tap(app.buttons["activity.manage"], in: app)
        tap(app.buttons["HealthKit 운동 가져오기"], in: app)
        tap(app.buttons["샘플 운동 가져오기 / Import Sample"], in: app)
        XCTAssertTrue(app.buttons["샘플 가져오기 완료 / Imported"].waitForExistence(timeout: 10))
        capture(app, name: "08 Local sample import completed")
        tap(app.buttons["활동에서 확인 / View Activities"], in: app)
        let imported = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "방금 가져온 샘플 러닝")).firstMatch
        reveal(imported, in: app)
        capture(app, name: "09 Imported workout visible in library")

        tap(app.buttons["reviewDemo.exit"], in: app)
        XCTAssertTrue(app.buttons["reviewDemo.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["reviewDemo.exit"].exists)
        XCTAssertFalse(app.buttons["soom.tab.feed"].exists)
        capture(app, name: "10 Exit restored onboarding")
    }

    func testWorkoutSourceAndMediaPagingSmoke() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) {
            tap(app.buttons["reviewDemo.start"], in: app)
        }
        guard app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Only the disposable demo account is eligible for this UI check")
        }
        defer { XCUIDevice.shared.orientation = .portrait }
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        let sample = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DEMO ·")).firstMatch
        tap(sample, in: app)
        capture(app, name: "Workout source - account-local provenance")
        tap(app.buttons["workout.detail.more"], in: app)
        tap(app.buttons["기록 수정"], in: app)
        let photoPicker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "사진 추가 (")).firstMatch
        XCTAssertTrue(photoPicker.waitForExistence(timeout: 5))
        let originalCount = Int(photoPicker.label.split(separator: "(").last?.split(separator: "/").first ?? "0") ?? 0
        let expectedPageCount = min(6, originalCount + 3) + 1
        let addSample = app.buttons["데모 사진 추가 / Add sample photo"]
        for _ in 0..<3 { tap(addSample, in: app) }
        tap(app.navigationBars["기록 수정"].buttons["저장"], in: app)
        XCTAssertTrue(app.buttons["workout.detail.more"].waitForExistence(timeout: 10))
        tap(app.buttons["뒤로가기"], in: app)
        // SwiftUI's ancestor card identifier can propagate to static text.
        // The adjustable accessibility value is the stable user-facing page contract.
        let indicators = app.descendants(matching: .any).matching(NSPredicate(format: "value BEGINSWITH %@", "\(expectedPageCount)페이지 중"))
        var visibleIndicator: XCUIElement?
        for _ in 0..<8 {
            visibleIndicator = indicators.allElementsBoundByIndex.first { $0.isHittable }
            if visibleIndicator != nil { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        let indicator = try XCTUnwrap(visibleIndicator, "A visible activity card must expose a current page")
        let pagers = app.descendants(matching: .any).matching(identifier: "workout.media.pager")
        let pager = try XCTUnwrap(pagers.allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.intersects(indicator.frame)
        }, "Use the visible card pager, excluding retained hidden tabs")
        XCTAssertEqual(pager.frame.height, 260, accuracy: 2)
        let initialValue = indicator.value as? String
        capture(app, name: "Workout paging - map and source badge")
        pager.swipeLeft()
        let changed = NSPredicate { _, _ in (indicator.value as? String) != initialValue }
        expectation(for: changed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        capture(app, name: "Workout paging - photo centered")
        for _ in 0..<3 { pager.swipeLeft() }
        XCTAssertTrue(indicator.exists)
        capture(app, name: "Workout paging - repeated swipes stay snapped")
        pager.swipeRight()
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        capture(app, name: "Workout paging - returned previous item")
        let valueBeforeReentry = indicator.value as? String
        tap(app.buttons["soom.tab.feed"], in: app)
        tap(app.buttons["soom.tab.activity"], in: app)
        var restored: XCUIElement?
        for _ in 0..<16 {
            restored = indicators.allElementsBoundByIndex.first { $0.isHittable }
            if restored != nil { break }
            // Small vertical drags cannot skip the 260pt target card in one step.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64)))
        }
        if restored == nil {
            capture(app, name: "Activity reentry - missing page indicator")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Activity reentry accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertEqual(try XCTUnwrap(restored).value as? String, valueBeforeReentry)
        capture(app, name: "Workout paging - tab reentry")
        tap(app.buttons["reviewDemo.exit"], in: app)
    }

    func testSharedWorkoutUsesCommonDetailWithoutPersonalAnalysisOrOwnerActions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        guard app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10) else { throw XCTSkip("Disposable demo required") }
        tap(app.buttons["soom.tab.feed"], in: app)
        let title = app.staticTexts["회복 친화 라이딩"].firstMatch
        for _ in 0..<10 {
            if title.isHittable { break }
            app.swipeUp()
        }
        tap(title, in: app)
        XCTAssertTrue(app.buttons["뒤로가기"].waitForExistence(timeout: 10) || app.navigationBars["운동 상세"].exists)
        let bookmark = app.buttons["feed.post.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["댓글 보기"].exists)
        XCTAssertTrue(app.staticTexts["회복 친화 라이딩"].exists)
        XCTAssertFalse(app.buttons["feed.post.manage"].exists)
        XCTAssertFalse(app.buttons["workout.detail.more"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout.source.evidence"].exists)
        let replay = app.buttons["workout.detail.routePlayback"]
        XCTAssertTrue(replay.waitForExistence(timeout: 5), "Owner and authorized viewer use the same masked-route motion")
        tap(replay, in: app)
        let pause = NSPredicate { _, _ in replay.label == "경로 일시정지" }
        expectation(for: pause, evaluatedWith: nil); waitForExpectations(timeout: 2)
        capture(app, name: "SharedFull masked route motion on common14 surface")
        tap(replay, in: app)
        capture(app, name: "SharedV1 native masked route and common14 heading")
        if app.buttons["상세 정보 시트"].exists { tap(app.buttons["상세 정보 시트"], in: app) }
        let measured = app.staticTexts["심박수"].firstMatch
        for _ in 0..<8 {
            XCTAssertFalse(app.staticTexts["AI 해석"].exists)
            XCTAssertFalse(app.buttons["이미지로 공유하기"].exists)
            XCTAssertFalse(app.buttons["피드에 공유하기"].exists)
            XCTAssertFalse(app.buttons["Apple 건강 경로·측정값 보완"].exists)
            XCTAssertFalse(app.buttons["여러 기기 기록 비교·대표 선택"].exists)
            if measured.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(measured.isHittable, "A measurement chart must actually be visible in the common detail")
        if measured.frame.minY > app.frame.height * 0.45 {
            app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.8)).press(forDuration:0.01,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.55)))
        }
        XCTAssertTrue(measured.isHittable)
        capture(app,name:"SharedV1 measured charts without personal analysis")
        if app.buttons["상세 정보 접기"].exists {
            let collapse = app.buttons["상세 정보 접기"]
            if collapse.isHittable { collapse.tap() }
            else {
                // The compact simulator's DEMO banner covers the glyph; use
                // the existing leading header drag target below the banner.
                let point = CGVector(dx: 30, dy: collapse.frame.maxY + 12)
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(point)
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 120)))
            }
        }
        tap(bookmark, in: app)
        let saved = NSPredicate { _, _ in (bookmark.value as? String) == "저장됨" }
        expectation(for: saved, evaluatedWith: nil); waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["댓글 보기"].exists)
        capture(app, name: "Readability peer detail without floating comment control")
        if app.buttons["뒤로가기"].exists { tap(app.buttons["뒤로가기"], in: app) }
        else { tap(app.navigationBars["운동 상세"].buttons.matching(NSPredicate(format: "label == %@", "Back")).firstMatch, in: app) }
        let exit = app.buttons.matching(identifier: "reviewDemo.exit").firstMatch
        tap(exit, in: app)
    }

    func testFeedScrollKeepsVerifiedCardsWithoutRepeatedReads() {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = uxLaunch(demo: false, environment: ["SOOM_FEED_SCROLL_READ_QA": "1"])
        defer { app.terminate() }
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10))
        tap(app.buttons["soom.tab.feed"], in: app)
        // SwiftUI propagates the feed.card parent identifier to its overlay text.
        // Match the rendered diagnostic label, then retain the actual card identifier.
        let diagnostics = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "access="))
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "R2 feed diagnostic AX"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let loaded = NSPredicate { _, _ in diagnostics.allElementsBoundByIndex.contains { $0.label.contains("visible=true") } }
        expectation(for: loaded, evaluatedWith: nil); waitForExpectations(timeout: 15)
        let first = diagnostics.allElementsBoundByIndex.first { $0.label.contains("visible=true") }!
        let id = first.identifier, counts = first.label
        capture(app, name: "Loading regression initial verified feed")
        app.swipeUp(); app.swipeUp(); app.swipeDown(); app.swipeDown()
        let original = diagnostics.matching(identifier: id).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 10))
        XCTAssertEqual(original.label, counts, "Scroll reappearance must preserve content and read counts")
        capture(app, name: "Loading regression scroll return same request counts")
        tap(app.buttons["soom.tab.profile"], in: app)
        tap(app.buttons["soom.tab.feed"], in: app)
        let returned = NSPredicate { _, _ in original.exists && original.label.contains("visible=true") }
        expectation(for: returned, evaluatedWith: nil); waitForExpectations(timeout: 15)
        func fullReads(_ label: String) -> Int {
            Int(label.split(separator: ";").first { $0.hasPrefix("full=") }?.dropFirst(5) ?? "") ?? -1
        }
        XCTAssertEqual(fullReads(original.label), fullReads(counts) + 1,
                       "One genuine return must perform one fresh full check, not old/new epoch duplicates")
        capture(app, name: "Loading regression real tab return revalidated")
        let returnedHierarchy = XCTAttachment(string: app.debugDescription); returnedHierarchy.name = "R2 return diagnostic AX"; returnedHierarchy.lifetime = .keepAlways; add(returnedHierarchy)
        XCUIDevice.shared.press(.home)
        let backgrounded = NSPredicate { _, _ in app.state == .runningBackground || app.state == .runningBackgroundSuspended }
        expectation(for: backgrounded, evaluatedWith: nil); waitForExpectations(timeout: 5)
        app.activate()
        expectation(for: returned, evaluatedWith: nil); waitForExpectations(timeout: 15)
        XCTAssertEqual(fullReads(original.label), fullReads(counts) + 2,
                       "Foreground return must add exactly one current protection check")
        capture(app, name: "R2 synthetic foreground return one fresh check")
        let title = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", id, "오늘의 성장 기록")).firstMatch
        tap(title, in: app)
        // This first synthetic post intentionally has no shared-detail consent.
        // Its guarded detail destination still pushes the real navigation stack.
        XCTAssertTrue(app.staticTexts.matching(identifier: "workout.sharedDetail.awaitingConsent").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.firstMatch.buttons["Back"].exists)
        XCTAssertFalse(original.isHittable, "Inactive feed content cannot remain interactive behind detail")
        capture(app, name: "R2 synthetic detail covers inactive feed")
        if app.buttons["뒤로가기"].exists { tap(app.buttons["뒤로가기"], in: app) }
        else { uxBack(app) }
        expectation(for: returned, evaluatedWith: nil); waitForExpectations(timeout: 15)
        XCTAssertEqual(fullReads(original.label), fullReads(counts) + 3,
                       "Detail dismissal must add exactly one current protection check")
        capture(app, name: "R2 synthetic detail back one fresh check")
        let finalHierarchy = XCTAttachment(string: app.debugDescription); finalHierarchy.name = "R2 all lifecycle diagnostic AX"; finalHierarchy.lifetime = .keepAlways; add(finalHierarchy)
    }

    func testMentionPreviewCannotRestoreManualFeedShare() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_MENTION_PREVIEW"] = "1"
        app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10))
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DEMO ·")).firstMatch, in: app)
        tap(app.buttons["workout.detail.more"], in: app)
        XCTAssertFalse(app.buttons["피드에 공유하기"].exists)
        XCTAssertFalse(app.buttons["공개 범위 변경"].exists)
        XCTAssertTrue(app.buttons["이미지로 공유하기"].exists)
        XCTAssertTrue(app.buttons["기록 수정"].exists)
        XCTAssertTrue(app.buttons["기록 삭제"].exists)
        tap(app.buttons["기록 수정"], in: app)
        XCTAssertTrue(app.navigationBars["기록 수정"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["workout.share.mentionPreview.text"].exists)
        tap(app.navigationBars["기록 수정"].buttons["취소"], in: app)
        tap(app.buttons["workout.detail.more"], in: app)
        XCTAssertFalse(app.buttons["피드에 공유하기"].exists)
        XCTAssertFalse(app.buttons["공개 범위 변경"].exists)
        capture(app, name: "Mention preview flag cannot restore manual feed share; edit cancel preserves menu")
    }

    func testImageShareRemainsWithoutManualFeedPublication() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10))
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DEMO ·")).firstMatch, in: app)
        tap(app.buttons["workout.detail.more"], in: app)
        XCTAssertFalse(app.buttons["피드에 공유하기"].exists)
        XCTAssertFalse(app.buttons["공개 범위 변경"].exists)
        tap(app.buttons["이미지로 공유하기"], in: app)
        XCTAssertTrue(app.navigationBars["공유하기"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.navigationBars["피드에 공유하기"].exists)
        XCTAssertFalse(app.buttons["workout.share.selectRepresentative"].exists)
        tap(app.buttons["공유 카드 닫기"], in: app)
        XCTAssertTrue(app.buttons["workout.detail.more"].waitForExistence(timeout: 5))
        tap(app.buttons["workout.detail.more"], in: app)
        XCTAssertFalse(app.buttons["피드에 공유하기"].exists)
        XCTAssertFalse(app.buttons["공개 범위 변경"].exists)
        XCTAssertTrue(app.buttons["이미지로 공유하기"].exists)
        XCTAssertTrue(app.buttons["기록 수정"].exists)
        XCTAssertTrue(app.buttons["기록 삭제"].exists)
        capture(app, name: "Image share close returns to record management without manual publication")
    }

    func testFeedPhotoQAOwnRoutingAndPhotoReentry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        guard app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10) else { throw XCTSkip("Disposable demo required") }
        defer { XCUIDevice.shared.orientation = .portrait }
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        let sample = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DEMO ·")).firstMatch
        tap(sample, in: app)
        tap(app.buttons["workout.detail.more"], in: app)
        tap(app.buttons["기록 수정"], in: app)
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "사진 추가 (")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let original = Int(picker.label.split(separator: "(").last?.split(separator: "/").first ?? "0") ?? 0
        let expectedCount = min(6, original + 2) + 1
        for _ in 0..<2 { tap(app.buttons["데모 사진 추가 / Add sample photo"], in: app) }
        tap(app.navigationBars["기록 수정"].buttons["저장"], in: app)
        XCTAssertTrue(app.buttons["workout.detail.more"].waitForExistence(timeout: 10))
        tap(app.buttons["뒤로가기"], in: app)
        tap(app.buttons["soom.tab.feed"], in: app)
        let summaryButtons = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", "DEMO ·", "reviewDemo.banner"))
        var ownSummary: XCUIElement?
        for _ in 0..<10 {
            ownSummary = summaryButtons.allElementsBoundByIndex.first { $0.isHittable }
            if ownSummary != nil { break }
            app.swipeUp()
        }
        capture(app, name: "Feed QA – own card before title tap")
        let ownCardMenu = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label == %@", "기록 더보기")).allElementsBoundByIndex.first { $0.isHittable }, "Own card has a profile-row management menu")
        tap(ownCardMenu, in: app)
        tap(app.buttons["기록 수정"], in: app)
        XCTAssertTrue(app.navigationBars["기록 수정"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "사진 추가 (")).firstMatch.exists)
        capture(app, name: "Own feed profile-row menu opens full record editor with photos")
        tap(app.navigationBars["기록 수정"].buttons["취소"], in: app)
        tap(try XCTUnwrap(ownSummary, "The synthetic edited workout creates only a private own post"), in: app)
        XCTAssertTrue(app.buttons["workout.detail.more"].waitForExistence(timeout: 10), "Own summary opens the existing local workout detail")
        capture(app, name: "Feed QA – own summary opens workout detail")
        tap(app.buttons["뒤로가기"], in: app)
        let indicators = app.descendants(matching: .any).matching(NSPredicate(format: "value BEGINSWITH %@", "\(expectedCount)페이지 중"))
        var indicator: XCUIElement?
        for _ in 0..<10 {
            indicator = indicators.allElementsBoundByIndex.first { $0.isHittable }
            if indicator != nil { break }
            app.swipeUp()
        }
        let visible = try XCTUnwrap(indicator)
        let pager = try XCTUnwrap(app.descendants(matching: .any).matching(identifier: "workout.media.pager")
            .allElementsBoundByIndex.first { $0.isHittable && $0.frame.intersects(visible.frame) })
        XCTAssertEqual(pager.frame.height, 260, accuracy: 2)
        XCTAssertEqual(visible.value as? String, "\(expectedCount)페이지 중 1페이지")
        capture(app, name: "Feed QA – first map page aligned")
        pager.swipeLeft()
        let second = NSPredicate { _, _ in (visible.value as? String) == "\(expectedCount)페이지 중 2페이지" }
        expectation(for: second, evaluatedWith: nil); waitForExpectations(timeout: 5)
        capture(app, name: "Feed QA – photo page aligned after load")
        let photo = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label == %@", "운동 사진 크게 보기")).allElementsBoundByIndex.first { $0.isHittable })
        tap(photo, in: app)
        XCTAssertTrue(app.buttons["workout.photo.close"].waitForExistence(timeout: 5), "Photo taps retain the gallery behavior")
        capture(app, name: "Feed QA – photo tap opens gallery")
        tap(app.buttons["workout.photo.close"], in: app)
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["soom.tab.feed"], in: app)
        var restored: XCUIElement?
        for _ in 0..<10 {
            restored = indicators.allElementsBoundByIndex.first { $0.isHittable }
            if restored != nil { break }
            app.swipeUp()
        }
        XCTAssertEqual(try XCTUnwrap(restored).value as? String, "\(expectedCount)페이지 중 2페이지")
        capture(app, name: "Feed QA – feed reentry retains selected photo")
        let exit = try XCTUnwrap(app.buttons.matching(identifier: "reviewDemo.exit").allElementsBoundByIndex.first { $0.isHittable })
        tap(exit, in: app)
    }

    func testShareImageFirstPresentationContainsNativeActivities() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        guard app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10) else { throw XCTSkip("Disposable demo required") }
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        let sample = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DEMO ·")).firstMatch
        tap(sample, in: app)
        tap(app.buttons["workout.detail.more"], in: app)
        let imageShare = app.buttons["이미지로 공유하기"]
        capture(app, name: "Share reply - image action")
        tap(imageShare, in: app)
        XCTAssertTrue(app.buttons["공유 카드 닫기"].waitForExistence(timeout: 10))
        capture(app, name: "Share reply - composer preview")
        tap(app.buttons["More"], in: app)
        let activities = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["복사", "이미지 저장", "Copy", "Save Image"]))
        let ready = NSPredicate { _, _ in activities.allElementsBoundByIndex.contains { $0.isHittable } }
        expectation(for: ready, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        let nativeReady = activities.allElementsBoundByIndex.contains { $0.isHittable }
        capture(app, name: "Share reply - first native sheet after preparation")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Share reply first presentation accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertTrue(nativeReady,
            "First share presentation must contain a rendered image and native activities")
        // Inspect only: never select a recipient, copy, save, or launch another app.
        let close = try XCTUnwrap(app.buttons.matching(identifier: "header.closeButton").allElementsBoundByIndex.first { $0.isHittable })
        close.tap()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        capture(app, name: "Share reply - native dismissal returns to composer")
        tap(app.buttons["More"], in: app)
        expectation(for: ready, evaluatedWith: nil); waitForExpectations(timeout: 10)
        capture(app, name: "Share reply - second presentation ready")
    }

    func testFeedbackPrivacyActualSheetCompletesAfterConfirmedSave() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launch()
        enterSyntheticDemo(app)
        tap(app.buttons["reviewDemo.privacyQA"], in: app)
        tap(app.buttons["privacy.choice.public"], in: app)
        tap(app.buttons["privacy.workout.followers"], in: app)
        tap(app.buttons["privacy.save"], in: app)
        XCTAssertTrue(app.staticTexts["qa.privacy.saved"].waitForExistence(timeout: 8))
        tap(app.buttons["qa.localAccess"], in: app)
        XCTAssertTrue(app.buttons["gate.unselected"].waitForExistence(timeout: 8))
        tap(app.buttons["gate.unselected"], in: app)
        tap(app.buttons["gate.failNextSave"], in: app)
        selectGateTab("soom.tab.feed", in: app)
        tap(app.buttons["social.lock.settings"], in: app)
        let save = app.buttons["privacy.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        tap(app.buttons["privacy.choice.public"], in: app)
        tap(app.buttons["privacy.workout.followers"], in: app)
        reveal(save, in: app)
        tap(save, in: app)
        let failure = app.staticTexts["저장을 확인하지 못했어요. 공개범위를 다시 불러온 뒤 선택해 주세요."]
        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        XCTAssertTrue(save.exists)
        capture(app, name: "Feedback privacy - failed save retains actual sheet")
        tap(app.buttons["공개범위 다시 불러오기"], in: app)
        tap(app.buttons["privacy.choice.public"], in: app)
        tap(app.buttons["privacy.workout.followers"], in: app)
        reveal(save, in: app)
        tap(save, in: app)
        let closed = NSPredicate { _, _ in !save.exists }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: closed, object: nil)], timeout: 8)
        capture(app, name: "Feedback privacy - actual sheet after successful save")
        XCTAssertEqual(result, .completed, "A confirmed explicit completion must return from the actual settings sheet")
        app.terminate()
    }

    func testFeedbackStartInstructionAndRadialRecording() throws {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launch()
        enterSyntheticDemo(app)
        selectGateTab("soom.tab.record", in: app)
        let launch = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "운동 시작,"))
            .allElementsBoundByIndex.last { $0.isHittable })
        let instruction = app.staticTexts["record.startInstruction"]
        XCTAssertTrue(instruction.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(instruction.frame.width, 0)
        XCTAssertTrue(app.frame.contains(instruction.frame))
        capture(app, name: "Feedback start - visible radial instruction")
        let circle = launch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        circle.tap()
        XCTAssertTrue(launch.exists)
        XCTAssertFalse(app.staticTexts["coach.caption"].isHittable)
        circle.press(forDuration: 0.2, thenDragTo: circle.withOffset(CGVector(dx: 0, dy: -174)))
        XCTAssertTrue(app.staticTexts["coach.caption"].waitForExistence(timeout: 10))
        capture(app, name: "Feedback start - selected running session active")
        tap(app.buttons["일시정지"], in: app)
        tap(app.buttons["종료"], in: app)
        tap(app.buttons["운동 종료"], in: app)
        XCTAssertTrue(app.staticTexts["기록 종료"].waitForExistence(timeout: 6))
        app.terminate()
    }

    func testV5LocalCoachRecordingLifecycleInDemo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        guard app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10) else { throw XCTSkip("Disposable demo required") }
        tap(app.buttons["soom.tab.record"], in: app)
        XCTAssertTrue(app.buttons["coach.readySettings"].waitForExistence(timeout: 10))
        capture(app, name: "V5 Ready and R11 preserved")
        tap(app.buttons["coach.readySettings"], in: app)
        XCTAssertTrue(app.switches["coach.enableSetting"].waitForExistence(timeout: 5))
        capture(app, name: "V5 Voice beta settings and AI disconnected")
        tap(app.buttons["완료"], in: app)
        let launch = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "운동 시작,")).firstMatch
        reveal(launch, in: app)
        // Preserve R11: hold the actual circle then drag 174pt upward to select running.
        // Its accessibility frame now follows the actual 88pt start circle.
        let circle = launch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        circle.press(forDuration: 0.2, thenDragTo: circle.withOffset(CGVector(dx: 0, dy: -174)))
        XCTAssertTrue(app.staticTexts["coach.caption"].waitForExistence(timeout: 10))
        capture(app, name: "V5 Active compact metrics")
        tap(app.buttons["일시정지"], in: app)
        XCTAssertTrue(app.staticTexts["coach.aiUnavailable"].waitForExistence(timeout: 5))
        capture(app, name: "V5 Paused local coach available")
        tap(app.buttons["coach.localPhrase"], in: app)
        XCTAssertEqual(app.staticTexts["coach.caption"].label, "잠시 숨을 고르고 편하게 이어가요.")
        tap(app.buttons["다시 시작"], in: app)
        XCTAssertFalse(app.staticTexts["coach.aiUnavailable"].exists)
        tap(app.buttons["일시정지"], in: app)
        tap(app.buttons["종료"], in: app)
        XCTAssertTrue(app.buttons["계속 쉬기"].waitForExistence(timeout: 5))
        capture(app, name: "V5 Finish requires confirmation")
        tap(app.buttons["운동 종료"], in: app)
        XCTAssertTrue(app.staticTexts["기록 종료"].waitForExistence(timeout: 5))
        capture(app, name: "V5 Finished remains unsaved")
        // Full-screen recording retains the underlying demo banner in accessibility.
        // Select the visible banner rather than the hidden first match.
        let visibleExit = try XCTUnwrap(app.buttons.matching(identifier: "reviewDemo.exit")
            .allElementsBoundByIndex.first { $0.isHittable }, "A visible demo exit must remain available")
        visibleExit.tap()
        XCTAssertTrue(app.buttons["reviewDemo.start"].waitForExistence(timeout: 10))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func enterSyntheticDemo(_ app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let exit = app.buttons["reviewDemo.exit"]
        if exit.exists { return }
        let start = app.buttons["reviewDemo.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), file: file, line: line)
        // The first root-layout transition can supersede a synthesized tap.
        // Retry only while the same idle opt-in demo button is still present;
        // the product's start() is idempotent and no real session is replaced.
        for _ in 0..<2 {
            tap(start, in: app, file: file, line: line)
            if exit.waitForExistence(timeout: 5) { return }
            if !start.exists { break }
        }
        capture(app, name: "Demo entry did not complete")
        XCTAssertTrue(exit.exists, "Synthetic demo entry must complete before QA", file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<24 {
            let exists = element.exists
            if exists && element.isHittable { return }
            // Lazy stacks may not create an off-screen card at accessibility sizes.
            // Querying its frame before existence aborts instead of scrolling.
            let upwards = !exists || element.frame.minY >= 195
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: upwards ? 0.72 : 0.44)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: upwards ? 0.44 : 0.72)))
        }
        capture(app, name: "Missing or obscured interactive element")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Accessibility hierarchy at failed interaction"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(element.exists && element.isHittable,
                      "Expected a visible interactive element", file: file, line: line)
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication,
                     file: StaticString = #filePath, line: UInt = #line) {
        reveal(element, in: app, file: file, line: line)
        element.tap()
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension ReviewDemoUITests {
    func testFeedAuthorFollowEntryAndProfileListSearchNavigation() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]; app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        guard app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10) else { throw XCTSkip("Disposable demo required") }
        tap(app.buttons["soom.tab.feed"], in: app)
        let entries = app.buttons.matching(NSPredicate(format: "value IN %@", ["팔로우", "팔로잉", "요청됨", "팔로우 요청"]))
        for _ in 0..<10 {
            if entries.allElementsBoundByIndex.contains(where: { $0.isHittable }) { break }
            app.swipeUp()
        }
        guard let entry = entries.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            capture(app, name: "Missing synthetic feed author follow entry")
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "Feed author follow hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            XCTFail("Peer feed author follow entry must be visible"); return
        }
        let suffix = try XCTUnwrap(entry.label.range(of: " 팔로", options: .backwards))
        let authorPrefix = String(entry.label[..<suffix.lowerBound]) + " "
        let current = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND value IN %@", authorPrefix, ["팔로우", "팔로잉", "요청됨", "팔로우 요청"])).firstMatch
        if (current.value as? String) == "팔로잉" { tap(current, in: app) }
        tap(current, in: app)
        let follows = NSPredicate { _, _ in (current.value as? String) == "팔로잉" }
        expectation(for: follows, evaluatedWith: nil); waitForExpectations(timeout: 10)
        for _ in 0..<10 {
            if current.exists && current.isHittable && current.frame.minY > 120 && current.frame.maxY < app.frame.maxY - 100 { break }
            app.swipeUp()
        }
        XCTAssertTrue(current.isHittable && current.frame.maxY < app.frame.maxY - 100)
        capture(app, name: "SocialParity01 feed author relation entry confirmed")
        tap(app.buttons["soom.tab.profile"], in: app)
        let posts = element("profile.social.posts", in: app); reveal(posts, in: app); XCTAssertTrue(posts.isEnabled); tap(posts, in: app)
        XCTAssertTrue(app.buttons["profile.tab.activities"].isSelected)
        let followers = element("profile.social.followers", in: app); reveal(followers, in: app); tap(followers, in: app)
        XCTAssertTrue(app.navigationBars["팔로워"].waitForExistence(timeout: 8))
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("never_matches_synthetic_user")
        XCTAssertTrue(app.staticTexts["검색 결과가 없어요"].waitForExistence(timeout: 8))
        capture(app, name: "SocialParity02 authorized people list search empty result")
        search.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.social.action.")).firstMatch.waitForExistence(timeout: 8))
        capture(app, name: "SocialParity03 search clear restores authorized rows and relationship actions")
        app.terminate()
    }
}


extension ReviewDemoUITests {
    func testPendingSocialVerificationShowsNeutralStatusAndThenFreshFeed() throws {
        continueAfterFailure = false; executionTimeAllowance = 120
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]; app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        guard app.buttons["reviewDemo.privacyQA"].waitForExistence(timeout: 10) else { throw XCTSkip("Disposable demo required") }
        tap(app.buttons["reviewDemo.privacyQA"], in: app)
        tap(app.buttons["privacy.choice.public"], in: app); tap(app.buttons["privacy.workout.public"], in: app); tap(app.buttons["privacy.save"], in: app)
        tap(app.buttons["qa.localAccess"], in: app)
        selectGateTab("soom.tab.feed", in: app)
        XCTAssertTrue(app.segmentedControls["feed.audience"].waitForExistence(timeout: 10))
        tap(app.buttons["gate.verifyDelayed"], in: app)
        XCTAssertTrue(app.staticTexts["공개범위를 확인하는 중"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.staticTexts["소셜 기능을 잠갔어요"].exists)
        capture(app, name: "SocialLoading01 pending server verification neutral status without lock wording")
        XCTAssertTrue(app.segmentedControls["feed.audience"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["소셜 기능을 잠갔어요"].exists)
        capture(app, name: "SocialLoading02 fresh feed after verified receipt")
        tap(app.buttons["gate.failure"], in: app)
        XCTAssertTrue(app.staticTexts["소셜 기능을 잠갔어요"].waitForExistence(timeout: 8))
        capture(app, name: "SocialLoading03 actual failed verification still restricted")
        app.terminate()
    }
}

extension ReviewDemoUITests {
    func testFollowMutationRefreshesOwnCountsAndPreservesInboundFollowerCount() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]; app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        guard app.buttons["reviewDemo.exit"].waitForExistence(timeout: 10) else { throw XCTSkip("Disposable demo required") }
        tap(app.buttons["soom.tab.profile"], in: app)
        func count(_ name: String) -> Int? {
            app.descendants(matching: .any).matching(identifier: "profile.social." + name).allElementsBoundByIndex.compactMap { Int($0.value as? String ?? "") }.first
        }
        let loaded = NSPredicate { _, _ in count("following") != nil && count("followers") != nil }
        expectation(for: loaded, evaluatedWith: nil); waitForExpectations(timeout: 10)
        let followingBefore = try XCTUnwrap(count("following")), followersBefore = try XCTUnwrap(count("followers"))
        tap(element("profile.social.followers", in: app), in: app)
        XCTAssertTrue(app.navigationBars["팔로워"].waitForExistence(timeout: 8))
        let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.social.action."))
        let action = try XCTUnwrap(actions.allElementsBoundByIndex.first { $0.isHittable })
        let targetID = action.identifier, wasFollowing = action.label.hasSuffix("팔로우해제")
        tap(action, in: app)
        let changed = NSPredicate { _, _ in app.buttons[targetID].exists && app.buttons[targetID].label.hasSuffix(wasFollowing ? "팔로우" : "팔로우해제") }
        expectation(for: changed, evaluatedWith: nil); waitForExpectations(timeout: 8)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let refreshed = NSPredicate { _, _ in count("following") == followingBefore + (wasFollowing ? -1 : 1) && count("followers") == followersBefore }
        expectation(for: refreshed, evaluatedWith: nil); waitForExpectations(timeout: 10)
        capture(app, name: "SocialCounts01 outgoing mutation refreshes own following count and preserves inbound count")
        tap(element("profile.social.followers", in: app), in: app)
        tap(app.buttons[targetID], in: app)
        let restored = NSPredicate { _, _ in app.buttons[targetID].exists && app.buttons[targetID].label.hasSuffix(wasFollowing ? "팔로우해제" : "팔로우") }
        expectation(for: restored, evaluatedWith: nil); waitForExpectations(timeout: 8)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let original = NSPredicate { _, _ in count("following") == followingBefore && count("followers") == followersBefore }
        expectation(for: original, evaluatedWith: nil); waitForExpectations(timeout: 10)
        capture(app, name: "SocialCounts02 synthetic outgoing restoration returns original counts")
        app.terminate()
    }
}

extension ReviewDemoUITests {
    private func uxLaunch(demo: Bool = true, environment: [String: String] = [:]) -> XCUIApplication {
        continueAfterFailure = false; executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        if environment["SOOM_PROJECTION_LARGE_QA"] == "1" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launch()
        if demo {
            XCTAssertTrue(app.buttons["reviewDemo.start"].waitForExistence(timeout: 15))
            uxTap(app.buttons["reviewDemo.start"], in: app)
            XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 15))
        }
        return app
    }
    private func uxViewport(_ app: XCUIApplication) -> CGRect {
        let scroll = app.scrollViews.allElementsBoundByIndex.first { $0.isHittable }
        var rect = scroll?.frame ?? app.frame.insetBy(dx: 0, dy: 50)
        let bars = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "soom.tab.")).allElementsBoundByIndex.filter { $0.isHittable }
        if let top = bars.map(\.frame.minY).min() { rect.size.height = max(0, min(rect.maxY, top - 8) - rect.minY) }
        return rect.intersection(app.frame)
    }
    private func uxReveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<30 {
            let viewport = uxViewport(app)
            if target.exists && target.isHittable {
                let visible = target.frame.intersection(viewport)
                if target.elementType == .switch {
                    if viewport.contains(CGPoint(x: target.frame.maxX - 22, y: target.frame.midY)) { return }
                } else if !visible.isNull && visible.height >= min(44, target.frame.height) { return }
            }
            let down = target.exists && target.frame.height > 0 && target.frame.midY < viewport.midY
            let point = CGVector(dx: viewport.midX, dy: viewport.midY)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(point)
            start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: down ? 100 : -100)))
        }
        XCTAssertTrue(target.exists)
    }
    private func uxTap(_ target: XCUIElement, in app: XCUIApplication) {
        if !target.exists { uxReveal(target, in: app) }
        if target.identifier.hasPrefix("soom.tab.") { selectGateTab(target.identifier, in: app); return }
        if !target.isHittable || target.elementType == .switch { uxReveal(target, in: app) }
        let visible = target.frame.intersection(uxViewport(app))
        if target.elementType == .switch && target.isHittable {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.frame.maxX - 22, dy: target.frame.midY)).tap()
            return
        }
        if target.isHittable && !visible.isNull && visible.width > 0 && visible.height > 0 {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
        } else { tap(target, in: app) }
    }
    private func uxBack(_ app: XCUIApplication) {
        let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5)); uxTap(back, in: app)
    }
    func testUXSharedPostsDestinationMatchesCountAndPreservesPersonalLibrary() throws {
        let app = uxLaunch(); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app)
        let posts = element("profile.social.posts", in: app)
        XCTAssertTrue(posts.waitForExistence(timeout: 10))
        let counts = NSPredicate { _, _ in Int(posts.value as? String ?? "") != nil }
        expectation(for: counts, evaluatedWith: nil); waitForExpectations(timeout: 10)
        let count = try XCTUnwrap(Int(posts.value as? String ?? ""))
        uxTap(posts, in: app)
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.sharedPost.")).count, count)
        XCTAssertFalse(app.staticTexts["AI 코치"].exists)
        capture(app, name: "UX F03 own shared posts match summary and show visibility")
        uxBack(app)
        uxTap(app.buttons["profile.tab.activities"], in: app)
        XCTAssertTrue(app.staticTexts["내 운동"].firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "UX F03 local personal workout library remains separate")
    }
    func testGestaltProfileSettingsGroupsBackAndSelectedSectionSurvive() {
        let app=uxLaunch();defer{app.terminate()}
        uxTap(app.buttons["soom.tab.profile"],in:app)
        XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["profile.social.posts"].exists)
        capture(app,name:"AFTER SYNTHETIC profile grouped identity and weekly activity")
        uxTap(app.buttons["profile.tab.activities"],in:app)
        XCTAssertTrue(app.buttons["profile.tab.activities"].isSelected)
        uxTap(app.buttons["profile.settings"],in:app)
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["settings.account"].exists);XCTAssertTrue(app.buttons["settings.integrations"].exists)
        capture(app,name:"AFTER SYNTHETIC settings account device and preferences groups")
        uxReveal(app.buttons["settings.support"],in:app)
        XCTAssertTrue(app.buttons["settings.privacy"].exists);XCTAssertTrue(app.buttons["settings.support"].isHittable)
        capture(app,name:"AFTER SYNTHETIC settings privacy support remain reachable")
        uxBack(app)
        XCTAssertTrue(app.buttons["profile.settings"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["profile.tab.activities"].isSelected)
        uxTap(app.buttons["profile.tab.progress"],in:app)
        XCTAssertTrue(app.staticTexts["주간 활동"].waitForExistence(timeout:5))
        capture(app,name:"AFTER SYNTHETIC back preserves profile section and weekly chart")
    }

    func testGestaltReducedMotionRetainsRangeAfterDragCancelAndReentry() throws {
        let app=detailFixtureApp(gesture:true);defer{app.terminate()}
        selectEffortFixture("자동 점수 범위",in:app)
        tap(app.switches["모션 줄이기"],in:app);openEffort(in:app)
        try assertEffortGestureOwnsParent(in:app,hasRange:true,name:"AFTER reduced motion persistent reference")
        tap(app.buttons["effort.cancel"],in:app);openEffort(in:app)
        let slider=app.descendants(matching:.any)["effort.slider"].firstMatch
        XCTAssertTrue((slider.value as? String ?? "").contains("접힘"))
        XCTAssertTrue((slider.value as? String ?? "").contains("빗금 숨김"))
        tap(app.buttons["effort.expansion"],in:app)
        XCTAssertTrue((slider.value as? String ?? "").contains("빗금 표시"))
        capture(app,name:"AFTER SYNTHETIC reduced motion reopen visible true comparison")
    }

    func testUXSettingsConnectionEntryAndThreeTabRoundTrips() {
        let app = uxLaunch(); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app)
        uxTap(app.buttons["profile.settings"], in: app)
        XCTAssertTrue(app.buttons["settings.integrations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.integrations"].isHittable)
        capture(app, name: "UX F04 device entry at settings top")
        uxTap(app.buttons["settings.integrations"], in: app)
        uxTap(app.buttons["integrations.appleHealth"], in: app)
        let providerTitle = app.navigationBars.firstMatch.identifier
        for index in 1...3 {
            uxTap(app.buttons["soom.tab.clubs"], in: app)
            uxTap(app.buttons["soom.tab.profile"], in: app)
            XCTAssertEqual(app.navigationBars.firstMatch.identifier, providerTitle)
            capture(app, name: "UX F08 retained provider detail round trip \(index)")
        }
    }
    func testUXClubDirectoryFailureRetryAndHonestManagement() {
        let app = uxLaunch(environment: ["SOOM_UX_CLUB_STATE": "directory"]); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.clubs"], in: app)
        XCTAssertTrue(element("clubs.loading", in: app).waitForExistence(timeout: 3))
        capture(app, name: "UX F02 directory loading is distinct from empty state")
        XCTAssertTrue(app.buttons["clubs.retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["클럽은 선택한 그룹 안에서만 랭킹과 뱃지가 쌓입니다."].exists, "Failure must not show the normal empty-directory guide")
        capture(app, name: "UX F02 club directory failure and retry")
        uxTap(app.buttons["clubs.retry"], in: app)
        let owned = app.buttons["Recovery Crew"].firstMatch; uxReveal(owned, in: app); uxTap(owned, in: app)
        let manage = app.buttons["관리 준비 중"]; uxReveal(manage, in: app); uxTap(manage, in: app)
        XCTAssertTrue(app.staticTexts["클럽 관리는 곧 더 자세히 연결될 예정이에요."].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["승인"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["clubs.sheet.close"].frame.width, 44)
        capture(app, name: "UX F06 management explicitly not yet available")
        uxTap(app.buttons["clubs.sheet.close"], in: app)
        XCTAssertTrue(app.navigationBars["Recovery Crew"].exists)
    }
    func testUXClubLeaveFailureKeepsSheetAndAllowsRetry() {
        let app = uxLaunch(environment: ["SOOM_UX_CLUB_STATE": "membership"]); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.clubs"], in: app)
        let club = app.buttons["SOOM Riders"].firstMatch
        XCTAssertTrue(club.waitForExistence(timeout: 10)); uxTap(club, in: app)
        let membership = app.buttons["가입됨"]; uxReveal(membership, in: app); uxTap(membership, in: app)
        let leave = app.buttons["클럽 나가기"]; uxReveal(leave, in: app); uxTap(leave, in: app)
        XCTAssertTrue(app.staticTexts["clubs.membership.error"].waitForExistence(timeout: 10))
        XCTAssertTrue(leave.exists)
        capture(app, name: "UX F02 failed leave preserves membership sheet and retry")
        uxTap(leave, in: app)
        XCTAssertTrue(app.buttons["가입하기"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["클럽 나가기"].exists)
        capture(app, name: "UX F02 confirmed leave dismisses sheet after completion")
    }
    func testUXGalleryFailureRetryAndRangeAreVisible() {
        let app = uxLaunch(environment: ["SOOM_UX_GALLERY_STATE": "failure"]); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app)
        uxTap(app.buttons["profile.tab.gallery"], in: app)
        XCTAssertTrue(element("profile.gallery.loading", in: app).waitForExistence(timeout: 3))
        capture(app, name: "UX F10 gallery loading is distinct from empty and failure")
        let retry = app.buttons["profile.gallery.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        uxReveal(retry, in: app)
        XCTAssertFalse(app.staticTexts["운동에 추가한 사진이 여기에 표시돼요."].exists)
        capture(app, name: "UX F10 gallery failure is not empty state")
        uxTap(retry, in: app)
        let absent = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: retry)
        wait(for: [absent], timeout: 15)
        capture(app, name: "UX F10 gallery retry completes and query range is explicit")
    }
    func testUXGuestLoginCancellationAndPrivacyExplanation() throws {
        let app = uxLaunch(demo: false); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.clubs"], in: app)
        XCTAssertTrue(app.buttons.matching(identifier: "social.login").firstMatch.waitForExistence(timeout: 8))
        let login = app.buttons.matching(identifier: "social.login")
            .matching(NSPredicate(format: "label CONTAINS %@", "클럽")).firstMatch
        uxReveal(login, in: app); XCTAssertTrue(login.isHittable)
        uxTap(login, in: app)
        XCTAssertTrue(app.buttons["취소"].waitForExistence(timeout: 8)); uxTap(app.buttons["취소"], in: app)
        XCTAssertTrue(login.waitForExistence(timeout: 8))
        capture(app, name: "UX F07 club login cancel returns to original purpose")
        uxTap(app.buttons["soom.tab.profile"], in: app); uxTap(app.buttons["profile.settings"], in: app)
        uxTap(app.buttons["settings.privacy"], in: app)
        let sharing = app.staticTexts["운동 상세에 포함되는 정보"]; uxReveal(sharing, in: app)
        XCTAssertTrue(sharing.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "피드 게시물에는 경로, 심박, 체크인 메모를 전송하지")).firstMatch.exists)
        capture(app, name: "UX F01 selected audience consent masking and owner-only analytics explanation")
    }
    func testUXGoogleStatusFailureRetryAndOAuthCancelPresentation() {
        let app = uxLaunch(demo: false, environment: ["SOOM_UX_GOOGLE_STATE": "failed"]); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app); uxTap(app.buttons["profile.settings"], in: app)
        uxTap(app.buttons["settings.integrations"], in: app); uxTap(app.buttons["integrations.googleHealth"], in: app)
        let open = app.buttons["Google 계정 연결 및 가져오기"]; uxReveal(open, in: app); uxTap(open, in: app)
        let retry = app.buttons["google.connection.retry"]; uxReveal(retry, in: app)
        XCTAssertTrue(retry.waitForExistence(timeout: 10)); capture(app, name: "UX F05 synthetic status failure has retry")
        uxTap(retry, in: app)
        XCTAssertTrue(app.staticTexts["연결 가능"].waitForExistence(timeout: 8))
        let consent = app.switches["이 내용을 확인하고 Google 계정 연결에 동의합니다"]; uxReveal(consent, in: app)
        if consent.value as? String != "1" { uxTap(consent, in: app) }
        XCTAssertEqual(consent.value as? String, "1")
        let connect = app.buttons["Google 계정 연결"]; uxReveal(connect, in: app)
        XCTAssertTrue(connect.isEnabled); uxTap(connect, in: app)
        XCTAssertTrue(app.staticTexts["연결을 취소했어요. 원할 때 다시 연결할 수 있어요."].waitForExistence(timeout: 8))
        capture(app, name: "UX F05 synthetic OAuth cancel keeps recoverable state without external requests")
    }
}

extension ReviewDemoUITests {
    func testUXAccessibilityWeekSelectionAndProviderNamesRemainUsable() {
        let app = uxLaunch(); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app)
        let previous = app.buttons["profile.week.previous"]; uxReveal(previous, in: app)
        XCTAssertTrue(previous.isHittable)
        XCTAssertGreaterThanOrEqual(previous.frame.width, 44)
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44)
        let current = app.staticTexts["profile.week.title"].label
        uxTap(previous, in: app)
        XCTAssertNotEqual(app.staticTexts["profile.week.title"].label, current)
        uxTap(app.buttons["profile.week.next"], in: app)
        XCTAssertEqual(app.staticTexts["profile.week.title"].label, current)
        capture(app, name: "UX F09 accessible week selection buttons and full selected week")
        let settings = app.buttons["profile.settings"]; uxReveal(settings, in: app); uxTap(settings, in: app)
        let integrations = app.buttons["settings.integrations"]; uxReveal(integrations, in: app); uxTap(integrations, in: app)
        let google = app.buttons["integrations.googleHealth"]; uxReveal(google, in: app)
        XCTAssertTrue(google.isHittable)
        XCTAssertTrue(google.label.contains("Google Health"))
        XCTAssertGreaterThanOrEqual(google.frame.height, 44)
        XCTAssertLessThanOrEqual(google.frame.maxX, app.frame.maxX)
        capture(app, name: "UX F09 provider names and adaptive service grid")
    }
}

extension ReviewDemoUITests {
    func testUXEmptyClubDirectoryHasAnExplicitEmptyGuide() {
        let app = uxLaunch(environment: ["SOOM_UX_CLUB_STATE": "empty"]); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.clubs"], in: app)
        XCTAssertTrue(app.staticTexts["클럽은 선택한 그룹 안에서만 랭킹과 뱃지가 쌓입니다."].waitForExistence(timeout: 8))
        XCTAssertFalse(element("clubs.error", in: app).exists)
        XCTAssertFalse(element("clubs.loading", in: app).exists)
        capture(app, name: "UX F02 successful empty directory differs from loading and failure")
    }
    func testUXGoogleGuestLoginCancelReturnsToConnection() {
        let app = uxLaunch(demo: false); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app); uxTap(app.buttons["profile.settings"], in: app)
        uxTap(app.buttons["settings.integrations"], in: app); uxTap(app.buttons["integrations.googleHealth"], in: app)
        let open = app.buttons["Google 계정 연결 및 가져오기"]; uxReveal(open, in: app); uxTap(open, in: app)
        let login = app.buttons["google.connection.login"]; uxReveal(login, in: app)
        XCTAssertTrue(login.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["서버 설정 전"].exists)
        capture(app, name: "UX F05 guest connection explicitly requires login without server claim")
        uxTap(login, in: app)
        XCTAssertTrue(app.buttons["취소"].waitForExistence(timeout: 8)); uxTap(app.buttons["취소"], in: app)
        XCTAssertTrue(login.waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["Google Health"].exists)
        capture(app, name: "UX F07 Google login cancellation returns to connection purpose")
    }
}

extension ReviewDemoUITests {
    private func uxAssertOwnedPostScope(_ expected: Int) throws {
        let app = uxLaunch(environment: ["SOOM_UX_POST_COUNT": String(expected)]); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app)
        let posts = element("profile.social.posts", in: app)
        let countReady = NSPredicate { _, _ in Int(posts.value as? String ?? "") == expected }
        expectation(for: countReady, evaluatedWith: nil); waitForExpectations(timeout: 10)
        uxTap(posts, in: app)
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].waitForExistence(timeout: 8))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.sharedPost."))
        if expected == 0 {
            XCTAssertTrue(app.staticTexts["접근 가능한 운동이 아직 없어요."].waitForExistence(timeout: 8))
            XCTAssertEqual(cards.count, 0)
        } else {
            expectation(for: NSPredicate { _, _ in cards.count == 8 }, evaluatedWith: nil); waitForExpectations(timeout: 8)
            let more = app.buttons["운동 더 보기"]; uxReveal(more, in: app); uxTap(more, in: app)
            expectation(for: NSPredicate { _, _ in cards.count == expected }, evaluatedWith: nil); waitForExpectations(timeout: 8)
            XCTAssertFalse(more.exists)
        }
        capture(app, name: "UX F03 shared post scope count \(expected) with local private workouts preserved")
    }
    func testUXSharedPostCountZeroDoesNotShowPrivateLocalWorkouts() throws { try uxAssertOwnedPostScope(0) }
    func testUXSharedPostCountMultiplePagesMatchesNineAuthorizedPosts() throws { try uxAssertOwnedPostScope(9) }
}

extension ReviewDemoUITests {
    func testUXLocalGuestStillReceivesClubLoginAction() throws {
        let app = uxLaunch(demo: false); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.clubs"], in: app)
        XCTAssertTrue(app.buttons.matching(identifier: "social.login").firstMatch.waitForExistence(timeout: 8))
        let entry = try XCTUnwrap(app.buttons.matching(identifier: "social.login").allElementsBoundByIndex.first { $0.isHittable })
        uxTap(entry, in: app)
        let local = app.buttons["로그인 없이 계속하기"]
        let continuedLocally = local.waitForExistence(timeout: 3)
        if continuedLocally { uxReveal(local, in: app); uxTap(local, in: app) }
        else { uxTap(app.buttons["취소"], in: app) }
        let returned = NSPredicate { _, _ in app.buttons["soom.tab.clubs"].isSelected }
        expectation(for: returned, evaluatedWith: nil); waitForExpectations(timeout: 12)
        let login = app.buttons.matching(identifier: "social.login")
        XCTAssertTrue(login.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(login.allElementsBoundByIndex.contains { $0.isHittable && $0.label.contains("클럽") })
        XCTAssertFalse(app.buttons["클럽 나가기"].isHittable)
        capture(app, name: "UX F07 local guest purpose and login CTA, continued locally \(continuedLocally)")
    }
}

extension ReviewDemoUITests {
    func testNotificationUpgradeStatusRetryAndPermissionAreDistinct() throws {
        continueAfterFailure=false;executionTimeAllowance=120
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"];app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launchEnvironment["SOOM_NOTIFICATION_QA"]="1";app.launch()
        tap(app.buttons["reviewDemo.start"],in:app);tap(app.buttons["reviewDemo.notificationQA"],in:app);tap(app.buttons["notificationQA.registration"],in:app)
        XCTAssertTrue(app.staticTexts["push.registration.status"].waitForExistence(timeout:6));XCTAssertTrue(app.staticTexts["push.registration.status"].label.contains("저장하지 못했어요"))
        XCTAssertTrue(app.staticTexts["push.permission.status"].label.contains("꺼져"));capture(app,name:"Notification01 registration failure and denied permission distinguished")
        tap(app.buttons["push.registration.retry"],in:app)
        let ready=NSPredicate{_,_ in app.staticTexts["push.registration.status"].label.contains("등록 완료")};expectation(for:ready,evaluatedWith:nil);waitForExpectations(timeout:6)
        XCTAssertTrue(app.staticTexts["push.permission.status"].label.contains("꺼져"));capture(app,name:"Notification02 mocked retry saves registration without enabling alert permission")
        tap(app.buttons["push.permission.request"],in:app);XCTAssertTrue(app.staticTexts["push.permission.status"].label.contains("허용"));capture(app,name:"Notification03 synthetic permission separate from actual APNs delivery")
        app.terminate()
    }
    func testReplyMentionInboxCopy() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_NOTIFICATION_QA"] = "1"
        app.launchEnvironment["SOOM_REPLY_MENTION_NOTIFICATION_QA"] = "1"
        app.launch(); defer { app.terminate() }
        tap(app.buttons["reviewDemo.start"], in: app)
        tap(app.buttons["reviewDemo.notificationQA"], in: app)
        tap(app.buttons["notificationQA.inbox"], in: app)
        for text in ["댓글에 답글을 남겼어요", "회원님을 언급했어요"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: 6))
        }
        capture(app, name: "SYNTHETIC reply and mention notification inbox")
    }
    func testNotificationUpgradeInboxFailureReadRetryDeleteUndoAndRequestRoute() throws {
        continueAfterFailure=false;executionTimeAllowance=180
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"];app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launchEnvironment["SOOM_NOTIFICATION_QA"]="1";app.launch()
        tap(app.buttons["reviewDemo.start"],in:app);tap(app.buttons["reviewDemo.notificationQA"],in:app)
        for id in ["notificationQA.fetchFailure","notificationQA.readFailure","notificationQA.hideFailure"] {
            let control=app.switches[id];XCTAssertTrue(control.waitForExistence(timeout:5))
            control.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
            XCTAssertEqual(control.value as? String,"1","Synthetic failure must actually be enabled")
        }
        capture(app,name:"Notification00 failure injection switches verified on")
        tap(app.buttons["notificationQA.inbox"],in:app)
        XCTAssertTrue(app.staticTexts["notifications.error"].waitForExistence(timeout:6));XCTAssertFalse(app.staticTexts["아직 알림이 없어요"].exists);capture(app,name:"Notification04 read failure not shown as empty inbox")
        tap(app.buttons["알림 다시 불러오기"],in:app);XCTAssertTrue(app.buttons["읽음 처리 다시 시도"].waitForExistence(timeout:6));capture(app,name:"Notification05 loaded follow events retain unread on failed read receipt")
        tap(app.buttons["읽음 처리 다시 시도"],in:app)
        let first="notifications.row.D3500000-0000-4000-8000-000000000001"
        let row=app.descendants(matching:.any).matching(identifier:first).firstMatch;XCTAssertTrue(row.waitForExistence(timeout:6));capture(app,name:"Notification06 request approval and comment in same inbox")
        row.swipeLeft();tap(app.buttons["삭제"].firstMatch,in:app)
        let itemError = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "이 알림을 숨기지 못했어요")).firstMatch
        XCTAssertTrue(itemError.waitForExistence(timeout:6));XCTAssertTrue(row.exists)
        let hideRetry = app.buttons["notifications.hideRetry.D3500000-0000-4000-8000-000000000001"]
        XCTAssertTrue(hideRetry.isHittable)
        XCTAssertGreaterThanOrEqual(hideRetry.frame.height + 0.000001, 44, "44pt belongs inside the label; tolerate only floating-point representation error")
        print("NOTIFICATION_RETRY_SCOPE|\(hideRetry.label)|\(hideRetry.frame)")
        capture(app,name:"Notification07 failed hide preserves row with item-scoped retry")
        tap(hideRetry,in:app);XCTAssertTrue(app.buttons["notifications.undo"].waitForExistence(timeout:6));capture(app,name:"Notification08 own notification soft hidden with undo")
        tap(app.buttons["notifications.undo"],in:app);XCTAssertTrue(row.waitForExistence(timeout:6));capture(app,name:"Notification09 undo restores row without original data deletion")
        tap(row,in:app);XCTAssertTrue(app.navigationBars["팔로우 요청 · 승인 관리"].waitForExistence(timeout:6));capture(app,name:"Notification10 request notification opens existing requests screen")
        app.terminate()
    }
    func testSearchUXCombinedEntryScopesAndQueryBackNavigationAudit() throws {
        continueAfterFailure=false;executionTimeAllowance=150
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"];app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"]="1";app.launch()
        tap(app.buttons["reviewDemo.start"],in:app);tap(app.buttons["soom.tab.feed"],in:app);tap(app.buttons["검색"].firstMatch,in:app)
        XCTAssertTrue(app.buttons["profile.search.open"].waitForExistence(timeout:6));capture(app,name:"SearchAudit01 one search entry with loaded-post scope and separate user link")
        let postSearch=app.searchFields.firstMatch;tap(postSearch,in:app);postSearch.typeText("never_matches_synthetic_post\n")
        XCTAssertTrue(app.staticTexts["불러온 피드 안에서 일치하는 게시물을 찾지 못했어요."].waitForExistence(timeout:6));capture(app,name:"SearchAudit02 local loaded-post search empty explicitly scoped")
        tap(app.buttons["profile.search.open"],in:app);XCTAssertTrue(app.navigationBars["사용자 검색"].waitForExistence(timeout:6));capture(app,name:"SearchAudit03 separate user page starts without inherited post query")
        let people=app.searchFields.firstMatch;tap(people,in:app);people.typeText("demo_minseo")
        XCTAssertTrue(app.staticTexts["민서 · Demo"].waitForExistence(timeout:8));capture(app,name:"SearchAudit04 remote-shaped synthetic user results and profile navigation")
        people.buttons.firstMatch.tap();people.typeText("no_synthetic_person\n")
        XCTAssertTrue(app.staticTexts["일치하는 사용자가 없어요."].waitForExistence(timeout:8));capture(app,name:"SearchAudit05 user search empty result distinct from loaded-post search")
        let userBar=app.navigationBars["사용자 검색"]
        // iOS18 places the active-search Cancel outside the navigation bar.
        // Prefer that visible control before iOS26's navigation-bar Close.
        let cancel=app.buttons.matching(NSPredicate(format:"label IN %@",["Cancel","취소"])).firstMatch
        let close=userBar.buttons.matching(NSPredicate(format:"label IN %@",["Close","닫기"])).firstMatch
        if cancel.exists && cancel.isHittable { tap(cancel,in:app) }
        else if close.exists && close.isHittable { tap(close,in:app) }
        capture(app,name:"SearchAudit05b search editing ended before back")
        let hierarchy=XCTAttachment(string:app.debugDescription);hierarchy.name="Search navigation after ending editing";hierarchy.lifetime = .keepAlways;add(hierarchy)
        let identifiedBack=userBar.buttons["BackButton"]
        let labelledBack=userBar.buttons["검색"]
        if userBar.exists {
            let back=identifiedBack.exists ? identifiedBack : labelledBack
            XCTAssertTrue(back.waitForExistence(timeout:3),"Native back control must be present after ending editing")
            back.tap()
            if !app.navigationBars["사용자 검색"].waitForNonExistence(timeout:2) { back.tap() }
        }
        XCTAssertTrue(app.buttons["profile.search.open"].waitForExistence(timeout:6))
        capture(app,name:"SearchAudit06 back navigation actual post-query state")
        let state=XCTAttachment(string:"Post query after return: \(app.searchFields.firstMatch.value as? String ?? "<none>")");state.name="Search audit observed query state";state.lifetime = .keepAlways;add(state)
        app.terminate()
    }
}

extension ReviewDemoUITests {
    func testClubConfirmedCreateRefreshFailureShowsWarningAndReadRetry() {
        let app = uxLaunch(environment: ["SOOM_UX_CLUB_STATE": "create_refresh_failure"])
        defer { app.terminate() }
        uxTap(app.buttons["soom.tab.clubs"], in: app)
        uxTap(app.buttons["clubs.create.open"], in: app)
        let name = app.textFields["club.create.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 6)); uxTap(name, in: app); name.typeText("Synthetic Club R4")
        let purpose = app.textFields["club.create.purpose"]
        uxTap(purpose, in: app); purpose.typeText("Synthetic purpose\n")
        let submit = app.buttons["club.create.submit"]
        uxReveal(submit, in: app); uxTap(submit, in: app)
        let localConfirmation = app.buttons["club.create.localConfirm"]
        XCTAssertTrue(localConfirmation.waitForExistence(timeout: 8), "This fixture uses the in-memory local store")
        uxTap(localConfirmation, in: app)
        XCTAssertTrue(submit.waitForNonExistence(timeout: 8))
        let warning = app.staticTexts["clubs.error"]
        XCTAssertTrue(warning.waitForExistence(timeout: 8))
        XCTAssertTrue(warning.label.contains("클럽을 다시 만들 필요는 없어요"))
        capture(app, name: "R4 confirmed create refresh failure keeps read retry visible")
        let retry = app.buttons["clubs.retry"]; uxReveal(retry, in: app); uxTap(retry, in: app)
        XCTAssertTrue(retry.waitForNonExistence(timeout: 8))
        let created = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic Club R4")).firstMatch
        uxReveal(created, in: app); XCTAssertTrue(created.exists)
        capture(app, name: "R4 read-only retry reveals synthetic created club")
    }

    func testSearchLoadingNeverShowsPrematureEmptyAndEntryTouchTargetIs44() {
        let app = uxLaunch(environment: ["SOOM_SEARCH_QA": "loading"])
        defer { app.terminate() }
        uxTap(app.buttons["soom.tab.feed"], in: app)
        let search = app.buttons["검색"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 6))
        XCTAssertGreaterThanOrEqual(search.frame.width, 44)
        XCTAssertGreaterThanOrEqual(search.frame.height, 44)
        capture(app, name: "R4 search entry before native button activation")
        tap(search, in: app)
        XCTAssertTrue(app.staticTexts["feed.search.scope"].waitForExistence(timeout: 6))
        capture(app, name: "R4 search scope after native button activation")
        uxTap(app.buttons["profile.search.open"], in: app)
        XCTAssertTrue(app.staticTexts["profile.search.scope"].waitForExistence(timeout: 6))
        let query = app.searchFields.firstMatch; uxTap(query, in: app); query.typeText("nobody\n")
        XCTAssertTrue(element("profile.search.loading", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["profile.search.empty"].exists)
        capture(app, name: "R4 search loading is distinct from completed empty")
        XCTAssertTrue(app.staticTexts["profile.search.empty"].waitForExistence(timeout: 10))
        capture(app, name: "R4 search empty only after successful response")
    }

    func testSearchPageFailureKeepsResultsAndRetryAddsNextPage() {
        let app = uxLaunch(environment: ["SOOM_SEARCH_QA": "pagination"])
        defer { app.terminate() }
        uxTap(app.buttons["soom.tab.feed"], in: app)
        uxTap(app.buttons["검색"].firstMatch, in: app)
        uxTap(app.buttons["profile.search.open"], in: app)
        let query = app.searchFields.firstMatch; uxTap(query, in: app); query.typeText("synthetic\n")
        XCTAssertTrue(app.staticTexts["검색 테스트 01"].waitForExistence(timeout: 8))
        let more = app.buttons["profile.search.more"]; uxReveal(more, in: app); uxTap(more, in: app)
        let failure = app.staticTexts["profile.search.pageError"]
        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["검색 테스트 20"].exists)
        capture(app, name: "R4 search next-page failure retains previous results")
        let retry = app.buttons["profile.search.pageRetry"]; uxReveal(retry, in: app); uxTap(retry, in: app)
        XCTAssertTrue(app.staticTexts["검색 테스트 21"].waitForExistence(timeout: 8))
        XCTAssertTrue(failure.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["검색 테스트 20"].exists)
        capture(app, name: "R4 search next-page retry appends without resetting rows")
    }
}


extension ReviewDemoUITests {
    func testClubConfirmedCreationIdentityReadFailureCanRetryWithoutCreatingAgain() {
        continueAfterFailure = false
        let app = uxLaunch(environment: ["SOOM_UX_CLUB_STATE": "identity_first_read_failure"])
        defer { app.terminate() }
        uxTap(app.buttons["soom.tab.clubs"], in: app)
        uxTap(app.buttons["clubs.create.open"], in: app)
        let name = app.textFields["club.create.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 6)); uxTap(name, in: app); name.typeText("Synthetic Identity Club")
        let purpose = app.textFields["club.create.purpose"]
        uxTap(purpose, in: app); purpose.typeText("Synthetic purpose\n")
        let submit = app.buttons["club.create.submit"]
        uxReveal(submit, in: app); uxTap(submit, in: app)
        let confirmation = app.buttons["club.create.localConfirm"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 8)); uxTap(confirmation, in: app)
        XCTAssertTrue(submit.waitForNonExistence(timeout: 8))
        let failed = app.staticTexts["클럽 정보를 확인하지 못했어요. 다시 불러와 주세요."]
        uxReveal(failed, in: app); XCTAssertTrue(failed.exists)
        capture(app, name: "Club confirmed creation identity lookup failed before retry")
        let retry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "club.identity.retry.")).firstMatch
        XCTAssertTrue(retry.exists, "A failed row identity read currently has no recovery action")
        uxTap(retry, in: app)
        let created = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic Identity Club")).firstMatch
        uxReveal(created, in: app); XCTAssertTrue(created.exists)
        XCTAssertFalse(retry.exists)
        capture(app, name: "Club confirmed creation identity read retry reveals existing club")
    }
}


extension ReviewDemoUITests {
    func testFeedbackAllFiveZonesZeroMissingAndCyclingRunningSplitUnits() {
        continueAfterFailure = false; executionTimeAllowance = 240
        let app = detailFixtureApp()
        defer { app.terminate() }
        selectEffortFixture("심박 0초", in: app)
        let zone5 = element("detail.hrZone.5", in: app)
        reveal(zone5, in: app)
        for index in 1...5 { XCTAssertTrue(element("detail.hrZone.\(index)", in: app).exists) }
        XCTAssertTrue(zone5.label.contains("0:00")); XCTAssertTrue(zone5.label.contains("0 퍼센트"))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64)))
        captureDetail(app, name: "Feedback all five heart zones including measured zero")
        selectEffortFixture("심박 결측", in: app)
        let missing5 = element("detail.hrZone.5", in: app)
        reveal(missing5, in: app)
        XCTAssertTrue(missing5.label.contains("기록 없음")); XCTAssertFalse(missing5.label.contains("0 퍼센트"))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64)))
        captureDetail(app, name: "Feedback missing heart data retains five unavailable rows")
        for (scenario, unit, title) in [("없음", "/km", "페이스"), ("사이클", "km/h", "평균 속도"), ("마일 사이클", "mph", "평균 속도"), ("마일 러닝", "/mi", "페이스")] {
            selectEffortFixture(scenario, in: app)
            let heading = app.staticTexts["detail.splits.heading"]
            reveal(heading, in: app); XCTAssertTrue(heading.label.contains(title))
            let first = element("detail.split.구간 1", in: app)
            reveal(first, in: app); XCTAssertTrue(first.label.contains(unit), first.label)
            captureDetail(app, name: "Feedback split sport and unit " + scenario)
        }
    }
}


extension ReviewDemoUITests {
    func testApprovedRecordStartVisibleTargetsCancelTapAlternativeAndDragStart() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"; app.launch()
        enterSyntheticDemo(app); selectGateTab("soom.tab.record", in: app)
        let circle = app.buttons["record.startCircle"]
        let startVisible = circle.waitForExistence(timeout: 10)
        if !startVisible {
            capture(app, name: "Approved start - missing circle diagnostic")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Approved start missing circle hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(startVisible)
        XCTAssertLessThanOrEqual(circle.frame.width, 112)
        XCTAssertLessThanOrEqual(circle.frame.height, 112)
        XCTAssertTrue(app.staticTexts["누른 채 위로 밀어보세요"].exists)
        XCTAssertTrue(app.buttons["record.tapStart"].isHittable)
        capture(app, name: "Approved start - persistent sport targets and upward path")
        let origin = circle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.tap()
        XCTAssertFalse(app.staticTexts["coach.caption"].exists)
        origin.press(forDuration: 0.2, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: -35)))
        XCTAssertFalse(app.staticTexts["coach.caption"].exists)
        capture(app, name: "Approved start - short gesture cancelled")
        tap(app.buttons["record.tapStart"], in: app)
        XCTAssertTrue(app.buttons["record.tapConfirm"].waitForExistence(timeout: 5))
        capture(app, name: "Approved start - accessible tap confirmation")
        tap(app.buttons["record.tapCancel"], in: app)
        XCTAssertTrue(circle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["coach.caption"].exists)
        origin.press(forDuration: 0.2, thenDragTo: origin.withOffset(CGVector(dx: 160, dy: -174)))
        XCTAssertFalse(app.staticTexts["coach.caption"].exists)
        origin.press(forDuration: 0.2, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: -174)))
        XCTAssertTrue(app.staticTexts["coach.caption"].waitForExistence(timeout: 10))
        capture(app, name: "Approved start - running session only after target release")
        tap(app.buttons["일시정지"], in: app); tap(app.buttons["종료"], in: app); tap(app.buttons["운동 종료"], in: app)
        XCTAssertTrue(app.staticTexts["기록 종료"].waitForExistence(timeout: 6))
        app.terminate()
    }
}


extension ReviewDemoUITests {
    func testClubInitiallyMissingDirectoryLocalConfirmationAndReadRecovery() {
        continueAfterFailure = false
        let app = uxLaunch(environment: ["SOOM_UX_CLUB_STATE": "initial_directory_failure"])
        selectGateTab("soom.tab.clubs", in: app)
        XCTAssertTrue(app.buttons["clubs.retry"].waitForExistence(timeout: 8))
        capture(app, name: "Club initial directory read failed - no successful-empty claim")
        tap(app.buttons["클럽 만들기"], in: app)
        let name = app.textFields["club.create.name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Synthetic Local Recovery")
        let purpose = app.textFields["club.create.purpose"]; purpose.tap(); purpose.typeText("Synthetic only")
        tap(app.buttons["club.create.submit"], in: app)
        let confirmation = app.buttons["club.create.localConfirm"]; XCTAssertTrue(confirmation.waitForExistence(timeout: 8))
        capture(app, name: "Club explicit local save confirmation before acknowledgement")
        tap(confirmation, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "이 기기에 클럽을 저장했지만")).firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "Club screenshot-correlated local save directory refresh failure")
        tap(app.buttons["clubs.retry"], in: app)
        let recovered = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic Local Recovery")).firstMatch
        uxReveal(recovered, in: app); XCTAssertTrue(recovered.exists)
        capture(app, name: "Club local receipt recovered by read only - local banner retained")
        app.terminate()
    }

    func testApprovedStartArmedAndDraggingVisualFixtures() {
        continueAfterFailure = false
        for state in ["dragging", "armed"] {
            let app = uxLaunch(environment: ["SOOM_RECORD_START_REVIEW_STATE": state])
            selectGateTab("soom.tab.record", in: app)
            let title = state == "armed" ? "손을 놓으면 러닝 시작" : "종목 쪽으로 조금 더"
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 8))
            XCTAssertFalse(app.staticTexts["coach.caption"].exists)
            capture(app, name: "Approved start visual render fixture - \(state) - not gesture evidence")
            app.terminate()
        }
    }

    func testApprovedTapAlternativeUsesSameWatchGateAndStartsCyclingAfterConfirmation() {
        continueAfterFailure = false
        let blocked = uxLaunch(environment: ["SOOM_RECORD_START_REVIEW_STATE": "watch"])
        selectGateTab("soom.tab.record", in: blocked)
        tap(blocked.buttons["record.tapStart"], in: blocked)
        tap(blocked.buttons["record.tapConfirm"], in: blocked)
        XCTAssertTrue(blocked.buttons["record.watchBack"].waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(blocked.buttons["record.watchBack"].frame.height, 44)
        XCTAssertFalse(blocked.staticTexts["coach.caption"].exists)
        capture(blocked, name: "Approved start watch-active gate - synthetic Watch signal")
        tap(blocked.buttons["record.watchBack"], in: blocked)
        XCTAssertTrue(blocked.buttons["record.tapStart"].waitForExistence(timeout: 5)); blocked.terminate()
        let app = uxLaunch(); selectGateTab("soom.tab.record", in: app)
        XCTAssertGreaterThanOrEqual(app.buttons["record.tapStart"].frame.height, 44)
        tap(app.buttons["record.tapStart"], in: app)
        XCTAssertGreaterThanOrEqual(app.buttons["record.tapConfirm"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["record.tapCancel"].frame.height, 44)
        tap(app.buttons["라이딩"], in: app)
        tap(app.buttons["record.tapConfirm"], in: app)
        XCTAssertTrue(app.staticTexts["coach.caption"].waitForExistence(timeout: 10))
        capture(app, name: "Approved accessible tap confirmation starts cycling without location permission")
        app.terminate()
    }
}


extension ReviewDemoUITests {
    func testChartsAndSplitsAlwaysVisiblePerVisitReference() {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = detailFixtureApp(); defer { app.terminate() }
        XCTAssertFalse(app.buttons["detail.charts.toggle"].exists)
        XCTAssertFalse(app.buttons["detail.splits.toggle"].exists)
        let zones = element("detail.hrZone.5", in: app)
        reveal(zones, in: app); XCTAssertTrue(zones.exists)
        captureDetail(app, name: "Reference compact heart zones all five")
        let first = element("detail.split.구간 1", in: app)
        reveal(first, in: app); XCTAssertTrue(first.exists)
        for _ in 0..<5 {
            if first.frame.minY < app.frame.height * 0.45 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.78)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        }
        XCTAssertLessThan(first.frame.maxY, app.frame.height * 0.8)
        captureDetail(app, name: "Reference compact running splits")
        app.swipeUp(); app.swipeDown()
        reveal(first, in: app); XCTAssertTrue(first.exists)
        captureDetail(app, name: "Same visit splits after scroll return")
        let heart = element("detail.chart.심박수", in: app)
        reveal(heart, in: app); XCTAssertTrue(heart.exists)
        captureDetail(app, name: "Always visible measured chart first viewport")
        selectEffortFixture("사이클", in: app)
        reveal(element("detail.split.구간 1", in: app), in: app)
        let cycling = element("detail.split.구간 1", in: app)
        for _ in 0..<5 {
            if cycling.frame.minY < app.frame.height * 0.45 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.78)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        }
        XCTAssertLessThan(cycling.frame.maxY, app.frame.height * 0.8)
        captureDetail(app, name: "Reference compact cycling splits")
    }

    func testAstraNativeMapInitialSummaryRunningAndCycling() {
        continueAfterFailure = false; executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
        app.launch(); defer { app.terminate() }
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        tap(app.buttons["soom.tab.activity"], in: app)
        tap(app.buttons["activity.section.workouts"], in: app)
        for title in ["공원 러닝", "강변 라이딩"] {
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "DEMO ·", title)).firstMatch
            reveal(card, in: app); tap(card, in: app)
            let handle = app.buttons["상세 정보 시트"]
            XCTAssertTrue(handle.waitForExistence(timeout: 10))
            XCTAssertGreaterThan(handle.frame.minY, app.frame.height * 0.5)
            XCTAssertLessThan(handle.frame.minY, app.frame.height * 0.65)
            XCTAssertFalse(app.buttons["soom.tab.feed"].isHittable)
            captureDetail(app, name: "Astra map initial summary " + title)
            // The map and initial sheet stay fixed; two-column metrics scroll.
            tap(handle, in: app)
            XCTAssertTrue(app.buttons["workout.detail.collapse"].waitForExistence(timeout: 5))
            let expandedHeader = app.buttons["workout.detail.collapse"]
            XCTAssertLessThan(expandedHeader.frame.minY, 85, "Expanded header must sit directly below the system safe area")
            captureDetail(app, name: "Expanded header safe area " + title)
            let distance = element("workout.summary.metric.거리", in: app)
            let rate = element(title == "공원 러닝" ? "workout.summary.metric.페이스" : "workout.summary.metric.평속", in: app)
            let duration = element("workout.summary.metric.총 시간", in: app)
            reveal(duration, in: app)
            XCTAssertEqual(distance.frame.minY, rate.frame.minY, accuracy: 2)
            XCTAssertGreaterThan(duration.frame.minY, distance.frame.minY + 10)
            XCTAssertEqual(duration.frame.minX, distance.frame.minX, accuracy: 2)
            for label in ["거리", "총 시간", "획득 고도", "활동 칼로리", "평균 파워"] {
                let metric = element("workout.summary.metric." + label, in: app)
                reveal(metric, in: app); XCTAssertTrue(metric.isHittable)
            }
            captureDetail(app, name: "Two column summary expanded " + title)
            openEffort(in: app)
            captureDetail(app, name: "Astra native effort presentation " + title)
            tap(app.buttons["effort.cancel"], in: app)
            XCTAssertTrue(app.buttons["effort.cancel"].waitForNonExistence(timeout: 5))
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
            tap(app.buttons["workout.detail.collapse"], in: app)
            let standard = NSPredicate(format: "label CONTAINS %@", "sheet=standard")
            XCTAssertTrue(app.staticTexts.matching(standard).firstMatch.waitForExistence(timeout: 5))
            captureDetail(app, name: "Astra map collapsed before back " + title)
            tap(app.buttons["workout.detail.back"], in: app)
        }
    }
}


extension ReviewDemoUITests {
    func testAstraSmallMapAndAccessibilitySummaryRemainReachable() {
        continueAfterFailure = false; executionTimeAllowance = 240
        for large in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
            if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
            app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
            app.launch()
            if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
            tap(app.buttons["soom.tab.activity"], in: app)
            tap(app.buttons["activity.section.workouts"], in: app)
            let running = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "DEMO ·", "공원 러닝")).firstMatch
            // The largest system text makes the bottom tab bar taller on SE.
            // Start above it so this gesture reaches the activity scroll view.
            for _ in 0..<20 {
                if running.exists && running.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.62)).press(forDuration: 0.05,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.30)))
            }
            tap(running, in: app)
            let handle = app.buttons["상세 정보 시트"]
            XCTAssertTrue(handle.waitForExistence(timeout: 10))
            XCTAssertGreaterThan(handle.frame.minY, app.frame.height * 0.5)
            captureDetail(app, name: large ? "Astra small map accessibility initial" : "Astra small map initial")
            tap(handle, in: app)
            let metric = element("workout.summary.metric.평균 파워", in: app)
            reveal(metric, in: app)
            XCTAssertGreaterThanOrEqual(metric.frame.minX, 0)
            XCTAssertLessThanOrEqual(metric.frame.maxX, app.frame.width)
            XCTAssertTrue(metric.isHittable)
            XCTAssertTrue(app.buttons["workout.detail.collapse"].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons["workout.detail.collapse"].frame.minY, 20)
            captureDetail(app, name: large ? "Astra small accessibility summary scrolled" : "Astra small summary expanded")
            app.terminate()
        }
    }
}


extension ReviewDemoUITests {
    func testAcceptanceProfileGalleryCountsScrollReturnAndRecordMutation() {
        let app = uxLaunch(environment: ["SOOM_UX_GALLERY_LOADING_COUNTER": "1"])
        defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app)
        let counter = app.staticTexts["profile.gallery.qa.counts"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        func counts() -> [String: Int] {
            Dictionary(uniqueKeysWithValues: counter.label.split(separator: " ").compactMap { part in
                let pieces = part.split(separator: "=")
                guard pieces.count == 2, let number = Int(pieces[1]) else { return nil }
                return (String(pieces[0]), number)
            })
        }
        let loadedProfile = expectation(for: NSPredicate { _, _ in (counts()["rows"] ?? 0) > 0 }, evaluatedWith: counter)
        wait(for: [loadedProfile], timeout: 10)
        uxTap(app.buttons["profile.tab.gallery"], in: app)
        let initial = expectation(for: NSPredicate { _, _ in counts()["attempts"] == 1 && counts()["loading"] == 0 }, evaluatedWith: counter)
        wait(for: [initial], timeout: 15)
        let rows = counts()["rows"] ?? 0
        XCTAssertGreaterThan(rows, 0); XCTAssertEqual(counts()["reads"], rows)
        capture(app, name: "Acceptance gallery initial synthetic photo reads")
        app.swipeUp(); app.swipeDown()
        XCTAssertEqual(counts()["attempts"], 1); XCTAssertEqual(counts()["reads"], rows)
        uxTap(app.buttons["soom.tab.activity"], in: app)
        uxTap(app.buttons["soom.tab.profile"], in: app)
        XCTAssertEqual(counts()["attempts"], 1); XCTAssertEqual(counts()["reads"], rows)
        app.buttons["profile.gallery.qa.mutation"].tap()
        let changed = expectation(for: NSPredicate { _, _ in counts()["attempts"] == 2 && counts()["loading"] == 0 }, evaluatedWith: counter)
        wait(for: [changed], timeout: 15)
        XCTAssertEqual(counts()["reads"], rows * 2)
        capture(app, name: "Acceptance gallery mutation exactly one synthetic refresh")
    }
}

@MainActor
final class SkeletonUITests: XCTestCase {
    private func app(style: String? = nil, dark: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_SKELETON_QA"] = "1"
        if let style { app.launchEnvironment["SOOM_SKELETON_STYLE"] = style }
        if dark { app.launchEnvironment["SOOM_SKELETON_DARK"] = "1" }
        if large { app.launchEnvironment["SOOM_SKELETON_LARGE"] = "1" }
        app.launch(); return app
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testSlowInitialRefreshFailureCancelRetryAndNoFetchOnRedraw() {
        let app = app()
        let placeholder = app.descendants(matching: .any)["skeleton.list"].firstMatch
        XCTAssertTrue(placeholder.waitForExistence(timeout: 15))
        capture("actual-health-initial", app)
        XCTAssertTrue(app.staticTexts["skeleton.qa.requests"].label.contains("요청 1"))
        app.buttons["skeleton.qa.redraw"].tap()
        app.swipeUp(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["skeleton.qa.requests"].label.contains("요청 1"))
        app.buttons["skeleton.qa.complete"].tap()
        XCTAssertTrue(placeholder.waitForNonExistence(timeout: 5))
        app.buttons["skeleton.qa.refresh"].tap()
        XCTAssertFalse(placeholder.exists)
        capture("actual-health-cached-refresh", app)
        app.buttons["skeleton.qa.fail"].tap()
        XCTAssertFalse(placeholder.exists)
        capture("actual-health-cached-failure", app)
        app.buttons["skeleton.qa.refresh"].tap()
        app.buttons["skeleton.qa.cancel"].tap()
        XCTAssertFalse(placeholder.exists)
        app.buttons["skeleton.qa.refresh"].tap()
        app.buttons["skeleton.qa.empty"].tap()
        XCTAssertFalse(placeholder.exists)
        capture("actual-health-empty", app)
        app.buttons["skeleton.qa.refresh"].tap()
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
        app.buttons["skeleton.qa.fail"].tap()
        XCTAssertTrue(placeholder.waitForNonExistence(timeout: 5))
        capture("actual-health-error", app)
        app.buttons["skeleton.qa.refresh"].tap()
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
        app.buttons["skeleton.qa.complete"].tap()
        XCTAssertTrue(placeholder.waitForNonExistence(timeout: 5))
    }
    func testSkeletonLayoutsLightAndDarkLargeText() {
        for style in ["feed", "workout", "list", "profile", "detail", "chart", "summary", "photo", "row"] {
            let app = app(style: style)
            XCTAssertTrue(app.descendants(matching: .any)["skeleton." + style].firstMatch.waitForExistence(timeout: 15))
            capture("skeleton-light-" + style, app); app.terminate()
        }
        for style in ["feed", "chart", "list"] {
            let app = app(style: style, dark: true, large: true)
            XCTAssertTrue(app.descendants(matching: .any)["skeleton." + style].firstMatch.waitForExistence(timeout: 15))
            capture("skeleton-dark-large-" + style, app); app.terminate()
        }
    }
}


extension ReviewDemoUITests {
    func testReportedEffortWithoutHistorySelectionCalloutAndReentry() {
        continueAfterFailure = false; executionTimeAllowance = 120
        let app = detailFixtureApp(); defer { app.terminate() }
        selectEffortFixture("Apple 기록", in: app); openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "6 / 10")
        XCTAssertEqual(app.staticTexts["effort.selection.status"].label, "선택 강도 6")
        XCTAssertFalse(app.staticTexts["effort.range.status"].exists)
        XCTAssertTrue(app.staticTexts["effort.range.empty"].label.contains("5개"))
        captureDetail(app, name: "Reported effort six no history after selection callout fix")
        dragEffort(to: 0.92, in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "10 / 10")
        XCTAssertEqual(app.staticTexts["effort.selection.status"].label, "선택 강도 10")
        captureDetail(app, name: "Reported effort ten no history after drag")
        tap(app.buttons["effort.cancel"], in: app); openEffort(in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "6 / 10")
        tap(app.buttons["effort.cancel"], in: app)
        app.switches["모션 줄이기"].tap()
        openEffort(in: app); dragEffort(to: 0.08, in: app)
        XCTAssertEqual(app.staticTexts["effort.value"].label, "1 / 10")
        captureDetail(app, name: "Reported effort reduced motion drag remains functional")
        tap(app.buttons["effort.cancel"], in: app)
    }
}


extension ReviewDemoUITests {
    func testCommonScreenEdgesAndTabReturnPreserveContent() {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = uxLaunch(demo: false, environment: ["SOOM_DETAIL_NORMAL_LAYOUT_QA": "1"])
        defer { app.terminate() }
        if app.buttons["reviewDemo.start"].waitForExistence(timeout: 10) { tap(app.buttons["reviewDemo.start"], in: app) }
        for tab in ["feed", "activity", "clubs", "profile"] {
            let button = app.buttons["soom.tab." + tab]
            // Tab controls are intentionally outside the content scroll viewport.
            uxTap(button, in: app)
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThan(button.frame.maxY, app.frame.height - 44)
            XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.height - 12)
            capture(app, name: "Common edge initial " + tab)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.74)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3)))
            capture(app, name: "Common edge scrolled " + tab)
            app.swipeDown()
        }
        uxTap(app.buttons["soom.tab.feed"], in: app)
        capture(app, name: "Common edge feed return preserved content")
    }
}


extension ReviewDemoUITests {
    func testHealthKitOriginalSwimmingLapsAndReadFailurePreserveContent() {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = detailFixtureApp(healthKit: true); defer { app.terminate() }
        selectEffortFixture("수영 원본 랩", in: app)
        let lap = element("detail.split.랩 1", in: app)
        reveal(lap, in: app); XCTAssertTrue(lap.exists)
        XCTAssertTrue(lap.label.contains("0:35"))
        XCTAssertTrue((lap.value as? String ?? "").contains("25 m"))
        captureDetail(app, name: "Synthetic HealthKit original swimming lap time and measured length")
        selectEffortFixture("수영 랩 결측", in: app)
        reveal(element("detail.hrZone.5", in: app), in: app)
        XCTAssertFalse(element("detail.splits.heading", in: app).exists)
        captureDetail(app, name: "Swimming distance series without invented laps")
        selectEffortFixture("심박 요약만", in: app)
        let aggregate = element("workout.summary.metric.평균 심박", in: app)
        reveal(aggregate, in: app); XCTAssertTrue(aggregate.exists)
        XCTAssertFalse(element("detail.chart.심박수", in: app).exists)
        captureDetail(app, name: "Measured heart aggregate without invented chart")
        selectEffortFixture("건강 읽기 오류", in: app)
        let retry = app.buttons["detail.health.retry"]
        reveal(retry, in: app); XCTAssertTrue(retry.isHittable)
        captureDetail(app, name: "Health read failure keeps existing detail and offers explicit retry")
        tap(retry, in: app)
        XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("detail.hrZone.5", in: app).exists)
    }
}


extension ReviewDemoUITests {
    private func assertRecoveryEntry(large: Bool) {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["reviewDemo.start"].waitForExistence(timeout: 12))
        uxTap(app.buttons["reviewDemo.start"], in: app)
        XCTAssertTrue(app.buttons["reviewDemo.exit"].waitForExistence(timeout: 12))
        selectGateTab("soom.tab.feed", in: app)
        let recovery = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "오늘의 회복")).firstMatch
        if large {
            uxReveal(recovery, in: app)
        } else {
            for _ in 0..<4 {
                if recovery.exists && recovery.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.34)).press(forDuration: 0.05,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.34)))
            }
        }
        XCTAssertTrue(recovery.exists && recovery.isHittable)
        capture(app, name: "RECOVERY SYNTHETIC before entry " + (large ? "large stacked" : "normal carousel"))
        let visible = recovery.frame.intersection(uxViewport(app))
        XCTAssertFalse(visible.isNull)
        print("SOOM_RECOVERY_ENTRY_RECT|large=\(large)|card=\(recovery.frame)|visible=\(visible)")
        // A plain card's visible whitespace must be part of its tap target.
        let baselinePoint = CGPoint(x: app.frame.width * (large ? 347.6666564941406 / 402 : 271.0 / 402),
                                    y: app.frame.height * (large ? 737.6666564941406 / 874 : 286.3333435058594 / 874))
        let point = visible.contains(baselinePoint) ? baselinePoint : CGPoint(x: visible.maxX - 10, y: visible.midY)
        print("SOOM_RECOVERY_TESTED_POINT|large=\(large)|point=\(point)")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        let opened = app.navigationBars["회복"].waitForExistence(timeout: 8)
        capture(app, name: "RECOVERY SYNTHETIC after entry " + (large ? "large stacked" : "normal carousel"))
        if !opened {
            let title = app.staticTexts["오늘의 회복"].firstMatch
            if title.exists && title.isHittable { uxTap(title, in: app) }
            else { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.minX + 20, dy: visible.minY + 12)).tap() }
            let textOpens = app.navigationBars["회복"].waitForExistence(timeout: 5)
            print("SOOM_RECOVERY_LABEL_RETRY|large=\(large)|opened=\(textOpens)")
            capture(app, name: "RECOVERY SYNTHETIC label diagnostic after blank card tap failed")
        }
        XCTAssertTrue(opened, "Visible card whitespace must navigate, not stay on feed")
        let checkIn = app.buttons.matching(identifier: "오늘 컨디션 기록하기").firstMatch
        recoveryReveal(checkIn, in: app); XCTAssertTrue(checkIn.isHittable)
        uxTap(checkIn, in: app)
        XCTAssertTrue(app.navigationBars["컨디션 기록"].waitForExistence(timeout: 5))
        capture(app, name: "RECOVERY SYNTHETIC check-in opened without saving")
        uxBack(app)
        XCTAssertTrue(app.navigationBars["회복"].waitForExistence(timeout: 5))
        let history = app.buttons.matching(identifier: "컨디션 기록 보기").firstMatch
        recoveryReveal(history, in: app); uxTap(history, in: app)
        XCTAssertTrue(app.navigationBars["컨디션 기록"].waitForExistence(timeout: 5))
        capture(app, name: "RECOVERY SYNTHETIC history opened without edits")
        uxBack(app); uxBack(app)
        XCTAssertTrue(app.buttons["검색"].waitForExistence(timeout: 5))
        capture(app, name: "RECOVERY SYNTHETIC back returns to same feed")
        if large { uxReveal(recovery, in: app) } else {
            for _ in 0..<4 {
                if recovery.exists && recovery.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.34)).press(forDuration: 0.05,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.34)))
            }
        }
        let reopenedFrame = recovery.frame.intersection(uxViewport(app))
        XCTAssertGreaterThan(reopenedFrame.height, 0)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: reopenedFrame.maxX - 10, dy: reopenedFrame.midY)).tap()
        XCTAssertTrue(app.navigationBars["회복"].waitForExistence(timeout: 5))
        capture(app, name: "RECOVERY SYNTHETIC repeated whitespace entry")
        uxBack(app); XCTAssertTrue(app.buttons["검색"].waitForExistence(timeout: 5))
    }
    private func recoveryReveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<30 {
            let viewport = uxViewport(app)
            if target.exists && target.isHittable && target.frame.intersection(viewport).height >= min(44, target.frame.height) { return }
            let up = !target.exists || target.frame.midY > viewport.midY
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewport.maxX - 5, dy: viewport.minY + viewport.height * (up ? 0.8 : 0.2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewport.maxX - 5, dy: viewport.minY + viewport.height * (up ? 0.2 : 0.8)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.exists && target.isHittable)
    }
    func testRecoveryEntryFromFeedCarouselReachesCheckInAndBack() { assertRecoveryEntry(large: false) }
    func testRecoveryEntryFromFeedAtMaximumTextReachesCheckInAndBack() { assertRecoveryEntry(large: true) }
}

extension ReviewDemoUITests {
    private func fullAppCheckIn(large: Bool, ordinaryLayout: Bool = false) {
        continueAfterFailure = false; executionTimeAllowance = large ? 420 : 300
        let app = XCUIApplication(); defer { app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_CHECKIN_FORM_QA"] = "1"
        if ordinaryLayout { app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1" }
        app.launch()
        if ordinaryLayout {
            XCTAssertTrue(app.staticTexts["LAYOUT QA · 합성"].waitForExistence(timeout: 10))
        } else { uxTap(app.buttons["reviewDemo.start"], in: app) }
        selectGateTab("soom.tab.feed", in: app)
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "오늘의 회복")).firstMatch
        if large { uxReveal(card, in: app) } else {
            for _ in 0..<4 {
                if card.exists && card.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.34)).press(forDuration: 0.05,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.34)))
            }
        }
        uxTap(card, in: app); XCTAssertTrue(app.navigationBars["회복"].waitForExistence(timeout: 8))
        capture(app, name: "FULL APP D recovery hierarchy synthetic " + (large ? "maximum" : "normal"))
        let entry = app.buttons["recovery.checkin.quick"]
        uxTap(entry, in: app)
        XCTAssertTrue(app.navigationBars["컨디션 기록"].waitForExistence(timeout: 8))
        let choices = [("피로감",2),("수면감",4),("근육통",2),("기분",4)]
        for (title, value) in choices {
            let first = app.buttons["checkin.scale.\(title).1"]
            checkInReveal(first, in: app); XCTAssertGreaterThanOrEqual(first.frame.height, 44)
            XCTAssertFalse(first.value as? String == "선택됨")
            let last = app.buttons["checkin.scale.\(title).5"]
            checkInReveal(last, in: app); XCTAssertTrue(last.label.contains("5점"))
            let chosen = app.buttons["checkin.scale.\(title).\(value)"]
            checkInReveal(chosen, in: app); chosen.tap()
            XCTAssertTrue(chosen.isSelected || (chosen.value as? String)?.contains("선택됨") == true)
            capture(app, name: "FULL APP A selected \(title) \(value) synthetic " + (large ? "maximum" : "normal"))
        }
        let note = app.textViews["메모"].firstMatch
        checkInReveal(note, in: app); note.tap(); note.typeText("QA native retained memo")
        capture(app, name: "FULL APP B keyboard synthetic " + (large ? "maximum" : "normal"))
        let keyboardDone = app.buttons["완료"].firstMatch
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5)); keyboardDone.tap()
        XCTAssertEqual(app.keyboards.count, 0)
        XCTAssertTrue(app.staticTexts["checkin.qa.attempts"].label.contains("0"), "Keyboard Done must not save")
        XCTAssertTrue((note.value as? String)?.contains("QA native retained memo") == true)
        note.tap(); XCTAssertGreaterThan(app.keyboards.count, 0)
        let save = app.buttons["오늘 상태 기록"]
        XCTAssertTrue(save.exists)
        // This is the original form -> original VM -> failing adapter -> in-memory SwiftData store.
        save.tap(); XCTAssertTrue(app.otherElements["checkin.save.failure"].waitForExistence(timeout: 8) || app.staticTexts["checkin.save.failure"].exists)
        XCTAssertEqual(app.keyboards.count, 0)
        XCTAssertTrue(app.staticTexts["checkin.qa.attempts"].label.contains("1"))
        XCTAssertTrue(save.isEnabled && save.isHittable)
        let retryLabel = save.staticTexts.firstMatch
        XCTAssertTrue(retryLabel.exists)
        XCTAssertGreaterThanOrEqual(save.frame.intersection(retryLabel.frame).height, retryLabel.frame.height - 1,
                                   "A tappable CTA with clipped text is still a failure")
        if large {
            let resultScroll = app.scrollViews["soom.feedback.scroll"]
            XCTAssertTrue(resultScroll.exists && resultScroll.isHittable)
            capture(app, name: "FULL APP B bounded error first lines retry fully visible maximum")
            resultScroll.swipeUp()
            capture(app, name: "FULL APP B bounded error last lines retry still visible maximum")
        }
        capture(app, name: "FULL APP B native failure draft retained " + (large ? "maximum" : "normal"))
        save.tap()
        let success = NSPredicate { _, _ in
            app.staticTexts["checkin.qa.attempts"].label.contains("2") && !save.isEnabled
        }
        expectation(for: success, evaluatedWith: nil); waitForExpectations(timeout: 8)
        capture(app, name: "FULL APP B native retry success no duplicate " + (large ? "maximum" : "normal"))
        // Read retained state here; no further editing is requested after save.
        // The following history/detail steps independently verify persisted values.
        XCTAssertTrue(note.exists)
        XCTAssertTrue((note.value as? String)?.contains("QA native retained memo") == true)
        uxBack(app); XCTAssertTrue(app.navigationBars["회복"].waitForExistence(timeout: 6))
        let history = app.buttons["recovery.history.quick"]
        uxTap(history, in: app)
        XCTAssertTrue(app.navigationBars["컨디션 기록"].waitForExistence(timeout: 6))
        let savedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND value CONTAINS %@", "컨디션 기록", "피로감 2점, 수면감 4점, 근육통 2점, 기분 4점")).firstMatch
        recoveryReveal(savedRow, in: app); XCTAssertTrue(savedRow.exists)
        capture(app, name: "FULL APP A saved history actual synthetic database " + (large ? "maximum" : "normal"))
        uxTap(savedRow, in: app); XCTAssertTrue(app.navigationBars["기록 상세"].waitForExistence(timeout: 6))
        capture(app, name: "FULL APP A detail preserves metrics " + (large ? "maximum" : "normal"))
        let management = app.navigationBars["기록 상세"].buttons["기록 관리"]
        XCTAssertTrue(management.exists)
        XCTAssertGreaterThanOrEqual(management.frame.height + 0.000001, 44)
        let toolbarHit = management.frame.intersection(app.navigationBars["기록 상세"].frame)
        XCTAssertGreaterThanOrEqual(toolbarHit.height + 0.000001, 44)
        // Menu wrappers may report isHittable=false on iOS18. Prove the real visible
        // 44pt toolbar location opens the menu instead of scrolling to the target.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: toolbarHit.midX, dy: toolbarHit.midY)).tap()
        XCTAssertTrue(app.buttons["수정하기"].waitForExistence(timeout: 5))
        uxTap(app.buttons["수정하기"], in: app)
        XCTAssertTrue(app.navigationBars["기록 수정"].waitForExistence(timeout: 5))
        let edit = app.buttons["수정 내용 저장"]; edit.tap()
        XCTAssertTrue(app.otherElements["checkin.save.failure"].waitForExistence(timeout: 8) || app.staticTexts["checkin.save.failure"].exists)
        capture(app, name: "FULL APP B edit failure retained " + (large ? "maximum" : "normal"))
        edit.tap(); XCTAssertTrue(app.navigationBars["기록 상세"].waitForExistence(timeout: 8))
        capture(app, name: "FULL APP B edit retry returns detail " + (large ? "maximum" : "normal"))
    }
    private func checkInReveal(_ element: XCUIElement, in app: XCUIApplication) {
        var previous: CGRect?; var stalled = 0
        for _ in 0..<18 {
            let footer = app.buttons["오늘 상태 기록"]
            var footerTop = footer.exists ? footer.frame.minY : app.frame.maxY - 82
            let attempts = app.staticTexts["checkin.qa.attempts"]
            if attempts.exists { footerTop = min(footerTop, attempts.frame.minY) }
            for id in ["checkin.save.failure", "checkin.save.success"] {
                let result = app.descendants(matching: .any).matching(identifier: id).firstMatch
                if result.exists { footerTop = min(footerTop, result.frame.minY) }
            }
            // Start inside the visible scroll content, above the *whole* footer,
            // not in the white padding/result area above the save button.
            let bottom = min(app.frame.maxY - 110, footerTop - 28)
            let knownBars = ["컨디션 기록", "기록 수정", "함께한 사람"].map { app.navigationBars[$0].firstMatch }
            let barBottom = knownBars.first(where: { $0.exists })?.frame.maxY ?? (app.frame.minY + 162)
            let top = barBottom + 8
            let viewport = CGRect(x: app.frame.minX, y: top, width: app.frame.width, height: max(1, bottom-top))
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let hit = exists && element.isHittable
            if exists {
                if hit && frame.intersection(viewport).height >= min(44, frame.height) { return }
                if previous == frame { stalled += 1 } else { stalled = 0 }
                previous = frame
                if stalled >= 3 { break }
            }
            // A full-viewport flick can bounce a near target from above the
            // navbar to below the footer on375pt/iOS18. Stop the finger after
            // the measured required displacement instead of adding momentum.
            let available = max(44, bottom - top - 32)
            let shift: CGFloat
            if !exists { shift = -available }
            else if frame.minY < top { shift = min(available, top + 12 - frame.minY) }
            else if frame.maxY > bottom { shift = -min(available, frame.maxY - bottom + 12) }
            else { shift = frame.midY > (top + bottom)/2 ? -min(80, available) : min(80, available) }
            let x = app.frame.width * 0.5
            let startY = shift < 0 ? bottom - 16 : top + 16
            let endY = min(bottom - 16, max(top + 16, startY + shift))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: startY))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let missingName = element.exists ? element.identifier : "missing target"
        capture(app, name: "FULL APP failed reveal " + missingName)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "FULL APP synthetic failed reveal hierarchy"; tree.lifetime = .keepAlways; add(tree)
        XCTFail("Native target did not meet the visible44pt/hittable condition within18 bounded scrolls")
    }
    func testFullAppCheckInFailureRetryNormal() { fullAppCheckIn(large: false) }
    func testFullAppCheckInFailureRetryMaximumText() { fullAppCheckIn(large: true) }
}

extension ReviewDemoUITests {
    func testFullAppCompanionFailureRetryCancelPreservesActualLocalDraft() { fullAppCompanion(large: false) }
    private func fullAppCompanion(large: Bool) {
        continueAfterFailure = false; executionTimeAllowance = 240
        let app = XCUIApplication(); defer { app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["SOOM_COMPANION_FORM_QA"] = "1"
        app.launch(); uxTap(app.buttons["reviewDemo.start"], in: app)
        selectGateTab("soom.tab.profile", in: app)
        let activity = app.buttons.matching(identifier: "profile.tab.activities").allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app.buttons["profile.tab.activities"].firstMatch
        uxTap(activity, in: app); XCTAssertTrue(activity.isSelected)
        capture(app, name: "FULL APP C original profile activities before opening own workout")
        // The card root's identifier is inherited by native child buttons. Use
        // its actual semantic detail action, verified in the saved AX tree.
        let detailActions = app.buttons.matching(NSPredicate(format: "label == %@", "운동 상세 보기"))
        let card = detailActions.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? detailActions.firstMatch
        checkInReveal(card, in: app); uxTap(card, in: app)
        let edit = app.buttons.matching(NSPredicate(format: "label IN %@", ["함께한 사람 추가", "함께한 사람 편집"])).firstMatch
        checkInReveal(edit, in: app); uxTap(edit, in: app)
        XCTAssertTrue(app.navigationBars["함께한 사람"].waitForExistence(timeout: 8))
        let field = app.textFields["함께한 사람 이름 입력"]
        field.tap(); field.typeText("QA new person"); app.buttons["추가"].tap()
        let save = app.navigationBars["함께한 사람"].buttons["저장"]
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "companions.save.failure").firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["QA new person"].exists)
        XCTAssertTrue(save.isEnabled)
        capture(app, name: "FULL APP C parent action failure keeps actual sheet names")
        save.tap()
        XCTAssertTrue(app.navigationBars["함께한 사람"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["QA new person"].exists)
        capture(app, name: "FULL APP C retry actual local store reflected once in parent tags")
        let editAgain = app.buttons["함께한 사람 편집"]
        checkInReveal(editAgain, in: app); uxTap(editAgain, in: app)
        field.tap(); field.typeText("QA cancelled input")
        app.navigationBars["함께한 사람"].buttons["취소"].tap()
        uxTap(editAgain, in: app)
        XCTAssertTrue(app.staticTexts["QA new person"].exists)
        XCTAssertFalse((field.value as? String)?.contains("QA cancelled input") == true)
        capture(app, name: "FULL APP C cancel reopen preserves original tags only")
        app.navigationBars["함께한 사람"].buttons["취소"].tap()
    }
}


extension ReviewDemoUITests {
    func testFullAppR7CheckInMaximumCurrentBinary() {
        print("SOOM_FULL_APP_R7_CURRENT_BINARY_CHECKIN")
        fullAppCheckIn(large: true)
    }
    func testFullAppR7CompanionCurrentBinary() {
        print("SOOM_FULL_APP_R7_CURRENT_BINARY_COMPANION")
        testFullAppCompanionFailureRetryCancelPreservesActualLocalDraft()
    }
}


extension ReviewDemoUITests {
    func testFullAppR8CompanionMaximumCurrentBinary() {
        print("SOOM_FULL_APP_R8_CURRENT_BINARY_COMPANION_MAX")
        fullAppCompanion(large: true)
    }
    func testFullAppR8RecordFinishedOriginalFlow() {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = uxLaunch(); defer { app.terminate() }
        selectGateTab("soom.tab.record", in: app)
        uxTap(app.buttons["record.tapStart"], in: app)
        uxTap(app.buttons["record.tapConfirm"], in: app)
        XCTAssertTrue(app.staticTexts["coach.caption"].waitForExistence(timeout: 10))
        uxTap(app.buttons["일시정지"], in: app); uxTap(app.buttons["종료"], in: app); uxTap(app.buttons["운동 종료"], in: app)
        XCTAssertTrue(app.staticTexts["기록 종료"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["시작"].exists); XCTAssertTrue(app.staticTexts["종료"].exists)
        XCTAssertTrue(app.staticTexts["시간 기록"].exists)
        capture(app, name: "FULL APP F original record finish time-only NO save or share")
    }
}

extension ReviewDemoUITests {
    func testFullAppR8CompanionNormalCurrentBinary() {
        print("SOOM_FULL_APP_R8_CURRENT_BINARY_COMPANION_NORMAL")
        fullAppCompanion(large: false)
    }
}


extension ReviewDemoUITests {
    func testFullAppR9CheckInBoundedMaximumFeedback() {
        print("SOOM_FULL_APP_R9_BOUNDED_FEEDBACK")
        fullAppCheckIn(large: true)
    }
    func testFullAppR9NotificationItemScopedFailureRetry() throws {
        try testNotificationUpgradeInboxFailureReadRetryDeleteUndoAndRequestRoute()
    }
}


extension ReviewDemoUITests {
    func testFullAppR10S031MinimizedIsDistinctFromStandard() {
        continueAfterFailure = false; executionTimeAllowance = 120
        let app = XCUIApplication(); defer { app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launchEnvironment["SOOM_SYNTHETIC_UI_TESTS"] = "1"
        app.launchEnvironment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] = "1"
        app.launch()
        // Normal-layout QA starts the isolated demo automatically. It uses the
        // ordinary RootTabView and deliberately omits the space-taking banner.
        XCTAssertTrue(app.staticTexts["LAYOUT QA · 합성"].waitForExistence(timeout: 10))
        selectGateTab("soom.tab.activity", in: app); uxTap(app.buttons["activity.section.workouts"], in: app)
        capture(app, name: "S031 ordinary-root workout list before minimum-state test")
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "DEMO ·", "강변 라이딩")).firstMatch
        reveal(card, in: app); uxTap(card, in: app)
        let handle = app.buttons["상세 정보 시트"]
        XCTAssertTrue(handle.waitForExistence(timeout: 8))
        let geometry = app.staticTexts["detail.sheet.geometry"]
        XCTAssertTrue(geometry.label.contains("sheet=standard"))
        let standardY = handle.frame.minY
        let point = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        point.press(forDuration: 0.1, thenDragTo: point.withOffset(CGVector(dx: 0, dy: 180)), withVelocity: .slow, thenHoldForDuration: 0)
        let minimized = NSPredicate { _, _ in geometry.label.contains("sheet=minimized") }
        expectation(for: minimized, evaluatedWith: nil); waitForExpectations(timeout: 6)
        XCTAssertGreaterThan(handle.frame.minY, standardY + 60)
        XCTAssertFalse(app.buttons["workout.detail.collapse"].exists)
        capture(app, name: "S031 original-root MINIMIZED not standard synthetic route")
        uxTap(handle, in: app)
        XCTAssertTrue(geometry.label.contains("sheet=standard"))
        capture(app, name: "S031 minimized handle returns to standard synthetic route")
    }
}


extension ReviewDemoUITests {
    func testFullAppR10CheckInMaximumVisibleRetryText() {
        print("SOOM_FULL_APP_R10_CHECKIN_VISIBLE_CTA")
        fullAppCheckIn(large: true)
    }
}

extension ReviewDemoUITests {
    func testFullAppR10NotificationRetryHasIndependentAction() throws {
        try testNotificationUpgradeInboxFailureReadRetryDeleteUndoAndRequestRoute()
    }
}

extension ReviewDemoUITests {
    func testFullAppR11S031ActualMinimizedEntry() { testFullAppR10S031MinimizedIsDistinctFromStandard() }
    func testFullAppR11NotificationRetry44PointNativeHit() throws {
        try testNotificationUpgradeInboxFailureReadRetryDeleteUndoAndRequestRoute()
    }
}


extension ReviewDemoUITests {
    func testFullAppR12LibraryAndRepresentativeThroughOriginalSyntheticImport() {
        continueAfterFailure = false; executionTimeAllowance = 240
        let app = uxLaunch(); defer { app.terminate() }
        selectGateTab("soom.tab.activity", in: app)
        uxTap(app.buttons["activity.section.workouts"], in: app)
        // Existing public demo import route. It writes only its isolated
        // in-memory/demo stores; no HealthKit permission, login or server write.
        for _ in 0..<2 {
            uxTap(app.buttons["activity.manage"], in: app)
            uxTap(app.buttons["HealthKit 운동 가져오기"], in: app)
            let sample = app.buttons["reviewDemo.importSample"]
            XCTAssertTrue(sample.waitForExistence(timeout: 6)); uxTap(sample, in: app)
            let imported = NSPredicate { _, _ in sample.exists && !sample.isEnabled }
            expectation(for: imported, evaluatedWith: nil); waitForExpectations(timeout: 6)
            uxBack(app)
        }
        uxTap(app.buttons["activity.manage"], in: app)
        uxTap(app.buttons["운동 기록 관리"], in: app)
        XCTAssertTrue(app.navigationBars["가져온 운동 기록"].waitForExistence(timeout: 8))
        capture(app, name: "FULL APP F original container library loaded synthetic data")
        uxTap(app.buttons["중복 후보 확인"], in: app)
        XCTAssertTrue(app.navigationBars["중복 후보 검토"].waitForExistence(timeout: 6))
        let primary = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "기록을 대표로 사용")).firstMatch
        uxReveal(primary, in: app); uxTap(primary, in: app)
        uxTap(app.buttons["원본 보관하고 합치기"], in: app)
        let result = app.descendants(matching: .any).matching(identifier: "duplicates.resolution.feedback").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "대표 선택 완료")).firstMatch.exists)
        capture(app, name: "FULL APP F original container selected representative result above existing tabs synthetic only")
        XCTAssertFalse(app.staticTexts["대표 기록을 변경하지 못했어요"].exists)
    }
}

extension ReviewDemoUITests {
    func testFullAppR13CheckInNormalSoftwareKeyboardDoneDoesNotSave() { fullAppCheckIn(large: false) }
    func testFullAppR13CheckInMaximumSoftwareKeyboardDoneDoesNotSave() { fullAppCheckIn(large: true) }
}

extension ReviewDemoUITests {
    func testFullAppR14SmallNormalExplicitIsolatedRoot() { fullAppCheckIn(large: false, ordinaryLayout: true) }
    func testFullAppR14SmallMaximumExplicitIsolatedRoot() { fullAppCheckIn(large: true, ordinaryLayout: true) }
}

extension ReviewDemoUITests {
    func testFullAppR15SmallNormalBoundedAXRequests() { fullAppCheckIn(large: false, ordinaryLayout: true) }
    func testFullAppR15SmallMaximumBoundedAXRequests() { fullAppCheckIn(large: true, ordinaryLayout: true) }
}

extension ReviewDemoUITests {
    func testFullAppR16SmallNormalMeasuredPan() { fullAppCheckIn(large: false, ordinaryLayout: true) }
    func testFullAppR16SmallMaximumMeasuredPan() { fullAppCheckIn(large: true, ordinaryLayout: true) }
}


extension ReviewDemoUITests {
    private func r3CompanionReveal(_ target: XCUIElement, in app: XCUIApplication) {
        var previous = CGRect.zero; var stalled = 0
        for _ in 0..<60 {
            let bar = app.navigationBars.firstMatch
            let collapse = app.buttons["workout.detail.collapse"]
            let top = bar.exists ? bar.frame.maxY + 8 : collapse.exists ? collapse.frame.maxY + 12 : 120
            let error = app.descendants(matching: .any).matching(identifier: "companions.save.failure").firstMatch
            let bottom = error.exists ? min(app.frame.maxY - 24, error.frame.minY - 12) : app.frame.maxY - 20
            let viewport = CGRect(x: 0, y: top, width: app.frame.width, height: max(44, bottom - top))
            let exists = target.exists; let frame = exists ? target.frame : .zero
            if exists && target.isHittable && frame.intersection(viewport).height >= min(44, frame.height) - 0.001 { return }
            if exists && frame == previous { stalled += 1 } else { stalled = 0 }
            if stalled > 3 { break }; previous = frame
            let available = max(44, viewport.height - 32)
            let shift = !exists ? -available : frame.minY < top ? min(available, top + 12 - frame.minY) : -min(available, frame.maxY - viewport.maxY + 12)
            let sy = shift < 0 ? viewport.maxY - 16 : top + 16
            let ey = min(viewport.maxY - 16, max(top + 16, sy + shift))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.maxX - 8, dy: sy)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.maxX - 8, dy: ey)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        capture(app, name: "R3 companion failed visible target synthetic")
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "R3 companion failure hierarchy"; tree.lifetime = .keepAlways; add(tree)
        XCTFail("Companion target must be visible above bounded feedback: \(target.label)")
    }
    private func r3CompanionUnaddedName(large: Bool) {
        continueAfterFailure = false; executionTimeAllowance = 360
        let app = XCUIApplication(); defer { app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment = ["SOOM_SYNTHETIC_UI_TESTS":"1", "SOOM_DETAIL_NORMAL_LAYOUT_QA":"1", "SOOM_COMPANION_FORM_QA":"1",
                                 "OS_ACTIVITY_MODE":"disable", "OS_ACTIVITY_DT_MODE":"NO"]
        app.launch(); XCTAssertTrue(app.staticTexts["LAYOUT QA · 합성"].waitForExistence(timeout: 12))
        selectGateTab("soom.tab.profile", in: app)
        let tab = app.buttons.matching(identifier: "profile.tab.activities").allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app.buttons["profile.tab.activities"].firstMatch
        uxTap(tab, in: app)
        let cards = app.buttons.matching(NSPredicate(format: "label == %@", "운동 상세 보기"))
        let card = cards.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? cards.firstMatch
        uxTap(card, in: app)
        let handle = app.buttons["상세 정보 시트"]
        XCTAssertTrue(handle.waitForExistence(timeout: 8)); handle.tap()
        XCTAssertTrue(app.buttons["workout.detail.collapse"].waitForExistence(timeout: 6))
        let edit = app.buttons.matching(NSPredicate(format: "label IN %@", ["함께한 사람 추가", "함께한 사람 편집"])).firstMatch
        r3CompanionReveal(edit, in: app); edit.tap()
        let bar = app.navigationBars["함께한 사람"]
        XCTAssertTrue(bar.waitForExistence(timeout: 6))
        let field = app.textFields["함께한 사람 이름 입력"]
        r3CompanionReveal(field, in: app); field.tap(); field.typeText("R3 retained name")
        let save = bar.buttons["저장"]; save.tap()
        let failure = app.descendants(matching: .any).matching(identifier: "companions.save.failure").firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 8)); XCTAssertTrue(bar.exists)
        XCTAssertTrue((field.value as? String)?.contains("R3 retained name") == true)
        XCTAssertLessThan(failure.frame.height, app.frame.height * 0.42, "Feedback must leave the editable form reachable")
        capture(app, name: "R3 unadded name bounded feedback original sheet synthetic " + (large ? "maximum" : "normal"))
        r3CompanionReveal(field, in: app); field.tap()
        XCTAssertTrue(field.isHittable); XCTAssertTrue((field.value as? String)?.contains("R3 retained name") == true)
        if app.buttons["완료"].exists { app.buttons["완료"].tap() }
        let addButton = app.buttons["추가"]
        r3CompanionReveal(addButton, in: app); addButton.tap()
        XCTAssertFalse((field.value as? String)?.contains("R3 retained name") == true)
        save.tap(); XCTAssertTrue(failure.waitForExistence(timeout: 8)); XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(app.staticTexts["R3 retained name"].exists)
        capture(app, name: "R3 explicit add first persistence failure retains draft synthetic " + (large ? "maximum" : "normal"))
        save.tap(); XCTAssertTrue(bar.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["R3 retained name"].exists)
        capture(app, name: "R3 retry saved in original parent synthetic " + (large ? "maximum" : "normal"))
        r3CompanionReveal(edit, in: app); edit.tap(); r3CompanionReveal(field, in: app)
        field.tap(); field.typeText("R3 cancel only")
        bar.buttons["취소"].tap(); r3CompanionReveal(edit, in: app); edit.tap()
        XCTAssertFalse((field.value as? String)?.contains("R3 cancel only") == true)
        XCTAssertTrue(app.staticTexts["R3 retained name"].exists)
        capture(app, name: "R3 cancel reopen saved names only synthetic " + (large ? "maximum" : "normal"))
        bar.buttons["취소"].tap()
    }
    func testFullAppR3CompanionUnaddedNameNormal() { r3CompanionUnaddedName(large: false) }
    func testFullAppR3CompanionUnaddedNameMaximum() { r3CompanionUnaddedName(large: true) }
}


extension ReviewDemoUITests {
    func testR2VideoRouteCalendarFeedProfileReturns() {
        let app = uxLaunch(); defer { app.terminate() }
        selectGateTab("soom.tab.activity", in: app)
        uxTap(app.buttons["activity.section.workouts"], in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@ AND label CONTAINS %@", "activity.calendar", "년", "월")).firstMatch.waitForExistence(timeout: 10))
        capture(app, name: "R2 SYNTHETIC actual activity calendar initial")
        app.swipeUp(); app.swipeDown()
        selectGateTab("soom.tab.feed", in: app)
        // The actual feed.card parent identifier is propagated over article identifiers.
        let firstCardTitle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "feed.card.", "오늘의 성장 기록")).firstMatch
        XCTAssertTrue(firstCardTitle.waitForExistence(timeout: 15))
        XCTAssertTrue(firstCardTitle.isHittable)
        app.swipeUp(); app.swipeUp(); app.swipeDown(); app.swipeDown()
        capture(app, name: "R2 SYNTHETIC feed after repeated scroll")
        selectGateTab("soom.tab.profile", in: app)
        uxTap(app.buttons["profile.tab.activities"], in: app)
        XCTAssertTrue(app.staticTexts["내 운동"].firstMatch.waitForExistence(timeout: 10))
        capture(app, name: "R2 SYNTHETIC profile lazy activity cards")
        app.swipeUp(); app.swipeDown()
        uxReveal(app.buttons["profile.tab.progress"], in: app); uxTap(app.buttons["profile.tab.progress"], in: app)
        XCTAssertTrue(app.staticTexts["주간 활동"].waitForExistence(timeout: 10))
        uxTap(app.buttons["profile.tab.activities"], in: app)
        XCTAssertTrue(app.staticTexts["내 운동"].firstMatch.waitForExistence(timeout: 5))
        selectGateTab("soom.tab.activity", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@ AND label CONTAINS %@", "activity.calendar", "년", "월")).firstMatch.waitForExistence(timeout: 10))
        capture(app, name: "R2 SYNTHETIC return retains actual calendar path")
    }
    func testRankingReplacesClubWithoutFabricatedProductionResults() {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = uxLaunch(); defer { app.terminate() }
        selectGateTab("soom.tab.clubs", in: app)
        XCTAssertTrue(app.staticTexts["랭킹 연결 준비 중"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["148위"].exists)
        XCTAssertFalse(app.buttons["클럽 만들기"].exists)
        XCTAssertTrue(app.buttons["주간"].exists)
        XCTAssertTrue(app.buttons["월간"].exists)
        capture(app, name: "RANKING gate closed no fabricated live ranking")
    }

    func testRankingSyntheticReferenceLayoutAndFilters() {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = uxLaunch(environment: ["SOOM_RANKING_LAYOUT_QA":"1"]); defer { app.terminate() }
        uxTap(visibleGateButton("soom.tab.clubs", in: app), in: app)
        XCTAssertTrue(app.staticTexts["현재 순위"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["148위 · 4시간 12분"].exists)
        capture(app, name: "RANKING SYNTHETIC reference layout no live users")
        uxTap(app.buttons["거리"], in: app)
        XCTAssertTrue(app.staticTexts["148위 · 25.20 km"].waitForExistence(timeout: 5))
        uxTap(app.buttons["월간"], in: app)
        XCTAssertTrue(app.staticTexts["현재 순위"].exists)
        app.swipeUp()
        capture(app, name: "RANKING SYNTHETIC nearby and top list")
    }

    func testRankingBadgeMotionPreviewNeverClaimsAnEarnedTier() {
        continueAfterFailure = false
        let app = uxLaunch(environment: ["SOOM_RANKING_LAYOUT_QA":"1"]); defer { app.terminate() }
        uxTap(visibleGateButton("soom.tab.clubs", in: app), in: app)
        uxTap(app.buttons["ranking.badge.preview"], in: app)
        XCTAssertTrue(app.staticTexts["동작 미리보기 · 실제 획득한 등급이 아닙니다"].waitForExistence(timeout: 5))
        capture(app, name: "RANKING badge visual preview no earned tier")
        uxTap(app.buttons["닫기"], in: app)
        XCTAssertTrue(app.buttons["ranking.badge.preview"].waitForExistence(timeout: 5))
    }

    func testAnnualBadgePolicyIsNotAnEarnedAward() {
        continueAfterFailure = false
        let app = uxLaunch(environment: ["SOOM_RANKING_LAYOUT_QA":"1"]); defer { app.terminate() }
        uxTap(visibleGateButton("soom.tab.clubs", in: app), in: app)
        uxTap(app.buttons["ranking.badge.policy"], in: app)
        XCTAssertTrue(app.staticTexts["유효 운동 1시간당 10점 · 시간 상한 없음"].waitForExistence(timeout: 5))
        capture(app, name: "ANNUAL BADGE approved policy not earned")
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["점수 집계와 획득 이력 연결 준비 중입니다. 이 화면은 승인된 기준 안내이며 실제 획득 배지가 아닙니다."].exists)
        capture(app, name: "ANNUAL BADGE unconfirmed ledger notice")
    }

    func testAnnualBadgeCandidateHistoryCannotClaimConfirmedAward() {
        continueAfterFailure = false
        let app = uxLaunch(environment: ["SOOM_RANKING_LAYOUT_QA":"1","SOOM_ANNUAL_BADGE_QA":"1"]); defer { app.terminate() }
        uxTap(visibleGateButton("soom.tab.clubs", in: app), in: app)
        uxTap(app.buttons["ranking.badge.history.open"], in: app)
        XCTAssertTrue(app.staticTexts["로컬 원장 연결 검증 · 확정 획득 이력이 아닙니다."].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["후보 기준 충족"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["사용자 제공 운동 · 서버 형식·중복 검증 기준입니다. 운동 내용의 진위를 검증한 결과는 아닙니다."].exists)
        capture(app,name:"ANNUAL BADGE candidate year history not confirmed")
    }

}

extension ReviewDemoUITests {
    private func pagingFooterQA(_ mode: String) {
        let app = uxLaunch(environment: ["SOOM_PAGING_QA": mode]); defer { app.terminate() }
        uxTap(app.buttons["reviewDemo.pagingQA"], in: app)
        let status = app.staticTexts["pagingQA.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        if mode != "empty" {
            XCTAssertTrue(status.label.contains("following 0"))
        }
        for _ in 0..<24 {
            if status.label.contains("following 8") { break }
            app.swipeUp()
        }
        XCTAssertTrue(status.label.contains("following 8"), "Real FeedView footer must request and render following page: \(status.label)")
        let target = app.descendants(matching: .any).matching(identifier: "feed.card.D4900000-0000-4000-8000-000000000100").firstMatch
        for _ in 0..<8 { if target.exists { break }; app.swipeUp() }
        XCTAssertTrue(target.exists, "View-model counts alone do not establish a rendered card")
        capture(app, name: "49 SYNTHETIC actual FeedView footer " + mode)
    }
    func testPaging49ActualFooterLoadsFollowingAfterFirstEight() { pagingFooterQA("normal") }
    func testPaging49ActualFooterDrainsEmptyFilteredPages() { pagingFooterQA("empty") }
    func testPaging49ActualFooterContinuesSameLastVisibleID() { pagingFooterQA("same") }
}


extension ReviewDemoUITests {
    func testPaging49ActualFooterResumesAfterRapidActiveRoundTrip() {
        let app = uxLaunch(environment: ["SOOM_PAGING_QA": "cancel"]); defer { app.terminate() }
        uxTap(app.buttons["reviewDemo.pagingQA"], in: app)
        let status = app.staticTexts["pagingQA.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        for _ in 0..<24 { if status.label.contains("busy true") { break }; app.swipeUp() }
        XCTAssertTrue(status.label.contains("busy true"))
        app.buttons["pagingQA.bounce"].tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "following 8"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 15), .completed)
        XCTAssertTrue(status.label.contains("calls 3"), "Cancelled page must retry same cursor rather than advance")
        capture(app, name: "49 SYNTHETIC actual footer cancellation rapid active round trip")
    }
}


extension ReviewDemoUITests {
    func testFeed50VisibleDatesAndOrderUseOwnerStartNotLatePublication() {
        let app = uxLaunch(environment: ["SOOM_PAGING_QA": "start-order"]); defer { app.terminate() }
        uxTap(app.buttons["reviewDemo.pagingQA"], in: app)
        let newer = app.buttons.matching(NSPredicate(format: "label == %@", "Newer following start")).firstMatch
        let older = app.buttons.matching(NSPredicate(format: "label == %@", "Older owner start")).firstMatch
        XCTAssertTrue(newer.waitForExistence(timeout: 10))
        for _ in 0..<5 { if older.exists { break }; app.swipeUp() }
        XCTAssertTrue(older.exists)
        XCTAssertLessThan(newer.frame.minY, older.frame.minY, "A late-published older workout must be below the newer start")
        let newerDate = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2026-11-11")).firstMatch
        let olderDate = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2026-11-10")).firstMatch
        XCTAssertTrue(newerDate.exists, "Following visible date must retain its own start date")
        XCTAssertTrue(olderDate.exists, "Owner visible date must use verified canonical start, not Nov 12 publication")
        XCTAssertLessThan(newerDate.frame.minY, newer.frame.minY)
        XCTAssertGreaterThan(olderDate.frame.minY, newer.frame.maxY)
        XCTAssertLessThan(olderDate.frame.minY, older.frame.minY)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2026-11-12")).firstMatch.exists)
        capture(app, name: "50 SYNTHETIC visible start dates match descending card order")
    }
}

extension ReviewDemoUITests {
    func testProfileOnlyScopeSwitchPreservesMeasurementChoiceAndRetriesFailedSave() {
        let app=uxLaunch();defer{app.terminate()}
        tap(app.buttons["reviewDemo.privacyQA"],in:app)
        tap(app.buttons["qa.profileOnly.open"],in:app)
        XCTAssertTrue(app.navigationBars["프로필 규칙 v2 QA"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["privacy.workout.public"].exists)
        XCTAssertFalse(app.buttons["privacy.workout.followers"].exists)
        XCTAssertFalse(app.switches.firstMatch.exists)
        tap(app.buttons["privacy.choice.private"],in:app)
        reveal(app.buttons["privacy.save"],in:app);tap(app.buttons["privacy.save"],in:app)
        let saved=app.staticTexts["qa.profileOnly.saved"]
        func expectSaves(_ count:Int) {
            let expectation=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@","저장 \(count)회"),object:saved)
            XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:6),.completed)
        }
        expectSaves(1)
        XCTAssertTrue(app.staticTexts["privacy.profileOnly.measurements"].label.contains("꺼짐"))
        for _ in 0..<3 {if app.buttons["privacy.choice.public"].isHittable{break};app.swipeDown()}
        XCTAssertTrue(app.buttons["privacy.choice.public"].isEnabled,"A private profile can explicitly return to public under v2")
        tap(app.buttons["privacy.choice.public"],in:app)
        reveal(app.buttons["privacy.save"],in:app);tap(app.buttons["privacy.save"],in:app)
        expectSaves(2)
        XCTAssertTrue(app.staticTexts["privacy.profileOnly.measurements"].label.contains("꺼짐"))
        capture(app,name:"Profile-only v2 public-private round trip without measurement consent changes")
        for _ in 0..<4 {if app.buttons["qa.profileOnly.fail"].isHittable{break};app.swipeDown()}
        tap(app.buttons["qa.profileOnly.fail"],in:app)
        tap(app.buttons["privacy.choice.private"],in:app)
        reveal(app.buttons["privacy.save"],in:app);tap(app.buttons["privacy.save"],in:app)
        XCTAssertTrue(app.staticTexts["저장을 확인하지 못했어요. 공개범위를 다시 불러온 뒤 선택해 주세요."].waitForExistence(timeout:6))
        XCTAssertFalse(app.buttons["privacy.save"].isEnabled)
        tap(app.buttons["공개범위 다시 불러오기"],in:app)
        for _ in 0..<4 {if app.buttons["privacy.choice.private"].isHittable{break};app.swipeDown()}
        tap(app.buttons["privacy.choice.private"],in:app)
        reveal(app.buttons["privacy.save"],in:app);tap(app.buttons["privacy.save"],in:app)
        expectSaves(3)
        XCTAssertTrue(app.staticTexts["privacy.profileOnly.measurements"].label.contains("꺼짐"))
        capture(app,name:"Profile-only v2 failure fresh reload and retry with unchanged originals")
    }
}


extension ReviewDemoUITests {
    func testProfileOnlyMeasurementWithdrawalCancelThenConfirmPreservesProfile() {
        let app=uxLaunch();defer{app.terminate()}
        tap(app.buttons["reviewDemo.privacyQA"],in:app)
        tap(app.buttons["qa.profileOnly.open"],in:app)
        tap(app.buttons["qa.profileOnly.measurementsOn"],in:app)
        let label=app.staticTexts["privacy.profileOnly.measurements"]
        reveal(label,in:app);XCTAssertTrue(label.label.contains("켜짐"))
        XCTAssertTrue(app.buttons["privacy.measurements.withdraw"].isEnabled)
        tap(app.buttons["privacy.measurements.withdraw"],in:app)
        capture(app,name:"Measurement withdrawal confirmation before cancel")
        tap(app.buttons["취소"],in:app);XCTAssertTrue(label.label.contains("켜짐"))
        tap(app.buttons["privacy.measurements.withdraw"],in:app)
        tap(app.buttons["공유 중지"],in:app)
        let off=NSPredicate(format:"label CONTAINS %@","꺼짐")
        expectation(for:off,evaluatedWith:label);waitForExpectations(timeout:6)
        XCTAssertFalse(app.buttons["privacy.measurements.withdraw"].exists)
        reveal(app.buttons["privacy.choice.public"],in:app)
        XCTAssertEqual(app.buttons["privacy.choice.public"].value as? String,"선택됨")
        capture(app,name:"Explicit measurement withdrawal preserves public profile and local originals")
    }
}


extension ReviewDemoUITests {
    func testRemoteProfileProgressNamesPartialScopeAndLoadsRemainingPosts() {
        let app = uxLaunch(environment: ["SOOM_UX_POST_COUNT": "9"]); defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app)
        let posts = element("profile.social.posts", in: app)
        expectation(for: NSPredicate { _, _ in Int(posts.value as? String ?? "") == 9 }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        uxTap(posts, in: app)
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].waitForExistence(timeout: 10))
        uxTap(app.buttons["profile.tab.progress"].firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["최근 불러온 8개 운동 기준 · 전체 기록 합계가 아니에요"].waitForExistence(timeout: 5))
        let more = app.buttons["profile.remote.loadMore"]
        uxReveal(more, in: app); uxTap(more, in: app)
        XCTAssertTrue(app.staticTexts["현재 계정으로 볼 수 있는 운동 기준"].waitForExistence(timeout: 8))
        XCTAssertFalse(more.exists)
        uxReveal(app.buttons["profile.tab.activities"].firstMatch, in: app)
        uxTap(app.buttons["profile.tab.activities"].firstMatch, in: app)
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.sharedPost."))
        XCTAssertEqual(cards.count, 9)
        capture(app, name: "Profile authorized pagination retains all nine posts after tab changes")
    }
    func testRemoteProfileInitialLoadingDoesNotClaimZeroActivity() {
        let app = uxLaunch(environment: ["SOOM_UX_POST_COUNT": "9", "SOOM_REMOTE_PROFILE_LOADING_QA": "1"])
        defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app)
        let posts = element("profile.social.posts", in: app)
        expectation(for: NSPredicate { _, _ in Int(posts.value as? String ?? "") == 9 }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        uxTap(posts, in: app)
        XCTAssertTrue(element("skeleton.profile", in: app).waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["접근 가능한 운동이 아직 없어요."].exists)
        XCTAssertFalse(app.staticTexts["0회"].exists)
        XCTAssertFalse(app.staticTexts["불러온 운동 0개"].exists)
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.sharedPost.")).count, 8)
        capture(app, name: "Profile loading resolves without a false empty activity state")
    }
}


extension ReviewDemoUITests {
    func testRemoteProfileCanceledFirstVisitCanReopenAndFinish() {
        let app = uxLaunch(environment: ["SOOM_UX_POST_COUNT": "9", "SOOM_REMOTE_PROFILE_LOADING_QA": "1"])
        defer { app.terminate() }
        uxTap(app.buttons["soom.tab.profile"], in: app)
        let posts = element("profile.social.posts", in: app)
        expectation(for: NSPredicate { _, _ in Int(posts.value as? String ?? "") == 9 }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        uxTap(posts, in: app)
        XCTAssertTrue(element("skeleton.profile", in: app).waitForExistence(timeout: 2))
        uxBack(app)
        XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 5))
        uxTap(posts, in: app)
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.sharedPost.")).count, 8)
        capture(app, name: "Profile canceled first request reopens and completes")
    }
}


extension ReviewDemoUITests {
    func testRemoteProfileSameAuthorDoesNotOpenNestedProfile() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA": "1", "SOOM_NATIVE_COMMENT_QA": "1"])
        defer { app.terminate() }
        let author = app.buttons["데모 운동 기록 프로필 보기"].firstMatch
        uxReveal(author, in: app); tap(author, in: app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout: 8))
        let activities = app.buttons.matching(identifier: "profile.tab.activities").allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(activities)
        if let activities { tap(activities, in: app) }
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].waitForExistence(timeout: 8))
        let staticAuthor = app.staticTexts.matching(NSPredicate(format: "label == %@", "데모 운동 기록")).firstMatch
        uxReveal(staticAuthor, in: app)
        XCTAssertTrue(staticAuthor.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "데모 운동 기록 프로필 보기")).allElementsBoundByIndex.filter(\.isHittable).isEmpty)
        let headerPoint = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: staticAuthor.frame.midX, dy: staticAuthor.frame.midY))
        headerPoint.tap()
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].exists)
        let secondHeaderPoint = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: staticAuthor.frame.midX, dy: staticAuthor.frame.midY))
        secondHeaderPoint.tap()
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].exists)
        XCTAssertEqual(app.navigationBars.matching(identifier: "프로필").allElementsBoundByIndex.filter(\.isHittable).count, 1)
        let detail = app.buttons.matching(NSPredicate(format: "label == %@", "러닝 기록")).allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(detail)
        if let detail { tap(detail, in: app) }
        XCTAssertTrue(app.navigationBars["운동 상세"].waitForExistence(timeout: 8))
        tap(app.navigationBars["운동 상세"].buttons.element(boundBy: 0), in: app)
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].waitForExistence(timeout: 8))
        capture(app, name: "Same author stays in one profile while workout detail still opens and returns")
    }
}

extension ReviewDemoUITests {
    func testProfileSocialLinkedWithoutSnapshotCheerBadgeAndParticipants() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_SOCIAL_QA":"1", "SOOM_PROJECTION_LEGACY_NO_DETAIL_QA":"1"])
        defer { app.terminate() }
        let cheer = app.buttons["feed.projection.cheer"].firstMatch
        uxReveal(cheer, in: app)
        expectation(for: NSPredicate(format:"enabled == true"), evaluatedWith:cheer)
        waitForExpectations(timeout:12)
        let comments = app.buttons["feed.projection.comments"].firstMatch
        XCTAssertEqual(comments.value as? String,"최근 댓글 있음")
        XCTAssertEqual(cheer.label,"응원")
        tap(cheer,in:app)
        expectation(for:NSPredicate(format:"label == %@","응원 취소"),evaluatedWith:cheer)
        waitForExpectations(timeout:8)
        capture(app,name:"SYNTHETIC profile social linked snapshot zero cheer and badge")
        cheer.press(forDuration:1)
        tap(app.buttons["응원한 사람 보기"],in:app)
        XCTAssertTrue(app.navigationBars["응원"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["나"].waitForExistence(timeout:8))
        capture(app,name:"SYNTHETIC profile scoped cheer participants")
        tap(app.buttons["닫기"],in:app)
        tap(cheer,in:app)
        expectation(for:NSPredicate(format:"label == %@","응원"),evaluatedWith:cheer)
        waitForExpectations(timeout:8)
    }

    func testProfileSocialReplyMentionAndAuthorlessDeletion() {
        let app = uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1"])
        defer { app.terminate() }
        let comments = app.buttons["feed.projection.comments"].firstMatch
        uxReveal(comments,in:app); tap(comments,in:app)
        XCTAssertTrue(app.staticTexts["함께 응원해요"].waitForExistence(timeout:10))
        tap(app.buttons["답글 달기"].firstMatch,in:app)
        let input = app.textFields["feed.comment.input"]
        tap(input,in:app); input.typeText("reply proof")
        tap(app.buttons["댓글 보내기"],in:app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","reply proof")).firstMatch.waitForExistence(timeout:8))
        let search = app.textFields["feed.mention.search"]
        tap(search,in:app); search.typeText("soom")
        let candidate = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","soom_test")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout:8)); tap(candidate,in:app)
        tap(input,in:app); input.typeText("mention proof")
        tap(app.buttons["댓글 보내기"],in:app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","mention proof")).firstMatch.waitForExistence(timeout:8))
        capture(app,name:"SYNTHETIC profile scoped reply and selected mention")
        let delete = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","feed.comment.delete.")).firstMatch
        uxReveal(delete,in:app); tap(delete,in:app)
        tap(app.sheets["이 댓글을 삭제할까요?"].buttons["feed.comment.delete.confirm"].firstMatch,in:app)
        XCTAssertTrue(app.staticTexts["삭제된 댓글입니다"].waitForExistence(timeout:8))
        capture(app,name:"SYNTHETIC profile social authorless tombstone preserves replies")
    }

    func testProfileSocialUncertainCommitRecoversWithoutNewRequest() {
        let app = uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1","SOOM_PROFILE_SOCIAL_TIMEOUT_QA":"1"])
        defer { app.terminate() }
        let comments = app.buttons["feed.projection.comments"].firstMatch
        uxReveal(comments,in:app); tap(comments,in:app)
        XCTAssertTrue(app.staticTexts["함께 응원해요"].waitForExistence(timeout:10))
        let input = app.textFields["feed.comment.input"]
        tap(input,in:app); input.typeText("one uncertain request")
        tap(app.buttons["댓글 보내기"],in:app)
        let recover = app.buttons["feed.profileSocial.recover"]
        XCTAssertTrue(recover.waitForExistence(timeout:8))
        capture(app,name:"SYNTHETIC committed timeout retains original request")
        tap(recover,in:app)
        XCTAssertTrue(app.staticTexts["one uncertain request"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts.matching(identifier:"one uncertain request").count,1)
        let sheet = app.descendants(matching:.any)["feed.profileSocial.comments"].firstMatch
        XCTAssertEqual(sheet.value as? String,"mutations 1, status 1, requests 1")
        XCTAssertFalse(recover.exists)
        capture(app,name:"SYNTHETIC uncertain recovery verifies same ID without replay")
    }

    func testProfileSocialRevocationImmediatelyRemovesConversation() {
        let app = uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1","SOOM_PROFILE_SOCIAL_BOUNDARY_QA":"1"])
        defer { app.terminate() }
        let comments = app.buttons["feed.projection.comments"].firstMatch
        uxReveal(comments,in:app); tap(comments,in:app)
        XCTAssertTrue(app.staticTexts["함께 응원해요"].waitForExistence(timeout:10))
        tap(app.buttons["feed.profileSocial.qa.revoke"],in:app)
        let hidden = NSPredicate { _,_ in !app.staticTexts["함께 응원해요"].exists }
        expectation(for:hidden,evaluatedWith:nil);waitForExpectations(timeout:8)
        XCTAssertFalse(app.buttons["댓글 보내기"].isEnabled)
        XCTAssertTrue(app.buttons["댓글 다시 확인"].waitForExistence(timeout:8))
        capture(app,name:"SYNTHETIC profile social revocation hides rows and disables writes")
        tap(app.buttons["댓글 다시 확인"],in:app)
        XCTAssertFalse(app.staticTexts["함께 응원해요"].exists)
    }
}

extension ReviewDemoUITests {
    func testProfileSocialInboxReadHideUndoPreservesOtherSourceState() {
        let app = uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1","SOOM_PROFILE_SOCIAL_INBOX_QA":"1"])
        defer { app.terminate() }
        scrollToInboxHeader(app); tap(app.buttons["알림"],in:app)
        XCTAssertTrue(app.navigationBars["알림"].waitForExistence(timeout:10))
        let item = app.buttons["notifications.profileSocial.row.profile_social_v2:00000000-0000-4000-8000-000000000163"]
        let legacy = app.buttons["notifications.profileSocial.row.legacy:00000000-0000-4000-8000-000000000165"]
        uxReveal(item,in:app); XCTAssertTrue(item.waitForExistence(timeout:10))
        XCTAssertEqual(item.value as? String,"읽지 않음")
        uxReveal(legacy,in:app); XCTAssertEqual(legacy.value as? String,"읽음")
        uxReveal(item,in:app); item.press(forDuration:1)
        tap(app.buttons["읽음으로 표시"],in:app)
        expectation(for:NSPredicate(format:"value == %@","읽음"),evaluatedWith:item); waitForExpectations(timeout:8)
        capture(app,name:"SYNTHETIC profile inbox current event read original legacy state retained")
        item.press(forDuration:1); tap(app.buttons["알림 숨기기"],in:app)
        expectation(for:NSPredicate { _,_ in !item.exists },evaluatedWith:nil); waitForExpectations(timeout:8)
        let undo = app.buttons["notifications.profileSocial.undo"]
        uxReveal(undo,in:app); XCTAssertTrue(undo.waitForExistence(timeout:8))
        capture(app,name:"SYNTHETIC profile inbox hide keeps reversible event identity")
        tap(undo,in:app)
        XCTAssertTrue(item.waitForExistence(timeout:8)); uxReveal(item,in:app)
        XCTAssertEqual(item.value as? String,"읽음")
        uxReveal(legacy,in:app); XCTAssertEqual(legacy.value as? String,"읽음")
        uxReveal(item,in:app); item.press(forDuration:1); tap(app.buttons["읽지 않음으로 표시"],in:app)
        expectation(for:NSPredicate(format:"value == %@","읽지 않음"),evaluatedWith:item); waitForExpectations(timeout:8)
        capture(app,name:"SYNTHETIC profile inbox undo preserves read state and source isolation")
    }

    func testProfileSocialInboxOpensCardScopedCommentsWithoutLegacyDetail() {
        let app = uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1","SOOM_PROFILE_SOCIAL_INBOX_QA":"1"])
        defer { app.terminate() }
        scrollToInboxHeader(app); tap(app.buttons["알림"],in:app)
        let item = app.buttons["notifications.profileSocial.row.profile_social_v2:00000000-0000-4000-8000-000000000163"]
        uxReveal(item,in:app); XCTAssertTrue(item.waitForExistence(timeout:10)); tap(item,in:app)
        XCTAssertTrue(app.navigationBars["댓글"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["함께 응원해요"].waitForExistence(timeout:10))
        XCTAssertFalse(app.navigationBars["운동 상세"].exists)
        capture(app,name:"SYNTHETIC profile inbox fresh card scoped comment destination")
        tap(app.buttons["닫기"],in:app)
        XCTAssertTrue(app.navigationBars["알림"].waitForExistence(timeout:8))
        uxReveal(item,in:app); XCTAssertEqual(item.value as? String,"읽음")
        let legacy = app.buttons["notifications.profileSocial.row.legacy:00000000-0000-4000-8000-000000000165"]
        uxReveal(legacy,in:app); XCTAssertEqual(legacy.value as? String,"읽음")
        capture(app,name:"SYNTHETIC profile inbox returning retains other source state")
    }
}


extension ReviewDemoUITests {
    func testMixedSocialSameOriginalIDPreservesBothSourcesAndDeletesOnlyOwnNative() {
        let app = uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1","SOOM_PROFILE_SOCIAL_MIXED_QA":"1"])
        defer { app.terminate() }
        let comments = app.buttons["feed.projection.comments"].firstMatch
        uxReveal(comments,in:app); tap(comments,in:app)
        XCTAssertTrue(app.staticTexts["함께 응원해요"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["원본 native 대화"].waitForExistence(timeout:10))
        XCTAssertLessThan(app.staticTexts["함께 응원해요"].frame.minY, app.staticTexts["원본 native 대화"].frame.minY)
        capture(app,name:"SYNTHETIC mixed same original UUID preserves distinct time ordered conversations")
        let remove = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","feed.comment.delete.")).firstMatch
        uxReveal(remove,in:app); tap(remove,in:app)
        tap(app.sheets["이 댓글을 삭제할까요?"].buttons["feed.comment.delete.confirm"].firstMatch,in:app)
        XCTAssertTrue(app.staticTexts["삭제된 댓글입니다"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["함께 응원해요"].exists)
        XCTAssertFalse(app.staticTexts["원본 native 대화"].exists)
        capture(app,name:"SYNTHETIC mixed native delete retains legacy same UUID original")
    }
}


extension ReviewDemoUITests {
    func testProfileNavigationCommentsPushAndBackPreservesOriginalProfile() {
        let app = uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1","SOOM_NATIVE_COMMENT_QA":"1","SOOM_PROFILE_NAVIGATION_QA":"1"])
        defer { app.terminate() }
        let author=app.buttons["데모 운동 기록 프로필 보기"].firstMatch
        uxReveal(author,in:app);tap(author,in:app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:10))
        let activities=app.buttons.matching(identifier:"profile.tab.activities").allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(activities);if let activities { tap(activities,in:app) }
        XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].waitForExistence(timeout:10))
        let profileCardID="profile.sharedPost.A9110000-0000-4000-8000-000000000777"
        let profileCard=app.otherElements[profileCardID]
        let profileScroll=app.scrollViews.containing(.other,identifier:profileCardID).firstMatch
        for visit in 0..<2 {
            let comments=profileCard.buttons["feed.projection.comments"]
            for _ in 0..<6 {
                if comments.exists && comments.isHittable { break }
                XCTAssertTrue(profileScroll.exists);profileScroll.swipeUp()
            }
            XCTAssertTrue(comments.isHittable)
            let originalButtonFrame=comments.frame
            let originalProfileBarFrame=app.navigationBars["프로필"].frame
            let originalProbe = app.descendants(matching:.any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.navigation.probe.")).allElementsBoundByIndex.first(where: { app.frame.intersects($0.frame) && $0.frame.width > 0 })?.label
            XCTAssertNotNil(originalProbe)
            tap(comments,in:app)
            XCTAssertTrue(app.staticTexts["함께 응원해요"].waitForExistence(timeout:10))
            tap(app.buttons.matching(identifier:"댓글 작성자 프로필").firstMatch,in:app)
            XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:10))
            XCTAssertFalse(app.buttons["feed.comment.independentProfile.close"].exists)
            XCTAssertFalse(app.navigationBars["댓글"].exists)
            let back = app.navigationBars["프로필"].buttons.firstMatch
            XCTAssertTrue(back.isHittable)
            capture(app,name:"Profile standard push visit \(visit)")
            if visit == 0 { tap(back,in:app) }
            else { app.swipeRight() }
            XCTAssertTrue(profileCard.waitForExistence(timeout:10))
            XCTAssertTrue(comments.isHittable)
            XCTAssertEqual(comments.frame.minY,originalButtonFrame.minY,accuracy:4)
            XCTAssertEqual(app.navigationBars["프로필"].frame.minY,originalProfileBarFrame.minY,accuracy:4)
            let restoredProbe = app.descendants(matching:.any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.navigation.probe.")).allElementsBoundByIndex.first(where: { app.frame.intersects($0.frame) && $0.frame.width > 0 })?.label
            XCTAssertEqual(originalProbe, restoredProbe, "Back must reuse the same profile instance, tab and completed load")
            XCTAssertFalse(app.navigationBars["댓글"].exists)
        }
        capture(app,name:"Standard Back restores exact original profile activities without reload")
    }
    func testProfileNavigationInboxAuthorPushReturnsToInbox() {
        let app=uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1","SOOM_PROFILE_SOCIAL_INBOX_QA":"1","SOOM_PROFILE_NAVIGATION_QA":"1"])
        defer { app.terminate() }
        scrollToInboxHeader(app);tap(app.buttons["알림"],in:app)
        let event=app.buttons["notifications.profileSocial.row.profile_social_v2:00000000-0000-4000-8000-000000000163"]
        uxReveal(event,in:app);tap(event,in:app)
        XCTAssertTrue(app.staticTexts["함께 응원해요"].waitForExistence(timeout:10))
        tap(app.buttons.matching(identifier:"댓글 작성자 프로필").firstMatch,in:app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["feed.comment.independentProfile.close"].exists)
        XCTAssertFalse(app.navigationBars["댓글"].exists)
        let back = app.navigationBars["프로필"].buttons.firstMatch
        XCTAssertTrue(back.isHittable)
        capture(app,name:"Inbox author opens shared standard profile destination")
        tap(back,in:app);XCTAssertTrue(app.navigationBars["알림"].waitForExistence(timeout:10))
        XCTAssertTrue(event.waitForExistence(timeout:8));XCTAssertFalse(app.navigationBars["댓글"].exists)
    }
}

extension ReviewDemoUITests {
    func testProfileNavigationForegroundRecheckPreservesInstanceAndPreviewGrant() {
        profileNavigationRevalidation(finalDenied: false)
    }
    func testProfileNavigationFinalDenialRemovesProtectedProfile() {
        profileNavigationRevalidation(finalDenied: true)
    }
    private func profileNavigationRevalidation(finalDenied: Bool) {
        var flags = ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_SOCIAL_QA":"1", "SOOM_PROFILE_NAVIGATION_QA":"1", "SOOM_DETAIL_REVALIDATION_QA":"1"]
        if finalDenied { flags["SOOM_DETAIL_REVALIDATION_FAIL"] = "1" }
        let app = uxLaunch(environment: flags); defer { app.terminate() }
        let author = app.buttons["데모 운동 기록 프로필 보기"].firstMatch
        uxReveal(author,in:app); tap(author,in:app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:10))
        let activities = app.buttons["profile.tab.activities"]
        tap(activities,in:app)
        let probe = app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@", "profile.navigation.probe.")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout:8))
        let before = probe.label
        XCTAssertTrue(before.contains("preview=true"))
        let instance = before.components(separatedBy:";").first
        XCUIDevice.shared.press(.home); app.activate()
        let release = app.buttons["profile.navigation.qa.finishCheck"]
        XCTAssertTrue(release.waitForExistence(timeout:8))
        XCTAssertTrue(element("social.checking",in:app).exists)
        capture(app,name:"Held fresh permission check excludes profile pixels and AX before release")
        let heldTree = XCTAttachment(string: app.debugDescription)
        heldTree.name = "Held permission check complete hierarchy"
        heldTree.lifetime = .keepAlways; add(heldTree)
        XCTAssertFalse(app.staticTexts["profile.sharedPosts.title"].exists)
        XCTAssertFalse(probe.exists)
        tap(release,in:app)
        if finalDenied {
            XCTAssertTrue(element("social.locked",in:app).waitForExistence(timeout:10))
            XCTAssertFalse(app.staticTexts["profile.sharedPosts.title"].exists)
            XCTAssertFalse(probe.exists)
            tap(app.buttons["profile.navigation.qa.regrant"],in:app)
            XCTAssertTrue(author.waitForExistence(timeout:12))
            XCTAssertFalse(app.navigationBars["프로필"].exists, "Final denial must not resurrect the old protected route after a fresh grant")
            tap(author,in:app)
            XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:10))
        } else {
            XCTAssertTrue(app.staticTexts["profile.sharedPosts.title"].waitForExistence(timeout:12))
            XCTAssertTrue(probe.waitForExistence(timeout:8))
            XCTAssertEqual(probe.label.components(separatedBy:";").first,instance)
            XCTAssertTrue(probe.label.contains("preview=true"))
            XCTAssertTrue(activities.isSelected)
            tap(app.navigationBars["프로필"].buttons.firstMatch,in:app)
            XCTAssertTrue(author.waitForExistence(timeout:8))
        }
        capture(app,name:finalDenied ? "Profile final denial hides content and clears protected route" : "Profile same-account check masks then restores original instance and tab")
    }
}

extension ReviewDemoUITests {
    func testProfileNavigationCheerParticipantPushReturnsToOriginalCard() {
        let app=uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1","SOOM_PROFILE_NAVIGATION_QA":"1"])
        defer { app.terminate() }
        let cheer=app.buttons["feed.projection.cheer"].firstMatch
        uxReveal(cheer,in:app); tap(cheer,in:app)
        XCTAssertEqual(cheer.label,"응원 취소")
        cheer.press(forDuration:1);tap(app.buttons["응원한 사람 보기"],in:app)
        XCTAssertTrue(app.navigationBars["응원"].waitForExistence(timeout:8))
        let person=app.buttons["나"]
        XCTAssertTrue(person.waitForExistence(timeout:8));XCTAssertTrue(person.isEnabled);tap(person,in:app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:10))
        XCTAssertFalse(app.navigationBars["응원"].exists)
        tap(app.navigationBars["프로필"].buttons.firstMatch,in:app)
        XCTAssertTrue(cheer.waitForExistence(timeout:8));XCTAssertTrue(cheer.isHittable)
        capture(app,name:"Cheer modal hands off to ordinary profile and Back preserves original card")
    }
    func testProfileNavigationSearchAndSavedListsUseBackAndKeepQuery() {
        let app=uxLaunch(environment:["SOOM_PROFILE_NAVIGATION_QA":"1"]);defer{app.terminate()}
        tap(app.buttons["검색"].firstMatch,in:app)
        XCTAssertTrue(app.navigationBars["검색"].waitForExistence(timeout:8))
        let query=app.searchFields.firstMatch;tap(query,in:app);query.typeText("original query\n")
        tap(app.buttons["profile.search.open"],in:app)
        let people=app.searchFields.firstMatch;tap(people,in:app);people.typeText("demo_minseo\n")
        let person=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","민서 · Demo")).firstMatch
        XCTAssertTrue(person.waitForExistence(timeout:10));tap(person,in:app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:8))
        tap(app.navigationBars["프로필"].buttons.firstMatch,in:app)
        XCTAssertTrue(app.navigationBars["사용자 검색"].waitForExistence(timeout:8))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String,"demo_minseo")
        // Native active-search chrome replaces Back until editing is ended.
        // Query preservation above is checked before invoking that system action.
        func endNativeSearchEditing(in bar: XCUIElement) {
            let endSearch = bar.buttons["Close"]
            let cancelSearch = app.buttons.matching(NSPredicate(format:"label IN %@", ["Cancel", "취소"])).firstMatch
            if endSearch.exists && endSearch.isHittable { tap(endSearch,in:app) }
            else if cancelSearch.exists && cancelSearch.isHittable { tap(cancelSearch,in:app) }
        }
        let userBar = app.navigationBars["사용자 검색"]
        endNativeSearchEditing(in: userBar)
        let userBack = userBar.buttons["BackButton"].exists ? userBar.buttons["BackButton"] : userBar.buttons["검색"]
        tap(userBack,in:app)
        XCTAssertTrue(app.navigationBars["검색"].waitForExistence(timeout:8))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String,"original query")
        endNativeSearchEditing(in: app.navigationBars["검색"])
        tap(app.navigationBars["검색"].buttons["BackButton"],in:app)
        tap(app.buttons["저장한 기록"],in:app)
        XCTAssertTrue(app.buttons["피드에서 저장한 글"].waitForExistence(timeout:8))
        tap(app.buttons["피드에서 저장한 글"],in:app)
        XCTAssertTrue(app.navigationBars["저장한 글"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["닫기"].exists)
        tap(app.navigationBars["저장한 글"].buttons["BackButton"],in:app)
        XCTAssertTrue(app.buttons["피드에서 저장한 글"].waitForExistence(timeout:8))
        capture(app,name:"Search query and saved list survive ordinary profile and nested list Back")
    }
}

extension ReviewDemoUITests {
    func testProfileNavigationCommentMentionTapUsesOrdinaryPushAndBack() {
        let app=uxLaunch(environment:["SOOM_PROJECTION_SUMMARY_QA":"1","SOOM_PROFILE_SOCIAL_QA":"1","SOOM_PROFILE_NAVIGATION_QA":"1"])
        defer { app.terminate() }
        let comments=app.buttons["feed.projection.comments"].firstMatch
        uxReveal(comments,in:app);tap(comments,in:app)
        XCTAssertTrue(app.staticTexts["함께 응원해요"].waitForExistence(timeout:10))
        let search=app.textFields["feed.mention.search"]
        tap(search,in:app);search.typeText("soom")
        let candidate=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","soom_test")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout:8));tap(candidate,in:app)
        let input=app.textFields["feed.comment.input"]
        XCTAssertTrue((input.value as? String ?? "").contains("@soom_test"))
        // Keep the selected handle intact: typeText after refocusing can place
        // the caret inside the token, which correctly produces no mention URL.
        tap(app.buttons["댓글 보내기"],in:app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","@soom_test")).firstMatch.waitForExistence(timeout:8))
        let link=app.links.matching(NSPredicate(format:"label CONTAINS %@","soom_test")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout:8), "Tap the actual attributed mention link, not a QA navigation shortcut")
        tap(link,in:app)
        XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:10))
        XCTAssertFalse(app.navigationBars["댓글"].exists)
        tap(app.navigationBars["프로필"].buttons.firstMatch,in:app)
        XCTAssertTrue(comments.waitForExistence(timeout:8));XCTAssertTrue(comments.isHittable)
        capture(app,name:"Stored attributed mention opens shared native profile and returns to original card")
    }
}


extension ReviewDemoUITests {
    func testProfileNavigationGalleryDetailDenialClearsRoutes() {
        let app = uxLaunch(environment: ["SOOM_PROJECTION_SUMMARY_QA":"1", "SOOM_PROFILE_PHOTO_QA":"1", "SOOM_PROFILE_NAVIGATION_QA":"1", "SOOM_DETAIL_REVALIDATION_QA":"1", "SOOM_DETAIL_REVALIDATION_FAIL":"1"])
        defer { app.terminate() }
        let author = app.buttons["데모 운동 기록 프로필 보기"].firstMatch
        func openGalleryDetail() {
            uxReveal(author,in:app); tap(author,in:app)
            XCTAssertTrue(app.navigationBars["프로필"].waitForExistence(timeout:10))
            tap(app.buttons["profile.tab.gallery"],in:app)
            let item = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@", "profile.gallery.item.")).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout:10)); uxReveal(item,in:app); tap(item,in:app)
            XCTAssertTrue(app.navigationBars["운동 상세"].waitForExistence(timeout:10))
            let photo = app.scrollViews["feed.projection.readonlyDetail"].buttons["workout.card.open.photo"].firstMatch
            uxReveal(photo,in:app); XCTAssertTrue(photo.isHittable)
            capture(app,name:"Gallery detail photo before held final denial")
        }
        openGalleryDetail()
        XCUIDevice.shared.press(.home); app.activate()
        let release = app.buttons["profile.navigation.qa.finishCheck"]
        XCTAssertTrue(release.waitForExistence(timeout:8))
        capture(app,name:"Gallery detail held permission check hides content")
        let tree=XCTAttachment(string:app.debugDescription);tree.name="Gallery detail held complete hierarchy";tree.lifetime = .keepAlways;add(tree)
        XCTAssertFalse(app.buttons["workout.card.open.photo"].exists)
        XCTAssertFalse(app.staticTexts["profile.displayName"].exists)
        tap(release,in:app)
        XCTAssertTrue(element("social.locked",in:app).waitForExistence(timeout:10))
        tap(app.buttons["profile.navigation.qa.regrant"],in:app)
        XCTAssertTrue(author.waitForExistence(timeout:12))
        XCTAssertFalse(app.navigationBars["운동 상세"].exists)
        XCTAssertFalse(app.navigationBars["프로필"].exists)
        capture(app,name:"Gallery detail final denial clears both stale detail and profile routes after regrant")
        openGalleryDetail()
    }
}
