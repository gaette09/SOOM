import SwiftUI
#if DEBUG && targetEnvironment(simulator)
import Supabase
#endif

struct ClubsView: View {
    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var clubViewModel: ClubsViewModel
    @State private var isCreateSheetPresented = false
    #if DEBUG && targetEnvironment(simulator)
    @State private var qaControl = UXClubFixtureControl()
    #endif

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

    private var directoryIsEmpty: Bool {
        directory.joinedClubs.isEmpty && directory.createdClubs.isEmpty && directory.recommendedClubs.isEmpty
    }

    var body: some View {
        SOOMScreen(tracksTabBarScroll: true) {
            ClubHomeHeader(onCreate: { isCreateSheetPresented = true })

            if clubViewModel.shouldShowLocalFallbackBanner {
                ClubLocalFallbackBanner()
            }

            if let error = clubViewModel.errorMessage {
                ClubRetryCard(message: error) {
                    #if DEBUG && targetEnvironment(simulator)
                    qaControl.allowDirectoryRetry = true
                    #endif
                    Task { await clubViewModel.loadDirectory() }
                }
            }
            if clubViewModel.isLoading && directoryIsEmpty {
                SOOMSkeleton(layout: .workout, label: "클럽 목록을 불러오는 중").accessibilityIdentifier("clubs.loading")
            } else if clubViewModel.errorMessage == nil && directoryIsEmpty {
                ClubEmptyStateView(
                    recommendedClubs: directory.recommendedClubs,
                    viewModel: clubViewModel,
                    onCreate: { isCreateSheetPresented = true }
                )
            } else {
                ClubHomeSection(title: "내 클럽", caption: "여러 클럽 안에서 이번 주 내 위치를 봅니다.") {
                    ForEach(directory.joinedClubs) { detail in
                        ClubSafetyRow(clubID: detail.id, isLocalFallback: clubViewModel.isShowingLocalFallbackData) {
                        NavigationLink {
                            ClubDashboardDetailView(viewModel: clubViewModel, clubId: detail.id)
                        } label: {
                            ClubHomeCard(summary: detail.summary)
                        }
                        .buttonStyle(.plain)
                        }
                    }
                }

                ClubHomeSection(title: "내가 만든 클럽", caption: "운영보다 소속감과 주간 기여를 먼저 보여줍니다.") {
                    ForEach(directory.createdClubs) { detail in
                        ClubSafetyRow(clubID: detail.id, isLocalFallback: clubViewModel.isShowingLocalFallbackData) {
                        NavigationLink {
                            ClubDashboardDetailView(viewModel: clubViewModel, clubId: detail.id)
                        } label: {
                            ClubHomeCard(summary: detail.summary, isOwned: true)
                        }
                        .buttonStyle(.plain)
                        }
                    }
                }

                ClubHomeSection(title: "추천 클럽", caption: "비슷한 리듬의 온라인 클럽을 가볍게 둘러봅니다.") {
                    ForEach(directory.recommendedClubs) { summary in
                        ClubSafetyRow(clubID: summary.id, isLocalFallback: clubViewModel.isShowingLocalFallbackData) {
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: authViewModel.session.currentUser?.id) {
            if ReviewDemoMode.isActive {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
                   let scenario = ProcessInfo.processInfo.environment["SOOM_UX_CLUB_STATE"] {
                    clubViewModel.configure(service: UXClubServiceFixture(wrapped: ReviewDemoCommunityStore.shared.clubs, scenario: scenario, control: qaControl))
                } else { clubViewModel.configure(service: ReviewDemoCommunityStore.shared.clubs) }
                #else
                clubViewModel.configure(service: ReviewDemoCommunityStore.shared.clubs)
                #endif
                await clubViewModel.loadDirectory()
                return
            }
            clubViewModel.configure(service: ClubServiceResolver.makeDefaultService(
                currentUserID: authViewModel.session.currentUser?.authProvider == .supabase
                    ? authViewModel.session.currentUser?.id
                    : nil,
                onDidUseFallback: clubViewModel.markUsingLocalFallback
            ))
            await clubViewModel.loadDirectory()
        }
        .onChange(of: safetyStore.revision) { _, _ in
            Task { await clubViewModel.loadDirectory() }
        }
        .suspendsSOOMTabBarScrollMotion(when: isCreateSheetPresented)
        .sheet(isPresented: $isCreateSheetPresented) {
            ClubCreateSheet { input in
                try await clubViewModel.createClub(input: input)
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ClubSafetyRow<Content: View>: View {
    let clubID: String
    let isLocalFallback: Bool
    @ViewBuilder let content: () -> Content
    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    @State private var identity: CommunityClubIdentity?
    @State private var verifiedAccountGeneration: Int?
    @State private var hasVerified = false
    @State private var identityRetryRevision = 0

    var body: some View {
        Group {
            if (ReviewDemoMode.isActive || UUID(uuidString: clubID) != nil),
               !hasVerified || verifiedAccountGeneration != safetyStore.accountGeneration {
                SOOMSkeleton(layout: .summary, label: "클럽 공개 범위 확인 중")
            } else if (ReviewDemoMode.isActive || UUID(uuidString: clubID) != nil), identity == nil {
                VStack(alignment: .leading, spacing: SOOMLayout.Spacing.sm) {
                    Text("클럽 정보를 확인하지 못했어요. 다시 불러와 주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("다시 확인") {
                        hasVerified = false
                        identity = nil
                        identityRetryRevision += 1
                    }
                    .accessibilityIdentifier("club.identity.retry.\(clubID)")
                    .frame(minHeight: 44)
                }
            } else if identity.map({ safetyStore.isBlocked($0.ownerID) }) != true {
                HStack(alignment: .top, spacing: SOOMLayout.Spacing.sm) {
                    content()
                    if let identity,
                       verifiedAccountGeneration == safetyStore.accountGeneration,
                       identity.ownerID != safetyStore.viewerID {
                        CommunitySafetyMenu(
                            target: CommunityReportTarget(kind: .club, id: identity.id),
                            authorID: identity.ownerID,
                            authorName: "클럽 운영자"
                        )
                    }
                }
            }
        }
        .task(id: "\(clubID):\(safetyStore.revision):\(isLocalFallback):\(identityRetryRevision)") {
            guard (ReviewDemoMode.isActive || UUID(uuidString: clubID) != nil) else { identity = nil; return }
            let generation = safetyStore.accountGeneration
            let result = try? await safetyStore.verifiedClubIdentity(clubID: clubID)
            guard !Task.isCancelled, generation == safetyStore.accountGeneration else { return }
            identity = result
            verifiedAccountGeneration = generation
            hasVerified = true
        }
    }
}

private struct ClubDashboardDetailView: View {
    @ObservedObject var viewModel: ClubsViewModel
    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    @State private var verifiedIdentity: CommunityClubIdentity?
    @State private var isVerifyingIdentity = true
    @State private var verifiedAccountGeneration: Int?
    let clubId: String
    @State private var rankingCategory: ClubRankingCategory = .distance
    @State private var isMembershipSheetPresented = false

    private var detail: ClubDetail? {
        viewModel.detail(for: clubId)
    }

    private var ranking: [ClubRankingEntry] {
        viewModel.ranking(for: clubId)
    }

    var body: some View {
        Group {
            if (ReviewDemoMode.isActive || UUID(uuidString: clubId) != nil) && isVerifyingIdentity {
                ScrollView { SOOMSkeleton(layout: .detail, label: "클럽 상세 확인 중").padding(SOOMLayout.screenPadding) }
            } else if (ReviewDemoMode.isActive || UUID(uuidString: clubId) != nil) && (verifiedIdentity == nil
                || verifiedAccountGeneration != safetyStore.accountGeneration
                || verifiedIdentity.map { safetyStore.isBlocked($0.ownerID) } == true) {
                CommunityContentUnavailableView()
            } else if let detail {
                clubContent(detail: detail)
            } else if viewModel.isLoading {
                ScrollView { SOOMSkeleton(layout: .detail, label: "클럽 상세 확인 중").padding(SOOMLayout.screenPadding) }
            } else if let error = viewModel.errorMessage {
                ClubRetryCard(message: error) { Task { await viewModel.openClub(clubId: clubId) } }.padding()
            } else {
                CommunityContentUnavailableView()
            }
        }
        .task(id: "\(clubId):\(safetyStore.revision)") {
            await viewModel.openClub(clubId: clubId)
        }
        .task(id: "identity:\(clubId):\(safetyStore.revision)") {
            let generation = safetyStore.accountGeneration
            let identity = try? await safetyStore.verifiedClubIdentity(clubID: clubId)
            guard !Task.isCancelled, generation == safetyStore.accountGeneration else { return }
            verifiedIdentity = identity
            verifiedAccountGeneration = generation
            isVerifyingIdentity = false
        }
    }

    private func clubContent(detail: ClubDetail) -> some View {
        SOOMScreen {
            if let error = viewModel.errorMessage {
                ClubRetryCard(message: error) {
                    Task {
                        if viewModel.rankingError != nil { await viewModel.selectRankingMetric(rankingCategory.metric, clubId: clubId) }
                        else { await viewModel.openClub(clubId: clubId) }
                    }
                }
            }
            if viewModel.membershipOperation != nil { ProgressView("가입 상태를 반영하는 중").accessibilityIdentifier("clubs.membership.busy") }
            ClubStatusHero(
                detail: detail,
                onMembershipAction: { handleMembershipAction(detail: detail) }
            ).disabled(viewModel.membershipOperation != nil || viewModel.isLoading)
            if ReviewDemoMode.isActive {
                ClubWorkoutFeedSection(clubID: ReviewDemoCommunityStore.shared.clubID(for: clubId), membershipState: detail.membershipState)
            } else if let id = UUID(uuidString: clubId), !viewModel.isShowingLocalFallbackData {
                ClubWorkoutFeedSection(clubID: id, membershipState: detail.membershipState)
            }
            ClubPurposeRulesSection(detail: detail)
            ClubMemberPreviewSection(members: detail.memberPreview)
            ClubNextGoalCard(summary: detail.motivationSummary, rankingCategory: rankingCategory)
            if viewModel.rankingLoading && ranking.isEmpty { SOOMSkeleton(layout: .list, label: "랭킹을 확인하는 중") }
            ClubWeeklyRankingSection(
                clubName: detail.name,
                motivationSummary: detail.motivationSummary,
                ranking: ranking,
                selectedCategory: $rankingCategory
            )
            ClubChallengesSection(challenges: viewModel.selectedClub?.id == clubId ? viewModel.challenges : detail.challenges)
            ClubBadgeWallSection(badges: viewModel.selectedClub?.id == clubId ? viewModel.badges : detail.badges)
            ClubActivityPulseSection(pulses: detail.pulses)
        }
        .navigationTitle(detail.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let identity = verifiedIdentity,
               viewModel.detail(for: clubId)?.id == clubId,
               identity.ownerID != safetyStore.viewerID {
                ToolbarItem(placement: .topBarTrailing) {
                    CommunitySafetyMenu(
                        target: CommunityReportTarget(kind: .club, id: identity.id),
                        authorID: identity.ownerID,
                        authorName: "클럽 운영자"
                    )
                }
            }
        }
        .onChange(of: rankingCategory) { _, category in
            Task {
                await viewModel.selectRankingMetric(category.metric, clubId: clubId)
            }
        }
        .sheet(isPresented: $isMembershipSheetPresented) {
            ClubMembershipPlaceholderSheet(
                state: detail.membershipState,
                busy: viewModel.membershipOperation != nil,
                error: viewModel.membershipError,
                onLeave: {
                    Task {
                        if await viewModel.leaveClub(clubId: clubId) { isMembershipSheetPresented = false }
                    }
                }
            )
                .presentationDetents([.large])
                .interactiveDismissDisabled(viewModel.membershipOperation != nil)
                .presentationDragIndicator(.visible)
        }
    }

    private func handleMembershipAction(detail: ClubDetail) {
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
    case duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: return "거리"
        case .sessions: return "운동 횟수"
        case .consistency: return "꾸준함"
        case .duration: return "운동시간"
        }
    }

    var unit: String {
        switch self {
        case .distance: return "km"
        case .sessions: return "회"
        case .consistency: return "일"
        case .duration: return ""
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
                Image(soom: SOOMIcon.record)
                    .font(.system(size: SOOMFont.Size.headline, weight: .bold))
                    .foregroundStyle(SOOMColor.white)
                    .frame(width: 44, height: 44)
                    .background(SOOMColor.ink)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("클럽 만들기")
            .accessibilityIdentifier("clubs.create.open")
        }
    }
}

/// Shown whenever `ClubServiceResolver`/`FallbackClubService` actually
/// served local data instead of the real service — covers both a signed-
/// out viewer and a signed-in one whose Supabase call silently failed, so
/// nobody looks at mock club data believing it's shared/synced. Not a
/// Button — purely informational, matching other passive `SOOMActionRow`
/// usage in this codebase (e.g. SettingsView's "계정 연결됨" row).
private struct ClubLocalFallbackBanner: View {
    var body: some View {
        SOOMCard(depth: .ambient) {
            SOOMActionRow(
                icon: "wifi.slash",
                title: "이 기기에 저장된 클럽 정보를 보고 있어요",
                subtitle: "온라인 클럽과 동기화되지 않은 로컬 정보입니다.",
                tint: SOOMColor.warning
            )
        }
        .accessibilityElement(children: .combine)
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
                Image(soom: SOOMIcon.clubs)
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
                                .padding(.horizontal, SOOMLayout.Spacing.sm)
                                .padding(.vertical, SOOMLayout.Spacing.xs)
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
                        .fixedSize(horizontal: false, vertical: true)

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

                Image(soom: SOOMIcon.chevronRight)
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
            Image(soom: SOOMIcon.sparkles)
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text("둘러보기")
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.accentInk)
                .padding(.horizontal, SOOMLayout.Spacing.md)
                .padding(.vertical, SOOMLayout.Spacing.sm)
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
                            .padding(.horizontal, SOOMLayout.Spacing.sm)
                            .padding(.vertical, SOOMLayout.Spacing.sm)
                            .background(SOOMColor.accentSurface)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: SOOMLayout.Metrics.gridSpacing) {
                    ClubStatTile(title: "내 순위", value: detail.weeklyRankText, icon: SOOMIcon.medal, tint: SOOMColor.accent)
                    ClubStatTile(title: "멤버", value: "\(detail.memberCount)명", icon: SOOMIcon.people, tint: SOOMColor.ink)
                    ClubStatTile(title: "이번 주", value: "\(detail.activeMembersThisWeek)명", icon: SOOMIcon.trendUp, tint: SOOMColor.accent)
                }

                ClubMotivationSummaryStrip(summary: detail.motivationSummary)

                Button(action: onMembershipAction) {
                    Text(detail.membershipState.actionTitle)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(detail.membershipState == .joined ? SOOMColor.accent : SOOMColor.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SOOMLayout.Spacing.md)
                        .background(detail.membershipState == .joined ? SOOMColor.accentSurface : SOOMColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(detail.membershipState.actionTitle)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.name)
        .accessibilityValue("이번 주 순위 \(detail.weeklyRankText), 기여 거리 \(String(format: "%.1f", detail.contributionDistanceKm))킬로미터, 클럽 목표 \(detail.goalPercentText)")
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
                .fixedSize(horizontal: false, vertical: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceSecondary)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: SOOMRadius.hairline)
                .fill(SOOMColor.accent)
                .frame(width: 3)
                .padding(.vertical, SOOMLayout.Spacing.md)
        }
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
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
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
            Image(soom: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(SOOMFont.body(16, weight: .bold, relativeTo: .headline))
                .foregroundStyle(SOOMColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.82)
            Text(title)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceSecondary)
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
                .fixedSize(horizontal: false, vertical: true)
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
            Image(soom: SOOMIcon.checkCircle)
                .font(.caption.weight(.bold))
                .foregroundStyle(SOOMColor.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceSecondary)
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
                .fixedSize(horizontal: false, vertical: true)

            Text(member.role)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(member.tone.color)
                .padding(.horizontal, SOOMLayout.Spacing.sm)
                .padding(.vertical, SOOMLayout.Spacing.xs)
                .background(member.tone.color.opacity(0.10))
                .clipShape(Capsule())
                .fixedSize(horizontal: false, vertical: true)

            Text(member.activityText)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 128, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceAmbient)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ClubWeeklyRankingSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var selectorLayout: AnyLayout { dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: SOOMLayout.Metrics.tagSpacing)) }
    let clubName: String
    let motivationSummary: ClubMotivationSummary
    let ranking: [ClubRankingEntry]
    @Binding var selectedCategory: ClubRankingCategory

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("\(clubName) 내 이번 주 랭킹", caption: rankingCaption)

            selectorLayout {
                ForEach(ClubRankingCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category.title)
                            .frame(minHeight: 44)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(selectedCategory == category ? SOOMColor.selectedInk : SOOMColor.secondaryInk)
                            .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
                            .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding)
                            .background(selectedCategory == category ? SOOMColor.selectedSurface : SOOMColor.surfaceMuted)
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
        case .duration:
            return "조금만 더 움직이면 운동시간 랭킹이 가까워져요."
        }
    }

