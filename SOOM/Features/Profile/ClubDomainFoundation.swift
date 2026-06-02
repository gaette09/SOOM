import Foundation
import SwiftUI

struct ClubDomain: Identifiable, Equatable {
    let id: String
    let name: String
    let intro: String
    let purpose: String
    let sportFocus: String
    let visibility: ClubVisibility
    let ownerId: String
    let memberCount: Int
    let createdAt: Date
    let isJoined: Bool
    let membershipState: ClubMembershipState
}

enum ClubVisibility: Hashable {
    case open
    case `private`

    var text: String {
        switch self {
        case .open: return "공개 클럽"
        case .private: return "비공개 클럽"
        }
    }
}

enum ClubMembershipState: Hashable {
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
        case .joined: return "클럽 연결 상태를 관리합니다."
        case .recommended: return "가입하면 내 클럽 목록에 저장돼요."
        case .owned: return "클럽 관리는 곧 더 자세히 연결될 예정이에요."
        }
    }
}

enum ClubMemberRole: String, Equatable {
    case owner
    case admin
    case member
}

struct ClubMember: Identifiable, Equatable {
    let id: String
    let clubId: String
    let userId: String
    let displayName: String
    let handle: String
    let role: ClubMemberRole
    let joinedAt: Date
    let weeklyDistance: Double
    let weeklyWorkoutCount: Int
    let consistencyScore: Double
    let avatarStyle: String
}

enum ClubChallengeMetricType: String, CaseIterable, Identifiable {
    case distance
    case workoutCount
    case consistency
    case recovery

    var id: String { rawValue }
}

enum ClubChallengeState: Equatable {
    case active
    case completed
    case expired
}

struct ClubChallenge: Identifiable, Equatable {
    let id: String
    let clubId: String
    let title: String
    let description: String
    let metricType: ClubChallengeMetricType
    let targetValue: Double
    let currentValue: Double
    let unit: String
    let startsAt: Date
    let endsAt: Date
    let state: ClubChallengeState
    let subtitle: String
    let remainingLabel: String
    let nextActionLine: String

    init(
        id: String = UUID().uuidString,
        clubId: String = "local-club",
        title: String,
        description: String? = nil,
        metricType: ClubChallengeMetricType = .distance,
        targetValue: Double? = nil,
        currentValue: Double? = nil,
        progress: Double? = nil,
        target: Double? = nil,
        unit: String,
        startsAt: Date = ClubSeedDate.weekStart,
        endsAt: Date = ClubSeedDate.weekEnd,
        state: ClubChallengeState = .active,
        subtitle: String,
        remainingLabel: String? = nil,
        nextActionLine: String? = nil
    ) {
        self.id = id
        self.clubId = clubId
        self.title = title
        self.description = description ?? subtitle
        self.metricType = metricType
        self.targetValue = targetValue ?? target ?? 0
        self.currentValue = currentValue ?? progress ?? 0
        self.unit = unit
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.state = state
        self.subtitle = subtitle
        self.remainingLabel = remainingLabel ?? Self.defaultRemainingLabel(
            metricType: metricType,
            targetValue: targetValue ?? target ?? 0,
            currentValue: currentValue ?? progress ?? 0,
            unit: unit
        )
        self.nextActionLine = nextActionLine ?? Self.defaultNextActionLine(
            metricType: metricType,
            remainingLabel: self.remainingLabel
        )
    }

    var progress: Double { currentValue }
    var target: Double { targetValue }

    var progressRatio: Double {
        guard targetValue > 0 else { return 0 }
        return min(max(currentValue / targetValue, 0), 1)
    }

    var progressText: String {
        "\(Self.formatted(currentValue)) / \(Self.formatted(targetValue))\(unit)"
    }

    private static func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private static func defaultRemainingLabel(
        metricType: ClubChallengeMetricType,
        targetValue: Double,
        currentValue: Double,
        unit: String
    ) -> String {
        let remaining = max(targetValue - currentValue, 0)
        if remaining == 0 {
            return "완료"
        }

        switch metricType {
        case .distance:
            return "\(formatted(remaining))\(unit) 남음"
        case .workoutCount:
            return "\(formatted(remaining))\(unit) 운동 남음"
        case .consistency:
            return "\(formatted(remaining))\(unit) 더 유지"
        case .recovery:
            return "목표까지 \(formatted(remaining))\(unit)"
        }
    }

    private static func defaultNextActionLine(
        metricType: ClubChallengeMetricType,
        remainingLabel: String
    ) -> String {
        if remainingLabel == "완료" {
            return "이번 주 리듬을 이미 채웠어요."
        }

        switch metricType {
        case .distance:
            return "짧게 한 번 더 움직이면 클럽 목표가 가까워져요."
        case .workoutCount:
            return "오늘 한 번만 더 움직이면 챌린지가 가까워져요."
        case .consistency:
            return "하루만 더 이어가면 꾸준함이 보입니다."
        case .recovery:
            return "무리하지 않는 움직임도 클럽 기여가 됩니다."
        }
    }
}

enum ClubRankingMetric: String, CaseIterable, Identifiable {
    case distance
    case workoutCount
    case consistency

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .distance: return "km"
        case .workoutCount: return "회"
        case .consistency: return "일"
        }
    }
}

struct ClubRankingEntry: Identifiable, Equatable {
    let id: String
    let clubId: String
    let userId: String
    let displayName: String
    let rank: Int
    let previousRank: Int?
    let metricType: ClubRankingMetric
    let value: Double
    let unit: String
    let isCurrentUser: Bool
    let distanceKm: Double
    let sessions: Int
    let consistencyDays: Int

    init(
        id: String? = nil,
        clubId: String = "local-club",
        userId: String? = nil,
        displayName: String? = nil,
        rank: Int,
        previousRank: Int? = nil,
        metricType: ClubRankingMetric = .distance,
        value: Double? = nil,
        unit: String? = nil,
        name: String,
        distanceKm: Double,
        sessions: Int,
        consistencyDays: Int,
        isCurrentUser: Bool
    ) {
        self.id = id ?? "\(clubId)-\(rank)-\(name)"
        self.clubId = clubId
        self.userId = userId ?? name
        self.displayName = displayName ?? name
        self.rank = rank
        self.previousRank = previousRank
        self.metricType = metricType
        self.value = value ?? distanceKm
        self.unit = unit ?? metricType.unit
        self.isCurrentUser = isCurrentUser
        self.distanceKm = distanceKm
        self.sessions = sessions
        self.consistencyDays = consistencyDays
    }

