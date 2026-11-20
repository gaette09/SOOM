import SwiftUI
import PhotosUI
import ImageIO
import UIKit

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
    func reportAvatarReadFailure() { errorMessage = ProfileAvatarError.invalidImage.errorDescription }

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
    @State private var showsPhotoPicker = false
    @State private var readyCrop: ProfileAvatarCropSource?
    @State private var pendingCrop: ProfileAvatarCropSource?
    @State private var reselectAfterCrop = false

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
                                Button(photoPickerTitle) {
                                    isNameFocused = false
                                    showsPhotoPicker = true
                                }
                                .frame(minHeight: 44)
                                .disabled(editor.isLoadingAvatar)
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
        .interactiveDismissDisabled(editor.hasChanges || editor.isSaving || editor.isLoadingAvatar)
        .photosPicker(isPresented: $showsPhotoPicker, selection: $selectedPhoto, matching: .images)
        .sheet(item: $pendingCrop, onDismiss: {
            if reselectAfterCrop {
                reselectAfterCrop = false
                showsPhotoPicker = true
            }
        }) { source in
            ProfileAvatarCropView(source: source) { disposition in
                switch disposition {
                case .cancel: break
                case .reselect: reselectAfterCrop = true
                case .use(let data):
                    if source.owner == auth.accountDeletionTarget && !auth.isRemoteSessionTransitionInProgress {
                        editor.selectAvatar(data)
                    }
                }
                pendingCrop = nil
            }
        }
        .onChange(of: showsPhotoPicker) {
            presentCropIfReady()
        }
        .onChange(of: auth.accountDeletionTarget) {
            selectedPhoto = nil
            readyCrop = nil
            pendingCrop = nil
            reselectAfterCrop = false
            showsPhotoPicker = false
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { editor.setAvatarLoading(false); return }
            let owner = auth.accountDeletionTarget
            editor.setAvatarLoading(true)
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                    throw ProfileAvatarError.invalidImage
                }
                guard !Task.isCancelled, owner == auth.accountDeletionTarget else { return }
                readyCrop = ProfileAvatarCropSource(owner: owner, image: try ProfileAvatarCropImage.decode(data))
                presentCropIfReady()
            } catch {
                guard !Task.isCancelled, owner == auth.accountDeletionTarget else { return }
                editor.reportAvatarReadFailure()
            }
            editor.setAvatarLoading(false)
            self.selectedPhoto = nil
        }
    }

    private func presentCropIfReady() {
        guard !showsPhotoPicker, pendingCrop == nil, let source = readyCrop else { return }
        readyCrop = nil
        guard source.owner == auth.accountDeletionTarget else { return }
        pendingCrop = source
    }

    private func save() {
        isNameFocused = false
        Task { if await editor.save(using: auth) { dismiss() } }
    }
}


/// All coordinates are in a square viewport of side one so resizing, pinch,
/// playback, and the final pixel crop use the same transform.
struct ProfileAvatarCropGeometry {
    let width: CGFloat
    let height: CGFloat

    init?(width: CGFloat, height: CGFloat) {
        guard width.isFinite, height.isFinite, width >= 1, height >= 1 else { return nil }
        self.width = width
        self.height = height
    }

    static let zoomRange: ClosedRange<CGFloat> = 1...5
    var shortSide: CGFloat { min(width, height) }

    func boundedZoom(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed.isFinite ? proposed : 1, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    func frame(zoom: CGFloat) -> CGSize {
        let zoom = boundedZoom(zoom)
        return CGSize(width: width / shortSide * zoom, height: height / shortSide * zoom)
    }

    func boundedOffset(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let size = frame(zoom: zoom)
        let x = (size.width - 1) / 2
        let y = (size.height - 1) / 2
        return CGSize(width: min(x, max(-x, offset.width.isFinite ? offset.width : 0)),
                      height: min(y, max(-y, offset.height.isFinite ? offset.height : 0)))
    }

    func pixelRect(zoom: CGFloat, offset: CGSize) -> CGRect {
        let zoom = boundedZoom(zoom)
        let offset = boundedOffset(offset, zoom: zoom)
        let units = shortSide / zoom
        let side: CGFloat = max(1, units.rounded(.down))
        let left = (width - units) / 2 - offset.width * units
        let top = (height - units) / 2 - offset.height * units
        let x: CGFloat = min(width - side, max(0, left.rounded()))
        let y: CGFloat = min(height - side, max(0, top.rounded()))
        return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: side, height: side))
    }
}

private struct ProfileAvatarCropSource: Identifiable {
    var id = UUID()
    let owner: AccountDeletionTarget
    let image: CGImage

    var geometry: ProfileAvatarCropGeometry {
        // CGImage reports positive integer dimensions for a successful decode.
        ProfileAvatarCropGeometry(width: CGFloat(image.width), height: CGFloat(image.height))!
    }
}

