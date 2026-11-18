import SwiftUI
import UIKit
import HealthKit
import SwiftData

@MainActor
private enum WorkoutEffortEditorFactory {
    static func make(workoutID:UUID,directory:URL,isDemo:Bool,workout:UnifiedWorkout?,canAccess:@escaping ()->Bool)->WorkoutEffortEditor {
        var store: any WorkoutEffortStoring = isDemo ? FixtureWorkoutEffortStore() : FileWorkoutEffortStore(scopeDirectory:directory,canAccess:canAccess)
        var estimate=workout.flatMap {FileActivityLoadStore(scope:directory,allowed:canAccess).automaticEstimate($0,maximum:TrainingSettingsStore.shared.loadSettings().maxHeartRate,at:Date())}
        #if DEBUG && targetEnvironment(simulator)
        if isDemo, let qa=ActivityLoadQAFixture.effortDirectory(base:directory) { store=FileWorkoutEffortStore(scopeDirectory:qa,canAccess:canAccess) }
        if ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_SCORE_EDITOR_QA"] == "1" {
            estimate=ActivityLoadEstimate(value:7.5,method:ActivityLoadRules.automaticMethod,settingsVersion:"synthetic:maxHR:200",source:"synthetic",confidence:"낮음 · 합성 UI 예시",computedAt:Date())
            if ProcessInfo.processInfo.environment["SOOM_SCORE_EDITOR_QA_MODE"] == "product",
               let fixture = ActivityLoadQAFixture.make(automated: true, missingBaseline: true).recent.first {
                estimate = ActivityLoadEstimate.automatic(fixture, maximum: nil, at: Date())
            }
        }
        // The weekly fixture deliberately has no configured maximum; use the
        // same input in its real editor instead of the demo account's setting.
        if isDemo, ReviewDemoMode.isActive,
           ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
           ProcessInfo.processInfo.environment["SOOM_WEEKLY_PARTIAL_QA"] == "1",
           ["D4110000-0000-4000-8000-000000000001", "D4120000-0000-4000-8000-000000000002", "D4130000-0000-4000-8000-000000000003"].contains(workoutID.uuidString),
           let workout {
            estimate = ActivityLoadEstimate.automatic(workout, maximum: nil, at: Date())
        }
        #endif
        let editor=WorkoutEffortEditor(workoutID:workoutID,store:store,sessionContext:workout.map(WorkoutEffortSessionContext.init),automaticEstimate:estimate)
        if workout != nil && !isDemo { editor.refreshScoreComparison(nil) }
        return editor
    }
}

@MainActor
private func refreshEffortComparison(_ editor:WorkoutEffortEditor,workout:UnifiedWorkout,context:ModelContext,scope:String,directory:URL,at:Date,canAccess:@escaping ()->Bool) {
    do {
        let result=try ActivityLoadStoredHeartRateReader(context:context,scope:scope).effortComparisonAssessment(for:workout,directory:directory,
            maximum:TrainingSettingsStore.shared.loadSettings().maxHeartRate,at:at,allowed:canAccess)
        editor.refreshScoreComparison(result.range, assessment: result)
    } catch { editor.refreshScoreComparison(nil,unavailable:true) }
}

/// The workout detail and activity graph use the same editor and sheet.
struct WorkoutEffortControl: View {
    @StateObject private var editor:WorkoutEffortEditor
    @Environment(\.workoutEffortEditorOverride) private var override
    @Environment(\.modelContext) private var context
    private let workout:UnifiedWorkout?
    private let canAccess:()->Bool
    private let scope:String
    private let directory:URL
    init(workoutID:UUID,directory:URL,isDemo:Bool,workout:UnifiedWorkout?=nil,canAccess:@escaping ()->Bool={true}) {
        self.workout=workout;self.canAccess=canAccess;self.scope=directory.lastPathComponent;self.directory=directory
        _editor=StateObject(wrappedValue:WorkoutEffortEditorFactory.make(workoutID:workoutID,directory:directory,isDemo:isDemo,workout:workout,canAccess:canAccess))
    }
    private func refreshEvidence() {
        guard override == nil,let workout,!ReviewDemoMode.isActive else{return}
        guard canAccess() else {editor.refreshScoreComparison(nil,unavailable:true);return}
        let stored=(try? ActivityLoadStoredHeartRateReader(context:context,scope:scope).read([workout]))?[workout.id]
        let at = Date()
        let history = ActivityLoadEstimate.measuredMean(workout, stored: stored) == nil
            ? (try? ActivityLoadStoredHeartRateReader(context: context, scope: scope).historicalReference(for: workout, directory: directory, at: at, allowed: canAccess)) : nil
        editor.refreshAutomaticEstimate(FileActivityLoadStore(scope:directory,allowed:canAccess).automaticEstimate(workout,maximum:TrainingSettingsStore.shared.loadSettings().maxHeartRate,at:at,stored:stored,history:history))
        refreshEffortComparison(editor,workout:workout,context:context,scope:scope,directory:directory,at:at,canAccess:canAccess)
    }
    var body:some View { WorkoutEffortRow(editor:override ?? editor)
        .task {await (override ?? editor).load();refreshEvidence()}
        .onReceive(NotificationCenter.default.publisher(for:ActivityLoadRules.changed)){_ in refreshEvidence()}
        .onReceive(NotificationCenter.default.publisher(for:ActivityLoadCalibrationRules.changed)){note in
            if note.object as? String == directory.path {refreshEvidence()}
        }
        .onReceive(NotificationCenter.default.publisher(for:HealthKitDetailReadCache.measurementsChanged)){note in
            if note.object as? String == scope {refreshEvidence()}
        }
    }
}

