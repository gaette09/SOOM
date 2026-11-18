import SwiftData
import SwiftUI

@MainActor
final class HealthStorageBootstrap: ObservableObject {
    @Published private(set) var controller: HealthAccountStorageController?
    @Published private(set) var errorMessage: String?
    private let remote: (any HealthCloudRemote)?
    init(remote: (any HealthCloudRemote)?) {
        self.remote = remote
        open()
    }
    func open() {
        let cleanup = AccountDeletionCleanupCoordinator.shared
        guard cleanup.prepareBeforeOpeningStorage() else {
            errorMessage = cleanup.errorMessage
            return
        }
        do {
            controller = try HealthAccountStorageController(remote: remote)
            errorMessage = nil
        } catch {
            // Never replace an unreadable persistent store with an empty one.
            errorMessage = "기록 저장 공간을 열지 못했어요. 기존 기록은 그대로 두었습니다. 다시 시도해 주세요."
        }
    }
}

struct HealthAccountRootGate<Content: View>: View {
    @ObservedObject var storage: HealthAccountStorageController
    @ObservedObject private var deletionCleanup = AccountDeletionCleanupCoordinator.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    let authReady: Bool
    @ViewBuilder let content: () -> Content
    @State private var openingError: String?
    @State private var configuredScope: String?
    @State private var consentTarget: HealthCloudConsentTarget?
    @State private var confirmsLocalRemoval = false
    @State private var cleanupActionError: String?

    private var expectedUserID: UUID? {
        let user = authViewModel.session.currentUser
        return user?.authProvider == .supabase ? user?.id : nil
    }
    private var transitionKey: String {
        "\(authReady)-\(expectedUserID?.uuidString ?? "guest")-\(authViewModel.isAccountDeletionInProgress)-\(deletionCleanup.marker?.phase.rawValue ?? "none")"
    }

