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
