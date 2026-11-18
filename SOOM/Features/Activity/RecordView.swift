import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var accountStorage: HealthAccountStorageController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var locationManager = RecordLocationManager(isDemo: ReviewDemoMode.isActive)
    @State private var selectedSport: RecordSportMode = RecordLaunchPlan.initial.defaultSport
    @State private var selectedRoute = RecordLaunchPlan.initial.route
    @State private var isWeatherDetailPresented = false
    @State private var isManualWorkoutPresented = false
    @State private var isRouteRecommendationPresented = false
    @State private var isReadyFocusMode = false
    @State private var hoveredSport: RecordSportMode?
    @State private var readyDragLocation: CGPoint?
    @State private var isTapStartPresented = false
    @State private var isWatchStartBlocked = false
    @State private var readyResetID = UUID()
    @State private var recenterTrigger = 0
    @State private var activeSession: RecordWorkoutSession?
    @State private var currentDate = Date()
    @State private var isSavingWorkout = false
    @State private var saveErrorMessage: String?
    @State private var hasPendingRouteSave = false
    @State private var checkpointStore: RecordWorkoutCheckpointStore?
    @State private var checkpointScopeID: String?
    @State private var checkpointMessage: String?
    @State private var checkpointLoadFailed = false
    @State private var lastCheckpointDate = Date.distantPast
    @State private var savedWorkoutForShare: UnifiedWorkout?
    @State private var isSourceReviewPresented = false
    @State private var isCreatingShareDraft = false
    @State private var shareDraftErrorMessage: String?
    @State private var shareOutcome: RecordShareOutcome?
    @State private var selectedShareVisibility: ShareableWorkoutVisibility = .privateOnly
    @State private var weatherSnapshot = RecordWeatherSnapshot.unavailable
    @State private var weatherDetailSnapshot = RecordWeatherDetailSnapshot.make(from: .unavailable)
    @State private var isFetchingWeather = false
    @State private var weatherRetryState = RecordWeatherRetryState()
    @State private var isBottomGradientBreathing = false
    @State private var readyInteractionState = RecordReadyWaveInteractionState.idle
    @State private var activeHUDMode: RecordActiveHUDMode = .defaultMode
    @State private var recoveryLabel = "회복 확인 중"
    @StateObject private var coach = WorkoutCoachCoordinator()
    @State private var isCoachSettingsPresented = false
    @State private var isFinishConfirmationPresented = false
    @State private var isCancelConfirmationPresented = false

    private let plan = RecordLaunchPlan.initial
    private let sessionStarter = RecordWorkoutSessionStarter()
    private let weatherService: any RecordWeatherService
    private let onDismiss: (() -> Void)?
    private let onSaveComplete: (() -> Void)?
    private let onShareDraftComplete: (() -> Void)?

    private var isExpandedHUDPresented: Bool {
        activeSession != nil && activeHUDMode == .expanded
    }

    init(
        weatherService: any RecordWeatherService = RecordWeatherServiceFactory.make(),
        onDismiss: (() -> Void)? = nil,
        onSaveComplete: (() -> Void)? = nil,
        onShareDraftComplete: (() -> Void)? = nil,
        shouldAutoPresentRouteRecommendation: Bool = false
    ) {
        self.weatherService = weatherService
        self.onDismiss = onDismiss
        self.onSaveComplete = onSaveComplete
        self.onShareDraftComplete = onShareDraftComplete
        _isRouteRecommendationPresented = State(initialValue: shouldAutoPresentRouteRecommendation)
    }

    var body: some View {
        GeometryReader { proxy in
            let headerFrames = RecordMapHeaderLayout.frames(
                containerSize: proxy.size,
                safeAreaTop: proxy.safeAreaInsets.top
            )

            ZStack {
                RecordMapView(
                    sport: selectedSport,
                    route: selectedRoute,
                    capturedRoute: activeSession?.capturedRoute,
                    locationState: locationManager.state,
                    recenterTrigger: recenterTrigger,
                    sessionState: activeSession?.state,
                    reduceMotionEnabled: reduceMotion,
                    hidesCompass: isExpandedHUDPresented
                )
                    .ignoresSafeArea()
                    .zIndex(RecordActiveHUDLayerLayout.mapZIndex)

                bottomFocusGradient
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)

                topControlsLayer(frames: headerFrames)
                    .opacity(RecordActiveHUDLayerLayout.topControlsOpacity(isExpanded: isExpandedHUDPresented))
                    .allowsHitTesting(!isExpandedHUDPresented)
                    .animation(.easeOut(duration: 0.18), value: isExpandedHUDPresented)
                    .zIndex(RecordActiveHUDLayerLayout.topBannerZIndex)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button { isCoachSettingsPresented = true } label: {
                            Label(coach.preferences.enabled ? "음성 안내 · 켜짐" : "음성 안내 · 꺼짐", systemImage: "speaker.wave.2")
                                .font(.caption.weight(.semibold)).padding(.horizontal, 12)
                                .frame(minHeight: 44).background(SOOMColor.surface, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).accessibilityIdentifier("coach.readySettings")
                        Button { isManualWorkoutPresented = true } label: {
                            Label("마친 운동 직접 입력", soomIcon: "plus")
                                .font(.caption.weight(.semibold)).padding(.horizontal, 12)
                                .frame(minHeight: 44).background(SOOMColor.surface, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).accessibilityIdentifier("record.manualWorkout")
                    }
                    .foregroundStyle(SOOMColor.ink).padding(.horizontal, 20)
                    readyLaunchControl(safeAreaInsets: proxy.safeAreaInsets)
                }
                .opacity(activeSession == nil ? 1 : 0)
                .allowsHitTesting(activeSession == nil)
                .accessibilityHidden(activeSession != nil)
                .zIndex(RecordActiveHUDLayerLayout.readyControlZIndex)

                if let activeSession {
                    activeWorkoutOverlay(
                        session: activeSession,
                        safeAreaInsets: proxy.safeAreaInsets
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(RecordActiveHUDLayerLayout.hudZIndex(for: activeHUDMode))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isTapStartPresented) {
            tapStartSheet
        }
        .sheet(isPresented: $isCoachSettingsPresented) {
            WorkoutCoachSettingsView(coach: coach, session: activeSession)
        }
        .confirmationDialog("운동을 마칠까요?", isPresented: $isFinishConfirmationPresented, titleVisibility: .visible) {
            Button("운동 종료") {
                guard let session = activeSession else { return }
                activeHUDMode = .expanded
                activeSession = session.finished(at: Date())
            }
            Button("계속 쉬기", role: .cancel) { }
        } message: { Text("종료 후 기록을 확인하고 저장할 수 있어요.") }
        .confirmationDialog("진행 중 기록을 취소할까요?", isPresented: $isCancelConfirmationPresented, titleVisibility: .visible) {
            Button("기록 취소", role: .destructive) {
                guard clearCheckpoint() else { return }
                coach.stop(); resetFinishedShareState(); activeHUDMode = .defaultMode; activeSession = nil
            }
            Button("운동 유지", role: .cancel) { }
        }
        .sheet(isPresented: $isWeatherDetailPresented) {
            weatherDetailSheet
        }
        .sheet(isPresented: $isRouteRecommendationPresented) {
            routeRecommendationSheet
        }
        .sheet(isPresented: $isManualWorkoutPresented) {
            ManualWorkoutEntryView { _ in
                if let onSaveComplete { onSaveComplete() } else { dismiss() }
            }
        }
        .sheet(isPresented: $isSourceReviewPresented) {
            NavigationStack {
                UnifiedWorkoutDuplicateReviewViewContainer()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { isSourceReviewPresented = false }
                        }
                    }
            }
        }
        .onChange(of: locationManager.state) { _, newState in
            guard newState.recenterTarget != nil else { return }
            recenterTrigger += 1
            Task {
                await fetchWeatherIfPossible(for: newState)
            }
        }
        .onReceive(locationManager.$recordingUpdates) { fixes in
            recordLocationsIfNeeded(fixes)
        }
        .onChange(of: activeSession?.state) { _, state in
            locationManager.setRecording(state == .active && checkpointScopeID == accountStorage.scopeID)
            updateCoach()
            persistCheckpoint(force: true)
            publishLiveWorkout(force: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { persistCheckpoint(force: true) }
            if phase == .active {
                locationManager.refreshAuthorization()
                publishLiveWorkout(force: true)
            }
        }
        .onChange(of: accountStorage.scopeID) { _, _ in
            suspendRecordingForDeparture()
        }
        .onDisappear { suspendRecordingForDeparture() }
        .task {
            await restoreCheckpoint()
        }
        .task {
            await fetchWeatherIfPossible(for: locationManager.state)
        }
        .task {
            await loadRecoveryLabel()
        }
        .task(id: activeSession?.id) {
            guard activeSession != nil else { return }

            while !Task.isCancelled {
                currentDate = Date()
                updateCoach()
                publishLiveWorkout()
                persistCheckpoint(force: false)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onChange(of: readyInteractionState) { _, newState in
            handleReadyInteractionStateChange(newState)
        }
    }

    @MainActor
    private func updateCoach() {
        guard checkpointScopeID == accountStorage.scopeID else { coach.stop(); return }
        if let session = activeSession {
            coach.update(session: session, at: Date(), phoneOwnsRecording: WatchWorkoutCompanion.shared.workout == nil)
        } else { coach.stop() }
    }

    private func publishLiveWorkout(force: Bool = false) {
        guard !ReviewDemoMode.isActive else { return }
        guard checkpointScopeID == accountStorage.scopeID else { return }
        if let session = activeSession {
            WorkoutLiveActivityController.shared.submit(session.liveState(scope: accountStorage.scopeID, at: Date()), force: force)
            WatchWorkoutCompanion.shared.setPhoneRecording(session.state == .active || session.state == .paused)
        } else {
            WorkoutLiveActivityController.shared.clear()
            WatchWorkoutCompanion.shared.setPhoneRecording(false)
        }
    }

    private func topControlsLayer(frames: RecordMapHeaderFrames) -> some View {
        ZStack(alignment: .topLeading) {
            topGuidanceBanner
                .frame(width: frames.bannerFrame.width, height: frames.bannerFrame.height)
                .position(x: frames.bannerFrame.midX, y: frames.bannerFrame.midY)
                .zIndex(RecordActiveHUDLayerLayout.topBannerZIndex)

            closeButton
                .position(frames.backButtonCenter)
                .zIndex(RecordActiveHUDLayerLayout.rightControlsZIndex)

            rightEdgeControls
                .frame(width: frames.rightControlsFrame.width, height: frames.rightControlsFrame.height)
                .position(x: frames.rightControlsFrame.midX, y: frames.rightControlsFrame.midY)
                .zIndex(RecordActiveHUDLayerLayout.rightControlsZIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
    }

    private var closeButton: some View {
        Button {
            SOOMHaptics.selection()
            if let onDismiss {
                onDismiss()
            } else {
                dismiss()
            }
        } label: {
            Image(soom: "chevron.left")
                .font(.system(size: SOOMFont.Size.headline, weight: .bold))
                .foregroundStyle(SOOMColor.ink)
                .frame(width: 44, height: 44)
                .background(SOOMColor.surface.opacity(0.94))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(SOOMColor.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("돌아가기")
    }

    private var topGuidanceBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(soom: "sparkle")
                    .font(.system(size: SOOMFont.Size.caption, weight: .bold))
                    .foregroundStyle(SOOMColor.accent)
                Text("오늘의 출발 기준")
                    .font(SOOMFont.body(9, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.accentInk)
                    .textCase(.uppercase)
            }

            if checkpointLoadFailed {
                Text("이전 임시 기록을 불러오지 못했어요.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                Button("복원 다시 시도") {
                    checkpointStore = nil
                    checkpointLoadFailed = false
                    Task { await restoreCheckpoint() }
                }
                Button("이전 임시 기록 삭제", role: .destructive) { _ = clearCheckpoint() }
            }
            Text(recoveryLabel)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.accentInk)
                .lineLimit(1)

            Text(guidanceRecommendationText)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(RecordMapHeaderLayout.maxBodyLineCount)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SOOMLayout.Spacing.lg)
        .padding(.vertical, SOOMLayout.Spacing.sm)
        .frame(minHeight: RecordMapHeaderLayout.guidanceMinHeight, maxHeight: RecordMapHeaderLayout.guidanceMaxHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SOOMColor.surface.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: RecordMapHeaderLayout.guidanceCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RecordMapHeaderLayout.guidanceCornerRadius, style: .continuous)
                .stroke(SOOMColor.accentLine, lineWidth: 1)
        }
        .shadow(color: SOOMColor.ink.opacity(0.045), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("오늘의 출발 기준")
        .accessibilityValue("\(recoveryLabel). \(guidanceRecommendationText)")
    }

    private var rightEdgeControls: some View {
        VStack(spacing: RecordMapHeaderLayout.controlSpacing) {
            ForEach(RecordLaunchControl.rightEdgeOrder, id: \.self) { control in
                rightEdgeControl(control)
            }
        }
    }

    @ViewBuilder
    private func rightEdgeControl(_ control: RecordLaunchControl) -> some View {
        switch control {
        case .weather:
            weatherPill
        case .routeRecommendation:
            EmptyView()
        case .currentLocation:
            iconButton(
                icon: control.iconName,
                accessibilityLabel: "현재 위치로 돌아가기",
                action: {
                    locationManager.handleLocationButtonTap()
                    if locationManager.state.recenterTarget != nil {
                        recenterTrigger += 1
                    }
                    Task {
                        await fetchWeatherIfPossible(for: locationManager.state, forceRefresh: true)
                    }
                }
            )
        }
    }

    private var weatherPill: some View {
        Button {
            SOOMHaptics.selection()
            Task {
                await fetchWeatherIfPossible(for: locationManager.state, forceRefresh: true)
            }
            isWeatherDetailPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Image(soom: weatherSnapshot.conditionIconName)
                        .font(.system(size: SOOMFont.Size.subheadline, weight: .semibold))
                        .foregroundStyle(weatherIconTint)

                    Text(weatherSnapshot.temperatureText)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.ink)
                        .monospacedDigit()
                }
                .frame(width: RecordMapHeaderLayout.controlSize, height: RecordMapHeaderLayout.controlSize)
                .background(SOOMColor.surface.opacity(0.94))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(SOOMColor.line.opacity(0.86), lineWidth: 1)
                }
                .shadow(color: SOOMColor.ink.opacity(0.05), radius: 9, x: 0, y: 5)

                if isFetchingWeather {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(SOOMColor.secondaryInk)
                        .offset(x: 4, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("날씨")
        .accessibilityValue(weatherSnapshot.pillText)
    }

    private var bottomFocusGradient: some View {
        RecordBreathingBottomWaveView(
            progress: bottomWaveProgress,
            opacity: bottomWaveOpacity,
            yOffset: bottomWaveOffset,
            isInteracting: readyInteractionState.weakensWave
        )
        .onAppear(perform: startBottomGradientBreathingIfNeeded)
        .onChange(of: reduceMotion) { _, _ in
            startBottomGradientBreathingIfNeeded()
        }
    }

    private var bottomWaveProgress: CGFloat {
        if readyInteractionState.weakensWave {
            return RecordBreathingBottomWaveLayout.interactionProgress
        }

        if reduceMotion {
            return RecordBreathingBottomWaveLayout.reducedMotionProgress
        }

        return isBottomGradientBreathing
            ? RecordBreathingBottomWaveLayout.exhaleProgress
            : RecordBreathingBottomWaveLayout.inhaleProgress
    }

    private var bottomWaveOpacity: Double {
        if readyInteractionState.weakensWave {
            return RecordBreathingBottomWaveLayout.interactionOpacity
        }

        if reduceMotion {
            return RecordBreathingBottomWaveLayout.reducedMotionOpacity
        }

        return isBottomGradientBreathing
            ? RecordBreathingBottomWaveLayout.exhaleOpacity
            : RecordBreathingBottomWaveLayout.inhaleOpacity
    }

    private var bottomWaveOffset: CGFloat {
        if readyInteractionState.weakensWave {
            return RecordBreathingBottomWaveLayout.interactionYOffset
        }

        if reduceMotion {
            return RecordBreathingBottomWaveLayout.reducedMotionYOffset
        }

        return isBottomGradientBreathing
            ? RecordBreathingBottomWaveLayout.exhaleYOffset
            : RecordBreathingBottomWaveLayout.inhaleYOffset
    }

    private func startBottomGradientBreathingIfNeeded() {
        if reduceMotion {
            isBottomGradientBreathing = false
            return
        }

        guard !isBottomGradientBreathing else { return }
        withAnimation(
            .easeInOut(duration: RecordBreathingBottomWaveLayout.breathingDuration)
                .repeatForever(autoreverses: true)
        ) {
            isBottomGradientBreathing = true
        }
    }

    @MainActor
    private func pauseBottomGradientBreathingForInteraction() {
        guard !reduceMotion else {
            isBottomGradientBreathing = false
            return
        }

        withAnimation(.easeOut(duration: RecordBreathingBottomWaveLayout.transitionDuration)) {
            isBottomGradientBreathing = false
        }
    }

    @MainActor
    private func restartBottomGradientBreathing() {
        guard !reduceMotion else {
            isBottomGradientBreathing = false
            return
        }

        isBottomGradientBreathing = false
        Task { @MainActor in
            await Task.yield()
            startBottomGradientBreathingIfNeeded()
        }
    }

    @MainActor
    private func handleReadyInteractionStateChange(_ state: RecordReadyWaveInteractionState) {
        if state.weakensWave {
            pauseBottomGradientBreathingForInteraction()
        } else if state.restoresBreathing {
            restartBottomGradientBreathing()
        }
    }

    private var readyStartTitle: String {
        if let hoveredSport { return "손을 놓으면 \(hoveredSport.title) 시작" }
        if isReadyFocusMode { return "종목 쪽으로 조금 더" }
        if readyInteractionState == .cancelled { return "시작하지 않았어요" }
        return "누른 채 위로 밀어보세요"
    }

    private var readyStartHint: String {
        if hoveredSport != nil { return "취소하려면 아래 원으로 돌아오세요" }
        if isReadyFocusMode { return "종목 영역에 닿을 때까지 밀어주세요" }
        if readyInteractionState == .cancelled { return "다시 시도할 수 있어요" }
        return "종목 위에서 놓으면 시작돼요"
    }

    private func readyLaunchControl(safeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 8) {
            if isWatchStartBlocked {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "applewatch").font(.title)
                    Text("Apple Watch에서 운동 중이에요").font(SOOMFont.body(22, weight: .bold, relativeTo: .title2))
                    Text("워치 운동을 종료한 후 다시 시작해 주세요.").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    readyActionButton("준비 화면으로 돌아가기", identifier: "record.watchBack", primary: false) { isWatchStartBlocked = false }
                }
                .padding(24).background(SOOMColor.surface, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(SOOMColor.accent.opacity(0.22)))
                .padding(.horizontal, 20)
            } else {
                if locationManager.state.authorization == .denied || locationManager.state.authorization == .restricted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("위치 권한 없이도 시작할 수 있어요").font(.subheadline.bold())
                        Text("경로는 기록되지 않아요. 위치 설정은 나중에 바꿀 수 있어요.").font(.caption)
                    }
                    .foregroundStyle(SOOMColor.ink).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).background(SOOMColor.surface, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20).accessibilityIdentifier("record.locationOptional")
                }
                if let checkpointMessage, activeSession == nil {
                    Text(checkpointMessage).font(.caption).foregroundStyle(SOOMColor.ink).padding(.horizontal, 20)
                }
                Text(readyStartTitle)
                    .font(SOOMFont.body(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(hoveredSport == nil ? SOOMColor.ink : SOOMColor.accent)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("record.startInstruction")
                Text(readyStartHint).font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("record.startHint")
                GeometryReader { geometry in
                    let readyCenter = CGPoint(x: geometry.size.width / 2,
                        y: geometry.size.height - RecordReadyLaunchVisualLayout.buttonCenterBottomOffset)
                    ZStack {
                        Path { path in
                            path.move(to: CGPoint(x: readyCenter.x, y: readyCenter.y - 58))
                            path.addLine(to: CGPoint(x: readyCenter.x, y: readyCenter.y - 128))
                        }
                        .stroke(SOOMColor.accent.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 5]))
                        .allowsHitTesting(false)
                        Image(systemName: "chevron.up").font(.caption.bold()).foregroundStyle(SOOMColor.accent)
                            .position(x: readyCenter.x, y: readyCenter.y - 76).allowsHitTesting(false)
                        if isReadyFocusMode, let point = readyVisualDragLocation(center: readyCenter) {
                            Path { path in path.move(to: readyCenter); path.addLine(to: point) }
                                .stroke(SOOMColor.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .allowsHitTesting(false)
                            Circle().fill(SOOMColor.accent).frame(width: 20, height: 20)
                                .position(point).allowsHitTesting(false)
                        }
                        ForEach(RecordReadyRadialLayout.items(center: readyCenter), id: \.sport.rawValue) { item in
                            radialSportButton(item: item, readyCenter: readyCenter)
                                .position(item.center).allowsHitTesting(false)
                        }
                        readyButtonSurface(for: selectedSport)
                            .contentShape(Circle())
                            .gesture(readyDragGesture(readyCenter: readyCenter))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("운동 시작, \(selectedSport.title)")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("탭으로 시작 화면에서 종목을 선택하고 시작을 확인하세요.")
                            .accessibilityIdentifier("record.startCircle")
                            .accessibilityAction { isTapStartPresented = true }
                            .offset(y: readyCenter.y - geometry.size.height / 2)
                        Text(hoveredSport == nil ? "시작" : "아래 원으로 돌아오면 취소")
                            .font(.caption.bold()).foregroundStyle(SOOMColor.secondaryInk)
                            .position(x: readyCenter.x, y: readyCenter.y + 60).allowsHitTesting(false)
                    }
                    .coordinateSpace(name: RecordReadyLaunchVisualLayout.coordinateSpaceName)
                    #if DEBUG && targetEnvironment(simulator)
                    .onAppear {
                        guard ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1" else { return }
                        switch ProcessInfo.processInfo.environment["SOOM_RECORD_START_REVIEW_STATE"] {
                        case "armed":
                            isReadyFocusMode = true; readyInteractionState = .dragging; hoveredSport = .running
                            readyDragLocation = RecordReadyRadialLayout.items(center: readyCenter).first { $0.sport == .running }?.center
                        case "dragging":
                            isReadyFocusMode = true; readyInteractionState = .dragging
                            readyDragLocation = CGPoint(x: readyCenter.x, y: readyCenter.y - 80)
                        default: break
                        }
                    }
                    #endif
                }
                .frame(height: RecordReadyLaunchVisualLayout.containerHeight)
                Button { isTapStartPresented = true } label: {
                    Text("탭으로 시작하기").font(.footnote.bold()).foregroundStyle(SOOMColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("record.tapStart")
            }
        }
        .padding(.top, 18)
        .padding(.bottom, max(safeAreaInsets.bottom, 8))
    }

    private func readyVisualDragLocation(center: CGPoint) -> CGPoint? {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1" {
            switch ProcessInfo.processInfo.environment["SOOM_RECORD_START_REVIEW_STATE"] {
            case "armed": return RecordReadyRadialLayout.items(center: center).first { $0.sport == .running }?.center
            case "dragging": return CGPoint(x: center.x, y: center.y - 80)
            default: break
            }
        }
        #endif
        return readyDragLocation
    }

    private var tapStartSheet: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("탭으로 시작").font(SOOMFont.body(22, weight: .bold, relativeTo: .title2))
            Text("종목을 선택한 다음 시작을 눌러주세요.").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            Picker("종목", selection: $selectedSport) {
                ForEach(RecordSportMode.allCases) { sport in Text(sport.title).tag(sport) }
            }.pickerStyle(.segmented).accessibilityIdentifier("record.tapSport")
            readyActionButton(selectedSport.startTitle, identifier: "record.tapConfirm", primary: true) {
                isTapStartPresented = false
                startWorkout(with: selectedSport)
            }
            readyActionButton("돌아가기", identifier: "record.tapCancel", primary: false) { isTapStartPresented = false }

        }
        .padding(24)
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func readyActionButton(_ title: String, identifier: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundStyle(primary ? SOOMColor.white : SOOMColor.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(primary ? SOOMColor.ink : SOOMColor.background, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }

    private func readyDragGesture(readyCenter: CGPoint) -> some Gesture {
        DragGesture(
            minimumDistance: RecordReadyRadialLayout.touchRevealMinimumDistance,
            coordinateSpace: .named(RecordReadyLaunchVisualLayout.coordinateSpaceName)
        )
        .onChanged { value in
            guard isReadyFocusMode || RecordReadyRadialInteraction.isTouchInsideReadyButton(
                location: value.startLocation,
                readyCenter: readyCenter
            ) else {
                return
            }

            if !isReadyFocusMode {
                beginReadyRadialSelection()
            }
            updateHoveredSport(at: value.location, readyCenter: readyCenter)
        }
        .onEnded { value in
            guard isReadyFocusMode else { return }
            updateHoveredSport(at: value.location, readyCenter: readyCenter)
            finishReadyRadialSelection()
        }
    }

    private func readyButtonSurface(for sport: RecordSportMode) -> some View {
        Image(soom: RecordReadyLaunchVisualLayout.primaryIconName)
            .font(.system(size: RecordReadyLaunchVisualLayout.playIconSize, weight: .black))
            .symbolRenderingMode(.hierarchical)
            .offset(x: 2)
        .foregroundStyle(SOOMColor.white.opacity(0.92))
        .frame(
            width: RecordReadyLaunchVisualLayout.buttonDiameter,
            height: RecordReadyLaunchVisualLayout.buttonDiameter
        )
        .background(
            Circle()
                .fill(SOOMColor.ink)
                .overlay {
                    readyBreathingRing
                }
                .overlay {
                    Circle()
                        .stroke(SOOMColor.white.opacity(0.18), lineWidth: 1.2)
                        .padding(SOOMLayout.Spacing.sm)
                }
        )
        .scaleEffect(isReadyFocusMode ? 0.96 : 1.0)
        .shadow(
            color: SOOMColor.ink.opacity(
                isReadyFocusMode
                    ? RecordReadyLaunchVisualLayout.focusedShadowOpacity
                    : RecordReadyLaunchVisualLayout.defaultShadowOpacity
            ),
            radius: isReadyFocusMode
                ? RecordReadyLaunchVisualLayout.focusedShadowRadius
                : RecordReadyLaunchVisualLayout.defaultShadowRadius,
            x: 0,
            y: RecordReadyLaunchVisualLayout.shadowYOffset
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isReadyFocusMode)
    }

    private var readyBreathingRing: some View {
        let isBreathing = isBottomGradientBreathing && !reduceMotion && !isReadyFocusMode
        let opacity: Double
        if reduceMotion {
            opacity = RecordReadyLaunchVisualLayout.ringMinOpacity
        } else if isReadyFocusMode {
            opacity = RecordReadyLaunchVisualLayout.focusedRingOpacity
        } else {
            opacity = isBreathing
                ? RecordReadyLaunchVisualLayout.ringMaxOpacity
                : RecordReadyLaunchVisualLayout.ringMinOpacity
        }

        let scale: CGFloat
        if reduceMotion || isReadyFocusMode {
            scale = RecordReadyLaunchVisualLayout.ringMinScale
        } else {
            scale = isBreathing
                ? RecordReadyLaunchVisualLayout.ringMaxScale
                : RecordReadyLaunchVisualLayout.ringMinScale
        }

        return Circle()
            .stroke(SOOMColor.white.opacity(opacity), lineWidth: RecordReadyLaunchVisualLayout.ringLineWidth)
            .scaleEffect(scale)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: RecordReadyLaunchVisualLayout.ringDuration)
                        .repeatForever(autoreverses: true),
                value: isBottomGradientBreathing
            )
    }

    private func radialSportButton(item: RecordReadyRadialItem, readyCenter: CGPoint) -> some View {
        let isHovered = hoveredSport == item.sport

        return VStack(spacing: 5) {
            Group {
                if isHovered { Image(systemName: "checkmark").font(.title2.bold()) }
                else { SOOMSportIconView(name: item.sport.iconName, size: 24) }
            }
            Text(item.sport.title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
        }
        .foregroundStyle(isHovered ? SOOMColor.white : SOOMColor.ink)
        .frame(width: 68, height: 68)
        .background(isHovered ? SOOMColor.accent : SOOMColor.surface.opacity(0.96))
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(isHovered ? SOOMColor.white.opacity(0.72) : SOOMColor.line.opacity(0.9), lineWidth: 1)
        }
        .overlay { if isHovered { Circle().stroke(SOOMColor.accent, lineWidth: 2).padding(-6) } }
        .accessibilityIdentifier("record.target.\(item.sport.rawValue)")
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: isHovered)
        .accessibilityHidden(!RecordReadyRadialLayout.isAboveReadyCenter(item: item, readyCenter: readyCenter))
    }

    @MainActor
    private func beginReadyRadialSelection() {
        guard !isReadyFocusMode else { return }

        RecordReadyRadialInteraction.begin().forEach(playReadyHaptic)
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            readyResetID = UUID()
            hoveredSport = nil
            readyDragLocation = nil
            readyInteractionState = .revealing
            isReadyFocusMode = true
        }
    }

    @MainActor
    private func updateHoveredSport(at location: CGPoint, readyCenter: CGPoint) {
        if isReadyFocusMode, readyInteractionState == .revealing {
            readyInteractionState = .dragging
        }
        readyDragLocation = location
        let nextSport = RecordReadyRadialLayout.hoveredSport(at: location, readyCenter: readyCenter)
        let events = RecordReadyRadialInteraction.hoverEvents(previous: hoveredSport, next: nextSport)
        hoveredSport = nextSport
        events.forEach(playReadyHaptic)
    }

    @MainActor
    private func finishReadyRadialSelection() {
        let wasSelecting = isReadyFocusMode
        let sportToStart = hoveredSport
        let shouldStart = RecordReadyRadialInteraction.shouldStartWorkout(
            isRadialSelectionActive: wasSelecting,
            hoveredSport: sportToStart
        )

        RecordReadyRadialInteraction.release(hoveredSport: sportToStart).forEach(playReadyHaptic)
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            isReadyFocusMode = false
            hoveredSport = nil
            readyDragLocation = nil
            readyInteractionState = shouldStart ? .confirmed : .cancelled
        }

        restoreReadyInteractionToIdle()

        if shouldStart, let sportToStart {
            selectedSport = sportToStart
            startWorkout(with: sportToStart)
        }
    }

    @MainActor
    private func restoreReadyInteractionToIdle() {
        let resetID = readyResetID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard resetID == readyResetID, !isReadyFocusMode else { return }
            readyInteractionState = .idle
        }
    }

    private func playReadyHaptic(_ event: RecordReadyRadialHapticEvent) {
        switch event {
        case .longPressStarted, .releaseConfirmed:
            SOOMHaptics.softImpact()
        case .menuRevealed, .hoverChanged:
            SOOMHaptics.selection()
        case .releaseCancelled:
            SOOMHaptics.typingTick()
        }
    }

    @MainActor
    private func startWorkout(with sport: RecordSportMode) {
        var watchActive = WatchWorkoutCompanion.shared.workout != nil
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
           ProcessInfo.processInfo.environment["SOOM_RECORD_START_REVIEW_STATE"] == "watch" { watchActive = true }
        #endif
        switch RecordStartEligibility.evaluate(hasActiveSession: activeSession != nil,
            watchWorkoutActive: watchActive,
            storageReady: checkpointScopeID == accountStorage.scopeID && !checkpointLoadFailed) {
        case .alreadyRecording: return
        case .watchActive: isWatchStartBlocked = true; return
        case .storageNotReady:
            checkpointMessage = "기록 저장소를 준비하고 있어요. 잠시 후 다시 시작해 주세요."
            return
        case .ready: break
        }
        isWatchStartBlocked = false
        checkpointMessage = nil
        currentDate = Date()
        SOOMHaptics.softImpact()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            resetFinishedShareState()
            activeHUDMode = .defaultMode
            activeSession = sessionStarter.start(
                sport: sport,
                locationState: locationManager.state
            )
        }
    }

    private var weatherDetailSheet: some View {
        let detail = weatherDetailSnapshot

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.locationName)
                            .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                        Text("현재 날씨")
                            .font(SOOMFont.displayMedium(24, relativeTo: .title2))
                            .foregroundStyle(SOOMColor.ink)
                    }

                    Spacer(minLength: 0)

                    Button {
                        SOOMHaptics.selection()
                        isWeatherDetailPresented = false
                    } label: {
                        Image(soom: "xmark")
                            .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .frame(width: 34, height: 34)
                            .background(SOOMColor.background)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("날씨 닫기")
                }

                HStack(alignment: .center, spacing: 16) {
                    Image(soom: detail.conditionIconName)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(weatherIconTint)
                    Text(detail.temperatureText)
                        .font(SOOMFont.displayMedium(46, relativeTo: .largeTitle))
                        .foregroundStyle(SOOMColor.ink)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.conditionText)
                            .font(SOOMFont.body(16, weight: .bold, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink)
                        Text("체감 \(detail.feelsLikeText) · \(detail.windText)")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    weatherDetailMetric(title: "바람", value: detail.windText, icon: "wind")
                    airQualityMetric(title: "미세", value: detail.fineDustText, level: detail.airQuality.pm10Level)
                    airQualityMetric(title: "초미세", value: detail.ultraFineDustText, level: detail.airQuality.pm25Level)
                }

                weatherGuideCard(for: detail)
                hourlyForecastSection(detail.hourlyForecasts)
                dailyForecastSection(detail.dailyForecasts)

                if detail.isFallback {
                    Text(weatherSnapshot.isFallback
                         ? "위치 권한과 네트워크 연결을 확인해 주세요."
                         : "일부 상세 날씨 정보를 확인할 수 없어요. 확인된 현재 날씨만 표시해요.")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
        }
        .background(SOOMColor.surface)
        .presentationDetents([.height(RecordFixedSheetLayout.weatherHeight)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false)
    }

    private var routeRecommendationSheet: some View {
        let options = RecordRouteCatalogOption.availableOptions(for: selectedSport)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("추천 코스")
                            .font(SOOMFont.displayMedium(24, relativeTo: .title2))
                            .foregroundStyle(SOOMColor.ink)
                        Text("이용할 수 있는 추천 코스를 확인해요.")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button {
                        SOOMHaptics.selection()
                        isRouteRecommendationPresented = false
                    } label: {
                        Image(soom: "xmark")
                            .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .frame(width: 34, height: 34)
                            .background(SOOMColor.background)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("추천 코스 닫기")
                }

                if options.isEmpty {
                    ContentUnavailableView(
                        RecordRouteCatalogOption.emptyStateTitle,
                        soomIcon: "map",
                        description: Text(RecordRouteCatalogOption.emptyStateMessage)
                    )
                } else {
                    ForEach(options) { option in
                        routeCatalogRow(option)
                    }
                }
            }
            .padding(22)
        }
        .background(SOOMColor.surface)
        .presentationDetents([.height(RecordFixedSheetLayout.routeRecommendationHeight)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false)
    }

    private func weatherDetailMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(soom: icon)
                .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                .foregroundStyle(SOOMColor.accent)
            Text(value)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(title)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.background)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.medium, style: .continuous))
    }

    private func airQualityMetric(title: String, value: String, level: RecordAirQualityLevel) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(soom: title == "미세" ? "aqi.medium" : "circle.hexagongrid.fill")
                .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                .foregroundStyle(airQualityColor(level))
            Text(value)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(airQualityColor(level).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.medium, style: .continuous)
                .stroke(airQualityColor(level).opacity(0.22), lineWidth: 1)
        }
    }

    private func weatherGuideCard(for detail: RecordWeatherDetailSnapshot) -> some View {
        let text = weatherGuideText(for: detail)

        return HStack(alignment: .top, spacing: 10) {
            Image(soom: "sparkle")
                .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 26, height: 26)
                .background(SOOMColor.accentSurface)
                .clipShape(Circle())

            Text(text)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SOOMLayout.Spacing.lg)
        .background(SOOMColor.background)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.pill, style: .continuous))
    }

    private func hourlyForecastSection(_ forecasts: [RecordHourlyWeather]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("시간별")
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)

            if forecasts.isEmpty {
                Text("시간별 예보를 확인할 수 없어요.")
                    .font(SOOMFont.body(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(forecasts) { forecast in
                        VStack(spacing: 8) {
                            Text(forecast.timeLabel)
                                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                                .foregroundStyle(SOOMColor.tertiaryInk)
                            Image(soom: forecast.iconName)
                                .font(.system(size: SOOMFont.Size.body, weight: .bold))
                                .foregroundStyle(SOOMColor.accent)
                            Text(forecast.temperatureText)
                                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                                .foregroundStyle(SOOMColor.ink)
                        }
                        .frame(width: 64)
                        .padding(.vertical, SOOMLayout.Spacing.md)
                        .background(SOOMColor.background)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.pill, style: .continuous))
                    }
                }
            }
        }
    }

    private func dailyForecastSection(_ forecasts: [RecordDailyWeather]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("일별")
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)

            if forecasts.isEmpty {
                Text("일별 예보를 확인할 수 없어요.")
                    .font(SOOMFont.body(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }

            VStack(spacing: 8) {
                ForEach(forecasts) { forecast in
                    HStack(spacing: 12) {
                        Text(forecast.dayLabel)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.ink)
                            .frame(width: 44, alignment: .leading)
                        Image(soom: forecast.iconName)
                            .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                            .foregroundStyle(SOOMColor.accent)
                            .frame(width: 24)
                        Text(forecast.conditionLabel)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                        Spacer(minLength: 0)
                        Text(forecast.rangeText)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.ink)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, SOOMLayout.Spacing.md)
                    .padding(.vertical, SOOMLayout.Spacing.md)
                    .background(SOOMColor.background)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.medium, style: .continuous))
                }
            }
        }
    }

    private func airQualityColor(_ level: RecordAirQualityLevel) -> Color {
        switch level {
        case .unknown:
            return SOOMColor.secondaryInk
        case .good:
            return SOOMColor.blue
        case .moderate:
            return SOOMColor.recovery
        case .bad:
            return SOOMColor.warning
        case .veryBad:
            return Color.red
        }
    }

    private func weatherGuideText(for detail: RecordWeatherDetailSnapshot) -> String {
        guard !weatherSnapshot.isFallback else { return RecordWeatherRecommendationCopy.unavailableGuidance }
        if detail.airQuality.pm10Level == .bad || detail.airQuality.pm10Level == .veryBad ||
            detail.airQuality.pm25Level == .bad || detail.airQuality.pm25Level == .veryBad {
            return "미세먼지가 높을 땐 강도를 낮추고 호흡이 편한 코스로 시작해요."
        }

        switch weatherSnapshot.condition {
        case .rain, .snow, .storm:
            return "노면이 미끄러울 수 있어요. 오늘은 짧게 움직이고 안전을 먼저 봐요."
        case .clear where (weatherSnapshot.temperatureCelsius ?? 0) >= 28:
            return "햇볕이 강한 날엔 물을 먼저 챙기고 초반 페이스를 낮춰요."
        case .unknown:
            return RecordWeatherRecommendationCopy.unavailableGuidance
        case .clear, .cloudy:
            return "현재 날씨와 주변 환경을 함께 확인하고 편안한 강도로 시작해요."
        }
    }

    private func routeCatalogRow(_ option: RecordRouteCatalogOption) -> some View {
        let isSelected = option.route.title == selectedRoute.title

        return Button {
            SOOMHaptics.softImpact()
            selectedRoute = option.route
            isRouteRecommendationPresented = false
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? SOOMColor.accentSurface : SOOMColor.background)
                        .frame(width: 48, height: 48)
                    Image(soom: RecordLaunchControl.routeRecommendation.iconName)
                        .font(.system(size: SOOMFont.Size.body, weight: .bold))
                        .foregroundStyle(isSelected ? SOOMColor.accent : SOOMColor.secondaryInk)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(option.route.title)
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink)
                            .lineLimit(1)
                        Text(option.tag)
                            .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(SOOMColor.accentInk)
                            .padding(.horizontal, SOOMLayout.Spacing.sm)
                            .padding(.vertical, SOOMLayout.Spacing.xs)
                            .background(SOOMColor.accentSurface)
                            .clipShape(Capsule())
                    }

                    Text("\(option.route.distanceText) · \(option.route.durationText) · \(option.route.reason)")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(soom: "checkmark.circle.fill")
                        .font(.system(size: SOOMFont.Size.headline, weight: .bold))
                        .foregroundStyle(SOOMColor.accent)
                }
            }
            .padding(SOOMLayout.Spacing.lg)
            .background(SOOMColor.background)
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.pill, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SOOMRadius.pill, style: .continuous)
                    .stroke(isSelected ? SOOMColor.accentLine : SOOMColor.line.opacity(0.82), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func activeWorkoutOverlay(session: RecordWorkoutSession, safeAreaInsets: EdgeInsets) -> some View {
        let hud = RecordActiveHUDLayout.make(session: session, referenceDate: currentDate)
        let fresh = session.lastLocationTimestamp.map { (-5...15).contains(currentDate.timeIntervalSince($0)) } ?? false
        return VStack {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(session.state == .finished && savedWorkoutForShare != nil ? "저장 완료" : session.statusLabel)
                                .font(.headline)
                            Spacer()
                            Text(session.sport.title).font(.subheadline)
                        }
                        if session.state == .finished {
                            activeHUDPrimaryMetric(hud.primaryMetric)
                            finishedSummaryContent(for: session)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hud.primaryMetric.label).font(.caption).foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline) {
                                    Text(fresh && session.state == .active ? hud.primaryMetric.value : "—")
                                        .font(.system(size: 56, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                                    Text(hud.primaryMetric.unit ?? "").font(.body)
                                }
                            }.accessibilityElement(children: .combine)
                            Divider()
                            HStack(spacing: 20) {
                                VStack(alignment: .leading) {
                                    Text("거리").font(.caption).foregroundStyle(.secondary)
                                    Text(String(format: "%.2f km", session.accumulatedDistanceMeters / 1000)).font(.title2.weight(.semibold))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading) {
                                    Text("운동 시간").font(.caption).foregroundStyle(.secondary)
                                    Text(hud.elapsed.value).font(.title2.weight(.semibold))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.accessibilityElement(children: .combine)
                        }
                        WorkoutCoachStrip(coach: coach, session: session, openSettings: { isCoachSettingsPresented = true }, now: currentDate)
                    }
                    .padding(18)
                }
                .frame(maxHeight: session.state == .finished ? 500 : 380)
                .background(SOOMColor.surfacePrimary.opacity(0.98), in: RoundedRectangle(cornerRadius: 24))
                if session.state != .finished { activeSessionActions(for: session) }
            }
            .padding(.horizontal, SOOMLayout.Spacing.lg)
            .padding(.bottom, max(safeAreaInsets.bottom, 16) + 14)
        }
    }

    private func activeHUDCard<Content: View>(
        mode: RecordActiveHUDMode,
        sessionState: RecordWorkoutSessionState,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isCompact = mode == .compact && sessionState != .finished

        return VStack(spacing: isCompact ? 10 : 16) {
            content()
        }
        .padding(.horizontal, isCompact ? 14 : 18)
        .padding(.top, isCompact ? 10 : 16)
        .padding(.bottom, isCompact ? 14 : 18)
        .frame(maxWidth: isCompact ? RecordActiveHUDVisualLayout.compactMaxWidth : .infinity)
        .background(SOOMColor.surfacePrimary.opacity(isCompact ? 0.96 : 0.98))
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 22 : 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isCompact ? 22 : 24, style: .continuous)
                .stroke(SOOMColor.line.opacity(isCompact ? 0.78 : 0.9), lineWidth: 1)
        }
        .shadow(
            color: SOOMColor.ink.opacity(isCompact ? 0.16 : 0.14),
            radius: isCompact ? 24 : 28,
            x: 0,
            y: isCompact ? 12 : 16
        )
        .zIndex(1)
    }

    private func compactActiveHUDContent(
        session: RecordWorkoutSession,
        hud: RecordActiveHUDLayout
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                activeHUDCenteredMetric(
                    hud.elapsed,
                    valueSize: 50,
                    unitSize: 14,
                    labelFirst: false
                )

                activeHUDCenteredMetric(
                    hud.primaryMetric,
                    valueSize: 46,
                    unitSize: 14,
                    labelFirst: true
                )
            }
            .padding(.top, SOOMLayout.Spacing.xs)
            .padding(.horizontal, 34)

            activeHUDModeButton(
                systemName: "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "운동 정보 펼치기"
            ) {
                SOOMHaptics.selection()
                activeHUDMode = RecordActiveHUDModeTransition.expand(from: activeHUDMode)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.sport.title) 기록 compact HUD")
        .accessibilityValue("\(hud.elapsed.label) \(hud.elapsed.value), \(hud.primaryMetric.label) \(hud.primaryMetric.value) \(hud.primaryMetric.unit ?? "")")
    }

    private func expandedActiveHUDContent(
        session: RecordWorkoutSession,
        hud: RecordActiveHUDLayout
    ) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                activeHUDSportStatusChip(session: session)

                Spacer(minLength: 0)

                activeHUDModeButton(
                    systemName: "arrow.down.right.and.arrow.up.left",
                    accessibilityLabel: "운동 정보 접기"
                ) {
                    SOOMHaptics.selection()
                    activeHUDMode = RecordActiveHUDModeTransition.collapse(from: activeHUDMode)
                }
            }

            activeHUDCenteredMetric(
                hud.elapsed,
                valueSize: 42,
                unitSize: 14,
                labelFirst: false
            )

            activeHUDPrimaryMetric(hud.primaryMetric)

            activeHUDMetricGrid(hud.secondaryMetrics)
        }
    }

    private func activeHUDModeButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(soom: systemName)
                .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 36, height: 36)
                .background(SOOMColor.accentSurface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func activeHUDSportStatusChip(session: RecordWorkoutSession) -> some View {
        HStack(spacing: 8) {
            SOOMSportIconView(name: session.sport.iconName, size: SOOMFont.Size.caption)
                .foregroundStyle(SOOMColor.accent)

            Text(session.sport.title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.textPrimary)

            Text(session.statusLabel)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(session.state == .paused ? SOOMColor.warning : SOOMColor.textSecondary)
                .padding(.horizontal, SOOMLayout.Spacing.sm)
                .padding(.vertical, SOOMLayout.Spacing.xs)
                .background((session.state == .paused ? SOOMColor.warning : SOOMColor.surfaceSecondary).opacity(session.state == .paused ? 0.12 : 1))
                .clipShape(Capsule())
        }
        .lineLimit(1)
    }

    private func activeHUDCenteredMetric(
        _ metric: RecordActiveHUDMetric,
        valueSize: CGFloat,
        unitSize: CGFloat,
        labelFirst: Bool
    ) -> some View {
        VStack(spacing: 5) {
            if labelFirst {
                Text(metric.label)
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.textSecondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(metric.value)
                    .font(SOOMFont.displayMedium(valueSize, relativeTo: .largeTitle))
                    .foregroundStyle(SOOMColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                if let unit = metric.unit {
                    Text(unit)
                        .font(SOOMFont.body(unitSize, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if !labelFirst {
                Text(metric.label)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func activeHUDHeader(
        session: RecordWorkoutSession,
        elapsed: RecordActiveHUDMetric
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(elapsed.value)
                    .font(SOOMFont.displayMedium(32, relativeTo: .title))
                    .foregroundStyle(SOOMColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(elapsed.label)
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.textSecondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 7) {
                    SOOMSportIconView(name: session.sport.iconName, size: SOOMFont.Size.caption)
                    Text(session.sport.title)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                }
                .foregroundStyle(SOOMColor.accent)

                Text(session.statusLabel)
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(session.state == .paused ? SOOMColor.warning : SOOMColor.textSecondary)
                    .padding(.horizontal, SOOMLayout.Spacing.sm)
                    .padding(.vertical, SOOMLayout.Spacing.xs)
                    .background((session.state == .paused ? SOOMColor.warning : SOOMColor.surfaceSecondary).opacity(session.state == .paused ? 0.12 : 1))
                    .clipShape(Capsule())
            }
        }
    }

    private func activeHUDPrimaryMetric(_ metric: RecordActiveHUDMetric) -> some View {
        VStack(spacing: 4) {
            Text(metric.label)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.textSecondary)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(metric.value)
                    .font(SOOMFont.displayMedium(58, relativeTo: .largeTitle))
                    .foregroundStyle(SOOMColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                if let unit = metric.unit {
                    Text(unit)
                        .font(SOOMFont.body(16, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SOOMLayout.Spacing.xs)
    }

    private func activeHUDMetricGrid(_ metrics: [RecordActiveHUDMetric]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                activeHUDMetricCard(metric)
            }
        }
    }

    private func activeHUDMetricCard(_ metric: RecordActiveHUDMetric) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(metric.label)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.textSecondary)
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(metric.value)
                    .font(SOOMFont.body(22, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let unit = metric.unit {
                    Text(unit)
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, SOOMLayout.Spacing.md)
        .padding(.vertical, SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.small, style: .continuous))
    }

    private func activeSessionActions(for session: RecordWorkoutSession) -> some View {
        HStack(spacing: 10) {
            Button {
                SOOMHaptics.selection()
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
                    activeSession = session.state == .paused ? session.resumed(at: Date()) : session.paused(at: Date())
                }
            } label: {
                Text(session.state == .paused ? "다시 시작" : "일시정지")
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .callout))
                    .foregroundStyle(SOOMColor.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(.vertical, SOOMLayout.Spacing.md)
                    .background(SOOMColor.background)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                SOOMHaptics.softImpact()
                isFinishConfirmationPresented = true
            } label: {
                Text("종료")
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .callout))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.md)
                    .background(SOOMColor.ink)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                SOOMHaptics.selection()
                isCancelConfirmationPresented = true
            } label: {
                Image(soom: "xmark")
                    .font(.system(size: SOOMFont.Size.subheadline, weight: .bold))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(width: 42, height: 42)
                    .background(SOOMColor.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("기록 취소")
        }
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfacePrimary.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.detailSheetTop, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.detailSheetTop, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: SOOMColor.ink.opacity(0.11), radius: 18, x: 0, y: 10)
        .zIndex(0)
    }

    private func finishedSummaryContent(for session: RecordWorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .overlay(SOOMColor.line.opacity(0.8))

            if let summary = RecordWorkoutSummaryBuilder.makeSummary(from: session) {
                VStack(alignment: .leading, spacing: 10) {
                    RecordFinishedSummaryMetrics(
                        startText: timeText(summary.startedAt), endText: timeText(summary.endedAt),
                        routeText: summary.capturedRoute ? (hasPendingRouteSave ? "경로 미저장" : savedWorkoutForShare == nil ? "경로 기록됨" : "경로 저장됨") : "시간 기록",
                        distanceText: summary.distanceText
                    )

                    Text(summaryStatusText)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let saveErrorMessage {
                    SOOMActionFeedback(title: "저장 상태 확인", message: saveErrorMessage, isError: true)
                }

                if let shareDraftErrorMessage {
                    SOOMActionFeedback(title: "공유하지 못했어요", message: shareDraftErrorMessage, isError: true)
                }

                if let shareOutcome {
                    Text(shareOutcome.postedRemotely
                         ? shareOutcome.summaryMessage
                         : "피드에 게시되지 않았어요. 공유 초안은 이 기기에만 저장됐어요.")
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(shareOutcome.postedRemotely ? SOOMColor.accent : SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let savedWorkoutForShare {
                    if hasPendingRouteSave {
                        Button(isSavingWorkout ? "경로 저장 중" : "경로 저장 다시 시도") {
                            Task { await saveFinishedSession(summary) }
                        }
                        .disabled(isSavingWorkout)
                    }
                    Text(ProfileOnlyPrivacyReleaseGate.productionReady ? "저장한 운동 요약은 프로필 공개범위에 따라 자동으로 반영돼요. 비공개 프로필의 운동은 서로 팔로우한 사람만 볼 수 있어요." : "저장한 운동은 본인 피드에도 자동으로 표시돼요. 다른 사람에게 보이는 범위는 계정 설정과 기존 공유 동의를 따라요.")
                        .font(.footnote)

                    HStack(spacing: 10) {
                        Button {
                            SOOMHaptics.softImpact()
                            finishSavedWorkoutFlow(shareCompleted: shareOutcome?.postedRemotely ?? false)
                        } label: {
                            Text(hasPendingRouteSave ? "경로 없이 완료" : "완료")
                                .font(SOOMFont.body(14, weight: .bold, relativeTo: .callout))
                                .foregroundStyle(SOOMColor.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SOOMLayout.Spacing.lg)
                                .background(SOOMColor.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isCreatingShareDraft || isSavingWorkout)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button {
                            SOOMHaptics.selection()
                            discardFinishedSession()
                        } label: {
                            Text("삭제")
                                .font(SOOMFont.body(14, weight: .bold, relativeTo: .callout))
                                .foregroundStyle(SOOMColor.secondaryInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SOOMLayout.Spacing.lg)
                                .background(SOOMColor.background)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSavingWorkout)

                        Button {
                            SOOMHaptics.softImpact()
                            Task {
                                await saveFinishedSession(summary)
                            }
                        } label: {
                            Text(isSavingWorkout ? "저장 중" : "저장")
                                .font(SOOMFont.body(14, weight: .bold, relativeTo: .callout))
                                .foregroundStyle(SOOMColor.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SOOMLayout.Spacing.lg)
                                .background(SOOMColor.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSavingWorkout)
                    }
                }
            } else {
                Button {
                    SOOMHaptics.selection()
                    discardFinishedSession()
                } label: {
                    Text("닫기")
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .callout))
                        .foregroundStyle(SOOMColor.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SOOMLayout.Spacing.lg)
                        .background(SOOMColor.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var summaryStatusText: String {
        if hasPendingRouteSave {
            return "운동 시간과 거리는 저장했지만 경로는 아직 저장하지 못했어요. 다시 시도하거나 경로 없이 완료할 수 있어요."
        }
        if savedWorkoutForShare == nil {
            return "저장하면 이 기기에 운동 기록이 남아요. 본인 피드에도 자동으로 표시돼요."
        }
        if isCreatingShareDraft {
            return "피드에 올리는 중이에요."
        }
        if shareOutcome != nil {
            return "운동 기록은 이 기기에 저장되어 있어요."
        }
        return "이 기기에 저장했어요. 저장한 운동은 본인 피드에도 자동으로 표시돼요."
    }

    @MainActor
    private func saveFinishedSession(_ summary: RecordWorkoutSummary) async {
        guard !isSavingWorkout else { return }

        isSavingWorkout = true
        saveErrorMessage = nil

        do {
            let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
            let routeStore = SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext)
            let saver = RecordWorkoutSaver(store: store, routeStore: routeStore,
                saveTelemetry: { try WorkoutTelemetryStore(modelContext: modelContext).save($0) })
            let workout = try await saver.save(summary)
            isSavingWorkout = false
            savedWorkoutForShare = workout
            hasPendingRouteSave = false
            coach.saved(at: Date())
            shareOutcome = nil
            shareDraftErrorMessage = nil
            // Preserve the stored preference. A legacy followers preference
            // currently has private visibility, as enforced by the feed API.
            selectedShareVisibility = accountStorage.defaultWorkoutAudience.shareableVisibility
        } catch RecordWorkoutSaveError.routeNotSaved(let workout, _) {
            isSavingWorkout = false
            savedWorkoutForShare = workout
            hasPendingRouteSave = true
            saveErrorMessage = "운동 기록은 저장됐어요. 경로 저장에 실패해 경로를 보관 중입니다."
            persistCheckpoint(force: true)
        } catch {
            isSavingWorkout = false
            saveErrorMessage = "저장하지 못했어요. 입력한 기록을 유지하고 있으니 다시 시도해 주세요."
        }
    }

    /// Called only by the explicit share button after local save succeeds.
    /// Keep the actual result visible until the user taps Done.
    @MainActor
    private func shareSavedWorkoutToFeed(_ workout: UnifiedWorkout) {
        guard ImportedWorkoutPublication.usesLegacyPublication else { return }
        guard !isCreatingShareDraft, shareOutcome == nil,
              let scope = checkpointScopeID, scope == accountStorage.scopeID else { return }

        let owner = accountStorage.userID
        let store = FileFeedShareDraftStore.live
        let visibility = selectedShareVisibility
        let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient()
        let remotePoster: (any FeedRemotePostPosting)? = ReviewDemoMode.isActive
            ? ReviewDemoCommunityStore.shared
            : owner.flatMap { owner in
                client.map { SupabaseFeedRemoteClient(client: $0, expectedPostingUserID: owner) }
            }
        let validateShareContext: @MainActor () throws -> Void = {
            guard accountStorage.scopeID == scope, accountStorage.userID == owner,
                  modelContext.container === accountStorage.container else {
                throw CommunitySafetyError.accountChanged
            }
            if let client, client.auth.currentSession?.user.id != owner {
                throw CommunitySafetyError.accountChanged
            }
            let id = workout.id
            guard try !modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id })).isEmpty else {
                throw WorkoutRecordManagementError.missingRecord
            }
        }
        let rankingPublication = SocialRankingPublicationContext()
        let automaticShare = UnifiedWorkoutAutomaticShare(context: modelContext, validate: validateShareContext,
            makeSecondaryPrivate: { member in
                guard owner != nil else { return }
                let model = WorkoutRecordManagement(workout: member)
                model.configure(context: modelContext, storage: accountStorage)
                guard await model.setVisibility(.privatePost) else { throw WorkoutRecordManagementError.unavailable }
            })
        let coordinator = RecordShareDraftCoordinator(
            store: store, remotePoster: remotePoster, visibilityProvider: { visibility },
            validateContext: validateShareContext,
            prepareWorkout: { workout in
                try validateShareContext()
                _ = await WorkoutRegionEnricher.resolveAndPersist(workoutID: workout.id,
                    context: modelContext, scopeID: scope, isCurrent: {
                        accountStorage.scopeID == scope && accountStorage.userID == owner
                            && modelContext.container === accountStorage.container
                    })
                try validateShareContext()
                let id = workout.id
                guard let record = try modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>(
                    predicate: #Predicate { $0.id == id })).first else {
                    throw WorkoutRecordManagementError.missingRecord
                }
                _ = record
                let prepared = try await automaticShare.prepare(workoutID: workout.id)
                if SocialRankingReleaseGate.productionReady {
                    rankingPublication.intent = try automaticShare.rankingContribution(primaryID: prepared.id)
                }
                return prepared
            },
            prepareRemoteShare: { workout in
                guard let owner, let client else { return }
                try validateShareContext()
                let route = try await WorkoutTelemetryStore(modelContext: modelContext).resolvedRoute(for: workout)
                try validateShareContext()
                let measurements = try WorkoutTelemetryStore(modelContext: modelContext).resolved(for: workout)
                let sharedService = SupabaseWorkoutSharedDetailService(client: client)
                let sharedEnabled = try await sharedService.enabled()
                try await sharedService.prepare(workout: workout,
                    route: route, telemetry: measurements, ownerID: owner)
                try validateShareContext()
                if sharedEnabled { return }
                guard let route, route.workoutId == workout.id else { return }
                let data = try await WorkoutRouteSnapshotRenderer().render(route: route, workoutType: workout.workoutType)
                try validateShareContext()
                guard let data else { return }
                try await WorkoutPhotoService(client: client).uploadRoute(workout: workout, ownerID: owner, data: data)
                try validateShareContext()
            }
        )
        isCreatingShareDraft = true
        shareDraftErrorMessage = nil
        shareOutcome = nil

        Task { @MainActor in
            do {
                try validateShareContext()
                var outcome = try await coordinator.handle(.shareToFeed, workout: workout)
                guard scope == accountStorage.scopeID else { return }
                // Posting is already confirmed. Registration is isolated and never
                // enters the posting retry/local-draft fallback path.
                if outcome?.postedRemotely == true, outcome?.visibility == .publicFeed,
                   SocialRankingReleaseGate.productionReady, let intent = rankingPublication.intent,
                   let owner, let client {
                    let safety = CommunitySafetyStore.shared
                    let result = await SocialRankingContributionClient(client: client, viewer: owner,
                        generation: safety.accountGeneration, safetyRevision: safety.revision)
                        .registerPublished(intent, store: SocialRankingRetryStore(directory: accountStorage.scopeDirectory, ownerID: owner))
                    guard scope == accountStorage.scopeID, accountStorage.userID == owner else { return }
                    outcome?.rankingRegistrationPending = result != .registered
                }
                if let confirmed = outcome, confirmed.postedRemotely {
                    outcome?.finalizeConfirmedPublication {
                        try automaticShare.complete(primaryID: confirmed.draft.sourceWorkoutId)
                    }
                }
                shareOutcome = outcome
            } catch {
                guard scope == accountStorage.scopeID else { return }
                shareDraftErrorMessage = (error as? RecordSharePublicationError)?.message ?? CommunitySafetyError.message(for: error)
            }
            isCreatingShareDraft = false
        }
    }

    @MainActor
    private func finishSavedWorkoutFlow(shareCompleted: Bool) {
        guard clearCheckpoint() else { return }
        savedWorkoutForShare = nil
        shareDraftErrorMessage = nil
        shareOutcome = nil
        activeHUDMode = .defaultMode
        activeSession = nil

        if shareCompleted, let onShareDraftComplete {
            onShareDraftComplete()
        } else if let onSaveComplete {
            onSaveComplete()
        } else {
            dismiss()
        }
    }

    @MainActor
    private func discardFinishedSession() {
        guard clearCheckpoint() else { return }
        resetFinishedShareState()
        withAnimation(.easeOut(duration: 0.22)) {
            activeHUDMode = .defaultMode
            activeSession = nil
        }
    }

    @MainActor
    private func resetFinishedShareState() {
        saveErrorMessage = nil
        hasPendingRouteSave = false
        shareDraftErrorMessage = nil
        shareOutcome = nil
        savedWorkoutForShare = nil
        isSavingWorkout = false
        isCreatingShareDraft = false
        selectedShareVisibility = .privateOnly
    }

    @MainActor
    private func recordLocationsIfNeeded(_ fixes: [RecordLocationFix]) {
        guard checkpointScopeID == accountStorage.scopeID, var session = activeSession, session.state == .active else { return }
        for fix in fixes {
            session = session.recordingLocation(fix.coordinate, at: fix.timestamp, speedMetersPerSecond: fix.speedMetersPerSecond, horizontalAccuracy: fix.horizontalAccuracy, speedAccuracy: fix.speedAccuracy, altitude: fix.altitude)
        }
        activeSession = session
        updateCoach()
        publishLiveWorkout()
        persistCheckpoint(force: false)
    }

    @MainActor
    private func restoreCheckpoint() async {
        guard checkpointStore == nil else { return }
        let scope = accountStorage.scopeID
        let store = RecordWorkoutCheckpointStore(fileURL: accountStorage.scopeDirectory.appendingPathComponent("active-workout.json"))
        checkpointScopeID = scope
        checkpointStore = store
        coach.bind(scope: scope)
        do {
            guard let restored = try store.load(), checkpointScopeID == accountStorage.scopeID else { return }
            coach.update(session: restored, at: Date(), restored: true)
            activeSession = restored
            selectedSport = restored.sport
            currentDate = Date()
            checkpointMessage = restored.state == .finished ? "저장 전 기록을 불러왔어요." : "중단된 기록을 불러왔어요. 확인 후 다시 시작해 주세요."
            if restored.state == .finished {
                let workoutStore = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
                let saved = try await workoutStore.fetchWorkout(id: restored.id)
                let route = try await SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext).fetchRoute(workoutId: restored.id)
                guard scope == accountStorage.scopeID else { return }
                savedWorkoutForShare = saved
                hasPendingRouteSave = saved != nil && restored.capturedRoute?.hasRoute == true && route == nil
                if hasPendingRouteSave { saveErrorMessage = "운동 기록은 저장됐지만 경로는 아직 저장되지 않았어요." }
            }
        } catch {
            checkpointLoadFailed = activeSession == nil
            checkpointMessage = "이전 기록을 완전히 불러오지 못했어요. 저장된 원본은 유지하고 있습니다."
        }
    }

    @MainActor
    private func persistCheckpoint(force: Bool) {
        guard !HealthCloudJournal.isRetired(modelContext),
              let checkpointStore, let session = activeSession else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastCheckpointDate) >= 10 else { return }
        do {
            var checkpointSession = session
            checkpointSession.coachCheckpoint = coach.checkpoint
            try checkpointStore.save(checkpointSession, at: now)
            lastCheckpointDate = now
        } catch {
            checkpointMessage = "진행 중 기록의 임시 저장에 실패했어요. 앱을 닫기 전에 운동을 종료하고 저장해 주세요."
        }
    }

    @MainActor
    private func suspendRecordingForDeparture() {
        coach.stop()
        if let session = activeSession, session.state == .active { activeSession = session.paused(at: Date()) }
        persistCheckpoint(force: true)
        locationManager.shutdown()
    }

    @MainActor
    private func clearCheckpoint() -> Bool {
        do {
            try checkpointStore?.clear()
            checkpointMessage = nil
            checkpointLoadFailed = false
            return true
        } catch {
            checkpointMessage = "임시 기록을 정리하지 못했어요. 다시 시도해 주세요."
            saveErrorMessage = checkpointMessage
            return false
        }
    }

    private func sessionSubtitle(for session: RecordWorkoutSession) -> String {
        if let checkpointMessage { return checkpointMessage }
        if let message = locationManager.recordingStatusMessage { return message }
        if session.state == .finished {
            return "요약을 확인하고 로컬 기록으로 저장할 수 있어요."
        }

        return session.state == .paused ? "일시정지 시간과 이동 거리는 운동 기록에 포함되지 않아요." : "운동 시간과 실제 위치를 기록하고 있어요."
    }

    private func elapsedText(for session: RecordWorkoutSession) -> String {
        let elapsed = Int(session.elapsedTime(referenceDate: currentDate))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var guidanceRecommendationText: String {
        plan.recommendation.guidanceText(for: selectedSport, weather: weatherSnapshot)
    }

    private var weatherIconTint: Color {
        switch weatherSnapshot.condition {
        case .clear:
            return SOOMColor.warning
        case .rain, .storm:
            return SOOMColor.blue
        case .snow:
            return SOOMColor.secondaryInk
        case .cloudy, .unknown:
            return SOOMColor.secondaryInk
        }
    }

    @MainActor
    private func loadRecoveryLabel() async {
        let provider = UnifiedWorkoutRecoveryDataProvider(
            previewProvider: UnifiedWorkoutRecoveryPreviewProvider(
                store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
            )
        )

        guard let summary = try? await provider.fetchRecoverySummary() else { return }
        recoveryLabel = summary.statusLabel
    }

    private func fetchWeatherIfPossible(for state: RecordLocationState, forceRefresh: Bool = false) async {
        guard state.canShowUserLocation,
              let coordinate = state.coordinate else {
            weatherSnapshot = .unavailable
            weatherDetailSnapshot = RecordWeatherDetailSnapshot.make(from: .unavailable)
            isFetchingWeather = false
            return
        }

        let coordinateKey = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        guard weatherRetryState.shouldAttemptFetch(for: coordinateKey, forceRefresh: forceRefresh) else { return }
        guard RecordWeatherFetchPolicy.shouldAttemptLiveFetch(locationState: state) else {
            weatherSnapshot = .unavailable
            weatherDetailSnapshot = RecordWeatherDetailSnapshot.make(from: .unavailable)
            isFetchingWeather = false
            return
        }

        weatherRetryState.markAttempt(for: coordinateKey)
        isFetchingWeather = true

        do {
            let snapshot = try await weatherService.fetchWeather(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            weatherSnapshot = snapshot
            weatherDetailSnapshot = (try? await weatherService.fetchWeatherDetail(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )) ?? RecordWeatherDetailSnapshot.make(from: snapshot)
            weatherRetryState.markSuccess(for: coordinateKey)
        } catch {
            weatherSnapshot = .unavailable
            weatherDetailSnapshot = RecordWeatherDetailSnapshot.make(from: .unavailable)
            weatherRetryState.markFailure(for: coordinateKey)
        }

        isFetchingWeather = false
    }

    private func iconButton(
        icon: String,
        tint: Color = SOOMColor.ink,
        background: Color = SOOMColor.surface.opacity(0.88),
        stroke: Color = SOOMColor.line.opacity(0.86),
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            SOOMHaptics.selection()
            action()
        } label: {
            iconSurface(icon: icon, tint: tint, background: background, stroke: stroke)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func iconSurface(
        icon: String,
        tint: Color,
        background: Color,
        stroke: Color
    ) -> some View {
        Image(soom: icon)
            .font(.system(size: SOOMFont.Size.headline, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: RecordMapHeaderLayout.controlSize, height: RecordMapHeaderLayout.controlSize)
            .background(background)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(stroke, lineWidth: 1)
            }
            .shadow(color: SOOMColor.ink.opacity(0.05), radius: 9, x: 0, y: 5)
    }

    private var sportTint: Color {
        sportTint(for: selectedSport)
    }

    private func sportTint(for sport: RecordSportMode) -> Color {
        switch sport {
        case .cycling:
            return SOOMColor.bike
        case .running:
            return SOOMColor.run
        case .walking:
            return SOOMColor.blue
        }
    }
}

struct RecordMapFallbackSurface: View {
    let sport: RecordSportMode
    let routeTitle: String
    let routeDistance: String

    var body: some View {
        ContentUnavailableView(
            "지도를 표시할 수 없어요",
            soomIcon: "map",
            description: Text("지도 연결 상태를 확인해 주세요. 지도 없이도 운동을 기록할 수 있어요.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SOOMColor.background)
    }

    private var routeOverlay: some View {
        HStack(spacing: 7) {
            Text(routeTitle)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .lineLimit(1)
            Text(routeDistance)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .foregroundStyle(SOOMColor.ink)
        .padding(.horizontal, SOOMLayout.Spacing.md)
        .padding(.vertical, SOOMLayout.Spacing.sm)
        .background(SOOMColor.surface.opacity(0.88))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(SOOMColor.line.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: SOOMColor.ink.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private var sportTint: Color {
        switch sport {
        case .cycling:
            return SOOMColor.bike
        case .running:
            return SOOMColor.run
        case .walking:
            return SOOMColor.blue
        }
    }

    private var currentLocationMarker: some View {
        ZStack {
            Circle()
                .fill(SOOMColor.accent.opacity(0.10))
                .frame(width: RecordCurrentLocationMarkerStyle.fallbackStaticHaloDiameter, height: RecordCurrentLocationMarkerStyle.fallbackStaticHaloDiameter)
            Circle()
                .fill(SOOMColor.white)
                .frame(width: 22, height: 22)
                .shadow(color: SOOMColor.ink.opacity(0.16), radius: 7, x: 0, y: 4)
            Circle()
                .fill(SOOMColor.accent)
                .frame(width: 12, height: 12)
        }
        .offset(
            x: RecordCurrentLocationMarkerStyle.anchorOffset.width,
            y: RecordCurrentLocationMarkerStyle.anchorOffset.height
        )
    }

    private func routeEndpoint(at point: CGPoint, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 13, height: 13)
            .overlay {
                Circle()
                    .stroke(SOOMColor.ink.opacity(0.16), lineWidth: 1)
            }
            .position(point)
    }

    private func riverShape(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: -30, y: size.height * 0.38))
            path.addCurve(
                to: CGPoint(x: size.width + 30, y: size.height * 0.58),
                control1: CGPoint(x: size.width * 0.18, y: size.height * 0.26),
                control2: CGPoint(x: size.width * 0.72, y: size.height * 0.70)
            )
            path.addLine(to: CGPoint(x: size.width + 30, y: size.height * 0.68))
            path.addCurve(
                to: CGPoint(x: -30, y: size.height * 0.49),
                control1: CGPoint(x: size.width * 0.74, y: size.height * 0.80),
                control2: CGPoint(x: size.width * 0.18, y: size.height * 0.38)
            )
            path.closeSubpath()
        }
    }

    private func parkShape(in size: CGSize) -> Path {
        Path { path in
            path.addRoundedRect(
                in: CGRect(x: size.width * 0.58, y: size.height * 0.12, width: size.width * 0.48, height: size.height * 0.26),
                cornerSize: CGSize(width: 70, height: 70)
            )
            path.addRoundedRect(
                in: CGRect(x: -size.width * 0.10, y: size.height * 0.70, width: size.width * 0.55, height: size.height * 0.22),
                cornerSize: CGSize(width: 64, height: 64)
            )
        }
    }

    private func roadNetwork(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.18))
            path.addCurve(
                to: CGPoint(x: size.width * 0.88, y: size.height * 0.34),
                control1: CGPoint(x: size.width * 0.24, y: size.height * 0.22),
                control2: CGPoint(x: size.width * 0.60, y: size.height * 0.15)
            )
            path.move(to: CGPoint(x: size.width * 0.10, y: size.height * 0.78))
            path.addCurve(
                to: CGPoint(x: size.width * 0.90, y: size.height * 0.72),
                control1: CGPoint(x: size.width * 0.35, y: size.height * 0.66),
                control2: CGPoint(x: size.width * 0.68, y: size.height * 0.86)
            )
            path.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.08))
            path.addLine(to: CGPoint(x: size.width * 0.40, y: size.height * 0.88))
            path.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.12))
            path.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.86))
        }
    }

    private func suggestedRoute(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.30, y: size.height * 0.60))
            path.addCurve(
                to: CGPoint(x: size.width * 0.72, y: size.height * 0.42),
                control1: CGPoint(x: size.width * 0.42, y: size.height * 0.70),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.30)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.38, y: size.height * 0.47),
                control1: CGPoint(x: size.width * 0.76, y: size.height * 0.55),
                control2: CGPoint(x: size.width * 0.50, y: size.height * 0.58)
            )
        }
    }
}

