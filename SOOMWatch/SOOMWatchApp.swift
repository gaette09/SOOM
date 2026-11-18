import SwiftUI
import WatchKit
import HealthKit

@main
struct SOOMWatchApp: App {
    @WKApplicationDelegateAdaptor(SOOMWatchDelegate.self) private var delegate
    @StateObject private var recorder = WatchWorkoutRecorder.shared
    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if let sport = WatchScreenshotPreview.sport {
                WatchScreenshotPreview(selectedSport: sport)
            } else { WatchWorkoutView().environmentObject(recorder) }
            #else
            WatchWorkoutView().environmentObject(recorder)
            #endif
        }
    }
}

final class SOOMWatchDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() { Task { @MainActor in await WatchWorkoutRecorder.shared.recover(force: true) } }
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchWorkoutRecorder.shared.start(configuration: workoutConfiguration)
        }
    }
}

struct WatchWorkoutView: View {
    @EnvironmentObject private var recorder: WatchWorkoutRecorder
    @State private var page = 1
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var confirmClearRecovery = false
    @State private var confirmWithoutRoute = false

    var body: some View {
        Group {
            if let state = recorder.snapshot {
                if state.phase == .finished || state.phase == .saving {
                    NavigationStack { summary(state) }
                } else {
                    TabView(selection: $page) {
                        controls(state).tag(0)
                        WatchWorkoutMetricsView(state: state).tag(1)
                        details(state).tag(2)
                    }.tabViewStyle(.page)
                }
            } else if recorder.isRecovering {
                ProgressView("기록 확인 중")
            } else { startList }
        }
        .tint(recorder.snapshot?.sport.watchColor ?? .purple)
        .overlay { if recorder.isStarting { ProgressView("운동 준비 중").frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.9)) } }
        .task { await recorder.recover() }
        .onChange(of: recorder.snapshot?.id) { _, _ in page = 1 }
        .alert("운동을 종료할까요?", isPresented: $confirmFinish) {
            Button("저장하고 종료") { recorder.finish() }
            Button("계속 기록", role: .cancel) {}
        } message: { Text("운동 기록을 Apple 건강에 저장해요.") }
        .alert("이 운동을 버릴까요?", isPresented: $confirmDiscard) {
            Button("운동 버리기", role: .destructive) { recorder.discard() }
            Button("계속 기록", role: .cancel) {}
        } message: { Text("이 운동은 SOOM 기록에 저장되지 않아요.") }
        .alert("복구 정보를 지울까요?", isPresented: $confirmClearRecovery) {
            Button("복구 정보 지우기", role: .destructive) { recorder.clearUnrecoverableCheckpoint() }
            Button("취소", role: .cancel) {}
        } message: { Text("먼저 건강 앱에서 운동 저장 상태를 확인해 주세요. 이 워치의 복구 정보만 지우며 이미 저장된 건강 기록은 삭제하지 않아요.") }
        .alert("경로 없이 완료할까요?", isPresented: $confirmWithoutRoute) {
            Button("완료") { recorder.finishWithoutRoute() }
            Button("취소", role: .cancel) {}
        } message: { Text("저장된 운동은 유지하지만 아직 저장하지 못한 경로는 다시 시도할 수 없어요.") }
    }

    private var startList: some View {
        NavigationStack {
            List {
                if let message = recorder.message { Text(message).font(.caption).foregroundStyle(.orange) }
                ForEach([WorkoutLiveState.Sport.swimming, .cycling, .running, .walking], id: \.self) { sport in
                    NavigationLink { WatchWorkoutSetupView(sport: sport) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: sport.symbol).font(.title2).foregroundStyle(sport.watchColor).frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sport.title).font(.headline)
                                Text(sport == .swimming ? "수영장 · 오픈워터" : "실외 · 실내").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                    .listRowBackground(Color.white.opacity(0.10))
                    .disabled(recorder.isStarting || recorder.isRecovering || recorder.phoneRecording)
                    .accessibilityIdentifier("watch.start.\(sport.rawValue)")
                }
                if recorder.phoneRecording { Text("iPhone에서 기록 중이에요. 먼저 종료해 주세요.").font(.caption).foregroundStyle(.orange) }
                NavigationLink { WatchWorkoutHistoryView() } label: {
                    Label("최근 운동", systemImage: "clock.arrow.circlepath")
                }.accessibilityIdentifier("watch.history")
                Text("iPhone 없이도 기록해요. 운동은 Apple 건강에 저장돼요.").font(.caption2).foregroundStyle(.secondary).listRowBackground(Color.clear)
            }.navigationTitle("SOOM")
        }
    }

    private func controls(_ state: WorkoutLiveState) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(state.phase == .paused ? "일시정지" : "운동 제어").font(.headline)
                Button {
                    recorder.togglePause()
                } label: {
                    Label(state.phase == .paused ? "재개" : "일시정지", systemImage: state.phase == .paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent).tint(state.sport.watchColor).foregroundStyle(.black)
                .disabled(recorder.isChangingState).accessibilityIdentifier("watch.pauseResume")
                Button { confirmFinish = true } label: {
                    Label("종료", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 40)
                }.buttonStyle(.bordered).tint(.red).accessibilityIdentifier("watch.finish")
                if state.sport == .swimming {
                    Button("물 잠금", systemImage: "drop.fill") { recorder.enableWaterLock() }
                        .accessibilityHint("터치가 잠겨요. Digital Crown을 길게 눌러 해제할 수 있어요.")
                    Text("물 잠금 해제는 Digital Crown을 길게 눌러 주세요.").font(.caption2).foregroundStyle(.secondary)
                }
                Button("운동 버리기", role: .destructive) { confirmDiscard = true }.font(.caption)
            }.padding(.horizontal, 8).padding(.bottom, 20)
        }
    }

    private func details(_ state: WorkoutLiveState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("운동 지표").font(.headline)
                WatchMetricRow(title: "활동 에너지", value: state.energy, unit: "kcal", color: .orange)
                if state.sport == .swimming {
                    WatchMetricRow(title: "총 스트로크", value: state.swimmingStrokeCount, unit: "회", color: state.sport.watchColor)
                    if let length = state.poolLengthMeters { WatchMetricRow(title: "수영장 길이", value: length, unit: "m", color: .white) }
                } else {
                    if state.sport != .walking { WatchMetricRow(title: "파워", value: state.power, unit: "W", color: .white) }
                    WatchMetricRow(title: "케이던스", value: state.cadence, unit: state.sport == .cycling ? "rpm" : "spm", color: .white)
                    WatchMetricRow(title: "획득 고도", value: state.elevationGain, unit: "m", color: .white)
                }
                if let message = recorder.message { Text(message).font(.caption2).foregroundStyle(.orange) }
                Text("측정되지 않은 값은 –로 표시해요.").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 8).padding(.bottom, 20)
        }
    }

    private func summary(_ state: WorkoutLiveState) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if state.phase == .saving && !recorder.canRetrySave { ProgressView() }
                else { Image(systemName: state.phase == .finished ? "checkmark.circle.fill" : "exclamationmark.circle").font(.largeTitle).foregroundStyle(state.phase == .finished ? .green : .orange) }
                Text(state.phase == .finished ? "운동 완료" : recorder.canRetrySave ? "저장 확인 필요" : "운동 저장 중").font(.headline)
                WatchMetricTile(title: "운동 시간", value: WorkoutLiveState.time(state.elapsed), unit: "", color: .white)
                HStack(spacing: 8) {
                    WatchMetricTile(title: "거리", value: state.displayDistance, unit: state.distanceUnit, color: state.sport.watchColor)
                    WatchMetricTile(title: "평균 " + (state.sport == .cycling ? "속도" : "페이스"), value: state.effortText(at: state.updatedAt), unit: state.effortUnit, color: .white)
                }
                if let message = recorder.message { Text(message).font(.caption2).foregroundStyle(.orange) }
                if state.phase == .finished {
                    Text("Apple 건강에 저장했어요. iPhone과 건강 동기화 후 SOOM의 연동 설정에 따라 가져와요.").font(.caption2).foregroundStyle(.secondary)
                    Button("완료") { recorder.reset() }.buttonStyle(.borderedProminent).accessibilityIdentifier("watch.done")
                } else if recorder.canRetrySave {
                    Button(recorder.needsRecoveryLookup ? "저장 상태 다시 확인" : "저장 다시 시도") { recorder.retrySave() }
                    if recorder.canFinishWithoutRoute { Button("경로 없이 완료") { confirmWithoutRoute = true } }
                    if recorder.needsRecoveryLookup { Button("복구 정보 지우기", role: .destructive) { confirmClearRecovery = true } }
                }
            }.padding(.horizontal, 8)
        }.navigationTitle(state.sport.title)
    }
}