    var body: some View {
        SOOMCard(depth: .secondary) {
            HStack(alignment: .top, spacing: SOOMLayout.Metrics.rowSpacing) {
                Image(soom: SOOMIcon.trendUp)
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
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.82)
                    Text(nextActionText)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
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

                    Text(entry.compactValueText(for: category))
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceSecondary)
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
                .foregroundStyle(entry.isCurrentUser ? SOOMColor.selectedInk : SOOMColor.secondaryInk)
                .frame(width: 42, height: 34)
                .background(entry.isCurrentUser ? SOOMColor.selectedSurface : SOOMColor.surfaceMuted)
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
        .background(entry.isCurrentUser ? SOOMColor.selectedSurface : SOOMColor.surfaceAmbient)
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
                            HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                                Text(challenge.title)
                                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                                    .foregroundStyle(SOOMColor.ink)
                                if let badge = ClubChallengeStateBadge(state: challenge.state) {
                                    Text(badge.label)
                                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                                        .foregroundStyle(badge.foreground)
                                        .padding(.horizontal, SOOMLayout.Spacing.sm)
                                        .padding(.vertical, SOOMLayout.Spacing.xs)
                                        .background(badge.background)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(challenge.subtitle)
                                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                                .foregroundStyle(SOOMColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(challenge.nextActionLine)
                                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                                .foregroundStyle(SOOMColor.accent)
                                .fixedSize(horizontal: false, vertical: true)
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
                    .accessibilityValue(
                        [challenge.progressText, ClubChallengeStateBadge(state: challenge.state)?.label]
                            .compactMap { $0 }
                            .joined(separator: ", ")
                    )
                }
                .padding(SOOMLayout.Spacing.md)
                .background(SOOMColor.surfaceAmbient)
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
        }
    }
}

