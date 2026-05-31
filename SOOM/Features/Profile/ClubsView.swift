import SwiftUI

struct ClubsView: View {
    @EnvironmentObject private var viewModel: CommunityViewModel
    @State private var rankingCategory: ClubRankingCategory = .distance

    private let snapshot = ClubDashboardSnapshot.mock

    var body: some View {
        SOOMScreen {
            if viewModel.clubs.isEmpty {
                ClubEmptyStateView()
            } else {
                ClubStatusHero(snapshot: snapshot)
                ClubWeeklyRankingSection(
                    ranking: snapshot.ranking,
                    selectedCategory: $rankingCategory
                )
                ClubChallengesSection(challenges: snapshot.challenges)
                ClubBadgeWallSection(badges: snapshot.badges)
                ClubActivityPulseSection(pulses: snapshot.pulses)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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

struct ClubDashboardSnapshot {
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

    static let mock = ClubDashboardSnapshot(
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

private struct ClubStatusHero: View {
    let snapshot: ClubDashboardSnapshot

    var body: some View {
        SOOMCard(depth: .primary) {
            VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                HStack(alignment: .top, spacing: SOOMLayout.Metrics.rowSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.name)
                            .font(SOOMFont.display(28, relativeTo: .title))
                            .foregroundStyle(SOOMColor.ink)
                        Text("\(snapshot.memberCount)명이 함께 움직이는 온라인 클럽")
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
                    SOOMMetricPill("이번 주", "\(snapshot.weeklyRank)위", tint: SOOMColor.bike)
                    SOOMMetricPill("기여 거리", String(format: "%.1fkm", snapshot.contributionDistanceKm), tint: SOOMColor.ink)
                }

                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing + 4) {
                    HStack {
                        Text("클럽 목표")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                        Spacer()
                        Text(snapshot.goalPercentText)
                            .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.bike)
                    }
                    ProgressView(value: snapshot.goalProgress)
                        .tint(SOOMColor.bike)
                        .accessibilityLabel("클럽 목표 진행률")
                        .accessibilityValue(snapshot.goalPercentText)
                    Label("이번 주 \(snapshot.rankMovement)계단 올라왔어요", systemImage: SOOMIcon.trendUp)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.bike)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.name)
        .accessibilityValue("이번 주 \(snapshot.weeklyRank)위, 기여 거리 \(String(format: "%.1f", snapshot.contributionDistanceKm))킬로미터, 클럽 목표 \(snapshot.goalPercentText)")
    }
}

private struct ClubWeeklyRankingSection: View {
    let ranking: [ClubRankingEntry]
    @Binding var selectedCategory: ClubRankingCategory

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("Weekly Ranking", caption: "내 위치는 보이되, 부끄럽게 만들지 않아요.")

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
    var body: some View {
        SOOMFirstJourneyCard(
            prompt: .club,
            actions: [
                SOOMFirstJourneyAction(
                    title: "비슷한 리듬의 클럽 찾기",
                    subtitle: "거리보다 꾸준함과 종목이 맞는 온라인 클럽부터 둘러봅니다.",
                    iconName: SOOMIcon.clubs
                ),
                SOOMFirstJourneyAction(
                    title: "추천 클럽 미리보기",
                    subtitle: "SOOM Riders처럼 주간 랭킹과 챌린지를 함께 쌓는 공간을 준비 중이에요.",
                    iconName: SOOMIcon.medal
                )
            ],
            footer: "클럽은 오프라인 모임보다 온라인 소속감, 기여, 랭킹, 뱃지를 먼저 보여줍니다."
        )
    }
}
