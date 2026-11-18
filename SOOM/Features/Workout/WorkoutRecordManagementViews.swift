import Combine
import SwiftData
import SwiftUI
import UIKit

/// UITextView enforces the limit at the edit boundary, including paste and IME
/// composition. SwiftUI's multiline TextField can retain over-limit display text.
struct WorkoutBoundedTextEditor: UIViewRepresentable {
    @Binding var text: String
    let limit: Int
    let minimumLines: Int
    let identifier: String
    var isEnabled = true

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = minimumLines == 1 ? "운동 제목" : "설명 추가 (선택)"
        view.isEditable = isEnabled
        if view.text != text && view.markedTextRange == nil { view.text = text }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let line = uiView.font?.lineHeight ?? 22
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: min(max(size.height, line * CGFloat(minimumLines)), line * 6))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: WorkoutBoundedTextEditor
        init(_ parent: WorkoutBoundedTextEditor) { self.parent = parent }
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText value: String) -> Bool {
            guard view.markedTextRange == nil else { return true }
            guard let replacementRange = Range(range, in: view.text) else { return false }
            let proposed = view.text.replacingCharacters(in: replacementRange, with: value)
            guard proposed.count > parent.limit else { return true }
            let remaining = max(0, parent.limit - (view.text.count - view.text[replacementRange].count))
            let accepted = String(value.prefix(remaining))
            view.text = view.text.replacingCharacters(in: replacementRange, with: accepted)
            parent.text = view.text
            view.selectedRange = NSRange(location: min(range.location + accepted.utf16.count, view.text.utf16.count), length: 0)
            return false
        }
        func textViewDidChange(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let bounded = String(view.text.prefix(parent.limit))
            if view.text != bounded { view.text = bounded }
            parent.text = bounded
        }
    }
}

private struct WorkoutManagementEnvironmentKey: EnvironmentKey {
    static let defaultValue: WorkoutRecordManagement? = nil
}
extension EnvironmentValues {
    var workoutManagement: WorkoutRecordManagement? {
        get { self[WorkoutManagementEnvironmentKey.self] }
        set { self[WorkoutManagementEnvironmentKey.self] = newValue }
    }
}

struct WorkoutManagementHost<Content: View>: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var storage: HealthAccountStorageController
    @Query private var records: [UnifiedWorkoutRecord]
    @StateObject private var model: WorkoutRecordManagement
    let content: (UnifiedWorkout, WorkoutRecordManagement) -> Content
    init(workout: UnifiedWorkout, @ViewBuilder content: @escaping (UnifiedWorkout, WorkoutRecordManagement) -> Content) {
        let id = workout.id
        _records = Query(filter: #Predicate<UnifiedWorkoutRecord> { $0.id == id })
        _model = StateObject(wrappedValue: WorkoutRecordManagement(workout: workout))
        self.content = content
    }
    var body: some View {
        Group {
            if model.isDeleted || records.isEmpty {
                ContentUnavailableView("기록이 삭제되었어요", soomIcon: SOOMIcon.trash,
                    description: Text("목록으로 돌아가 다른 운동을 확인해 주세요."))
                    .navigationTitle("운동 상세").toolbar(.visible, for: .navigationBar)
            } else {
                content(displayWorkout, model)
            }
        }
            .environment(\.workoutManagement, model)
            .task {
                model.configure(context: context, storage: storage)
                adoptRecord()
                await model.refreshSharing()
            }
            .onChange(of: records.first?.updatedAt) { _, _ in adoptRecord() }
            .onChange(of: storage.dataRevision) { _, _ in adoptRecord() }
    }
    private var displayWorkout: UnifiedWorkout {
        let current = model.workout
        guard current.preferredWorkoutID == current.id,
              context.container === storage.container,
              let originals = try? WorkoutTelemetryStore(modelContext: context).relatedWorkouts(to: current) else { return current }
        // Enrich the display only. Owner edits always write to the selected
        // original and never overwrite another device's measurements.
        return UnifiedWorkoutDeduplicationEngine().canonicalWorkouts(originals)
            .first { $0.id == current.id } ?? current
    }

    private func adoptRecord() {
        if let record = records.first { model.adopt(UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)) }
    }
}

