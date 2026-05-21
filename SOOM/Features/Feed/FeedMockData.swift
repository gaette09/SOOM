import Foundation

enum FeedMockData {
    static let items: [FeedItem] = [
        FeedItem(
            id: UUID(uuidString: "8F3F1C68-BF75-43B8-B142-3FE3D60E13A1")!,
            authorName: "정지환",
            authorHandle: "@jihwan",
            createdAt: Date(timeIntervalSince1970: 1_800_420_000),
            itemType: .workoutSession,
            visibility: .followers,
            cardData: .workoutSession(
                ShareableWorkoutCardModel(
                    id: UUID(uuidString: "AA3F18AC-24D4-46CB-AEE1-035F41381F01")!,
                    workoutType: .running,
                    title: "오늘의 성장 기록",
                    distanceText: "10.40 km",
                    durationText: "52분",
                    primaryMessage: "오늘은 리듬을 잘 이어간 러닝이에요.",
                    growthMessage: "지난 기록보다 조금 더 오래 움직였어요.",
                    recoveryMessage: "회복 흐름을 생각한 안정적인 강도였어요.",
                    footerText: "SOOM 공유 카드 미리보기",
                    visibility: .followers
                )
            ),
            caption: "초반을 차분하게 가져가니까 후반 리듬이 더 편했어요."
        ),
        FeedItem(
            id: UUID(uuidString: "D6F50D11-84DD-4201-A0CE-BAD3E3AC9DF8")!,
            authorName: "민서",
            authorHandle: "@steady_m",
            createdAt: Date(timeIntervalSince1970: 1_800_360_000),
            itemType: .weeklyProgress,
            visibility: .followers,
            cardData: .weeklyProgress(
                ShareableWeeklyProgressCardModel(
                    weekLabel: "이번 주 성장 기록",
                    totalDistanceText: "42.5 km",
                    totalDurationText: "3시간 30분",
                    workoutCountText: "4회",
                    progressMessage: "이번 주는 꾸준함이 좋아지고 있어요.",
                    motivationText: "기록이 크게 튀지 않아도 자주 움직인 흐름 자체가 좋은 성장 신호예요.",
                    footerText: "SOOM 주간 공유 카드",
                    visibility: .followers
                )
            ),
            caption: "이번 주는 기록보다 루틴을 지키는 쪽에 집중했어요."
        ),
        FeedItem(
            id: UUID(uuidString: "0B6B8040-7330-46A9-9A6F-F3F0ED71962E")!,
            authorName: "도윤",
            authorHandle: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_300_000),
            itemType: .recoveryFriendly,
            visibility: .publicFeed,
            cardData: .workoutSession(
                ShareableWorkoutCardModel(
                    id: UUID(uuidString: "E448A791-1AF5-4F66-8D41-70DDE0442652")!,
                    workoutType: .cycling,
                    title: "회복 친화 라이딩",
                    distanceText: "24.8 km",
                    durationText: "1시간 12분",
                    primaryMessage: "가볍게 리듬을 이어간 라이딩이에요.",
                    growthMessage: "꾸준히 움직인 시간이 좋은 신호예요.",
                    recoveryMessage: "몸을 깨우는 정도의 부담 없는 흐름이었어요.",
                    footerText: "SOOM 공유 카드 미리보기",
                    visibility: .publicFeed
                )
            ),
            caption: "오늘은 강도보다 회복 리듬을 먼저 봤어요."
        )
    ]
}
