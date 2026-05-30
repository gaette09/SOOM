import SwiftData
import SwiftUI
import UIKit

private enum SOOMTab: String, CaseIterable, Identifiable {
    case feed
    case activity
    case record
    case clubs
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed:
            return "피드"
        case .record:
            return "기록"
        case .activity:
            return "활동"
        case .clubs:
            return "클럽"
        case .profile:
            return "프로필"
        }
    }

    var iconName: String {
        switch self {
        case .feed:
            return SOOMIcon.feed
        case .record:
            return SOOMIcon.record
        case .activity:
            return SOOMIcon.activity
        case .clubs:
            return SOOMIcon.clubs
        case .profile:
            return SOOMIcon.profile
        }
    }
}

final class SOOMTabBarVisibility: ObservableObject {
    @Published var isHidden = false
}

struct RootTabView: View {
    @State private var selectedTab: SOOMTab = .feed
    @State private var isRecordLaunchPresented = false
    @State private var shouldReturnToActivityAfterRecordSave = false
    @State private var shouldShowInitialCoachPreview = true
    @StateObject private var tabBarVisibility = SOOMTabBarVisibility()
    @Namespace private var tabBarNamespace

    init() {
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(name: SOOMFont.displayBoldName, size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: UIColor(SOOMColor.ink)
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFont(name: SOOMFont.displayMediumName, size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: UIColor(SOOMColor.ink)
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            selectedContent
                .environmentObject(tabBarVisibility)
                .environment(\.soomBottomOverlayInset, tabBarVisibility.isHidden ? 0 : SOOMLayout.TabBar.bottomOverlayInset + 72)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SOOMColor.background.ignoresSafeArea())

            if !tabBarVisibility.isHidden {
                FloatingRecoveryCoach(shouldShowInitialPreview: $shouldShowInitialCoachPreview)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, SOOMLayout.FloatingCoach.trailingPadding)
                    .padding(.bottom, SOOMLayout.TabBar.bottomOverlayInset + SOOMLayout.FloatingCoach.bottomPaddingAboveTab)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }

            if !tabBarVisibility.isHidden {
                SOOMBottomTabBar(
                    selectedTab: $selectedTab,
                    namespace: tabBarNamespace,
                    onRecordSelected: {
                        SOOMHaptics.softImpact()
                        isRecordLaunchPresented = true
                    }
                )
                    .padding(.horizontal, SOOMLayout.TabBar.outerHorizontalPadding)
                    .padding(.bottom, SOOMLayout.TabBar.bottomPadding)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(SOOMColor.background.ignoresSafeArea())
        // SOOM v1 keeps Light Mode only while the visual system stabilizes.
        .preferredColorScheme(.light)
        .environment(\.font, SOOMFont.body(15, relativeTo: .body))
        .sensoryFeedback(.selection, trigger: selectedTab)
        .animation(.easeOut(duration: SOOMMotion.Duration.normal), value: tabBarVisibility.isHidden)
        .fullScreenCover(isPresented: $isRecordLaunchPresented, onDismiss: {
            selectedTab = shouldReturnToActivityAfterRecordSave ? .activity : .feed
            shouldReturnToActivityAfterRecordSave = false
        }) {
            NavigationStack {
                RecordView(
                    onDismiss: {
                        shouldReturnToActivityAfterRecordSave = false
                        selectedTab = .feed
                        isRecordLaunchPresented = false
                    },
                    onSaveComplete: {
                        shouldReturnToActivityAfterRecordSave = true
                        isRecordLaunchPresented = false
                    }
                )
            }
            .preferredColorScheme(.light)
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .feed:
            NavigationStack {
                FeedView()
            }
        case .record:
            NavigationStack {
                RecordView()
            }
        case .activity:
            NavigationStack {
                ActivityView()
            }
        case .clubs:
            NavigationStack {
                ClubsView()
            }
        case .profile:
            NavigationStack {
                SettingsView()
            }
        }
    }
}

private struct FloatingRecoveryCoach: View {
    @Binding var shouldShowInitialPreview: Bool
    @State private var isExpanded = false
    @State private var dismissedUntil: Date?
    @State private var isPreviewVisible = false
    @State private var didScheduleInitialPreview = false
    @State private var typedCoachMessage = ""
    @State private var typingTask: Task<Void, Never>?
    @State private var selectedSheetDetent: PresentationDetent = .height(368)
    @State private var isDetailExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let compactSheetDetent: PresentationDetent = .height(368)
    private static let expandedSheetDetent: PresentationDetent = .fraction(0.70)

