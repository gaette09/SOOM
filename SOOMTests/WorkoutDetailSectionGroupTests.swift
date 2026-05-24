import XCTest
@testable import SOOM

final class WorkoutDetailSectionGroupTests: XCTestCase {
    func testOrderedGroupsFollowWorkoutDetailReadingFlow() {
        XCTAssertEqual(
            WorkoutDetailSectionGroup.ordered.map(\.id),
            [.core, .growth, .sensorData, .recovery]
        )
    }

    func testGroupPrioritiesIncreaseWithReadingOrder() {
        let priorities = WorkoutDetailSectionGroup.ordered.map(\.priority)

        XCTAssertEqual(priorities, priorities.sorted())
        XCTAssertEqual(Set(priorities).count, priorities.count)
    }

    func testGroupTitlesStayShortAndScannable() {
        let titles = WorkoutDetailSectionGroup.ordered.map(\.title)

        XCTAssertEqual(titles, ["오늘 핵심", "성장 흐름", "운동 데이터", "회복 해석"])
        XCTAssertTrue(titles.allSatisfy { $0.count <= 6 })
    }

    func testGroupsAreFutureReadyWithoutEnablingCollapse() {
        XCTAssertTrue(WorkoutDetailSectionGroup.ordered.allSatisfy { !$0.isCollapsibleReady })
    }
}
