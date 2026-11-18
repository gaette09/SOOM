import SwiftUI
import SwiftData
import Charts

struct ActivityLoadTodayContainer: View {
    @EnvironmentObject private var storage: HealthAccountStorageController
    var onAllRecords: () -> Void
    var body: some View {
        ActivityLoadDashboard(directory: storage.scopeDirectory,
            allowed: { [weak storage, scope = storage.scopeID] in storage?.scopeID == scope },
            onAllRecords: onAllRecords)
            .id(storage.scopeID)
    }
}

struct ActivityLoadDashboard: View {
    @EnvironmentObject private var storage: HealthAccountStorageController
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scene
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.soomBottomOverlayInset) private var bottomOverlayInset
    @StateObject private var model: ActivityLoadViewModel
    @State private var revision = 0
    @State private var selected: Date?
    @State private var chartSelection: Date?
    @State private var showDay = false
    @State private var showWeekDetails = false
    @State private var weekOffset = 0
    @State private var zoneChoice = TimeZone.current.identifier
    @State private var showZoneChange = false
    @State private var selectedWorkout: UnifiedWorkout?
    @State private var selectedEffort: UnifiedWorkout?
    @State private var inputError: String?
    private enum FocusRegion: Hashable { case summary, dayValue }
    @AccessibilityFocusState private var focusedRegion: FocusRegion?
    let directory: URL
    let onAllRecords: () -> Void
    init(directory: URL, allowed: @escaping () -> Bool, onAllRecords: @escaping () -> Void) {
        self.directory = directory; self.onAllRecords = onAllRecords
        _model = StateObject(wrappedValue: ActivityLoadViewModel(directory: directory, allowed: allowed))
    }
    private var calendar: Calendar { ActivityLoadRules.calendar(model.snapshot?.timeZoneID ?? TimeZone.current.identifier) }
    private var day: ActivityLoadDay? {
        guard let snapshot = model.snapshot else { return nil }
        return ActivityLoadGraphMetric.selectedDay(in: snapshot, selected: selected, calendar: calendar)
    }
    private var start: Date { calendar.date(byAdding: .day, value: -7, to: selected ?? day?.date ?? Date())! }
    private var end: Date { calendar.date(byAdding: .day, value: 10, to: start)! }
    private var inputPlan:ActivityLoadInputPlan{ActivityLoadInputPlan(model.snapshot)}
    private var inputNeeded:[ActivityLoadSession]{inputPlan.recordInputs}
    private var visible: [ActivityLoadDay] {
        model.snapshot?.days.filter { $0.date >= start && $0.date <= end } ?? []
    }
    private var metric: ActivityLoadGraphMetric { .init(days: visible) }
    private func text(_ date: Date, _ format: String) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "ko_KR"); f.dateFormat = format; return f.string(from: date)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if model.snapshot == nil && model.isLoading {
                    SOOMSkeleton(layout: .chart, label: "활동 부하 불러오는 중").padding()
                } else if let day {
                    if let week {
                        weekHeader(week)
                        weekNavigation
                        weeklyChart(week)
                    }
                    reviewDisclosure
                    DisclosureGroup {
                    Button { showDay = true } label: { hero(day) }
                        .buttonStyle(.plain).accessibilityIdentifier("activity.load.day")
                        .accessibilityHint("선택 날짜의 계산값과 기록을 확인합니다")
                        .accessibilityFocused($focusedRegion, equals: .summary)
                    if metric.value(day) == nil, let latest = model.snapshot?.days.last(where: { !$0.isForecast && $0.workoutPresent }), latest.date != day.date {
                        Button("최근 운동 날짜로") { selected = latest.date }
                            .font(.caption.bold()).frame(minHeight: 44).accessibilityIdentifier("activity.load.latestWorkout")
                    }
                    HStack {
                        Button { move(-7) } label: { Image(soom: "chevron.left").frame(width: 44, height: 40) }.accessibilityLabel("이전 7일")
                        Spacer()
                        Text(text(start, "MM.dd") + " — " + text(end, "MM.dd")).font(.caption.bold()).accessibilityIdentifier("activity.load.window")
                        Spacer()
                        Button { move(7) } label: { Image(soom: "chevron.right").frame(width: 44, height: 40) }.accessibilityLabel("다음 7일")
                    }.foregroundStyle(SOOMColor.secondaryInk).background(SOOMColor.surfaceMuted)
                    ActivityLoadChart(days: visible, selection: $chartSelection, selectedDate: day.date, start: start, end: end, calendar: calendar, metric: metric)
                        .onChange(of: chartSelection) { _, next in
                            if let next, let closest = visible.min(by: { abs($0.date.timeIntervalSince(next)) < abs($1.date.timeIntervalSince(next)) }) { selected = closest.date }
                        }
                    HStack {
                        if metric == .recentTrend { RoundedRectangle(cornerRadius: 2).fill(ActivityLoadPalette.band).frame(width: 14, height: 9) }
                        Text(metric == .recentTrend ? "내 과거 부하 범위" : "● 일별 기록 · 미확인 날짜는 빈칸").font(.caption)
                        Spacer(); Text("◆ 운동한 날").font(.caption2)
                    }.foregroundStyle(SOOMColor.secondaryInk).padding(.horizontal, 20).frame(minHeight: 40)
                    } label: {
                        Text("일별 추세와 기록 확인").font(.subheadline).frame(minHeight: 44)
                            .accessibilityIdentifier("activity.load.dailyDetails")
                    }.tint(SOOMColor.secondaryInk).padding(.horizontal, 20)
                    explanation
                    recent
                }
                if let error = model.error {
                    VStack { Text(error).font(.footnote); Button("다시 불러오기") { revision += 1 } }.padding()
                        .accessibilityIdentifier("activity.load.error")
                }
            }
            // Reserve the root's floating tab overlay inside scroll content,
            // so the final workout can scroll fully above its touch targets.
            .padding(.bottom, max(0, bottomOverlayInset) + SOOMLayout.Screen.bottomPadding)
        }
        .background(SOOMColor.surface)
        .accessibilityIdentifier("activity.load.dashboard")
        .task(id: "\(storage.dataRevision):\(revision)") { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: ActivityLoadRules.changed)) { note in
            if acceptsEffortChange(note) { revision += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for:HealthKitDetailReadCache.measurementsChanged)){note in
            if note.object as? String == storage.scopeID {revision += 1}
        }
        .onReceive(NotificationCenter.default.publisher(for: HealthCloudJournal.didCommit)) { note in
            if note.object as? UUID == storage.userID { revision += 1 }
        }
        .onChange(of: scene) { _, phase in if phase == .active { Task { await reload() } } }
        .sheet(isPresented: $showWeekDetails) { weekDetails }
        .sheet(isPresented: $showDay, onDismiss: {
            if selectedWorkout == nil { focusedRegion = .summary }
        }) { daySheet }
        .sheet(item:$selectedEffort){workout in
            WorkoutEffortDirectEntry(workout:workout,directory:directory,isDemo:ReviewDemoMode.isActive,canAccess:{[weak storage,scope=storage.scopeID] in
                guard storage?.scopeID == scope else{return false}
                let id=workout.id
                guard let row=try? context.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate:#Predicate{$0.id == id})).first else{return false}
                return row.startDate == workout.startDate && row.endDate == workout.endDate
            })
        }
        .alert("운동 강도를 열지 못했어요",isPresented:Binding(get:{inputError != nil},set:{if !$0{inputError=nil}})){Button("확인"){inputError=nil}}message:{Text(inputError ?? "")}
        .confirmationDialog("분석 시간대를 바꾸면 날짜별 기록 확인을 다시 해야 해요. 원본 운동과 저장 점수는 보존됩니다.", isPresented: $showZoneChange) {
            Button("기기 시간대로 변경") { model.changeTimeZone(TimeZone.current.identifier) }
        }
        .workoutCardDestination(selection: $selectedWorkout)
        .modifier(ActivityLoadReadProbe(count: model.inputReadCount))
    }
    private var week: ActivityLoadWeekProjection? {
        guard let snapshot = model.snapshot,
              let anchor = calendar.date(byAdding: .day, value: weekOffset * 7, to: snapshot.asOf) else { return nil }
        return ActivityLoadWeekProjection(snapshot: snapshot, containing: anchor)
    }
    private func previousWeek(_ week: ActivityLoadWeekProjection) -> ActivityLoadWeekProjection? {
        guard let snapshot = model.snapshot, let date = calendar.date(byAdding: .day, value: -7, to: week.start) else { return nil }
        return ActivityLoadWeekProjection(snapshot: snapshot, containing: date)
    }
    private func amountText(_ amount: Double?) -> String {
        amount.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—"
    }
    private func weekValue(_ week: ActivityLoadWeekProjection) -> some View {
        Text(amountText(week.subtotal)).font(SOOMFont.displayMedium(typeSize.isAccessibilitySize ? 40 : 60, relativeTo: .largeTitle))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier("activity.week.value")
    }
    private func weekSource(_ week: ActivityLoadWeekProjection) -> String {
        let sessions = week.slots.filter { !$0.isFuture }.compactMap(\.day).flatMap { ActivityLoadComputedRecords(day: $0).included }
        let automatic = sessions.filter { ActivityLoadRules.isAutomatic($0.methodKey) }
        if automatic.contains(where: { $0.sourceLabel.contains("초기 추정") }) { return "SOOM 참고 부하 · 초기 추정 포함" }
        if !automatic.isEmpty { return "SOOM 참고 부하 · 자동 추정 포함" }
        return sessions.isEmpty ? (week.isComplete ? "SOOM 참고 부하 · 확인된 운동 없음" : "SOOM 참고 부하 · 기록 확인 필요") : "SOOM 참고 부하 · 사용자 지정"
    }
    private func weekHeader(_ week: ActivityLoadWeekProjection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(weekOffset == 0 ? "이번 주 운동 부하" : "주간 운동 부하").font(.headline)
                Spacer()
                Button { showWeekDetails = true } label: {
                    Image(systemName: "arrow.up.right").frame(width: 44, height: 44)
                }.accessibilityLabel("주간 운동 상세").accessibilityIdentifier("activity.week.detail")
            }
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { weekValue(week); Text("AU").font(.title3).foregroundStyle(SOOMColor.secondaryInk) }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { weekValue(week); Text("AU").font(.title3).foregroundStyle(SOOMColor.secondaryInk) }
                }
            }
            Text(week.isComplete ? "확인된 주간 합계" : "계산된 기록 부분합")
                .font(.subheadline.weight(.medium)).accessibilityIdentifier("activity.week.state")
            Text(weekSource(week)).font(.caption).foregroundStyle(SOOMColor.secondaryInk).accessibilityIdentifier("activity.week.source")
            Text("계산된 운동 \(week.computedCount)개 · 확인이 필요한 운동 \(week.issues.values.reduce(0,+))개")
                .font(.caption).foregroundStyle(SOOMColor.secondaryInk).accessibilityIdentifier("activity.week.counts")
            if let previous = previousWeek(week) {
                Text("지난주 같은 요일까지 " + amountText(previous.subtotal(through: week.elapsedIndex)) + " AU · 계산된 기록 기준")
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk).accessibilityIdentifier("activity.week.previous")
            }
            if let snapshot = model.snapshot,
               let mean = ActivityLoadWeekProjection.precedingThreeCompleteWeeksMean(snapshot: snapshot, before: week.start) {
                Text("직전 연속 3개 완료주 평균 " + amountText(mean) + " AU")
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk).accessibilityIdentifier("activity.week.mean")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 12)
    }
    private var weekNavigation: some View {
        HStack {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .disabled(weekOffset <= -24).accessibilityLabel("이전 주").accessibilityIdentifier("activity.week.previousWeek")
            Spacer()
            if let week { Text(text(week.start, "M.d") + " — " + text(week.slots[6].date, "M.d")).font(.subheadline.weight(.semibold)).accessibilityIdentifier("activity.week.window") }
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(weekOffset >= 0).accessibilityLabel("다음 주").accessibilityIdentifier("activity.week.nextWeek")
        }.foregroundStyle(SOOMColor.ink).padding(.horizontal, 16)
    }
    private func weeklyChart(_ week: ActivityLoadWeekProjection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                if let previous = previousWeek(week) {
                    ForEach(previous.cumulative) { point in
                        LineMark(x: .value("요일", point.index), y: .value("기록 누적", point.value), series: .value("구간", "이전-\(point.segment)"))
                            .foregroundStyle(SOOMColor.secondaryInk.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("요일", point.index), y: .value("기록 누적", point.value))
                            .foregroundStyle(SOOMColor.secondaryInk.opacity(0.45)).symbolSize(22)
                    }
                }
                ForEach(week.cumulative) { point in
                    LineMark(x: .value("요일", point.index), y: .value("기록 누적", point.value), series: .value("구간", "현재-\(point.segment)"))
                        .foregroundStyle(SOOMColor.accent).lineStyle(StrokeStyle(lineWidth: 3))
                    PointMark(x: .value("요일", point.index), y: .value("기록 누적", point.value))
                        .foregroundStyle(SOOMColor.accent).symbolSize(44)
                        .accessibilityLabel("\(["월","화","수","목","금","토","일"][point.index]), 계산된 기록 누적 \(amountText(point.value)) AU")
                }
            }.chartXScale(domain: -0.5...6.5)
                .chartXAxis { AxisMarks(values: Array(0...6)) { value in
                    AxisValueLabel { if let index = value.as(Int.self) { Text(["월","화","수","목","금","토","일"][index]) } }
                } }
                .chartYAxis { AxisMarks(position: .trailing) }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(height: 190).accessibilityIdentifier("activity.week.chart")
            HStack(spacing: 16) {
                Label(weekOffset == 0 ? "이번 주" : "선택한 주", systemImage: "circle.fill").foregroundStyle(SOOMColor.accent)
                Label("지난주", systemImage: "circle.fill").foregroundStyle(SOOMColor.secondaryInk)
            }.font(.caption).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Text("계산된 기록 누적 · 미확인 날짜는 빈칸")
                .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }
    private var reviewDisclosure: some View {
        DisclosureGroup {
            if let week {
                ForEach(ActivityLoadComputedRecords.Issue.allCases, id: \.self) { issue in
                    if let count = week.issues[issue] { Text("\(issue.rawValue) \(count)개").font(.footnote) }
                }
                if week.unlocatedCount > 0 { Text("날짜를 배치할 수 없는 원본 \(week.unlocatedCount)개 · 날짜별 완결 여부는 보류해요").font(.footnote) }
                Text("부분합은 계산 가능한 기록만 더한 값이에요. 기록 누락·완료 여부를 확인한 합계나 안전 판정이 아니에요.")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            if !inputPlan.baseline.isEmpty { baselinePrompt }
            if inputPlan.automaticCount > 0 || inputPlan.manualCount > 0 {
                Text("자동 추정 \(inputPlan.automaticCount)개 · 사용자 수정 \(inputPlan.manualCount)개")
                    .font(.caption).accessibilityIdentifier("activity.load.inputSources")
            }
            if !inputNeeded.isEmpty { inputPrompt }
        } label: { Text("기록 확인과 계산 안내").font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("activity.load.review") }
            .tint(SOOMColor.secondaryInk).padding(.horizontal, 20)
    }
    private var weekSessionLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
    }
    private var weekDetails: some View {
        NavigationStack {
            ScrollView {
                if let week {
                    VStack(alignment: .leading, spacing: 20) {
                        weekNavigation
                        Text(amountText(week.subtotal) + " AU").font(.largeTitle.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        Text(week.isComplete ? "확인된 주간 합계" : "계산된 기록 부분합").font(.subheadline)
                        Chart(week.slots) { slot in
                            if let amount = slot.amount {
                                BarMark(x: .value("요일", slot.index), y: .value("기록 부하", amount))
                                    .foregroundStyle(SOOMColor.accent).cornerRadius(4)
                                    .accessibilityLabel("\(text(slot.date, "M월 d일")), \(amountText(amount)) AU")
                            }
                        }.chartXScale(domain: -0.5...6.5)
                            .chartXAxis { AxisMarks(values: Array(0...6)) { value in
                                AxisValueLabel { if let index = value.as(Int.self) { Text(["월","화","수","목","금","토","일"][index]) } }
                            } }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(height: 150).accessibilityIdentifier("activity.week.bars")
                        Text(weekOffset == 0 ? "이번 주 운동" : "선택한 주 운동").font(.headline)
                        ForEach(week.slots) { slot in
                            if let day = slot.day, !slot.isFuture {
                                ForEach(day.sessions) { session in
                                    Button { showWeekDetails = false; openWeeklyWorkout(session.workout) } label: {
                                        weekSessionLayout {
                                            SOOMSportIconView(name: loadIcon(session.workout.workoutType), size: 22)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(text(session.workout.startDate, "M월 d일") + " " + session.workout.workoutType.feedShortTitle).font(.subheadline.weight(.semibold))
                                                Text(scoreText(session.workout)).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                                                Text(session.sourceLabel).font(.caption2).foregroundStyle(SOOMColor.secondaryInk)
                                            }
                                            if !typeSize.isAccessibilitySize { Spacer() }
                                            let included = ActivityLoadComputedRecords(day: day).included.contains { $0.id == session.id }
                                            Text(included ? amountText(session.amount) + " AU" : "확인 필요").font(.subheadline.weight(.semibold)).monospacedDigit()
                                        }.frame(minHeight: 54).padding(.vertical, 8).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("activity.week.workout." + session.id.uuidString)
                                }
                            }
                        }
                        if week.computedCount == 0 { Text("계산된 부하가 없어요. 기록이 없거나 확인이 필요한 날을 0으로 채우지 않아요.").font(.footnote).foregroundStyle(SOOMColor.secondaryInk) }
                    }.padding(20)
                }
            }.navigationTitle("주간 운동 상세").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showWeekDetails = false } } }
        }.accessibilityIdentifier("activity.week.details")
    }
    private func reload() async {
        await model.reloadIfNeeded(revision: "\(storage.dataRevision):\(revision)", store: SwiftDataUnifiedWorkoutStore(modelContext: context), maximum: TrainingSettingsStore.shared.loadSettings().maxHeartRate,storedHeartRates:{try ActivityLoadStoredHeartRateReader(context:context,scope:storage.scopeID).read($0)})
    }
    private func move(_ count: Int) {
        guard let snapshot = model.snapshot, let first = snapshot.days.first?.date, let last = snapshot.days.last?.date,
              let target = calendar.date(byAdding: .day, value: count, to: selected ?? day?.date ?? Date()) else { return }
        selected = min(last, max(first, target))
    }
    private func hero(_ day: ActivityLoadDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(text(day.date, "M월 d일") + (day.isForecast ? " · 예상" : day.isProvisional ? " · 집계 중" : day.daily == nil ? " · 미확인" : " · 마감"))
                Spacer()
                #if DEBUG
                if ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_ACTIVITY_LOAD_QA"] == "1" { Text("가상 예시").font(.caption2) }
                #endif
            }.font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            HStack(spacing: 10) {
                Text(metric.value(day).map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                    .font(SOOMFont.displayMedium(typeSize.isAccessibilitySize ? 48 : 68, relativeTo: .largeTitle)).monospacedDigit()
                    .accessibilityIdentifier("activity.load.value")
                VStack(alignment: .leading) { Text("AU").bold(); Text(metric.label).font(.footnote).accessibilityIdentifier("activity.load.metric") }
                    .foregroundStyle(SOOMColor.secondaryInk)
            }.frame(minHeight: 86)
            Text(metric.stateLabel(day) + (day.isProvisional ? " · 집계 중" : "")).font(.caption.bold()).foregroundStyle(metric == .recentTrend ? day.state.tint : SOOMColor.secondaryInk)
                .padding(.horizontal, 12).padding(.vertical, 7).background(metric == .recentTrend ? day.state.chipBackground : SOOMColor.secondaryInk.opacity(0.09), in: Capsule())
                .accessibilityIdentifier("activity.load.state")
            Text("SOOM 점수 기반 참고 부하 · " + day.inputSummary)
                .font(.caption2).foregroundStyle(SOOMColor.secondaryInk)
            if inputPlan.initialCount > 0 {
                Text("초기 추정 포함 · 개인 생리 강도나 안전 판정이 아니에요")
                    .font(.caption2).foregroundStyle(SOOMColor.secondaryInk)
                    .accessibilityIdentifier("activity.load.initialEstimate")
            }
            if let total = day.daily ?? day.recordedSubtotal, !day.isForecast {
                Text("선택일 합계 " + total.formatted(.number.precision(.fractionLength(0...1))) + " AU" + (day.daily == nil ? " · 미마감/미확인" : ""))
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk).accessibilityIdentifier("activity.load.dailyTotal")
            }
            if day.smoothed == nil {
                Text(metric == .recordedDays ? "계산된 운동 점수는 일별 기록 부하로 먼저 보여요. 미산출·누락 미확인 날짜는 0으로 채우지 않아요. 28일 추세와 개인 범위는 확인된 기록이 쌓이면 표시돼요." : (day.reason ?? "같은 기준의 완결 기록 28일이 필요해요. 일별 값은 날짜별 상세에서 확인할 수 있어요."))
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 20).background(SOOMColor.surfaceMuted)
    }
    private var baselinePrompt:some View {
        VStack(alignment:.leading,spacing:8){
            Text("자동 점수의 개인 기준은 아직 없어요").font(.subheadline.bold())
            Text("저장 심박이 있는 \(inputPlan.baseline.count)개 운동은 근거가 있는 기준이 없어 자동 점수를 확정하지 않았어요. 기준 입력 없이 기록을 보거나 원하는 운동만 직접 지정할 수 있어요. FTP는 심박 점수에 필요하지 않아요.").font(.caption)
            NavigationLink("기준값 보기 · 선택 사항"){SettingsView(category:.app)}.frame(minHeight:44)
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(SOOMColor.surfaceMuted)
            .accessibilityIdentifier("activity.load.baselineNeeded")
    }
    private var inputPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("심박 정보 확인이 필요한 운동 \(inputNeeded.count)개").font(.subheadline.bold()).accessibilityIdentifier("activity.load.inputNeeded")
            Text("심박과 참고할 앞선 직접 입력이 없어 일부 점수를 계산하지 않았어요. 기록 저장·조회는 그대로 가능하고, 원하는 운동만 같은 강도 조절에서 지정할 수 있어요.").font(.caption)
            ForEach(Array(inputNeeded.prefix(3))) { session in
                Button { openInput(session.workout) } label: {
                    Text(text(session.workout.startDate,"M월 d일") + " " + session.workout.workoutType.feedShortTitle + " · 점수 직접 지정  ›")
                        .font(.subheadline).frame(minHeight: 44)
                }.accessibilityIdentifier("activity.load.enterIntensity." + session.id.uuidString)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(SOOMColor.surfaceMuted)
    }
    private func openWeeklyWorkout(_ workout: UnifiedWorkout) {
        #if DEBUG && targetEnvironment(simulator)
        // Isolated synthetic records exercise the ordinary persisted-detail guard.
        let fixtureIDs = ["D4110000-0000-4000-8000-000000000001", "D4120000-0000-4000-8000-000000000002", "D4130000-0000-4000-8000-000000000003"]
        if ReviewDemoMode.isActive,
           ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
           ProcessInfo.processInfo.environment["SOOM_WEEKLY_PARTIAL_QA"] == "1",
           fixtureIDs.contains(workout.id.uuidString) {
            let id = workout.id
            if (try? context.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id }))) == 0 {
                context.insert(UnifiedWorkoutPersistenceMapper().makeRecord(from: workout))
                do { try context.save() } catch { return }
            }
        }
        #endif
        selectedWorkout = workout
    }
    private func openInput(_ workout: UnifiedWorkout) {
        #if DEBUG && targetEnvironment(simulator)
        // The graph oracle intentionally does not import data. Seed only this
        // synthetic demo row so the real deleted-record guard stays exercised.
        if ReviewDemoMode.isActive,
           ProcessInfo.processInfo.environment["SOOM_ACTIVITY_LOAD_QA_MODE"] == "missing" {
            let id=workout.id
            let query=FetchDescriptor<UnifiedWorkoutRecord>(predicate:#Predicate { $0.id == id })
            if (try? context.fetchCount(query)) == 0 {
                context.insert(UnifiedWorkoutPersistenceMapper().makeRecord(from:workout))
                do { try context.save() } catch { return }
            }
        }
        #endif
        let id=workout.id
        do {
            guard let row=try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate:#Predicate{$0.id == id})).first else {inputError="삭제되었거나 더 이상 접근할 수 없는 기록이에요.";return}
            selectedEffort=UnifiedWorkoutPersistenceMapper().makeWorkout(from:row)
        } catch {inputError="기록을 불러오지 못했어요. 다시 시도해 주세요."}
    }
    private func acceptsEffortChange(_ note:Notification)->Bool {
        if note.object == nil || note.object as? String == directory.path{return true}
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive,let qa=ActivityLoadQAFixture.effortDirectory(base:directory),note.object as? String == qa.path{return true}
        #endif
        return false
    }
    private var explanation: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("추세를 계산할 수 없을 때는 계산된 일별 기록 부하를 회색 점으로 먼저 보여요. 미확인 날짜는 0으로 채우거나 이어 붙이지 않으며, 이 점은 28일 평균이나 평소 범위 판정이 아니에요.")
                Text("최근 부하는 같은 SOOM 점수 입력으로 계산한 일별 부하 28일을 반감기 7일로 가중 평균한 값이에요. 내 과거 부하 범위는 당일을 뺀 56일의 Q10–Q90이며 표본이 부족하면 표시하지 않아요.")
                Text("SOOM 강도점수는 한 제품 입력이에요. 개인 최대심박 기준이 있으면 기존 심박 비율 추정을 유지해요. 기준이 없으면 평균심박÷20을 1–10으로 제한한 초기 추정으로 시작해요. 개인 최대심박·FTP를 임의로 채우지 않으며 검증된 RPE·개인 생리 강도 환산은 아니에요. 직접 지정한 1–10 값은 항상 추정을 대체해요.")
                Text("심박도 없으면 앞선 90일 같은 종목의 명시적 직접 입력 중앙값을 낮은 신뢰로 참고해요. 현재 운동·이후 운동·다른 종목·삭제된 기록·추정값은 참고하지 않아요. 근거가 전혀 없으면 점수를 만들지 않고 기록과 선택적 직접 지정을 유지해요.")
                Text("시간은 운동 기록의 값을 부하 계산에서 한 번만 반영해요. 강도 지정 때 시간이나 다른 항목을 추가 입력하지 않아요. 기록 누락은 자동으로 0이 되지 않아요. 직접 수정·해제하면 해당 세션부터 다시 계산하고 추세를 끊지 않아요. 실제 기록이 미확인인 날은 빈칸이며 새 완결 구간이 필요해요.")
                Text("회색 띠인 내 과거 부하 범위는 편집기의 21일 입력 점수 범위와 다릅니다. 동일 계산 계약으로 현재 입력을 반영해 다시 계산한 개인 과거 참고 범위예요. 출처·추정 신뢰는 별도로 표시해요. 정상·안전·위험 또는 과훈련 또는 검증된 생리학적 부하 판정은 아니에요. 점선은 추가 운동이 없을 때의 조건 계산이고 실제 관측값이 아니에요.")
                Text("분석 시간대: \(model.snapshot?.timeZoneID ?? "—") · 현재 설정으로 과거 전체를 다시 계산해요. 원래 운동 시간대는 미확인일 수 있어요.")
                Text("자동 보정은 최근 90일의 같은 종목에서 직접 수정한 점수와 유효한 저장 심박이 5건·3일 이상 연결될 때만 적용해요. 생리적 최대심박이나 FTP를 바꾸지 않으며, 점수 보정은 ±2·7일당 최대 0.25로 제한한 제품 가설이에요. 현재 기준으로 과거 자동 추정도 다시 계산하며 원본과 직접 입력은 보존해요.")
                ForEach(model.calibrationSummaries, id: \.sport.rawValue) { item in
                    Text(item.sport.feedShortTitle + " · 심박과 직접 입력 연결 \(item.validHeartRatePairs)건 · 현재 기준으로 보정 가능한 \(item.usableBasePairs)건/\(item.distinctDays)일")
                        .accessibilityIdentifier("activity.load.calibrationPairs." + item.sport.rawValue)
                }
                if let notice = model.calibrationNotice { Text(notice) }
                Button(model.calibration.enabled ? "자동 보정 끄기 · 기본 추정으로 복원" : "자동 보정 다시 사용") {
                    model.setAutomaticCalibrationEnabled(!model.calibration.enabled)
                }.frame(minHeight: 44).accessibilityIdentifier("activity.load.calibrationToggle")
                Button("기기 시간대로 분석 날짜 변경") { showZoneChange = true }.frame(minHeight: 44)
            }.font(.footnote).fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
        } label: { Text("점수와 범위는 어떻게 보나요?").font(.footnote) }
            .tint(SOOMColor.secondaryInk).padding(.horizontal, 20).padding(.vertical, 12).background(SOOMColor.surfaceMuted)
            .accessibilityIdentifier("activity.load.help")
    }
    private func loadIcon(_ type: UnifiedWorkoutType) -> String {
        switch type {
        case .running: SOOMIcon.run
        case .cycling: SOOMIcon.bike
        case .swimming: SOOMIcon.swim
        case .walking, .hiking: "figure.walk"
        case .strength: "dumbbell"
        case .yoga: "figure.mind.and.body"
        case .other: SOOMIcon.activity
        }
    }
    private func scoreText(_ workout: UnifiedWorkout) -> String {
        guard let session = model.snapshot?.days.lazy.flatMap(\.sessions).first(where: { $0.id == workout.id }) else { return "분석 기간 밖의 기록" }
        guard let value = session.intensity else { return "점수 미산출 · 직접 지정 가능" }
        let source = session.methodKey?.hasPrefix(ActivityLoadRules.manualMethod) == true ? "사용자 지정" : session.sourceLabel.contains("초기 추정") ? "초기 추정" : "자동 추정"
        return source + " " + value.formatted(.number.precision(.fractionLength(0...1))) + " / 10"
    }
    private var recent: some View {
        VStack(spacing: 10) {
            HStack { Text("최근 운동").font(.subheadline.bold()); Spacer(); Button("전체 기록  ›", action: onAllRecords).font(.caption) }
            ForEach(Array((model.snapshot?.recent ?? []).prefix(1))) { workout in
                Button { selectedWorkout = workout } label: {
                    HStack {
                        SOOMSportIconView(name: loadIcon(workout.workoutType), size: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(text(workout.startDate, "M월 d일") + " " + workout.workoutType.feedShortTitle).font(.subheadline.bold())
                            Text(scoreText(workout)).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                                .accessibilityIdentifier("activity.load.workoutScore." + workout.id.uuidString)
                        }
                        Spacer()
                        Text(workout.durationSeconds.isFinite && workout.durationSeconds > 0 ? "\(Int(workout.durationSeconds / 60))분  ›" : "—  ›").font(.caption)
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("activity.load.workout." + workout.id.uuidString)
            }
            if model.snapshot?.recent.isEmpty == true { Text("아직 확인할 운동이 없어요.").font(.footnote).foregroundStyle(SOOMColor.secondaryInk) }
        }.padding(20).foregroundStyle(SOOMColor.ink)
    }
    private var daySheet: some View {
        NavigationStack {
            if let day {
                List {
                    Section(text(day.date, "yyyy년 M월 d일")) {
                        LabeledContent("최근 부하", value: day.smoothed.map { String(format: "%.3f AU", $0) } ?? "미확인")
                            .accessibilityFocused($focusedRegion, equals: .dayValue)
                        LabeledContent(day.daily == nil && day.recordedSubtotal != nil ? "현재 기록 합계 · 미마감/미확인" : "이날 부하", value: (day.daily ?? day.recordedSubtotal).map { String(format: "%.3f AU", $0) } ?? "입력/기록 확인 필요")
                        if let lower = day.lower, let upper = day.upper { Text(String(format: "내 과거 부하 범위 %.3f–%.3f AU", lower, upper)) }
                        if let subtotal = ActivityLoadComputedRecords(day: day).subtotal {
                            LabeledContent("계산된 기록 부분합", value: amountText(subtotal) + " AU")
                                .accessibilityIdentifier("activity.load.computedSubtotal")
                            Text("계산된 운동 \(ActivityLoadComputedRecords(day: day).included.count)개 · 하루 전체의 완결 합계와 달라요").font(.caption)
                        }
                        Text(day.reason ?? day.state.label).font(.footnote)
                    }
                    Section {
                        Text("SOOM 점수 기반 참고 부하 · " + day.inputSummary)
                        Text("자동 추정과 사용자 수정은 같은 0–10 SOOM 점수 입력의 출처예요. 사용자 수정값이 자동값을 대체하며 선택 점수×분을 한 번만 계산해요. HR 기반 추정이 실제 체감과 과학적으로 동등하게 검증된 것은 아니에요.").font(.footnote)
                    }
                    Section("계산에 포함할 운동") {
                        ForEach(day.sessions) { session in
                            Button { showDay = false; selectedWorkout = session.workout } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(session.workout.workoutType.feedShortTitle)
                                    Text(scoreText(session.workout)).font(.subheadline.bold())
                                        .accessibilityIdentifier("activity.load.sessionScore." + session.id.uuidString)
                                    Text(session.sourceLabel).font(.caption)
                                    Text(session.confidence).font(.caption2)
                                        .accessibilityIdentifier("activity.load.sessionEvidence." + session.id.uuidString)
                                    Text(session.amount.map { String(format: "%.3f AU", $0) } ?? session.reason ?? "입력 필요").font(.footnote)
                                    if session.amount == nil { Text("운동 상세에서 점수 직접 지정  ›").font(.caption.bold()) }
                                }
                            }
                        }
                        if day.sessions.isEmpty { Text(day.rawCount == 0 ? "불러온 기록이 없어요. 휴식이라고 추정하지 않아요." : "이날 기록은 모두 분석에서 제외됐어요.") }
                    }
                    if !day.isForecast {
                        Section {
                            Text("이 기기의 해당 날짜에 빠진 운동이 없는지와 가져온 세션 시간이 전체 운동시간인지 확인한 뒤 눌러 주세요. 이후 새 기록·수정·삭제가 들어오면 확인은 다시 필요해요.").font(.footnote)
                            Button(day.rawCount == 0 ? "분석할 운동이 없는 날로 확인" : day.sessions.isEmpty ? "모든 운동 분석 제외 확인" : "이날 기록과 세션 시간 확인") { model.approve(day) }
                                .disabled(day.date >= calendar.startOfDay(for: model.snapshot?.asOf ?? Date()))
                                .accessibilityIdentifier("activity.load.confirmDay")
                        }
                    }
                }.onAppear { focusedRegion = .dayValue }
                .navigationTitle("날짜별 기록").toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showDay = false } } }
            }
        }
    }
}
private enum ActivityLoadPalette {
    static let below = SOOMColor.blue
    static let within = SOOMColor.purple
    static let above = SOOMColor.red
    static let band = Color("ActivityLoadHistoricalBand")
    static let aboveTint = Color("ActivityLoadAboveTint")
}
private extension ActivityLoadState {
    var chipBackground: Color { self == .above ? ActivityLoadPalette.aboveTint : tint.opacity(0.09) }
    var tint: Color {
        switch self {
        case .below: ActivityLoadPalette.below
        case .inside: ActivityLoadPalette.within
        case .above: ActivityLoadPalette.above
        default: SOOMColor.secondaryInk
        }
    }
}
private struct ActivityLoadChart: View {
    let days: [ActivityLoadDay]
    @Binding var selection: Date?
    let selectedDate: Date
    let start: Date
    let end: Date
    let calendar: Calendar
    let metric: ActivityLoadGraphMetric
    private var upper: Double {
        let maxValue = days.flatMap { [metric.value($0), metric == .recentTrend ? $0.upper : nil].compactMap { $0 } }.max() ?? 0
        return max(30, ceil(maxValue / 30) * 30)
    }
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 240
    @State private var daySelection: Double?
    private func x(_ date: Date) -> Double { Double(calendar.dateComponents([.day], from: start, to: date).day ?? 0) }
    private var groups: [String] { Array(Set(days.filter { $0.lower != nil }.map { String($0.bandGroup) })).sorted() }
    var body: some View {
        VStack(spacing: 2) {
            HStack { Text(metric == .recentTrend ? "기록" : "일별 기록 부하"); Spacer(); if metric == .recentTrend && days.contains(where: \.isForecast) { Text("예상 · 운동 없음") }; Text("AU").padding(.leading, 16) }
                .font(.caption2).foregroundStyle(SOOMColor.secondaryInk)
            Chart {
                if metric == .recentTrend, let firstFuture = days.first(where: \.isForecast) {
                    RectangleMark(xStart: .value("일", x(firstFuture.date) - 0.5), xEnd: .value("일", 10.0),
                        yStart: .value("시나리오 바탕", 0), yEnd: .value("시나리오 바탕", upper))
                        .foregroundStyle(SOOMColor.surfaceMuted)
                }
                ForEach(days) { day in
                    if metric == .recentTrend, let lo = day.lower, let hi = day.upper {
                        AreaMark(x: .value("일", x(day.date)), yStart: .value("하한", lo), yEnd: .value("상한", hi))
                            .foregroundStyle(by: .value("범위 구간", String(day.bandGroup))).interpolationMethod(.linear)
                    }
                    if let value = metric.value(day) {
                        if metric == .recentTrend && (day.isForecast || days.first(where: \.isForecast).map({ x(day.date) == x($0.date) - 1 }) == true) {
                            LineMark(x: .value("일", x(day.date)), y: .value("추가 운동 없음", value), series: .value("시나리오", "forecast"))
                                .foregroundStyle(.gray).lineStyle(StrokeStyle(lineWidth: 1, dash: [3,4]))
                        }
                        PointMark(x: .value("일", x(day.date)), y: .value(metric.label, value))
                            .symbol { Circle().stroke(Color.gray, lineWidth: 1.4).background(Circle().fill(SOOMColor.surface)).frame(width: day.isForecast ? 4 : 7, height: day.isForecast ? 4 : 7) }
                            .accessibilityLabel(Text("\(day.key), \(value.formatted()) AU, \(metric.stateLabel(day))"))
                        if day.date == selectedDate {
                            PointMark(x: .value("일", x(day.date)), y: .value("선택", value))
                                .symbol { Circle().fill((metric == .recentTrend ? day.state.tint : Color.gray).opacity(0.2)).frame(width: 26, height: 26).overlay(Circle().fill(metric == .recentTrend ? day.state.tint : Color.gray).frame(width: 8,height: 8)) }
                        }
                    }
                    if day.workoutPresent {
                        PointMark(x: .value("일", x(day.date)), y: .value("운동한 날", -upper * 0.06))
                            .symbol(.diamond).symbolSize(10).foregroundStyle(.gray).accessibilityHidden(true)
                    }
                }
                RuleMark(x: .value("선택 날짜", x(selectedDate))).foregroundStyle(Color.gray.opacity(0.6))
            }
            .chartXScale(domain: 0.0...10.0).chartYScale(domain: (-upper * 0.1)...upper)
            .chartForegroundStyleScale(domain: groups, range: groups.map { _ in ActivityLoadPalette.band }).chartLegend(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: stride(from: 0.0, through: upper, by: upper / 3).map { $0 }) { AxisValueLabel().font(.caption2) } }
            .chartXAxis { AxisMarks(values: (0...10).map(Double.init)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.gray.opacity(0.3))
                if let raw = value.as(Double.self), let date = calendar.date(byAdding: .day, value: Int(raw.rounded()), to: start) {
                    let index = Int(raw.rounded())
                    let number = calendar.component(.day, from: date)
                    if index == 0 || number % 2 == 0 || calendar.isDate(date, inSameDayAs: selectedDate) {
                        AxisValueLabel { Text(index == 0 ? "\(calendar.component(.month, from: date)).\(number)" : "\(number)").font(.caption2).foregroundStyle(SOOMColor.secondaryInk) }
                    }
                }
            } }
            .chartXSelection(value: $daySelection)
            .onChange(of: daySelection) { _, index in
                if let index { selection = calendar.date(byAdding: .day, value: Int(min(10, max(0, index)).rounded()), to: start) }
            }
            .frame(height: chartHeight).padding(.trailing, 2)
        }.padding(.horizontal, 16).padding(.top, 6).accessibilityIdentifier("activity.load.chart")
            .accessibilityRepresentation {
                ActivityLoadAccessibleChart(days: days, selection: $selection, metric: metric)
            }
    }
}

private struct ActivityLoadAccessibleChart: View {
    let days: [ActivityLoadDay]
    @Binding var selection: Date?
    let metric: ActivityLoadGraphMetric
    private func value(_ day: ActivityLoadDay) -> String {
        let amount = metric.value(day).map { String(format: "%.3f AU", $0) } ?? "미확인"
        return [amount, day.inputSummary, metric.stateLabel(day)].joined(separator: ", ")
    }
    var body: some View {
        VStack {
            Text("잠정 참고 부하 차트").accessibilityAddTraits(.isHeader)
            ForEach(days) { day in
                Button(day.key) { selection = day.date }
                    .accessibilityLabel(day.key + " " + metric.label)
                    .accessibilityValue(value(day))
                    .accessibilityHint("이 날짜를 선택합니다. 날짜별 기록 버튼에서 세션을 확인할 수 있습니다.")
                    .accessibilityIdentifier("activity.load.chart.day." + day.key)
            }
        }
    }
}

private struct ActivityLoadReadProbe: ViewModifier {
    let count: Int
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_ACTIVITY_LOAD_QA"] == "1" {
            content.accessibilityValue("snapshot-load-count=\(count)")
        } else { content }
        #else
        content
        #endif
    }
}
