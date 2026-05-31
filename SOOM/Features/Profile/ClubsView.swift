import SwiftUI

struct ClubsView: View {
    @EnvironmentObject private var viewModel: CommunityViewModel
    @State private var isCreateSheetPresented = false

    private var directory: ClubDirectorySnapshot {
        ClubDirectorySnapshot.mock(hasJoinedClubs: !viewModel.clubs.isEmpty)
    }

    var body: some View {
        SOOMScreen {
            ClubHomeHeader(onCreate: { isCreateSheetPresented = true })

            if directory.joinedClubs.isEmpty {
                ClubEmptyStateView(
                    recommendedClubs: directory.recommendedClubs,
                    onCreate: { isCreateSheetPresented = true }
                )
            } else {
                ClubHomeSection(title: "내 클럽", caption: "여러 클럽 안에서 이번 주 내 위치를 봅니다.") {
                    ForEach(directory.joinedClubs) { detail in
                        NavigationLink {
                            ClubDashboardDetailView(detail: detail)
                        } label: {
                            ClubHomeCard(summary: detail.summary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ClubHomeSection(title: "내가 만든 클럽", caption: "운영보다 소속감과 주간 기여를 먼저 보여줍니다.") {
                    ForEach(directory.createdClubs) { detail in
                        NavigationLink {
                            ClubDashboardDetailView(detail: detail)
                        } label: {
                            ClubHomeCard(summary: detail.summary, isOwned: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ClubHomeSection(title: "추천 클럽", caption: "비슷한 리듬의 온라인 클럽을 가볍게 둘러봅니다.") {
                    ForEach(directory.recommendedClubs) { summary in
                        ClubRecommendedCard(summary: summary)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isCreateSheetPresented) {
            ClubCreatePlaceholderSheet()
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ClubDashboardDetailView: View {
    let detail: ClubDetail
    @State private var rankingCategory: ClubRankingCategory = .distance
    @State private var isMembershipSheetPresented = false

    var body: some View {
        SOOMScreen {
            ClubStatusHero(
                detail: detail,
                onMembershipAction: { isMembershipSheetPresented = true }
            )
            ClubPurposeRulesSection(detail: detail)
            ClubMemberPreviewSection(members: detail.memberPreview)
            ClubWeeklyRankingSection(
                clubName: detail.name,
                ranking: detail.ranking,
                selectedCategory: $rankingCategory
            )
            ClubChallengesSection(challenges: detail.challenges)
            ClubBadgeWallSection(badges: detail.badges)
            ClubActivityPulseSection(pulses: detail.pulses)
        }
        .navigationTitle(detail.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isMembershipSheetPresented) {
            ClubMembershipPlaceholderSheet(state: detail.membershipState)
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
    }
}

enum ClubRankingCategory: String, CaseIterable, Identifiable {
    case distance
    case sessions
    case consistency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: return "거리"
        case .sessions: return "운동 횟수"
        case .consistency: return "꾸준함"
        }
    }

    var unit: String {
        switch self {
        case .distance: return "km"
        case .sessions: return "회"
        case .consistency: return "일"
        }
    }
}

struct ClubDirectorySnapshot {
    let joinedClubs: [ClubDetail]
    let createdClubs: [ClubDetail]
    let recommendedClubs: [ClubSummary]

    static func mock(hasJoinedClubs: Bool = true) -> ClubDirectorySnapshot {
        ClubDirectorySnapshot(
            joinedClubs: hasJoinedClubs ? [.soomRiders, .morningRunners] : [],
            createdClubs: hasJoinedClubs ? [.recoveryCrew] : [],
            recommendedClubs: ClubSummary.recommended
        )
    }
}

struct ClubSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let sport: String
    let memberCount: Int
    let weeklyRank: Int?
    let contributionText: String
    let goalPercent: Int
    let tagline: String

    var memberText: String {
        "\(memberCount)명"
    }

    var rankText: String {
        guard let weeklyRank else { return "가입 전" }
        return "이번 주 내 순위 \(weeklyRank)위"
    }

    static let recommended: [ClubSummary] = [
        ClubSummary(
            id: "hangang-riders",
            name: "한강 라이더스",
            sport: "자전거",
            memberCount: 284,
            weeklyRank: nil,
            contributionText: "초보 라이딩 중심",
            goalPercent: 61,
            tagline: "강변 코스를 꾸준히 타는 사람들"
        ),
        ClubSummary(
            id: "easy-ride-club",
            name: "초보 라이딩",
            sport: "자전거",
            memberCount: 93,
            weeklyRank: nil,
            contributionText: "주 2회 완주 챌린지",
            goalPercent: 44,
            tagline: "빠르게보다 오래 이어가는 클럽"
        ),
        ClubSummary(
            id: "weekend-runners",
            name: "주말 러너스",
            sport: "러닝",
            memberCount: 156,
            weeklyRank: nil,
            contributionText: "주말 5km부터",
            goalPercent: 58,
            tagline: "토요일 아침을 같이 시작해요"
        )
    ]
}

struct ClubDetail: Identifiable {
    let summary: ClubSummary
    let name: String
    let intro: String
    let purpose: String
    let sport: String
    let owner: String
    let privacy: Privacy
    let activeMembersThisWeek: Int
    let rules: [String]
    let memberPreview: [ClubMemberPreview]
    let identityTags: [String]
    let membershipState: MembershipState
    let memberCount: Int
    let weeklyRank: Int
    let rankMovement: Int
    let contributionDistanceKm: Double
    let goalProgress: Double
    let ranking: [ClubRankingEntry]
    let challenges: [ClubChallenge]
    let badges: [ClubBadge]
    let pulses: [ClubActivityPulse]

    var goalPercentText: String {
        "\(Int((goalProgress * 100).rounded()))%"
    }

    var privacyText: String {
        switch privacy {
        case .open: return "공개 클럽"
        case .private: return "비공개 클럽"
        }
    }

    enum Privacy: Equatable {
        case open
        case `private`
    }

    enum MembershipState: Equatable {
        case joined
        case recommended
        case owned

        var actionTitle: String {
            switch self {
            case .joined: return "가입됨"
            case .recommended: return "가입하기"
            case .owned: return "관리"
            }
        }

        var placeholderTitle: String {
            switch self {
            case .joined: return "클럽 연결 상태는 곧 더 자세히 볼 수 있어요."
            case .recommended: return "클럽 가입은 곧 사용할 수 있어요."
            case .owned: return "클럽 관리는 곧 사용할 수 있어요."
            }
        }
    }

    static let soomRiders = ClubDetail(
        summary: ClubSummary(
            id: "soom-riders",
            name: "SOOM Riders",
            sport: "자전거",
            memberCount: 412,
            weeklyRank: 12,
            contributionText: "기여 거리 42.6km",
            goalPercent: 73,
            tagline: "회복 리듬을 지키며 오래 타는 클럽"
        ),
        name: "SOOM Riders",
        intro: "빠르기보다 꾸준함을 쌓는 라이더 클럽",
        purpose: "주 3회 이상 가볍게 움직이며, 오래 이어갈 수 있는 라이딩 리듬을 만듭니다.",
        sport: "자전거",
        owner: "지환",
        privacy: .open,
        activeMembersThisWeek: 128,
        rules: [
            "무리한 경쟁보다 꾸준함을 먼저 봅니다.",
            "회복 라이딩도 클럽 기여로 인정합니다.",
            "공개 피드 운동만 랭킹에 반영합니다."
        ],
        memberPreview: [
            ClubMemberPreview(name: "지환", role: "운영자", activityText: "이번 주 42.6km", tone: .ink),
            ClubMemberPreview(name: "김하늘", role: "이번 주 1위", activityText: "142km", tone: .bike),
            ClubMemberPreview(name: "박서연", role: "꾸준함 리더", activityText: "5일 활동", tone: .recovery),
            ClubMemberPreview(name: "태호", role: "최근 합류", activityText: "첫 챌린지", tone: .green)
        ],
        identityTags: ["꾸준함", "회복 라이딩", "초보 환영", "주말 장거리", "라이딩 중심"],
        membershipState: .joined,
        memberCount: 412,
        weeklyRank: 12,
        rankMovement: 2,
        contributionDistanceKm: 42.6,
        goalProgress: 0.73,
        ranking: [
            ClubRankingEntry(rank: 1, name: "김하늘", distanceKm: 142, sessions: 6, consistencyDays: 6, isCurrentUser: false),
            ClubRankingEntry(rank: 2, name: "이도윤", distanceKm: 131, sessions: 5, consistencyDays: 5, isCurrentUser: false),
            ClubRankingEntry(rank: 3, name: "박서연", distanceKm: 118, sessions: 5, consistencyDays: 5, isCurrentUser: false),
            ClubRankingEntry(rank: 4, name: "최민준", distanceKm: 91, sessions: 4, consistencyDays: 4, isCurrentUser: false),
            ClubRankingEntry(rank: 12, name: "나", distanceKm: 42.6, sessions: 3, consistencyDays: 3, isCurrentUser: true)
        ],
        challenges: [
            ClubChallenge(title: "이번 주 3회 운동", progress: 2, target: 3, unit: "회", subtitle: "한 번만 더 움직이면 개인 목표 달성"),
            ClubChallenge(title: "클럽 전체 1,000km", progress: 730, target: 1_000, unit: "km", subtitle: "412명이 함께 채우는 주간 거리"),
            ClubChallenge(title: "아침 운동 챌린지", progress: 4, target: 7, unit: "일", subtitle: "4일 남음")
        ],
        badges: [
            ClubBadge(title: "1000km", subtitle: "획득", icon: SOOMIcon.medal, state: .earned),
            ClubBadge(title: "30일 연속", subtitle: "진행 중", icon: SOOMIcon.calendarClock, state: .inProgress),
            ClubBadge(title: "Century Ride", subtitle: "희귀", icon: SOOMIcon.bike, state: .rare),
            ClubBadge(title: "회복 라이딩", subtitle: "이번 주", icon: SOOMIcon.recovery, state: .newThisWeek)
        ],
        pulses: [
            ClubActivityPulse(icon: SOOMIcon.medal, message: "김하늘이 Century 배지를 획득했어요", tone: .warning),
            ClubActivityPulse(icon: SOOMIcon.trendUp, message: "박서연이 거리 랭킹 3위로 올라왔어요", tone: .bike),
            ClubActivityPulse(icon: SOOMIcon.checkCircle, message: "클럽 목표가 73%까지 찼어요", tone: .recovery),
            ClubActivityPulse(icon: SOOMIcon.people, message: "이번 주 28명이 움직였어요", tone: .ink)
        ]
    )

    static let morningRunners = ClubDetail(
        summary: ClubSummary(
            id: "morning-runners",
            name: "Morning Runners",
            sport: "러닝",
            memberCount: 128,
            weeklyRank: 8,
            contributionText: "기여 거리 18.4km",
            goalPercent: 64,
            tagline: "아침에 짧게 뛰는 리듬을 모아요"
        ),
        name: "Morning Runners",
        intro: "하루를 가볍게 여는 러너들의 온라인 클럽",
        purpose: "짧은 러닝을 반복해 아침 움직임을 일상의 리듬으로 만듭니다.",
        sport: "러닝",
        owner: "소라",
        privacy: .open,
        activeMembersThisWeek: 54,
        rules: [
            "속도보다 출석과 리듬을 존중합니다.",
            "5km 이하의 짧은 러닝도 충분히 기록합니다.",
            "서로의 페이스를 비교하지 않습니다."
        ],
        memberPreview: [
            ClubMemberPreview(name: "소라", role: "운영자", activityText: "64.2km", tone: .run),
            ClubMemberPreview(name: "강지훈", role: "이번 주 2위", activityText: "52.8km", tone: .bike),
            ClubMemberPreview(name: "윤하민", role: "꾸준함 리더", activityText: "4일 활동", tone: .recovery),
            ClubMemberPreview(name: "나", role: "내 위치", activityText: "18.4km", tone: .ink)
        ],
        identityTags: ["아침 러닝", "짧게 자주", "초보 환영", "회복 조깅"],
        membershipState: .joined,
        memberCount: 128,
        weeklyRank: 8,
        rankMovement: 1,
        contributionDistanceKm: 18.4,
        goalProgress: 0.64,
        ranking: [
            ClubRankingEntry(rank: 1, name: "문소라", distanceKm: 64.2, sessions: 5, consistencyDays: 5, isCurrentUser: false),
            ClubRankingEntry(rank: 2, name: "강지훈", distanceKm: 52.8, sessions: 4, consistencyDays: 4, isCurrentUser: false),
            ClubRankingEntry(rank: 3, name: "윤하민", distanceKm: 41.5, sessions: 4, consistencyDays: 4, isCurrentUser: false),
            ClubRankingEntry(rank: 8, name: "나", distanceKm: 18.4, sessions: 3, consistencyDays: 3, isCurrentUser: true)
        ],
        challenges: [
            ClubChallenge(title: "아침 3회 뛰기", progress: 2, target: 3, unit: "회", subtitle: "짧아도 아침 리듬이 쌓이면 충분해요"),
            ClubChallenge(title: "클럽 전체 300km", progress: 192, target: 300, unit: "km", subtitle: "128명이 함께 채우는 주간 거리"),
            ClubChallenge(title: "회복 조깅 챌린지", progress: 5, target: 7, unit: "일", subtitle: "2일 남음")
        ],
        badges: [
            ClubBadge(title: "Morning 10", subtitle: "획득", icon: SOOMIcon.calendar, state: .earned),
            ClubBadge(title: "5km 루틴", subtitle: "진행 중", icon: SOOMIcon.run, state: .inProgress),
            ClubBadge(title: "비 오는 날", subtitle: "이번 주", icon: SOOMIcon.sparkles, state: .newThisWeek),
            ClubBadge(title: "꾸준함", subtitle: "희귀", icon: SOOMIcon.medal, state: .rare)
        ],
        pulses: [
            ClubActivityPulse(icon: SOOMIcon.trendUp, message: "강지훈이 운동 횟수 랭킹 2위로 올라왔어요", tone: .run),
            ClubActivityPulse(icon: SOOMIcon.checkCircle, message: "아침 3회 뛰기 챌린지가 68%까지 찼어요", tone: .recovery),
            ClubActivityPulse(icon: SOOMIcon.people, message: "이번 주 19명이 아침에 움직였어요", tone: .ink)
        ]
    )

    static let recoveryCrew = ClubDetail(
        summary: ClubSummary(
            id: "recovery-crew",
            name: "Recovery Crew",
            sport: "혼합",
            memberCount: 46,
            weeklyRank: 4,
            contributionText: "기여 거리 12.0km",
            goalPercent: 52,
            tagline: "무리하지 않는 움직임도 클럽 기여가 됩니다"
        ),
        name: "Recovery Crew",
        intro: "무리하지 않는 움직임도 클럽 기여가 되는 곳",
        purpose: "강도보다 회복과 지속성을 기준으로, 가벼운 운동을 서로 인정합니다.",
        sport: "혼합",
        owner: "지환",
        privacy: .private,
        activeMembersThisWeek: 21,
        rules: [
            "회복 운동을 낮게 보지 않습니다.",
            "개인 회복 점수는 공개 랭킹에 사용하지 않습니다.",
            "기록 조작 없이 실제 움직임만 반영합니다."
        ],
        memberPreview: [
            ClubMemberPreview(name: "지환", role: "운영자", activityText: "12.0km", tone: .ink),
            ClubMemberPreview(name: "서유진", role: "회복 루틴", activityText: "6회 활동", tone: .recovery),
            ClubMemberPreview(name: "한도겸", role: "꾸준함", activityText: "5일 활동", tone: .bike)
        ],
        identityTags: ["회복 친화", "가벼운 운동", "꾸준함", "비공개"],
        membershipState: .owned,
        memberCount: 46,
        weeklyRank: 4,
        rankMovement: 3,
        contributionDistanceKm: 12.0,
        goalProgress: 0.52,
        ranking: [
            ClubRankingEntry(rank: 1, name: "서유진", distanceKm: 28.4, sessions: 6, consistencyDays: 6, isCurrentUser: false),
            ClubRankingEntry(rank: 2, name: "한도겸", distanceKm: 24.0, sessions: 5, consistencyDays: 5, isCurrentUser: false),
            ClubRankingEntry(rank: 4, name: "나", distanceKm: 12.0, sessions: 4, consistencyDays: 4, isCurrentUser: true)
        ],
        challenges: [
            ClubChallenge(title: "회복 운동 4회", progress: 3, target: 4, unit: "회", subtitle: "강도보다 이어가는 리듬에 집중해요"),
            ClubChallenge(title: "클럽 전체 120km", progress: 62, target: 120, unit: "km", subtitle: "가볍게 쌓는 공동 목표")
        ],
        badges: [
            ClubBadge(title: "회복 루틴", subtitle: "획득", icon: SOOMIcon.recovery, state: .earned),
            ClubBadge(title: "가벼운 4회", subtitle: "진행 중", icon: SOOMIcon.checkCircle, state: .inProgress),
            ClubBadge(title: "균형", subtitle: "이번 주", icon: SOOMIcon.sparkles, state: .newThisWeek)
        ],
        pulses: [
            ClubActivityPulse(icon: SOOMIcon.recovery, message: "서유진이 회복 루틴 배지를 획득했어요", tone: .recovery),
            ClubActivityPulse(icon: SOOMIcon.checkCircle, message: "클럽 목표가 52%까지 찼어요", tone: .bike)
        ]
    )

    var id: String {
        summary.id
    }
}

struct ClubRankingEntry: Identifiable, Equatable {
    let rank: Int
    let name: String
    let distanceKm: Double
    let sessions: Int
    let consistencyDays: Int
    let isCurrentUser: Bool

    var id: String {
        "\(rank)-\(name)"
    }

    func valueText(for category: ClubRankingCategory) -> String {
        switch category {
        case .distance:
            return String(format: "%.1f %@", distanceKm, category.unit)
        case .sessions:
            return "\(sessions)\(category.unit)"
        case .consistency:
            return "\(consistencyDays)\(category.unit)"
        }
    }

    func numericValue(for category: ClubRankingCategory) -> Double {
        switch category {
        case .distance:
            return distanceKm
        case .sessions:
            return Double(sessions)
        case .consistency:
            return Double(consistencyDays)
        }
    }
}

struct ClubChallenge: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let progress: Double
    let target: Double
    let unit: String
    let subtitle: String

    var progressRatio: Double {
        guard target > 0 else { return 0 }
        return min(max(progress / target, 0), 1)
    }

    var progressText: String {
        "\(Self.formatted(progress)) / \(Self.formatted(target))\(unit)"
    }

    private static func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

struct ClubBadge: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let state: State

    enum State: Hashable {
        case earned
        case inProgress
        case newThisWeek
        case rare

        var tint: Color {
            switch self {
            case .earned: return SOOMColor.accent
            case .inProgress: return SOOMColor.accent.opacity(0.64)
            case .newThisWeek: return SOOMColor.accent.opacity(0.82)
            case .rare: return SOOMColor.accentInk
            }
        }
    }
}

enum ClubVisualTone: Hashable {
    case ink
    case bike
    case recovery
    case green
    case warning
    case run

    var color: Color {
        switch self {
        case .ink: return SOOMColor.ink
        case .bike: return SOOMColor.accent
        case .recovery: return SOOMColor.accent
        case .green: return SOOMColor.accent
        case .warning: return SOOMColor.warning
        case .run: return SOOMColor.accent
        }
    }
}

struct ClubActivityPulse: Identifiable {
    let id = UUID()
    let icon: String
    let message: String
    let tone: ClubVisualTone
}

struct ClubMemberPreview: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let activityText: String
    let tone: ClubVisualTone
}

private struct ClubHomeHeader: View {
    let onCreate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: SOOMLayout.Metrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("클럽")
                    .font(SOOMFont.display(30, relativeTo: .largeTitle))
                    .foregroundStyle(SOOMColor.ink)
                Text("내가 속한 그룹 안에서 랭킹, 뱃지, 챌린지를 쌓아요.")
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onCreate) {
                Image(systemName: SOOMIcon.record)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SOOMColor.white)
                    .frame(width: 44, height: 44)
                    .background(SOOMColor.ink)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("클럽 만들기")
        }
    }
}

private struct ClubHomeSection<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowSpacing) {
            SOOMSectionHeader(title, caption: caption)
            content
        }
    }
}

private struct ClubHomeCard: View {
    let summary: ClubSummary
    var isOwned = false

    var body: some View {
        SOOMCard(depth: .secondary) {
            HStack(alignment: .top, spacing: SOOMLayout.Metrics.rowSpacing) {
                Image(systemName: SOOMIcon.clubs)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SOOMColor.accent)
                    .frame(width: 44, height: 44)
                    .background(SOOMColor.accentSurface)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                        Text(summary.name)
                            .font(SOOMFont.body(17, weight: .bold, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink)
                        if isOwned {
                            Text("내가 만든 클럽")
                                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                                .foregroundStyle(SOOMColor.accentInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(SOOMColor.accentSurface)
                                .clipShape(Capsule())
                        }
                    }

                    Text("\(summary.sport) · \(summary.memberText) · \(summary.rankText)")
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)

                    Text(summary.tagline)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .lineLimit(2)

                    HStack {
                        Text(summary.contributionText)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.ink)
                        Spacer()
                        Text("목표 \(summary.goalPercent)%")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.accent)
                    }
                }

                Image(systemName: SOOMIcon.chevronRight)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.name)
        .accessibilityValue("\(summary.sport), \(summary.memberText), \(summary.rankText)")
    }
}

private struct ClubRecommendedCard: View {
    let summary: ClubSummary

