import SwiftUI

/// "프로필" 탭 콘텐츠 — 정체성만(아바타/성향/대표기록/뱃지/Signature Routes).
/// 설정(계정/기준값/공개범위/알림/앱정보)은 ⚙️를 통해 `SettingsView`로 완전히 분리했다
/// (soom-migration-plan.md M1, Q3가 그은 identityAreaHeader/supportAreaHeader 경계를 그대로 물리적 분리 기준으로 재사용).
struct ProfileIdentityView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var localDataPresence: LocalDataPresence = .empty
    @State private var profileIdentity: ProfileIdentitySystem = .foundation

    var body: some View {
        SOOMScreen {
            settingsEntryRow

            ProfileSummaryCard(
                name: authViewModel.session.currentUser?.displayName ?? "SOOM 사용자",
                handle: authViewModel.session.currentUser?.handle ?? "@soom.local",
                identityTitle: profileIdentity.hero.identityTitle,
                representativeBadgeTitle: profileIdentity.representativeBadge?.title ?? "첫 리듬",
                representativeBadgeSubtitle: profileIdentity.representativeBadge?.subtitle ?? "정체성 준비 중",
                representativeBadgeState: profileIdentity.representativeBadge?.state ?? "준비 중",
                compactStats: profileIdentity.compactHeroStats,
                authStatus: authStatusText
            )
            if shouldShowProfileFirstJourney {
                profileFirstJourneyCard
            }
            movementPatternSection
            personalBestSection
            badgeShowcaseSection
            signatureRoutesSection
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await refreshLocalDataPresence()
            await refreshProfileIdentity()
        }
        .task(id: authViewModel.session.currentUser?.id) {
            await refreshLocalDataPresence()
            await refreshProfileIdentity()
        }
    }

    private var settingsEntryRow: some View {
        HStack {
            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: SOOMFont.Size.headline, weight: .semibold))
                    .foregroundStyle(SOOMColor.ink)
                    .frame(width: 38, height: 38)
                    .background(SOOMColor.surfaceMuted)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정")
        }
    }

    private var authStatusText: String {
        if authViewModel.session.currentUser?.authProvider == .supabase {
            return "계정 연결됨"
        }

        return authViewModel.session.isLocalOnly ? "로컬 사용자" : "로그인 준비 중"
    }

    private var shouldShowProfileFirstJourney: Bool {
        authViewModel.session.currentUser?.authProvider != .supabase && !localDataPresence.hasAnyData
    }

    private var profileFirstJourneyCard: some View {
        SOOMFirstJourneyCard(
            prompt: .profile,
            actions: [
                SOOMFirstJourneyAction(
                    title: "Health 앱 연결",
                    subtitle: "권한을 허용하면 첫 운동 기록을 SOOM으로 이어볼 수 있어요.",
                    iconName: SOOMIcon.health
                ),
                SOOMFirstJourneyAction(
                    title: "로컬로 먼저 시작",
                    subtitle: "계정 연결 전에도 이 기기에서 조용히 기록을 쌓을 수 있어요.",
                    iconName: SOOMIcon.profile
                )
            ],
            footer: "설정은 체크리스트보다 신뢰를 쌓는 공간으로 유지합니다."
        )
    }

    private var movementPatternSection: some View {
        SOOMCard(depth: .ambient) {
            SOOMSectionHeader("운동 성향", caption: "기록 목록이 아니라, 움직이는 방식을 읽는 자리입니다.")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(profileIdentity.patterns) { pattern in
                    ProfilePatternCard(pattern: pattern)
                }
            }
        }
    }

    private var personalBestSection: some View {
        SOOMCard {
            SOOMSectionHeader("대표 기록", caption: "전체 기록표가 아니라 나를 설명하는 3개의 피크만 둡니다.")

            VStack(spacing: 10) {
                ForEach(profileIdentity.personalBests) { best in
                    ProfileBestRow(best: best)
                }
            }
        }
    }

    private var signatureRoutesSection: some View {
        SOOMCard(depth: .ambient) {
            SOOMSectionHeader("Signature Routes", caption: "자주 간 길이 아니라, 나를 대표하는 장소입니다.")

            HStack(spacing: 10) {
                ForEach(profileIdentity.signatureRoutes) { route in
                    ProfileRouteIdentityCard(route: route)
                }
            }
        }
    }

    private var badgeShowcaseSection: some View {
        SOOMCard {
            SOOMSectionHeader("Badge Showcase", caption: "Club과 연결될 수 있는 대표 성취만 조용히 보여줍니다.")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(profileIdentity.badges) { badge in
                    ProfileBadgeTile(badge: badge)
                }
            }
        }
    }

    @MainActor
    private func refreshLocalDataPresence() async {
        let detector = LocalDataDetector.live(modelContext: modelContext)
        localDataPresence = await detector.detect()
    }

    @MainActor
    private func refreshProfileIdentity() async {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let workouts = (try? await store.fetchRecentWorkouts(days: 3_650)) ?? []
        profileIdentity = ProfileWorkoutAggregator().profileIdentity(from: workouts)
    }
}