    var name: String { displayName }

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

    func rankingValue(for metric: ClubRankingMetric) -> Double {
        switch metric {
        case .distance:
            return distanceKm
        case .workoutCount:
            return Double(sessions)
        case .consistency:
            return Double(consistencyDays)
        }
    }
}

enum ClubBadgeState: Hashable {
    case earned
    case inProgress
    case locked
    case newThisWeek
    case rare

    var tint: Color {
        switch self {
        case .earned: return SOOMColor.accent
        case .inProgress: return SOOMColor.accent.opacity(0.64)
        case .locked: return SOOMColor.secondaryInk
        case .newThisWeek: return SOOMColor.accent.opacity(0.82)
        case .rare: return SOOMColor.accentInk
        }
    }
}

enum ClubBadgeRarity: String, Equatable {
    case common
    case uncommon
    case rare
}

struct ClubBadge: Identifiable, Equatable {
    let id: String
    let clubId: String?
    let title: String
    let description: String
    let subtitle: String
    let icon: String
    let state: ClubBadgeState
    let progress: Double
    let rarity: ClubBadgeRarity

    init(
        id: String = UUID().uuidString,
        clubId: String? = nil,
        title: String,
        description: String? = nil,
        subtitle: String,
        icon: String,
        state: ClubBadgeState,
        progress: Double = 1.0,
        rarity: ClubBadgeRarity = .common
    ) {
        self.id = id
        self.clubId = clubId
        self.title = title
        self.description = description ?? subtitle
        self.subtitle = subtitle
        self.icon = icon
        self.state = state
        self.progress = progress
        self.rarity = rarity
    }

    typealias State = ClubBadgeState
}

struct ClubMotivationSummary: Equatable {
    let currentRank: Int
    let previousRank: Int?
    let weeklyContributionDistance: Double
    let weeklyContributionCount: Int
    let contributionPercent: Double
    let nextRankTargetDistance: Double?
    let nextRankTargetLabel: String
    let activeMembersThisWeek: Int
    let newBadgesThisWeek: Int
    let completedChallengesThisWeek: Int
    let clubGoalProgress: Double
    let motivationLine: String

    var rankDelta: Int? {
        guard let previousRank, currentRank > 0 else { return nil }
        return previousRank - currentRank
    }

    var rankMovementLabel: String {
        guard let rankDelta else {
            return "이번 주 위치를 만드는 중"
        }

        if rankDelta > 0 {
            return "지난주보다 \(rankDelta)계단 상승"
        }

        if rankDelta < 0 {
            return "이번 주는 숨 고르는 중"
        }

        return "지난주와 같은 리듬"
    }

    var rankDeltaSymbol: String {
        guard let rankDelta, rankDelta != 0 else { return "→" }
        return rankDelta > 0 ? "▲ \(rankDelta)" : "→"
    }

    var contributionText: String {
        "\(Self.formattedDistance(weeklyContributionDistance))km · 클럽 목표 \(Self.formattedPercent(contributionPercent))"
    }

    var nextGoalText: String {
        if let nextRankTargetDistance {
            return "\(currentRank - 1)위까지 \(Self.formattedDistance(nextRankTargetDistance))km"
        }
        return nextRankTargetLabel
    }

    var activeMembersText: String {
        "이번 주 활성 멤버 \(activeMembersThisWeek)명"
    }

    var newBadgeText: String {
        "새 뱃지 \(newBadgesThisWeek)개"
    }

    var completedChallengeText: String {
        "완료 챌린지 \(completedChallengesThisWeek)개"
    }

    static func defaultSummary(
        currentRank: Int,
        rankMovement: Int,
        contributionDistanceKm: Double,
        weeklyContributionCount: Int,
        activeMembersThisWeek: Int,
        newBadgesThisWeek: Int,
        completedChallengesThisWeek: Int,
        goalProgress: Double,
        motivationLine: String
    ) -> ClubMotivationSummary {
        let previousRank = currentRank > 0 ? max(currentRank + rankMovement, 1) : nil
        let nextTarget = currentRank > 1 ? max(1.2, min(4.8, contributionDistanceKm * 0.08)) : nil
        return ClubMotivationSummary(
            currentRank: currentRank,
            previousRank: previousRank,
            weeklyContributionDistance: contributionDistanceKm,
            weeklyContributionCount: max(weeklyContributionCount, 0),
            contributionPercent: goalProgress > 0 ? min(max((contributionDistanceKm / max(goalProgress * 800, 1)), 0), 0.16) : 0,
            nextRankTargetDistance: nextTarget,
            nextRankTargetLabel: currentRank > 0 ? "다음 순위까지 조금만 더" : "첫 기여를 시작해보세요",
            activeMembersThisWeek: activeMembersThisWeek,
            newBadgesThisWeek: newBadgesThisWeek,
            completedChallengesThisWeek: completedChallengesThisWeek,
            clubGoalProgress: goalProgress,
            motivationLine: motivationLine
        )
    }

    static let emptyNewClub = ClubMotivationSummary(
        currentRank: 1,
        previousRank: nil,
        weeklyContributionDistance: 0,
        weeklyContributionCount: 0,
        contributionPercent: 0,
        nextRankTargetDistance: nil,
        nextRankTargetLabel: "첫 기여를 시작해보세요",
        activeMembersThisWeek: 1,
        newBadgesThisWeek: 1,
        completedChallengesThisWeek: 0,
        clubGoalProgress: 0,
        motivationLine: "아직 랭킹이 만들어지는 중이에요. 첫 움직임이 클럽의 기준이 됩니다."
    )

