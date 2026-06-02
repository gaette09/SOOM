import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var locationManager = RecordLocationManager()
    @State private var selectedSport: RecordSportMode = RecordLaunchPlan.mockToday.defaultSport
    @State private var selectedRoute = RecordLaunchPlan.mockToday.route
    @State private var isWeatherDetailPresented = false
    @State private var isRouteRecommendationPresented = false
    @State private var isReadyFocusMode = false
    @State private var hoveredSport: RecordSportMode?
    @State private var recenterTrigger = 0
    @State private var activeSession: RecordWorkoutSession?
    @State private var currentDate = Date()
    @State private var isSavingWorkout = false
    @State private var saveErrorMessage: String?
    @State private var savedWorkoutForShare: UnifiedWorkout?
    @State private var isCreatingShareDraft = false
    @State private var shareDraftErrorMessage: String?
    @State private var weatherSnapshot = RecordWeatherSnapshot.fallbackClear
    @State private var weatherDetailSnapshot = RecordWeatherDetailSnapshot.make(from: .fallbackClear)
    @State private var isFetchingWeather = false
    @State private var lastWeatherCoordinateKey: String?
    @State private var isBottomGradientBreathing = false
    @State private var readyInteractionState = RecordReadyWaveInteractionState.idle

    private let plan = RecordLaunchPlan.mockToday
    private let sessionStarter = RecordWorkoutSessionStarter()
    private let weatherService: any RecordWeatherService
    private let onDismiss: (() -> Void)?
    private let onSaveComplete: (() -> Void)?
    private let onShareDraftComplete: (() -> Void)?

    init(
        weatherService: any RecordWeatherService = RecordWeatherServiceFactory.make(),
        onDismiss: (() -> Void)? = nil,
        onSaveComplete: (() -> Void)? = nil,
        onShareDraftComplete: (() -> Void)? = nil
    ) {
        self.weatherService = weatherService
        self.onDismiss = onDismiss
        self.onSaveComplete = onSaveComplete
        self.onShareDraftComplete = onShareDraftComplete
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
                    locationState: locationManager.state,
                    recenterTrigger: recenterTrigger
                )
                    .ignoresSafeArea()

                bottomFocusGradient
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)

                topControlsLayer(frames: headerFrames)
                    .zIndex(4)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    readyLaunchControl(safeAreaInsets: proxy.safeAreaInsets)
                }
                .zIndex(1)

                if let activeSession {
                    activeWorkoutOverlay(
                        session: activeSession,
                        safeAreaInsets: proxy.safeAreaInsets
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isWeatherDetailPresented) {
            weatherDetailSheet
        }
        .sheet(isPresented: $isRouteRecommendationPresented) {
            routeRecommendationSheet
        }
        .onChange(of: locationManager.state) { _, newState in
            guard newState.recenterTarget != nil else { return }
            recenterTrigger += 1
            Task {
                await fetchWeatherIfPossible(for: newState)
            }
        }
        .task {
            await fetchWeatherIfPossible(for: locationManager.state)
        }
        .task(id: activeSession?.id) {
            guard activeSession != nil else { return }

            while !Task.isCancelled {
                currentDate = Date()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onChange(of: readyInteractionState) { _, newState in
            handleReadyInteractionStateChange(newState)
        }
    }

    private func topControlsLayer(frames: RecordMapHeaderFrames) -> some View {
        ZStack(alignment: .topLeading) {
            topGuidanceBanner
                .frame(width: frames.bannerFrame.width, height: frames.bannerFrame.height)
                .position(x: frames.bannerFrame.midX, y: frames.bannerFrame.midY)

            closeButton
                .position(frames.backButtonCenter)

            rightEdgeControls
                .frame(width: frames.rightControlsFrame.width, height: frames.rightControlsFrame.height)
                .position(x: frames.rightControlsFrame.midX, y: frames.rightControlsFrame.midY)
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
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .bold))
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
        .accessibilityLabel("Feed로 돌아가기")
    }

    private var topGuidanceBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SOOMColor.accent)
                Text("오늘의 출발 기준")
                    .font(SOOMFont.body(9, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.accentInk)
                    .textCase(.uppercase)
            }

            Text(plan.recommendation.recoveryLabel)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.accentInk)
                .lineLimit(1)

            Text(guidanceRecommendationText)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(RecordMapHeaderLayout.maxBodyLineCount)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
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
        .accessibilityValue("\(plan.recommendation.recoveryLabel). \(guidanceRecommendationText)")
    }

    private var rightEdgeControls: some View {
        VStack(spacing: RecordMapHeaderLayout.controlSpacing) {
            weatherPill
            iconButton(
                icon: RecordLaunchControl.routeRecommendation.iconName,
                accessibilityLabel: "추천 코스 보기",
                action: { isRouteRecommendationPresented = true }
            )
            iconButton(
                icon: RecordLaunchControl.currentLocation.iconName,
                accessibilityLabel: "현재 위치로 돌아가기",
                action: {
                    locationManager.handleLocationButtonTap()
                    if locationManager.state.recenterTarget != nil {
                        recenterTrigger += 1
                    }
                }
            )
        }
    }

    private var weatherPill: some View {
        Button {
            SOOMHaptics.selection()
            isWeatherDetailPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Image(systemName: weatherSnapshot.conditionIconName)
                        .font(.system(size: 14, weight: .semibold))
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

    private func readyLaunchControl(safeAreaInsets: EdgeInsets) -> some View {
        GeometryReader { geometry in
            let readyCenter = CGPoint(
                x: geometry.size.width / 2,
                y: geometry.size.height - RecordReadyLaunchVisualLayout.buttonCenterBottomOffset
            )

            ZStack {
                ForEach(RecordReadyRadialLayout.items(center: readyCenter), id: \.sport.rawValue) { item in
                    radialSportButton(item: item, readyCenter: readyCenter)
                        .position(
                            RecordReadyRadialLayout.displayCenter(
                                for: item,
                                readyCenter: readyCenter,
                                isRevealed: isReadyFocusMode
                            )
                        )
                        .opacity(isReadyFocusMode ? 1 : 0)
                        .scaleEffect(isReadyFocusMode ? RecordReadyRadialLayout.sportIconFinalScale : RecordReadyRadialLayout.sportIconInitialScale)
                        .animation(
                            .spring(response: 0.34, dampingFraction: 0.78)
                                .delay(isReadyFocusMode ? (RecordReadyRadialLayout.revealDelays[item.sport] ?? 0) : 0),
                            value: isReadyFocusMode
                        )
                        .allowsHitTesting(false)
                }

                readyButtonSurface(for: selectedSport)
                    .position(readyCenter)
                    .contentShape(Circle())
                    .gesture(readyDragGesture(readyCenter: readyCenter))
            }
            .coordinateSpace(name: RecordReadyLaunchVisualLayout.coordinateSpaceName)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("READY")
            .accessibilityHint("누르면 운동 종류가 보이고, 위쪽 반원의 운동 종류로 드래그한 뒤 손을 떼면 시작해요.")
        }
        .frame(height: RecordReadyLaunchVisualLayout.containerHeight)
        .padding(.bottom, max(safeAreaInsets.bottom, 18) + RecordReadyLaunchVisualLayout.bottomPaddingExtra)
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
        Image(systemName: RecordReadyLaunchVisualLayout.primaryIconName)
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
                        .padding(8)
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
            Image(systemName: item.sport.iconName)
                .font(.system(size: 19, weight: .bold))
            Text(item.sport.title)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
        }
        .foregroundStyle(isHovered ? SOOMColor.white : SOOMColor.ink)
        .frame(width: 68, height: 68)
        .background(isHovered ? SOOMColor.accent : SOOMColor.surface.opacity(0.96))
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(isHovered ? SOOMColor.white.opacity(0.72) : SOOMColor.line.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: SOOMColor.ink.opacity(isHovered ? 0.18 : 0.10), radius: isHovered ? 16 : 10, x: 0, y: 8)
        .scaleEffect(isHovered ? RecordReadyRadialLayout.hoveredScale : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isHovered)
        .accessibilityHidden(!RecordReadyRadialLayout.isAboveReadyCenter(item: item, readyCenter: readyCenter))
    }

    @MainActor
    private func beginReadyRadialSelection() {
        guard !isReadyFocusMode else { return }

        RecordReadyRadialInteraction.begin().forEach(playReadyHaptic)
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            hoveredSport = nil
            readyInteractionState = .revealing
            isReadyFocusMode = true
        }
    }

    @MainActor
    private func updateHoveredSport(at location: CGPoint, readyCenter: CGPoint) {
        if isReadyFocusMode, readyInteractionState == .revealing {
            readyInteractionState = .dragging
        }
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
        Task { @MainActor in
            await Task.yield()
            guard !isReadyFocusMode else { return }
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
        SOOMHaptics.softImpact()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            resetFinishedShareState()
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
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .frame(width: 34, height: 34)
                            .background(SOOMColor.background)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("날씨 닫기")
                }

                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: detail.conditionIconName)
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
                    Text("위치나 날씨 API가 준비되지 않으면 안전한 fallback 날씨를 보여줘요.")
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
        let options = RecordRouteCatalogOption.mockOptions(for: selectedSport)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("추천 코스")
                            .font(SOOMFont.displayMedium(24, relativeTo: .title2))
                            .foregroundStyle(SOOMColor.ink)
                        Text("실제 Directions 없이 mock catalog로 출발 전 코스를 고르는 foundation이에요.")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button {
                        SOOMHaptics.selection()
                        isRouteRecommendationPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .frame(width: 34, height: 34)
                            .background(SOOMColor.background)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("추천 코스 닫기")
                }

                ForEach(options) { option in
                    routeCatalogRow(option)
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
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
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
        .padding(12)
        .background(SOOMColor.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func airQualityMetric(title: String, value: String, level: RecordAirQualityLevel) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: title == "미세" ? "aqi.medium" : "circle.hexagongrid.fill")
                .font(.system(size: 14, weight: .bold))
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
        .padding(12)
        .background(airQualityColor(level).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(airQualityColor(level).opacity(0.22), lineWidth: 1)
        }
    }

    private func weatherGuideCard(for detail: RecordWeatherDetailSnapshot) -> some View {
        let text = weatherGuideText(for: detail)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 26, height: 26)
                .background(SOOMColor.accentSurface)
                .clipShape(Circle())

            Text(text)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(SOOMColor.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hourlyForecastSection(_ forecasts: [RecordHourlyWeather]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("시간별")
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(forecasts) { forecast in
                        VStack(spacing: 8) {
                            Text(forecast.timeLabel)
                                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                                .foregroundStyle(SOOMColor.tertiaryInk)
                            Image(systemName: forecast.iconName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(SOOMColor.accent)
                            Text(forecast.temperatureText)
                                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                                .foregroundStyle(SOOMColor.ink)
                        }
                        .frame(width: 64)
                        .padding(.vertical, 12)
                        .background(SOOMColor.background)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

            VStack(spacing: 8) {
                ForEach(forecasts) { forecast in
                    HStack(spacing: 12) {
                        Text(forecast.dayLabel)
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.ink)
                            .frame(width: 44, alignment: .leading)
                        Image(systemName: forecast.iconName)
                            .font(.system(size: 14, weight: .bold))
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(SOOMColor.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func airQualityColor(_ level: RecordAirQualityLevel) -> Color {
        switch level {
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
        if detail.airQuality.pm10Level == .bad || detail.airQuality.pm10Level == .veryBad ||
            detail.airQuality.pm25Level == .bad || detail.airQuality.pm25Level == .veryBad {
            return "미세먼지가 높을 땐 강도를 낮추고 호흡이 편한 코스로 시작해요."
        }

        switch weatherSnapshot.condition {
        case .rain, .snow, .storm:
            return "노면이 미끄러울 수 있어요. 오늘은 짧게 움직이고 안전을 먼저 봐요."
        case .clear where (weatherSnapshot.temperatureCelsius ?? 0) >= 28:
            return "햇볕이 강한 날엔 물을 먼저 챙기고 초반 페이스를 낮춰요."
        case .clear, .cloudy, .unknown:
            return "날씨 흐름은 무난해요. READY에서 종목을 골라 가볍게 시작해요."
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
                    Image(systemName: RecordLaunchControl.routeRecommendation.iconName)
                        .font(.system(size: 16, weight: .bold))
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
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
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
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(SOOMColor.accent)
                }
            }
            .padding(14)
            .background(SOOMColor.background)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? SOOMColor.accentLine : SOOMColor.line.opacity(0.82), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func activeWorkoutOverlay(
        session: RecordWorkoutSession,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(sportTint(for: session.sport).opacity(0.14))
                            .frame(width: 46, height: 46)
                        Image(systemName: session.sport.iconName)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(sportTint(for: session.sport))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.title)
                            .font(SOOMFont.body(16, weight: .bold, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink)
                        Text(sessionSubtitle(for: session))
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Text(session.statusLabel)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(session.state == .paused ? SOOMColor.warning : SOOMColor.recovery)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background((session.state == .paused ? SOOMColor.warning : SOOMColor.recovery).opacity(0.12))
                        .clipShape(Capsule())
                }

                HStack(alignment: .bottom, spacing: 22) {
                    metricBlock(
                        value: elapsedText(for: session),
                        label: "경과 시간"
                    )
                    metricBlock(
                        value: "-- km",
                        label: session.startedWithLocation ? "거리 측정 준비" : "위치 없이 시작"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if session.state == .finished {
                    finishedSummaryContent(for: session)
                } else {
                    activeSessionActions(for: session)
                }
            }
            .padding(18)
            .background(SOOMColor.surface.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(SOOMColor.line.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: SOOMColor.ink.opacity(0.14), radius: 28, x: 0, y: 16)
            .padding(.horizontal, 16)
            .padding(.bottom, max(safeAreaInsets.bottom, 16) + 8)
        }
    }

    private func metricBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(SOOMFont.displayMedium(28, relativeTo: .title))
                .foregroundStyle(SOOMColor.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(label)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
    }

    private func activeSessionActions(for session: RecordWorkoutSession) -> some View {
        HStack(spacing: 10) {
            Button {
                SOOMHaptics.selection()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    activeSession = session.state == .paused ? session.resumed() : session.paused(at: currentDate)
                }
            } label: {
                Text(session.state == .paused ? "다시 시작" : "일시정지")
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .callout))
                    .foregroundStyle(SOOMColor.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(SOOMColor.background)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                SOOMHaptics.softImpact()
                withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                    activeSession = session.finished(at: currentDate)
                }
            } label: {
                Text("종료")
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .callout))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(SOOMColor.ink)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                SOOMHaptics.selection()
                withAnimation(.easeOut(duration: 0.22)) {
                    resetFinishedShareState()
                    activeSession = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(width: 42, height: 42)
                    .background(SOOMColor.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("기록 취소")
        }
    }

    private func finishedSummaryContent(for session: RecordWorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .overlay(SOOMColor.line.opacity(0.8))

            if let summary = RecordWorkoutSummaryBuilder.makeSummary(from: session) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        summaryPill(title: "시작", value: timeText(summary.startedAt))
                        summaryPill(title: "종료", value: timeText(summary.endedAt))
                        summaryPill(
                            title: "Route",
                            value: summary.capturedRoute ? "기록 준비" : "없음"
                        )
                    }

                    Text(savedWorkoutForShare == nil
                         ? "저장하면 이 기기의 로컬 운동 기록으로 남고 Activity에서 확인할 수 있어요."
                         : "저장됐어요. 원하면 이 기록을 공개 전 피드 초안으로 만들어둘 수 있어요.")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let saveErrorMessage {
                    Text(saveErrorMessage)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let shareDraftErrorMessage {
                    Text(shareDraftErrorMessage)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let savedWorkoutForShare {
                    HStack(spacing: 10) {
                        Button {
                            SOOMHaptics.selection()
                            completeSavedWorkoutLater()
                        } label: {
                            Text("나중에")
                                .font(SOOMFont.body(14, weight: .bold, relativeTo: .callout))
                                .foregroundStyle(SOOMColor.secondaryInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(SOOMColor.background)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isCreatingShareDraft)

                        Button {
                            SOOMHaptics.softImpact()
                            Task {
                                await createFeedShareDraft(from: savedWorkoutForShare)
                            }
                        } label: {
                            Text(isCreatingShareDraft ? "초안 생성 중" : "피드에 공유하기")
                                .font(SOOMFont.body(14, weight: .bold, relativeTo: .callout))
                                .foregroundStyle(SOOMColor.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(SOOMColor.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isCreatingShareDraft)
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
                                .padding(.vertical, 14)
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
                                .padding(.vertical, 14)
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
                        .padding(.vertical, 14)
                        .background(SOOMColor.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SOOMFont.body(9, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)
                .textCase(.uppercase)
            Text(value)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(SOOMColor.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func saveFinishedSession(_ summary: RecordWorkoutSummary) async {
        guard !isSavingWorkout else { return }

        isSavingWorkout = true
        saveErrorMessage = nil

        do {
            let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
            let saver = RecordWorkoutSaver(store: store)
            let workout = try await saver.save(summary)
            isSavingWorkout = false
            savedWorkoutForShare = workout
        } catch {
            isSavingWorkout = false
            saveErrorMessage = "저장하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    @MainActor
    private func createFeedShareDraft(from workout: UnifiedWorkout) async {
        guard !isCreatingShareDraft else { return }

        isCreatingShareDraft = true
        shareDraftErrorMessage = nil

        do {
            let coordinator = RecordShareDraftCoordinator(store: FileFeedShareDraftStore.live)
            _ = try await coordinator.handle(.shareToFeed, workout: workout)
            isCreatingShareDraft = false
            finishSavedWorkoutFlow(shareCompleted: true)
        } catch {
            isCreatingShareDraft = false
            shareDraftErrorMessage = "피드 초안을 만들지 못했어요. 기록은 이 기기에 저장되어 있어요."
        }
    }

    @MainActor
    private func completeSavedWorkoutLater() {
        finishSavedWorkoutFlow(shareCompleted: false)
    }

    @MainActor
    private func finishSavedWorkoutFlow(shareCompleted: Bool) {
        savedWorkoutForShare = nil
        shareDraftErrorMessage = nil
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
        resetFinishedShareState()
        withAnimation(.easeOut(duration: 0.22)) {
            activeSession = nil
        }
    }

    @MainActor
    private func resetFinishedShareState() {
        saveErrorMessage = nil
        shareDraftErrorMessage = nil
        savedWorkoutForShare = nil
        isSavingWorkout = false
        isCreatingShareDraft = false
    }

    private func sessionSubtitle(for session: RecordWorkoutSession) -> String {
        if session.state == .finished {
            return "요약을 확인하고 로컬 기록으로 저장할 수 있어요."
        }

        return session.startedWithLocation
            ? "현재 위치를 바탕으로 route 기록 준비 중"
            : "위치 권한 없이도 local-first로 시간 기록을 시작했어요."
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
            return SOOMColor.accent
        }
    }

    @MainActor
    private func fetchWeatherIfPossible(for state: RecordLocationState) async {
        guard state.canShowUserLocation,
              let coordinate = state.coordinate else {
            weatherSnapshot = .fallbackClear
            weatherDetailSnapshot = RecordWeatherDetailSnapshot.make(from: .fallbackClear)
            isFetchingWeather = false
            return
        }

        let coordinateKey = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        guard coordinateKey != lastWeatherCoordinateKey else { return }
        guard RecordWeatherFetchPolicy.shouldAttemptLiveFetch(locationState: state) else {
            weatherSnapshot = .fallbackClear
            weatherDetailSnapshot = RecordWeatherDetailSnapshot.make(from: .fallbackClear)
            isFetchingWeather = false
            return
        }

        lastWeatherCoordinateKey = coordinateKey
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
        } catch {
            weatherSnapshot = .fallbackClear
            weatherDetailSnapshot = RecordWeatherDetailSnapshot.make(from: .fallbackClear)
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
        Image(systemName: icon)
            .font(.system(size: 17, weight: .bold))
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
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xDDE7DC),
                        SOOMColor.background,
                        Color(hex: 0xE8E1D2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                parkShape(in: proxy.size)
                    .fill(Color(hex: 0xC9D7C4).opacity(0.70))
                    .blur(radius: 0.5)

                riverShape(in: proxy.size)
                    .fill(Color(hex: 0xB8CAD0).opacity(0.58))

                roadNetwork(in: proxy.size)
                    .stroke(SOOMColor.white.opacity(0.72), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                roadNetwork(in: proxy.size)
                    .stroke(SOOMColor.line.opacity(0.42), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                suggestedRoute(in: proxy.size)
                    .stroke(sportTint, style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: sportTint.opacity(0.22), radius: 5, x: 0, y: 3)

                routeOverlay
                    .position(x: proxy.size.width * 0.58, y: proxy.size.height * 0.38)

                routeEndpoint(at: CGPoint(x: proxy.size.width * 0.30, y: proxy.size.height * 0.60), color: sportTint)
                routeEndpoint(at: CGPoint(x: proxy.size.width * 0.72, y: proxy.size.height * 0.42), color: SOOMColor.white)

                currentLocationMarker
                    .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.51)

                VStack {
                    Spacer()
                    Text("mock map surface · 위치 권한 요청 없음")
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .padding(.bottom, 12)
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