    var body: some View {
        HStack(spacing: SOOMLayout.Metrics.rowSpacing) {
            Image(systemName: SOOMIcon.sparkles)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 36, height: 36)
                .background(SOOMColor.accentSurface)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)
                Text("\(summary.sport) · \(summary.memberText) · \(summary.contributionText)")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .lineLimit(1)
            }

            Spacer()

            Text("둘러보기")
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.accentInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SOOMColor.accentSurface)
                .clipShape(Capsule())
        }
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(SOOMColor.surfaceAmbient)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ClubStatusHero: View {
    let detail: ClubDetail
    let onMembershipAction: () -> Void

    var body: some View {
        SOOMCard(depth: .primary) {
            VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                HStack(alignment: .top, spacing: SOOMLayout.Metrics.rowSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.name)
                            .font(SOOMFont.display(28, relativeTo: .title))
                            .foregroundStyle(SOOMColor.ink)
                        Text("\"\(detail.intro)\"")
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(detail.sport) · \(detail.privacyText) · 운영자 \(detail.owner)")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }
                    Spacer()
                    ClubProgressRing(progress: detail.goalProgress, label: detail.goalPercentText)
                }

                HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                    ForEach(detail.identityTags.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(SOOMColor.accentInk)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(SOOMColor.accentSurface)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: SOOMLayout.Metrics.gridSpacing) {
                    ClubStatTile(title: "내 순위", value: "\(detail.weeklyRank)위", icon: SOOMIcon.medal, tint: SOOMColor.accent)
                    ClubStatTile(title: "멤버", value: "\(detail.memberCount)명", icon: SOOMIcon.people, tint: SOOMColor.ink)
                    ClubStatTile(title: "이번 주", value: "\(detail.activeMembersThisWeek)명", icon: SOOMIcon.trendUp, tint: SOOMColor.accent)
                }

                Button(action: onMembershipAction) {
                    Text(detail.membershipState.actionTitle)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(detail.membershipState == .joined ? SOOMColor.accent : SOOMColor.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(detail.membershipState == .joined ? SOOMColor.accentSurface : SOOMColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(detail.membershipState.actionTitle)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.name)
        .accessibilityValue("이번 주 \(detail.weeklyRank)위, 기여 거리 \(String(format: "%.1f", detail.contributionDistanceKm))킬로미터, 클럽 목표 \(detail.goalPercentText)")
    }
}

private struct ClubProgressRing: View {
    let progress: Double
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(SOOMColor.accentSurface, lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(SOOMColor.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(label)
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.accent)
                Text("목표")
                    .font(SOOMFont.body(9, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }
        }
        .frame(width: 74, height: 74)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("클럽 목표 진행률")
        .accessibilityValue(label)
    }
}

private struct ClubStatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(SOOMFont.body(16, weight: .bold, relativeTo: .headline))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(title)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ClubPurposeRulesSection: View {
    let detail: ClubDetail
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("클럽 기준", caption: "목표와 규칙")

            Text(detail.purpose)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, spacing: SOOMLayout.Metrics.gridSpacing) {
                ForEach(detail.rules, id: \.self) { rule in
                    ClubRuleChip(title: rule)
                }
            }
        }
    }
}