    private static func formattedDistance(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private static func formattedPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
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
}

struct ClubDetail: Identifiable, Equatable {
    let summary: ClubSummary
    let name: String
    let intro: String
    let purpose: String
    let sport: String
    let owner: String
    let ownerId: String
    let privacy: ClubVisibility
    let activeMembersThisWeek: Int
    let rules: [String]
    let memberPreview: [ClubMemberPreview]
    let members: [ClubMember]
    let identityTags: [String]
    let membershipState: ClubMembershipState
    let memberCount: Int
    let weeklyRank: Int
    let rankMovement: Int
    let contributionDistanceKm: Double
    let goalProgress: Double
    let ranking: [ClubRankingEntry]
    let challenges: [ClubChallenge]
    let badges: [ClubBadge]
    let pulses: [ClubActivityPulse]
    let motivationSummary: ClubMotivationSummary
    let createdAt: Date

    init(
        summary: ClubSummary,
        name: String,
        intro: String,
        purpose: String,
        sport: String,
        owner: String,
        ownerId: String = "local-owner",
        privacy: ClubVisibility,
        activeMembersThisWeek: Int,
        rules: [String],
        memberPreview: [ClubMemberPreview],
        members: [ClubMember]? = nil,
        identityTags: [String],
        membershipState: ClubMembershipState,
        memberCount: Int,
        weeklyRank: Int,
        rankMovement: Int,
        contributionDistanceKm: Double,
        goalProgress: Double,
        ranking: [ClubRankingEntry],
        challenges: [ClubChallenge],
        badges: [ClubBadge],
        pulses: [ClubActivityPulse],
        motivationSummary: ClubMotivationSummary? = nil,
        createdAt: Date = ClubSeedDate.createdAt
    ) {
        self.summary = summary
        self.name = name
        self.intro = intro
        self.purpose = purpose
        self.sport = sport
        self.owner = owner
        self.ownerId = ownerId
        self.privacy = privacy
        self.activeMembersThisWeek = activeMembersThisWeek
        self.rules = rules
        self.memberPreview = memberPreview
        self.members = members ?? Self.members(from: memberPreview, clubId: summary.id)
        self.identityTags = identityTags
        self.membershipState = membershipState
        self.memberCount = memberCount
        self.weeklyRank = weeklyRank
        self.rankMovement = rankMovement
        self.contributionDistanceKm = contributionDistanceKm
        self.goalProgress = goalProgress
        self.ranking = ranking
        self.challenges = challenges
        self.badges = badges
        self.pulses = pulses
        self.motivationSummary = motivationSummary ?? ClubMotivationSummary.defaultSummary(
            currentRank: weeklyRank,
            rankMovement: rankMovement,
            contributionDistanceKm: contributionDistanceKm,
            weeklyContributionCount: ranking.first(where: \.isCurrentUser)?.sessions ?? 0,
            activeMembersThisWeek: activeMembersThisWeek,
            newBadgesThisWeek: badges.filter { $0.state == .newThisWeek || $0.state == .earned }.count,
            completedChallengesThisWeek: challenges.filter { $0.progressRatio >= 1.0 }.count,
            goalProgress: goalProgress,
            motivationLine: membershipState == .recommended
                ? "가입하면 내 기여가 이 클럽의 주간 리듬에 더해져요."
                : "오늘 한 번 더 움직이면 클럽 안에서 내 위치가 조금 더 선명해져요."
        )
        self.createdAt = createdAt
    }

    var id: String {
        summary.id
    }

    var club: ClubDomain {
        ClubDomain(
            id: id,
            name: name,
            intro: intro,
            purpose: purpose,
            sportFocus: sport,
            visibility: privacy,
            ownerId: ownerId,
            memberCount: memberCount,
            createdAt: createdAt,
            isJoined: membershipState == .joined || membershipState == .owned,
            membershipState: membershipState
        )
    }

    var goalPercentText: String {
        "\(Int((goalProgress * 100).rounded()))%"
    }

    var privacyText: String {
        privacy.text
    }

    typealias Privacy = ClubVisibility
    typealias MembershipState = ClubMembershipState

    func withMembershipState(_ state: ClubMembershipState) -> ClubDetail {
        let joinedNow = membershipState == .joined || membershipState == .owned
        let joinedNext = state == .joined || state == .owned
        let adjustedMemberCount = max(0, memberCount + (joinedNext && !joinedNow ? 1 : 0) - (!joinedNext && joinedNow ? 1 : 0))
        let adjustedSummary = ClubSummary(
            id: summary.id,
            name: summary.name,
            sport: summary.sport,
            memberCount: adjustedMemberCount,
            weeklyRank: state == .recommended ? nil : weeklyRank,
            contributionText: state == .recommended ? "가입하면 이번 주 기여가 시작돼요" : summary.contributionText,
            goalPercent: summary.goalPercent,
            tagline: summary.tagline
        )

        return ClubDetail(
            summary: adjustedSummary,
            name: name,
            intro: intro,
            purpose: purpose,
            sport: sport,
            owner: owner,
            ownerId: ownerId,
            privacy: privacy,
            activeMembersThisWeek: activeMembersThisWeek,
            rules: rules,
            memberPreview: memberPreview,
            members: members,
            identityTags: identityTags,
            membershipState: state,
            memberCount: adjustedMemberCount,
            weeklyRank: state == .recommended ? 0 : weeklyRank,
            rankMovement: rankMovement,
            contributionDistanceKm: state == .recommended ? 0 : contributionDistanceKm,
            goalProgress: goalProgress,
            ranking: ranking,
            challenges: challenges,
            badges: badges,
            pulses: pulses,
            motivationSummary: state == .recommended
                ? ClubMotivationSummary(
                    currentRank: 0,
                    previousRank: nil,
                    weeklyContributionDistance: 0,
                    weeklyContributionCount: 0,
                    contributionPercent: 0,
                    nextRankTargetDistance: nil,
                    nextRankTargetLabel: "첫 기여를 시작해보세요",
                    activeMembersThisWeek: activeMembersThisWeek,
                    newBadgesThisWeek: motivationSummary.newBadgesThisWeek,
                    completedChallengesThisWeek: motivationSummary.completedChallengesThisWeek,
                    clubGoalProgress: goalProgress,
                    motivationLine: "가입하면 내 첫 움직임이 클럽 목표에 바로 더해져요."
                )
                : motivationSummary,
            createdAt: createdAt
        )
    }

