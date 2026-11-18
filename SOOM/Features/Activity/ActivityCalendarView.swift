import SwiftData
import SwiftUI

struct ActivityCalendarView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var storage: HealthAccountStorageController
    @Query(sort: \UnifiedWorkoutRecord.startDate, order: .reverse) private var records: [UnifiedWorkoutRecord]
    @State private var calendarModel = ActivityCalendarModel()
    @State private var today = Date()
    @State private var selectedWorkout: UnifiedWorkout?
    @State private var confirmingAllPrivate = false
    @State private var confirmingAutoPublish = false
    @State private var isChangingAllPrivacy = false
    @State private var privacyMessage: String?
    @ScaledMetric(relativeTo: .body) private var dayCellWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var weekdayHeaderHeight: CGFloat = 28

    private var dayCellHeight: CGFloat { dayCellWidth }

    private var workouts: [UnifiedWorkout] {
        UnifiedWorkoutDeduplicationEngine().canonicalWorkouts(
            records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }
        )
    }

    var body: some View {
        #if DEBUG
        let _ = WorkoutCardPerformanceProbe.hit("calendarBody")
        #endif
        let savedWorkouts = workouts
        let visibleWorkouts = calendarModel.visibleWorkouts(savedWorkouts)
        let summariesByDay = calendarModel.workoutSummariesByDay(savedWorkouts)

        SOOMScreen(tracksTabBarScroll: true) {
            shortcuts
            privacyControls
            calendarSection(summariesByDay: summariesByDay)
            if _records.fetchError != nil {
                SOOMCard {
                    Text("운동 기록을 불러오지 못했어요")
                        .font(SOOMFont.body(17, weight: .bold, relativeTo: .headline))
                    Text("잠시 후 활동 화면을 다시 열어 주세요. 저장된 기록은 삭제되지 않았어요.")
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
                .accessibilityIdentifier("activity.calendar.loadError")
            } else {
                workoutList(visibleWorkouts)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .workoutCardDestination(selection: $selectedWorkout)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = Date() }
        }
    }

    private var privacyControls: some View {
        SOOMCard {
            Text("활동과 내 피드")
                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
            Text(ProfileOnlyPrivacyReleaseGate.productionReady ? "기존 운동과 새 운동의 요약이 자동으로 반영돼요. 공개 프로필은 팔로워의 피드에, 비공개 프로필은 서로 팔로우한 사람에게만 표시됩니다." : "과거 운동까지 본인 피드에 자동으로 표시돼요. 다른 사람에게 보이는 범위는 계정 설정과 기존 공유 동의를 따르며, 이전 기록을 자동 공개하지 않아요.")
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }.accessibilityIdentifier("activity.privacy.controls")
    }

    private var shortcuts: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            NavigationLink {
                WorkoutBookmarksView()
            } label: {
                shortcutLabel("저장한 기록", icon: SOOMIcon.bookmark)
            }
            .accessibilityIdentifier("activity.bookmarks")

            NavigationLink {
                PersonalWorkoutRankingView()
            } label: {
                shortcutLabel("내 기록 순위", icon: SOOMIcon.medal)
            }
            .accessibilityIdentifier("activity.ranking")

            Menu {
                NavigationLink("HealthKit 운동 가져오기") {
                    HealthKitWorkoutImportViewContainer()
                }
                NavigationLink("ZIP 파일 가져오기") {
                    StravaImportViewContainer()
                }
                NavigationLink("운동 기록 관리") {
                    UnifiedWorkoutLibraryViewContainer()
                }
            } label: {
                Image(soom: SOOMIcon.more)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("운동 가져오기 및 관리")
            .accessibilityIdentifier("activity.manage")
        }
        .buttonStyle(.plain)
    }

    private func shortcutLabel(_ title: String, icon: String) -> some View {
        Label(title, soomIcon: icon)
            .font(SOOMFont.body(13, weight: .bold, relativeTo: .subheadline))
            .foregroundStyle(SOOMColor.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func calendarSection(summariesByDay: [Date: ActivityCalendarDaySummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                monthButton(offset: -1, icon: SOOMIcon.back)
                VStack(spacing: 3) {
                    Text("\(String(calendarModel.calendar.component(.year, from: calendarModel.displayedMonth)))년")
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                    Text("\(calendarModel.calendar.component(.month, from: calendarModel.displayedMonth))월")
                        .font(SOOMFont.displayMedium(26, relativeTo: .title2))
                        .foregroundStyle(SOOMColor.ink)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("activity.calendar.month")
                monthButton(offset: 1, icon: SOOMIcon.chevronRight)
            }

            // Keep all date hit areas at least 44 pt. At large text sizes the
            // calendar scrolls horizontally instead of shrinking or clipping dates.
            if dynamicTypeSize.isAccessibilitySize {
                Text("달력을 좌우로 움직여 다른 요일을 볼 수 있어요.")
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GeometryReader { proxy in
                let width = max(proxy.size.width, dayCellWidth * 7)
                ScrollView(.horizontal) {
                    VStack(spacing: 4) {
                        HStack(spacing: 0) {
                            ForEach(Array(calendarModel.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                                Text(symbol)
                                    .font(SOOMFont.body(12, relativeTo: .caption))
                                    .foregroundStyle(SOOMColor.secondaryInk)
                                    .frame(maxWidth: .infinity, minHeight: weekdayHeaderHeight)
                                    .accessibilityHidden(true)
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                            ForEach(Array(calendarModel.dayCells.enumerated()), id: \.offset) { _, date in
                                if let date {
                                    dayCell(date, summary: summariesByDay[date])
                                } else {
                                    Color.clear
                                        .frame(height: dayCellHeight)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                    .frame(width: width)
                }
                .scrollIndicators(.visible)
            }
            .frame(height: weekdayHeaderHeight + 4 + CGFloat(calendarModel.dayCells.count / 7) * (dayCellHeight + 4))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    calendarLegend
                    Spacer(minLength: 0)
                    todayButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    calendarLegend
                    todayButton
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("activity.calendar")
    }

    private func monthButton(offset: Int, icon: String) -> some View {
        Button {
            calendarModel.moveMonth(by: offset)
            SOOMHaptics.selection()
        } label: {
            Image(soom: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(SOOMColor.ink)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(offset < 0 ? "이전 달" : "다음 달")
        .accessibilityIdentifier(offset < 0 ? "activity.calendar.previousMonth" : "activity.calendar.nextMonth")
    }

    private func dayCell(_ date: Date, summary: ActivityCalendarDaySummary?) -> some View {
        let isToday = calendarModel.calendar.isDate(date, inSameDayAs: today)
        let isSelected = calendarModel.selectedDate.map { calendarModel.calendar.isDate(date, inSameDayAs: $0) } ?? false
        return Button {
            calendarModel.selectDate(date)
            SOOMHaptics.selection()
        } label: {
            ZStack {
                if let summary {
                    SOOMSportIconView(name: calendarIconName(for: summary.firstWorkoutType), size: 19)
                        .foregroundStyle(SOOMColor.white)
                        .offset(y: summary.count > 1 ? -4 : 0)
                    if summary.count > 1 {
                        Circle()
                            .fill(SOOMColor.white)
                            .frame(width: 4, height: 4)
                            .offset(y: 14)
                    }
                } else {
                    Text("\(calendarModel.calendar.component(.day, from: date))")
                        .font(SOOMFont.body(15, weight: isSelected || isToday ? .bold : .regular, relativeTo: .body))
                        .foregroundStyle(isToday ? SOOMColor.accent : (isSelected ? SOOMColor.accentInk : SOOMColor.ink))
                        .monospacedDigit()
                }
            }
            .frame(width: dayCellWidth - 4, height: dayCellWidth - 4)
            .background(summary != nil ? (isSelected ? SOOMColor.accent : SOOMColor.ink)
                        : (isSelected ? SOOMColor.accentSurface : SOOMColor.surfaceMuted),
                        in: Circle())
            .overlay {
                Circle()
                    .stroke(isToday ? SOOMColor.accent : Color.clear, lineWidth: 1.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .frame(height: dayCellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.year().month().day().weekday()))
        .accessibilityValue([isToday ? "오늘" : nil, isSelected ? "선택됨" : nil, summary.map { "첫 운동 \($0.firstWorkoutType.shareDisplayName), 총 \($0.count)개" } ?? "운동 기록 없음"].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("activity.calendar.day.\(calendarModel.calendar.component(.day, from: date))")
    }

    private func calendarIconName(for type: UnifiedWorkoutType) -> String {
        switch type {
        case .running: SOOMIcon.run
        case .cycling: SOOMIcon.bike
        case .swimming: SOOMIcon.swim
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .strength: "dumbbell"
        case .yoga: "figure.mind.and.body"
        case .other: SOOMIcon.activity
        }
    }

    private var calendarLegend: some View {
        HStack(spacing: 10) {
            Label {
                Text("오늘")
            } icon: {
                RoundedRectangle(cornerRadius: 3).stroke(SOOMColor.accent, lineWidth: 1.5).frame(width: 10, height: 10)
            }
            Label {
                Text("첫 운동 아이콘")
            } icon: {
                SOOMSportIconView(name: SOOMIcon.run, size: 12)
            }
            Label {
                Text("추가 운동")
            } icon: {
                Circle().fill(SOOMColor.ink).frame(width: 5, height: 5)
            }
        }
        .font(SOOMFont.body(11, relativeTo: .caption2))
        .foregroundStyle(SOOMColor.secondaryInk)
    }

    private var todayButton: some View {
        Button("오늘로 이동") {
            today = Date()
            calendarModel.showCurrentMonth(referenceDate: today)
            calendarModel.selectDate(today)
        }
        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
        .foregroundStyle(SOOMColor.accent)
        .frame(minHeight: 44)
        .accessibilityIdentifier("activity.calendar.today")
    }

    private func workoutList(_ visibleWorkouts: [UnifiedWorkout]) -> some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        periodTitle
                        Spacer(minLength: 12)
                        entireMonthButton
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        periodTitle
                        entireMonthButton
                    }
                }
                Text("\(visibleWorkouts.count)개 기록 · 최신순")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
            if visibleWorkouts.isEmpty {
                SOOMCard(depth: .ambient) {
                    Text(calendarModel.selectedDate == nil ? "이번 달에는 운동 기록이 없어요" : "이 날짜에는 운동 기록이 없어요")
                        .font(SOOMFont.body(17, weight: .bold, relativeTo: .headline))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("다른 날짜를 선택하거나 운동을 기록해 보세요. 이전에 저장한 기록은 해당 월에서 확인할 수 있어요.")
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("activity.calendar.empty")
            } else {
                ForEach(visibleWorkouts) { workout in
                    ActivityWorkoutRow(workout: workout, onOpen: { selectedWorkout = $0 })
                }
            }
        }
        .accessibilityIdentifier("activity.calendar.workouts")
    }

    private var periodTitle: some View {
        Text(calendarModel.selectedDate.map { $0.formatted(.dateTime.month().day().weekday()) } ?? "월 전체 기록")
            .font(SOOMFont.body(18, weight: .bold, relativeTo: .headline))
            .foregroundStyle(SOOMColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("activity.calendar.period")
    }

    @ViewBuilder
    private var entireMonthButton: some View {
        if calendarModel.selectedDate != nil {
            Button("월 전체 보기") { calendarModel.showEntireMonth() }
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("activity.calendar.showMonth")
        }
    }
}
