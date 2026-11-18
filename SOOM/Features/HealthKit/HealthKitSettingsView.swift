import SwiftUI
import SwiftData
import UserNotifications

struct HealthKitSettingsView: View {
    @StateObject private var viewModel: HealthKitSettingsViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.soomOpenActivities) private var openActivities
    @EnvironmentObject private var storage: HealthAccountStorageController
    @State private var fullHistoryImport = false
    @State private var autoImport = true
    @State private var importNotifications = false
    @State private var recentWorkouts: [HealthKitWorkout] = []
    @State private var importedIDs: Set<UUID> = []
    @State private var selectedWorkout: HealthKitWorkout?
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var isLoadingWorkouts = false
    @State private var loadError: String?
    @State private var importedRecords: [UUID: UnifiedWorkout] = [:]

    init(viewModel: HealthKitSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header
            HealthKitStatusCard(status: recentWorkouts.isEmpty ? viewModel.status : .authorized)
            automationCard
            recentWorkoutsCard
            workoutImportEntryCard
            permissionCard
            workoutPreviewEntryCard
            workoutLibraryEntryCard
            #if DEBUG
            realDataRecoveryPreviewEntryCard
            recoveryPreviewEntryCard
            #endif

            if let errorMessage = viewModel.errorMessage {
                errorCard(errorMessage)
            }
        }
        .navigationTitle("HealthKit 연결")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRecentWorkouts() }
        .refreshable { await loadRecentWorkouts() }
        .alert("이미 가져온 운동", isPresented: Binding(
            get: { selectedWorkout != nil },
            set: { if !$0 { selectedWorkout = nil } }
        )) {
            Button("경로·측정값 다시 가져오기") {
                guard let workout = selectedWorkout else { return }
                selectedWorkout = nil
                Task { await importWorkout(workout) }
            }
            Button("취소", role: .cancel) { selectedWorkout = nil }
        } message: {
            Text("기존 카드, 사진, 댓글과 공개 설정을 유지하면서 건강 앱의 경로와 상세 측정값을 다시 확인합니다. Watch의 동기화가 완료되고 읽기 권한이 허용된 데이터만 보완됩니다.")
        }
    }

    private var automationCard: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: 14) {
                SOOMSectionHeader("자동화 설정", caption: "Apple 건강의 새 운동을 SOOM 활동에 반영합니다.")
                Toggle("새 운동 자동 가져오기", isOn: $autoImport)
                    .onChange(of: autoImport) { _, enabled in
                        HealthKitAutomaticImport.setEnabled(enabled, for: storage)
                        if enabled { Task { await HealthKitAutomaticImport.run(storage: storage); await loadRecentWorkouts() } }
                    }
                Text(fullHistoryImport
                    ? "읽기 권한이 허용된 이전 운동부터 새 운동까지 이어 가져와요. 중단되어도 다음 실행에서 계속합니다."
                    : "건강 앱의 운동 변경 알림이 오면 최근 90일 기록을 반영해요. iOS가 백그라운드 실행을 허용할 때도 동작합니다.")
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                Toggle("이전 운동도 모두 가져오기", isOn: $fullHistoryImport)
                    .accessibilityIdentifier("health.import.fullHistory")
                    .onChange(of: fullHistoryImport) { _, enabled in
                        HealthKitAutomaticImport.setFullHistoryEnabled(enabled,for:storage)
                        if enabled && autoImport { Task { await HealthKitAutomaticImport.run(storage:storage); await loadRecentWorkouts() } }
                    }
                Text("이 선택은 이 계정의 Apple 건강 가져오기 범위만 바꿉니다. 이미 가져온 원본은 삭제하지 않으며, 피드 공개 범위와 심박·경로 공유 동의는 별도로 유지돼요.")
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                Toggle("새 운동 알림", isOn: $importNotifications)
                    .onChange(of: importNotifications) { _, enabled in
                        Task {
                            if enabled {
                                let granted = (try? await UNUserNotificationCenter.current()
                                    .requestAuthorization(options: [.alert, .sound])) ?? false
                                importNotifications = granted
                                HealthKitAutomaticImport.setNotificationsEnabled(granted, for: storage)
                            } else {
                                HealthKitAutomaticImport.setNotificationsEnabled(false, for: storage)
                            }
                        }
                    }
                Text("운동을 가져왔을 때 알립니다. 건강 앱으로 운동 보내기는 현재 지원하지 않아요.")
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            }
        }
        .onAppear {
            fullHistoryImport = HealthKitAutomaticImport.isFullHistoryEnabled(for:storage)
            autoImport = HealthKitAutomaticImport.isEnabled(for: storage)
            importNotifications = HealthKitAutomaticImport.notificationsEnabled(for: storage)
        }
    }

    private var recentWorkoutsCard: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: 12) {
                SOOMSectionHeader("최근 90일 운동", caption: "\(recentWorkouts.count)개 · 건강 앱에서 읽을 수 있는 기록")
                if isLoadingWorkouts && recentWorkouts.isEmpty { SOOMSkeleton(layout: .list, label: "건강 앱 운동 확인 중") }
                if let loadError {
                    Text(loadError).font(.footnote).foregroundStyle(.secondary)
                    Button("다시 불러오기") { Task { await loadRecentWorkouts() } }.frame(minHeight: 44)
                }
                if recentWorkouts.isEmpty && !isLoadingWorkouts && loadError == nil {
                    Text("표시할 운동이 없어요. 건강 앱의 운동 읽기 권한을 확인해 주세요.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                }
                ForEach(recentWorkouts) { workout in
                    Button {
                        if importedIDs.contains(workout.id) { selectedWorkout = workout }
                        else { Task { await importWorkout(workout) } }
                    } label: {
                        HStack {
                            Image(systemName: workout.workoutType == .cycling ? "bicycle" : (workout.workoutType == .swimming ? "figure.pool.swim" : "figure.run"))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(workout.startDate, format: .dateTime.year().month().day().hour().minute())
                                Text("\(workout.deviceName ?? "Apple 건강") · \(workout.distance.map { String(format: "%.2f km", $0 / 1000) } ?? "거리 없음") · \(Int(workout.duration / 60))분")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let record = importedRecords[workout.id] {
                                    Text(record.sharingVisibilityRaw == "source_review_pending" ? "같은 운동의 대표 기록 선택이 필요해요" : (record.preferredWorkoutID != nil && record.preferredWorkoutID != record.id ? "대표 운동의 보완 데이터로 사용 중" : "가져온 운동 · 눌러서 경로·측정값 보완"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: importedIDs.contains(workout.id) ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(SOOMColor.accent)
                                .accessibilityLabel(importedIDs.contains(workout.id) ? "가져온 운동 다시 확인" : "운동 가져오기")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting)
                    Divider()
                }
                NavigationLink { UnifiedWorkoutDuplicateReviewViewContainer() } label: {
                    Label("여러 기기 기록 비교·대표 선택", systemImage: "square.stack.3d.up")
                        .frame(minHeight: 44)
                }
                Text("✓는 기기에 저장한 기록입니다. 피드 공개 여부와는 별개예요. 경로가 비어 있으면 iPhone 피트니스 앱에 경로가 보이는지, 건강 앱의 SOOM 읽기 권한을 확인해 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
                if let importMessage {
                    Text(importMessage).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    Button("활동에서 보기") { openActivities?() }.frame(minHeight: 44)
                }
            }
        }
    }

    private func loadRecentWorkouts() async {
        guard !isLoadingWorkouts, !ReviewDemoMode.isActive else { return }
        isLoadingWorkouts = true
        loadError = nil
        let owner = storage.userID
        let scope = storage.scopeID
        defer { isLoadingWorkouts = false }
        do {
            let cutoff = Date().addingTimeInterval(-90 * 86_400)
            let workouts = try await HealthKitWorkoutFetcher(since: cutoff).fetchRecentWorkouts(limit: 500)
            let raw = try await SwiftDataUnifiedWorkoutStore(modelContext: modelContext).fetchRecentWorkouts(days: 90)
            guard storage.userID == owner, storage.scopeID == scope, modelContext.container === storage.container else { return }
            recentWorkouts = workouts.filter { $0.startDate >= cutoff }.sorted { $0.startDate > $1.startDate }
            importedRecords = Dictionary(raw.filter { $0.source == .appleHealthKit }.map {
                (UUID(uuidString: $0.externalId ?? "") ?? $0.id, $0)
            }, uniquingKeysWith: { first, _ in first })
            importedIDs = Set(importedRecords.keys)
        } catch { loadError = "건강 앱 기록을 읽지 못했어요. 잠금을 풀고 읽기 권한을 확인한 뒤 다시 시도해 주세요." }
    }

    private func importWorkout(_ workout: HealthKitWorkout) async {
        guard !isImporting else { return }
        let owner = storage.userID
        let scope = storage.scopeID
        isImporting = true
        importMessage = nil
        defer { isImporting = false }
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: SingleHealthKitWorkoutFetcher(workout: workout),
            store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext),
            routeLookupProvider: HealthKitWorkoutLookupProvider(),
            routeFetcher: HealthKitWorkoutRouteFetcher(),
            routeStore: SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext),
            telemetryFetcher: HealthKitWorkoutTelemetryFetcher(),
            saveTelemetry: { try WorkoutTelemetryStore(modelContext: modelContext).save($0) },
            autoPublishNewWorkouts: ImportedWorkoutPublication.usesLegacyPublication && storage.autoPublishImportedWorkouts, pendingAudience: storage.defaultWorkoutAudience
        )
        let result = await pipeline.importRecentWorkouts(limit: 1)
        guard storage.userID == owner, storage.scopeID == scope, modelContext.container === storage.container else { return }
        for refreshed in result.refreshedWorkouts {
            let management = WorkoutRecordManagement(workout: refreshed)
            management.configure(context: modelContext, storage: storage)
            if !(await management.refreshProviderMeasurements()) {
                importMessage = "측정값은 기기에 보완했어요. 기존 피드 카드 반영은 다시 시도해 주세요."
            }
        }
        if !result.importedWorkouts.isEmpty, storage.autoPublishImportedWorkouts {
            _ = await ImportedWorkoutPublication(context: modelContext, storage: storage)
                .publish(ids: result.importedWorkouts.map(\.id))
        }
        importMessage = [result.message, importMessage].compactMap { $0 }.joined(separator: "\n")
        NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil)
        await loadRecentWorkouts()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("HealthKit 연결")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("Apple 건강 앱 운동 기록을 SOOM으로 가져오고 연결 상태를 관리합니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var permissionCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "읽기 권한만 요청합니다",
                caption: "운동, 경로, 심박, 러닝·사이클 파워, 속도, 걸음 수·케이던스, 거리와 활동 에너지의 읽기 권한을 요청합니다. 허용되지 않은 항목은 표시되지 않아요."
            )

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Label("운동 기록을 SOOM에 가져와 기기에 저장합니다.", soomIcon: SOOMIcon.record)
                Label("언제든 iPhone 건강 앱 설정에서 권한을 변경할 수 있어요.", soomIcon: SOOMIcon.health)
                Label("분석에 포함한 운동으로 회복과 성장 흐름을 확인할 수 있어요.", soomIcon: SOOMIcon.checkCircle)
            }
            .font(SOOMFont.body(13, relativeTo: .caption))
            .foregroundStyle(SOOMColor.secondaryInk)

            Button {
                Task {
                    await viewModel.requestAuthorization()
                    if viewModel.errorMessage == nil {
                        HealthKitAutomaticImport.setEnabled(true, for: storage)
                        autoImport = true
                        await HealthKitAutomaticImport.run(storage: storage)
                    }
                    await loadRecentWorkouts()
                }
            } label: {
                HStack(spacing: SOOMLayout.SectionHeader.spacing) {
                    if viewModel.isRequesting {
                        ProgressView()
                            .tint(SOOMColor.white)
                            .accessibilityHidden(true)
                    }

                    Text(viewModel.isRequesting ? "권한 요청 중" : "HealthKit 권한 요청하기")
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing + 10)
                .foregroundStyle(SOOMColor.white)
                .background(viewModel.canRequestAuthorization ? SOOMColor.accent : SOOMColor.tertiaryInk)
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canRequestAuthorization)
            .accessibilityLabel("HealthKit 권한 요청하기")
            .accessibilityHint("Apple 건강 앱의 운동 데이터 읽기 권한 요청을 시작합니다.")
        }
    }

    private func errorCard(_ message: String) -> some View {
        SOOMCard {
            SOOMActionRow(
                icon: SOOMIcon.health,
                title: "권한 요청을 완료하지 못했어요",
                subtitle: message,
                tint: SOOMColor.warning
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var workoutPreviewEntryCard: some View {
        NavigationLink {
            HealthKitWorkoutPreviewViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.record,
                    title: "최근 운동 기록 미리보기",
                    subtitle: "HealthKit에서 불러올 수 있는 운동 목록을 확인합니다.",
                    tint: SOOMColor.accent
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("최근 운동 기록 미리보기")
        .accessibilityHint("HealthKit 운동 기록 미리보기 화면으로 이동합니다.")
    }

    #if DEBUG
    private var recoveryPreviewEntryCard: some View {
        NavigationLink {
            HealthKitRecoveryPreviewViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.recovery,
                    title: "HealthKit Recovery 미리보기",
                    subtitle: "HealthKit source로 계산한 회복 요약을 개발용으로 확인합니다.",
                    tint: SOOMColor.warning
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("HealthKit Recovery 미리보기")
        .accessibilityHint("HealthKit 기반 Recovery 개발용 미리보기 화면으로 이동합니다.")
    }

    private var realDataRecoveryPreviewEntryCard: some View {
        NavigationLink {
            RecoveryRealDataPreviewViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.recovery,
                    title: "실제 운동 기반 Recovery 미리보기",
                    subtitle: "가져온 운동 기록으로 계산한 Recovery 요약을 검증합니다.",
                    tint: SOOMColor.accent
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("실제 운동 기반 Recovery 미리보기")
        .accessibilityHint("가져온 UnifiedWorkout 기반 Recovery 미리보기 화면으로 이동합니다.")
    }
    #endif

    private var workoutImportEntryCard: some View {
        NavigationLink {
            HealthKitWorkoutImportViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.sync,
                    title: "HealthKit 운동 가져오기",
                    subtitle: "Apple 건강 앱 운동 기록을 SOOM으로 가져와요. 분석에 포함한 운동으로 회복과 성장 흐름을 확인할 수 있어요.",
                    tint: SOOMColor.accent
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("HealthKit 운동 가져오기")
        .accessibilityHint("HealthKit 운동 기록을 SOOM으로 가져오는 화면으로 이동합니다.")
    }

    private var workoutLibraryEntryCard: some View {
        NavigationLink {
            UnifiedWorkoutLibraryViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.package,
                    title: "가져온 운동 기록 보기",
                    subtitle: "SOOM 공통 운동 데이터로 저장된 기록을 확인합니다.",
                    tint: SOOMColor.secondaryInk
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("가져온 운동 기록 보기")
        .accessibilityHint("UnifiedWorkout 저장소에 저장된 운동 기록 목록으로 이동합니다.")
    }
}

#Preview("HealthKitSettingsView") {
    NavigationStack {
        HealthKitSettingsView(
            viewModel: HealthKitSettingsViewModel(manager: PreviewHealthKitManager())
        )
    }
    .preferredColorScheme(.light)
}

private struct PreviewHealthKitManager: HealthKitManaging {
    func isHealthDataAvailable() -> Bool { true }
    func requestAuthorization() async throws {}
}


private struct SingleHealthKitWorkoutFetcher: HealthKitWorkoutFetching {
    let workout: HealthKitWorkout
    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] { [workout] }
}
