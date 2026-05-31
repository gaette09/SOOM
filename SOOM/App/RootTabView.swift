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
                .environment(\.soomBottomOverlayInset, bottomOverlayInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SOOMColor.background.ignoresSafeArea())

            if shouldShowFloatingCoach {
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
                    },
                    onShareDraftComplete: {
                        shouldReturnToActivityAfterRecordSave = false
                        selectedTab = .feed
                        isRecordLaunchPresented = false
                    }
                )
            }
            .preferredColorScheme(.light)
        }
    }

    private var shouldShowFloatingCoach: Bool {
        !tabBarVisibility.isHidden && selectedTab != .activity && selectedTab != .clubs
    }

    private var bottomOverlayInset: CGFloat {
        guard !tabBarVisibility.isHidden else { return 0 }
        return shouldShowFloatingCoach
            ? SOOMLayout.TabBar.bottomOverlayInset + 72
            : SOOMLayout.TabBar.bottomOverlayInset
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
                    .fill(SOOMColor.accent)
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
                            .stroke(SOOMColor.accent, lineWidth: 1.2)
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
                        .foregroundStyle(SOOMColor.accent)
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
                .background(SOOMColor.accent)
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
    @Environment(\.modelContext) private var modelContext
    @State private var savedWorkouts: [UnifiedWorkout] = []

    var body: some View {
        SOOMScreen {
            activityCalendarSection
            recentChangeSection
            recentWorkoutSection
            favoriteRoutesSection
            statisticsSection
            libraryManagementSection
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadSavedWorkouts()
        }
    }

    private var libraryEntries: [ActivityLibraryEntry] {
        let dashboardEntries = dashboardViewModel.workouts.map(ActivityLibraryEntry.make)
        let savedEntries = savedWorkouts.map(ActivityLibraryEntry.make)

        return (savedEntries + dashboardEntries)
            .sorted { $0.date > $1.date }
    }

    private var activityCalendarSection: some View {
        ActivityCalendarSection(entries: libraryEntries)
    }

    private var recentWorkoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SOOMSectionHeader("최근 운동", caption: "최근 저장된 움직임을 도서관 서가처럼 모아봅니다.")

            if libraryEntries.isEmpty {
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
                ForEach(libraryEntries.prefix(5)) { entry in
                    recentWorkoutLink(for: entry)
                }
            }
        }
    }

    private var recentChangeSection: some View {
        SOOMCard(depth: .ambient) {
            SOOMSectionHeader("최근 변화", caption: "숫자보다 방향을 먼저 봅니다.")

            HStack(spacing: 10) {
                ActivityDirectionPill(title: "꾸준함", value: "↑", tint: SOOMColor.accent)
                ActivityDirectionPill(title: "회복", value: "→", tint: SOOMColor.accent)
                ActivityDirectionPill(title: "운동 시간", value: "↑", tint: SOOMColor.accent)
            }
        }
    }

    private var favoriteRoutesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SOOMSectionHeader("자주 가는 코스", caption: "자주 남은 길을 도서관처럼 모아둡니다.")

            HStack(spacing: 10) {
                ActivityRouteCard(title: "한강 북단", count: "12회", tint: SOOMColor.accent)
                ActivityRouteCard(title: "탄천", count: "8회", tint: SOOMColor.accent)
                ActivityRouteCard(title: "북악", count: "3회", tint: SOOMColor.accent)
            }
        }
    }

    private var statisticsSection: some View {
        SOOMCard(depth: .ambient) {
            SOOMSectionHeader("통계", caption: "도서관의 작은 인덱스처럼 하단에 둡니다.")

            HStack(spacing: 10) {
                ActivityStatTile(title: "운동 횟수", value: "\(libraryEntries.count)")
                ActivityStatTile(title: "운동 시간", value: totalDurationText)
                ActivityStatTile(title: "총 거리", value: totalDistanceText)
            }
        }
    }

    private var libraryManagementSection: some View {
        SOOMCard {
            SOOMSectionHeader("운동 라이브러리 관리", caption: "HealthKit 가져오기, 분석 제외, 상세 분석 진입은 이곳에서 정리합니다.")

            NavigationLink {
                UnifiedWorkoutLibraryViewContainer()
            } label: {
                SOOMActionRow(
                    icon: SOOMIcon.package,
                    title: "운동 라이브러리",
                    subtitle: "저장된 운동 기록, route 재사용, 상세 분석 진입을 확인합니다.",
                    tint: SOOMColor.accent
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func recentWorkoutLink(for entry: ActivityLibraryEntry) -> some View {
        switch entry.destination {
        case .workout(let workout):
            NavigationLink {
                WorkoutDetailView(workout: workout, comparisonWorkouts: dashboardViewModel.workouts)
            } label: {
                ActivityWorkoutLibraryCard(entry: entry)
            }
            .buttonStyle(.plain)
            .accessibilityHint("운동 상세 흐름으로 이동합니다.")
        case .library:
            NavigationLink {
                UnifiedWorkoutLibraryViewContainer()
            } label: {
                ActivityWorkoutLibraryCard(entry: entry)
            }
            .buttonStyle(.plain)
            .accessibilityHint("운동 라이브러리에서 저장된 운동을 확인합니다.")
        }
    }

    private var totalDurationText: String {
        let totalSeconds = libraryEntries.reduce(0) { $0 + $1.durationSeconds }
        let hours = Int(totalSeconds / 3_600)
        let minutes = Int(totalSeconds.truncatingRemainder(dividingBy: 3_600) / 60)

        if hours > 0 {
            return "\(hours)시간"
        }

        return "\(minutes)분"
    }

    private var totalDistanceText: String {
        let totalMeters = libraryEntries.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
        guard totalMeters > 0 else { return "0 km" }

        return String(format: "%.1f km", totalMeters / 1_000)
    }

    @MainActor
    private func loadSavedWorkouts() async {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        savedWorkouts = (try? await store.fetchRecentWorkouts(days: 180)) ?? []
    }
}

private enum ActivityCalendarMode: String, CaseIterable, Identifiable {
    case month
    case week
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month:
            return "월"
        case .week:
            return "주"
        case .list:
            return "목록"
        }
    }
}

private enum ActivityLibraryDestination {
    case workout(Workout)
    case library
}

private struct ActivityLibraryEntry: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let typeTitle: String
    let iconName: String
    let tint: Color
    let distanceMeters: Double?
    let durationSeconds: TimeInterval
    let routePoints: [RoutePoint]
    let destination: ActivityLibraryDestination

    var distanceText: String {
        guard let distanceMeters, distanceMeters > 0 else { return "기록 준비 중" }
        if distanceMeters < 1_000 {
            return "\(Int(distanceMeters)) m"
        }
        return String(format: "%.1f km", distanceMeters / 1_000)
    }

    var durationText: String {
        let totalMinutes = max(0, Int(durationSeconds / 60))
        guard totalMinutes > 0 else { return "기록 준비 중" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }

        return "\(minutes)분"
    }

    var compactEvidence: [(title: String, value: String)] {
        var items: [(String, String)] = []

        if let distanceMeters, distanceMeters > 0 {
            items.append(("거리", distanceText))
        }

        if durationSeconds >= 60 {
            items.append(("시간", durationText))
        }

        items.append(("날짜", compactDateText))
        return items
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M.d HH:mm"
        return formatter.string(from: date)
    }

    var compactDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M.d"
        return formatter.string(from: date)
    }

    static func make(from workout: Workout) -> ActivityLibraryEntry {
        ActivityLibraryEntry(
            id: workout.id,
            title: workout.title,
            date: workout.date,
            typeTitle: workout.sport.title,
            iconName: workout.sport.iconName,
            tint: workout.sport.tint,
            distanceMeters: workout.distanceMeters,
            durationSeconds: workout.duration,
            routePoints: workout.route,
            destination: .workout(workout)
        )
    }

    static func make(from workout: UnifiedWorkout) -> ActivityLibraryEntry {
        ActivityLibraryEntry(
            id: workout.id,
            title: "\(displayName(for: workout.workoutType)) 기록",
            date: workout.startDate,
            typeTitle: displayName(for: workout.workoutType),
            iconName: iconName(for: workout.workoutType),
            tint: tint(for: workout.workoutType),
            distanceMeters: workout.distanceMeters,
            durationSeconds: workout.durationSeconds,
            routePoints: [],
            destination: .library
        )
    }

    private static func displayName(for workoutType: UnifiedWorkoutType) -> String {
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

    private static func iconName(for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .running:
            return SOOMIcon.run
        case .cycling:
            return SOOMIcon.bike
        case .walking:
            return "figure.walk"
        case .swimming:
            return SOOMIcon.swim
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

    private static func tint(for workoutType: UnifiedWorkoutType) -> Color {
        switch workoutType {
        case .walking:
            return Color(hex: 0x9FC8A8)
        case .running:
            return SOOMColor.run
        case .cycling:
            return SOOMColor.bike
        default:
            return SOOMColor.secondaryInk
        }
    }
}

private struct ActivityCalendarSection: View {
    let entries: [ActivityLibraryEntry]
    @State private var mode: ActivityCalendarMode = .month

    var body: some View {
        SOOMCard(depth: .primary) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("운동 도서관")
                            .font(SOOMFont.displayMedium(24, relativeTo: .title2))
                            .foregroundStyle(SOOMColor.ink)
                        Text("언제, 어떤 움직임이 남았는지 먼저 봅니다.")
                            .font(SOOMFont.body(13, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        ForEach(ActivityCalendarMode.allCases) { calendarMode in
                            Button {
                                mode = calendarMode
                                SOOMHaptics.selection()
                            } label: {
                                Text(calendarMode.title)
                                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                                    .foregroundStyle(mode == calendarMode ? SOOMColor.selectedInk : SOOMColor.secondaryInk)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 7)
                                    .background(mode == calendarMode ? SOOMColor.selectedSurface : SOOMColor.surfaceMuted)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                switch mode {
                case .month:
                    monthGrid
                case .week:
                    weekStrip
                case .list:
                    dateList
                }

                calendarLegend
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 9) {
            ForEach(monthDays, id: \.self) { date in
                calendarDayCell(date)
            }
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 7) {
            ForEach(weekDays, id: \.self) { date in
                calendarDayCell(date)
            }
        }
    }

    private var dateList: some View {
        VStack(spacing: 8) {
            ForEach(entries.prefix(5)) { entry in
                HStack(spacing: 10) {
                    Circle()
                        .fill(entry.tint)
                        .frame(width: 8, height: 8)

                    Text(entry.dateText)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)

                    Text(entry.title)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }

            if entries.isEmpty {
                Text("첫 운동이 저장되면 이곳에 날짜가 쌓입니다.")
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
        }
    }

    private var calendarLegend: some View {
        HStack(spacing: 12) {
            legendDot(title: "걷기", color: Color(hex: 0x9FC8A8))
            legendDot(title: "러닝", color: SOOMColor.run)
            legendDot(title: "라이딩", color: SOOMColor.bike)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calendarDayCell(_ date: Date) -> some View {
        let dayEntries = entries(on: date)

        return VStack(spacing: 5) {
            Text(dayNumber(for: date))
                .font(SOOMFont.body(11, weight: dayEntries.isEmpty ? .regular : .bold, relativeTo: .caption2))
                .foregroundStyle(dayEntries.isEmpty ? SOOMColor.secondaryInk : SOOMColor.ink)
                .monospacedDigit()

            HStack(spacing: 2) {
                ForEach(Array(dayEntries.prefix(3).enumerated()), id: \.offset) { _, entry in
                    Circle()
                        .fill(entry.tint)
                        .frame(width: 4.5, height: 4.5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(dayEntries.isEmpty ? SOOMColor.surfaceMuted.opacity(0.55) : SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func legendDot(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
    }

    private func entries(on date: Date) -> [ActivityLibraryEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private var monthDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<28).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 27, to: today)
        }
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 6, to: today)
        }
    }

    private func dayNumber(for date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return "\(day)"
    }
}

private struct ActivityWorkoutLibraryCard: View {
    let entry: ActivityLibraryEntry

    var body: some View {
        SOOMCard(depth: .secondary) {
            HStack(spacing: 12) {
                ActivityCompactMediaStrip(entry: entry)
                    .frame(width: 116, height: 82)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Image(systemName: entry.iconName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(entry.tint)
                            .frame(width: 24, height: 24)
                            .background(entry.tint.opacity(0.12))
                            .clipShape(Circle())

                        Text(entry.typeTitle)
                            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(entry.tint)

                        Text(entry.dateText)
                            .font(SOOMFont.body(11, relativeTo: .caption2))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .lineLimit(1)
                    }

                    Text(entry.title)
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        ForEach(Array(entry.compactEvidence.enumerated()), id: \.offset) { _, item in
                            ActivityMetricEvidence(title: item.title, value: item.value)
                        }

                        if entry.compactEvidence.count == 1 {
                            ActivityMetricEvidence(title: "상태", value: "기록 준비 중")
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 92)
        }
    }
}

private struct ActivityCompactMediaStrip: View {
    let entry: ActivityLibraryEntry

    var body: some View {
        HStack(spacing: 5) {
            ActivityRoutePreview(points: entry.routePoints, tint: entry.tint, showsLabel: false)
                .frame(width: 72)

            ActivityPhotoThumbnail(tint: entry.tint, showsLabel: false)
                .frame(width: 39)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ActivityRoutePreview: View {
    let points: [RoutePoint]
    let tint: Color
    var showsLabel: Bool = true

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xDDE8DC),
                                Color(hex: 0xEFF0E8),
                                Color(hex: 0xD5DFD3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                ActivityMapTexture()
                    .stroke(SOOMColor.white.opacity(0.55), style: StrokeStyle(lineWidth: 7, lineCap: .round))

                ActivityRouteShape(points: normalizedPoints)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: tint.opacity(0.16), radius: 5, x: 0, y: 3)
                    .padding(18)

                routeDot(at: normalizedPoints.first ?? CGPoint(x: 0.18, y: 0.72), color: SOOMColor.white, in: proxy.size)
                routeDot(at: normalizedPoints.last ?? CGPoint(x: 0.82, y: 0.32), color: tint, in: proxy.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if showsLabel {
                    Text(points.isEmpty ? "route 준비" : "route")
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(SOOMColor.surface.opacity(0.86))
                        .clipShape(Capsule())
                        .padding(9)
                }
            }
        }
    }

    private var normalizedPoints: [CGPoint] {
        guard points.count >= 2 else {
            return [
                CGPoint(x: 0.12, y: 0.70),
                CGPoint(x: 0.28, y: 0.58),
                CGPoint(x: 0.44, y: 0.62),
                CGPoint(x: 0.62, y: 0.42),
                CGPoint(x: 0.85, y: 0.30)
            ]
        }

        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let minLatitude = latitudes.min() ?? 0
        let maxLatitude = latitudes.max() ?? 1
        let minLongitude = longitudes.min() ?? 0
        let maxLongitude = longitudes.max() ?? 1
        let latitudeRange = max(maxLatitude - minLatitude, 0.000_001)
        let longitudeRange = max(maxLongitude - minLongitude, 0.000_001)

        return points.map { point in
            CGPoint(
                x: 0.10 + CGFloat((point.longitude - minLongitude) / longitudeRange) * 0.80,
                y: 0.86 - CGFloat((point.latitude - minLatitude) / latitudeRange) * 0.72
            )
        }
    }

    private func routeDot(at normalizedPoint: CGPoint, color: Color, in size: CGSize) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay {
                Circle().stroke(SOOMColor.ink.opacity(0.14), lineWidth: 1)
            }
            .position(
                x: normalizedPoint.x * size.width,
                y: normalizedPoint.y * size.height
            )
    }
}

private struct ActivityRouteShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))

        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }

        return path
    }
}

private struct ActivityMapTexture: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 20, y: rect.midY * 0.82))
        path.addCurve(
            to: CGPoint(x: rect.maxX + 20, y: rect.midY * 1.12),
            control1: CGPoint(x: rect.width * 0.22, y: rect.minY + rect.height * 0.30),
            control2: CGPoint(x: rect.width * 0.70, y: rect.minY + rect.height * 0.72)
        )
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY + 12))
        path.addCurve(
            to: CGPoint(x: rect.maxX + 12, y: rect.minY + rect.height * 0.26),
            control1: CGPoint(x: rect.width * 0.34, y: rect.height * 0.76),
            control2: CGPoint(x: rect.width * 0.58, y: rect.height * 0.14)
        )
        return path
    }
}

