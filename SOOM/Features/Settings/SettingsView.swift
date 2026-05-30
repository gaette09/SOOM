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
                tagline: "Ride the rhythm.",
                totalWorkoutCount: "라이딩 중심",
                weeklySummary: "꾸준함 중심",
                authStatus: authStatusText
            )
            movementIdentitySection
            movementPatternSection
            personalBestSection
            profileFavoriteRoutesSection
            badgeShowcaseSection
            if shouldShowProfileFirstJourney {
                profileFirstJourneyCard
            }
            connectionsSection
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
                SOOMActionRow(icon: "person.crop.circle", title: "로컬 사용자 시작", subtitle: "서버 계정 없이 이 기기에서 SOOM 기록을 이어갑니다.", tint: SOOMColor.recovery)

                Button {
                    authViewModel.continueAsLocalUser()
                } label: {
                    Text("로컬 사용자로 계속하기")
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SOOMLayout.Card.padding)
                        .background(SOOMColor.recovery)
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
                    SOOMActionRow(icon: "checkmark.seal", title: "계정 연결됨", subtitle: "Supabase 세션을 확인했어요. 로컬 기록 동기화는 다음 단계입니다.", tint: SOOMColor.recovery)

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
                .foregroundStyle(SOOMColor.recovery)

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

    private var movementIdentitySection: some View {
        SOOMCard(depth: .primary) {
            SOOMSectionHeader("Movement Identity", caption: "최근 기록 목록이 아니라, 내가 어떤 운동가인지 보여주는 요약입니다.")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ProfileIdentityTile(title: "대표 종목", value: "라이딩", icon: SOOMIcon.bike, tint: SOOMColor.bike)
                ProfileIdentityTile(title: "운동한 날", value: "183일", icon: "calendar", tint: SOOMColor.recovery)
                ProfileIdentityTile(title: "총 거리", value: "5,421km", icon: SOOMIcon.map, tint: SOOMColor.run)
                ProfileIdentityTile(title: "운동 시간", value: "312시간", icon: "clock", tint: SOOMColor.blue)
            }

            ProfileIdentityTile(title: "대표 코스", value: "한강 북단", icon: SOOMIcon.map, tint: SOOMColor.secondaryInk)
        }
    }

    private var movementPatternSection: some View {
        SOOMCard(depth: .ambient) {
            SOOMSectionHeader("Movement Pattern", caption: "운동 기록을 성격으로 읽는 자리입니다.")

            FlowTags(
                tags: ["아침형 라이더", "회복 친화형", "꾸준함 중심", "주말 장거리형"],
                tint: SOOMColor.recovery
            )
        }
    }

    private var personalBestSection: some View {
        SOOMCard {
            SOOMSectionHeader("Personal Best", caption: "운동 리스트가 아니라 나를 설명하는 대표 기록만 둡니다.")

            VStack(spacing: 10) {
                ProfileBestRow(title: "Longest Ride", value: "212km", tint: SOOMColor.bike)
                ProfileBestRow(title: "Longest Run", value: "42km", tint: SOOMColor.run)
                ProfileBestRow(title: "Fastest 10km", value: "기록 준비 중", tint: SOOMColor.secondaryInk)
            }
        }
    }

    private var profileFavoriteRoutesSection: some View {
        SOOMCard(depth: .ambient) {
            SOOMSectionHeader("대표 코스", caption: "자주 간 길 전체가 아니라, 나를 설명하는 코스만 보여줍니다.")

            HStack(spacing: 10) {
                ProfileRouteIdentityCard(title: "한강 북단", count: "12회", tint: SOOMColor.bike)
                ProfileRouteIdentityCard(title: "탄천", count: "8회", tint: SOOMColor.run)
                ProfileRouteIdentityCard(title: "북악", count: "3회", tint: SOOMColor.secondaryInk)
            }
        }
    }

    private var badgeShowcaseSection: some View {
        SOOMCard {
            SOOMSectionHeader("Badge Showcase", caption: "Club과 연결되는 대표 성취만 3~5개로 요약합니다.")

            HStack(spacing: 10) {
                ProfileBadgeTile(title: "1000km", subtitle: "기여 거리", tint: SOOMColor.bike)
                ProfileBadgeTile(title: "30일", subtitle: "꾸준함", tint: SOOMColor.recovery)
                ProfileBadgeTile(title: "Century", subtitle: "첫 완주", tint: SOOMColor.warning)
            }
        }
    }

    private var connectionsSection: some View {
        SOOMCard {
            SOOMSectionHeader("Connections", caption: "설정은 마지막에 둡니다. 연결은 운동 정체성을 더 선명하게 만들 때만 사용합니다.")

            NavigationLink {
                HealthKitSettingsViewContainer()
            } label: {
                SOOMActionRow(icon: SOOMIcon.health, title: "Apple 건강 앱", subtitle: "HealthKit 연결과 권한을 관리합니다.", tint: SOOMColor.bike)
            }
            .buttonStyle(.plain)

            NavigationLink {
                HealthKitWorkoutImportViewContainer()
            } label: {
                SOOMActionRow(icon: SOOMIcon.sync, title: "운동 가져오기", subtitle: "가져온 운동은 Activity 도서관과 상세 분석으로 이어집니다.", tint: SOOMColor.recovery)
            }
            .buttonStyle(.plain)

            SOOMActionRow(icon: "figure.run.circle", title: "Strava", subtitle: "외부 운동 정체성 연결은 이후 단계입니다.", tint: SOOMColor.run)
            SOOMActionRow(icon: "sensor.tag.radiowaves.forward", title: "Garmin", subtitle: "기기 연결은 future connection으로 남겨둡니다.", tint: SOOMColor.secondaryInk)
        }
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
                .foregroundStyle(SOOMColor.recovery)
        }
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
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
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                Text(value)
                    .font(SOOMFont.displayMedium(22, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfileRouteIdentityCard: View {
    let title: String
    let count: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: SOOMIcon.map)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)

            Text(count)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfileBadgeTile: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: SOOMIcon.medal)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(subtitle)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

#Preview("SettingsView") {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AuthViewModel())
    .preferredColorScheme(.light)
}