private struct ClubRuleChip: View {
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: SOOMIcon.checkCircle)
                .font(.caption.weight(.bold))
                .foregroundStyle(SOOMColor.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .padding(10)
        .background(SOOMColor.accentSurface.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ClubMemberPreviewSection: View {
    let members: [ClubMemberPreview]

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("멤버 미리보기", caption: "운영자와 이번 주 리더")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SOOMLayout.Metrics.rowSpacing) {
                    ForEach(members) { member in
                        ClubMemberAvatarCard(member: member)
                    }
                }
            }
        }
    }
}

private struct ClubMemberAvatarCard: View {
    let member: ClubMemberPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(String(member.name.prefix(1)))
                .font(SOOMFont.body(18, weight: .bold, relativeTo: .headline))
                .foregroundStyle(SOOMColor.white)
                .frame(width: 48, height: 48)
                .background(member.tone.color)
                .clipShape(Circle())

            Text(member.name)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)

            Text(member.role)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(member.tone.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(member.tone.color.opacity(0.10))
                .clipShape(Capsule())
                .lineLimit(1)

            Text(member.activityText)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(1)
        }
        .frame(width: 128, alignment: .leading)
        .padding(12)
        .background(SOOMColor.surfaceAmbient)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ClubWeeklyRankingSection: View {
    let clubName: String
    let ranking: [ClubRankingEntry]
    @Binding var selectedCategory: ClubRankingCategory

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("\(clubName) 내 이번 주 랭킹", caption: "클럽 내 순위")

            HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                ForEach(ClubRankingCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category.title)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(selectedCategory == category ? SOOMColor.white : SOOMColor.secondaryInk)
                            .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
                            .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding)
                            .background(selectedCategory == category ? SOOMColor.accent : SOOMColor.surfaceMuted)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            ClubRankingGraph(ranking: ranking, category: selectedCategory)

            VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                ForEach(ranking) { entry in
                    ClubRankingRow(entry: entry, category: selectedCategory)
                }
            }
        }
    }
}

