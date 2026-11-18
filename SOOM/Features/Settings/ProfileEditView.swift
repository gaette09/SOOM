import SwiftUI
import PhotosUI

/// The auth snapshot includes its session revision, so signing into the same UUID
/// again does not authorize an editor opened for an earlier session.
@MainActor
final class ProfileEditViewModel: ObservableObject {
    @Published var name: String
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    private(set) var originalName: String
    private var owner: AccountDeletionTarget
    @Published private(set) var avatarData: Data?
    @Published private(set) var removesAvatar = false
    @Published private(set) var isLoadingAvatar = false
    private(set) var originalAvatarPath: String?
    var userID: UUID? { owner.userID }
    var isDemoProfile: Bool {
        ReviewDemoMode.isActive && owner.userID == ReviewDemoMode.userID && owner.provider == .local
    }
    var supportsAvatar: Bool { owner.provider == .supabase || isDemoProfile }

    init(auth: AuthViewModel) {
        originalName = auth.session.currentUser?.displayName ?? ""
        name = originalName
        owner = auth.accountDeletionTarget
        originalAvatarPath = auth.session.currentUser?.avatarPath
    }

    var hasAvatarChanges: Bool { avatarData != nil || removesAvatar }
    var hasChanges: Bool { name != originalName || hasAvatarChanges }
    var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool { hasChanges && !normalizedName.isEmpty && normalizedName.count <= 80 && !isSaving && !isLoadingAvatar }

    func selectAvatar(_ data: Data?) {
        guard !isSaving, supportsAvatar else { return }
        do {
            guard let data else { throw ProfileAvatarError.invalidImage }
            avatarData = try ProfileAvatarPolicy.sanitizedJPEG(from: data)
            removesAvatar = false
            errorMessage = nil
        } catch { errorMessage = (error as? LocalizedError)?.errorDescription }
    }

    func setAvatarLoading(_ loading: Bool) { isLoadingAvatar = loading }

    func removeAvatar() {
        guard !isSaving, supportsAvatar else { return }
        avatarData = nil
        removesAvatar = originalAvatarPath != nil
        errorMessage = nil
    }

    func save(using auth: AuthViewModel) async -> Bool {
        guard !isSaving, !isLoadingAvatar else { return false }
        guard owner == auth.accountDeletionTarget, owner.userID != nil else {
            errorMessage = "계정이 변경됐어요. 프로필을 닫고 현재 계정에서 다시 수정해 주세요."
            return false
        }
        guard !auth.isRemoteSessionTransitionInProgress else {
            errorMessage = "계정 작업을 마친 뒤 다시 저장해 주세요."
            return false
        }
        guard !normalizedName.isEmpty, normalizedName.count <= 80 else {
            errorMessage = "이름은 1~80자로 입력해 주세요."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let requestedName = normalizedName
        if requestedName != originalName {
            auth.displayNameText = requestedName
            await auth.updateDisplayName()
            if let error = auth.errorMessage {
                errorMessage = error
                return false
            }
        }
        // Remote updates preserve the revision; AuthViewModel also guards its RPC
        // result. A local update completes synchronously and advances the revision.
        guard auth.session.currentUser?.id == owner.userID,
              auth.session.currentUser?.authProvider == owner.provider,
              owner.provider != .supabase || auth.accountDeletionTarget == owner else {
            errorMessage = "계정이 변경되어 저장 결과를 적용하지 않았어요."
            return false
        }
        guard auth.session.currentUser?.displayName == requestedName else {
            errorMessage = "이름을 저장하지 못했어요. 다시 시도해 주세요."
            return false
        }
        originalName = requestedName
        name = requestedName
        if isDemoProfile { owner = auth.accountDeletionTarget }
        if hasAvatarChanges {
            // A demo name update advances the local revision synchronously.
            // Pin the photo save to that resulting session, retaining the earlier
            // account checks above and exact revision checks across the await.
            let avatarOwner = auth.accountDeletionTarget
            guard await auth.updateAvatar(removesAvatar ? nil : avatarData), auth.accountDeletionTarget == avatarOwner else {
                errorMessage = auth.errorMessage ?? "계정이 변경되어 사진 저장 결과를 적용하지 않았어요."
                return false
            }
            originalAvatarPath = auth.session.currentUser?.avatarPath
            avatarData = nil
            removesAvatar = false
            NotificationCenter.default.post(name: FeedPostManagement.didChange, object: owner.userID)
        }
        return true
    }
}

struct ProfileEditView: View {
    @ObservedObject var auth: AuthViewModel
    @StateObject private var editor: ProfileEditViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsDiscardConfirmation = false
    @FocusState private var isNameFocused: Bool
    @State private var selectedPhoto: PhotosPickerItem?