enum ProfileAvatarCropImage {
    static func decode(_ data: Data) throws -> CGImage {
        guard !data.isEmpty, data.count <= 30 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_536,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ProfileAvatarError.invalidImage }
        return image
    }

    static func jpeg(image: CGImage, pixelRect: CGRect) throws -> Data {
        guard let cropped = image.cropping(to: pixelRect) else { throw ProfileAvatarError.invalidImage }
        // Render pixels into a fresh, bounded, opaque square; never attach source metadata.
        let side = CGFloat(min(768, cropped.width))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let data = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .jpegData(withCompressionQuality: 0.88) { context in
                let bounds = CGRect(x: 0, y: 0, width: side, height: side)
                UIColor.white.setFill()
                context.fill(bounds)
                UIImage(cgImage: cropped).draw(in: bounds)
            }
        guard !data.isEmpty, data.count <= ProfileAvatarPolicy.maximumBytes else {
            throw ProfileAvatarError.invalidImage
        }
        return data
    }
}

private struct ProfileAvatarCropView: View {
    enum Disposition { case cancel, reselect, use(Data) }
    private struct Motion {
        var scale: CGFloat = 1
        var translation = CGSize.zero
    }

    let source: ProfileAvatarCropSource
    let finish: (Disposition) -> Void
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var cropFailed = false
    @GestureState private var motion = Motion()

    private var geometry: ProfileAvatarCropGeometry { source.geometry }
    var body: some View {
        NavigationStack {
            GeometryReader { layout in
                let cropSide = max(1, min(360, min(layout.size.width, layout.size.height) - 48))
                    GeometryReader { proxy in
                        let side = max(1, proxy.size.width)
                        let previewZoom = geometry.boundedZoom(zoom * motion.scale)
                        let position = geometry.boundedOffset(
                            CGSize(width: offset.width + motion.translation.width / side,
                                   height: offset.height + motion.translation.height / side), zoom: previewZoom)
                        let size = geometry.frame(zoom: previewZoom)
                        // UIKit displays transparent areas on white, as does the final raster.
                        ZStack {
                            Color.white
                            Image(decorative: source.image, scale: 1, orientation: .up)
                                .resizable()
                                .frame(width: size.width * side, height: size.height * side)
                                .offset(x: position.width * side, y: position.height * side)
                        }
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                        .overlay { Circle().strokeBorder(.secondary.opacity(0.45), lineWidth: 1) }
                        .contentShape(Circle())
                        .gesture(cropGesture(side: side))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("사진 구도")
                        .accessibilityValue("\(Int(zoom * 100))% 확대")
                        .accessibilityHint("위나 아래로 쓸어 확대 크기를 조절하거나 동작에서 사진을 이동할 수 있어요.")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: adjustZoom(by: 0.2)
                            case .decrement: adjustZoom(by: -0.2)
                            @unknown default: break
                            }
                        }
                        .accessibilityAction(named: Text("왼쪽으로 이동")) { move(x: -0.08, y: 0) }
                        .accessibilityAction(named: Text("오른쪽으로 이동")) { move(x: 0.08, y: 0) }
                        .accessibilityAction(named: Text("위로 이동")) { move(x: 0, y: -0.08) }
                        .accessibilityAction(named: Text("아래로 이동")) { move(x: 0, y: 0.08) }
                        .accessibilityIdentifier("profile.photo.crop.preview")
                    }
                    .frame(width: cropSide, height: cropSide)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("프로필 사진 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { finish(.cancel) }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("profile.photo.crop.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        do {
                            finish(.use(try ProfileAvatarCropImage.jpeg(image: source.image,
                                pixelRect: geometry.pixelRect(zoom: zoom, offset: offset))))
                        } catch { cropFailed = true }
                    }
                    .fontWeight(.semibold)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("profile.photo.crop.apply")
                }
            }
            .alert("사진을 편집하지 못했어요", isPresented: $cropFailed) {
                Button("확인", role: .cancel) {}
                Button("다른 사진 선택") { finish(.reselect) }
            } message: {
                Text("다시 시도하거나 다른 사진을 선택해 주세요.")
            }
        }
    }

    private func adjustZoom(by delta: CGFloat) {
        zoom = geometry.boundedZoom(zoom + delta)
        offset = geometry.boundedOffset(offset, zoom: zoom)
    }

    private func move(x: CGFloat, y: CGFloat) {
        offset = geometry.boundedOffset(CGSize(width: offset.width + x, height: offset.height + y), zoom: zoom)
    }

    private func cropGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2).simultaneously(with: MagnifyGesture())
            .updating($motion) { value, state, _ in
                state.scale = value.second?.magnification ?? 1
                state.translation = value.first?.translation ?? .zero
            }
            .onEnded { value in
                zoom = geometry.boundedZoom(zoom * (value.second?.magnification ?? 1))
                let translation = value.first?.translation ?? .zero
                offset = geometry.boundedOffset(
                    CGSize(width: offset.width + translation.width / side,
                           height: offset.height + translation.height / side), zoom: zoom)
            }
    }
}