    private var summary: RecoverySummary {
        .mockToday
    }

    private var coachMessage: String {
        "오늘은 무리하지 않아도 좋아요.\n가볍게 이어가도 충분해요."
    }

    private var sheetDetents: Set<PresentationDetent> {
        [Self.compactSheetDetent, Self.expandedSheetDetent]
    }

    private var isDismissed: Bool {
        if let dismissedUntil {
            return Date() < dismissedUntil
        }
        return false
    }

    var body: some View {
        if !isDismissed {
            HStack(alignment: .bottom, spacing: 10) {
                if isPreviewVisible {
                    coachPreview
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)),
                                removal: .opacity.combined(with: .move(edge: .trailing))
                            )
                        )
                }

                circularButton
            }
            .task {
                await showInitialPreviewIfNeeded()
            }
            .sheet(isPresented: $isExpanded) {
                coachSheet
                    .presentationDetents(sheetDetents, selection: $selectedSheetDetent)
                    .presentationDragIndicator(.visible)
            }
            .animation(reduceMotion ? nil : SOOMMotion.coachSpring, value: isPreviewVisible)
            .animation(reduceMotion ? nil : SOOMMotion.coachSpring, value: isDismissed)
        }
    }

    private var coachPreview: some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Button {
                collapsePreview()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("회복 리듬 확인")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                    Text("오늘은 가볍게 시작해도 좋아요")
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                collapsePreview()
            } label: {
                Image(systemName: SOOMIcon.close)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("회복 코치 미리보기 닫기")
        }
        .padding(.horizontal, SOOMLayout.FloatingCoach.previewHorizontalPadding)
        .padding(.vertical, SOOMLayout.FloatingCoach.previewVerticalPadding)
        .frame(maxWidth: SOOMLayout.FloatingCoach.previewMaxWidth, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.58), lineWidth: 1)
        }
        .shadow(color: SOOMColor.ink.opacity(0.055), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("회복 코치 미리보기")
        .accessibilityValue("오늘은 가볍게 시작해도 좋아요")
    }

    private var circularButton: some View {
        Button {
            collapsePreview()
            SOOMHaptics.softImpact()
            selectedSheetDetent = Self.compactSheetDetent
            isDetailExpanded = false
            isExpanded = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(SOOMColor.recovery)
                    .overlay {
                        Circle()
                            .stroke(SOOMColor.white, lineWidth: 1.25)
                    }

                companionMark
                    .accessibilityHidden(true)

                Text("\(summary.score)")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.ink)
                    .frame(width: SOOMLayout.FloatingCoach.scoreBadgeSize, height: SOOMLayout.FloatingCoach.scoreBadgeSize)
                    .background(SOOMColor.white)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(SOOMColor.recovery, lineWidth: 1.2)
                    }
                    .shadow(color: SOOMColor.ink.opacity(0.10), radius: 4, x: 0, y: 2)
                    .padding(2)
            }
            .frame(width: SOOMLayout.FloatingCoach.buttonSize, height: SOOMLayout.FloatingCoach.buttonSize)
            .shadow(color: SOOMColor.ink.opacity(0.12), radius: 14, x: 0, y: 8)
            .contentShape(Circle())
        }
        .buttonStyle(FloatingCoachButtonStyle())
        .accessibilityLabel("회복 코치 열기")
        .accessibilityValue("\(summary.score)점, \(summary.recommendation)")
    }

    private var companionMark: some View {
        ZStack {
            Circle()
                .trim(from: 0.06, to: 0.40)
                .stroke(SOOMColor.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 45, height: 45)
                .rotationEffect(.degrees(-18))

            Circle()
                .trim(from: 0.57, to: 0.91)
                .stroke(SOOMColor.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 45, height: 45)
                .rotationEffect(.degrees(-18))

            Circle()
                .stroke(SOOMColor.white, lineWidth: 1.3)
                .frame(width: 31, height: 31)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(SOOMColor.white)
                        .frame(width: 5.2, height: 5.2)
                    Circle()
                        .fill(SOOMColor.white)
                        .frame(width: 5.2, height: 5.2)
                }

                Capsule()
                    .fill(SOOMColor.white)
                    .frame(width: 14, height: 3)
                    .offset(y: -1)
            }
        }
        .frame(width: 48, height: 48)
    }

    private func collapsePreview() {
        withAnimation(reduceMotion ? nil : SOOMMotion.coachSpring) {
            isPreviewVisible = false
        }
    }

    private func showInitialPreviewIfNeeded() async {
        guard !didScheduleInitialPreview, shouldShowInitialPreview, !isDismissed else {
            return
        }
        didScheduleInitialPreview = true
        shouldShowInitialPreview = false

        await MainActor.run {
            withAnimation(reduceMotion ? nil : SOOMMotion.coachSpring) {
                isPreviewVisible = true
            }
        }

        let delay = UInt64(SOOMLayout.FloatingCoach.previewAutoCollapseDelaySeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: delay)

        guard !Task.isCancelled, !isExpanded, !isDismissed else {
            return
        }

        await MainActor.run {
            collapsePreview()
        }
    }

    private func hideUntil(_ date: Date) {
        dismissedUntil = date
        collapsePreview()
        isExpanded = false
        isDetailExpanded = false
        stopTypingCoachMessage(reset: true)
    }

    private struct FloatingCoachButtonStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(configuration.isPressed ? 0.92 : 1)
                .animation(reduceMotion ? nil : SOOMMotion.cardPress, value: configuration.isPressed)
        }
    }

    private var coachSheet: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 18) {
                Text("회복 코치")
                    .font(SOOMFont.body(17, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 6) {
                    Text("오늘의 회복 리듬")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .textCase(.uppercase)

                    Text("\(summary.score)")
                        .font(SOOMFont.display(54, relativeTo: .largeTitle))
                        .foregroundStyle(SOOMColor.recovery)
                        .accessibilityLabel("회복 점수 \(summary.score)")

                    Text(summary.status)
                        .font(SOOMFont.displayMedium(23, relativeTo: .title3))
                        .foregroundStyle(SOOMColor.ink)
                }

                Text(typedCoachMessage.isEmpty ? " " : typedCoachMessage)
                    .font(SOOMFont.displayMedium(18, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .fixedSize(horizontal: false, vertical: true)

                if isDetailExpanded {
                    expandedCoachContext
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                actionArea
                    .padding(.top, isDetailExpanded ? 4 : 12)
            }
            .padding(.horizontal, SOOMLayout.screenPadding)
            .padding(.top, SOOMLayout.screenPadding + 4)
            .padding(.bottom, SOOMLayout.screenPadding + 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SOOMColor.background)
        .animation(reduceMotion ? nil : SOOMMotion.coachSpring, value: isDetailExpanded)
        .onAppear {
            startTypingCoachMessage()
        }
        .onDisappear {
            stopTypingCoachMessage(reset: true)
            isDetailExpanded = false
            selectedSheetDetent = Self.compactSheetDetent
        }
    }

    private var expandedCoachContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            recoveryContextRow(title: "오늘의 방향", value: "가볍게 이어가기")
            recoveryContextRow(title: "리듬", value: "무리한 강도보다 호흡 유지")
            recoveryContextRow(title: "추천", value: "짧은 산책이나 낮은 강도의 러닝")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.7), lineWidth: 1)
        }
    }

    private func recoveryContextRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.tertiaryInk)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                hideForOneHourButton
                hideForTodayButton
            }
            .frame(maxWidth: .infinity)

            coachDetailButton
        }
        .padding(.bottom, 4)
    }

    private var coachDetailButton: some View {
        Button {
            SOOMHaptics.softImpact()
            withAnimation(reduceMotion ? nil : SOOMMotion.coachSpring) {
                isDetailExpanded = true
                selectedSheetDetent = Self.expandedSheetDetent
            }
        } label: {
            Text(isDetailExpanded ? "자세히 보는 중" : "자세히 보기")
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(SOOMColor.recovery)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDetailExpanded)
    }

    private var hideForOneHourButton: some View {
        Button("1시간 숨기기") {
            SOOMHaptics.selection()
            hideUntil(Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date())
        }
        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
        .foregroundStyle(SOOMColor.secondaryInk)
    }

    private var hideForTodayButton: some View {
        Button("오늘 숨기기") {
            SOOMHaptics.selection()
            let endOfDay = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
            hideUntil(endOfDay)
        }
        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
        .foregroundStyle(SOOMColor.secondaryInk)
    }

    private func startTypingCoachMessage() {
        typingTask?.cancel()

        guard reduceMotion == false else {
            typedCoachMessage = coachMessage
            return
        }

        typedCoachMessage = ""
        let characters = Array(coachMessage)
        typingTask = Task {
            var wasInsideWord = false

            for index in characters.indices {
                let character = characters[index]
                let isWordCharacter = isTypingWordCharacter(character)
                let isWordStart = isWordCharacter && !wasInsideWord

                if isWordStart {
                    await MainActor.run {
                        SOOMHaptics.typingWordStart()
                    }
                }

                try? await Task.sleep(nanoseconds: 78_000_000)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    typedCoachMessage.append(character)
                }

                let isLastCharacter = index == characters.index(before: characters.endIndex)
                let nextCharacter = isLastCharacter ? nil : characters[characters.index(after: index)]
                let isWordEnd = isWordCharacter && (nextCharacter.map(isTypingWordCharacter) != true)
                wasInsideWord = isWordCharacter

                if isWordEnd && !isLastCharacter {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                }
            }
        }
    }

    private func stopTypingCoachMessage(reset: Bool) {
        typingTask?.cancel()
        typingTask = nil
        if reset {
            typedCoachMessage = ""
        }
    }

    private func isTypingWordCharacter(_ character: Character) -> Bool {
        guard reduceMotion == false else {
            return false
        }

        let scalars = character.unicodeScalars
        return scalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
            CharacterSet.punctuationCharacters.contains(scalar) == false
        }
    }
}

