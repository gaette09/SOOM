import XCTest
@testable import SOOM

final class FeedItemTests: XCTestCase {
    func testFeedItemKeepsVisibilityAndWorkoutCardData() {
        let item = FeedMockData.items[0]

        XCTAssertEqual(item.visibility, .followers)

        guard case .workoutSession(let card) = item.cardData else {
            return XCTFail("Expected workout session card data")
        }

        XCTAssertEqual(card.visibility, item.visibility)
        XCTAssertEqual(card.workoutType, .running)
    }

    func testFeedItemKeepsWeeklyProgressCardData() {
        let item = FeedMockData.items[1]

        guard case .weeklyProgress(let card) = item.cardData else {
            return XCTFail("Expected weekly progress card data")
        }

        XCTAssertEqual(item.itemType, .weeklyProgress)
        XCTAssertEqual(card.visibility, item.visibility)
        XCTAssertFalse(card.progressMessage.isEmpty)
    }

    func testFeedViewSortsItemsByNewestFirst() {
        let older = FeedMockData.items[2]
        let newer = FeedMockData.items[0]

        let view = FeedView(items: [older, newer])

        XCTAssertEqual(view.items.map(\.id), [newer.id, older.id])
    }
}
