import XCTest
@testable import SOOM

final class FeedMockDataTests: XCTestCase {
    func testMockFeedIsNotEmpty() {
        XCTAssertFalse(FeedMockData.items.isEmpty)
    }

    func testMockFeedContainsWorkoutAndWeeklyCards() {
        let cardTypes = FeedMockData.items.map(\.cardData)

        XCTAssertTrue(cardTypes.contains { data in
            if case .workoutSession = data { return true }
            return false
        })
        XCTAssertTrue(cardTypes.contains { data in
            if case .weeklyProgress = data { return true }
            return false
        })
    }

    func testMockFeedCopyAvoidsCompetitiveTone() {
        let copy = FeedMockData.items.flatMap { item -> [String] in
            var values = [
                item.authorName,
                item.authorHandle ?? "",
                item.caption ?? "",
                item.itemType.title
            ]

            switch item.cardData {
            case .workoutSession(let card):
                values.append(contentsOf: [
                    card.title,
                    card.primaryMessage,
                    card.growthMessage,
                    card.recoveryMessage,
                    card.footerText
                ])
            case .weeklyProgress(let card):
                values.append(contentsOf: [
                    card.weekLabel,
                    card.progressMessage,
                    card.motivationText,
                    card.footerText
                ])
            }

            return values
        }.joined(separator: " ")

        ["랭킹", "순위", "이겼", "친구보다", "경쟁", "1등"].forEach { word in
            XCTAssertFalse(copy.contains(word), "Feed mock copy should avoid competitive tone: \(word)")
        }
    }
}
