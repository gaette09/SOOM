import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationManager = RecordLocationManager()
    @State private var selectedSport: RecordSportMode = RecordLaunchPlan.mockToday.defaultSport
    @State private var isRoutePlaceholderPresented = false
    @State private var recenterTrigger = 0
    @State private var activeSession: RecordWorkoutSession?
    @State private var currentDate = Date()
    @State private var isSavingWorkout = false
    @State private var saveErrorMessage: String?
    @State private var savedWorkoutForShare: UnifiedWorkout?
    @State private var isCreatingShareDraft = false
    @State private var shareDraftErrorMessage: String?
    @State private var weatherSnapshot = RecordWeatherSnapshot.fallbackClear
    @State private var isFetchingWeather = false
    @State private var lastWeatherCoordinateKey: String?

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
            ZStack {
                RecordMapView(
                    sport: selectedSport,
                    route: plan.route,
                    locationState: locationManager.state,
                    recenterTrigger: recenterTrigger
                )
                    .ignoresSafeArea()

                HStack {
                    iconButton(
                        icon: "location.viewfinder",
                        accessibilityLabel: "현재 위치 다시 잡기",
                        action: {
                            locationManager.handleLocationButtonTap()
                            if locationManager.state.recenterTarget != nil {
                                recenterTrigger += 1
                            }
                        }
                    )

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, proxy.safeAreaInsets.top + 142)

                VStack(spacing: 0) {
                    topBar
                        .padding(.top, proxy.safeAreaInsets.top + 8)

                    Spacer(minLength: 0)

                    VStack(spacing: 14) {
                        recommendationPill
                        sportSelector
                        startButton
                    }
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18) + 28)
                }
                .padding(.horizontal, 18)

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
        .alert("추천 루트", isPresented: $isRoutePlaceholderPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("v1에서는 mock route preview만 보여주고, 실제 route recommendation backend는 아직 연결하지 않았어요.")
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
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            closeButton

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                weatherPill
                iconButton(
                    icon: SOOMIcon.map,
                    accessibilityLabel: "추천 루트 보기",
                    action: { isRoutePlaceholderPresented = true }
                )
            }
        }
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

    private var recommendationPill: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(plan.recommendation.recoveryLabel)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(SOOMColor.recovery)
                .clipShape(Capsule())

            Text(shortRecommendationText)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SOOMColor.surface.opacity(0.88))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(SOOMColor.line, lineWidth: 1)
        }
        .shadow(color: SOOMColor.ink.opacity(0.045), radius: 10, x: 0, y: 6)
    }

    private var weatherPill: some View {
        HStack(spacing: 8) {
            Image(systemName: weatherSnapshot.conditionIconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(weatherIconTint)

            Text(weatherSnapshot.temperatureText)
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)

            if isFetchingWeather {
                ProgressView()
                    .controlSize(.mini)
                    .tint(SOOMColor.secondaryInk)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SOOMColor.surface.opacity(0.94))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(SOOMColor.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("날씨")
        .accessibilityValue(weatherSnapshot.pillText)
    }

    private var sportSelector: some View {
        HStack(spacing: 10) {
            ForEach(RecordSportMode.allCases) { sport in
                Button {
                    selectedSport = sport
                    SOOMHaptics.selection()
                } label: {
                    Image(systemName: sport.iconName)
                        .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(selectedSport == sport ? SOOMColor.selectedInk : SOOMColor.ink)
                    .frame(width: 48, height: 48)
                    .background(selectedSport == sport ? SOOMColor.selectedSurface : SOOMColor.surface.opacity(0.90))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(selectedSport == sport ? Color.clear : SOOMColor.line, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(sport.title) 선택")
            }
        }
        .padding(5)
        .background(SOOMColor.surface.opacity(0.78))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(SOOMColor.line.opacity(0.8), lineWidth: 1)
        }
    }

    private var startButton: some View {
        Button {
            SOOMHaptics.softImpact()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                resetFinishedShareState()
                activeSession = sessionStarter.start(
                    sport: selectedSport,
                    locationState: locationManager.state
                )
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: selectedSport.iconName)
                    .font(.system(size: 24, weight: .bold))
                Text("READY")
                    .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                    .tracking(1.0)
            }
            .foregroundStyle(SOOMColor.white)
            .frame(width: 104, height: 104)
            .background(
                Circle()
                    .fill(SOOMColor.accent)
                    .overlay {
                        Circle()
                            .stroke(SOOMColor.white.opacity(0.75), lineWidth: 1.4)
                            .padding(8)
                    }
            )
            .shadow(color: SOOMColor.accent.opacity(0.26), radius: 18, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedSport.startTitle)
        .accessibilityHint("선택한 운동 모드로 기록을 시작합니다.")
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

    private var shortRecommendationText: String {
        plan.recommendation.compactText(for: selectedSport, weather: weatherSnapshot)
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
            isFetchingWeather = false
            return
        }

        let coordinateKey = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        guard coordinateKey != lastWeatherCoordinateKey else { return }
        guard RecordWeatherFetchPolicy.shouldAttemptLiveFetch(locationState: state) else {
            weatherSnapshot = .fallbackClear
            isFetchingWeather = false
            return
        }

        lastWeatherCoordinateKey = coordinateKey
        isFetchingWeather = true

        do {
            weatherSnapshot = try await weatherService.fetchWeather(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            weatherSnapshot = .fallbackClear
        }

        isFetchingWeather = false
    }

    private func iconButton(icon: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button {
            SOOMHaptics.selection()
            action()
        } label: {
            iconSurface(icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func iconSurface(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(SOOMColor.ink)
            .frame(width: 46, height: 46)
            .background(SOOMColor.surface.opacity(0.88))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(SOOMColor.line.opacity(0.86), lineWidth: 1)
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
                .fill(SOOMColor.blue.opacity(0.12))
                .frame(width: 72, height: 72)
            Circle()
                .fill(SOOMColor.white)
                .frame(width: 22, height: 22)
                .shadow(color: SOOMColor.ink.opacity(0.16), radius: 7, x: 0, y: 4)
            Circle()
                .fill(SOOMColor.blue)
                .frame(width: 12, height: 12)
        }
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
