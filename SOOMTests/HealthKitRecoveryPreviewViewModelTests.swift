import XCTest
@testable import SOOM

@MainActor
final class HealthKitRecoveryPreviewViewModelTests: XCTestCase {
    func testLoadSummarySuccessPublishesProviderResult() async {
        let expectedSummary = makeSummary(
            score: 84,
            status: "좋음",
            recommendation: "가벼운 Z2 라이딩을 추천해요."
        )
        let viewModel = HealthKitRecoveryPreviewViewModel(
            provider: FakeRecoveryPreviewProvider(summary: expectedSummary)
        )

        await viewModel.loadSummary()

        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertEqual(viewModel.summary?.status, expectedSummary.status)
        XCTAssertEqual(viewModel.summary?.recommendation, expectedSummary.recommendation)
        XCTAssertEqual(viewModel.summary?.coachMessage.message, expectedSummary.coachMessage.message)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testEmptyWorkoutSummaryIsHandledAsInsufficientData() async {
        let viewModel = HealthKitRecoveryPreviewViewModel(
            provider: FakeRecoveryPreviewProvider(summary: makeDataInsufficientSummary())
        )

        await viewModel.loadSummary()

        XCTAssertEqual(viewModel.summary?.score, 72)
        XCTAssertEqual(viewModel.summary?.status, "데이터 부족")
        XCTAssertTrue(viewModel.hasInsufficientHealthKitData)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testProviderFailureSetsErrorMessage() async {
        let viewModel = HealthKitRecoveryPreviewViewModel(
            provider: FakeRecoveryPreviewProvider(error: PreviewTestError.fetchFailed)
        )

        await viewModel.loadSummary()

        XCTAssertNil(viewModel.summary)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testScoreStatusAndRecommendationAreDisplayedFromProviderUnchanged() async {
        let expectedSummary = makeSummary(
            score: 65,
            status: "주의",
            recommendation: "오늘은 강도를 낮추고 회복성 활동을 선택하세요."
        )
        let viewModel = HealthKitRecoveryPreviewViewModel(
            provider: FakeRecoveryPreviewProvider(summary: expectedSummary)
        )

        await viewModel.loadSummary()

        XCTAssertEqual(viewModel.summary?.score, 65)
        XCTAssertEqual(viewModel.summary?.status, "주의")
        XCTAssertEqual(viewModel.summary?.recommendation, "오늘은 강도를 낮추고 회복성 활동을 선택하세요.")
    }

    private func makeSummary(
        score: Int,
        status: String,
        recommendation: String
    ) -> RecoverySummary {
        RecoverySummary(
            score: score,
            status: status,
            description: "HealthKit source 검증용 요약입니다.",
            recommendation: recommendation,
            trendText: "검증용 흐름",
            coachMessage: RecoveryCoachMessage(
                coachName: "SOOM AI 코치",
                subtitle: "HealthKit 미리보기",
                message: "HealthKit 운동 기록 기반으로 계산된 개발용 코치 메시지입니다."
            ),
            recommendationCard: RecoveryRecommendation(
                title: "개발용 추천",
                description: recommendation,
                actionLabel: "확인",
                icon: SOOMIcon.recovery
            ),
            trends: [
                RecoveryTrend(
                    title: "운동 부하",
                    currentValue: "72",
                    unit: "TL",
                    changeText: "보통",
                    direction: .flat,
                    values: [64, 68, 72]
                )
            ],
            insights: [
                RecoveryInsight(
                    title: "HealthKit 검증",
                    message: "HealthKit source에서 RecoverySummary가 생성되었습니다.",
                    icon: SOOMIcon.health,
                    tone: .neutral
                )
            ],
            lastUpdated: Date(timeIntervalSince1970: 1_800_000_000),
            dataQuality: .estimated
        )
    }

    private func makeDataInsufficientSummary() -> RecoverySummary {
        RecoverySummary(
            score: 72,
            status: "데이터 부족",
            description: "최근 HealthKit 운동 기록이 충분하지 않습니다.",
            recommendation: "운동 기록이 쌓이면 회복 해석을 더 안정적으로 확인할 수 있어요.",
            trendText: "기록 부족",
            coachMessage: RecoveryCoachMessage(
                coachName: "SOOM AI 코치",
                subtitle: "기록 준비 중",
                message: "HealthKit 운동 기록이 더 쌓이면 Recovery 미리보기를 확인할 수 있어요."
            ),
            recommendationCard: RecoveryRecommendation(
                title: "운동 기록 준비",
                description: "HealthKit 운동 기록이 쌓이면 미리보기가 더 자연스럽게 표시됩니다.",
                actionLabel: "확인",
                icon: SOOMIcon.health
            ),
            trends: [],
            insights: [],
            lastUpdated: Date(timeIntervalSince1970: 1_800_000_000),
            dataQuality: .estimated
        )
    }
}

private struct FakeRecoveryPreviewProvider: RecoveryDataProvider {
    let summary: RecoverySummary?
    let error: Error?

    init(summary: RecoverySummary? = nil, error: Error? = nil) {
        self.summary = summary
        self.error = error
    }

    func fetchRecoverySummary() async throws -> RecoverySummary {
        if let error {
            throw error
        }

        return summary ?? RecoverySummary.mockToday
    }
}

private enum PreviewTestError: Error {
    case fetchFailed
}