private struct ClubRankingGraph: View {
    let ranking: [ClubRankingEntry]
    let category: ClubRankingCategory

    private var maxValue: Double {
        max(ranking.map { $0.numericValue(for: category) }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
            ForEach(ranking.prefix(4)) { entry in
                HStack(spacing: SOOMLayout.Metrics.rowSpacing) {
                    Text("#\(entry.rank)")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(entry.isCurrentUser ? SOOMColor.accent : SOOMColor.secondaryInk)
                        .frame(width: 34, alignment: .leading)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(SOOMColor.surfaceMuted)
                            Capsule()
                                .fill(entry.isCurrentUser ? SOOMColor.accent : SOOMColor.accent.opacity(0.36))
                                .frame(width: max(8, proxy.size.width * entry.numericValue(for: category) / maxValue))
                        }
                    }
                    .frame(height: 9)

                    Text(entry.valueText(for: category))
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(SOOMColor.accentSurface.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("클럽 내 랭킹 비교 그래프")
    }
}

private struct ClubRankingRow: View {
    let entry: ClubRankingEntry
    let category: ClubRankingCategory

    var body: some View {
        HStack(spacing: SOOMLayout.Metrics.rowSpacing) {
            Text("#\(entry.rank)")
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                .foregroundStyle(entry.isCurrentUser ? SOOMColor.white : SOOMColor.secondaryInk)
                .frame(width: 42, height: 34)
                .background(entry.isCurrentUser ? SOOMColor.accent : SOOMColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)
                if entry.isCurrentUser {
                    Text("내 위치")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.accent)
                }
            }

            Spacer()

            Text(entry.valueText(for: category))
                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(entry.isCurrentUser ? SOOMColor.accent : SOOMColor.secondaryInk)
        }
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(entry.isCurrentUser ? SOOMColor.accentSurface : SOOMColor.surfaceAmbient)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.rank)위 \(entry.name)")
        .accessibilityValue(entry.valueText(for: category))
    }
}