struct WorkoutEffortDirectEntry:View {
    @StateObject private var editor:WorkoutEffortEditor
    @State private var began=false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let workout:UnifiedWorkout
    private let canAccess:()->Bool
    private let scope:String
    private let directory:URL
    init(workout:UnifiedWorkout,directory:URL,isDemo:Bool,canAccess:@escaping ()->Bool) {
        self.workout=workout;self.canAccess=canAccess;self.scope=directory.lastPathComponent;self.directory=directory
        _editor=StateObject(wrappedValue:WorkoutEffortEditorFactory.make(workoutID:workout.id,directory:directory,isDemo:isDemo,workout:workout,canAccess:canAccess))
    }
    private func start() async {
        await editor.load()
        guard canAccess() else {editor.refreshScoreComparison(nil,unavailable:true);return}
        if !ReviewDemoMode.isActive {
            let stored=(try? ActivityLoadStoredHeartRateReader(context:context,scope:scope).read([workout]))?[workout.id]
            let at = Date()
        let history = ActivityLoadEstimate.measuredMean(workout, stored: stored) == nil
            ? (try? ActivityLoadStoredHeartRateReader(context: context, scope: scope).historicalReference(for: workout, directory: directory, at: at, allowed: canAccess)) : nil
        editor.refreshAutomaticEstimate(FileActivityLoadStore(scope:directory,allowed:canAccess).automaticEstimate(workout,maximum:TrainingSettingsStore.shared.loadSettings().maxHeartRate,at:at,stored:stored,history:history))
        refreshEffortComparison(editor,workout:workout,context:context,scope:scope,directory:directory,at:at,canAccess:canAccess)
        }
        editor.begin();began=editor.isEditing
    }
    var body:some View {
        Group {
            if editor.isLoading {ProgressView("운동 강도 불러오는 중")}
            else if !editor.isEditing,let error=editor.error {
                VStack(spacing:16){Text(error);Button("다시 불러오기"){Task{await start()}};Button("닫기"){dismiss()}}.padding()
            } else {WorkoutEffortSheet(editor:editor)}
        }
        .task {await start()}
        .onChange(of:editor.isEditing){_,editing in if began && !editing {dismiss()}}
        .presentationDetents([.large]).presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(editor.isSaving)
    }
}

struct WorkoutEffortRow: View {
    @ObservedObject var editor: WorkoutEffortEditor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.workoutDetailReduceMotion) private var previewReduced
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { editor.begin() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(SOOMColor.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("운동강도").font(.headline).foregroundStyle(SOOMColor.ink)
                        Text(editor.sourceLabel).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Text(editor.displayedLabel)
                        .font(.headline.monospacedDigit()).foregroundStyle(SOOMColor.accentInk)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(SOOMColor.secondaryInk)
                }.padding(16).frame(minHeight: 60)
                    .background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain).disabled(editor.isLoading)
                .accessibilityIdentifier("effort.open")
                .accessibilityHint(editor.displayedValue == nil ? "운동 강도를 1부터 10까지 직접 지정합니다." : "운동 강도를 1부터 10까지 지정하거나 직접 입력을 해제합니다.")
            if let error = editor.error, !editor.isEditing {
                Text(error).font(.footnote).foregroundStyle(SOOMColor.run)
                Button("다시 불러오기") { Task { await editor.load() } }.frame(minHeight: 44)
            }
        }
        .sheet(isPresented: Binding(get: { editor.isEditing }, set: { if !$0 { editor.cancel() } })) {
            WorkoutEffortSheet(editor: editor)
                .dynamicTypeSize(dynamicTypeSize)
                .environment(\.workoutDetailReduceMotion, previewReduced)
        }
    }
}

enum WorkoutEffortStyle {
    // The complete effort spectrum remains visible at every selection.
    private static let stops: [(Double, Double, Double)] = [
        (0.45,0.68,0.81), (0.95,0.78,0.23), (0.98,0.48,0.17),
        (0.85,0.24,0.40), (0.55,0.34,0.84)
    ]
    private static let steps = [1.0, 3, 5, 7, 10]
    static let spectrum = Gradient(stops: steps.map { .init(color: color($0), location: ($0 - 1) / 9) })
    private static func rgb(_ value: Double) -> (Double, Double, Double) {
        let value = min(10, max(1, value))
        let i = (0..<4).first { value <= steps[$0 + 1] } ?? 3
        let t = (value - steps[i]) / (steps[i + 1] - steps[i])
        let a=stops[i], b=stops[i+1]
        return (a.0+(b.0-a.0)*t,a.1+(b.1-a.1)*t,a.2+(b.2-a.2)*t)
    }
    static func color(_ value: Double) -> Color {
        let c=rgb(value); return Color(red:c.0,green:c.1,blue:c.2)
    }
    static func foreground(_ value: Double) -> Color {
        let c=rgb(value)
        func linear(_ v:Double)->Double { v <= 0.04045 ? v/12.92 : pow((v+0.055)/1.055,2.4) }
        let luminance=0.2126*linear(c.0)+0.7152*linear(c.1)+0.0722*linear(c.2)
        // Choose the higher contrast neutral text (at least 4.58:1).
        return luminance > 0.179 ? .black : .white
    }
    static func title(_ value: Int?, isManualSelection: Bool = false) -> String {
        guard let value else { return "점수를 선택해 주세요" }
        if !isManualSelection {
            switch value { case 0: return "기존 0점 · 보존"; case 1...3: return "낮은 쪽 점수"; case 4...6: return "중간 쪽 점수"; case 7...9: return "높은 쪽 점수"; default: return "점수 척도의 상한" }
        }
        switch value { case 0: return "기존 0점 · 보존"; case 1...3: return "가볍게 느껴졌어요"; case 4...6: return "적당히 힘들었어요"; case 7...9: return "많이 힘들었어요"; default: return "아주 많이 힘들었어요" }
    }
    static func description(_ value: Int?, isManualSelection: Bool = false) -> String {
        guard let value else { return "원을 움직여 SOOM 점수를 직접 지정해 주세요." }
        if !isManualSelection {
            switch value { case 0: return "사용자가 지정한 척도 하한이며, 자료 없음과는 달라요."; case 1...3: return "0–10 점수 척도에서 낮은 쪽이에요."; case 4...6: return "0–10 점수 척도에서 중간 쪽이에요."; case 7...9: return "0–10 점수 척도에서 높은 쪽이에요."; default: return "10은 점수 척도의 상한이며, 신체 최대 능력의 측정값은 아니에요." }
        }
        switch value { case 0: return "사용자가 지정한 척도 하한이며, 자료 없음과는 달라요."; case 1...3: return "숨이 편안하고 대화하기 쉬웠어요."; case 4...6: return "숨이 조금 찼지만 대화할 수 있었어요."; case 7...9: return "숨이 차고 길게 말하기 어려웠어요."; default: return "숨이 많이 차고 말하기 어려웠어요." }
    }
}