private struct ProfileBestRow: View {
    let best: ProfileIdentitySystem.PersonalBest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: best.icon)
                .font(.system(size: SOOMFont.Size.body, weight: .bold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 36, height: 36)
                .background(SOOMColor.accentSurface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(best.title)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                Text(best.value)
                    .font(SOOMFont.displayMedium(22, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Text(best.context)
                    .font(SOOMFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }

            Spacer(minLength: 0)
        }
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfileRouteIdentityCard: View {
    let route: ProfileIdentitySystem.SignatureRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: SOOMIcon.map)
                .font(.system(size: SOOMFont.Size.body, weight: .bold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 32, height: 32)
                .background(SOOMColor.accentSurface)
                .clipShape(Circle())

            Text(route.title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)

            Text(route.marker)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.accentInk)
                .lineLimit(1)

            Text(route.mood)
                .font(SOOMFont.body(10, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfileBadgeTile: View {
    let badge: ProfileIdentitySystem.Badge

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: SOOMIcon.medal)
                    .font(.system(size: SOOMFont.Size.body, weight: .bold))
                    .foregroundStyle(SOOMColor.accent)
                    .frame(width: 34, height: 34)
                    .background(SOOMColor.accentSurface)
                    .clipShape(Circle())

                Spacer(minLength: 0)

                Text(badge.state)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(badge.isRare ? SOOMColor.accentInk : SOOMColor.secondaryInk)
                    .padding(.horizontal, SOOMLayout.Spacing.sm)
                    .padding(.vertical, SOOMLayout.Spacing.xs)
                    .background(badge.isRare ? SOOMColor.accentSurface : SOOMColor.surface)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(badge.title)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(badge.subtitle)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .lineLimit(1)
            }

            ProgressView(value: badge.progress)
                .tint(SOOMColor.accent)
                .scaleEffect(x: 1, y: 0.72, anchor: .center)
                .accessibilityLabel("\(badge.title) 진행률")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfilePatternCard: View {
    let pattern: ProfileIdentitySystem.MovementPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: pattern.icon)
                    .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                    .foregroundStyle(pattern.isPrimary ? SOOMColor.accent : SOOMColor.secondaryInk)
                    .frame(width: 30, height: 30)
                    .background(pattern.isPrimary ? SOOMColor.accentSurface : SOOMColor.surface)
                    .clipShape(Circle())

                Text(pattern.isPrimary ? "대표" : "성향")
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(pattern.isPrimary ? SOOMColor.accentInk : SOOMColor.tertiaryInk)
            }

            Text(pattern.title)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)

            Text(pattern.subtitle)
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

#Preview("ProfileIdentityView") {
    NavigationStack {
        ProfileIdentityView()
    }
    .environmentObject(AuthViewModel())
    .preferredColorScheme(.light)
}