    private static func members(from previews: [ClubMemberPreview], clubId: String) -> [ClubMember] {
        previews.enumerated().map { index, preview in
            let decimalText = String(preview.activityText.filter { $0.isNumber || $0 == "." })
            let integerText = String(preview.activityText.filter(\.isNumber))
            let role: ClubMemberRole
            if preview.role == "운영자" {
                role = .owner
            } else if preview.role.contains("리더") || preview.role.contains("1위") {
                role = .admin
            } else {
                role = .member
            }

            return ClubMember(
                id: "\(clubId)-member-\(index)",
                clubId: clubId,
                userId: preview.name == "나" ? "current-user" : "\(clubId)-user-\(index)",
                displayName: preview.name,
                handle: "@\(preview.name.lowercased())",
                role: role,
                joinedAt: ClubSeedDate.createdAt,
                weeklyDistance: Double(decimalText) ?? 0,
                weeklyWorkoutCount: preview.activityText.contains("회") ? Int(integerText) ?? 0 : 0,
                consistencyScore: preview.activityText.contains("일") ? Double(integerText) ?? 0 : 0,
                avatarStyle: String(describing: preview.tone)
            )
        }
    }
}

extension ClubRankingCategory {
    var metric: ClubRankingMetric {
        switch self {
        case .distance:
            return .distance
        case .sessions:
            return .workoutCount
        case .consistency:
            return .consistency
        }
    }
}

struct ClubDirectorySnapshot: Equatable {
    let joinedClubs: [ClubDetail]
    let createdClubs: [ClubDetail]
    let recommendedClubs: [ClubSummary]

    static let empty = ClubDirectorySnapshot(joinedClubs: [], createdClubs: [], recommendedClubs: [])

    static func mock(hasJoinedClubs: Bool = true) -> ClubDirectorySnapshot {
        InMemoryClubService.makeSeedDirectory(hasJoinedClubs: hasJoinedClubs)
    }
}

struct ClubSnapshot: Equatable {
    let myClubs: [ClubDomain]
    let createdClubs: [ClubDomain]
    let recommendedClubs: [ClubDomain]
    let selectedClubDetail: ClubDetail?
}

struct ClubCreateInput: Equatable {
    let name: String
    let purpose: String
    let sportFocus: String
    let visibility: ClubVisibility
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

struct ClubActivityPulse: Identifiable, Equatable {
    let id: String
    let icon: String
    let message: String
    let tone: ClubVisualTone

    init(id: String = UUID().uuidString, icon: String, message: String, tone: ClubVisualTone) {
        self.id = id
        self.icon = icon
        self.message = message
        self.tone = tone
    }
}

struct ClubMemberPreview: Identifiable, Equatable {
    let id: String
    let name: String
    let role: String
    let activityText: String
    let tone: ClubVisualTone

    init(id: String = UUID().uuidString, name: String, role: String, activityText: String, tone: ClubVisualTone) {
        self.id = id
        self.name = name
        self.role = role
        self.activityText = activityText
        self.tone = tone
    }
}

protocol ClubService {
    func fetchClubDirectory() async throws -> ClubDirectorySnapshot
    func fetchClubDetail(clubId: String) async throws -> ClubDetail
    func createClub(input: ClubCreateInput) async throws -> ClubDomain
    func joinClub(clubId: String) async throws
    func leaveClub(clubId: String) async throws
    func fetchRankings(clubId: String, metric: ClubRankingMetric) async throws -> [ClubRankingEntry]
    func fetchChallenges(clubId: String) async throws -> [ClubChallenge]
}

enum ClubServiceError: Error, Equatable {
    case clubNotFound
}

final class LocalClubPersistence {
    private struct StoredState: Codable, Equatable {
        var createdClubs: [StoredCreatedClub] = []
        var membershipOverrides: [String: String] = [:]
    }

    private struct StoredCreatedClub: Codable, Equatable {
        let name: String
        let purpose: String
        let sportFocus: String
        let visibility: String

        var input: ClubCreateInput {
            ClubCreateInput(
                name: name,
                purpose: purpose,
                sportFocus: sportFocus,
                visibility: visibility == "private" ? .private : .open
            )
        }
    }

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "soom.club.local.persistence.v1"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadCreatedClubDetails() -> [ClubDetail] {
        loadState().createdClubs.map { ClubDetail.localCreated(input: $0.input) }
    }

    func loadMembershipOverrides() -> [String: ClubMembershipState] {
        loadState().membershipOverrides.compactMapValues(Self.membershipState(from:))
    }

    func saveCreatedClub(input: ClubCreateInput) {
        var state = loadState()
        let stored = StoredCreatedClub(
            name: input.name,
            purpose: input.purpose,
            sportFocus: input.sportFocus,
            visibility: input.visibility == .private ? "private" : "open"
        )
        state.createdClubs.removeAll { ClubDetail.localCreated(input: $0.input).id == ClubDetail.localCreated(input: input).id }
        state.createdClubs.insert(stored, at: 0)
        saveState(state)
    }

    func saveMembershipState(_ membershipState: ClubMembershipState, for clubId: String) {
        var state = loadState()
        state.membershipOverrides[clubId] = Self.rawValue(for: membershipState)
        saveState(state)
    }

    func reset() {
        userDefaults.removeObject(forKey: key)
    }

    private func loadState() -> StoredState {
        guard let data = userDefaults.data(forKey: key) else {
            return StoredState()
        }

        do {
            return try JSONDecoder().decode(StoredState.self, from: data)
        } catch {
            return StoredState()
        }
    }

    private func saveState(_ state: StoredState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: key)
    }

    private static func rawValue(for membershipState: ClubMembershipState) -> String {
        switch membershipState {
        case .joined: return "joined"
        case .recommended: return "recommended"
        case .owned: return "owned"
        }
    }

    private static func membershipState(from rawValue: String) -> ClubMembershipState? {
        switch rawValue {
        case "joined": return .joined
        case "recommended": return .recommended
        case "owned": return .owned
        default: return nil
        }
    }
}

final class InMemoryClubService: ClubService {
    private var detailsByID: [String: ClubDetail]
    private var orderedIDs: [String]
    private let persistence: LocalClubPersistence?