private struct ActivityPhotoThumbnail: View {
    let tint: Color
    var showsLabel: Bool = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.24),
                            Color(hex: 0xEEF0E7),
                            Color(hex: 0xC9D7C4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: SOOMIcon.map)
                .font(.system(size: showsLabel ? 22 : 15, weight: .semibold))
                .foregroundStyle(SOOMColor.white.opacity(0.86))

            if showsLabel {
                Text("photo")
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(SOOMColor.surface.opacity(0.86))
                    .clipShape(Capsule())
                    .padding(9)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ActivityMetricEvidence: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SOOMFont.body(9, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)
            Text(value)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct ActivityDirectionPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
            Text(value)
                .font(SOOMFont.displayMedium(21, relativeTo: .title3))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ActivityRouteCard: View {
    let title: String
    let count: String
    let tint: Color

    var body: some View {
        SOOMCard(depth: .ambient) {
            VStack(alignment: .leading, spacing: 10) {
                ActivityRoutePreview(points: [], tint: tint)
                    .frame(height: 86)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(1)
                    Text(count)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
            }
        }
    }
}

private struct ActivityStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)
            Text(value)
                .font(SOOMFont.body(16, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                                        SOOMColor.accentSurface.opacity(0.80),
                                        SOOMColor.white.opacity(0.30),
                                        SOOMColor.accent.opacity(0.08)
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
                    .shadow(color: SOOMColor.accent.opacity(0.10), radius: SOOMLayout.TabBar.selectedShadowRadius, x: 0, y: 4)
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
        .foregroundStyle(isSelected ? SOOMColor.accent : SOOMColor.ink.opacity(0.56))
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
                .fill(SOOMColor.accent)
                .overlay {
                    Circle()
                        .stroke(SOOMColor.white.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: SOOMColor.accent.opacity(isSelected ? 0.28 : 0.16), radius: 10, x: 0, y: 5)

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