    init(auth: AuthViewModel) {
        self.auth = auth
        _editor = StateObject(wrappedValue: ProfileEditViewModel(auth: auth))
    }

    var body: some View {
        NavigationStack {
            Form {
                if editor.supportsAvatar {
                    Section("프로필 사진") {
                        HStack(spacing: 18) {
                            if let data = editor.avatarData, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 72, height: 72).clipShape(Circle()).accessibilityHidden(true)
                            } else {
                                SOOMAvatarView(userID: editor.userID,
                                    avatarPath: editor.removesAvatar ? nil : editor.originalAvatarPath, size: 72)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                let photoPickerTitle = editor.originalAvatarPath == nil && editor.avatarData == nil ? "사진 추가" : "사진 변경"
                                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                                    Text(photoPickerTitle)
                                }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("profile.photo.pick")
                                if editor.isDemoProfile {
                                    Button("샘플 사진 사용 / Use Sample") {
                                        selectedPhoto = nil
                                        editor.selectAvatar(ReviewDemoAvatarStore.sampleImageData())
                                    }
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("reviewDemo.profile.samplePhoto")
                                }
                                if editor.avatarData != nil || (editor.originalAvatarPath != nil && !editor.removesAvatar) {
                                    Button("사진 삭제", role: .destructive) {
                                        selectedPhoto = nil
                                        editor.removeAvatar()
                                    }
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("profile.photo.remove")
                                }
                            }
                        }
                        Text(editor.isDemoProfile
                            ? "데모 사진은 이 체험에서만 표시되고 종료하면 삭제돼요. / Demo photo resets on exit."
                            : "선택한 사진만 계정에 저장해요. 프로필과 공유한 운동 기록에 표시됩니다.")
                            .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                        if editor.isLoadingAvatar { ProgressView("사진을 준비하는 중") }
                    }
                }
                Section {
                    TextField("이름", text: $editor.name)
                        .textContentType(.nickname)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit { if editor.canSave { save() } }
                        .accessibilityIdentifier("profile.name")
                    HStack {
                        Text("프로필과 공유한 기록에 표시되는 이름")
                        Spacer(minLength: 8)
                        Text("\(editor.name.count)/80")
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(editor.name.count > 80 ? SOOMColor.warning : SOOMColor.secondaryInk)
                } header: {
                    Text("표시 이름")
                }
                if let error = editor.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(SOOMColor.warning)
                            .accessibilityIdentifier("profile.saveError")
                    }
                }
                if editor.isSaving {
                    ProgressView("프로필을 저장하는 중")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(editor.isSaving)
            .navigationTitle("프로필 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if editor.hasChanges { showsDiscardConfirmation = true }
                        else { dismiss() }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(editor.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .fontWeight(.semibold)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!editor.canSave || auth.isRemoteSessionTransitionInProgress)
                        .accessibilityIdentifier("profile.save")
                }
            }
            .confirmationDialog("변경한 프로필을 저장하지 않고 닫을까요?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("변경사항 버리기", role: .destructive) { dismiss() }
                Button("계속 수정", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(editor.hasChanges || editor.isSaving)
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { editor.setAvatarLoading(false); return }
            editor.setAvatarLoading(true)
            let data = try? await selectedPhoto.loadTransferable(type: Data.self)
            guard !Task.isCancelled else { return }
            editor.selectAvatar(data)
            editor.setAvatarLoading(false)
        }
    }

    private func save() {
        isNameFocused = false
        Task { if await editor.save(using: auth) { dismiss() } }
    }
}