/// nil for .active — the badge only needs to appear once a challenge stops
/// being "in progress" (completed or expired).
private struct ClubChallengeStateBadge {
    let label: String
    let foreground: Color
    let background: Color

    init?(state: ClubChallengeState) {
        switch state {
        case .active:
            return nil
        case .completed:
            label = "완료"
            foreground = SOOMColor.green
            background = SOOMColor.green.opacity(0.14)
        case .expired:
            label = "만료됨"
            foreground = SOOMColor.tertiaryInk
            background = SOOMColor.surfaceMuted
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
                        Image(soom: badge.icon)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(badge.state.tint)
                            .frame(width: 34, height: 34)
                            .background(badge.state.tint.opacity(0.12))
                            .clipShape(Circle())
                        Text(badge.title)
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(badge.subtitle)
                            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(badge.state.tint)
                            .padding(.horizontal, SOOMLayout.Spacing.sm)
                            .padding(.vertical, SOOMLayout.Spacing.xs)
                            .background(badge.state.tint.opacity(0.10))
                            .clipShape(Capsule())
                            .fixedSize(horizontal: false, vertical: true)
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
                        Image(soom: pulse.icon)
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
                        title: "클럽 만들기",
                        subtitle: "직접 만든 클럽 안에서 주간 랭킹과 챌린지를 열 수 있게 준비 중이에요.",
                        iconName: SOOMIcon.record,
                        action: onCreate
                    )
                ],
                footer: "클럽은 선택한 그룹 안에서만 랭킹과 뱃지가 쌓입니다."
            )

            Button(action: onCreate) {
                Label("클럽 만들기", soomIcon: SOOMIcon.record)
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.lg)
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
    @StateObject private var viewModel = ClubCreateViewModel()
    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    let onCreate: (ClubCreateInput) async throws -> ClubDomain

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            HStack {
                Image(soom: SOOMIcon.clubs)
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
                    Image(soom: SOOMIcon.close)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 44, height: 44)
                        .background(SOOMColor.surfaceMuted, in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
                .accessibilityIdentifier("clubs.sheet.close")
                .disabled(viewModel.isSubmitting)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("클럽 만들기")
                    .font(SOOMFont.body(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Text("온라인에 공개 클럽을 만들어요. 서버 연결이 어려워 기기에만 저장된 경우에는 따로 알려드려요.")
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                TextField("클럽 이름", text: $viewModel.name)
                    .accessibilityIdentifier("club.create.name")
                    .textInputAutocapitalization(.never)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .padding(SOOMLayout.Spacing.lg)
                    .background(SOOMColor.surfaceAmbient)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))

                TextField("클럽 목적", text: $viewModel.purpose)
                    .accessibilityIdentifier("club.create.purpose")
                    .font(SOOMFont.body(15, relativeTo: .subheadline))
                    .padding(SOOMLayout.Spacing.lg)
                    .background(SOOMColor.surfaceAmbient)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))

                Picker("대표 종목", selection: $viewModel.sportFocus) {
                    Text("자전거").tag("자전거")
                    Text("러닝").tag("러닝")
                    Text("걷기").tag("걷기")
                    Text("혼합").tag("혼합")
                }
                .pickerStyle(.segmented)

                // "비공개" is hidden until an invite mechanism exists —
                // RLS only allows joining a club whose visibility is
                // 'open' (see club_members_insert_join_open in
                // club_foundation_v1.sql), so a private club created today
                // would be permanently limited to its owner. visibility
                // stays hardcoded to .open below.
            }
            .disabled(viewModel.isSubmitting || viewModel.savedLocally)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("club.create.error")
            }

            if viewModel.savedLocally {
                Text("이 기기에만 저장했어요. 온라인 클럽이 생성되거나 다른 사용자에게 공개된 상태는 아니에요.")
                    .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                Button("확인") { dismiss() }.accessibilityIdentifier("club.create.localConfirm")
            }

            Button {
                Task {
                    if await viewModel.submit(using: onCreate) { dismiss() }
                }
            } label: {
                Text(viewModel.isSubmitting ? "클럽 만드는 중…" : "클럽 만들기")
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.lg)
                    .background(viewModel.canCreate ? SOOMColor.accent : SOOMColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canCreate)
            .accessibilityIdentifier("club.create.submit")
        }
        .padding(SOOMLayout.screenPadding)
        }
        .background(SOOMColor.background)
        .interactiveDismissDisabled(viewModel.isSubmitting)
        .onChange(of: safetyStore.accountGeneration) { _, _ in dismiss() }
    }
}

