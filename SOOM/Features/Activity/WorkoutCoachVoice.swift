import AVFoundation
import Combine
import UIKit

@MainActor
protocol CoachSpeechOutput: AnyObject {
    var status: String { get }
    func speak(_ event: CoachEvent)
    func stop()
    func confirmOutput()
}

@MainActor
final class DeviceCoachSpeech: NSObject, CoachSpeechOutput, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let audio = AVAudioSession.sharedInstance()
    private var current: AVSpeechUtterance?
    private var observers: [NSObjectProtocol] = []
    private var watchdog: Task<Void, Never>?
    private var outputBlocked = false
    private(set) var status = "기기 음성 · 오프라인 사용 가능"

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, UIAccessibility.voiceOverStatusDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let name = notification.name
                let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if name == AVAudioSession.interruptionNotification {
                        if type == AVAudioSession.InterruptionType.began.rawValue { self.block("오디오 중단 · 음성을 껐다 켜서 출력 확인") }
                    } else if name == AVAudioSession.routeChangeNotification {
                        if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                            || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue {
                            self.block("출력이 바뀌었어요 · 음성을 껐다 켜서 확인")
                        }
                    } else if name == UIAccessibility.voiceOverStatusDidChangeNotification {
                        if UIAccessibility.isVoiceOverRunning { self.stop() }
                    } else { self.block("음성 출력을 다시 확인해 주세요") }
                }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver); watchdog?.cancel() }

    func confirmOutput() { outputBlocked = false; status = "기기 음성 · 오프라인 사용 가능" }
    func speak(_ event: CoachEvent) {
        guard event.expiresAt >= Date(), !outputBlocked, !UIAccessibility.isVoiceOverRunning else { return }
        guard !synthesizer.isSpeaking || event.replacesSpeech else { return } // No historical queue.
        stop()
        guard let voice = AVSpeechSynthesisVoice(language: "ko-KR") else {
            status = "한국어 기기 음성 없음 · 텍스트 안내 유지"; return
        }
        do {
            try audio.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try audio.setActive(true)
            let utterance = AVSpeechUtterance(string: event.text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            current = utterance
            status = "기기 음성 안내 중"
            synthesizer.speak(utterance)
            watchdog = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                self?.block("음성 응답 없음 · 텍스트 안내 유지")
            }
        } catch { stop(); status = "기기 음성 사용 불가 · 텍스트 안내 유지" }
    }
    func stop() {
        watchdog?.cancel(); watchdog = nil; current = nil
        synthesizer.stopSpeaking(at: .immediate)
        try? audio.setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func block(_ reason: String) { stop(); outputBlocked = true; status = reason }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.current === utterance else { return }
            self.stop(); self.status = "기기 음성 · 오프라인 사용 가능"
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.current === utterance else { return }
            self.stop()
        }
    }
}

@MainActor
final class WorkoutCoachCoordinator: ObservableObject {
    @Published private(set) var preferences = CoachPreferences()
    @Published private(set) var caption = "기본 안내는 기기에서 말해요. 음성은 기본 꺼짐이에요."
    @Published private(set) var voiceStatus = "음성 꺼짐"
    private var engine: WorkoutCoachEngine?
    private var scope = "unbound"
    private let defaults: UserDefaults
    private let speech: any CoachSpeechOutput
    init(defaults: UserDefaults = .standard, speech: (any CoachSpeechOutput)? = nil) {
        self.defaults = defaults; self.speech = speech ?? DeviceCoachSpeech()
    }
    func bind(scope: String) {
        guard self.scope != scope else { return }
        stop(); engine = nil; self.scope = scope
        caption = "기본 안내는 기기에서 말해요. 음성은 기본 꺼짐이에요."
        preferences = defaults.data(forKey: preferenceKey).flatMap { try? JSONDecoder().decode(CoachPreferences.self, from: $0) } ?? CoachPreferences()
        refreshStatus()
    }
    func configure(_ preference: CoachPreferences, session: RecordWorkoutSession?, at now: Date) {
        speech.stop()
        preferences = preference
        if preference.enabled { speech.confirmOutput() }
        if let session { engine?.baseline(session: session, preferences: preferences, at: now) }
        if let data = try? JSONEncoder().encode(preference) { defaults.set(data, forKey: preferenceKey) }
        refreshStatus()
    }
    func update(session: RecordWorkoutSession, at now: Date, restored: Bool = false, phoneOwnsRecording: Bool = true) {
        guard phoneOwnsRecording else { stop(); return }
        if engine?.sessionID != session.id {
            engine = WorkoutCoachEngine(sessionID: session.id, checkpoint: session.coachCheckpoint)
            if restored { engine?.baseline(session: session, preferences: preferences, at: now); speech.stop(); return }
            // Restored/changed interval must never announce historical milestones.
            if session.coachCheckpoint == nil { engine?.checkpoint.interval = preferences.interval }
            else if engine?.checkpoint.interval != preferences.interval { engine?.baseline(session: session, preferences: preferences, at: now) }
        }
        if let event = engine?.update(session: session, preferences: preferences, at: now) { deliver(event) }
        refreshStatus()
    }
    var checkpoint: CoachCheckpoint? { engine?.checkpoint }
    func saved(at now: Date) { if let event = engine?.saved(at: now) { deliver(event) }; refreshStatus() }
    func localEncouragement() {
        guard engine?.checkpoint.state == .paused else { return }
        deliver(CoachEvent(id: "local-\(UUID())", text: CoachPhraseClient.reviewedPhrases[0], expiresAt: Date().addingTimeInterval(10), replacesSpeech: true))
        refreshStatus()
    }
    func stop() { speech.stop(); refreshStatus() }
    private var preferenceKey: String { "soom.coach.v5.\(scope)" }
    private func refreshStatus() {
        voiceStatus = !preferences.enabled ? "음성 꺼짐" : UIAccessibility.isVoiceOverRunning ? "VoiceOver 사용 중 · 자동 음성 쉬기" : speech.status
    }
    private func deliver(_ event: CoachEvent) {
        caption = event.text
        if preferences.enabled { speech.speak(event) } else { speech.stop() }
    }
}
