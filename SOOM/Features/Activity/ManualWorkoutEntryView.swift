import SwiftData
import SwiftUI
import UIKit

/// Present as a sheet. The supplied callback runs only after the account-scoped
/// workout and its cloud outbox entry have committed successfully.
struct ManualWorkoutEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var storage: HealthAccountStorageController
    @State private var draft = ManualWorkoutDraft()
    @State private var initialScopeID: String?
    @State private var isSaving = false
    @State private var isLoadingPhotos = false
    @State private var photos: [WorkoutPhotoDraft] = []
    @State private var savedWorkout: UnifiedWorkout?
    @State private var attemptedPhotoUpload = false
    @State private var draftStore: (any FeedShareDraftStoreProtocol)?
    @State private var errorMessage: String?
    private let onSave: @MainActor (UnifiedWorkout) -> Void

    init(onSave: @escaping @MainActor (UnifiedWorkout) -> Void = { _ in }) {
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("기기를 착용하지 않았어도 마친 운동을 기록할 수 있어요.")
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
                Section("운동") {
                    Picker("운동 종류", selection: $draft.workoutType) {
                        ForEach(ManualWorkoutDraft.workoutTypes, id: \.rawValue) { type in
                            Text(type.shareDisplayName).tag(type)
                        }
                    }
                    .accessibilityIdentifier("manualWorkout.sport")
                    DatePicker("시작 일시", selection: $draft.startedAt,
                        in: Date(timeIntervalSince1970: 0)...Date(), displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("manualWorkout.date")
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        durationField("시간", text: $draft.hours, identifier: "hours")
                        durationField("분", text: $draft.minutes, identifier: "minutes")
                        durationField("초", text: $draft.seconds, identifier: "seconds")
                    }
                    HStack {
                        Text("거리 (선택)")
                        Spacer()
                        TextField("예: 5.25", text: $draft.distanceKilometers)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("거리, 킬로미터")
                            .accessibilityIdentifier("manualWorkout.distance")
                        Text("km").foregroundStyle(SOOMColor.secondaryInk)
                    }
                    TextField("지역명 (선택)", text: $draft.locationName)
                        .accessibilityIdentifier("manualWorkout.location")
                }
                .disabled(isSaving || savedWorkout != nil)

                Section {
                    TextField("\(draft.workoutType.shareDisplayName) 기록", text: $draft.title, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityLabel("운동 제목")
                        .accessibilityIdentifier("manualWorkout.title")
                    TextField("설명 추가 (선택)", text: $draft.description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("manualWorkout.description")
                    Text("제목 \(draft.title.count)/80 · 설명 \(draft.description.count)/100")
                        .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                } header: { Text("제목과 내용") }
                .disabled(isSaving || savedWorkout != nil)

                Section("운동 사진 (선택)") {
                    if storage.userID != nil {
                        WorkoutPhotoEditor(photos: $photos, isEnabled: !isSaving,
                            onImportingChanged: { isLoadingPhotos = $0 })
                    } else {
                        Text("사진은 로그인 후 기록 편집에서 추가할 수 있어요.")
                            .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                    }
                }

                Section {
                    Label("직접 입력 · 나만 보기", soomIcon: "lock")
                    Text(storageDescription)
                        .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                    Text("직접 입력한 기록에는 GPS 경로, 심박수, 소모 칼로리가 없어요. 페이스는 입력한 거리와 운동 시간으로 계산됩니다.")
                        .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                            .accessibilityIdentifier("manualWorkout.error")
                        if let savedWorkout {
                            Button("저장한 운동 보기") { finish(savedWorkout) }
                                .disabled(isSaving || isLoadingPhotos || initialScopeID != storage.scopeID)
                        }
                    }
                }
            }
            .navigationTitle("운동 직접 입력")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedWorkout == nil ? "취소" : "닫기") { dismiss() }.disabled(isSaving || isLoadingPhotos)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView() } else { Text(savedWorkout == nil ? "저장" : "저장 재시도").fontWeight(.bold) }
                    }
                    .disabled(isSaving || isLoadingPhotos || initialScopeID == nil || initialScopeID != storage.scopeID)
                    .accessibilityIdentifier("manualWorkout.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("입력 완료") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving || isLoadingPhotos)
            .onAppear {
                if initialScopeID == nil {
                    initialScopeID = storage.scopeID
                    draftStore = FileFeedShareDraftStore.live
                }
            }
            .onChange(of: storage.scopeID) { _, _ in
                errorMessage = ManualWorkoutEntryError.accountChanged.localizedDescription
            }
        }
        .tint(SOOMColor.accent)
    }

    private var storageDescription: String {
        if storage.userID == nil {
            return "현재 기기에 저장돼요. 로그인한 뒤 설정에서 기존 기록을 계정으로 가져올 수 있어요."
        }
        if storage.cloudConsentGranted {
            return "이 계정의 기록으로 저장하고 Supabase에 자동 동기화해요. 연결이 끊겨도 저장한 기록은 다시 연결되면 업로드됩니다."
        }
        return "이 계정의 기기 저장소에 저장돼요. 설정에서 운동 기록 클라우드 동기화에 동의하면 Supabase로 업로드됩니다."
    }

    private func durationField(_ label: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            TextField("0", text: text).keyboardType(.numberPad)
                .accessibilityLabel("운동 \(label)")
                .accessibilityIdentifier("manualWorkout.\(identifier)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func save() async {
        guard !isSaving, let initialScopeID, let draftStore, context.container === storage.container else {
            errorMessage = ManualWorkoutEntryError.accountChanged.localizedDescription
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let saver = ManualWorkoutEntrySaver(store: SwiftDataUnifiedWorkoutStore(modelContext: context),
                expectedScopeID: initialScopeID, currentScopeID: { storage.scopeID })
            let workout: UnifiedWorkout
            if let savedWorkout { workout = savedWorkout }
            else {
                workout = try await saver.save(draft)
                savedWorkout = workout
                NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: storage.userID)
            }
            guard initialScopeID == storage.scopeID else { throw ManualWorkoutEntryError.accountChanged }
            let preview = ManualWorkoutFeedDraftCoordinator(store: draftStore,
                expectedScopeID: initialScopeID, currentScopeID: { storage.scopeID })
            try await preview.savePreview(for: workout)
            if ReviewDemoMode.isActive && (!photos.isEmpty || attemptedPhotoUpload) {
                attemptedPhotoUpload = true
                try await ReviewDemoPhotoStore.shared.replace(workout: workout, ownerID: ReviewDemoMode.userID, photos: photos)
                try await preview.removePreviewAfterConfirmedRemotePost(workoutID: workout.id)
            } else if !photos.isEmpty || attemptedPhotoUpload {
                guard let ownerID = storage.userID,
                      let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else {
                    throw WorkoutPhotoError.uploadUnavailable
                }
                attemptedPhotoUpload = true
                try await WorkoutPhotoService(client: client).replace(workout: workout, ownerID: ownerID, photos: photos)
                let posts = try await SupabaseWorkoutRecordRemote(client: client)
                    .linkedPosts(workoutID: workout.id, ownerID: ownerID)
                if !posts.isEmpty { try await preview.removePreviewAfterConfirmedRemotePost(workoutID: workout.id) }
            }
            guard initialScopeID == storage.scopeID else { throw ManualWorkoutEntryError.accountChanged }
            NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: storage.userID)
            finish(workout)
        } catch {
            errorMessage = savedWorkout == nil ? error.localizedDescription
                : "운동 기록은 저장됐지만 피드 또는 사진 반영을 완료하지 못했어요. 다시 시도하거나 저장한 운동의 편집에서 확인해 주세요. " + error.localizedDescription
        }
    }

    @MainActor
    private func finish(_ workout: UnifiedWorkout) {
        onSave(workout)
        dismiss()
    }
}
