import XCTest
@testable import SOOM

final class ShareableWeeklyProgressCardBuilderTests: XCTestCase {
    private let builder = ShareableWeeklyProgressCardBuilder()

    func testBuildCreatesCardFromWeeklyProgress() {
        let card = builder.build(progress: improvingProgress)

        XCTAssertFalse(card.weekLabel.isEmpty)
        XCTAssertEqual(card.totalDistanceText, "42.5 km")
        XCTAssertEqual(card.totalDurationText, "3시간 30분")
        XCTAssertEqual(card.workoutCountText, "4회")
        XCTAssertFalse(card.progressMessage.isEmpty)
        XCTAssertFalse(card.motivationText.isEmpty)
        XCTAssertTrue(card.footerText.contains("SOOM"))
    }

    func testDefaultVisibilityIsPrivateOnly() {
        let card = builder.build(progress: improvingProgress)

        XCTAssertEqual(card.visibility, .privateOnly)
        XCTAssertEqual(card.visibility.title, "나만 보기")
        XCTAssertTrue(card.footerText.contains("미리보기"))
    }

    func testVisibilityCanBeSetForFutureShareScopes() {
        let card = builder.build(progress: improvingProgress, visibility: .followers)

        XCTAssertEqual(card.visibility, .followers)
        XCTAssertTrue(card.footerText.contains("팔로워"))
    }

    func testInsufficientDataBuildsSafeShareCopy() {
        let card = builder.build(progress: insufficientProgress)

        XCTAssertEqual(card.totalDistanceText, "거리 준비 중")
        XCTAssertEqual(card.totalDurationText, "시간 준비 중")
        XCTAssertEqual(card.workoutCountText, "0회")
        XCTAssertTrue(card.progressMessage.contains("기록"))
        XCTAssertFalse(card.motivationText.isEmpty)
    }

    func testImprovingFourWeekTrendKeepsGrowthTone() {
        let card = builder.build(progress: improvingProgress, trend: improvingTrend)

        XCTAssertTrue(card.progressMessage.contains("리듬"))
        XCTAssertTrue(card.progressMessage.contains("이어"))
    }

    func testShareableWeeklyCardDoesNotIncludeSensitiveHealthDataByDefault() {
        let card = builder.build(progress: improvingProgress)
        let copy = [
            card.weekLabel,
            card.totalDistanceText,
            card.totalDurationText,
            card.workoutCountText,
            card.progressMessage,
            card.motivationText,
            card.footerText
        ].joined(separator: " ")

        ["bpm", "심박", "회복 점수", "위치", "메모", "수면", "피로"].forEach { sensitiveWord in
            XCTAssertFalse(copy.contains(sensitiveWord), "Weekly share card should not include sensitive data by default: \(sensitiveWord)")
        }
    }

    func testShareableWeeklyCardCopyAvoidsCompetitiveTone() {
        let card = builder.build(progress: improvingProgress)
        let copy = [card.progressMessage, card.motivationText, card.footerText].joined(separator: " ")

        ["랭킹", "순위", "이겼", "친구보다", "경쟁", "1등"].forEach { word in
            XCTAssertFalse(copy.contains(word), "Weekly share copy should avoid competitive tone: \(word)")
        }
    }

    private var improvingProgress: WeeklyWorkoutProgress {
        WeeklyWorkoutProgress(
            weekStartDate: Date(timeIntervalSince1970: 1_800_000_000),
            workoutCount: 4,
            totalDistanceKm: 42.5,
            totalDurationMinutes: 210,
            averagePaceOrSpeedText: "평균 5:15/km",
            progressSummary: "이번 주는 운동 리듬이 더 꾸준했어요.",
            motivationText: "기록이 크게 튀지 않아도 자주 움직인 흐름 자체가 좋은 성장 신호예요.",
            trendType: .improving
        )
    }

    private var insufficientProgress: WeeklyWorkoutProgress {
        WeeklyWorkoutProgress(
            weekStartDate: Date(timeIntervalSince1970: 1_800_000_000),
            workoutCount: 0,
            totalDistanceKm: 0,
            totalDurationMinutes: 0,
            averagePaceOrSpeedText: "-",
            progressSummary: "기록이 쌓이면 주간 흐름을 보여드릴게요.",
            motivationText: "운동 기록이 생기면 이번 주 움직임과 성장 신호를 함께 정리해드릴게요.",
            trendType: .insufficientData
        )
    }

    private var improvingTrend: FourWeekWorkoutTrend {
        FourWeekWorkoutTrend(
            weeks: [],
            trendType: .improving,
            summaryText: "최근 4주 흐름이 좋아지고 있어요.",
            motivationText: "지금 리듬을 차분히 이어가보세요."
        )
    }
}
