import Foundation

extension RecoverySummary {
    static let mockToday = RecoverySummary(
        score: 82,
        status: "좋음",
        description: "수면과 휴식 흐름이 안정적입니다. 다만 러닝 볼륨 증가가 남아 있어 강도 조절이 필요합니다.",
        recommendation: "오늘은 Z2 라이딩 40분 또는 가벼운 조깅을 추천해요.",
        trendText: "지난 7일 대비 +6점",
        coachMessage: RecoveryCoachMessage(
            coachName: "SOOM AI 코치",
            subtitle: "회복 우선 주간",
            message: "훈련 흐름은 좋습니다. 오늘은 강도를 올리기보다 몸을 가볍게 움직이며 회복 리듬을 유지하세요."
        ),
        recommendationCard: RecoveryRecommendation(
            title: "오늘의 추천",
            description: "하체 피로가 완전히 빠지기 전이라 긴 인터벌보다 짧고 편한 유산소가 더 적합합니다.",
            actionLabel: "40분 Z2 라이딩 보기",
            icon: SOOMIcon.bike
        ),
        trends: [
            RecoveryTrend(
                title: "휴식기 심박",
                currentValue: "48",
                unit: "bpm",
                changeText: "3 낮아짐",
                direction: .down,
                values: [52, 51, 50, 49, 49, 48, 48]
            ),
            RecoveryTrend(
                title: "운동 부하",
                currentValue: "642",
                unit: "TL",
                changeText: "12% 증가",
                direction: .up,
                values: [420, 468, 510, 536, 588, 610, 642]
            ),
            RecoveryTrend(
                title: "피로도",
                currentValue: "64",
                unit: "점",
                changeText: "보통",
                direction: .flat,
                values: [62, 66, 65, 63, 64, 65, 64]
            )
        ],
        insights: [
            RecoveryInsight(
                title: "심박 안정",
                message: "최근 7일 평균 심박이 안정적으로 내려가고 있어요.",
                icon: SOOMIcon.heart,
                tone: .positive
            ),
            RecoveryInsight(
                title: "러닝 부하 주의",
                message: "러닝 거리가 빠르게 늘었습니다. 이번 주는 회복 세션을 섞어 부상 위험을 낮추세요.",
                icon: SOOMIcon.run,
                tone: .warning
            ),
            RecoveryInsight(
                title: "수면 리듬 양호",
                message: "최근 수면 패턴은 안정적입니다. 고강도 전날에는 취침 시간을 조금 앞당기는 편이 좋습니다.",
                icon: SOOMIcon.moon,
                tone: .neutral
            )
        ],
        lastUpdated: Date(timeIntervalSince1970: 1_778_716_800),
        dataQuality: .mock
    )
}