struct WorkoutEffortSheet: View {
    @ObservedObject var editor: WorkoutEffortEditor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.workoutDetailReduceMotion) private var previewReduced
    @Environment(\.scenePhase) private var scenePhase
    private var motionReduced: Bool { reduceMotion || previewReduced }
    @StateObject private var character = SoomCharacterPlayer()
    @State private var scrollQA = ""
    @State private var dragging = false
    @State private var haptics = WorkoutEffortHaptics()
    private var value: Double { editor.draft ?? 5 }
    private var tint: Color { WorkoutEffortStyle.color(value) }
    private var isAboveUsual: Bool {
        guard let draft=editor.draft, let range=editor.usualRange else { return false }
        return (editor.selectedValue.map(Double.init) ?? draft) > range.upper
    }
    private var saveDetail:String? {editor.selectedValue.map {"운동 강도 \($0) / 10"}}
    private var showsAutomaticProposal: Bool { editor.selectedValue == nil && !editor.isUsingSavedOverride && editor.automaticEstimate != nil }
    private var displayedEffortTitle: String {
        if editor.selectedValue == nil && editor.isUsingSavedOverride { return "기존 입력" }
        if showsAutomaticProposal, let estimate = editor.automaticEstimate { return estimate.isInitial ? "초기 추정" : "자동 제안" }
        return WorkoutEffortStyle.title(editor.selectedValue, isManualSelection: editor.selectedValue != nil)
    }
    private var displayedEffortValue: String {
        if showsAutomaticProposal, let estimate = editor.automaticEstimate {
            return estimate.value.formatted(.number.precision(.fractionLength(0...2))) + " / 10"
        }
        return editor.draftScoreLabel
    }
    private var automaticDescription: String { "자동으로 제안한 SOOM 점수예요. 직접 조절하면 선택한 점수가 우선해요." }
    // Reserve copy height so score changes never move the touch surface.
    @ScaledMetric(relativeTo: .title3) private var titleLineHeight: CGFloat = 26
    private var effortTitle: some View {
        Text(displayedEffortTitle)
            .font(.title3.weight(.semibold)).lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(0.8)
            .frame(height: titleLineHeight * (dynamicTypeSize.isAccessibilitySize ? 2 : 1))
            .accessibilityIdentifier("effort.state")
    }
    private var effortDescription: some View {
        ZStack(alignment: .top) {
            ForEach(Array(Set([editor.automaticEstimate == nil ? WorkoutEffortStyle.description(nil, isManualSelection: true) : automaticDescription] + (1...10).map { WorkoutEffortStyle.description($0, isManualSelection: true) })).sorted(), id: \.self) { description in
                Text(description).fixedSize(horizontal: false, vertical: true).hidden().accessibilityHidden(true)
            }
            Text(showsAutomaticProposal ? automaticDescription : WorkoutEffortStyle.description(editor.selectedValue, isManualSelection: editor.selectedValue != nil))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("effort.description")
        }.font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }
    private var effortValue: some View {
        Text(displayedEffortValue).fixedSize(horizontal: false, vertical: true)
            .font(.subheadline.weight(.medium).monospacedDigit())
            .foregroundStyle(SOOMColor.secondaryInk).accessibilityIdentifier("effort.value")
    }
    private var effortSource: some View {
        let automatic = editor.automaticEstimate.map { estimate in
            (estimate.isInitial ? "초기 추정 " : "자동 추정 ") + estimate.value.formatted(.number.precision(.fractionLength(0...2))) + " / 10 · " + estimate.confidence
        }
        let manual = "직접 지정 · 체감 표현은 참고 예시"
        return ZStack {
            Text(automatic ?? editor.sourceLabel).hidden().accessibilityHidden(true)
            Text(manual).hidden().accessibilityHidden(true)
            Text(editor.selectedValue == nil && editor.isUsingSavedOverride ? editor.sourceLabel + " · 기존 입력 보존" : editor.selectedValue == nil ? automatic ?? editor.sourceLabel : manual)
                .accessibilityIdentifier(editor.automaticEstimate?.isInitial == true && !editor.isUsingSavedOverride ? "effort.initialEstimate" : "effort.source.label")
        }.font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }
    private func rangeSummary(_ range: WorkoutEffortUsualRange) -> String {
        let base = range.comparisonVersion == nil
            ? "내 입력 점수 범위 \(range.label) · 21일 · \(range.count)개"
            : "같은 종목 \(range.displayTitle) \(range.label) · 이전 21일 · 자동 \(range.automaticCount)개/수정 \(range.count-range.automaticCount)개"
                + (range.automaticCount > 0 ? " · 낮은 신뢰" : "")
        guard let mean = range.referenceMean, mean.isFinite else { return base }
        return base + " · 평균 " + mean.formatted(.number.precision(.fractionLength(0...1)))
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                    VStack(spacing: 6) {
                        Text("운동강도").font(.title2.weight(.bold)).foregroundStyle(SOOMColor.ink)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("effort.title")
                        if ReviewDemoMode.isActive {
                            Text("DEMO · 합성 강도 · 이 체험에서만 유지돼요")
                                .font(.caption).foregroundStyle(SOOMColor.accentInk)
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("effort.fixture")
                        }
                    }.frame(maxWidth: .infinity).padding(.top, 12)
                    VStack(spacing: 16) {
                        Text("운동이 어땠나요?").font(.headline)
                            .accessibilityIdentifier("effort.question")
                        SoomCharacterView(player: character, size: 108, reduceMotionPreview: motionReduced)
                            .accessibilityIdentifier("effort.character")
                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(spacing: 6) { effortTitle; effortValue }
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 8) { effortTitle; effortValue }
                            }
                        }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
                            .transaction { $0.animation = nil }
                        effortDescription
                        effortSource
                        EffortScale(value: value, selected: editor.selectedValue,
                            range: editor.usualRange, dragging: dragging, reduced: motionReduced,
                            accessibilityValueOverride: showsAutomaticProposal ? displayedEffortTitle + ", " + displayedEffortValue + ", 직접 지정 전" : editor.usesSessionScale ? editor.scoreAccessibilityValue : nil,
                            valueLabelOverride: nil,
                            onMove: { next in
                                if !dragging { haptics.begin(value) }
                                dragging = true; editor.preview(next)
                                haptics.move(value, reduced: motionReduced)
                            }, onEnd: { dragging = false; haptics.end() },
                            onAdjust: { delta in
                                haptics.begin(value); editor.adjustScore(Int(delta))
                                haptics.move(value, reduced: true); haptics.end()
                            })
                            .disabled(editor.isSaving)
                        if let range = editor.usualRange {
                            Text("평소 범위 \(range.label) · \(range.count)개 기록 기준")
                                .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center).accessibilityLabel(rangeSummary(range)).accessibilityIdentifier("effort.range.summary")
                        } else {
                            Text(editor.historyUnavailable
                                 ? "비교 점수를 불러오지 못했어요. 범위 없이 점수를 지정할 수 있어요."
                                 : editor.comparisonAssessment?.message
                                    ?? (editor.usesCurrentScoreComparison
                                        ? "같은 종목의 비교 점수를 확인하고 있어요. 범위 없이 점수를 지정할 수 있어요."
                                        : "비교 자료가 부족해 범위를 표시하지 않아요. 최근 21일의 다른 운동 점수가 5개 이상이면 보여요."))
                                .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center).accessibilityIdentifier("effort.range.empty")
                        }
                        if let error = editor.error {
                            Text(error).font(.footnote).foregroundStyle(SOOMColor.run)
                                .accessibilityIdentifier("effort.error")
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("effort.scoreCard")
                    Divider()
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(editor.sourceLabel)
                            if let range = editor.usualRange { Text(rangeSummary(range)) }
                            Text("직접 지정은 1–10의 정수 단계예요. 저장한 값이 자동 추정을 대체하며, 열거나 취소한 것만으로는 저장하지 않아요. 시간은 운동 기록의 값을 사용해 부하 계산에 한 번만 반영해요.")
                            Text("이전 입력과 0점은 그대로 보존해요. 새로 지정해 저장하거나 직접 입력을 해제할 때만 바뀝니다.")
                            Text(editor.usesCurrentScoreComparison ? "비교 범위는 같은 종목에서 이 운동 이전 21일의 자동·수정 최종점수 가운데 50%(Q25–Q75)예요. 최소 5개가 필요하며 수동 수정은 그 운동의 자동값을 대체해요. 현재 운동·미래 운동·중복·겹침은 빼고, 심박 없이 과거 입력을 복제한 초기 추정도 중복 표본으로 세지 않아요. 현재 계산 기준으로 다시 계산하며 자동값이 포함되면 낮은 신뢰의 추정 범위예요. 활동 그래프의 이전 56일 부하 범위(Q10–Q90)와 다르고 시간으로 가중하지 않아요." : "내 입력 점수 범위는 최근 21일 저장한 다른 운동 강도의 가운데 50%(Q25–Q75)이며 최소 5개가 필요해요. 현재 운동은 빼며, 활동 그래프의 이전 56일 부하 범위(Q10–Q90)와는 달라요.")
                            Text("위의 표현은 직접 강도를 고를 때 참고하는 예시예요. 자동 추정은 실제 호흡이나 체감을 측정한 값이 아니에요.")
                            Text("자동 추정과 범위는 개인 기록 참고용이며 검증된 RPE 측정이나 안전·과훈련 판정이 아니에요.")
                            if editor.automaticEstimate?.isInitial == true {
                                Text(editor.automaticEstimate?.method == ActivityLoadRules.historyPriorMethod
                                     ? "이 초기 추정은 앞선 같은 종목의 직접 입력을 참고한 값으로 현재 운동의 측정값이 아니에요. 직접 지정하면 그 값이 우선해요."
                                     : "이 초기 추정은 평균심박÷20을 1–10으로 제한한 SOOM 제품 기준이에요. 개인 최대심박이나 FTP를 측정·설정한 값이 아니며 직접 지정하면 그 값이 우선해요.")
                            }
                            Text(ReviewDemoMode.isActive ? "합성값만 사용해요. 건강 앱에 접근하거나 저장하지 않습니다." : "SOOM의 이 기기에만 저장돼요. Apple 원본 기록은 유지됩니다.")
                        }.font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                            .accessibilityIdentifier("effort.guide.content")
                    } label: {
                        Text("강도 평가 방법").font(.subheadline).foregroundStyle(SOOMColor.ink).frame(minHeight: 44)
                    }.tint(SOOMColor.secondaryInk).accessibilityIdentifier("effort.guide")
                }.padding(.horizontal, SOOMLayout.screenPadding).padding(.bottom, 12)
            }
            .clipped().accessibilityIdentifier("effort.scroll")
            .onScrollGeometryChange(for: String.self) { g in
                "offset=\(Int(g.contentOffset.y)) content=\(Int(g.contentSize.height)) viewport=\(Int(g.containerSize.height))"
            } action: { _, value in if ReviewDemoMode.isActive { scrollQA = value } }
            .accessibilityValue(ReviewDemoMode.isActive ? scrollQA : "")
            .environment(\.isScrollEnabled, true)
            VStack(spacing: 8) {
                Button {
                    haptics.end(); Task { await editor.save() }
                } label: {
                    VStack(spacing: 3) {
                        HStack {
                            if editor.isSaving { ProgressView().tint(WorkoutEffortStyle.foreground(value)) }
                            Text(editor.isSaving ? "저장 중…" : "저장").font(.headline)
                        }
                        Text(saveDetail ?? "운동 강도 10 / 10").font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(saveDetail == nil ? 0 : 1).accessibilityHidden(saveDetail == nil)
                    }
                    .foregroundStyle(editor.canSave ? WorkoutEffortStyle.foreground(value) : .white)
                    .padding(.vertical, 11).frame(maxWidth: .infinity, minHeight: 58)
                    .background(editor.canSave ? tint : SOOMColor.secondaryInk, in: Capsule())
                }.disabled(!editor.canSave).accessibilityLabel(editor.isSaving ? "저장 중…" : "저장")
                    .accessibilityValue(saveDetail ?? "선택 전").accessibilityIdentifier("effort.save")
                if editor.usesSessionScale && editor.confirmation != nil {
                    Button { haptics.end(); Task { await editor.clearConfirmation() } } label: {
                        Text(editor.automaticEstimate == nil ? "수정 해제 · 점수 미입력으로" : "수정 해제 · 자동 제안으로")
                            .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(editor.isSaving).accessibilityIdentifier("effort.clear")
                }
                Button { haptics.end(); editor.cancel() } label: {
                    Text("취소").font(.headline).foregroundStyle(SOOMColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(SOOMColor.ink.opacity(0.04), in: Capsule())
                }.disabled(editor.isSaving).accessibilityIdentifier("effort.cancel")
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
        }
        .presentationBackground(SOOMColor.surface)
        .presentationCornerRadius(36)
        .presentationDetents([.large]).presentationDragIndicator(.hidden)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(editor.isSaving || dragging)
        .preferredColorScheme(.light)
        .onAppear { character.setEffort(value, aboveUsual: isAboveUsual); haptics.prepare() }
        .onChange(of: value) { _, next in character.setEffort(next, aboveUsual: isAboveUsual) }
        .onChange(of: isAboveUsual) { _, above in character.setEffort(value, aboveUsual: above) }
        .onChange(of: motionReduced) { _, _ in dragging = false; haptics.end() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { dragging = false; haptics.end() } else { haptics.prepare() }
        }
        .onDisappear { dragging = false; haptics.end() }
    }
}


