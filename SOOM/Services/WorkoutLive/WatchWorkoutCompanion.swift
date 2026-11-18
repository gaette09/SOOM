import Combine
import HealthKit
import SwiftUI
import WatchConnectivity

@MainActor
final class WatchWorkoutCompanion: NSObject, ObservableObject {
    static let shared = WatchWorkoutCompanion()
    @Published private(set) var workout: WorkoutLiveState?
    @Published private(set) var connectionMessage: String?
    @Published var shouldOpenWorkout = false
    private let healthStore = HKHealthStore()
    private var mirror: HKWorkoutSession?
    private var inbox = WorkoutLiveInbox()
    private var scope: String?
    private var pending: WorkoutLiveState?
    private var phoneRecording = false

    override private init() {
        super.init()
        scope = UserDefaults.standard.string(forKey: "SOOM.watch.liveScope")
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                guard let self, !ReviewDemoMode.isActive else { return }
                self.mirror = session
                session.delegate = self
                self.requestSnapshot()
            }
        }
    }
    func bind(scope: String) {
        guard self.scope != scope else { return }
        self.scope = scope
        UserDefaults.standard.set(scope, forKey: "SOOM.watch.liveScope")
        inbox.reset(); workout = nil
        WorkoutLiveActivityController.shared.clear()
        publishContext()
        if let pending { self.pending = nil; receive(pending) }
        requestSnapshot()
    }
    func setPhoneRecording(_ active: Bool) {
        guard phoneRecording != active else { return }
        phoneRecording = active; publishContext()
    }
    private func publishContext() {
        guard let scope, WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(["soomScope": scope, "phoneRecording": phoneRecording])
    }
    private func receive(_ state: WorkoutLiveState) {
        guard !ReviewDemoMode.isActive else { return }
        guard let scope else { pending = state; return }
        guard inbox.receive(state, scope: scope) else { return }
        workout = state.isTerminal ? nil : state
        connectionMessage = nil
        // Watch owns HealthKit persistence. Phone imports the same UUID through existing HealthKit observers.
        if !phoneRecording { WorkoutLiveActivityController.shared.submit(state, force: state.phase != .running) }
    }
    func command(_ action: WorkoutRemoteCommand.Action) {
        guard let scope, let state = workout else { return }
        send(WorkoutRemoteCommand(workoutID: state.id, scope: scope, action: action))
    }
    private func requestSnapshot() {
        guard let scope else { return }
        send(WorkoutRemoteCommand(workoutID: nil, scope: scope, action: .snapshot))
    }
    private func send(_ command: WorkoutRemoteCommand) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        if let mirror {
            mirror.sendToRemoteWorkoutSession(data: data) { [weak self] success, _ in
                if !success { Task { @MainActor in self?.connectionMessage = "워치 연결을 확인해 주세요. 운동은 워치에서 계속 기록돼요." } }
            }
        } else if WCSession.default.isReachable {
            WCSession.default.sendMessageData(data, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.connectionMessage = "워치에서 운동을 제어해 주세요." }
            }
        } else if command.action != .snapshot { connectionMessage = "워치와 연결되지 않았어요. 워치에서 운동을 제어해 주세요." }
        // Never queue controls: a delayed stop/pause must not affect a later workout.
    }
    private func decode(_ data: Data) {
        guard let state = try? JSONDecoder().decode(WorkoutLiveState.self, from: data) else { return }
        receive(state)
    }
}

extension WatchWorkoutCompanion: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publishContext(); self.requestSnapshot() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.decode(messageData) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo["soomWorkout"] as? Data else { return }
        Task { @MainActor in self.decode(data) }
    }
}
extension WatchWorkoutCompanion: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            if toState == .ended {
                self.mirror = nil
                if var state = self.workout {
                    state.elapsed = state.elapsed(at: date); state.updatedAt = date
                    state.phase = .finished; state.sequence += 1
                    self.receive(state)
                }
            } else { self.requestSnapshot() }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.connectionMessage = "워치 연결이 끊겼어요. 워치에서 기록 상태를 확인해 주세요." }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in data.forEach { self.decode($0) } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.mirror = nil; self.connectionMessage = "워치에서 기록 중 · 연결 확인 필요" }
    }
}

struct WatchWorkoutCompanionView: View {
    @ObservedObject var companion = WatchWorkoutCompanion.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmFinish = false
    var body: some View {
        NavigationStack {
            if let state = companion.workout {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 24) {
                        Label("Apple Watch에서 \(state.sport.title)", systemImage: state.sport.symbol)
                            .font(.title2.bold())
                        Text(WorkoutLiveState.time(state.elapsed(at: context.date)))
                            .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                        HStack(spacing: 28) {
                            watchMetric(state.displayDistance, label: state.distanceUnit)
                            watchMetric(state.effortText(at: context.date), label: state.effortUnit)
                            watchMetric(state.heartRate.map { String(Int($0)) } ?? "–", label: "bpm")
                        }
                        if let message = companion.connectionMessage { Text(message).font(.callout).foregroundStyle(.secondary) }
                        if let message = WorkoutLiveActivityController.shared.unavailableReason { Text(message).font(.caption).foregroundStyle(.secondary) }
                        Text(state.phase == .paused ? "일시정지" : state.phase == .saving ? "워치에 저장 중" : "워치가 운동을 기록하고 있어요")
                            .foregroundStyle(.secondary)
                        if state.phase == .running || state.phase == .paused {
                            Button(state.phase == .paused ? "계속하기" : "일시정지", systemImage: state.phase == .paused ? "play.fill" : "pause.fill") {
                                companion.command(state.phase == .paused ? .resume : .pause)
                            }.buttonStyle(.borderedProminent).tint(.purple).controlSize(.large)
                            Button("운동 종료", role: .destructive) { confirmFinish = true }.buttonStyle(.bordered).controlSize(.large)
                        }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationTitle("운동 중").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
            } else {
                ContentUnavailableView("워치 운동을 종료했어요", systemImage: "checkmark.circle", description: Text("Apple 건강 동기화가 완료되면 기존 연동 설정에 따라 운동 기록을 가져와요."))
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
            }
        }
        .confirmationDialog("운동을 종료하고 저장할까요?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("종료하고 저장", role: .destructive) { companion.command(.finish) }
        }
        .onAppear { WorkoutLiveActivityController.shared.reconcile() }
    }
    private func watchMetric(_ value: String, label: String) -> some View {
        VStack { Text(value).font(.title.bold()).monospacedDigit(); Text(label).foregroundStyle(.secondary) }
    }
}