private struct ClubChallengesSection: View {
    let challenges: [ClubChallenge]

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("Challenges", caption: "진행률 중심")

            ForEach(challenges) { challenge in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(challenge.title)
                                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                                .foregroundStyle(SOOMColor.ink)
                            Text(challenge.subtitle)
                                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                                .foregroundStyle(SOOMColor.secondaryInk)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(challenge.progressText)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.accent)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(SOOMColor.surfaceMuted)
                            Capsule()
                                .fill(SOOMColor.accent)
                                .frame(width: max(8, proxy.size.width * challenge.progressRatio))
                        }
                    }
                    .frame(height: 10)
                    .accessibilityLabel(challenge.title)
                    .accessibilityValue(challenge.progressText)
                }
                .padding(12)
                .background(SOOMColor.surfaceAmbient)
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
        }
    }
}

private struct ClubBadgeWallSection: View {
    let badges: [ClubBadge]
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("Badge Wall", caption: "클럽 안에서 쌓이는 대표 성취")

            LazyVGrid(columns: columns, spacing: SOOMLayout.Metrics.gridSpacing) {
                ForEach(badges) { badge in
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: badge.icon)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(badge.state.tint)
                            .frame(width: 34, height: 34)
                            .background(badge.state.tint.opacity(0.12))
                            .clipShape(Circle())
                        Text(badge.title)
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.ink)
                            .lineLimit(1)
                        Text(badge.subtitle)
                            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(badge.state.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(badge.state.tint.opacity(0.10))
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SOOMLayout.Metrics.pillPadding)
                    .background(SOOMColor.surfaceAmbient)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(badge.title) 뱃지")
                    .accessibilityValue(badge.subtitle)
                }
            }
        }
    }
}