/// Geometry expands only within the reserved gutter, so 1 and 10 never clip.
/// Touch mapping always uses the fully expanded track and stays stable mid-drag.
struct EffortScaleGeometry {
    static func x(_ value: Double, width: Double, expansion: Double) -> Double {
        let gutter = 22 + 12 * (1 - min(1, max(0, expansion)))
        return gutter + (min(10, max(1, value)) - 1) / 9 * max(1, width - 2 * gutter)
    }
    static func value(at x: Double, width: Double) -> Double {
        1 + 9 * min(1, max(0, (x - 22) / max(1, width - 44)))
    }
    static func calloutCenter(_ value: Double, width: Double, calloutWidth: Double, expansion: Double) -> Double {
        let half = min(max(0, width), max(0, calloutWidth)) / 2
        return min(width - half, max(half, x(value, width: width, expansion: expansion)))
    }
    static func emphasis(_ value: Double, range: WorkoutEffortUsualRange) -> ClosedRange<Double>? {
        guard value.isFinite else { return nil }
        let value = min(10, max(1, value))
        if value > range.upper { return range.upper...value }
        if value < range.lower { return value...range.lower }
        return nil
    }
}

struct EffortScaleInteraction: Equatable {
    private(set) var isExpanded = false
    private(set) var isDragging = false
    mutating func press() { isExpanded = true }
    mutating func drag() { isExpanded = true; isDragging = true }
    mutating func end() { isDragging = false }
    mutating func collapse() { isExpanded = false; isDragging = false }
    func showsHatching(hasRange: Bool) -> Bool { hasRange && isExpanded }
}

