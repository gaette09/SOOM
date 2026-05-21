import XCTest
@testable import SOOM

final class ShareableWorkoutCardBuilderTests: XCTestCase {
    private let builder = ShareableWorkoutCardBuilder()

    func testBuildCreatesCardFromSessionGrowthAndRecoveryImpact() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        XCTAssertEqual(card.id, growthInput.id)
        XCTAssertEqual(card.workoutType, .running)
        XCTAssertEqual(card.primaryMessage, sessionSummary.title)
        XCTAssertEqual(card.growthMessage, growthSummary.motivationText)
        XCTAssertEqual(card.recoveryMessage, recoveryImpact.shortMessage)
        XCTAssertFalse(card.footerText.isEmpty)
    }

    func testDistanceAndDurationTextAreFormattedForPreviewCard() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        XCTAssertEqual(card.distanceText, "10.40 km")
        XCTAssertEqual(card.durationText, "52분")
    }

    func testDefaultVisibilityIsPrivateOnly() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )

        XCTAssertEqual(card.visibility, .privateOnly)
        XCTAssertTrue(card.footerText.contains("미리보기"))
    }

    func testShareableCardDoesNotIncludeSensitiveHealthDataByDefault() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )
        let copy = [
            card.title,
            card.distanceText,
            card.durationText,
            card.primaryMessage,
            card.growthMessage,
            card.recoveryMessage,
            card.footerText
        ].joined(separator: " ")

        ["bpm", "심박", "회복 점수", "위치", "메모"].forEach { sensitiveWord in
            XCTAssertFalse(copy.contains(sensitiveWord), "Shareable card should not include sensitive data by default: \(sensitiveWord)")
        }
    }

    func testShareableCardCopyAvoidsNegativeOrCompetitiveTone() {
        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact,
            input: growthInput
        )
        let copy = [
            card.primaryMessage,
            card.growthMessage,
            card.recoveryMessage,
            card.footerText
        ].joined(separator: " ")

        ["못", "실패", "나쁨", "위험", "랭킹", "순위", "이겼"].forEach { word in
            XCTAssertFalse(copy.contains(word), "Shareable card should keep a calm growth tone without '\(word)'.")
        }
    }

    func testRecoveryFriendlyImpactUsesGrowthSharingTone() {
        let recoveryFriendlyImpact = WorkoutRecoveryImpact(
            impactLevel: .recoveryFriendly,
            title: "회복 친화적인 운동",
            shortMessage: "가볍게 몸을 깨운 흐름이에요.",
            recommendation: "다음 운동도 몸 상태를 보면서 이어가보세요.",
            icon: SOOMIcon.recovery
        )

        let card = builder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryFriendlyImpact,
            input: growthInput
        )

        XCTAssertTrue(card.recoveryMessage.contains("회복 흐름"))
        XCTAssertTrue(card.recoveryMessage.contains("좋은 강도"))
    }

    private var sessionSummary: WorkoutSessionSummary {
        WorkoutSessionSummary(
            title: "오늘은 리듬을 잘 이어간 운동이에요",
            summaryText: "거리와 시간 모두 안정적으로 쌓였어요.",
            highlightText: "지구력 흐름이 좋아졌어요.",
            improvementText: "초반 리듬을 조금 더 부드럽게 가져가면 좋아요.",
            recoveryText: "몸에 적당한 자극을 남기는 흐름이에요.",
            closingMotivation: "다음 운동도 오늘 리듬을 기준으로 이어가보세요.",
            icon: SOOMIcon.sparkles
        )
    }

    private var growthSummary: WorkoutGrowthSummary {
        WorkoutGrowthSummary(
            workoutId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "더 오래 움직였어요",
            shortSummary: "오늘은 같은 종목의 최근 기록보다 지구력 흐름이 좋아졌어요.",
            improvementType: .endurance,
            comparisonText: "10.4 km · 이전 8.8 km",
            motivationText: "조금씩 거리가 길어지고 있어요.",
            insight: "다음에는 같은 리듬을 유지하면서 회복 여유를 확인해보세요."
        )
    }

    private var recoveryImpact: WorkoutRecoveryImpact {
        WorkoutRecoveryImpact(
            impactLevel: .moderate,
            title: "적당한 자극이 있는 운동",
            shortMessage: "회복 흐름을 생각한 안정적인 강도였어요.",
            recommendation: "다음 운동 전 회복 리듬을 한 번 확인하고 비슷한 강도를 이어가보세요.",
            icon: SOOMIcon.waveform
        )
    }

    private var growthInput: WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            source: .soomLocal,
            workoutType: .running,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: 52,
            distanceKm: 10.4,
            averagePaceText: "5:00/km",
            averageSpeedKmh: nil,
            averageHeartRate: 151,
            elevationGainMeters: 78,
            activeEnergyKcal: 676
        )
    }
}
