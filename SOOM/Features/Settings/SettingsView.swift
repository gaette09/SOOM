import SwiftUI
import UIKit

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var isShowingDisconnectConfirmation = false
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
            header
            ProfileSummaryCard(
                name: authViewModel.session.currentUser?.displayName ?? "SOOM 사용자",
                handle: authViewModel.session.currentUser?.handle ?? "@soom.local",
                authStatus: authStatusText
            )
            profileSection
            dataConnectionSection
            trainingBaselineSection
            privacySection
            notificationSection
            appInfoSection
        }
        .navigationTitle("마이")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.load()
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
            Text("마이")
                .font(SOOMFont.display(38, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)
            Text("프로필, 데이터 연결, 운동 기준값을 한곳에서 관리합니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var profileSection: some View {
        SOOMCard {
            SOOMSectionHeader("프로필", caption: "로컬 기록을 유지하면서 Supabase 이메일 세션 확인을 준비합니다. 동기화와 소유권 이전은 다음 단계입니다.")

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

                    SOOMActionRow(icon: "externaldrive.badge.person.crop", title: "기록 소유권", subtitle: ownershipPlanNotice, tint: SOOMColor.secondaryInk)

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

    private var dataConnectionSection: some View {
        SOOMCard {
            SOOMSectionHeader("데이터 연결", caption: "HealthKit과 가져온 운동 기록을 관리합니다.")

            NavigationLink {
                HealthKitSettingsViewContainer()
            } label: {
                SOOMActionRow(icon: SOOMIcon.health, title: "Apple 건강 앱 연결 관리", subtitle: "읽기 권한과 HealthKit 미리보기를 확인합니다.", tint: SOOMColor.bike)
            }
            .buttonStyle(.plain)

            NavigationLink {
                HealthKitWorkoutImportViewContainer()
            } label: {
                SOOMActionRow(icon: SOOMIcon.sync, title: "HealthKit 운동 가져오기", subtitle: "가져온 운동은 성장 분석과 Recovery 미리보기에 사용됩니다.", tint: SOOMColor.recovery)
            }
            .buttonStyle(.plain)
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

    private var ownershipPlanNotice: String {
        let plan = UserOwnershipMigrationPlanner().buildPlan(localSession: authViewModel.session)
        return plan.userFacingSummary
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

#Preview("SettingsView") {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AuthViewModel())
    .preferredColorScheme(.light)
}