private struct EffortScale: View {
    let value: Double
    let selected: Int?
    let range: WorkoutEffortUsualRange?
    let dragging: Bool
    let reduced: Bool
    var accessibilityValueOverride: String? = nil
    var valueLabelOverride: String? = nil
    let onMove: (Double) -> Void
    let onEnd: () -> Void
    let onAdjust: (Double) -> Void
    @ScaledMetric(relativeTo: .caption) private var calloutWidth: CGFloat = 126
    @ScaledMetric(relativeTo: .caption) private var calloutHeight: CGFloat = 24
    @State private var interaction = EffortScaleInteraction()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if DEBUG && targetEnvironment(simulator)
    @State private var lastGesture = EffortGestureEvidence()
    @State private var hatchPresentations = 0
    #endif
    private var gestureReporter: ((EffortGestureEvidence) -> Void)? {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_EFFORT_GESTURE_QA"] == "1" {
            return { lastGesture = $0 }
        }
        #endif
        return nil
    }
    private func recordHatchPresentation() {
        #if DEBUG && targetEnvironment(simulator)
        if gestureReporter != nil { hatchPresentations += 1 }
        #endif
    }
    private var gestureQASuffix: String {
        #if DEBUG && targetEnvironment(simulator)
        if gestureReporter != nil {
            return String(format: ", QA hatch=%d drag=%d pans=%d restored=%d maxY=%.2f maxScroll=%.2f cancelled=%d", hatchPresentations,
                lastGesture.didDrag ? 1 : 0, lastGesture.ancestorPans, lastGesture.restoredPans,
                Double(lastGesture.maxVerticalShift), Double(lastGesture.maxScrollShift), lastGesture.cancelled ? 1 : 0)
        }
        #endif
        return ""
    }
    private var trackHeight: CGFloat { interaction.isExpanded ? 126 : 90 }
    private var trackY: CGFloat { interaction.isExpanded ? 68 : 48 }
    private var expansion: Double { interaction.isExpanded ? 1 : 0 }
    private var showHatching: Bool { interaction.showsHatching(hasRange: range != nil) }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if let selected {
                    let badgeWidth = min(calloutWidth, geometry.size.width)
                    Text(selectionLabel(selected, short: dynamicTypeSize.isAccessibilitySize))
                        .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(WorkoutEffortStyle.foreground(value))
                        .frame(width: badgeWidth, height: calloutHeight)
                        .background(WorkoutEffortStyle.color(value), in: Capsule())
                        .position(x: EffortScaleGeometry.calloutCenter(value, width: geometry.size.width,
                            calloutWidth: badgeWidth, expansion: expansion), y: calloutHeight / 2)
                        .accessibilityLabel(Text(selectionLabel(selected)))
                        .accessibilityIdentifier(range == nil ? "effort.selection.status" : "effort.range.status")
                }
            }.frame(height: calloutHeight + 4)
            GeometryReader { geometry in
                let width = geometry.size.width
                let start = EffortScaleGeometry.x(1, width: width, expansion: expansion)
                let end = EffortScaleGeometry.x(10, width: width, expansion: expansion)
                let thumb = EffortScaleGeometry.x(value, width: width, expansion: expansion)
                ZStack(alignment: .topLeading) {
                    if let range, showHatching {
                        let lo = EffortScaleGeometry.x(range.lower, width: width, expansion: expansion)
                        let hi = EffortScaleGeometry.x(range.upper, width: width, expansion: expansion)
                        ZStack(alignment: .topLeading) {
                            hatch(from: start, to: lo, color: SOOMColor.secondaryInk.opacity(0.24))
                            hatch(from: hi, to: end, color: SOOMColor.secondaryInk.opacity(0.24))
                            if selected != nil, let emphasis = EffortScaleGeometry.emphasis(value, range: range) {
                                hatch(from: EffortScaleGeometry.x(emphasis.lowerBound, width: width, expansion: expansion),
                                      to: EffortScaleGeometry.x(emphasis.upperBound, width: width, expansion: expansion),
                                      color: WorkoutEffortStyle.color(value).opacity(0.68))
                            }
                        }
                        .frame(width: width, height: trackHeight, alignment: .topLeading)
                        .allowsHitTesting(false)
                        .transaction { $0.animation = nil }
                        .onAppear { recordHatchPresentation() }
                    }
                    EffortWedge(amount: interaction.isExpanded ? 0.65 : 0.18)
                        .fill(LinearGradient(gradient: WorkoutEffortStyle.spectrum, startPoint: .leading, endPoint: .trailing))
                        .opacity(0.32)
                        .overlay(alignment: .leading) {
                            EffortWedge(amount: interaction.isExpanded ? 0.65 : 0.18)
                                .fill(LinearGradient(gradient: WorkoutEffortStyle.spectrum, startPoint: .leading, endPoint: .trailing))
                                .mask(alignment: .leading) { Rectangle().frame(width: selected == nil ? 0 : thumb - start) }
                        }
                        .frame(width: end - start, height: 64).offset(x: start, y: trackY - 32)
                    ForEach(1...10, id: \.self) { tick in
                        let x = EffortScaleGeometry.x(Double(tick), width: width, expansion: expansion)
                        Text(String(tick)).font(.subheadline.monospacedDigit()).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(SOOMColor.ink)
                            .position(x: x, y: 14)
                            .accessibilityIdentifier("effort.tick.\(tick)")
                        Capsule().fill(.white.opacity(0.8))
                            .frame(width: 2, height: interaction.isExpanded ? 8 : 5)
                            .position(x: x, y: trackY).accessibilityHidden(true)
                    }
                    Circle().fill(selected == nil ? SOOMColor.secondaryInk.opacity(0.35) : WorkoutEffortStyle.color(value)).frame(width: 32, height: 32)
                        .overlay { Circle().stroke(.white, lineWidth: 4) }
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .position(x: thumb, y: trackY)
                }
                .frame(width: width, height: trackHeight)
                .contentShape(Rectangle())
                // Horizontal score pans own the touch; vertical pans still scroll normally.
                // UIKit decides direction before either ancestor pan can begin.
                .overlay {
                    EffortTouchSurface(onPress: { if $0 { interaction.press() } }, onDrag: { active in
                        if active { interaction.drag() } else { interaction.end() }
                    }, onMove: { x in
                        onMove(EffortScaleGeometry.value(at: x, width: width))
                    }, onEnd: onEnd, onEvidence: gestureReporter)
                }
                .onDisappear { interaction.collapse(); onEnd() }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("운동강도")
                .accessibilityValue((accessibilityValueOverride ?? selected.map { "\($0), 10 중" } ?? "선택 전") + ", " + (interaction.isExpanded ? "펼침" : "접힘") + ", " + (showHatching ? "빗금 표시" : "빗금 숨김") + gestureQASuffix)
                .accessibilityHint("위아래로 쓸어 1부터 10까지 한 단계씩 지정하세요. 열기만 해서는 저장되지 않아요.")
                .accessibilityAdjustableAction { direction in
                    interaction.press()
                    switch direction { case .increment: onAdjust(1); case .decrement: onAdjust(-1); @unknown default: break }
                }
                .accessibilityIdentifier("effort.slider")
            }.frame(height: trackHeight)
            Button {
                if interaction.isExpanded { interaction.collapse(); onEnd() } else { interaction.press() }
            } label: {
                HStack(spacing: 5) {
                    Text(range == nil ? "1–10 단계" : "평소 범위")
                    Image(systemName: interaction.isExpanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .medium))
                }.font(.caption).foregroundStyle(SOOMColor.secondaryInk).frame(minHeight: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(interaction.isExpanded ? "조절 영역 접기" : "조절 영역 펼치기")
                .accessibilityIdentifier("effort.expansion")
        }
        .animation(reduced ? nil : .easeInOut(duration: 0.24), value: expansion)
    }
    private func selectionLabel(_ selected: Int, short: Bool = false) -> String {
        if let valueLabelOverride { return "SOOM 점수 " + valueLabelOverride }
        if let range { return range.relation(to: Double(selected)) }
        return "선택 강도 \(selected)"
    }
    private func hatch(from start: CGFloat, to end: CGFloat, color: Color) -> some View {
        EffortHatching().stroke(color, lineWidth: 1.6)
            .frame(width: max(0, end - start), height: 76).clipped().offset(x: start, y: trackY - 38)
    }
}

