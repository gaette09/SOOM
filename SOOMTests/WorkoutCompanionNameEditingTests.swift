import XCTest
@testable import SOOM

final class WorkoutCompanionNameEditingTests: XCTestCase {
    func testNormalizedTrimsWhitespaceAndCapsLength() {
        XCTAssertEqual(WorkoutCompanionNameEditing.normalized("  민수  "), "민수")
        XCTAssertNil(WorkoutCompanionNameEditing.normalized("   "))
        XCTAssertNil(WorkoutCompanionNameEditing.normalized(""))

        let longName = String(repeating: "가", count: 30)
        XCTAssertEqual(
            WorkoutCompanionNameEditing.normalized(longName)?.count,
            WorkoutCompanionNameEditing.maximumNameLength
        )
    }

    func testAddingAppendsTrimmedName() {
        let result = WorkoutCompanionNameEditing.adding("  지훈  ", to: ["민수"])
        XCTAssertEqual(result, ["민수", "지훈"])
    }

    func testAddingIgnoresBlankInput() {
        let result = WorkoutCompanionNameEditing.adding("   ", to: ["민수"])
        XCTAssertEqual(result, ["민수"])
    }

    func testAddingDeduplicatesCaseInsensitively() {
        let result = WorkoutCompanionNameEditing.adding("MINSU", to: ["minsu"])
        XCTAssertEqual(result, ["minsu"])
    }

    func testAddingRespectsMaximumCompanionCount() {
        let names = (0..<WorkoutCompanionNameEditing.maximumCompanionCount).map { "이름\($0)" }
        let result = WorkoutCompanionNameEditing.adding("한명더", to: names)
        XCTAssertEqual(result, names)
    }

    func testRemovingDropsExactMatch() {
        let result = WorkoutCompanionNameEditing.removing("민수", from: ["민수", "지훈"])
        XCTAssertEqual(result, ["지훈"])
    }

    func testRemovingNonexistentNameIsNoOp() {
        let result = WorkoutCompanionNameEditing.removing("없음", from: ["민수", "지훈"])
        XCTAssertEqual(result, ["민수", "지훈"])
    }
}

@MainActor
final class WorkoutCompanionDraftRegressionTests: XCTestCase {
    func testFailedSaveKeepsDraftRetrySucceedsAndOriginalArrayIsNotMutated() async {
        let original = ["QA original"]; var calls = 0
        let model = WorkoutCompanionEditor(initialNames: original) { names in
            calls += 1; return calls == 1 ? .failure(.persistenceFailed) : .success(names)
        }
        model.newName = "  QA added  "; model.addName(); XCTAssertEqual(model.names, ["QA original", "QA added"])
        let failed = await model.save(); XCTAssertFalse(failed); XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.names, ["QA original", "QA added"]); XCTAssertFalse(model.isSaving)
        let success = await model.save(); XCTAssertTrue(success); XCTAssertEqual(calls, 2); XCTAssertNil(model.errorMessage)
        XCTAssertEqual(original, ["QA original"])
    }
    func testUnaddedTextIsNotSilentlyLostOrSentAsAnImplicitTag() async {
        var calls = 0
        let model = WorkoutCompanionEditor(initialNames: ["QA original"]) { names in calls += 1; return .success(names) }
        model.newName = "QA unadded"
        let result = await model.save(); XCTAssertFalse(result); XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.newName, "QA unadded"); XCTAssertEqual(model.names, ["QA original"]); XCTAssertNotNil(model.errorMessage)
        model.addName(); let saved = await model.save(); XCTAssertTrue(saved); XCTAssertEqual(calls, 1)
    }
    func testScopeChangeBeforeSaveNeverCallsPersistence() async {
        var allowed = true; var calls = 0
        let model = WorkoutCompanionEditor(initialNames: ["QA original"], canAccess: { allowed }) { names in calls += 1; return .success(names) }
        allowed = false; let result = await model.save(); XCTAssertFalse(result); XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.names, ["QA original"])
    }
    func testDuplicateTapAndLateResponseAfterScopeChangeCannotSucceedOrReplaceDraft() async {
        var allowed = true; var calls = 0; var waiter: CheckedContinuation<WorkoutCompanionUpdateResult, Never>?
        let model = WorkoutCompanionEditor(initialNames: ["QA original"], canAccess: { allowed }) { _ in
            calls += 1; return await withCheckedContinuation { waiter = $0 }
        }
        let task = Task { await model.save() }
        for _ in 0..<1000 { if waiter != nil { break }; await Task.yield() }
        XCTAssertTrue(model.isSaving); let duplicate = await model.save(); XCTAssertFalse(duplicate); XCTAssertEqual(calls, 1)
        allowed = false; waiter?.resume(returning: .success(["late other account"])); let success = await task.value
        XCTAssertFalse(success); XCTAssertEqual(model.names, ["QA original"]); XCTAssertFalse(model.isSaving)
    }
}
