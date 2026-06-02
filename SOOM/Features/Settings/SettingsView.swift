import SwiftUI
import UIKit
import SwiftData

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingDisconnectConfirmation = false
    @State private var localDataPresence: LocalDataPresence = .empty
    private let authEnvironment: AuthEnvironment

    init(
        viewModel: SettingsViewModel = SettingsViewModel(),
        authEnvironment: AuthEnvironment = AuthEnvironmentLoader().load()
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.authEnvironment = authEnvironment
    }

    var body: some View {
        SOOMScreen {
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
            connectionsSection
            supportAreaHeader
            profileSection
            trainingBaselineSection
            privacySection
            notificationSection
            appInfoSection
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.load()
            await refreshLocalDataPresence()
        }
        .task(id: authViewModel.session.currentUser?.id) {
            await refreshLocalDataPresence()
        }
        .alert(
            "설정 값을 확인해주세요",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { viewModel.load() }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "입력 값을 다시 확인해주세요.")
        }
        .confirmationDialog(
            "계정 연결만 해제합니다",
            isPresented: $isShowingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("계정 연결 해제") {
                Task {
                    await authViewModel.disconnectRemoteAccount()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 기기의 운동 기록, 설정, route 데이터는 삭제하지 않아요. 로컬 기록은 그대로 유지됩니다.")
        }
    }

    private var authStatusText: String {
        if authViewModel.session.currentUser?.authProvider == .supabase {
            return "계정 연결됨"
        }

        return authViewModel.session.isLocalOnly ? "로컬 사용자" : "로그인 준비 중"
    }

    private var profileIdentity: ProfileIdentitySystem {
        ProfileIdentitySystem.foundation
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("프로필")
                .font(SOOMFont.display(38, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)
            Text("계정, 데이터 소유권, HealthKit, 기준값, 공개 범위를 한곳에서 관리합니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var profileSection: some View {
        SOOMCard {
            SOOMSectionHeader("계정", caption: "운동 정체성과 로컬 기록을 유지하면서 계정 연결을 관리합니다.")

            if authViewModel.session.currentUser == nil {
                SOOMActionRow(icon: "person.crop.circle", title: "로컬 사용자 시작", subtitle: "서버 계정 없이 이 기기에서 SOOM 기록을 이어갑니다.", tint: SOOMColor.accent)

                Button {
                    authViewModel.continueAsLocalUser()
                } label: {
                    Text("로컬 사용자로 계속하기")
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SOOMLayout.Card.padding)
                        .background(SOOMColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                settingInputRow(
                    title: "표시 이름",
                    suffix: "",
                    text: $authViewModel.displayNameText,
                    actionTitle: "저장",
                    keyboardType: .default,
                    action: { authViewModel.updateDisplayName() }
                )

                SOOMActionRow(icon: "lock", title: "계정 연결 상태", subtitle: "현재 기록은 로컬에 유지돼요. 계정 연결과 동기화는 단계적으로 확인합니다.", tint: SOOMColor.secondaryInk)

                EmailAuthCard(environment: authEnvironment)

                AppleAuthCard(authViewModel: authViewModel)

                if authViewModel.session.currentUser?.authProvider == .supabase {
                    SOOMActionRow(icon: "checkmark.seal", title: "계정 연결됨", subtitle: "Supabase 세션을 확인했어요. 로컬 기록 동기화는 다음 단계입니다.", tint: SOOMColor.accent)

                    if let ownershipPlanNotice {
                        SOOMActionRow(icon: "externaldrive.badge.person.crop", title: "기록 소유권", subtitle: ownershipPlanNotice, tint: SOOMColor.secondaryInk)
                    }

                    SOOMActionRow(icon: "person.crop.circle.badge.minus", title: "계정 연결 해제", subtitle: "원격 세션만 종료하고 이 기기의 기록과 설정은 유지합니다.", tint: SOOMColor.warning)

                    Button("계정 연결만 해제하기") {
                        isShowingDisconnectConfirmation = true
                    }
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.warning)
                }

                Button("계정 상태 확인") {
                    Task {
                        await authViewModel.checkRemoteSession()
                    }
                }
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.accent)

                if authViewModel.session.currentUser?.authProvider != .supabase {
                    Button("로컬 세션 초기화") {
                        authViewModel.signOut()
                    }
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                }
            }

            if let error = authViewModel.errorMessage {
                Text(error)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.warning)
            }
        }
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

    private var connectionsSection: some View {
        SOOMCard {
            SOOMSectionHeader("Connections", caption: "연결은 정체성을 보강하는 지원 영역입니다.")

            NavigationLink {
                HealthKitSettingsViewContainer()
            } label: {
                ProfileConnectionRow(connection: profileIdentity.connections[0])
            }
            .buttonStyle(.plain)

            NavigationLink {
                HealthKitWorkoutImportViewContainer()
            } label: {
                SOOMActionRow(icon: SOOMIcon.sync, title: "운동 가져오기", subtitle: "가져온 운동은 Activity 도서관과 상세 분석으로 이어집니다.", tint: SOOMColor.accent)
            }
            .buttonStyle(.plain)

            ForEach(profileIdentity.connections.dropFirst()) { connection in
                ProfileConnectionRow(connection: connection)
            }
        }
    }

    private var supportAreaHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("지원 영역")
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
            Text("계정, 권한, 기준값은 운동 정체성을 유지하기 위한 하단 관리 영역입니다.")
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    private var trainingBaselineSection: some View {
        SOOMCard {
            SOOMSectionHeader("운동 기준값", caption: "최대심박과 FTP는 Zone 분석 기준으로 사용돼요. Recovery/Growth 공식 계산에는 아직 자동 반영하지 않아요.")

            settingInputRow(
                title: "최대 심박",
                suffix: "bpm",
                text: $viewModel.maxHeartRateText,
                actionTitle: "저장",
                action: { viewModel.saveMaxHeartRate() }
            )

            settingInputRow(
                title: "사이클 FTP",
                suffix: "W",
                text: $viewModel.cyclingFTPText,
                actionTitle: "저장",
                action: { viewModel.saveCyclingFTP() }
            )

            Picker("단위", selection: Binding(
                get: { viewModel.settings.preferredUnit },
                set: { viewModel.updatePreferredUnit($0) }
            )) {
                ForEach(TrainingPreferredUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var privacySection: some View {
        SOOMCard {
            SOOMSectionHeader("공개 범위", caption: "공유 기본값은 사용자가 선택할 때만 적용되는 후보 설정입니다.")

            Picker("공유 기본값", selection: Binding(
                get: { viewModel.settings.privacyDefault },
                set: { viewModel.updatePrivacyDefault($0) }
            )) {
                Text(ShareableWorkoutVisibility.privateOnly.title).tag(ShareableWorkoutVisibility.privateOnly)
                Text(ShareableWorkoutVisibility.followers.title).tag(ShareableWorkoutVisibility.followers)
                Text(ShareableWorkoutVisibility.publicFeed.title).tag(ShareableWorkoutVisibility.publicFeed)
            }
            .pickerStyle(.segmented)

            Text("위치, 심박, 체크인 메모는 기본 공유 항목에 포함하지 않습니다.")
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
    }

    private var notificationSection: some View {
        SOOMCard {
            SOOMSectionHeader("알림", caption: "아침 체크인과 주간 리듬 알림을 담을 자리입니다.")
            SOOMActionRow(icon: "bell", title: "알림 설정 준비 중", subtitle: "강요하지 않는 리마인더 정책으로 설계합니다.", tint: SOOMColor.warning)
        }
    }

    private var appInfoSection: some View {
        SOOMCard {
            SOOMSectionHeader("앱 정보")
            SOOMActionRow(icon: "info.circle", title: "SOOM Foundation", subtitle: "Recovery, Growth, HealthKit 데이터 신뢰 구조를 실험 중입니다.", tint: SOOMColor.secondaryInk)
            SOOMActionRow(icon: "lock.shield", title: "계정 환경", subtitle: authEnvironmentStatusText, tint: SOOMColor.secondaryInk)
            SOOMActionRow(icon: "person.badge.key", title: "Supabase 세션", subtitle: authSessionSmokeStatusText, tint: SOOMColor.secondaryInk)
        }
    }

    private var authEnvironmentStatusText: String {
        let sdkStatus = "SDK 준비됨"
        let supabaseStatus = authEnvironment.isSupabaseConfigured ? "환경 설정됨" : "환경 미설정"
        let redirectStatus = authEnvironment.isRedirectConfigured ? "Redirect 준비됨" : "Redirect 미설정"
        let appleStatus = authEnvironment.isSupabaseConfigured ? "Apple 로그인 준비됨" : "Apple 로그인 환경 미설정"
        return "\(authEnvironment.environment.title) · \(sdkStatus) · \(supabaseStatus) · \(redirectStatus) · \(appleStatus)"
    }

    private var authSessionSmokeStatusText: String {
        let sessionStatus: String
        if authViewModel.isCheckingRemoteSession {
            sessionStatus = "계정 상태 확인 중"
        } else if authViewModel.session.currentUser?.authProvider == .supabase {
            sessionStatus = "계정 연결됨"
        } else {
            sessionStatus = authEnvironment.isSupabaseConfigured ? "세션 복원 준비됨" : "미설정"
        }
        return "\(sessionStatus) · 로컬 기록 동기화는 다음 단계입니다."
    }

    private var ownershipPlanNotice: String? {
        let plan = UserOwnershipMigrationPlanner().buildPlan(
            localSession: authViewModel.session,
            localDataPresence: localDataPresence
        )
        guard plan.hasEligibleLocalData else {
            return nil
        }
        return plan.userFacingSummary
    }

    @MainActor
    private func refreshLocalDataPresence() async {
        let detector = LocalDataDetector.live(modelContext: modelContext)
        localDataPresence = await detector.detect()
    }

    private func settingInputRow(
        title: String,
        suffix: String,
        text: Binding<String>,
        actionTitle: String,
        keyboardType: UIKeyboardType = .numberPad,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text(title)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)
                HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    TextField("미설정", text: text)
                        .keyboardType(keyboardType)
                        .font(SOOMFont.body(15, relativeTo: .subheadline))
                    Text(suffix)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
            }

            Button(actionTitle, action: action)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.accent)
        }
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

struct ProfileIdentitySystem {
    let hero: Hero
    let patterns: [MovementPattern]
    let personalBests: [PersonalBest]
    let badges: [Badge]
    let signatureRoutes: [SignatureRoute]
    let connections: [Connection]
    let emptyStateCopy: String

    struct Hero: Equatable {
        let identityTitle: String
        let representativeBadgeID: String
        let representativeSport: String
        let activeDays: String
        let totalDistance: String
        let monthlyState: String
    }

    struct MovementPattern: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let isPrimary: Bool
    }

    struct PersonalBest: Identifiable, Equatable {
        let id: String
        let title: String
        let value: String
        let context: String
        let icon: String
    }

    struct Badge: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let state: String
        let progress: Double
        let isRare: Bool
    }

    struct SignatureRoute: Identifiable, Equatable {
        let id: String
        let title: String
        let marker: String
        let mood: String
    }

    struct Connection: Identifiable, Equatable {
        let id: String
        let title: String
        let status: String
        let subtitle: String
        let icon: String
        let state: ConnectionState
    }

    enum ConnectionState: Equatable {
        case connected
        case needsPermission
        case future

        var tint: Color {
            switch self {
            case .connected:
                return SOOMColor.accent
            case .needsPermission:
                return SOOMColor.warning
            case .future:
                return SOOMColor.secondaryInk
            }
        }
    }

    static let maxPersonalBestCount = 3
    static let profileDoesNotShowRecentWorkoutList = true
    static let connectionsAreSupportArea = true
    static let heroIdentityPhraseIsPrimary = true
    static let heroStatsAreSecondary = true
    static let heroRepresentativeBadgeCount = 1

    var representativeBadge: Badge? {
        badges.first { $0.id == hero.representativeBadgeID } ?? badges.first
    }

    var compactHeroStats: [ProfileHeroStat] {
        [
            ProfileHeroStat(id: "active-days", title: "움직인 날", value: hero.activeDays),
            ProfileHeroStat(id: "distance", title: "누적 거리", value: hero.totalDistance),
            ProfileHeroStat(id: "sport", title: "대표 종목", value: hero.representativeSport)
        ]
    }

    static let foundation = ProfileIdentitySystem(
        hero: Hero(
            identityTitle: "리듬을 지키는 라이더",
            representativeBadgeID: "thirty-days",
            representativeSport: "자전거 중심",
            activeDays: "128일 활동",
            totalDistance: "1,240km",
            monthlyState: "이번 달 안정적"
        ),
        patterns: [
            MovementPattern(id: "morning", title: "아침형", subtitle: "하루를 먼저 깨우는 편", icon: "sunrise.fill", isPrimary: true),
            MovementPattern(id: "recovery", title: "회복 친화형", subtitle: "무리보다 지속을 선택", icon: "leaf.fill", isPrimary: true),
            MovementPattern(id: "consistency", title: "꾸준함 중심", subtitle: "긴 공백 없이 이어감", icon: "calendar.badge.clock", isPrimary: false),
            MovementPattern(id: "weekend", title: "주말 장거리형", subtitle: "길게 리듬을 쌓는 날", icon: SOOMIcon.map, isPrimary: false)
        ],
        personalBests: [
            PersonalBest(id: "longest-ride", title: "최장 라이딩", value: "212km", context: "한 번에 이어간 거리", icon: SOOMIcon.bike),
            PersonalBest(id: "longest-run", title: "최장 러닝", value: "42km", context: "완주 리듬", icon: SOOMIcon.run),
            PersonalBest(id: "weekly-distance", title: "최고 주간 거리", value: "318km", context: "가장 길게 쌓은 한 주", icon: "chart.line.uptrend.xyaxis")
        ],
        badges: [
            Badge(id: "thirty-days", title: "30일 리듬", subtitle: "꾸준함", state: "획득", progress: 1.0, isRare: false),
            Badge(id: "thousand-km", title: "1000km", subtitle: "누적 거리", state: "획득", progress: 1.0, isRare: false),
            Badge(id: "recovery-ride", title: "회복 라이딩", subtitle: "무리 없는 참여", state: "진행중", progress: 0.68, isRare: false),
            Badge(id: "club-contribution", title: "첫 클럽 기여", subtitle: "SOOM Riders", state: "희귀", progress: 1.0, isRare: true)
        ],
        signatureRoutes: [
            SignatureRoute(id: "hangang-north", title: "한강 북단", marker: "대표 코스", mood: "숨이 풀리는 길"),
            SignatureRoute(id: "tancheon-loop", title: "탄천 루프", marker: "회복 루프", mood: "가볍게 이어감"),
            SignatureRoute(id: "bugak", title: "북악", marker: "도전 지점", mood: "기준을 세우는 언덕")
        ],
        connections: [
            Connection(id: "healthkit", title: "Apple 건강 앱", status: "권한 관리", subtitle: "HealthKit 연결과 권한을 관리합니다.", icon: SOOMIcon.health, state: .needsPermission),
            Connection(id: "strava", title: "Strava", status: "준비중", subtitle: "외부 운동 정체성 연결은 이후 단계입니다.", icon: "figure.run.circle", state: .future),
            Connection(id: "garmin", title: "Garmin", status: "준비중", subtitle: "기기 연결은 future connection으로 남겨둡니다.", icon: "sensor.tag.radiowaves.forward", state: .future),
            Connection(id: "weather", title: "위치/날씨", status: "선택 권한", subtitle: "Record 출발 전 날씨와 위치 맥락을 지원합니다.", icon: "location.circle", state: .needsPermission)
        ],
        emptyStateCopy: "아직 나의 운동 리듬을 만드는 중입니다. 첫 운동을 기록하면 대표 종목과 성향이 생겨요."
    )
}

private struct ProfileIdentityTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                Text(value)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfileBestRow: View {
    let best: ProfileIdentitySystem.PersonalBest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: best.icon)
                .font(.system(size: 16, weight: .bold))
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
        .padding(12)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfileRouteIdentityCard: View {
    let route: ProfileIdentitySystem.SignatureRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: SOOMIcon.map)
                .font(.system(size: 15, weight: .bold))
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
        .padding(12)
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SOOMColor.accent)
                    .frame(width: 34, height: 34)
                    .background(SOOMColor.accentSurface)
                    .clipShape(Circle())

                Spacer(minLength: 0)

                Text(badge.state)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(badge.isRare ? SOOMColor.accentInk : SOOMColor.secondaryInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
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
        .padding(12)
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
                    .font(.system(size: 14, weight: .bold))
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
        .padding(12)
        .background(pattern.isPrimary ? SOOMColor.accentSurface.opacity(0.72) : SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfileConnectionRow: View {
    let connection: ProfileIdentitySystem.Connection

    var body: some View {
        SOOMActionRow(
            icon: connection.icon,
            title: connection.title,
            subtitle: "\(connection.status) · \(connection.subtitle)",
            tint: connection.state.tint
        )
    }
}

#Preview("SettingsView") {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AuthViewModel())
    .preferredColorScheme(.light)
}