private struct EffortHatching: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for x in stride(from: -rect.height, through: rect.width, by: 7) {
            p.move(to: CGPoint(x: x, y: rect.maxY)); p.addLine(to: CGPoint(x: x + rect.height, y: 0))
        }
        return p
    }
}

struct EffortWedge: Shape {
    var amount: Double
    var animatableData: Double { get { amount } set { amount = newValue } }
    func path(in rect: CGRect) -> Path {
        let left: CGFloat = 3 + 2 * amount, right: CGFloat = 3 + 27 * amount
        let radius: CGFloat = min(6, right)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - left))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.midY - right))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY - right + radius), control: CGPoint(x: rect.maxX, y: rect.midY - right))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + right - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.midY + right), control: CGPoint(x: rect.maxX, y: rect.midY + right))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + left)); path.closeSubpath()
        return path
    }
}

private struct WorkoutEffortEditorOverrideKey: EnvironmentKey {
    static let defaultValue: WorkoutEffortEditor? = nil
}
extension EnvironmentValues {
    var workoutEffortEditorOverride: WorkoutEffortEditor? {
        get { self[WorkoutEffortEditorOverrideKey.self] }
        set { self[WorkoutEffortEditorOverrideKey.self] = newValue }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Explicit synthetic entry uses the ordinary detail view and existing local
/// demo runtime. Scenarios never read HealthKit or write account/cloud stores.
struct WorkoutDetailMotionQAView: View {
    @StateObject private var tabVisibility = SOOMTabBarVisibility()
    @State private var scenario = ProcessInfo.processInfo.environment["SOOM_EFFORT_LEGACY_ZERO_QA"] == "1" ? "기존 0점" : ProcessInfo.processInfo.environment["SOOM_EFFORT_SPARSE_QA"] == "1" ? "비교 1개" : "없음"
    @State private var reduced = false
    @State private var large = false
    private var workout: UnifiedWorkout {
        // This comparison scenario requires a completed target, including when
        // the UI suite crosses midnight before today's sample has finished.
        if scenario == "자동 점수 범위" || scenario == "비교 1개" || scenario == "기존 0점" {
            return ReviewDemoData.workouts(referenceDate:Date().addingTimeInterval(-86400))[0]
        }
        if scenario.contains("수영") { return ReviewDemoData.workouts().first { $0.workoutType == .swimming }! }
        return scenario.contains("사이클") ? ReviewDemoData.workouts().first { $0.workoutType == .cycling }! : ReviewDemoData.workouts()[0]
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Menu {
                        ForEach(ProcessInfo.processInfo.environment["SOOM_HEALTH_DETAIL_QA"] == "1"
                            ? ["수영 원본 랩", "수영 랩 결측", "심박 요약만", "건강 읽기 오류", "없음"]
                            : ["없음", "평소 범위", "자동 점수 범위", "범위 읽기 실패", "Apple 기록", "Apple 추정", "SOOM 저장값", "저장 실패", "사이클", "마일 러닝", "마일 사이클", "심박 0초", "심박 9퍼센트", "심박 결측"], id: \.self) { item in
                            Button(item) { scenario = item }.accessibilityIdentifier("fixture." + item)
                        }
                    } label: {
                        Text("Fixture · " + scenario).frame(minHeight:44).contentShape(Rectangle())
                    }.accessibilityIdentifier("fixture.menu")
                    Spacer()
                    Toggle("모션 줄이기", isOn: $reduced).labelsHidden().accessibilityLabel("모션 줄이기")
                    Toggle("큰 글자", isOn: $large).labelsHidden().accessibilityLabel("큰 글자")
                }.font(.caption).padding(.horizontal, 16).frame(minHeight:44)
                WorkoutDetailMotionQAScenario(workout: workout, scenario: scenario).id(scenario)
            }
            .environment(\.workoutDetailReduceMotion, reduced)
            .dynamicTypeSize(large ? .accessibility5 : .large)
        }.preferredColorScheme(.light).environmentObject(tabVisibility)
    }
}