    init(
        details: [ClubDetail] = InMemoryClubService.seedDetails,
        persistence: LocalClubPersistence? = nil
    ) {
        self.persistence = persistence
        var mergedDetails = details

        if let persistence {
            for createdDetail in persistence.loadCreatedClubDetails().reversed() {
                mergedDetails.removeAll { $0.id == createdDetail.id }
                mergedDetails.insert(createdDetail, at: 0)
            }

            let overrides = persistence.loadMembershipOverrides()
            mergedDetails = mergedDetails.map { detail in
                guard let override = overrides[detail.id], detail.membershipState != .owned else {
                    return detail
                }
                return detail.withMembershipState(override)
            }
        }

        self.detailsByID = Dictionary(uniqueKeysWithValues: mergedDetails.map { ($0.id, $0) })
        self.orderedIDs = mergedDetails.map(\.id)
    }

    func fetchClubDirectory() async throws -> ClubDirectorySnapshot {
        directorySnapshot
    }

    func fetchClubDetail(clubId: String) async throws -> ClubDetail {
        guard let detail = detailsByID[clubId] else {
            throw ClubServiceError.clubNotFound
        }
        return detail
    }

    func createClub(input: ClubCreateInput) async throws -> ClubDomain {
        let detail = ClubDetail.localCreated(input: input)
        detailsByID[detail.id] = detail
        if !orderedIDs.contains(detail.id) {
            orderedIDs.insert(detail.id, at: 0)
        }
        persistence?.saveCreatedClub(input: input)
        return detail.club
    }

    func joinClub(clubId: String) async throws {
        guard let detail = detailsByID[clubId] else {
            throw ClubServiceError.clubNotFound
        }
        detailsByID[clubId] = detail.withMembershipState(.joined)
        persistence?.saveMembershipState(.joined, for: clubId)
    }

    func leaveClub(clubId: String) async throws {
        guard let detail = detailsByID[clubId] else {
            throw ClubServiceError.clubNotFound
        }
        guard detail.membershipState != .owned else {
            detailsByID[clubId] = detail
            return
        }
        detailsByID[clubId] = detail.withMembershipState(.recommended)
        persistence?.saveMembershipState(.recommended, for: clubId)
    }

    func fetchRankings(clubId: String, metric: ClubRankingMetric) async throws -> [ClubRankingEntry] {
        guard let detail = detailsByID[clubId] else {
            throw ClubServiceError.clubNotFound
        }
        return detail.ranking
            .sorted { lhs, rhs in
                if lhs.rankingValue(for: metric) == rhs.rankingValue(for: metric) {
                    return lhs.rank < rhs.rank
                }
                return lhs.rankingValue(for: metric) > rhs.rankingValue(for: metric)
            }
            .enumerated()
            .map { index, entry in
                ClubRankingEntry(
                    id: "\(entry.clubId)-\(metric.rawValue)-\(entry.userId)",
                    clubId: entry.clubId,
                    userId: entry.userId,
                    displayName: entry.displayName,
                    rank: index + 1,
                    previousRank: entry.previousRank,
                    metricType: metric,
                    value: entry.rankingValue(for: metric),
                    unit: metric.unit,
                    name: entry.name,
                    distanceKm: entry.distanceKm,
                    sessions: entry.sessions,
                    consistencyDays: entry.consistencyDays,
                    isCurrentUser: entry.isCurrentUser
                )
            }
    }

    func fetchChallenges(clubId: String) async throws -> [ClubChallenge] {
        guard let detail = detailsByID[clubId] else {
            throw ClubServiceError.clubNotFound
        }
        return detail.challenges
    }

    static func makeSeedDirectory(hasJoinedClubs: Bool = true) -> ClubDirectorySnapshot {
        if !hasJoinedClubs {
            return ClubDirectorySnapshot(
                joinedClubs: [],
                createdClubs: [],
                recommendedClubs: [
                    ClubDetail.hangangRiders.summary,
                    ClubDetail.easyRideClub.summary,
                    ClubDetail.weekendRunners.summary
                ]
            )
        }

        let seed = seedDetails
        let recommended = seed
            .filter { $0.membershipState == .recommended }
            .map(\.summary)
        return ClubDirectorySnapshot(
            joinedClubs: seed.filter { $0.membershipState == .joined },
            createdClubs: seed.filter { $0.membershipState == .owned },
            recommendedClubs: recommended
        )
    }

    private var directorySnapshot: ClubDirectorySnapshot {
        let values = orderedIDs.compactMap { detailsByID[$0] }
        return ClubDirectorySnapshot(
            joinedClubs: values.filter { $0.membershipState == .joined },
            createdClubs: values.filter { $0.membershipState == .owned },
            recommendedClubs: values.filter { $0.membershipState == .recommended }.map(\.summary)
        )
    }
}

@MainActor
final class ClubsViewModel: ObservableObject {
    @Published private(set) var directory: ClubDirectorySnapshot = .empty
    @Published private(set) var selectedClub: ClubDetail?
    @Published private(set) var rankings: [ClubRankingEntry] = []
    @Published private(set) var challenges: [ClubChallenge] = []
    @Published private(set) var badges: [ClubBadge] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedRankingMetric: ClubRankingMetric = .distance

    private let service: ClubService

    init(service: ClubService = InMemoryClubService(persistence: LocalClubPersistence())) {
        self.service = service
    }

    func loadDirectory() async {
        isLoading = true
        defer { isLoading = false }

        do {
            directory = try await service.fetchClubDirectory()
            errorMessage = nil
        } catch {
            errorMessage = "클럽 목록을 불러오지 못했어요."
        }
    }

    func openClub(clubId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let detail = try await service.fetchClubDetail(clubId: clubId)
            selectedClub = detail
            rankings = try await service.fetchRankings(clubId: clubId, metric: selectedRankingMetric)
            challenges = try await service.fetchChallenges(clubId: clubId)
            badges = detail.badges
            errorMessage = nil
        } catch {
            errorMessage = "클럽 상세를 불러오지 못했어요."
        }
    }

    func joinClub(clubId: String) async {
        do {
            try await service.joinClub(clubId: clubId)
            directory = try await service.fetchClubDirectory()
            await openClub(clubId: clubId)
            errorMessage = nil
        } catch {
            errorMessage = "클럽 가입을 반영하지 못했어요."
        }
    }

    func leaveClub(clubId: String) async {
        do {
            try await service.leaveClub(clubId: clubId)
            directory = try await service.fetchClubDirectory()
            await openClub(clubId: clubId)
            errorMessage = nil
        } catch {
            errorMessage = "클럽 탈퇴를 반영하지 못했어요."
        }
    }

