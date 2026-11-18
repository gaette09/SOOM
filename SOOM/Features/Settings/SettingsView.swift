import SwiftUI
import UIKit
import SwiftData
import UniformTypeIdentifiers

enum SettingsCategory: String, CaseIterable, Identifiable {
    case account, privacy, notifications, app, support
    var id: String { rawValue }
    var title: String {
        switch self {
        case .account: return "계정"
        case .privacy: return "개인정보 및 공개 범위"
        case .notifications: return "알림"
        case .app: return "운동 설정"
        case .support: return "도움말 및 앱 정보"
        }
    }
    var subtitle: String {
        switch self {
        case .account: return "로그인 정보와 계정 관리"
        case .privacy: return "기록 공개, 동기화, 차단 관리"
        case .notifications: return "알림 권한 관리"
        case .app: return "운동 기준값, 단위, 기록 가져오기"
        case .support: return "문의, 이용 규칙, 버전 정보"
        }
    }
    var icon: String {
        switch self {
        case .account: return "person.crop.circle"
        case .privacy: return "lock"
        case .notifications: return "bell"
        case .app: return "slider.horizontal.3"
        case .support: return "questionmark.circle"
        }
    }
}

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthStorage: HealthAccountStorageController
    @Environment(\.soomAccountPrivacyModel) private var privacyModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var cloudErasureError: String?
    @State private var accountActionError: String?
    @State private var confirmedDeletionUserID: UUID?
    @ObservedObject private var deletionCleanup = AccountDeletionCleanupCoordinator.shared
    @State private var isShowingDisconnectConfirmation = false
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var deletionConfirmationTarget: AccountDeletionTarget?
    @State private var deletionConfirmationScopeID: String?
    @State private var localDataPresence: LocalDataPresence = .empty
    @State private var demoNotificationsEnabled = false
    @State private var isRequestingNotificationPermission = false
    @ObservedObject private var pushRegistration = PushRegistrationStatus.shared
    @State private var isErasingLocalData = false
    @State private var isDeletingAccount = false
    @State private var showsAppleAccessRemoval = false
    @State private var showsProfileEditor = false
    @State private var disconnectConfirmationTarget: AccountDeletionTarget?
    private let category: SettingsCategory?
    @State private var localErasureFailures: [LocalAccountDataStore] = []
    private let authEnvironment: AuthEnvironment
    private let notificationPermissionRequester: any NotificationPermissionRequesting

    init(
        category: SettingsCategory? = nil,
        viewModel: SettingsViewModel = SettingsViewModel(),
        authEnvironment: AuthEnvironment = AuthEnvironmentLoader().load(),
        notificationPermissionRequester: any NotificationPermissionRequesting = NotificationPermissionRequester()
    ) {
        self.category = category
        _viewModel = StateObject(wrappedValue: viewModel)
        self.authEnvironment = authEnvironment
        self.notificationPermissionRequester = notificationPermissionRequester
    }

    var body: some View {
        SOOMScreen {
            if let category {
                categoryContent(category)
            } else {
                categoryLanding
            }
        }
        .disabled(isDeletingAccount || isErasingLocalData)
        .navigationTitle(category?.title ?? "설정")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
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
            "로그아웃할까요?",
            isPresented: $isShowingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("로그아웃") {
                let target = disconnectConfirmationTarget
                Task {
                    guard target == authViewModel.accountDeletionTarget else {
                        accountActionError = "계정이 변경됐어요. 현재 계정에서 로그아웃을 다시 선택해 주세요."
                        return
                    }
                    accountActionError = nil
                    await authViewModel.disconnectRemoteAccount()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 계정의 기록은 보관되며 화면에서 숨겨집니다. 같은 계정으로 다시 로그인하면 이어 볼 수 있어요.")
        }
        .sheet(isPresented: $showsProfileEditor) {
            ProfileEditView(auth: authViewModel)
        }
        .sheet(isPresented: $isShowingDeleteAccountConfirmation) {
            if let target = deletionConfirmationTarget, let scopeID = deletionConfirmationScopeID {
                AccountDeletionConfirmationSheet(
                    isGuestUser: target.provider != .supabase,
                    onConfirm: {
                        guard target == authViewModel.accountDeletionTarget,
                              scopeID == healthStorage.scopeID else {
                            cloudErasureError = "계정이 변경됐어요. 현재 계정에서 삭제를 다시 확인해 주세요."
                            return
                        }
                        Task { await performAccountDeletion(expectedTarget: target, expectedScopeID: scopeID) }
                    }
                )
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var categoryLanding: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            settingsGroup("계정 및 기기", id: "account") {
                categoryLink(.account)
                Divider()
                integrationLink
            }
            settingsGroup("환경 및 알림", id: "preferences") {
                categoryLink(.app)
                Divider()
                categoryLink(.notifications)
            }
            settingsGroup("개인정보 및 지원", id: "privacy") {
                categoryLink(.privacy)
                Divider()
                categoryLink(.support)
            }
        }
    }

    private func settingsGroup<Content: View>(_ title: String, id: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Spacing.sm) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(SOOMColor.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            SOOMCard { content() }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("settings.group." + id)
    }

    private func categoryLink(_ item: SettingsCategory) -> some View {
        NavigationLink {
            SettingsView(category: item, authEnvironment: authEnvironment,
                         notificationPermissionRequester: notificationPermissionRequester)
        } label: {
            SettingsNavigationRow(icon: item.icon, title: item.title,
                subtitle: item == .account && authViewModel.session.currentUser?.authProvider != .supabase
                    ? "로그인하고 계정 관리하기" : item.subtitle, compact: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.\(item.rawValue)")
    }

    private var integrationLink: some View {
        NavigationLink { IntegrationHubView() } label: {
            SettingsNavigationRow(icon: SOOMIcon.sync, title: "기기·앱 연결 관리",
                                  subtitle: "Apple 건강, Strava ZIP, 지원 기기 안내", compact: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.integrations")
    }

    @ViewBuilder
    private func categoryContent(_ category: SettingsCategory) -> some View {
        switch category {
        case .account:
            if ReviewDemoMode.isActive {
                SOOMCard {
                    Text("DEMO · 로컬 체험 프로필").font(.headline)
                    Text(authViewModel.session.currentUser?.displayName ?? "Demo Athlete")
                    Button("표시 이름 수정 / Edit Name") { showsProfileEditor = true }
                        .frame(minHeight: 44)
                    Text("로그인 없이 사용하는 체험 프로필입니다. 계정 연결·삭제는 데모 종료 후 사용할 수 있어요.")
                        .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                }
                ReviewDemoEntryCard()
            } else {
                profileSection
                if authViewModel.session.currentUser != nil || localDataPresence.hasAnyData || !localErasureFailures.isEmpty || cloudErasureError != nil {
                    dangerZoneSection
                }
                if showsAppleAccessRemoval { appleAccessRemovalNotice }
            }
        case .privacy:
            privacySection
            if ReviewDemoMode.isActive {
                SOOMCard {
                    Text("DEMO · 기기 안에서만 저장").font(.headline)
                    Text("체험 데이터와 변경 사항은 서버에 동기화하지 않으며, 데모를 종료하면 초기화됩니다.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                }
            } else { HealthCloudSettingsSection() }
            SOOMCard {
                NavigationLink { BlockedUsersViewContainer() } label: {
                    SettingsNavigationRow(icon: "person.crop.circle.badge.xmark", title: "차단한 사용자", subtitle: "차단 목록 확인 및 해제")
                }.buttonStyle(.plain)
                NavigationLink { PrivacyAndSupportView() } label: {
                    SettingsNavigationRow(icon: "hand.raised", title: "개인정보 안내", subtitle: "건강·위치 정보의 사용과 삭제")
                }.buttonStyle(.plain)
            }
        case .notifications:
            if ReviewDemoMode.isActive {
                SOOMCard {
                    Text("DEMO · 알림 설정").font(.headline)
                    Toggle("샘플 알림 / Sample notifications", isOn: $demoNotificationsEnabled)
                    Text(demoNotificationsEnabled ? "체험 알림 설정을 켰어요. 실제 푸시 알림은 전송하지 않습니다." : "이 설정은 체험 중에만 유지됩니다. 실제 권한은 요청하지 않습니다.")
                        .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                }
            } else { notificationSection }
        case .app:
            trainingBaselineSection
        case .support:
            appInfoSection
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let user = authViewModel.session.currentUser, user.authProvider == .supabase {
                SOOMCard {
                    Label("로그인됨", soomIcon: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    Text(user.displayName).font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let email = user.email {
                        Text(email).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { showsProfileEditor = true } label: {
                        SettingsNavigationRow(icon: "pencil", title: "프로필 수정", subtitle: "표시 이름 변경")
                    }.buttonStyle(.plain)
                    .disabled(authViewModel.isRemoteSessionTransitionInProgress)
                }
                if authViewModel.isCurrentAccountLinkedToApple {
                    SOOMCard { AppleAuthCard(authViewModel: authViewModel) }
                }
                Button {
                    disconnectConfirmationTarget = authViewModel.accountDeletionTarget
                    isShowingDisconnectConfirmation = true
                } label: {
                    Text("로그아웃")
                        .font(.headline)
                        .foregroundStyle(SOOMColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(authViewModel.isRemoteSessionTransitionInProgress)
                .accessibilityIdentifier("settings.logout")
                Button(authViewModel.isCheckingRemoteSession ? "계정 확인 중" : "로그인 상태 다시 확인") {
                    Task { await authViewModel.checkRemoteSession() }
                }
                .font(.subheadline).frame(minHeight: 44)
                .disabled(authViewModel.isCheckingRemoteSession || authViewModel.isRemoteSessionTransitionInProgress)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("로그인").font(.title2.weight(.semibold))
                    Text("로그인 전 기록은 이 기기에 보관됩니다.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                }
                SOOMCard { AppleAuthCard(authViewModel: authViewModel) }
                SOOMCard { EmailAuthCard(environment: authEnvironment) }
                if authViewModel.session.currentUser == nil {
                    Button("로그인 없이 계속하기") { authViewModel.continueAsLocalUser() }
                        .font(.subheadline).frame(minHeight: 44)
                        .disabled(authViewModel.isRemoteSessionTransitionInProgress)
                } else {
                    Button("이 기기에서 사용하는 이름 수정") { showsProfileEditor = true }
                        .font(.subheadline).frame(minHeight: 44)
                        .disabled(authViewModel.isRemoteSessionTransitionInProgress)
                }
            }
            if let error = accountActionError ?? authViewModel.errorMessage {
                Text(error).font(.subheadline).foregroundStyle(SOOMColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.accountError")
            }
        }
    }

    private var connectionsSection: some View {
        SOOMCard { integrationLink }
    }

    private var trainingBaselineSection: some View {
        SOOMCard {
            SOOMSectionHeader("운동 기준값", caption: "개인 최대심박은 활동 점수 자동 추정과 심박 Zone 기준에 사용돼요. FTP는 파워 Zone 기준이에요. 기록의 최고심박을 개인 최대심박으로 대신하지 않아요.")

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
        VStack(alignment: .leading, spacing: 16) {
            SOOMCard {
                SOOMSectionHeader("현재 공개 대상", caption: ProfileOnlyPrivacyReleaseGate.productionReady ? "모든 운동 요약의 공개범위를 프로필에서 관리해요." : "계정 공개범위와 새 운동의 기본 공개 대상을 확인해요.")
                if let model = privacyModel, authViewModel.session.currentUser?.authProvider == .supabase {
                    Text(model.receipt?.accountScope?.title ?? "확인 필요").font(.headline)
                    Text(model.receipt?.workoutDefault?.shareableVisibility.title ?? "공개범위를 확인해 주세요.")
                    NavigationLink {
                        if let owner = authViewModel.session.currentUser?.id { AccountPrivacySettingsView(owner: owner) }
                    } label: {
                        SettingsNavigationRow(icon: "lock", title: model.usesProfileOnlyRules ? "프로필 공개범위" : "계정 · 새 운동 공개범위", subtitle: "현재 설정 확인 및 변경")
                    }.accessibilityIdentifier("settings.accountPrivacy")
                } else if !ProfileOnlyPrivacyReleaseGate.productionReady {
                    Text("직접 공유 기본값").font(.headline)
                    Text("계정 공개범위는 로그인한 계정의 설정에서 확인해요. 아래 값은 기존 직접 공유 기본값이며 계정 설정을 바꾸지 않아요.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    ForEach(legacyShareChoices, id: \.rawValue) { value in
                        Button { viewModel.updatePrivacyDefault(value) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: viewModel.settings.privacyDefault == value ? "largecircle.fill.circle" : "circle")
                                Text(value == .privateOnly || value == .followers ? "개인 전용 (기존 보관값)" : value.title).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4)
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(viewModel.settings.privacyDefault == value ? .isSelected : [])
                    }
                    Text("맞팔공개는 서로 팔로우한 사람에게, 승인된 팔로워 공개는 승인된 팔로워에게 보여요. 두 공개 대상은 서로 달라요.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                } else {
                    Text("로그인한 뒤 프로필 공개범위를 선택할 수 있어요. 기기에 저장한 운동 원본은 그대로 유지됩니다.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                }
            }
            SOOMCard {
                Text("운동 상세에 포함되는 정보").font(.headline)
                Text("상세 공유에 동의한 운동은 선택한 공개 대상에게 경로와 측정 차트가 함께 공유돼요. 공유 경로는 시작·끝 200m를 가립니다. AI 해석·회복·과거 운동 비교는 본인만 볼 수 있어요.")
                Text(ProfileOnlyPrivacyReleaseGate.productionReady ? "운동 요약은 프로필 공개범위를 따릅니다. 프로필 변경은 심박·경로·사진의 기존 공유 동의나 건강 기록의 클라우드 저장 동의를 바꾸지 않아요." : "기존 개인 전용 운동과 과거 측정자료는 자동으로 공개하지 않아요. 별도로 내보내는 공유 이미지도 미리보기에서 확인해 주세요.")
            }.font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            SOOMCard {
                if ProfileOnlyPrivacyReleaseGate.productionReady {
                    Text("운동 자동 반영").font(.headline)
                    Text("기존 운동과 앞으로 저장하는 운동 요약이 자동으로 반영돼요. 공개 프로필은 팔로워의 피드에, 비공개 프로필은 서로 팔로우한 사람에게만 표시됩니다.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                } else {
                Text("가져온 운동 자동 공개").font(.headline)
                Text(healthStorage.autoPublishImportedWorkouts ? "현재 켜짐 · 이후 새로 가져오는 운동에 적용" : "현재 꺼짐 · 가져온 운동을 자동으로 공개하지 않음")
                Text("설정을 바꿔도 기존 기록은 자동으로 공개하지 않아요. 활동의 가져오기 공개 설정과 각 운동의 공개 대상을 확인해 주세요. 건강 기록의 클라우드 저장 동의는 별도예요.")
                    .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                }
            }
        }.accessibilityIdentifier("settings.privacy.explanation")
    }

    private var legacyShareChoices: [ShareableWorkoutVisibility] {
        let current = viewModel.settings.privacyDefault
        return (current == .privateOnly || current == .followers ? [current] : []) + [.mutual, .publicFeed]
    }

    @ViewBuilder private var notificationSection: some View {
        NotificationSettingsContent(requester: notificationPermissionRequester)
    }

    private var dangerZoneSection: some View {
        SOOMCard {
            SOOMSectionHeader("계정 및 데이터 삭제", caption: "삭제한 데이터는 되돌릴 수 없어요.")

            SOOMActionRow(
                icon: "trash",
                title: dangerZoneActionTitle,
                subtitle: dangerZoneActionSubtitle,
                tint: SOOMColor.warning
            )

            Button(dangerZoneActionTitle) {
                deletionConfirmationTarget = authViewModel.accountDeletionTarget
                deletionConfirmationScopeID = healthStorage.scopeID
                isShowingDeleteAccountConfirmation = true
            }
            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
            .foregroundStyle(SOOMColor.warning)
            .frame(minHeight: 44)
            .disabled(isErasingLocalData || authViewModel.isRemoteSessionTransitionInProgress)

            if isErasingLocalData { ProgressView("기기 데이터를 정리하는 중") }
            if let cloudErasureError {
                Text(cloudErasureError).foregroundStyle(SOOMColor.warning)
            }
            if !localErasureFailures.isEmpty || cloudErasureError != nil {
                Text("일부 기기 데이터를 지우지 못했어요: " + localErasureFailures.map(\.title).joined(separator: ", "))
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.warning)
                Button("남은 기기 데이터 다시 지우기") {
                    Task { await eraseLocalData() }
                }
                .disabled(isErasingLocalData)
            }
        }
    }

    private var dangerZoneActionTitle: String {
        authViewModel.session.currentUser?.authProvider == .supabase ? "계정 삭제" : "기기 데이터 초기화"
    }

    private var dangerZoneActionSubtitle: String {
        authViewModel.session.currentUser?.authProvider == .supabase
            ? "온라인 계정과 서버의 운동·경로·체크인·회복 기록, 게시물, 소유한 클럽과 현재 계정의 기기 사본을 삭제합니다. Apple 건강 앱의 원본 기록은 유지됩니다."
            : "이 기기의 운동·경로·체크인·회복 기록과 설정을 삭제합니다. Apple 건강 앱의 원본 기록은 유지됩니다."
    }

    @MainActor
    private func performAccountDeletion(expectedTarget: AccountDeletionTarget, expectedScopeID: String) async {
        guard !isDeletingAccount else { return }
        guard expectedTarget == authViewModel.accountDeletionTarget,
              expectedScopeID == healthStorage.scopeID,
              healthStorage.userID == expectedTarget.remoteUserID else {
            cloudErasureError = "계정이 변경됐어요. 현재 계정에서 삭제를 다시 확인해 주세요."
            return
        }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        let remoteUserID = expectedTarget.remoteUserID
        if let remoteUserID {
            guard healthStorage.userID == remoteUserID else {
                cloudErasureError = "현재 계정의 기록을 확인하지 못했어요. 다시 시도해 주세요."
                return
            }
            do { try deletionCleanup.begin(userID: remoteUserID) }
            catch {
                cloudErasureError = "기기 정리 재시도 정보를 저장하지 못했어요. 이전 정리를 확인한 뒤 다시 시도해 주세요. 아직 계정 삭제를 시작하지 않았습니다."
                return
            }
        }
        let wasLinkedToApple = authViewModel.isCurrentAccountLinkedToApple
        let deletionCommitted = await authViewModel.deleteAccount(expectedTarget: expectedTarget)
        guard deletionCommitted else { return }
        confirmedDeletionUserID = remoteUserID
        showsAppleAccessRemoval = wasLinkedToApple
        await eraseLocalData()
    }

    @MainActor
    private func eraseLocalData() async {
        guard !isErasingLocalData else { return }
        isErasingLocalData = true
        defer { isErasingLocalData = false }
        // Acknowledgment must reach durable storage before the first local wipe.
        // If writing it fails, keep the session deletion latch and offer a retry.
        if let userID = confirmedDeletionUserID {
            guard healthStorage.userID == userID else {
                cloudErasureError = "계정이 변경되어 기기 정리를 중단했어요."
                return
            }
            do { try deletionCleanup.confirmServerDeletion(userID: userID) }
            catch {
                cloudErasureError = "서버 삭제는 확인했지만 기기 정리 상태를 저장하지 못했어요. 아래에서 다시 시도해 주세요."
                return
            }
        }
        do { try healthStorage.setCloudConsent(false) }
        catch { cloudErasureError = "동기화를 중지하지 못했어요. 다시 시도해 주세요."; return }
        let result = await LocalAccountDataEraser.live(modelContext: modelContext).eraseAll()
        localErasureFailures = result.failedStores
        do {
            try healthStorage.eraseCurrentScopeData(expectedUserID: confirmedDeletionUserID ?? healthStorage.userID,
                retireScope: confirmedDeletionUserID != nil)
            try RecordWorkoutCheckpointStore(
                fileURL: healthStorage.scopeDirectory.appendingPathComponent("active-workout.json")
            ).clear()
            cloudErasureError = nil
        } catch {
            cloudErasureError = "계정의 기기 사본 일부를 정리하지 못했어요. 아래에서 다시 시도해 주세요."
        }
        if localErasureFailures.isEmpty && cloudErasureError == nil {
            do {
                if let userID = confirmedDeletionUserID { try deletionCleanup.complete(userID: userID) }
                confirmedDeletionUserID = nil
                authViewModel.finishAccountDeletion()
            } catch {
                cloudErasureError = "기기 정리는 끝났지만 완료 상태를 저장하지 못했어요. 다시 시도해 주세요."
            }
        }
        viewModel.load()
        await refreshLocalDataPresence()
    }

    private var appInfoSection: some View {
        SOOMCard {
            SOOMSectionHeader("앱 정보")
            SOOMActionRow(icon: "info.circle", title: "SOOM", subtitle: "버전 " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"), tint: SOOMColor.secondaryInk)
            NavigationLink { CommunityRulesView() } label: {
                SOOMActionRow(icon: "person.2", title: "커뮤니티 이용 규칙", subtitle: "신고, 차단 및 운영 기준", tint: SOOMColor.secondaryInk)
            }.buttonStyle(.plain)
            Link(destination: SOOMPublicInformation.supportURL) {
                SOOMActionRow(icon: "envelope", title: "고객지원 및 신고 문의", subtitle: SOOMPublicInformation.supportEmail, tint: SOOMColor.secondaryInk)
            }.buttonStyle(.plain)
            #if DEBUG
            SOOMActionRow(icon: "lock.shield", title: "계정 환경", subtitle: authEnvironmentStatusText, tint: SOOMColor.secondaryInk)
            SOOMActionRow(icon: "person.badge.key", title: "원격 계정 상태", subtitle: authSessionSmokeStatusText, tint: SOOMColor.secondaryInk)
            #endif
        }
    }

    private var appleAccessRemovalNotice: some View {
        SOOMCard {
            Text("온라인 계정을 삭제했어요. 서버에 등록된 Apple 연결은 자동 해제 요청 대상으로 처리됩니다. iPhone 설정 → 내 이름 → Apple로 로그인에서 확인하고, SOOM이 남아 있으면 직접 해제할 수 있어요.")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Link("Apple 연결 해제 안내", destination: URL(string: "https://support.apple.com/102571")!)
                .frame(minHeight: 44)
        }
    }

    private var authEnvironmentStatusText: String {
        let accountStatus = authEnvironment.isSupabaseConfigured ? "계정 연결 준비됨" : "계정 연결 준비 중"
        let redirectStatus = authEnvironment.isRedirectConfigured ? "돌아오기 경로 준비됨" : "돌아오기 경로 준비 중"
        let appleStatus = authEnvironment.isSupabaseConfigured ? "Apple 로그인 준비됨" : "Apple 로그인 준비 중"
        return "\(authEnvironment.environment.title) · \(accountStatus) · \(redirectStatus) · \(appleStatus)"
    }

    private var authSessionSmokeStatusText: String {
        let sessionStatus: String
        if authViewModel.isCheckingRemoteSession {
            sessionStatus = "계정 상태 확인 중"
        } else if authViewModel.session.currentUser?.authProvider == .supabase {
            sessionStatus = "계정 연결됨"
        } else {
            sessionStatus = authEnvironment.isSupabaseConfigured ? "계정 복원 준비됨" : "계정 연결 준비 중"
        }
        return "\(sessionStatus) · 동기화 상태는 내 기록 동기화에서 확인합니다."
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
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SOOMColor.accent)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

/// Shared within profile/settings: a neutral icon, readable labels and a 44pt target.
struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var compact = false
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(soom: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(SOOMColor.secondaryInk)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(SOOMColor.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Image(soom: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SOOMColor.tertiaryInk)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, compact ? SOOMLayout.Spacing.sm : 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
            Image(soom: icon)
                .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
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
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted)
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

// A single catalogue keeps every entry honest about what the iPhone build can do today.
private enum IntegrationProvider: String, CaseIterable, Identifiable {
    case appleHealth, stravaArchive, workoutFile, nike, amazfit, wahoo, garmin
    case googleHealth, samsungHealth, zwift, huawei, coros, oura, peloton, polar, suunto, whoop

    var id: String { rawValue }
    var title: String {
        switch self {
        case .appleHealth: return "Apple 건강"
        case .stravaArchive: return "Strava ZIP"
        case .workoutFile: return "운동 파일"
        case .nike: return "Nike"
        case .amazfit: return "Amazfit"
        case .wahoo: return "Wahoo"
        case .garmin: return "Garmin"
        case .googleHealth: return "Google Health"
        case .samsungHealth: return "Samsung Health"
        case .zwift: return "Zwift"
        case .huawei: return "Huawei"
        case .coros: return "COROS"
        case .oura: return "Oura"
        case .peloton: return "Peloton"
        case .polar: return "Polar"
        case .suunto: return "Suunto"
        case .whoop: return "WHOOP"
        }
    }
    var symbol: String {
        switch self {
        case .appleHealth: return "heart.text.square"
        case .stravaArchive: return "archivebox"
        case .workoutFile: return "doc.zipper"
        case .nike: return "figure.run"
        case .amazfit: return "applewatch"
        case .wahoo, .garmin, .coros, .polar, .suunto: return "bicycle"
        case .googleHealth, .samsungHealth, .huawei: return "heart"
        case .zwift, .peloton: return "figure.indoor.cycle"
        case .oura: return "circle.dotted"
        case .whoop: return "waveform.path.ecg"
        }
    }
    var logoAssetName: String? {
        switch self {
        case .appleHealth: return "IntegrationApple"
        case .stravaArchive: return "IntegrationStrava"
        case .workoutFile: return nil
        case .nike: return "IntegrationNike"
        case .amazfit: return "IntegrationAmazfit"
        case .wahoo: return "IntegrationWahoo"
        case .garmin: return "IntegrationGarmin"
        case .googleHealth: return "IntegrationGoogleHealth"
        case .samsungHealth: return "IntegrationSamsungHealth"
        case .zwift: return "IntegrationZwift"
        case .huawei: return "IntegrationHuawei"
        case .coros: return "IntegrationCoros"
        case .oura: return "IntegrationOura"
        case .peloton: return "IntegrationPeloton"
        case .polar: return "IntegrationPolar"
        case .suunto: return "IntegrationSuunto"
        case .whoop: return "IntegrationWhoop"
        }
    }
    var status: String {
        switch self {
        case .appleHealth, .stravaArchive, .workoutFile, .googleHealth: return "바로 사용"
        case .nike, .amazfit, .wahoo, .garmin, .coros, .polar: return "Apple 건강 경유"
        case .suunto, .zwift: return "운동 파일로 사용"
        default: return "연동 예정"
        }
    }
    var explanation: String {
        switch self {
        case .appleHealth: return "이 iPhone의 Apple 건강 앱에 저장된 운동을 SOOM에 가져옵니다. 권한은 언제든 변경할 수 있어요."
        case .stravaArchive: return "Strava 웹에서 직접 요청한 계정 ZIP을 SOOM으로 가져옵니다. 계정 자동 연동은 제공하지 않아요."
        case .workoutFile: return "FIT, TCX, GPX 원본 파일 하나를 새 운동으로 저장합니다. Garmin·Wahoo·Zwift 등에서 내려받은 파일을 선택할 수 있어요."
        case .nike: return "Nike Run Club에서 Apple 건강 앱으로 공유한 운동을 SOOM에 가져올 수 있어요. 경로 등 세부 항목은 원본 앱이 건강 앱에 보낸 범위에 따라 달라집니다."
        case .amazfit: return "Zepp 앱에서 Apple 건강 앱에 공유한 운동을 SOOM에 가져올 수 있어요. Zepp 계정 직접 연결은 예정되어 있어요."
        case .wahoo: return "Wahoo 앱에서 Apple 건강 앱으로 공유한 운동을 가져올 수 있어요. FIT·TCX·GPX 원본 파일도 가져올 수 있어요. Wahoo 계정 직접 연결은 운영 심사 후 제공할 예정이에요."
        case .garmin: return "Garmin Connect가 Apple 건강 앱에 공유한 운동 요약을 가져올 수 있어요. Garmin은 건강 앱으로 GPS 경로를 보내지 않아요. 직접 연결은 제휴 승인 후 검토합니다. FIT·TCX·GPX 원본 파일도 가져올 수 있어요."
        case .googleHealth: return "Google 계정을 연결해 운동 요약을 SOOM 활동으로 가져옵니다. 연결 상태와 가져오기 결과를 이 화면에서 확인할 수 있어요."
        case .samsungHealth: return "Samsung Health의 Android 기록은 Health Connect 연결이 필요해요. SOOM Android 앱에서 제공할 예정이에요."
        case .zwift: return "Zwift 계정 자동 연결은 파트너 승인이 필요해요. 내려받은 FIT 원본 파일은 지금 가져올 수 있어요."
        case .coros: return "COROS 앱에서 Apple 건강으로 운동 공유를 켜거나 FIT·GPX 원본 파일을 내려받아 가져오세요. COROS 계정 직접 연결은 준비 중이에요."
        case .polar: return "Polar Flow에서 Apple 건강으로 운동 공유를 켠 뒤 SOOM에서 가져오세요. 원본 운동 파일이 있다면 파일 가져오기도 사용할 수 있어요."
        case .suunto: return "Suunto 앱에서 운동을 FIT 또는 GPX로 내보내 SOOM에서 가져올 수 있어요. 계정 직접 연결은 준비 중이에요."
        case .huawei: return "Huawei Health 직접 연결은 데이터 접근 자격과 지역 지원 확인 후 제공할 예정이에요."
        default: return "이 기기 또는 앱의 SOOM 직접 연동은 아직 제공하지 않아요. 지원 범위가 확인되면 여기에 안내할게요."
        }
    }
    var helpURL: URL? {
        let address: String?
        switch self {
        case .stravaArchive: address = "https://support.strava.com/en-us/articles/15401919-how-do-i-export-my-strava-data"
        case .nike: address = "https://www.nike.com/help/a/connect-nrc-health-app"
        case .amazfit: address = "https://support.amazfit.com/"
        case .wahoo: address = "https://support.wahoofitness.com/"
        case .garmin: address = "https://support.garmin.com/"
        case .coros: address = "https://support.coros.com/hc/en-us/articles/360043975752-Exporting-Workout-Data-and-Uploading-to-3rd-Party-Apps"
        case .polar: address = "https://support.polar.com/en/support/connecting_polar_flow_with_apple_health"
        case .suunto: address = "https://us.suunto.com/pages/what-type-of-files-can-i-export-from-the-suunto-app"
        default: address = nil
        }
        return address.flatMap(URL.init(string:))
    }
}

struct IntegrationHubView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    private let ready: [IntegrationProvider] = [.appleHealth, .googleHealth, .stravaArchive, .workoutFile]
    private let bridged: [IntegrationProvider] = [.nike, .amazfit, .wahoo, .garmin,
                                                   .coros, .polar, .suunto, .zwift]
    private let planned: [IntegrationProvider] = [.samsungHealth, .huawei,
                                                   .oura, .peloton, .whoop]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2) }

    var body: some View {
        SOOMScreen {
            VStack(alignment: .leading, spacing: 10) {
                Text("기기와 앱 연결")
                    .font(SOOMFont.display(32, relativeTo: .largeTitle))
                    .foregroundStyle(SOOMColor.ink)
                Text("로고를 선택하면 연결 상태와 가져오는 방법을 확인할 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            integrationGroup("바로 사용", providers: ready)
            integrationGroup("건강 앱·파일로 가져오기", providers: bridged)
            integrationGroup("연동 예정", providers: planned)
        }
        .navigationTitle("기기와 앱")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("integrations.hub")
    }

    private func currentStatus(_ provider: IntegrationProvider) -> String {
        if ReviewDemoMode.isActive { return "합성 체험에서 확인" }
        if provider == .googleHealth {
            return authViewModel.session.currentUser?.authProvider == .supabase ? "선택해 연결 상태 확인" : "로그인 필요"
        }
        if provider == .appleHealth { return "이 iPhone에서 읽기 권한 확인" }
        if provider == .stravaArchive || provider == .workoutFile { return "파일 선택 필요" }
        if planned.contains(provider) { return "직접 연결 준비 중" }
        return "건강 앱 또는 파일로 가져오기"
    }

    private func integrationGroup(_ title: String, providers: [IntegrationProvider]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(SOOMColor.ink)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(providers) { provider in
                    NavigationLink { IntegrationProviderDetailView(provider: provider) } label: {
                        IntegrationBrandLogo(provider: provider, width: 112, height: 30)
                            .environment(\.colorScheme, .light)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            // Keep each existing multicolor brand legible in either appearance.
                            .background(Color.white, in: Capsule())
                            .overlay(Capsule().stroke(SOOMColor.secondaryInk.opacity(0.35), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(provider.title)
                    .accessibilityValue("지원 방식 · \(provider.status). \(currentStatus(provider))")
                    .accessibilityHint("연결 상태와 지원 방법을 엽니다")
                    .accessibilityIdentifier("integrations.\(provider.rawValue)")
                }
            }
        }
        .padding(.vertical, 8)
    }

}

private struct IntegrationBrandLogo: View {
    let provider: IntegrationProvider
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let assetName = provider.logoAssetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: provider == .workoutFile ? "doc" : provider.symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(SOOMColor.ink)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

private struct IntegrationProviderDetailView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    let provider: IntegrationProvider

    private var currentStatus: String {
        if ReviewDemoMode.isActive { return "합성 체험 · 실제 계정 연결 상태가 아니에요" }
        switch provider {
        case .appleHealth: return "아래에서 이 iPhone의 읽기 권한을 확인하세요"
        case .googleHealth:
            return authViewModel.session.currentUser?.authProvider == .supabase
                ? "아래에서 현재 연결 상태와 가져오기 결과를 확인하세요" : "계정 연결에는 로그인이 필요해요"
        case .stravaArchive, .workoutFile: return "가져올 파일을 선택해 주세요"
        case .nike, .amazfit, .wahoo, .garmin, .coros, .polar: return "건강 앱 공유 또는 원본 파일을 이용해요"
        case .suunto, .zwift: return "원본 운동 파일을 이용해요"
        default: return "직접 연결은 아직 제공하지 않아요"
        }
    }

    var body: some View {
        SOOMScreen {
            VStack(spacing: 18) {
                Spacer(minLength: 70)
                IntegrationBrandLogo(provider: provider, width: 220, height: 72)
                Text(provider.title)
                    .font(SOOMFont.display(32, relativeTo: .largeTitle))
                    .foregroundStyle(SOOMColor.ink)
                Text(provider.explanation)
                    .font(.body)
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("지원 방식 · " + provider.status)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SOOMColor.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(SOOMColor.accentSurface, in: Capsule())
                Text(currentStatus)
                    .font(.footnote)
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("integrations.detail.status")
                Spacer(minLength: 40)
                actions
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(provider.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("integrations.detail.\(provider.rawValue)")
    }

    @ViewBuilder
    private var actions: some View {
        if ReviewDemoMode.isActive {
            NavigationLink { ReviewDemoIntegrationView(title: provider.title) } label: {
                primaryAction("샘플 운동 가져오기 / Import Sample")
            }
            .buttonStyle(.plain)
        } else if provider == .stravaArchive {
            NavigationLink { StravaImportViewContainer() } label: { primaryAction("Strava ZIP 가져오기") }
                .buttonStyle(.plain)
        } else if provider == .workoutFile {
            NavigationLink { WorkoutFileImportView() } label: { primaryAction("FIT·TCX·GPX 선택") }
                .buttonStyle(.plain)
        } else if provider == .googleHealth {
            NavigationLink { GoogleHealthConnectionView() } label: { primaryAction("Google 계정 연결 및 가져오기") }
                .buttonStyle(.plain)
        } else if provider == .appleHealth {
            NavigationLink { HealthKitSettingsViewContainer() } label: { primaryAction("Apple 건강 권한 관리") }
                .buttonStyle(.plain)
            NavigationLink { HealthKitWorkoutImportViewContainer() } label: { secondaryAction("운동 가져오기") }
                .buttonStyle(.plain)
        } else if [.nike, .amazfit, .wahoo, .garmin, .coros, .polar].contains(provider) {
            NavigationLink { HealthKitWorkoutImportViewContainer() } label: { primaryAction("Apple 건강 운동 가져오기") }
                .buttonStyle(.plain)
            NavigationLink { HealthKitSettingsViewContainer() } label: { secondaryAction("건강 앱 권한 관리") }
                .buttonStyle(.plain)
            NavigationLink { WorkoutFileImportView() } label: { secondaryAction("운동 원본 파일 가져오기") }
                .buttonStyle(.plain)
        } else if [.suunto, .zwift].contains(provider) {
            NavigationLink { WorkoutFileImportView() } label: { primaryAction("운동 원본 파일 가져오기") }
                .buttonStyle(.plain)
        }
        if let url = provider.helpURL {
            Link(destination: url) { secondaryAction("공식 연결 안내 보기") }
        }
    }

    private func primaryAction(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(SOOMColor.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(SOOMColor.accent, in: Capsule())
    }
    private func secondaryAction(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SOOMColor.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .overlay(Capsule().stroke(SOOMColor.line, lineWidth: 1))
    }
}

struct WorkoutFileImportView: View {
    @Environment(\.soomOpenActivities) private var openActivities
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var storage: HealthAccountStorageController
    @State private var isPickerPresented = false
    @State private var isPublicConfirmationPresented = false
    @State private var isSimilarConfirmationPresented = false
    @State private var isImporting = false
    @State private var selectedURL: URL?
    @State private var resultMessage: String?
    @State private var selectedSport: UnifiedWorkoutType = .other
    @State private var deviceName = "원본 파일"
    private let sports: [UnifiedWorkoutType] = [.other, .running, .cycling, .walking, .swimming, .hiking]
    private let fileTypes: [UTType] = ["fit", "tcx", "gpx"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        if ReviewDemoMode.isActive {
            ReviewDemoIntegrationView(title: "운동 파일 / Workout File")
        } else {
            importContent
        }
    }

    private var importContent: some View {
        SOOMScreen {
            VStack(alignment: .leading, spacing: 12) {
                Text("운동 파일 가져오기")
                    .font(SOOMFont.display(30, relativeTo: .largeTitle))
                Text("기기나 앱에서 내려받은 FIT·TCX·GPX 파일을 새 운동으로 저장해요.")
                    .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            }
            SOOMCard {
                Text("원본 파일 선택").font(.headline)
                Text("ZIP이 아닌 10MB 이하 운동 파일 하나를 선택하세요. 같은 파일은 한 번만 저장하고, 비슷한 운동은 먼저 확인해요.")
                    .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                Picker("원본 기기·앱", selection: $deviceName) {
                    ForEach(["원본 파일", "Garmin", "Wahoo", "Zwift", "COROS", "Polar", "Suunto", "기타 기기"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Picker("운동 종류", selection: $selectedSport) {
                    ForEach(sports, id: \.rawValue) { sport in
                        Text(sportTitle(sport)).tag(sport)
                    }
                }
                Text("FIT·TCX는 파일의 종목을 사용할 수 있어요. GPX에 종목이 없으면 여기서 직접 골라주세요.")
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                Text(ProfileOnlyPrivacyReleaseGate.productionReady
                     ? "저장한 운동 요약은 프로필 공개범위에 따라 자동으로 반영돼요. 파일의 경로·측정 정보 공유 동의는 별도예요."
                     : (storage.autoPublishImportedWorkouts
                        ? "새 운동은 가져온 뒤 공개 피드에 게시돼요. 활동에서 비공개로 바꿀 수 있어요."
                        : "새 운동은 비공개로 저장돼요."))
                    .font(.footnote.weight(.semibold))
                Button {
                    if !ProfileOnlyPrivacyReleaseGate.productionReady && storage.autoPublishImportedWorkouts { isPublicConfirmationPresented = true }
                    else { isPickerPresented = true }
                } label: {
                    HStack {
                        if isImporting { ProgressView().tint(.white) }
                        Text(isImporting ? "가져오는 중" : "FIT·TCX·GPX 파일 선택")
                    }
                    .font(.headline)
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(SOOMColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                .accessibilityIdentifier("integrations.fileImport.select")
            }
            if let resultMessage {
                SOOMCard {
                    Text(resultMessage).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("활동에서 보기") { openActivities?() }.frame(minHeight: 44)
                }
            }
        }
        .navigationTitle("운동 파일")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("새 운동을 공개 피드에 올릴까요?", isPresented: $isPublicConfirmationPresented,
                            titleVisibility: .visible) {
            Button("공개로 파일 선택") { isPickerPresented = true }
            Button("취소", role: .cancel) {}
        } message: {
            Text("선택한 파일에서 새로 저장된 운동만 공개됩니다. 비슷하거나 이미 저장된 운동은 다시 공개하지 않아요.")
        }
        .confirmationDialog("비슷한 운동이 이미 있어요", isPresented: $isSimilarConfirmationPresented,
                            titleVisibility: .visible) {
            Button("별도 운동으로 저장") {
                if let selectedURL { Task { await importFile(selectedURL, allowSimilar: true) } }
            }
            Button("건너뛰기", role: .cancel) { selectedURL = nil }
        } message: {
            Text("건강 앱이나 다른 파일에서 가져온 같은 운동일 수 있어요. 별도로 저장하면 활동에 두 개가 표시됩니다.")
        }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: fileTypes) { result in
            switch result {
            case .success(let url):
                selectedURL = url
                Task { await importFile(url) }
            case .failure:
                resultMessage = "파일 선택을 마치지 못했어요."
            }
        }
    }

    private func sportTitle(_ sport: UnifiedWorkoutType) -> String {
        switch sport {
        case .other: return "파일에서 자동 판별"
        case .running: return "러닝"
        case .cycling: return "자전거"
        case .walking: return "걷기"
        case .swimming: return "수영"
        case .hiking: return "하이킹"
        case .strength: return "근력"
        case .yoga: return "요가"
        }
    }

    @MainActor
    private func importFile(_ url: URL, allowSimilar: Bool = false) async {
        guard !isImporting else { return }
        isImporting = true
        resultMessage = nil
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            isImporting = false
        }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10 * 1_024 * 1_024 else { throw WorkoutFileImportError.fileTooLarge }
            let data = try Data(contentsOf: url)
            let service = WorkoutFileImportService(
                store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext),
                routeStore: SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext)
            )
            let result = try await service.importFile(data, filename: url.lastPathComponent,
                sport: selectedSport, deviceName: deviceName,
                autoPublish: !ProfileOnlyPrivacyReleaseGate.productionReady && storage.autoPublishImportedWorkouts, pendingAudience: storage.defaultWorkoutAudience, allowSimilar: allowSimilar)
            switch result {
            case .duplicate:
                resultMessage = "이미 가져온 동일한 파일이에요. 기존 운동은 유지했어요."
                selectedURL = nil
            case .similarWorkout:
                isSimilarConfirmationPresented = true
            case .imported(let workoutID, let routeSaved):
                selectedURL = nil
                let suffix = routeSaved ? "경로도 함께 저장했어요." : "경로가 없거나 저장되지 않아 운동 요약을 보관했어요."
                if ProfileOnlyPrivacyReleaseGate.productionReady {
                    resultMessage = "운동을 저장했어요. 프로필 공개범위를 확인한 뒤 자동으로 반영합니다. \(suffix)"
                } else if storage.autoPublishImportedWorkouts {
                    let publication = ImportedWorkoutPublication(context: modelContext, storage: storage)
                    let result = await publication.publish(ids: [workoutID])
                    resultMessage = result.published > 0
                        ? "운동을 저장하고 공개 피드에 올렸어요. \(suffix)"
                        : "운동을 저장했어요. 공개 피드 반영은 활동에서 다시 확인해 주세요. \(suffix)"
                } else {
                    resultMessage = "운동을 비공개로 저장했어요. \(suffix)"
                }
            }
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}


struct PushRegistrationPanel: View {
    @ObservedObject var status:PushRegistrationStatus
    let requester:any NotificationPermissionRequesting
    @State private var requesting=false
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            SOOMSectionHeader("알림 권한",caption:"응원·댓글·팔로우 요청과 승인 내역을 알림창에서 확인해요.")
            Text(status.permissionMessage).font(.subheadline).accessibilityIdentifier("push.permission.status")
            Text(status.message).font(.subheadline).accessibilityIdentifier("push.registration.status")
            Button(requesting ? "권한 확인 중" : "알림 권한 요청") {
                requesting=true;Task { await requester.requestAuthorization();requesting=false }
            }.disabled(requesting).frame(minHeight:44).accessibilityIdentifier("push.permission.request")
            if status.state != .registering {
                Button("기기 등록 다시 시도") { status.retryAction?();Task { await requester.registerForBackgroundUpdates() } }
                    .frame(minHeight:44).accessibilityIdentifier("push.registration.retry")
            }
            Button("iPhone 알림 설정") {
                guard !ReviewDemoMode.isActive,let url=URL(string:UIApplication.openSettingsURLString) else { return };UIApplication.shared.open(url)
            }.frame(minHeight:44)
            Text("서버의 확장 알림 활성화와 현재 접근 권한에 따라 수신 대상이 달라져요.").font(.caption).foregroundStyle(SOOMColor.secondaryInk)
        }.task { await requester.refreshPermissionStatus() }
    }
}


/// Shared destination for the inbox and Settings. Opening this page only reads
/// permission state; it never asks for authorization or enables a server feature.
struct NotificationSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NotificationSettingsContent(requester: NotificationPermissionRequester())
            }.padding()
        }
        .navigationTitle("알림 설정")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("notifications.settings.page")
    }
}

struct NotificationSettingsContent: View {
    let requester: any NotificationPermissionRequesting
    @ObservedObject private var status = PushRegistrationStatus.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SOOMCard {
                PushRegistrationPanel(status: status, requester: requester)
            }
            SOOMCard {
                VStack(alignment: .leading, spacing: 12) {
                    SOOMSectionHeader("푸시와 알림함", caption: "기기 알림과 앱 안의 기록은 달라요.")
                    Text("iPhone 알림을 꺼도 앱 알림함의 응원·댓글·팔로우 내역은 삭제되지 않아요.")
                    Text("댓글·응원·팔로우별 푸시 설정과 일시 중지는 아직 지원하지 않아요. 현재는 iPhone 설정에서 앱 알림을 관리할 수 있어요.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                }
            }
            if EventNotificationFeature.enabled {
                NavigationLink("이벤트·광고 알림 설정") { EventNotificationSettingsView() }
                    .accessibilityIdentifier("settings.eventNotifications")
            } else {
                SOOMCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("이벤트·광고 알림").font(.headline)
                        Text("아직 제공하지 않는 기능이에요. 알림함을 열거나 기기 알림을 허용해도 이벤트·광고 수신에 동의한 것으로 처리하지 않아요.")
                            .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await requester.refreshPermissionStatus() } }
        }
    }
}