private struct ClubActivityPulseSection: View {
    let pulses: [ClubActivityPulse]

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("Club Activity Pulse", caption: "Feed 카드 반복 없이 클럽 안의 변화를 요약해요.")

            VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                ForEach(pulses) { pulse in
                    HStack(spacing: SOOMLayout.Metrics.rowSpacing) {
                        Image(systemName: pulse.icon)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(pulse.tone.color)
                            .frame(width: 34, height: 34)
                            .background(pulse.tone.color.opacity(0.10))
                            .clipShape(Circle())
                            .accessibilityHidden(true)

                        Text(pulse.message)
                            .font(SOOMFont.body(14, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ClubEmptyStateView: View {
    let recommendedClubs: [ClubSummary]
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            SOOMFirstJourneyCard(
                prompt: .club,
                actions: [
                    SOOMFirstJourneyAction(
                        title: "비슷한 리듬의 클럽 찾기",
                        subtitle: "거리보다 꾸준함과 종목이 맞는 온라인 클럽부터 둘러봅니다.",
                        iconName: SOOMIcon.clubs
                    ),
                    SOOMFirstJourneyAction(
                        title: "클럽 만들기",
                        subtitle: "직접 만든 클럽 안에서 주간 랭킹과 챌린지를 열 수 있게 준비 중이에요.",
                        iconName: SOOMIcon.record
                    )
                ],
                footer: "클럽은 선택한 그룹 안에서만 랭킹과 뱃지가 쌓입니다."
            )

            Button(action: onCreate) {
                Label("클럽 만들기", systemImage: SOOMIcon.record)
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SOOMColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
            .buttonStyle(.plain)

            ClubHomeSection(title: "추천 클럽", caption: "가입 전에도 클럽의 리듬을 미리 볼 수 있어요.") {
                ForEach(recommendedClubs) { summary in
                    ClubRecommendedCard(summary: summary)
                }
            }
        }
    }
}

private struct ClubCreatePlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            HStack {
                Image(systemName: SOOMIcon.clubs)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SOOMColor.accent)
                    .frame(width: 44, height: 44)
                    .background(SOOMColor.accentSurface)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: SOOMIcon.close)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("클럽 만들기는 곧 사용할 수 있어요.")
                    .font(SOOMFont.body(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Text("v1에서는 mock 기반으로 클럽 홈과 상세 구조를 먼저 잡고, 실제 생성과 초대는 backend 단계에서 연결합니다.")
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(SOOMLayout.screenPadding)
        .background(SOOMColor.background)
    }
}

private struct ClubMembershipPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ClubDetail.MembershipState

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            HStack {
                Image(systemName: SOOMIcon.clubs)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SOOMColor.accent)
                    .frame(width: 44, height: 44)
                    .background(SOOMColor.accentSurface)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: SOOMIcon.close)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(state.placeholderTitle)
                    .font(SOOMFont.body(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Text("v1에서는 클럽 정체성과 상세 구조만 mock으로 준비하고, 가입/탈퇴/관리는 backend 단계에서 연결합니다.")
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(SOOMLayout.screenPadding)
        .background(SOOMColor.background)
    }
}