    @discardableResult
    func createClub(input: ClubCreateInput) async -> ClubDomain? {
        do {
            let club = try await service.createClub(input: input)
            directory = try await service.fetchClubDirectory()
            errorMessage = nil
            return club
        } catch {
            errorMessage = "클럽을 만들지 못했어요."
            return nil
        }
    }

    func selectRankingMetric(_ metric: ClubRankingMetric, clubId: String) async {
        selectedRankingMetric = metric
        do {
            rankings = try await service.fetchRankings(clubId: clubId, metric: metric)
            errorMessage = nil
        } catch {
            errorMessage = "랭킹을 불러오지 못했어요."
        }
    }

    func detail(for clubId: String) -> ClubDetail? {
        if selectedClub?.id == clubId {
            return selectedClub
        }

        if let joined = directory.joinedClubs.first(where: { $0.id == clubId }) {
            return joined
        }

        if let created = directory.createdClubs.first(where: { $0.id == clubId }) {
            return created
        }

        return InMemoryClubService.seedDetails.first { $0.id == clubId }
    }

    func ranking(for clubId: String) -> [ClubRankingEntry] {
        if selectedClub?.id == clubId, !rankings.isEmpty {
            return rankings
        }
        return detail(for: clubId)?.ranking ?? []
    }
}

private enum ClubSeedDate {
    static let createdAt = Date(timeIntervalSince1970: 1_767_228_000)
    static let weekStart = Date(timeIntervalSince1970: 1_767_228_000)
    static let weekEnd = Date(timeIntervalSince1970: 1_767_832_800)
}

