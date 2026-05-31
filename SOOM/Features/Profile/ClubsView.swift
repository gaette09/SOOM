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

    var body: some View {
        SOOMScreen {
            ClubStatusHero(detail: detail)
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
            ClubActivityPulse(icon: SOOMIcon.medal, message: "김하늘이 Century 배지를 획득했어요", tint: SOOMColor.warning),
            ClubActivityPulse(icon: SOOMIcon.trendUp, message: "박서연이 거리 랭킹 3위로 올라왔어요", tint: SOOMColor.bike),
            ClubActivityPulse(icon: SOOMIcon.checkCircle, message: "클럽 목표가 73%까지 찼어요", tint: SOOMColor.recovery),
            ClubActivityPulse(icon: SOOMIcon.people, message: "이번 주 28명이 움직였어요", tint: SOOMColor.ink)
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
            ClubActivityPulse(icon: SOOMIcon.trendUp, message: "강지훈이 운동 횟수 랭킹 2위로 올라왔어요", tint: SOOMColor.run),
            ClubActivityPulse(icon: SOOMIcon.checkCircle, message: "아침 3회 뛰기 챌린지가 68%까지 찼어요", tint: SOOMColor.recovery),
            ClubActivityPulse(icon: SOOMIcon.people, message: "이번 주 19명이 아침에 움직였어요", tint: SOOMColor.ink)
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
            ClubActivityPulse(icon: SOOMIcon.recovery, message: "서유진이 회복 루틴 배지를 획득했어요", tint: SOOMColor.recovery),
            ClubActivityPulse(icon: SOOMIcon.checkCircle, message: "클럽 목표가 52%까지 찼어요", tint: SOOMColor.bike)
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
            case .earned: return SOOMColor.bike
            case .inProgress: return SOOMColor.recovery
            case .newThisWeek: return SOOMColor.green
            case .rare: return SOOMColor.warning
            }
        }
    }
}

struct ClubActivityPulse: Identifiable {
    let id = UUID()
    let icon: String
    let message: String
    let tint: Color
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
                    .foregroundStyle(SOOMColor.bike)
                    .frame(width: 44, height: 44)
                    .background(SOOMColor.bike.opacity(0.12))
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
                                .foregroundStyle(SOOMColor.bike)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(SOOMColor.bike.opacity(0.10))
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
                            .foregroundStyle(SOOMColor.bike)
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
                .foregroundStyle(SOOMColor.bike)
                .frame(width: 36, height: 36)
                .background(SOOMColor.surfaceMuted)
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
                .foregroundStyle(SOOMColor.bike)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SOOMColor.bike.opacity(0.10))
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

    var body: some View {
        SOOMCard(depth: .primary) {
            VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                HStack(alignment: .top, spacing: SOOMLayout.Metrics.rowSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.name)
                            .font(SOOMFont.display(28, relativeTo: .title))
                            .foregroundStyle(SOOMColor.ink)
                        Text("\(detail.memberCount)명이 함께 움직이는 온라인 클럽")
                            .font(SOOMFont.body(14, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: SOOMIcon.clubs)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SOOMColor.bike)
                        .frame(width: 44, height: 44)
                        .background(SOOMColor.bike.opacity(0.12))
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                }

                HStack(spacing: SOOMLayout.Metrics.gridSpacing) {
                    SOOMMetricPill("이번 주", "\(detail.weeklyRank)위", tint: SOOMColor.bike)
                    SOOMMetricPill("기여 거리", String(format: "%.1fkm", detail.contributionDistanceKm), tint: SOOMColor.ink)
                }

                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing + 4) {
                    HStack {
                        Text("클럽 목표")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                        Spacer()
                        Text(detail.goalPercentText)
                            .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.bike)
                    }
                    ProgressView(value: detail.goalProgress)
                        .tint(SOOMColor.bike)
                        .accessibilityLabel("클럽 목표 진행률")
                        .accessibilityValue(detail.goalPercentText)
                    Label("이번 주 \(detail.rankMovement)계단 올라왔어요", systemImage: SOOMIcon.trendUp)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.bike)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.name)
        .accessibilityValue("이번 주 \(detail.weeklyRank)위, 기여 거리 \(String(format: "%.1f", detail.contributionDistanceKm))킬로미터, 클럽 목표 \(detail.goalPercentText)")
    }
}

private struct ClubWeeklyRankingSection: View {
    let clubName: String
    let ranking: [ClubRankingEntry]
    @Binding var selectedCategory: ClubRankingCategory

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("\(clubName) 내 이번 주 랭킹", caption: "선택한 클럽 안에서만 계산되는 위치입니다.")

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
                            .background(selectedCategory == category ? SOOMColor.ink : SOOMColor.surfaceMuted)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                ForEach(ranking) { entry in
                    ClubRankingRow(entry: entry, category: selectedCategory)
                }
            }
        }
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
                .background(entry.isCurrentUser ? SOOMColor.bike : SOOMColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)
                if entry.isCurrentUser {
                    Text("내 위치")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.bike)
                }
            }

            Spacer()

            Text(entry.valueText(for: category))
                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(entry.isCurrentUser ? SOOMColor.bike : SOOMColor.secondaryInk)
        }
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(entry.isCurrentUser ? SOOMColor.bike.opacity(0.10) : SOOMColor.surfaceAmbient)
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
            SOOMSectionHeader("Challenges", caption: "개인 기록보다 클럽 기여를 작게 쌓아요.")

            ForEach(challenges) { challenge in
                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing + 4) {
                    HStack {
                        Text(challenge.title)
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.ink)
                        Spacer()
                        Text(challenge.progressText)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.bike)
                    }
                    ProgressView(value: challenge.progressRatio)
                        .tint(SOOMColor.bike)
                    Text(challenge.subtitle)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
                .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing)
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
                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing + 4) {
                        Image(systemName: badge.icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(badge.state.tint)
                        Text(badge.title)
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.ink)
                        Text(badge.subtitle)
                            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(badge.state.tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SOOMLayout.Metrics.pillPadding)
                    .background(badge.state.tint.opacity(0.10))
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
                            .foregroundStyle(pulse.tint)
                            .frame(width: 34, height: 34)
                            .background(pulse.tint.opacity(0.10))
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
                    .background(SOOMColor.ink)
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
                    .foregroundStyle(SOOMColor.bike)
                    .frame(width: 44, height: 44)
                    .background(SOOMColor.bike.opacity(0.12))
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
