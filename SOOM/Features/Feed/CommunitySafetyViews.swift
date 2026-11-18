import SwiftUI

struct CommunitySafetyMenu: View {
    let target: CommunityReportTarget
    let authorID: UUID
    let authorName: String
    @ObservedObject private var store = CommunitySafetyStore.shared
    @State private var reportTarget: CommunityReportTarget?
    @State private var isConfirmingBlock = false
    @State private var isBlocking = false
    @State private var errorMessage: String?

    private var reportTitle: String {
        switch target.kind {
        case .post: return "게시물 신고"
        case .comment: return "댓글 신고"
        case .club: return "클럽 신고"
        case .user: return "사용자 신고"
        }
    }

    var body: some View {
        Menu {
            Button(reportTitle, soomIcon: "flag") {
                reportTarget = target
            }
            Button("사용자 신고", soomIcon: "person.crop.circle.badge.exclamationmark") {
                reportTarget = CommunityReportTarget(kind: .user, id: authorID)
            }
            Button("사용자 차단", soomIcon: "person.crop.circle.badge.xmark", role: .destructive) {
                isConfirmingBlock = true
            }
        } label: {
            Image(soom: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SOOMColor.secondaryInk)
                .frame(width: 44, height: 44)
        }
        .disabled(isBlocking)
        .onChange(of: store.accountGeneration) { _, _ in
            isConfirmingBlock = false
            reportTarget = nil
            errorMessage = nil
        }
        .accessibilityLabel("신고 및 차단")
        .sheet(item: $reportTarget) { target in
            CommunityReportSheet(target: target, store: store)
        }
        .confirmationDialog("\(authorName)님을 차단할까요?", isPresented: $isConfirmingBlock, titleVisibility: .visible) {
            Button("사용자 차단", role: .destructive) {
                Task {
                    isBlocking = true
                    defer { isBlocking = false }
                    do { try await store.block(userID: authorID, displayName: authorName) }
                    catch { errorMessage = CommunitySafetyError.message(for: error) }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("서로의 게시물과 댓글이 숨겨지고 커뮤니티에서 상호작용할 수 없어요. 설정에서 차단을 해제할 수 있어요.")
        }
        .alert("차단하지 못했어요", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

struct CommunityReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CommunityReportViewModel

    init(target: CommunityReportTarget, store: CommunitySafetyStore) {
        _viewModel = StateObject(wrappedValue: CommunityReportViewModel(target: target, store: store))
    }

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.receiptID != nil {
                    Section {
                        Label("신고가 접수되었어요", soomIcon: "checkmark.circle")
                            .foregroundStyle(SOOMColor.accent)
                        Text(ReviewDemoMode.isActive ? "데모 신고가 이 기기의 체험 세션에 저장됐어요. 실제 운영팀에 전송하지 않습니다." : "운영팀이 커뮤니티 규칙에 따라 검토해요. 신고자의 정보는 상대방에게 공개되지 않아요.")
                        Button("닫기") { dismiss() }
                    }
                } else {
                    Section("신고 이유") {
                        ForEach(CommunityReportReason.allCases) { reason in
                            Button {
                                viewModel.reason = reason
                            } label: {
                                HStack {
                                    Text(reason.title).foregroundStyle(SOOMColor.ink)
                                    Spacer()
                                    if viewModel.reason == reason { Image(soom: "checkmark").foregroundStyle(SOOMColor.accent) }
                                }
                            }
                            .accessibilityAddTraits(viewModel.reason == reason ? [.isSelected] : [])
                        }
                    }
                    Section("추가 내용 (선택)") {
                        TextField("검토에 도움이 되는 내용을 적어 주세요", text: $viewModel.details, axis: .vertical)
                            .lineLimit(4...8)
                        Text("\(viewModel.details.count)/2,000")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let errorMessage = viewModel.errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("community.report.error") }
                    }
                    Section {
                        Button {
                            Task { await viewModel.submit() }
                        } label: {
                            HStack {
                                Text(viewModel.isSubmitting ? "신고 보내는 중…" : "신고 보내기")
                                Spacer()
                                if viewModel.isSubmitting { ProgressView() }
                            }
                        }
                        .disabled(!viewModel.canSubmit)
                        .accessibilityIdentifier("community.report.submit")
                    } footer: {
                        Text(ReviewDemoMode.isActive ? "데모 신고는 체험 세션 안에서만 처리됩니다." : "신고 내용은 운영팀의 검토에 사용돼요. 문의: support@example.com")
                    }
                }
            }
            .disabled(viewModel.isSubmitting)
            .navigationTitle("신고하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.disabled(viewModel.isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
    }
}

struct BlockedUsersView: View {
    @Environment(\.soomBottomOverlayInset) private var bottomOverlayInset
    @ObservedObject var store: CommunitySafetyStore
    @State private var isLoading = false
    @State private var pendingUser: CommunityBlockedUser?
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading && store.blockedUsers.isEmpty { SOOMSkeleton(layout: .list, label: "차단 목록을 불러오는 중") }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("다시 불러오기") { Task { await refresh() } }.disabled(isLoading || isUpdating)
                }
            }
            if !isLoading && store.blockedUsers.isEmpty && errorMessage == nil {
                Text("차단한 사용자가 없어요.").foregroundStyle(.secondary)
            }
            ForEach(store.blockedUsers) { user in
                HStack {
                    Text(user.displayName)
                    Spacer()
                    Button("차단 해제") { pendingUser = user }.disabled(isUpdating)
                }
            }
        }
        .safeAreaPadding(.bottom, bottomOverlayInset)
        .navigationTitle("차단한 사용자")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.accountGeneration) { await refresh() }
        .onChange(of: store.accountGeneration) { _, _ in
            pendingUser = nil
            errorMessage = nil
        }
        .confirmationDialog("차단을 해제할까요?", isPresented: Binding(
            get: { pendingUser != nil }, set: { if !$0 { pendingUser = nil } }
        ), titleVisibility: .visible) {
            if let user = pendingUser {
                Button("차단 해제") {
                    Task {
                        isUpdating = true
                        defer { isUpdating = false; pendingUser = nil }
                        do {
                            try await store.unblock(userID: user.id)
                            errorMessage = nil
                        } catch { errorMessage = CommunitySafetyError.message(for: error) }
                    }
                }
            }
            Button("취소", role: .cancel) { pendingUser = nil }
        } message: { Text("서로의 공개 게시물과 댓글을 다시 볼 수 있어요.") }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do { try await store.refreshBlockedUsers(); errorMessage = nil }
        catch { errorMessage = CommunitySafetyError.message(for: error) }
    }
}

struct BlockedUsersViewContainer: View {
    var body: some View { BlockedUsersView(store: CommunitySafetyStore.shared) }
}

struct CommunityContentUnavailableView: View {
    var body: some View {
        ContentUnavailableView("게시물을 볼 수 없어요", soomIcon: "eye.slash", description: Text("커뮤니티 설정이나 공개 상태가 변경되었어요. 피드를 새로 불러와 주세요."))
    }
}