extension ClubDetail {
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
        ownerId: "owner-jihwan",
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
            ClubRankingEntry(clubId: "soom-riders", rank: 1, name: "김하늘", distanceKm: 142, sessions: 6, consistencyDays: 6, isCurrentUser: false),
            ClubRankingEntry(clubId: "soom-riders", rank: 2, name: "이도윤", distanceKm: 131, sessions: 5, consistencyDays: 5, isCurrentUser: false),
            ClubRankingEntry(clubId: "soom-riders", rank: 3, name: "박서연", distanceKm: 118, sessions: 5, consistencyDays: 5, isCurrentUser: false),
            ClubRankingEntry(clubId: "soom-riders", rank: 4, name: "최민준", distanceKm: 91, sessions: 4, consistencyDays: 4, isCurrentUser: false),
            ClubRankingEntry(clubId: "soom-riders", rank: 12, name: "나", distanceKm: 42.6, sessions: 3, consistencyDays: 3, isCurrentUser: true)
        ],
        challenges: [
            ClubChallenge(clubId: "soom-riders", title: "이번 주 3회 운동", metricType: .workoutCount, progress: 2, target: 3, unit: "회", subtitle: "한 번만 더 움직이면 개인 목표 달성"),
            ClubChallenge(clubId: "soom-riders", title: "클럽 전체 1,000km", metricType: .distance, progress: 730, target: 1_000, unit: "km", subtitle: "412명이 함께 채우는 주간 거리"),
            ClubChallenge(clubId: "soom-riders", title: "아침 운동 챌린지", metricType: .consistency, progress: 4, target: 7, unit: "일", subtitle: "4일 남음")
        ],
        badges: [
            ClubBadge(clubId: "soom-riders", title: "1000km", subtitle: "획득", icon: SOOMIcon.medal, state: .earned),
            ClubBadge(clubId: "soom-riders", title: "30일 연속", subtitle: "진행 중", icon: SOOMIcon.calendarClock, state: .inProgress, progress: 0.7),
            ClubBadge(clubId: "soom-riders", title: "Century Ride", subtitle: "희귀", icon: SOOMIcon.bike, state: .rare, rarity: .rare),
            ClubBadge(clubId: "soom-riders", title: "회복 라이딩", subtitle: "이번 주", icon: SOOMIcon.recovery, state: .newThisWeek)
        ],
        pulses: [
            ClubActivityPulse(icon: SOOMIcon.people, message: "이번 주 활성 멤버 42명이 리듬을 이어갔어요", tone: .ink),
            ClubActivityPulse(icon: SOOMIcon.medal, message: "새 뱃지 8개가 클럽 안에서 열렸어요", tone: .warning),
            ClubActivityPulse(icon: SOOMIcon.checkCircle, message: "클럽 목표가 73%까지 찼어요", tone: .recovery),
            ClubActivityPulse(icon: SOOMIcon.trendUp, message: "내가 클럽 거리의 8%를 기여했어요", tone: .bike)
        ],
        motivationSummary: ClubMotivationSummary(
            currentRank: 12,
            previousRank: 18,
            weeklyContributionDistance: 42.6,
            weeklyContributionCount: 3,
            contributionPercent: 0.08,
            nextRankTargetDistance: 3.4,
            nextRankTargetLabel: "11위까지 3.4km",
            activeMembersThisWeek: 42,
            newBadgesThisWeek: 8,
            completedChallengesThisWeek: 2,
            clubGoalProgress: 0.73,
            motivationLine: "이번 주는 이미 클럽 거리의 8%를 채웠어요. 한 번만 더 움직이면 한 계단 더 가까워져요."
        )
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
        ownerId: "owner-sora",
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
            ClubRankingEntry(clubId: "morning-runners", rank: 1, name: "문소라", distanceKm: 64.2, sessions: 5, consistencyDays: 5, isCurrentUser: false),
            ClubRankingEntry(clubId: "morning-runners", rank: 2, name: "강지훈", distanceKm: 52.8, sessions: 4, consistencyDays: 4, isCurrentUser: false),
            ClubRankingEntry(clubId: "morning-runners", rank: 3, name: "윤하민", distanceKm: 41.5, sessions: 4, consistencyDays: 4, isCurrentUser: false),
            ClubRankingEntry(clubId: "morning-runners", rank: 8, name: "나", distanceKm: 18.4, sessions: 3, consistencyDays: 3, isCurrentUser: true)
        ],
        challenges: [
            ClubChallenge(clubId: "morning-runners", title: "아침 3회 뛰기", metricType: .workoutCount, progress: 2, target: 3, unit: "회", subtitle: "짧아도 아침 리듬이 쌓이면 충분해요"),
            ClubChallenge(clubId: "morning-runners", title: "클럽 전체 300km", metricType: .distance, progress: 192, target: 300, unit: "km", subtitle: "128명이 함께 채우는 주간 거리"),
            ClubChallenge(clubId: "morning-runners", title: "회복 조깅 챌린지", metricType: .consistency, progress: 5, target: 7, unit: "일", subtitle: "2일 남음")
        ],
        badges: [
            ClubBadge(clubId: "morning-runners", title: "Morning 10", subtitle: "획득", icon: SOOMIcon.calendar, state: .earned),
            ClubBadge(clubId: "morning-runners", title: "5km 루틴", subtitle: "진행 중", icon: SOOMIcon.run, state: .inProgress, progress: 0.55),
            ClubBadge(clubId: "morning-runners", title: "비 오는 날", subtitle: "이번 주", icon: SOOMIcon.sparkles, state: .newThisWeek),
            ClubBadge(clubId: "morning-runners", title: "꾸준함", subtitle: "희귀", icon: SOOMIcon.medal, state: .rare, rarity: .rare)
        ],
        pulses: [
            ClubActivityPulse(icon: SOOMIcon.people, message: "오늘 12명이 아침 운동을 완료했어요", tone: .ink),
            ClubActivityPulse(icon: SOOMIcon.checkCircle, message: "아침 3회 뛰기 챌린지가 68%까지 찼어요", tone: .recovery),
            ClubActivityPulse(icon: SOOMIcon.trendUp, message: "내가 클럽 거리의 6%를 기여했어요", tone: .run)
        ],
        motivationSummary: ClubMotivationSummary(
            currentRank: 8,
            previousRank: 11,
            weeklyContributionDistance: 18.4,
            weeklyContributionCount: 3,
            contributionPercent: 0.06,
            nextRankTargetDistance: 2.1,
            nextRankTargetLabel: "7위까지 2.1km",
            activeMembersThisWeek: 19,
            newBadgesThisWeek: 5,
            completedChallengesThisWeek: 1,
            clubGoalProgress: 0.64,
            motivationLine: "짧게 한 번만 더 뛰면 아침 리듬이 이번 주 랭킹에도 남아요."
        )
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
        ownerId: "owner-jihwan",
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
            ClubRankingEntry(clubId: "recovery-crew", rank: 1, name: "서유진", distanceKm: 28.4, sessions: 6, consistencyDays: 6, isCurrentUser: false),
            ClubRankingEntry(clubId: "recovery-crew", rank: 2, name: "한도겸", distanceKm: 24.0, sessions: 5, consistencyDays: 5, isCurrentUser: false),
            ClubRankingEntry(clubId: "recovery-crew", rank: 4, name: "나", distanceKm: 12.0, sessions: 4, consistencyDays: 4, isCurrentUser: true)
        ],
        challenges: [
            ClubChallenge(clubId: "recovery-crew", title: "회복 운동 4회", metricType: .workoutCount, progress: 3, target: 4, unit: "회", subtitle: "강도보다 이어가는 리듬에 집중해요"),
            ClubChallenge(clubId: "recovery-crew", title: "클럽 전체 120km", metricType: .distance, progress: 62, target: 120, unit: "km", subtitle: "가볍게 쌓는 공동 목표")
        ],
        badges: [
            ClubBadge(clubId: "recovery-crew", title: "회복 루틴", subtitle: "획득", icon: SOOMIcon.recovery, state: .earned),
            ClubBadge(clubId: "recovery-crew", title: "가벼운 4회", subtitle: "진행 중", icon: SOOMIcon.checkCircle, state: .inProgress, progress: 0.75),
            ClubBadge(clubId: "recovery-crew", title: "균형", subtitle: "이번 주", icon: SOOMIcon.sparkles, state: .newThisWeek)
        ],
        pulses: [
            ClubActivityPulse(icon: SOOMIcon.recovery, message: "서유진이 회복 루틴 배지를 획득했어요", tone: .recovery),
            ClubActivityPulse(icon: SOOMIcon.checkCircle, message: "클럽 목표가 52%까지 찼어요", tone: .bike)
        ],
        motivationSummary: ClubMotivationSummary(
            currentRank: 4,
            previousRank: 7,
            weeklyContributionDistance: 12.0,
            weeklyContributionCount: 4,
            contributionPercent: 0.10,
            nextRankTargetDistance: 1.8,
            nextRankTargetLabel: "3위까지 1.8km",
            activeMembersThisWeek: 21,
            newBadgesThisWeek: 3,
            completedChallengesThisWeek: 1,
            clubGoalProgress: 0.52,
            motivationLine: "무리하지 않는 네 번의 움직임이 이 클럽의 회복 리듬을 만들고 있어요."
        )
    )

    static let hangangRiders = recommendedDetail(
        id: "hangang-riders",
        name: "한강 라이더스",
        sport: "자전거",
        memberCount: 284,
        contributionText: "초보 라이딩 중심",
        goalPercent: 61,
        tagline: "강변 코스를 꾸준히 타는 사람들",
        intro: "강변 코스를 꾸준히 타는 온라인 라이더 클럽",
        purpose: "한강 주변 코스를 기준으로 초보도 부담 없이 주간 기여를 쌓습니다.",
        owner: "하늘",
        activeMembersThisWeek: 72,
        tags: ["강변", "초보 환영", "주말 라이딩", "꾸준함"],
        distance: 21.4
    )

    static let easyRideClub = recommendedDetail(
        id: "easy-ride-club",
        name: "초보 라이딩",
        sport: "자전거",
        memberCount: 93,
        contributionText: "주 2회 완주 챌린지",
        goalPercent: 44,
        tagline: "빠르게보다 오래 이어가는 클럽",
        intro: "속도보다 완주 감각을 먼저 쌓는 라이딩 클럽",
        purpose: "처음 시작하는 라이더가 서로의 페이스를 존중하며 주 2회 움직입니다.",
        owner: "민준",
        activeMembersThisWeek: 31,
        tags: ["입문", "완주", "페이스 존중", "회복"],
        distance: 14.8
    )

    static let weekendRunners = recommendedDetail(
        id: "weekend-runners",
        name: "주말 러너스",
        sport: "러닝",
        memberCount: 156,
        contributionText: "주말 5km부터",
        goalPercent: 58,
        tagline: "토요일 아침을 같이 시작해요",
        intro: "주말 아침을 같이 여는 온라인 러닝 클럽",
        purpose: "주말 5km부터 시작해 부담 없는 반복 리듬을 만듭니다.",
        owner: "서윤",
        activeMembersThisWeek: 49,
        tags: ["주말", "5km", "아침 러닝", "초보 환영"],
        distance: 9.6
    )

    static func localCreated(input: ClubCreateInput) -> ClubDetail {
        let id = "local-\(input.name.lowercased().replacingOccurrences(of: " ", with: "-"))"
        return ClubDetail(
            summary: ClubSummary(
                id: id,
                name: input.name,
                sport: input.sportFocus,
                memberCount: 1,
                weeklyRank: 1,
                contributionText: "방금 만든 클럽",
                goalPercent: 0,
                tagline: input.purpose
            ),
            name: input.name,
            intro: input.purpose,
            purpose: input.purpose,
            sport: input.sportFocus,
            owner: "나",
            ownerId: "current-user",
            privacy: input.visibility,
            activeMembersThisWeek: 1,
            rules: ["기록 조작 없이 실제 움직임만 반영합니다.", "서로의 페이스를 존중합니다."],
            memberPreview: [
                ClubMemberPreview(name: "나", role: "운영자", activityText: "첫 챌린지 준비", tone: .ink)
            ],
            identityTags: [input.sportFocus, "새 클럽", input.visibility.text],
            membershipState: .owned,
            memberCount: 1,
            weeklyRank: 1,
            rankMovement: 0,
            contributionDistanceKm: 0,
            goalProgress: 0,
            ranking: [
                ClubRankingEntry(clubId: id, rank: 1, name: "나", distanceKm: 0, sessions: 0, consistencyDays: 0, isCurrentUser: true)
            ],
            challenges: [
                ClubChallenge(clubId: id, title: "첫 주 3회 움직이기", metricType: .workoutCount, progress: 0, target: 3, unit: "회", subtitle: "클럽의 첫 리듬을 만듭니다.")
            ],
            badges: [
                ClubBadge(clubId: id, title: "첫 클럽", subtitle: "획득", icon: SOOMIcon.clubs, state: .earned)
            ],
            pulses: [
                ClubActivityPulse(icon: SOOMIcon.sparkles, message: "\(input.name)이 만들어졌어요", tone: .bike)
            ],
            motivationSummary: .emptyNewClub,
            createdAt: Date()
        )
    }

    private static func recommendedDetail(
        id: String,
        name: String,
        sport: String,
        memberCount: Int,
        contributionText: String,
        goalPercent: Int,
        tagline: String,
        intro: String,
        purpose: String,
        owner: String,
        activeMembersThisWeek: Int,
        tags: [String],
        distance: Double
    ) -> ClubDetail {
        ClubDetail(
            summary: ClubSummary(
                id: id,
                name: name,
                sport: sport,
                memberCount: memberCount,
                weeklyRank: nil,
                contributionText: contributionText,
                goalPercent: goalPercent,
                tagline: tagline
            ),
            name: name,
            intro: intro,
            purpose: purpose,
            sport: sport,
            owner: owner,
            ownerId: "owner-\(id)",
            privacy: .open,
            activeMembersThisWeek: activeMembersThisWeek,
            rules: ["클럽 안 랭킹만 표시합니다.", "무리한 비교보다 꾸준한 참여를 봅니다.", "공개 운동 기록만 기여에 반영합니다."],
            memberPreview: [
                ClubMemberPreview(name: owner, role: "운영자", activityText: "\(String(format: "%.1f", distance * 2))km", tone: .ink),
                ClubMemberPreview(name: "리더", role: "이번 주 1위", activityText: "\(String(format: "%.1f", distance * 3))km", tone: .bike),
                ClubMemberPreview(name: "새 멤버", role: "최근 합류", activityText: "첫 챌린지", tone: .green)
            ],
            identityTags: tags,
            membershipState: .recommended,
            memberCount: memberCount,
            weeklyRank: 0,
            rankMovement: 0,
            contributionDistanceKm: 0,
            goalProgress: Double(goalPercent) / 100,
            ranking: [
                ClubRankingEntry(clubId: id, rank: 1, name: "리더", distanceKm: distance * 3, sessions: 5, consistencyDays: 5, isCurrentUser: false),
                ClubRankingEntry(clubId: id, rank: 2, name: owner, distanceKm: distance * 2, sessions: 4, consistencyDays: 4, isCurrentUser: false),
                ClubRankingEntry(clubId: id, rank: 24, name: "나", distanceKm: 0, sessions: 0, consistencyDays: 0, isCurrentUser: true)
            ],
            challenges: [
                ClubChallenge(clubId: id, title: "이번 주 3회 움직이기", metricType: .workoutCount, progress: 1, target: 3, unit: "회", subtitle: "가입하면 내 기여가 시작돼요"),
                ClubChallenge(clubId: id, title: "클럽 전체 목표", metricType: .distance, progress: Double(goalPercent), target: 100, unit: "%", subtitle: "이번 주 목표 진행률")
            ],
            badges: [
                ClubBadge(clubId: id, title: "첫 기여", subtitle: "진행 중", icon: SOOMIcon.medal, state: .inProgress, progress: 0.2),
                ClubBadge(clubId: id, title: "꾸준함", subtitle: "잠김", icon: SOOMIcon.calendarClock, state: .locked, progress: 0)
            ],
            pulses: [
                ClubActivityPulse(icon: SOOMIcon.people, message: "이번 주 \(activeMembersThisWeek)명이 움직였어요", tone: .ink),
                ClubActivityPulse(icon: SOOMIcon.trendUp, message: "클럽 목표가 \(goalPercent)%까지 찼어요", tone: .bike)
            ]
        )
    }
}

extension InMemoryClubService {
    static let seedDetails: [ClubDetail] = [
        .soomRiders,
        .morningRunners,
        .recoveryCrew,
        .hangangRiders,
        .easyRideClub,
        .weekendRunners
    ]
}
