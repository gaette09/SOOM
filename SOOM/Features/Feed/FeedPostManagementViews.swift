import SwiftUI

/// A linked detail cannot delete just the old post while its canonical card
/// remains. This context does not affect source-backed workout management.
private struct FeedLegacyPostDeletionAllowedKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    var feedLegacyPostDeletionAllowed: Bool {
        get { self[FeedLegacyPostDeletionAllowedKey.self] }
        set { self[FeedLegacyPostDeletionAllowedKey.self] = newValue }
    }
}
enum FeedPostDeletionPresentationPolicy {
    static func allows(canManage: Bool, legacyDeletionAllowed: Bool) -> Bool {
        canManage && legacyDeletionAllowed
    }
}

struct FeedPostManagementButtons: View {
    @ObservedObject var model: FeedPostManagement
    @Environment(\.feedLegacyPostDeletionAllowed) private var legacyDeletionAllowed
    var includesBookmark = true
    var onDelete: () -> Void = {}
    @State private var editing = false
    @State private var showingMenu = false
    @State private var privacy = false
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 8) {
            if includesBookmark && model.canBookmark {
                Button {
                    Task { await model.toggleBookmark() }
                } label: {
                    Image(soom: model.isBookmarked ? "bookmark.fill" : SOOMIcon.bookmark)
                        .font(.system(size: 22, weight: .regular))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.isBookmarked ? "저장한 기록에서 해제" : "기록 북마크")
                .accessibilityValue(model.isBookmarked ? "저장됨" : "저장 안 됨")
                .accessibilityIdentifier("feed.post.bookmark")
            }
            if model.canManage {
                Button { showingMenu = true } label: {
                    Image(soom: SOOMIcon.more)
                        .font(.system(size: 22, weight: .regular))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("내 게시물 더보기")
                .accessibilityIdentifier("feed.post.manage")
            } else if model.canBookmark {
                CommunitySafetyMenu(target: CommunityReportTarget(kind: .post, id: model.item.id),
                                    authorID: model.item.authorId, authorName: model.item.authorName)
            }
        }
        .foregroundStyle(SOOMColor.ink)
        .buttonStyle(.plain)
        .disabled(model.isWorking)
        .confirmationDialog("게시물 관리", isPresented: $showingMenu, titleVisibility: .visible) {
            if model.canManage {
                Button("기록 수정") { model.errorMessage = nil; editing = true }
                if FeedPostDeletionPresentationPolicy.allows(canManage: model.canManage, legacyDeletionAllowed: legacyDeletionAllowed) {
                    Button("게시물 삭제", role: .destructive) { confirmingDelete = true }
                } else {
                    Text("운동 삭제는 운동 카드의 더보기에서 할 수 있어요.")
                }
            }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("게시물을 삭제할까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            if FeedPostDeletionPresentationPolicy.allows(canManage: model.canManage, legacyDeletionAllowed: legacyDeletionAllowed) {
                Button("게시물 삭제", role: .destructive) {
                    Task {
                        guard FeedPostDeletionPresentationPolicy.allows(canManage: model.canManage, legacyDeletionAllowed: legacyDeletionAllowed) else { return }
                        await model.delete()
                        if model.isDeleted { onDelete() }
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 피드 게시물과 댓글·반응·북마크를 삭제합니다. 원본 운동 기록은 삭제하지 않아요. 게시물 삭제는 되돌릴 수 없어요.")
        }
        .sheet(isPresented: $editing) { FeedPostEditSheet(model: model) }
        .alert("요청을 완료하지 못했어요", isPresented: Binding(
            get: { model.errorMessage != nil && !editing },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .accessibilityHint(model.notice ?? "")
    }
}

struct FeedPostEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: FeedPostManagement
    @State private var title: String
    @State private var description: String
    @State private var confirmingDiscard = false
    @State private var mentionDraft = FeedMentionDraft()
    private let originalTitle: String
    private let originalDescription: String

    init(model: FeedPostManagement) {
        self.model = model
        originalTitle = model.title
        originalDescription = model.description
        _title = State(initialValue: model.title)
        _description = State(initialValue: model.description)
    }

    private var hasUnsavedChanges: Bool { title != originalTitle || description != originalDescription }
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= WorkoutRecordEditPolicy.titleLimit
            && description.count <= WorkoutRecordEditPolicy.descriptionLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("제목") {
                    WorkoutBoundedTextEditor(text: $title, limit: WorkoutRecordEditPolicy.titleLimit,
                        minimumLines: 1, identifier: "feed.post.edit.title", isEnabled: !model.isWorking)
                    Text("\(title.count) / \(WorkoutRecordEditPolicy.titleLimit)자")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Section("간단한 설명") {
                    WorkoutBoundedTextEditor(text: $description, limit: WorkoutRecordEditPolicy.descriptionLimit,
                        minimumLines: 3, identifier: "feed.post.edit.description", isEnabled: !model.isWorking)
                    if FeedMentionPicker.isPreviewEnabled {
                        FeedMentionPicker(text: $description, draft: $mentionDraft, limit: WorkoutRecordEditPolicy.descriptionLimit)
                    }
                    Text("\(description.count) / \(WorkoutRecordEditPolicy.descriptionLimit)자 · 공백 포함")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let message = model.errorMessage {
                    Section {
                        Text(message).foregroundStyle(SOOMColor.run)
                        Text("입력한 내용은 유지됩니다. 연결을 확인한 뒤 저장을 다시 눌러 주세요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if model.isWorking { ProgressView("저장 중") }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("기록 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if hasUnsavedChanges { confirmingDiscard = true }
                        else { dismiss() }
                    }
                    .disabled(model.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        Task {
                            if await model.edit(title: title, description: description) { dismiss() }
                        }
                    }
                    .disabled(model.isWorking || !isValid || !mentionDraft.retainedSelections(in: description).isEmpty)
                    .accessibilityIdentifier("feed.post.edit.save")
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges || model.isWorking)
            .confirmationDialog("저장하지 않은 변경을 버릴까요?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("변경 버리기", role: .destructive) { model.errorMessage = nil; dismiss() }
                Button("계속 수정", role: .cancel) {}
            }
        }
    }
}