private struct ActivityView: View {
    @EnvironmentObject private var dashboardViewModel: DashboardViewModel

    var body: some View {
        SOOMScreen {
            header
            workoutHistorySection
            localSavedWorkoutSection
            importedWorkoutSection
            analysisEntrySection
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("내 운동 기록을 먼저 보고, 분석은 각 운동의 상세 흐름 안에서 확인합니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var workoutHistorySection: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
            SOOMSectionHeader("최근 운동", caption: "route, split, terrain, climb, zone, recovery impact는 상세에서 이어집니다.")

            if dashboardViewModel.workouts.isEmpty {
                SOOMFirstJourneyCard(
                    prompt: .activity,
                    actions: [
                        SOOMFirstJourneyAction(
                            title: "첫 운동 가져오기",
                            subtitle: "HealthKit에서 불러온 기록은 상세 흐름의 시작점이 됩니다.",
                            iconName: SOOMIcon.sync
                        ),
                        SOOMFirstJourneyAction(
                            title: "route preview 보기",
                            subtitle: "기록이 생기면 길, split, terrain이 차례로 열립니다.",
                            iconName: SOOMIcon.map
                        )
                    ],
                    footer: "0을 크게 보여주기보다, 첫 움직임이 남을 자리를 비워둡니다."
                )
            } else {
                ForEach(dashboardViewModel.workouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout, comparisonWorkouts: dashboardViewModel.workouts)
                    } label: {
                        SOOMCard {
                            SOOMActionRow(
                                icon: workout.sport.iconName,
                                title: workout.title,
                                subtitle: "\(workout.formattedDistance) · \(workout.formattedDuration) · \(workout.formattedPace)",
                                tint: workout.sport.tint
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("운동 상세 분석 화면으로 이동합니다.")
                }
            }
        }
    }

    private var importedWorkoutSection: some View {
        SOOMCard {
            SOOMSectionHeader("가져온 기록", caption: "HealthKit에서 가져온 운동과 분석 제외 상태를 관리합니다.")

            NavigationLink {
                UnifiedWorkoutLibraryViewContainer()
            } label: {
                SOOMActionRow(
                    icon: SOOMIcon.package,
                    title: "운동 라이브러리",
                    subtitle: "저장된 운동 기록, route 재사용, 상세 분석 진입을 확인합니다.",
                    tint: SOOMColor.bike
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var localSavedWorkoutSection: some View {
        LocalSavedWorkoutSection()
    }

    private var analysisEntrySection: some View {
        SOOMCard {
            SOOMSectionHeader("최근 흐름", caption: "주간/월간 분석은 별도 탭이 아니라 내 활동의 보조 레이어로 둡니다.")

            NavigationLink {
                AnalysisViewContainer()
            } label: {
                SOOMActionRow(
                    icon: SOOMIcon.chartLine,
                    title: "성장 리포트 보기",
                    subtitle: "주간 흐름, 개인 기록, progression intelligence를 조용히 확인합니다.",
                    tint: SOOMColor.secondaryInk
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct LocalSavedWorkoutSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var workouts: [UnifiedWorkout] = []

    var body: some View {
        if !workouts.isEmpty {
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                SOOMSectionHeader("Record에서 저장한 운동", caption: "방금 저장한 local-first 기록입니다. 자세한 관리는 운동 라이브러리에서 이어집니다.")

                ForEach(workouts.prefix(3)) { workout in
                    NavigationLink {
                        UnifiedWorkoutLibraryViewContainer()
                    } label: {
                        SOOMCard {
                            SOOMActionRow(
                                icon: iconName(for: workout.workoutType),
                                title: "\(displayName(for: workout.workoutType)) 저장됨",
                                subtitle: "\(dateText(workout.startDate)) · \(durationText(workout.durationSeconds)) · \(distanceText(workout.distanceMeters))",
                                tint: tint(for: workout.workoutType)
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("운동 라이브러리에서 저장된 운동을 확인합니다.")
                }
            }
            .task {
                await loadWorkouts()
            }
        } else {
            EmptyView()
                .task {
                    await loadWorkouts()
                }
        }
    }

    @MainActor
    private func loadWorkouts() async {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        workouts = (try? await store.fetchRecentWorkouts(days: 30))
            .map { recent in
                recent
                    .filter { $0.source == .soomLocal }
                    .sorted { $0.startDate > $1.startDate }
            } ?? []
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M.d HH:mm"
        return formatter.string(from: date)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }

        return "\(minutes)분"
    }

    private func distanceText(_ distanceMeters: Double?) -> String {
        guard let distanceMeters else {
            return "거리 없음"
        }

        return String(format: "%.1f km", distanceMeters / 1_000)
    }

    private func tint(for workoutType: UnifiedWorkoutType) -> Color {
        switch workoutType {
        case .cycling:
            return SOOMColor.bike
        case .running:
            return SOOMColor.run
        case .walking:
            return SOOMColor.blue
        default:
            return SOOMColor.secondaryInk
        }
    }

    private func displayName(for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .running:
            return "러닝"
        case .cycling:
            return "라이딩"
        case .walking:
            return "걷기"
        case .swimming:
            return "수영"
        case .hiking:
            return "하이킹"
        case .strength:
            return "근력"
        case .yoga:
            return "요가"
        case .other:
            return "운동"
        }
    }

    private func iconName(for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .running:
            return SOOMIcon.run
        case .cycling:
            return SOOMIcon.bike
        case .walking:
            return "figure.walk"
        case .swimming:
            return "figure.pool.swim"
        case .hiking:
            return "figure.hiking"
        case .strength:
            return "dumbbell"
        case .yoga:
            return "figure.mind.and.body"
        case .other:
            return SOOMIcon.activity
        }
    }
}

private struct SOOMBottomTabBar: View {
    @Binding var selectedTab: SOOMTab
    let namespace: Namespace.ID
    let onRecordSelected: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SOOMTab.allCases) { tab in
                Button {
                    if tab == .record {
                        onRecordSelected()
                    } else {
                        SOOMHaptics.selection()
                        withAnimation(SOOMMotion.quickEaseOut) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    SOOMBottomTabItem(tab: tab, isSelected: selectedTab == tab, namespace: namespace)
                }
                .buttonStyle(LiquidTabButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: SOOMLayout.TabBar.height)
        .padding(.horizontal, SOOMLayout.TabBar.containerHorizontalPadding)
        .padding(.vertical, SOOMLayout.TabBar.containerVerticalPadding)
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SOOMColor.white.opacity(0.46),
                                SOOMColor.white.opacity(0.18),
                                SOOMColor.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                SOOMColor.white.opacity(0.52),
                                SOOMColor.ink.opacity(0.05),
                                SOOMColor.white.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: SOOMColor.ink.opacity(0.07), radius: SOOMLayout.TabBar.containerShadowRadius, x: 0, y: SOOMLayout.TabBar.containerShadowYOffset)
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(SOOMColor.white.opacity(0.48))
                .frame(height: SOOMLayout.TabBar.topHighlightHeight)
                .padding(.horizontal, SOOMLayout.TabBar.topHighlightHorizontalPadding)
                .offset(y: 1.5)
        }
        .overlay(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(SOOMColor.ink.opacity(0.04))
                .frame(height: SOOMLayout.TabBar.bottomHighlightHeight)
                .padding(.horizontal, SOOMLayout.TabBar.bottomHighlightHorizontalPadding)
                .offset(y: -1)
        }
        .compositingGroup()
    }
}

private struct SOOMBottomTabItem: View {
    let tab: SOOMTab
    let isSelected: Bool
    let namespace: Namespace.ID

    var body: some View {
        if tab == .record {
            recordItem
        } else {
            standardItem
        }
    }

    private var standardItem: some View {
        ZStack {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        SOOMColor.white.opacity(0.58),
                                        SOOMColor.white.opacity(0.18),
                                        SOOMColor.ink.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(SOOMColor.white.opacity(0.56), lineWidth: 1)
                    }
                    .shadow(color: SOOMColor.ink.opacity(0.04), radius: SOOMLayout.TabBar.selectedShadowRadius, x: 0, y: 4)
                    .matchedGeometryEffect(id: "selectedLiquidTab", in: namespace)
            }

            VStack(spacing: SOOMLayout.TabBar.itemLabelSpacing) {
                Image(systemName: tab.iconName)
                    .font(.system(size: tab == .record ? SOOMLayout.TabBar.recordIconSize : SOOMLayout.TabBar.defaultIconSize, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: SOOMLayout.TabBar.iconHeight)
                    .scaleEffect(isSelected ? SOOMLayout.TabBar.selectedIconScale : SOOMLayout.TabBar.normalIconScale)

                Text(tab.title)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .lineLimit(1)
                    .opacity(isSelected ? 1 : 0.74)
            }
        }
        .foregroundStyle(isSelected ? SOOMColor.ink : SOOMColor.ink.opacity(0.56))
        .frame(maxWidth: .infinity)
        .frame(height: SOOMLayout.TabBar.itemHeight)
        .contentShape(RoundedRectangle(cornerRadius: SOOMLayout.TabBar.itemCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
        .animation(SOOMMotion.quickEaseOut, value: isSelected)
    }

    private var recordItem: some View {
        ZStack {
            Circle()
                .fill(SOOMColor.recovery)
                .overlay {
                    Circle()
                        .stroke(SOOMColor.white.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: SOOMColor.recovery.opacity(isSelected ? 0.26 : 0.14), radius: 10, x: 0, y: 5)

            Image(systemName: tab.iconName)
                .font(.system(size: 26, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(SOOMColor.white)
        }
        .frame(width: 58, height: 58)
        .scaleEffect(isSelected ? 1.04 : 1)
        .frame(maxWidth: .infinity)
        .frame(height: SOOMLayout.TabBar.itemHeight)
        .offset(y: -10)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("운동 기록 시작")
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
        .animation(SOOMMotion.quickEaseOut, value: isSelected)
    }
}

private struct LiquidTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? SOOMLayout.TabBar.pressScale : 1)
            .animation(SOOMMotion.quickEaseOut, value: configuration.isPressed)
    }
}

private struct SOOMTabBarHiddenModifier: ViewModifier {
    @EnvironmentObject private var visibility: SOOMTabBarVisibility

    func body(content: Content) -> some View {
        content
            .onAppear {
                visibility.isHidden = true
            }
            .onDisappear {
                visibility.isHidden = false
            }
    }
}

extension View {
    func hidesSOOMTabBar() -> some View {
        modifier(SOOMTabBarHiddenModifier())
    }
}
