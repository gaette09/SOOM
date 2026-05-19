import XCTest
@testable import SOOM

final class RecoveryExplanationBuilderTests: XCTestCase {
    private let builder = RecoveryExplanationBuilder()

    func testHighTrainingLoadCreatesLoadExplanation() {
        let summary = makeSummary(
            description: "최근 훈련량은 관리 가능한 범위입니다.",
            trendText: "최근 3일 평균 부하 92",
            trends: [
                RecoveryTrend(
                    title: "운동 부하",
                    currentValue: "650",
                    unit: "TL",
                    changeText: "3일 평균 92",
                    direction: .up,
                    values: [82, 88, 92, 94]
                )
            ]
        )

        let explanation = builder.build(summary: summary, latestCheckIn: nil)

        XCTAssertTrue(explanation.explanation.contains("운동 부하"))
        XCTAssertTrue(isWarning(explanation.tone))
    }

    func testRestDaysCreateStableRecoveryExplanation() {
        let summary = makeSummary(
            description: "휴식일 2일이 회복 흐름을 받쳐주고 있어요.",
            trendText: "최근 3일 평균 부하 44",
            trends: [
                RecoveryTrend(
                    title: "운동 부하",
                    currentValue: "220",
                    unit: "TL",
                    changeText: "3일 평균 44",
                    direction: .flat,
                    values: [42, 46, 44]
                )
            ]
        )

        let explanation = builder.build(summary: summary, latestCheckIn: nil)

        XCTAssertTrue(explanation.explanation.contains("휴식"))
        XCTAssertTrue(isPositive(explanation.tone))
    }

    func testHighFatigueCreatesFatigueExplanation() {
        let summary = makeSummary()
        let checkIn = makeCheckIn(fatigue: 5)

        let explanation = builder.build(summary: summary, latestCheckIn: checkIn)

        XCTAssertTrue(explanation.explanation.contains("피로감"))
        XCTAssertTrue(isWarning(explanation.tone))
    }

    func testLowSleepCreatesSleepExplanation() {
        let summary = makeSummary()
        let checkIn = makeCheckIn(sleepQuality: 1)

        let explanation = builder.build(summary: summary, latestCheckIn: checkIn)

        XCTAssertTrue(explanation.explanation.contains("수면감"))
        XCTAssertEqual(explanation.icon, SOOMIcon.moon)
    }

    func testBuilderDoesNotChangeScoreStatusOrRecommendation() {
        let summary = makeSummary()
        let originalScore = summary.score
        let originalStatus = summary.status
        let originalRecommendation = summary.recommendation

        _ = builder.build(summary: summary, latestCheckIn: makeCheckIn(fatigue: 5))

        XCTAssertEqual(summary.score, originalScore)
        XCTAssertEqual(summary.status, originalStatus)
        XCTAssertEqual(summary.recommendation, originalRecommendation)
    }

    private func makeSummary(
        description: String = "최근 훈련량은 관리 가능한 범위입니다.",
        trendText: String = "최근 3일 평균 부하 52",
        trends: [RecoveryTrend] = []
    ) -> RecoverySummary {
        RecoverySummary(
            score: 82,
            status: "좋음",
            description: description,
            recommendation: "오늘은 Z2 라이딩 40분 또는 가벼운 조깅을 추천해요.",
            trendText: trendText,
            coachMessage: RecoveryCoachMessage(
                coachName: "SOOM AI 코치",
                subtitle: "운동 기록 기반 추정",
                message: "오늘은 편안한 강도로 리듬을 이어가세요."
            ),
            recommendationCard: RecoveryRecommendation(
                title: "오늘의 추천",
                description: "짧고 편한 유산소가 적합합니다.",
                actionLabel: "40분 Z2 라이딩 보기",
                icon: SOOMIcon.bike
            ),
            trends: trends,
            insights: [
                RecoveryInsight(
                    title: "훈련 부하 안정",
                    message: "최근 부하는 관리 가능한 수준입니다.",
                    icon: SOOMIcon.checkCircle,
                    tone: .positive
                )
            ],
            lastUpdated: Date(timeIntervalSince1970: 1_800_000_000),
            dataQuality: .estimated
        )
    }

    private func makeCheckIn(
        fatigue: Int = 2,
        sleepQuality: Int = 4,
        muscleSoreness: Int = 2,
        mood: Int = 4
    ) -> RecoveryCheckIn {
        RecoveryCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            fatigueLevel: fatigue,
            sleepQuality: sleepQuality,
            muscleSoreness: muscleSoreness,
            moodLevel: mood,
            note: nil
        )
    }

    private func isWarning(_ tone: InsightTone) -> Bool {
        if case .warning = tone {
            return true
        }

        return false
    }

    private func isPositive(_ tone: InsightTone) -> Bool {
        if case .positive = tone {
            return true
        }

        return false
    }
}
