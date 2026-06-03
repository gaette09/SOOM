import SwiftUI

struct ClubsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var clubViewModel: ClubsViewModel
    @State private var isCreateSheetPresented = false

    @MainActor
    init() {
        _clubViewModel = StateObject(wrappedValue: ClubsViewModel())
    }

    @MainActor
    init(viewModel: ClubsViewModel) {
        _clubViewModel = StateObject(wrappedValue: viewModel)
    }

    private var directory: ClubDirectorySnapshot {
        clubViewModel.directory
    }

    var body: some View {
        SOOMScreen {
            ClubHomeHeader(onCreate: { isCreateSheetPresented = true })

            if directory.joinedClubs.isEmpty {
                ClubEmptyStateView(
                    recommendedClubs: directory.recommendedClubs,
                    viewModel: clubViewModel,
                    onCreate: { isCreateSheetPresented = true }
                )
            } else {
                ClubHomeSection(title: "내 클럽", caption: "여러 클럽 안에서 이번 주 내 위치를 봅니다.") {
                    ForEach(directory.joinedClubs) { detail in
                        NavigationLink {
                            ClubDashboardDetailView(viewModel: clubViewModel, clubId: detail.id)
                        } label: {
                            ClubHomeCard(summary: detail.summary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ClubHomeSection(title: "내가 만든 클럽", caption: "운영보다 소속감과 주간 기여를 먼저 보여줍니다.") {
                    ForEach(directory.createdClubs) { detail in
                        NavigationLink {
                            ClubDashboardDetailView(viewModel: clubViewModel, clubId: detail.id)
                        } label: {
                            ClubHomeCard(summary: detail.summary, isOwned: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ClubHomeSection(title: "추천 클럽", caption: "비슷한 리듬의 온라인 클럽을 가볍게 둘러봅니다.") {
                    ForEach(directory.recommendedClubs) { summary in
                        NavigationLink {
                            ClubDashboardDetailView(viewModel: clubViewModel, clubId: summary.id)
                        } label: {
                            ClubRecommendedCard(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: authViewModel.session.currentUser?.id) {
            clubViewModel.configure(service: ClubServiceResolver.makeDefaultService(
                currentUserID: authViewModel.session.currentUser?.authProvider == .supabase
                    ? authViewModel.session.currentUser?.id
                    : nil
            ))
            await clubViewModel.loadDirectory()
        }
        .sheet(isPresented: $isCreateSheetPresented) {
            ClubCreateSheet { input in
                Task {
                    await clubViewModel.createClub(input: input)
                    isCreateSheetPresented = false
                }
            }
                .presentationDetents([.height(520)])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ClubDashboardDetailView: View {
    @ObservedObject var viewModel: ClubsViewModel
    let clubId: String
    @State private var rankingCategory: ClubRankingCategory = .distance
    @State private var isMembershipSheetPresented = false

    private var detail: ClubDetail {
        viewModel.detail(for: clubId) ?? .soomRiders
    }

    private var ranking: [ClubRankingEntry] {
        viewModel.ranking(for: clubId)
    }

    private var challenges: [ClubChallenge] {
        viewModel.selectedClub?.id == clubId && !viewModel.challenges.isEmpty
            ? viewModel.challenges
            : detail.challenges
    }

    var body: some View {
        SOOMScreen {
            ClubStatusHero(
                detail: detail,
                onMembershipAction: { handleMembershipAction() }
            )
            ClubPurposeRulesSection(detail: detail)
            ClubMemberPreviewSection(members: detail.memberPreview)
            ClubNextGoalCard(summary: detail.motivationSummary, rankingCategory: rankingCategory)
            ClubWeeklyRankingSection(
                clubName: detail.name,
                motivationSummary: detail.motivationSummary,
                ranking: ranking,
                selectedCategory: $rankingCategory
            )
            ClubChallengesSection(challenges: challenges)
            ClubBadgeWallSection(badges: viewModel.selectedClub?.id == clubId ? viewModel.badges : detail.badges)
            ClubActivityPulseSection(pulses: detail.pulses)
        }
        .navigationTitle(detail.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: clubId) {
            await viewModel.openClub(clubId: clubId)
        }
        .onChange(of: rankingCategory) { _, category in
            Task {
                await viewModel.selectRankingMetric(category.metric, clubId: clubId)
            }
        }
        .sheet(isPresented: $isMembershipSheetPresented) {
            ClubMembershipPlaceholderSheet(
                state: detail.membershipState,
                onLeave: {
                    Task {
                        await viewModel.leaveClub(clubId: clubId)
                        isMembershipSheetPresented = false
                    }
                }
            )
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
    }

    private func handleMembershipAction() {
        switch detail.membershipState {
        case .recommended:
            Task {
                await viewModel.joinClub(clubId: clubId)
            }
        case .joined, .owned, .admin:
            isMembershipSheetPresented = true
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

                ClubMotivationSummaryStrip(summary: detail.motivationSummary)

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

private struct ClubMotivationSummaryStrip: View {
    let summary: ClubMotivationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
            HStack(spacing: SOOMLayout.Metrics.gridSpacing) {
                ClubMiniMotivationTile(
                    label: "순위 변화",
                    value: summary.rankDeltaSymbol,
                    caption: summary.rankMovementLabel,
                    tint: SOOMColor.accent
                )
                ClubMiniMotivationTile(
                    label: "내 기여",
                    value: String(format: "%.1fkm", summary.weeklyContributionDistance),
                    caption: "클럽 목표 \(Int((summary.contributionPercent * 100).rounded()))%",
                    tint: SOOMColor.ink
                )
            }

            Text(summary.motivationLine)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(SOOMColor.accentSurface.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("클럽 동기부여 요약")
        .accessibilityValue("\(summary.rankMovementLabel), \(summary.contributionText), \(summary.nextGoalText)")
    }
}

private struct ClubMiniMotivationTile: View {
    let label: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)
            Text(value)
                .font(SOOMFont.body(18, weight: .bold, relativeTo: .headline))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(caption)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let motivationSummary: ClubMotivationSummary
    let ranking: [ClubRankingEntry]
    @Binding var selectedCategory: ClubRankingCategory

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("\(clubName) 내 이번 주 랭킹", caption: rankingCaption)

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

    private var rankingCaption: String {
        guard motivationSummary.currentRank > 0 else {
            return "첫 기여가 생기면 내 위치가 만들어져요."
        }

        return "내 위치: \(motivationSummary.currentRank)위 · \(motivationSummary.nextGoalText)"
    }
}

private struct ClubNextGoalCard: View {
    let summary: ClubMotivationSummary
    let rankingCategory: ClubRankingCategory

    private var nextActionText: String {
        if summary.currentRank <= 1 && summary.weeklyContributionDistance > 0 {
            return "오늘은 무리해서 올리기보다 지금의 기준을 유지해도 좋아요."
        }

        switch rankingCategory {
        case .distance:
            if let distance = summary.nextRankTargetDistance, distance > 0 {
                return "오늘 20분만 더 움직이면 \(String(format: "%.1f", distance))km만큼 가까워져요."
            }
            return "첫 거리를 쌓으면 클럽 안 내 위치가 생겨요."
        case .sessions:
            return "한 번만 더 기록하면 운동 횟수 랭킹이 가까워져요."
        case .consistency:
            return "하루만 더 이어가면 꾸준함 랭킹이 흔들리지 않아요."
        }
    }

    var body: some View {
        SOOMCard(depth: .secondary) {
            HStack(alignment: .top, spacing: SOOMLayout.Metrics.rowSpacing) {
                Image(systemName: SOOMIcon.trendUp)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SOOMColor.accent)
                    .frame(width: 42, height: 42)
                    .background(SOOMColor.accentSurface)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("다음 목표")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.accent)
                    Text(summary.nextGoalText)
                        .font(SOOMFont.body(18, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(nextActionText)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("다음 목표")
        .accessibilityValue("\(summary.nextGoalText), \(nextActionText)")
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
                            Text(challenge.nextActionLine)
                                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                                .foregroundStyle(SOOMColor.accent)
                                .lineLimit(2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(challenge.remainingLabel)
                                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                                .foregroundStyle(SOOMColor.accent)
                            Text(challenge.progressText)
                                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                                .foregroundStyle(SOOMColor.tertiaryInk)
                        }
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
    @ObservedObject var viewModel: ClubsViewModel
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
                    NavigationLink {
                        ClubDashboardDetailView(viewModel: viewModel, clubId: summary.id)
                    } label: {
                        ClubRecommendedCard(summary: summary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ClubCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var purpose = ""
    @State private var sportFocus = "자전거"
    @State private var visibility: ClubVisibility = .open
    let onCreate: (ClubCreateInput) -> Void

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                Text("클럽 만들기")
                    .font(SOOMFont.body(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Text("지금 만든 클럽은 이 기기에서 먼저 저장돼요. 초대와 멤버 관리는 곧 더 자세히 연결됩니다.")
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                TextField("클럽 이름", text: $name)
                    .textInputAutocapitalization(.never)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .padding(14)
                    .background(SOOMColor.surfaceAmbient)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))

                TextField("클럽 목적", text: $purpose)
                    .font(SOOMFont.body(15, relativeTo: .subheadline))
                    .padding(14)
                    .background(SOOMColor.surfaceAmbient)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))

                Picker("대표 종목", selection: $sportFocus) {
                    Text("자전거").tag("자전거")
                    Text("러닝").tag("러닝")
                    Text("걷기").tag("걷기")
                    Text("혼합").tag("혼합")
                }
                .pickerStyle(.segmented)

                Picker("공개 범위", selection: $visibility) {
                    Text("공개").tag(ClubVisibility.open)
                    Text("비공개").tag(ClubVisibility.private)
                }
                .pickerStyle(.segmented)
            }

            Button {
                let input = ClubCreateInput(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                    sportFocus: sportFocus,
                    visibility: visibility
                )
                onCreate(input)
                dismiss()
            } label: {
                Text("클럽 만들기")
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canCreate ? SOOMColor.accent : SOOMColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canCreate)
        }
        .padding(SOOMLayout.screenPadding)
        .background(SOOMColor.background)
    }
}

private struct ClubMembershipPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ClubDetail.MembershipState
    let onLeave: (() -> Void)?

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
                Text("클럽 상태와 세부 관리는 곧 더 자세히 연결됩니다.")
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if (state == .joined || state == .admin), let onLeave {
                Button {
                    onLeave()
                    dismiss()
                } label: {
                    Text("클럽 나가기")
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(SOOMColor.accentSurface)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(SOOMLayout.screenPadding)
        .background(SOOMColor.background)
    }
}
