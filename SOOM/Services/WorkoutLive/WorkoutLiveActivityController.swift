import ActivityKit
import Foundation

/// Serializes ActivityKit mutations so an older end/update cannot erase a new workout.
@MainActor
final class WorkoutLiveActivityController {
    static let shared = WorkoutLiveActivityController()
    private var activity: Activity<SOOMWorkoutAttributes>?
    private var desired: WorkoutLiveState?
    private var worker: Task<Void, Never>?
    private var lastUpdate: Date = .distantPast
    private var lastSubmitted: WorkoutLiveState?
    private(set) var unavailableReason: String?

    func submit(_ state: WorkoutLiveState, force: Bool = false) {
        guard state.isValid else { return }
        let significant = lastSubmitted?.id != state.id || lastSubmitted?.phase != state.phase
        guard force || significant || state.updatedAt.timeIntervalSince(lastUpdate) >= 5 else { return }
        lastUpdate = state.updatedAt
        lastSubmitted = state
        desired = state.isTerminal ? nil : state
        drain()
    }
    func clear() { desired = nil; lastSubmitted = nil; lastUpdate = .distantPast; drain() }
    func reconcile() { lastUpdate = .distantPast; drain() }

    private func drain() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while true {
                let target = self.desired
                // Also reconcile after app restart; never leave another account's activity visible.
                for old in Activity<SOOMWorkoutAttributes>.activities where old.id != self.activity?.id {
                    if old.attributes.workoutID == target?.id { self.activity = old }
                    else { await old.end(nil, dismissalPolicy: .immediate) }
                }
                if let old = self.activity, old.attributes.workoutID != target?.id {
                    await old.end(nil, dismissalPolicy: .immediate)
                    self.activity = nil
                }
                if let target, !target.isTerminal {
                    let content = ActivityContent(state: target, staleDate: target.phase == .running ? Date().addingTimeInterval(45) : nil)
                    if let activity = self.activity { await activity.update(content) }
                    else if ActivityAuthorizationInfo().areActivitiesEnabled {
                        do {
                            self.activity = try Activity.request(attributes: SOOMWorkoutAttributes(workoutID: target.id, sport: target.sport, isWatch: target.isWatch), content: content, pushType: nil)
                            self.unavailableReason = nil
                        } catch { self.unavailableReason = "라이브 액티비티를 시작하지 못했어요. 운동 화면을 다시 열어 주세요." }
                    } else { self.unavailableReason = "설정에서 SOOM 라이브 액티비티를 허용해 주세요." }
                }
                if self.desired == target { break }
            }
            self.worker = nil
        }
    }
}

extension RecordWorkoutSession {
    func liveState(scope: String, at date: Date) -> WorkoutLiveState {
        let phase: WorkoutLiveState.Phase = switch state {
        case .active: .running
        case .paused: .paused
        case .finished: .finished
        case .cancelled: .discarded
        }
        return WorkoutLiveState(id: id, scope: scope, sport: .init(rawValue: sport.rawValue) ?? .running,
            phase: phase, startedAt: startedAt, updatedAt: date, elapsed: elapsedTime(referenceDate: date),
            distance: accumulatedDistanceMeters, isWatch: false)
    }
}