private struct WorkoutDetailMotionQAScenario: View {
    let workout: UnifiedWorkout
    @StateObject private var editor: WorkoutEffortEditor
    private let scenario: String
    @State private var didRetry = false
    init(workout: UnifiedWorkout, scenario: String) {
        self.workout = workout
        self.scenario = scenario
        TrainingSettingsStore.shared.savePreferredUnit(scenario.contains("마일") ? .imperial : .metric)
        let fixture = FixtureWorkoutEffortStore()
        if scenario == "Apple 기록" || scenario == "Apple 추정" {
            fixture.observed = WorkoutEffortObservation(value: 6, origin: scenario == "Apple 기록" ? .apple : .appleEstimate,
                sampleID: UUID(), workoutID: workout.id, observedAt: Date())
        }
        if scenario == "SOOM 저장값" { fixture.value = .init(value:4,confirmedAt:Date(),revision:UUID()) }
        if scenario == "평소 범위" || scenario == "비교 1개" {
            fixture.value = .init(value: 7, confirmedAt: Date(), revision: UUID())
            fixture.historyValues = [3, 4, 4, 5, 6, 6, 7].map {
                .init(value: $0, confirmedAt: Date().addingTimeInterval(-86400), revision: UUID())
            }
        }
        if scenario == "비교 1개" { fixture.historyValues = Array(fixture.historyValues.prefix(1)) }
        fixture.failsHistory = scenario == "범위 읽기 실패"
        fixture.failsNextSave = scenario == "저장 실패"
        if scenario == "기존 0점" {
            var legacy = WorkoutEffortConfirmation(value: 0, confirmedAt: Date(), revision: UUID())
            legacy.scaleVersion = ActivityLoadRules.scaleVersion
            legacy.reviewedDurationSeconds = workout.durationSeconds
            legacy.durationPolicy = ActivityLoadRules.legacyDurationPolicy
            legacy.inputControlVersion = nil
            legacy.workoutStart = workout.startDate; legacy.workoutEnd = workout.endDate
            legacy.unit = ActivityLoadRules.intensityUnit; legacy.origin = "user"
            fixture.value = legacy
        }
        let editor=WorkoutEffortEditor(workoutID:workout.id,store:fixture,reader:fixture,
            sessionContext: scenario == "기존 0점" ? WorkoutEffortSessionContext(workout) : nil,
            automaticEstimate: scenario == "기존 0점" ? .init(value:7.5,method:ActivityLoadRules.automaticMethod,settingsVersion:"synthetic:maxHR:200",source:"synthetic",confidence:"낮음 · 합성 UI 예시",computedAt:Date()) : nil)
        if scenario == "자동 점수 범위" || scenario == "비교 1개" {
            let rows=(1...(scenario == "비교 1개" ? 1 : 7)).map { i -> UnifiedWorkout in
                let start=workout.startDate.addingTimeInterval(-Double(i)*86400)
                return UnifiedWorkout(id:UUID(),externalId:UUID().uuidString,source:.manual,workoutType:workout.workoutType,
                    startDate:start,endDate:start.addingTimeInterval(1800),durationSeconds:1800,distanceMeters:nil,activeEnergyKcal:nil,
                    averageHeartRate:Double(90+i*10),maxHeartRate:nil,averageSpeedMetersPerSecond:nil,elevationGainMeters:nil,
                    dataQuality:.complete,createdAt:start,updatedAt:start.addingTimeInterval(1800))
            }
            let result = WorkoutEffortScoreComparison.assessment(for:workout,workouts:rows,confirmations:[:],maximum:nil,at:Date())
            editor.refreshScoreComparison(result.range, assessment: result)
        }
        _editor = StateObject(wrappedValue:editor)
    }
    private var telemetry: WorkoutTelemetry {
        var value = ReviewDemoData.telemetry(for: workout)
        if scenario == "심박 0초" {
            value.heartRateZones = (1...5).map { .init(name: "Z\($0)", durationSeconds: $0 == 1 ? 100 : 0) }
        } else if scenario == "심박 9퍼센트" {
            value.heartRateZones = (1...5).map { .init(name: "Z\($0)", durationSeconds: $0 == 2 ? 9 : ($0 == 5 ? 91 : 0)) }
        } else if scenario == "심박 결측" || scenario == "심박 요약만" {
            value.heartRateZones = []
            value.samples = value.samples.map { var sample = $0; sample.heartRateBPM = nil; return sample }
        }
        if scenario.contains("수영") {
            if scenario == "수영 원본 랩" {
                let events = (0..<4).map { index in
                    HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: workout.startDate.addingTimeInterval(Double(index) * 40), duration: 35), metadata: nil)
                }
                let raw = HKWorkout(activityType: .swimming, start: workout.startDate, end: workout.endDate,
                    workoutEvents: events, totalEnergyBurned: nil, totalDistance: nil,
                    metadata: [HKMetadataKeySwimmingLocationType: NSNumber(value: HKWorkoutSwimmingLocationType.pool.rawValue),
                        HKMetadataKeyLapLength: HKQuantity(unit: .meter(), doubleValue: 25)])
                value.splits = HealthKitWorkoutTelemetryFetcher.swimmingSplits(raw)
            } else { value.splits = [] }
        }
        return value
    }
    var body: some View {
        WorkoutDeepDetailView(workout:Workout(unifiedWorkout:workout),
            telemetryOverride:telemetry,
            healthKitReadPresentation: scenario == "건강 읽기 오류" && !didRetry
                ? .init(message: "일부 측정값을 읽지 못했어요. 이미 표시된 기록은 유지됩니다.", retry: { didRetry = true }) : nil,
            sourceUnifiedWorkout:workout)
            .environment(\.workoutEffortEditorOverride, editor)
    }
}
#endif

private struct WorkoutDetailReduceMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var workoutDetailReduceMotion: Bool {
        get { self[WorkoutDetailReduceMotionKey.self] }
        set { self[WorkoutDetailReduceMotionKey.self] = newValue }
    }
}