    var body: some View {
        Group {
            if deletionCleanup.blocksAppAccess && !authViewModel.isAccountDeletionInProgress {
                cleanupRecoveryView
            } else if let openingError {
                ContentUnavailableView {
                    Label("기록을 안전하게 열 수 없어요", soomIcon: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(openingError)
                } actions: {
                    Button("다시 시도") { reconcile() }
                }
            } else if !authReady || configuredScope == nil || (storage.userID != expectedUserID && !authViewModel.isAccountDeletionInProgress) {
                SOOMSkeleton(layout: .workout, label: "계정의 기록을 여는 중").padding(SOOMLayout.screenPadding)
            } else {
                content()
                    .modelContainer(storage.container)
                    .environmentObject(storage)
                    .id(storage.scopeID)
                    .safeAreaInset(edge: .top) {
                        if deletionCleanup.deferredUnconfirmedCleanup {
                            Button("이전 계정 삭제 확인이 필요해요 · 확인") {
                                deletionCleanup.showPendingCleanup()
                            }
                            .font(.footnote)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(.regularMaterial)
                        }
                    }
            }
        }
        .task(id: transitionKey) {
            reconcile()
            if !ReviewDemoMode.isActive && authReady && openingError == nil && !authViewModel.isAccountDeletionInProgress && !deletionCleanup.blocksAppAccess {
                await storage.syncNow()
                await GoogleHealthAutomaticImport.run(storage: storage)
            }
        }
        .sheet(item: $consentTarget) { target in
            NavigationStack {
                HealthCloudConsentView(expectedUserID: target.id)
                    .environmentObject(storage)
            }
        }
    }

    private var cleanupRecoveryView: some View {
        ContentUnavailableView {
            Label("이전 계정의 기기 정리", soomIcon: "externaldrive.badge.exclamationmark")
        } description: {
            if deletionCleanup.marker?.phase == .awaitingServerConfirmation {
                Text("서버에서 계정 삭제가 끝났는지 확인하지 못했어요. 기기 기록은 자동으로 지우지 않았습니다. 기록을 유지하고 계정 삭제를 다시 시도하거나, 이 계정의 기기 사본만 지울 수 있어요.")
            } else {
                Text(deletionCleanup.errorMessage ?? "이전 계정의 남은 기기 데이터를 정리해야 해요. 다른 계정의 기록과 로그인 전 기록은 유지됩니다.")
            }
            if let cleanupActionError { Text(cleanupActionError) }
        } actions: {
            if deletionCleanup.marker?.phase == .awaitingServerConfirmation {
                Button("기록 보존하고 계속") {
                    deletionCleanup.preserveAndContinue()
                    reconcile()
                }
                Button("이 계정의 기기 사본만 삭제", role: .destructive) { confirmsLocalRemoval = true }
            } else {
                Button("남은 기기 데이터 다시 지우기") {
                    deletionCleanup.eraseMountedScope(using: storage)
                    reconcile()
                }
            }
        }
        .confirmationDialog("서버 삭제 여부와 관계없이 기기 사본을 지울까요?", isPresented: $confirmsLocalRemoval, titleVisibility: .visible) {
            Button("이전 계정의 기기 사본 삭제", role: .destructive) {
                guard let userID = deletionCleanup.marker?.userID else { return }
                do {
                    try deletionCleanup.approveLocalRemoval(userID: userID)
                    cleanupActionError = nil
                    deletionCleanup.eraseMountedScope(using: storage)
                    reconcile()
                } catch { cleanupActionError = "정리 상태를 저장하지 못했어요. 아직 기기 기록을 지우지 않았습니다." }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이전에 삭제를 요청한 계정의 운동·경로·체크인·회복 기록과 공유 초안, 진행 중 운동을 이 기기에서 지웁니다. 서버 계정 삭제가 확인되는 것은 아니며, Apple 건강 앱과 다른 계정의 기록은 유지됩니다.")
        }
    }

    private func reconcile() {
        let trace = LoadTrace("health-account-reconcile")
        defer { trace.mark("reconcile-returned") }
        guard !ReviewDemoMode.isActive, authReady, !authViewModel.isAccountDeletionInProgress,
              !deletionCleanup.blocksAppAccess, !deletionCleanup.isCleaning else { return }
        do {
            try storage.switchAccount(userID: expectedUserID)
            if configuredScope != storage.scopeID {
                TrainingSettingsStore.selectAccount(expectedUserID)
                FileFeedShareDraftStore.selectAccount(expectedUserID, directory: storage.scopeDirectory)
                MorningCheckInSkipStore.accountKey = "soom.morningCheckIn.skippedDate." + storage.scopeID
                if expectedUserID == nil { MorningCheckInSkipStore.accountKey = "soom.morningCheckIn.skippedDate" }
                LocalClubPersistence.accountKey = expectedUserID == nil ? "soom.club.local.persistence.v1" : "soom.club.local.persistence.v1." + storage.scopeID
                configuredScope = storage.scopeID
            }
            openingError = nil
            guard let owner = expectedUserID else { consentTarget = nil; return }
            let offeredKey = "healthCloudConsentOffered." + owner.uuidString.lowercased()
            if !storage.cloudConsentGranted && !UserDefaults.standard.bool(forKey: offeredKey) {
                UserDefaults.standard.set(true, forKey: offeredKey)
                consentTarget = HealthCloudConsentTarget(id: owner)
            } else if consentTarget?.id != owner { consentTarget = nil }
        } catch {
            consentTarget = nil
            openingError = "현재 계정의 저장 공간을 열지 못했어요. 다른 계정의 기록은 표시하지 않습니다."
        }
    }
}

struct HealthCloudConsentTarget: Identifiable { let id: UUID }

struct HealthCloudConsentView: View {
    @EnvironmentObject private var storage: HealthAccountStorageController
    @Environment(\.dismiss) private var dismiss
    let expectedUserID: UUID
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("어디서든 내 기록을 이어 보기") {
                Text("동의하면 이 계정에서 저장하는 운동·GPS 경로·심박 등 운동 지표, 체크인과 회복 기록을 Supabase 서버에 보관하고 다른 기기에서 복원해요.")
                Text("내 기록 순위와 분석은 현재 계정의 기록을 사용해요. 서버의 기록은 계정 소유자만 읽고 바꿀 수 있으며, 별도 공유를 선택하기 전에는 피드에 게시되지 않아요.")
            }
            Section("전송과 보관") {
                Text("인터넷이 없으면 이 기기에 임시 저장하고, 연결이 복구되면 자동 전송해요. 기존 로그인 전 기록은 별도로 이관을 선택해야 해요.")
                Text("설정에서 동기화를 중지할 수 있어요. 중지는 서버에 이미 보관한 기록을 삭제하지 않으며, 계정 삭제 시 온라인 기록도 삭제돼요. Apple 건강 앱의 원본은 유지돼요.")
                NavigationLink("데이터 사용 및 개인정보 안내") { PrivacyAndSupportView() }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(SOOMColor.warning) }
            }
            Section {
                Button("동의하고 동기화 시작") {
                    guard storage.userID == expectedUserID else {
                        errorMessage = "계정이 변경됐어요. 현재 계정에서 다시 선택해 주세요."
                        return
                    }
                    do {
                        try storage.setCloudConsent(true)
                        dismiss()
                    } catch {
                        errorMessage = "동의를 저장하지 못했어요. 아직 전송을 시작하지 않았습니다."
                    }
                }
                .font(.headline)
                Button("나중에", role: .cancel) { dismiss() }
            }
        }
        .navigationTitle("내 기록 동기화")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HealthCloudSettingsSection: View {
    @EnvironmentObject private var storage: HealthAccountStorageController
    @State private var consentTarget: HealthCloudConsentTarget?
    @State private var confirmsImport = false
    @State private var conflictChoice: Bool?
    @State private var conflictOwnerID: UUID?
    @State private var importOwnerID: UUID?
    @State private var errorMessage: String?
    @State private var importMessage: String?

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("내 기록 동기화", caption: "계정별로 기록을 보관하고 다른 기기에서 복원합니다.")
            if let owner = storage.userID {
                Toggle("운동·건강 기록 동기화", isOn: Binding(
                    get: { storage.cloudConsentGranted },
                    set: { enabled in
                        if enabled { consentTarget = HealthCloudConsentTarget(id: owner) }
                        else {
                            do { try storage.setCloudConsent(false) }
                            catch { errorMessage = "동기화 설정을 저장하지 못했어요." }
                        }
                    }
                ))
                .tint(SOOMColor.accent)
                Text(statusText).font(SOOMFont.body(13)).foregroundStyle(SOOMColor.secondaryInk)
                if let date = storage.lastSyncAt {
                    Text("최근 확인: " + date.formatted(date: .abbreviated, time: .shortened))
                        .font(SOOMFont.body(12, relativeTo: .caption)).foregroundStyle(SOOMColor.secondaryInk)
                }
                if storage.cloudConsentGranted {
                    Button {
                        Task { await storage.syncNow() }
                    } label: {
                        Label(storage.isSyncing ? "동기화 중" : "지금 동기화", soomIcon: "arrow.triangle.2.circlepath")
                    }
                    .disabled(storage.isSyncing)
                    Button("로그인 전 이 기기 기록 가져오기") { importOwnerID = owner; confirmsImport = true }
                        .disabled(storage.isSyncing)
                    if storage.conflictCount > 0 {
                        Text("\(storage.conflictCount)개 기록이 다른 기기에서도 변경됐어요. 선택하기 전까지 양쪽 변경을 보존합니다.")
                            .font(SOOMFont.body(13))
                        Button("충돌 기록: 서버 기록 사용") { conflictOwnerID = owner; conflictChoice = false }
                        Button("충돌 기록: 이 기기 변경 사용") { conflictOwnerID = owner; conflictChoice = true }
                    }
                } else {
                    Text("동기화가 중지되어 있어요. 이미 서버에 저장한 기록은 유지됩니다.")
                        .font(SOOMFont.body(12, relativeTo: .caption)).foregroundStyle(SOOMColor.secondaryInk)
                }
                if let message = errorMessage ?? storage.errorMessage {
                    Text(message).font(SOOMFont.body(13)).foregroundStyle(SOOMColor.warning)
                }
                if let importMessage { Text(importMessage).font(SOOMFont.body(13)) }
            } else {
                Text("로그인 후 동기화에 동의하면 내 기록을 서버에 보관할 수 있어요. 로그인 전 기록은 자동으로 전송하지 않아요.")
                    .font(SOOMFont.body(13)).foregroundStyle(SOOMColor.secondaryInk)
            }
        }
        .sheet(item: $consentTarget) { target in
            NavigationStack { HealthCloudConsentView(expectedUserID: target.id).environmentObject(storage) }
        }
        .confirmationDialog("로그인 전 기록을 현재 계정으로 가져올까요?", isPresented: $confirmsImport, titleVisibility: .visible) {
            Button("현재 계정으로 가져오기") {
                guard let owner = importOwnerID, storage.userID == owner else { return }
                do {
                    try storage.importGuestData(expectedUserID: owner)
                    importMessage = "기존 기록을 가져왔어요. 전송 상태는 동기화 결과에서 확인해 주세요."
                    errorMessage = nil
                } catch { errorMessage = error.localizedDescription }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 기기의 로그인 전 운동·경로·체크인·회복 기록을 현재 계정에 복사하고 서버에 전송합니다. 다른 계정으로 가져갔던 기록은 다시 이관하지 않습니다.")
        }
        .confirmationDialog("충돌한 기록의 기준을 선택합니다", isPresented: Binding(
            get: { conflictChoice != nil }, set: { if !$0 { conflictChoice = nil } }
        ), titleVisibility: .visible) {
            let keepLocal = conflictChoice == true
            Button(keepLocal ? "이 기기 변경으로 서버 갱신" : "서버 기록으로 이 기기 갱신") {
                guard let owner = conflictOwnerID, storage.userID == owner else { conflictChoice = nil; return }
                Task { await storage.resolveConflicts(expectedUserID: owner, keepingLocal: keepLocal) }
                conflictChoice = nil
            }
            Button("취소", role: .cancel) { conflictChoice = nil }
        } message: {
            Text("현재 충돌한 \(storage.conflictCount)개 기록 모두에 적용합니다. 선택하지 않은 쪽의 변경은 덮어씁니다.")
        }
    }

    private var statusText: String {
        if storage.isSyncing { return "기록을 안전하게 동기화하고 있어요." }
        if storage.invalidRecordCount > 0 { return "서버 기록 \(storage.invalidRecordCount)개를 읽지 못했어요. 다른 기록은 계속 복원합니다." }
        if storage.conflictCount > 0 { return "충돌 \(storage.conflictCount)개 · 전송 대기 \(storage.pendingCount)개" }
        if storage.pendingCount > 0 { return "전송 대기 \(storage.pendingCount)개 · 연결이 복구되면 다시 시도해요." }
        if storage.lastSyncAt != nil { return "이 계정의 기록이 동기화됐어요." }
        return "아직 서버와 동기화를 확인하지 않았어요."
    }
}