private struct ClubMembershipPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ClubDetail.MembershipState
    var busy = false
    var error: String?
    let onLeave: (() -> Void)?

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            HStack {
                Image(soom: SOOMIcon.clubs)
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
                    Image(soom: SOOMIcon.close)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 44, height: 44)
                        .background(SOOMColor.surfaceMuted, in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
                .accessibilityIdentifier("clubs.sheet.close")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(state.placeholderTitle)
                    .font(SOOMFont.body(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Text("멤버 승인·권한 변경·초대 설정은 아직 제공하지 않아요. 현재 화면에서는 가입 상태를 확인할 수 있어요.")
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if busy { ProgressView("클럽 상태를 반영하는 중") }
            if let error { Text(error).font(.subheadline).foregroundStyle(SOOMColor.warning).accessibilityIdentifier("clubs.membership.error") }
            if (state == .joined || state == .admin), let onLeave {
                Button {
                    onLeave()
                } label: {
                    Text("클럽 나가기")
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SOOMLayout.Spacing.md)
                        .background(SOOMColor.accentSurface)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(SOOMLayout.screenPadding)
        .background(SOOMColor.background)
        }.disabled(busy)
    }
}

private struct ClubRetryCard: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        SOOMCard {
            Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(SOOMColor.warning).accessibilityIdentifier("clubs.error")
            Button(action: retry) { Text("다시 불러오기").frame(minHeight: 44) }
                .accessibilityIdentifier("clubs.retry")
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Explicit synthetic QA only; never constructed by an ordinary launch or Release.
private final class UXClubFixtureControl { var allowDirectoryRetry = false }
private final class UXClubServiceFixture: ClubService {
    let wrapped: any ClubService
    let scenario: String
    let control: UXClubFixtureControl
    var directoryAttempts = 0
    var joins = 0
    var leaves = 0
    var creations = 0
    init(wrapped: any ClubService, scenario: String, control: UXClubFixtureControl) { self.wrapped = wrapped; self.scenario = scenario; self.control = control }
    func fetchClubDirectory() async throws -> ClubDirectorySnapshot {
        directoryAttempts += 1
        if scenario == "directory" && !control.allowDirectoryRetry {
            try await Task.sleep(for: .seconds(4)); throw ClubServiceError.clubNotFound
        }
        if scenario == "initial_directory_failure", !control.allowDirectoryRetry { throw ClubServiceError.clubNotFound }
        if scenario == "empty" { return .empty }
        if scenario == "create_refresh_failure", creations > 0, !control.allowDirectoryRetry { throw ClubServiceError.clubNotFound }
        return try await wrapped.fetchClubDirectory()
    }
    func fetchClubDetail(clubId: String) async throws -> ClubDetail { try await wrapped.fetchClubDetail(clubId: clubId) }
    func createClub(input: ClubCreateInput) async throws -> ClubDomain {
        creations += 1
        switch scenario {
        case "create_permission_denied": throw PostgrestError(code: "42501", message: "Synthetic permission rejection")
        case "create_server_schema": throw PostgrestError(code: "42P01", message: "Synthetic schema rejection")
        case "create_timeout": throw URLError(.timedOut)
        default: break
        }
        let created = try await wrapped.createClub(input: input)
        // The receipt must retain the stored row ID. Fabricating a different ID
        // would make an honest successful refresh look like a filtered-out row.
        return created
    }
    func joinClub(clubId: String) async throws {
        joins += 1
        if scenario == "membership" && joins == 1 { try await Task.sleep(for: .seconds(2)); throw ClubServiceError.clubNotFound }
        try await wrapped.joinClub(clubId: clubId)
    }
    func leaveClub(clubId: String) async throws {
        leaves += 1
        if scenario == "membership" && leaves == 1 { try await Task.sleep(for: .seconds(2)); throw ClubServiceError.clubNotFound }
        try await wrapped.leaveClub(clubId: clubId)
    }
    func fetchRankings(clubId: String, metric: ClubRankingMetric) async throws -> [ClubRankingEntry] { try await wrapped.fetchRankings(clubId: clubId, metric: metric) }
    func fetchChallenges(clubId: String) async throws -> [ClubChallenge] { try await wrapped.fetchChallenges(clubId: clubId) }
}
#endif
