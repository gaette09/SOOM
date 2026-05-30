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
            caption: "초반을 차분하게 가져가니까 후반 리듬이 더 편했어요.",
            photoPlaceholders: [
                FeedPhotoPlaceholder(title: "아침 공원", tone: .morning),
                FeedPhotoPlaceholder(title: "젖은 강변길", tone: .city)
            ],
            activityContext: "비 오는 아침 러닝",
            emotionalContext: "비 오기 전에 짧게 달렸어요",
            movementMood: "호흡 먼저",
            optionalShortStory: "오늘은 페이스보다 호흡을 먼저 봤고, 마지막에는 다리보다 리듬이 편했어요.",
            routeMood: "비 온 뒤 공기가 차분했던 강변 코스",
            recoveryCue: "무리하지 않아도 좋아요",
            locationHint: "서강대교 근처",
            clubContext: "SOOM 러닝 크루",
            contextLabels: [
                FeedContextLabel(title: "비슷한 페이스", icon: SOOMIcon.trendFlat),
                FeedContextLabel(title: "회복 친화", icon: SOOMIcon.recovery)
            ],
            reactions: [
                FeedReaction(symbol: "👏", label: "차분한 리듬"),
                FeedReaction(symbol: "🌙", label: "아침 응원"),
                FeedReaction(symbol: "🫶", label: "함께 뛰는 느낌")
            ],
            microComment: "민서: 후반 리듬 진짜 편해 보여요."
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
            caption: "이번 주는 기록보다 루틴을 지키는 쪽에 집중했어요.",
            activityContext: "조용히 쌓은 한 주",
            emotionalContext: "기록보다 루틴을 지킨 주",
            movementMood: "꾸준함",
            optionalShortStory: "큰 변화보다 같은 시간에 다시 움직인 날들이 쌓였어요.",
            routeMood: "자주 걷고 달린 익숙한 동네 리듬",
            recoveryCue: "가볍게 이어가도 충분해요",
            locationHint: "집 근처 루틴",
            clubContext: "평일 루틴 클럽",
            contextLabels: [
                FeedContextLabel(title: "같은 클럽", icon: SOOMIcon.clubs),
                FeedContextLabel(title: "오늘 추천", icon: SOOMIcon.sparkles)
            ],
            reactions: [
                FeedReaction(symbol: "👏", label: "꾸준함"),
                FeedReaction(symbol: "🫶", label: "응원")
            ],
            microComment: "도윤: 이런 주가 오래 남더라구요."
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
            caption: "오늘은 강도보다 회복 리듬을 먼저 봤어요.",
            photoPlaceholders: [
                FeedPhotoPlaceholder(title: "강변 라이딩", tone: .city),
                FeedPhotoPlaceholder(title: "느린 회복길", tone: .trail)
            ],
            activityContext: "퇴근 후 회복 라이딩",
            emotionalContext: "천천히 강변 한 바퀴",
            movementMood: "바람 따라",
            optionalShortStory: "다리보다 리듬에 집중한 날. 속도를 올리기보다 몸이 풀리는 쪽을 골랐어요.",
            routeMood: "강변 바람이 좋았던 회복 코스",
            recoveryCue: "몸 깨우는 정도로 충분해요",
            locationHint: "한강 남쪽길",
            clubContext: "목요 라이트 라이딩",
            contextLabels: [
                FeedContextLabel(title: "같은 루트", icon: SOOMIcon.map),
                FeedContextLabel(title: "recovery-friendly", icon: SOOMIcon.recovery)
            ],
            reactions: [
                FeedReaction(symbol: "💨", label: "부드러운 흐름"),
                FeedReaction(symbol: "👏", label: "좋은 선택")
            ],
            microComment: "지환: 오늘은 이런 강도가 딱 좋네요."
        )
    ]
}
