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

    func testFirstJourneyPromptsUseWarmNonEmptyCopy() {
        let prompts: [SOOMFirstJourneyPrompt] = [
            .feed,
            .activity,
            .club,
            .coach,
            .profile
        ]

        prompts.forEach { prompt in
            XCTAssertFalse(prompt.title.isEmpty)
            XCTAssertFalse(prompt.message.isEmpty)
            XCTAssertFalse(prompt.iconName.isEmpty)
        }

        let joinedCopy = prompts.map { "\($0.title) \($0.message)" }.joined(separator: " ")
        ["아직 아무도", "기록 없음", "0개", "실패", "경쟁", "랭킹"].forEach { word in
            XCTAssertFalse(joinedCopy.contains(word), "First journey copy should avoid cold empty-state tone: \(word)")
        }
    }
}