/// Direction is decided before the ancestor scroll/presentation pans may begin.
/// Only a horizontal score adjustment leases those pans until end/cancel.
/// Vertical gestures and touches outside this surface keep native scrolling.
private struct EffortTouchSurface: UIViewRepresentable {
    let onPress: (Bool) -> Void
    let onDrag: (Bool) -> Void
    let onMove: (CGFloat) -> Void
    let onEnd: () -> Void
    var onEvidence: ((EffortGestureEvidence) -> Void)? = nil
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    func makeUIView(context: Context) -> EffortTouchView { EffortTouchView() }
    func updateUIView(_ view: EffortTouchView, context: Context) {
        view.onPress = onPress; view.onDrag = onDrag; view.onMove = onMove; view.onEnd = onEnd
        view.onEvidence = onEvidence
        view.acceptsTouches = isEnabled && scenePhase == .active
    }
    static func dismantleUIView(_ view: EffortTouchView, coordinator: ()) { view.cancelInteraction() }
}

struct EffortGestureEvidence: Equatable {
    var ancestorPans = 0
    var restoredPans = 0
    var maxVerticalShift: CGFloat = 0
    var maxScrollShift: CGFloat = 0
    var didDrag = false
    var cancelled = false
}

final class EffortTouchView: UIView, UIGestureRecognizerDelegate {
    var onPress: (Bool) -> Void = { _ in }
    var onDrag: (Bool) -> Void = { _ in }
    var onMove: (CGFloat) -> Void = { _ in }
    var onEnd: () -> Void = {}
    var onEvidence: ((EffortGestureEvidence) -> Void)?
    var acceptsTouches = true {
        didSet {
            guard oldValue != acceptsTouches else { return }
            if !acceptsTouches { cancelInteraction() }
            // A cancellation can disable our own recognizer as well as the view.
            // Explicitly restore it when the scene/control becomes active again.
            pan.isEnabled = acceptsTouches
            isUserInteractionEnabled = acceptsTouches
        }
    }
    private struct PanEntry { weak var pan: UIPanGestureRecognizer?; let wasEnabled: Bool }
    private struct ScrollEntry { weak var view: UIScrollView?; let y: CGFloat }
    private var ancestors: [PanEntry] = []
    private var scrollStarts: [ScrollEntry] = []
    private var startY: CGFloat = 0
    private var evidence = EffortGestureEvidence()
    private(set) var isTrackingScore = false
    private var touchStart: CGPoint?
    private var hasPanned = false
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handleEffortPan(_:)))
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isAccessibilityElement = false
        pan.delegate = self; pan.cancelsTouchesInView = false; pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil { cancelInteraction() }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelInteraction() }
    }
    @objc private func interrupted() { cancelInteraction() }
    func beginInteraction() {
        guard acceptsTouches, !isTrackingScore else { return }
        isTrackingScore = true; hasPanned = false; evidence = .init()
        var ancestor = superview
        var seen = Set<ObjectIdentifier>()
        while let view = ancestor, !(view is UIWindow) {
            for recognizer in view.gestureRecognizers ?? [] {
                guard let candidate = recognizer as? UIPanGestureRecognizer,
                      candidate !== pan, seen.insert(ObjectIdentifier(candidate)).inserted else { continue }
                ancestors.append(.init(pan: candidate, wasEnabled: candidate.isEnabled))
            }
            if onEvidence != nil, let scroll = view as? UIScrollView { scrollStarts.append(.init(view: scroll, y: scroll.contentOffset.y)) }
            ancestor = view.superview
        }
        if onEvidence != nil { startY = convert(bounds, to: window).minY }
        onPress(true)
    }
    func beginScorePan() {
        beginInteraction()
        guard isTrackingScore, evidence.ancestorPans == 0 else { return }
        evidence.ancestorPans = ancestors.filter(\.wasEnabled).count
        // Dynamic failure priority holds ancestors while direction is undecided;
        // this lease then excludes them even if another delegate allows simultaneity.
        for entry in ancestors where entry.wasEnabled { entry.pan?.isEnabled = false }
    }
    private func sampleMovement() {
        guard onEvidence != nil else { return }
        evidence.maxVerticalShift = max(evidence.maxVerticalShift, abs(convert(bounds, to: window).minY - startY))
        for entry in scrollStarts {
            if let scroll = entry.view { evidence.maxScrollShift = max(evidence.maxScrollShift, abs(scroll.contentOffset.y - entry.y)) }
        }
    }
    private func finishInteraction(cancelled: Bool) {
        guard isTrackingScore else { return }
        sampleMovement(); isTrackingScore = false; evidence.cancelled = cancelled
        onDrag(false); onPress(false); onEnd()
        for entry in ancestors where entry.wasEnabled {
            if let recognizer = entry.pan { recognizer.isEnabled = true; evidence.restoredPans += 1 }
        }
        ancestors.removeAll(); scrollStarts.removeAll(); touchStart = nil
        onEvidence?(evidence)
    }
    func cancelInteraction() {
        finishInteraction(cancelled: true)
        if pan.state == .began || pan.state == .changed { pan.isEnabled = false; pan.isEnabled = acceptsTouches }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard acceptsTouches else { return false }
        beginInteraction(); return true
    }
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === pan else { return true }
        let velocity = pan.velocity(in: self)
        let horizontal = abs(velocity.x) > abs(velocity.y)
        if horizontal { beginScorePan() } else { cancelInteraction() }
        return horizontal
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, otherGestureRecognizer is UIPanGestureRecognizer,
              let ancestor = otherGestureRecognizer.view, ancestor !== self else { return false }
        return isDescendant(of: ancestor)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        beginInteraction(); touchStart = touches.first?.location(in: self)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if isTrackingScore, !hasPanned, let start = touchStart, let end = touches.first?.location(in: self),
           hypot(end.x - start.x, end.y - start.y) < 8 { onMove(end.x) }
        finishInteraction(cancelled: false)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event); cancelInteraction()
    }
    @objc private func handleEffortPan(_ recognizer: UIPanGestureRecognizer) {
        guard isTrackingScore else { return }
        switch recognizer.state {
        case .began, .changed:
            hasPanned = true; evidence.didDrag = true; onDrag(true); onPress(true)
            onMove(recognizer.location(in: self).x); sampleMovement()
        case .ended:
            onMove(recognizer.location(in: self).x); finishInteraction(cancelled: false)
        case .cancelled, .failed: finishInteraction(cancelled: true)
        default: break
        }
    }
}