private struct RecordBreathingBottomWaveView: View {
    let progress: CGFloat
    let opacity: Double
    let yOffset: CGFloat
    let isInteracting: Bool

    var body: some View {
        GeometryReader { geometry in
            let blobWidth = RecordBreathingBottomWaveLayout.blobWidth(for: geometry.size.width)
            let blobHeight = RecordBreathingBottomWaveLayout.blobFrameHeight(for: geometry.size.width)
            let blobCenterY = geometry.size.height + RecordBreathingBottomWaveLayout.blobCenterYOffset + yOffset
            let endRadius = RecordBreathingBottomWaveLayout.blobEndRadius(for: geometry.size.width)
            let blobScale = isInteracting
                ? RecordBreathingBottomWaveLayout.blobInteractionScale
                : RecordBreathingBottomWaveLayout.blobScale(progress: progress)

            radialBlob(endRadius: endRadius)
                .frame(width: blobWidth, height: blobHeight)
                .scaleEffect(blobScale, anchor: .center)
                .opacity(opacity)
                .position(x: geometry.size.width / 2, y: blobCenterY)
        }
        .allowsHitTesting(false)
    }

    private func radialBlob(endRadius: CGFloat) -> RadialGradient {
        RadialGradient(
            stops: RecordBreathingBottomWaveLayout.radialBlobOpacityStops.map { stop in
                .init(color: SOOMColor.accent.opacity(stop.opacity), location: stop.location)
            },
            center: .center,
            startRadius: 0,
            endRadius: endRadius
        )
    }
}

/// The production finished-summary grid, also rendered directly in native layout tests.
/// The parent retains the original time/route/save/share contracts.
struct RecordFinishedSummaryMetrics: View {
    let startText: String
    let endText: String
    let routeText: String
    let distanceText: String
    var body: some View {
        SOOMAdaptiveSummaryGrid {
            pill(title: "시작", value: startText)
            pill(title: "종료", value: endText)
            pill(title: "경로", value: routeText)
            pill(title: "거리", value: distanceText)
        }
        .accessibilityElement(children: .contain)
    }
    private func pill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .textCase(.uppercase)
            Text(value)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SOOMLayout.Spacing.md)
        .padding(.vertical, SOOMLayout.Spacing.sm)
        .background(SOOMColor.background)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.small, style: .continuous))
    }

}