private struct WatchWorkoutSetupView: View {
    let sport: WorkoutLiveState.Sport
    @EnvironmentObject private var recorder: WatchWorkoutRecorder
    @State private var indoor = false
    @State private var poolLength = 25.0
    init(sport: WorkoutLiveState.Sport) {
        self.sport = sport
        _indoor = State(initialValue: sport == .swimming)
    }
    var body: some View {
        List {
            Picker(sport == .swimming ? "수영 장소" : "운동 장소", selection: $indoor) {
                Text(sport == .swimming ? "오픈워터" : "실외").tag(false)
                Text(sport == .swimming ? "수영장" : "실내").tag(true)
            }.accessibilityIdentifier("watch.location")
            if sport == .swimming && indoor {
                Picker("수영장 길이", selection: $poolLength) {
                    Text("25m").tag(25.0)
                    Text("50m").tag(50.0)
                    Text("20m").tag(20.0)
                    Text("33⅓m").tag(100.0 / 3)
                }.accessibilityIdentifier("watch.poolLength")
                Text("한쪽 끝에서 반대편 끝까지의 길이예요.").font(.caption2).foregroundStyle(.secondary)
            }
            if let message = recorder.message { Text(message).font(.caption).foregroundStyle(.orange) }
            Button {
                Task { await recorder.start(WatchWorkoutPlan(sport: sport, indoor: indoor, poolLengthMeters: sport == .swimming && indoor ? poolLength : nil)) }
            } label: {
                Label("운동 시작", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .listRowBackground(sport.watchColor).foregroundStyle(.black)
            .disabled(recorder.isStarting || recorder.isRecovering || recorder.phoneRecording)
            .accessibilityIdentifier("watch.confirmStart")
            Text(indoor ? "GPS 경로 없이 기록해요." : "위치 권한을 허용하면 야외 경로를 함께 기록해요.").font(.caption2).foregroundStyle(.secondary)
            if sport == .swimming { Text("시작 후 제어 화면에서 물 잠금을 켤 수 있어요.").font(.caption2).foregroundStyle(.secondary) }
        }
        .navigationTitle(sport.title).tint(sport.watchColor)
    }
}

struct WatchWorkoutMetricsView: View {
    let state: WorkoutLiveState
    /// Only screenshot fixtures supply a fixed clock; live recording uses TimelineView.
    var referenceDate: Date? = nil
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 190
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let date = referenceDate ?? context.date
                ScrollView {
                    if state.sport == .running || state.sport == .swimming {
                        orderedMetrics(at: date, compact: compact)
                    } else {
                        existingMetrics(at: date, compact: compact)
                    }
                }
                .contentMargins(.vertical, 0, for: .scrollContent)
                .accessibilityHint("왼쪽 페이지 운동 제어, 오른쪽 페이지 추가 지표")
            }
        }
    }

    private func orderedMetrics(at date: Date, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: (compact ? 4 : state.sport == .swimming ? 5 : 6) * textScale) {
            if state.sport == .swimming { swimmingHeader(at: date, compact: compact) }
            metricLine(value: state.sport == .swimming ? state.distance.formatted(.number.precision(.fractionLength(0))) : state.displayDistance,
                       unit: state.distanceUnit, size: compact ? 43 : 50,
                       unitSize: state.sport == .swimming ? (compact ? 23 : 27) : (compact ? 12 : 13),
                       color: state.sport == .running ? WatchR05Style.run : .primary,
                       unitColor: state.sport == .swimming ? WatchR05Style.swim : WatchR05Style.secondary,
                       label: "전체 거리 \(state.displayDistance) \(state.distanceUnit)")
                .accessibilityIdentifier("watch.distance")
            if state.sport == .running {
                Text(WorkoutLiveState.clockTime(state.elapsed(at: date)))
                    .font(.system(size: (compact ? 29 : 35) * textScale)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityLabel("전체 시간 \(WorkoutLiveState.time(state.elapsed(at: date)))")
                    .accessibilityIdentifier("watch.elapsed")
            }
            metricLine(value: paddedPace(at: date), unit: "평균 \(state.effortUnit)",
                       size: compact ? 27 : 32, unitSize: compact ? 10 : 11,
                       color: state.sport == .running ? WatchR05Style.run : .primary,
                       unitColor: WatchR05Style.secondary,
                       label: "평균 페이스 \(state.effortText(at: date)) \(state.effortUnit)")
                .accessibilityIdentifier("watch.averagePace")
            heartRateAndZones(at: date, compact: compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.bottom, 8)
        .overlay(alignment: .topLeading) {
            if state.sport == .running && state.phase == .paused {
                Text("일시정지").font(.caption2).foregroundStyle(.orange)
                    .offset(x: 12, y: -19).accessibilityIdentifier("watch.paused")
            }
        }
    }

    private func swimmingHeader(at date: Date, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Label(state.phase == .paused ? "일시정지" : state.poolLengthMeters == nil ? "오픈워터" : "수영 중",
                      systemImage: state.phase == .paused ? "pause.fill" : "figure.pool.swim")
                    .font(.system(size: (compact ? 11 : 12) * textScale, weight: .semibold))
                    .foregroundStyle(state.phase == .paused ? .orange : WatchR05Style.swim)
                    .accessibilityIdentifier("watch.swimStatus")
                Text(WorkoutLiveState.clockTime(state.elapsed(at: date)))
                    .font(.system(size: (compact ? 20 : 23) * textScale)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityLabel("전체 시간 \(WorkoutLiveState.time(state.elapsed(at: date)))")
                    .accessibilityIdentifier("watch.elapsed")
            }
            Spacer(minLength: 0)
            if state.poolLengthMeters != nil {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Laps").font(.system(size: (compact ? 11 : 12) * textScale, weight: .semibold))
                        .foregroundStyle(WatchR05Style.swim)
                    // No verified pool-length counter exists. Never infer laps from distance or strokes.
                    Text("—").font(.system(size: (compact ? 20 : 23) * textScale))
                }
                .accessibilityElement(children: .ignore).accessibilityLabel("수영 랩 수, 정보 없음")
                .accessibilityIdentifier("watch.lapsUnavailable")
            }
        }
    }

    private func metricLine(value: String, unit: String, size: Double, unitSize: Double,
                            color: Color, unitColor: Color, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: size * textScale, weight: .bold)).monospacedDigit()
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
            Text(unit).font(.system(size: unitSize * textScale)).foregroundStyle(unitColor)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(label)
    }

    private func heartRateAndZones(at date: Date, compact: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: compact ? 4 : 6) {
                heartRate(at: date, compact: compact).fixedSize()
                unconfiguredZones.frame(minWidth: 48)
            }
            VStack(alignment: .leading, spacing: 4) {
                heartRate(at: date, compact: compact)
                unconfiguredZones
            }
        }
    }

    private func heartRate(at date: Date, compact: Bool) -> some View {
        let value = state.currentHeartRate(at: date).map { String(Int($0)) } ?? "—"
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemName: "heart.fill").font(.system(size: (compact ? 12 : 13) * textScale))
                .foregroundStyle(WatchR05Style.heart).accessibilityHidden(true)
            Text(value).font(.system(size: (compact ? 22 : 25) * textScale, weight: .semibold))
                .monospacedDigit().foregroundStyle(.primary)
            Text("bpm").font(.system(size: 10 * textScale)).foregroundStyle(WatchR05Style.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value == "—" ? "심박, 현재 측정값 없음" : "심박, 분당 \(value)회")
        .accessibilityIdentifier("watch.heartRate")
    }

    private var unconfiguredZones: some View {
        // Equal-width colour regions are a legend, never a physiological estimate.
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(WatchR05Style.zoneColors[index]).frame(maxWidth: .infinity)
            }
        }
        .frame(height: 22).padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("심박존 색상 범례, 개인 존 정보 없음")
        .accessibilityIdentifier("watch.zoneLegend")
    }

    private func paddedPace(at date: Date) -> String {
        let value = state.effortText(at: date)
        return value.first?.isNumber == true && value.firstIndex(of: ":") == value.index(after: value.startIndex) ? "0" + value : value
    }

    private func existingMetrics(at date: Date, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack {
                Label(state.sport.title, systemImage: state.sport.symbol).foregroundStyle(state.sport.watchColor)
                Spacer(minLength: 2)
                Text(state.phase == .paused ? "일시정지" : "기록 중").foregroundStyle(state.phase == .paused ? .orange : .secondary)
            }.font(.system(size: compact ? 12 : 14, weight: .semibold))
            Text(WorkoutLiveState.time(state.elapsed(at: date)))
                .font(.system(size: compact ? 30 : 38, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityLabel("운동 시간 \(WorkoutLiveState.time(state.elapsed(at: date)))")
                .accessibilityIdentifier("watch.elapsed")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(state.displayDistance).font(.system(size: compact ? 26 : 34, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(state.distanceUnit).font(.caption).foregroundStyle(.secondary)
            }.foregroundStyle(state.sport.watchColor).accessibilityElement(children: .ignore)
                .accessibilityLabel("거리 \(state.displayDistance) \(state.distanceUnit)")
            HStack(spacing: 7) {
                WatchMetricTile(title: state.sport == .cycling ? "평균 속도" : "평균 페이스", value: state.effortText(at: date), unit: state.effortUnit, color: .white, compact: compact)
                WatchMetricTile(title: "심박", value: state.heartRate.map { String(Int($0)) } ?? "–", unit: "bpm", color: .red, compact: compact)
            }
        }.padding(.horizontal, 8).padding(.bottom, compact ? 6 : 14)
    }
}

private enum WatchR05Style {
    static let run = Color("WatchRun")
    static let swim = Color("WatchSwim")
    static let heart = Color("WatchZone5")
    static let secondary = Color("WatchSecondary")
    static let zoneColors = (1...5).map { Color("WatchZone\($0)") }
}


private struct WatchWorkoutHistoryView: View {
    @StateObject private var history = WatchWorkoutHistoryStore()
    var body: some View {
        List {
            if history.isLoading { ProgressView("기록 불러오는 중") }
            if let message = history.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            ForEach(history.workouts) { workout in
                NavigationLink { WatchWorkoutHistoryDetail(workout: workout) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(workout.sport.title, systemImage: workout.sport.symbol).foregroundStyle(workout.sport.watchColor)
                        Text(workout.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                        Text(workout.distanceText + (workout.sport == .swimming ? " m" : " km") + " · " + WorkoutLiveState.time(workout.duration)).font(.headline).monospacedDigit()
                    }.padding(.vertical, 3)
                }
            }
            Button("새로고침", systemImage: "arrow.clockwise") { Task { await history.load() } }.disabled(history.isLoading)
            Text("Apple 건강에서 최근 SOOM 운동 30개를 가져와요.").font(.caption2).foregroundStyle(.secondary)
        }.navigationTitle("최근 운동").task { await history.load() }
    }
}

private struct WatchWorkoutHistoryDetail: View {
    let workout: WatchWorkoutHistoryItem
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                Text(workout.startedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                Text(workout.indoor ? "실내 운동" : "실외 운동").font(.caption2).foregroundStyle(workout.sport.watchColor)
                WatchMetricTile(title: "운동 시간", value: WorkoutLiveState.time(workout.duration), unit: "", color: .white)
                HStack(spacing: 7) {
                    WatchMetricTile(title: "거리", value: workout.distanceText, unit: workout.sport == .swimming ? "m" : "km", color: workout.sport.watchColor)
                    WatchMetricTile(title: workout.sport == .cycling ? "평균 속도" : "평균 페이스", value: workout.effortText, unit: workout.sport == .cycling ? "km/h" : workout.sport == .swimming ? "/100m" : "/km", color: .white)
                }
                WatchMetricRow(title: "평균 심박", value: workout.averageHeartRate, unit: "bpm", color: .red)
                WatchMetricRow(title: "활동 에너지", value: workout.energy, unit: "kcal", color: .orange)
                if workout.sport == .swimming {
                    WatchMetricRow(title: "총 스트로크", value: workout.strokes, unit: "회", color: .cyan)
                    if let length = workout.poolLengthMeters { WatchMetricRow(title: "수영장 길이", value: length, unit: "m", color: .white) }
                }
                Text("측정되지 않았거나 읽기가 허용되지 않은 값은 –로 표시해요.").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 8)
        }.navigationTitle(workout.sport.title)
    }
}