struct WorkoutVisibilityLabel: View {
    let visibility: FeedPostVisibility?
    var body: some View {
        Label(title, soomIcon: visibility == .publicPost ? "globe" : "lock")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(SOOMColor.secondaryInk)
            .accessibilityLabel("공개 범위: \(title)")
    }
    private var title: String {
        switch visibility {
        case .publicPost: return "공개"
        case .privatePost: return "나만 보기"
        case .followers: return "승인된 팔로워"
    case .mutual: return "맞팔공개"
        case nil: return "공개 범위 확인 필요"
        }
    }
}

struct WorkoutRecordHeading: View {
    let title: String
    let date: Date
    let sport: String
    let description: String?
    let visibility: FeedPostVisibility?
    var sportType: UnifiedWorkoutType = .other
    var author: String = "나"
    var authorID: UUID? = nil
    var avatarPath: String? = nil
    var device: String? = nil
    var location: String = "지역 미입력"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkoutIdentityLine(author: author, authorID: authorID, avatarPath: avatarPath,
                date: date, device: nil, sport: sportType, location: location)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title2.weight(.bold)).foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let description, !description.isEmpty {
                    Text(description).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkoutManagementButtons: View {
    @Environment(\.workoutDetailSharing) private var sharing
    @ObservedObject var model: WorkoutRecordManagement
    var includesBookmark = true
    var onDelete: () -> Void = {}
    @State private var editing = false
    @State private var privacy = false
    @State private var confirmingDelete = false
    @State private var showingMenu = false
    var body: some View {
        HStack(spacing: 8) {
            if includesBookmark {
                Button { Task { await model.toggleBookmark() } } label: {
                    Image(soom: model.isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 22, weight: .medium)).frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.isBookmarked ? "저장한 기록에서 해제" : "기록 북마크")
                .accessibilityValue(model.isBookmarked ? "저장됨" : "저장 안 됨")
            }
            Button { showingMenu = true } label: {
                Image(soom: "ellipsis").font(.system(size: 22, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("기록 더보기")
            .accessibilityIdentifier("workout.detail.more")
        }
        .foregroundStyle(SOOMColor.ink)
        .background(SOOMColor.surface, in: Capsule())
        .buttonStyle(.plain)
        .disabled(model.isWorking)
        .confirmationDialog("기록 관리", isPresented: $showingMenu, titleVisibility: .visible) {
            if let sharing {
                Button("이미지로 공유하기") { sharing.actions.send(.image) }
            }
            Button("기록 수정") { editing = true }
            Button("기록 삭제", role: .destructive) { confirmingDelete = true }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("기록을 삭제할까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("기록 삭제", role: .destructive) {
                Task { await model.delete(); if model.isDeleted { onDelete() } }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("SOOM의 운동 기록과 경로, 연결된 피드 게시물을 삭제합니다. 이 작업은 되돌릴 수 없어요. 원본 운동 앱의 기록은 유지됩니다.")
        }
        .sheet(isPresented: $editing) { WorkoutRecordEditSheet(model: model) }
        .alert("변경하지 못했어요", isPresented: Binding(get: { model.errorMessage != nil && !editing }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("확인", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .overlay(alignment: .bottom) {
            if model.isWorking { ProgressView().offset(y: 24).accessibilityLabel("저장 중") }
        }
        .accessibilityHint(model.notice ?? "제목·설명 수정, 이미지 공유와 기록 삭제를 관리합니다.")
    }
}

struct WorkoutPhotoEditButton: View {
    @ObservedObject var model: WorkoutRecordManagement
    @State private var editing = false
    @EnvironmentObject private var storage: HealthAccountStorageController

    var body: some View {
        Button { editing = true } label: {
            Label("사진 추가·수정", systemImage: "photo.badge.plus")
        }
        .accessibilityIdentifier("workout.photos.edit")
        .disabled(model.isWorking)
        .sheet(isPresented: $editing) { WorkoutRecordEditSheet(model: model, photosOnly: true) }
        .onChange(of: storage.scopeID) { _, _ in editing = false }
    }
}

struct WorkoutRecordEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: WorkoutRecordManagement
    @State private var title: String
    @State private var description: String
    @State private var location: String
    @State private var discard = false
    @State private var photos: [WorkoutPhotoDraft] = []
    @State private var originalPhotos: [WorkoutPhotoDraft] = []
    @State private var importingPhotos = false
    private let originalTitle: String
    private let originalDescription: String
    private let originalLocation: String
    private let photosOnly: Bool
    init(model: WorkoutRecordManagement, photosOnly: Bool = false) {
        self.model = model
        self.photosOnly = photosOnly
        originalTitle = model.workout.displayTitle; originalDescription = model.workout.userDescription ?? ""
        originalLocation = model.workout.locationName ?? ""
        _title = State(initialValue: model.workout.displayTitle)
        _description = State(initialValue: model.workout.userDescription ?? "")
        _location = State(initialValue: model.workout.locationName ?? "")
    }
    private var dirty: Bool { title != originalTitle || description != originalDescription || location != originalLocation || photos != originalPhotos }
    var body: some View {
        NavigationStack {
            Form {
                if !photosOnly {
                    Section("제목") {
                        WorkoutBoundedTextEditor(text: $title, limit: WorkoutRecordEditPolicy.titleLimit,
                            minimumLines: 1, identifier: "workout.edit.title", isEnabled: !model.isWorking)
                    }
                    Section {
                        WorkoutBoundedTextEditor(text: $description, limit: WorkoutRecordEditPolicy.descriptionLimit,
                            minimumLines: 3, identifier: "workout.edit.description", isEnabled: !model.isWorking)
                        Text("\(description.count) / 100자 · 공백 포함")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                    } header: { Text("간단한 설명") }
                    Section("지역") {
                        WorkoutBoundedTextEditor(text: $location, limit: WorkoutRecordEditPolicy.locationLimit,
                            minimumLines: 1, identifier: "workout.edit.location", isEnabled: !model.isWorking)
                        Text("운동한 지역을 입력하면 카드와 상세 화면에 표시돼요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("운동 사진") {
                    if model.canSavePhotos {
                        if model.photosLoading && photos.isEmpty { SOOMSkeleton(layout: .photo, label: "사진 불러오는 중").frame(height: 160) }
                        else if let error = model.photosError {
                            Text(error).foregroundStyle(.secondary)
                            Button("다시 불러오기") { Task { await loadPhotos() } }
                        } else { WorkoutPhotoEditor(photos: $photos, isEnabled: !model.isWorking,
                            onImportingChanged: { importingPhotos = $0 }) }
                    } else {
                        Text("로그인하면 운동 사진을 계정에 저장할 수 있어요.").foregroundStyle(.secondary)
                    }
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red); Text("입력한 내용은 유지됩니다. 저장을 다시 눌러 재시도하세요.").font(.footnote) }
                }
                if model.isWorking { ProgressView("저장 중") }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(photosOnly ? "사진 추가·수정" : "기록 수정").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { if dirty { discard = true } else { dismiss() } }.disabled(model.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task {
                        if photosOnly {
                            if photos == originalPhotos { dismiss() }
                            else if await model.replacePhotos(photos) { dismiss() }
                        } else if await model.edit(title: title, description: description, location: location,
                            photos: photos == originalPhotos ? nil : photos) { dismiss() }
                    } }
                        .disabled(model.isWorking || model.photosLoading || importingPhotos || (photosOnly && (!model.canSavePhotos || model.photosError != nil)) || (!photosOnly && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .interactiveDismissDisabled(dirty || model.isWorking || importingPhotos)
            .task { await loadPhotos() }
            .confirmationDialog("저장하지 않은 변경을 버릴까요?", isPresented: $discard, titleVisibility: .visible) {
                Button("변경 버리기", role: .destructive) { model.errorMessage = nil; dismiss() }
                Button("계속 수정", role: .cancel) {}
            }
        }
    }
    private func loadPhotos() async {
        await model.refreshPhotos()
        guard model.photosError == nil else { return }
        photos = model.photos; originalPhotos = model.photos
    }
}

@MainActor
final class WorkoutDetailShareActions: ObservableObject {
    enum Action { case image, feed }
    let actions = PassthroughSubject<Action, Never>()
}
private struct WorkoutDetailSharingKey: EnvironmentKey {
    static let defaultValue: WorkoutDetailShareActions? = nil
}
extension EnvironmentValues {
    var workoutDetailSharing: WorkoutDetailShareActions? {
        get { self[WorkoutDetailSharingKey.self] }
        set { self[WorkoutDetailSharingKey.self] = newValue }
    }
}