private struct WatchMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 3) {
            Text(title).font(.system(size: compact ? 9 : 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: compact ? 20 : 24, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.55)
            if !unit.isEmpty { Text(unit).font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(compact ? 5 : 8)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(title), \(value) \(unit)")
    }
}

private struct WatchMetricRow: View {
    let title: String
    let value: Double?
    let unit: String
    let color: Color
    var body: some View {
        HStack {
            Text(title).font(.caption2)
            Spacer(minLength: 4)
            Text(value.map { String(format: "%.0f", $0) } ?? "–").font(.title3.bold()).monospacedDigit().foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }.padding(9).background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
    }
}

private extension WorkoutLiveState.Sport {
    var watchColor: Color {
        switch self { case .swimming: WatchR05Style.swim; case .cycling: .orange; case .running: WatchR05Style.run; case .walking: .mint }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Explicit, labelled screenshot fixtures. Never compiled into a device or Release build; never saved to HealthKit.
private struct WatchScreenshotPreview: View {
    let selectedSport: WorkoutLiveState.Sport
    static var sport: WorkoutLiveState.Sport? {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--watch-ui-preview=") }) else { return nil }
        return WorkoutLiveState.Sport(rawValue: String(argument.dropFirst("--watch-ui-preview=".count)))
    }
    @State private var sampleDate = Date()
    private var variant: String {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--watch-ui-state=") }?.components(separatedBy: "=").last ?? "live"
    }
    private var state: WorkoutLiveState {
        var value = WorkoutLiveState(id: UUID(), scope: "ui-preview-only", sport: selectedSport,
            phase: variant == "paused" ? .paused : .running,
            startedAt: sampleDate.addingTimeInterval(-1234), updatedAt: sampleDate,
            elapsed: selectedSport == .swimming ? 1200 : 1234,
            distance: selectedSport == .swimming ? 1000 : 4200,
            heartRate: variant == "missing" ? nil : selectedSport == .swimming ? 138 : 142, isWatch: true)
        value.poolLengthMeters = selectedSport == .swimming && variant != "openwater" ? 25 : nil
        value.heartRateMeasuredAt = sampleDate.addingTimeInterval(variant == "stale" ? -60 : 0)
        return value
    }
    var body: some View {
        TabView(selection: .constant(1)) {
            Color.clear.tag(0)
            WatchWorkoutMetricsView(state: state, referenceDate: sampleDate).tag(1)
            Color.clear.tag(2)
        }.tabViewStyle(.page)
            .environment(\.dynamicTypeSize, variant == "large" ? .accessibility3 : .large)
            .overlay(alignment: .topLeading) { Text("샘플").font(.system(size: 8)).foregroundStyle(.yellow).padding(.leading, 74).offset(y: -20) }
    }
}
#endif
