import SwiftUI
import UIKit
import CoreHaptics

enum SOOMMotion {
    enum Duration {
        static let quick: Double = 0.12
        static let normal: Double = 0.20
        static let slow: Double = 0.32
        static let background: Double = 0.80
    }

    enum Scale {
        static let pressed: CGFloat = 0.98
        static let subtlePressed: CGFloat = 0.99
        static let selected: CGFloat = 1.02
    }

    enum Offset {
        static let cardRevealY: CGFloat = 6
        static let subtleRevealY: CGFloat = 4
    }

    enum Opacity {
        static let hidden: Double = 0
        static let visible: Double = 1
        static let muted: Double = 0.72
    }

    static let quickEaseOut = Animation.easeOut(duration: Duration.quick)
    static let normalEaseOut = Animation.easeOut(duration: Duration.normal)
    static let slowEaseOut = Animation.easeOut(duration: Duration.slow)
    static let subtleSpring = Animation.spring(response: 0.28, dampingFraction: 0.88)
    static let cardPress = Animation.spring(response: 0.24, dampingFraction: 0.92)
    static let coachSpring = Animation.spring(response: 0.34, dampingFraction: 0.90)
}

enum SOOMHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func softImpact() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.48)
    }

    static func typingTick() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.34)
    }

    static func typingWordStart() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.58)
    }
}

/// Motion pulses follow finger movement; a held finger never starts a timer.
/// Integer transitions have priority over the quieter movement pulse.
struct WorkoutEffortHapticPolicy {
    enum Pulse: Equatable { case movement, step }
    private(set) var previousValue: Double?
    private var lastPulse = -Double.infinity
    private var lastStep = -Double.infinity
    static let subdivisions = 13 // Twelve quiet points between adjacent integers.
    private var previousGrid: Int?
    private var announcedStep: Int?
    static func intensity(_ pulse: Pulse, value: Double) -> Double {
        let amount = (min(10, max(1, value.isFinite ? value : 1)) - 1) / 9
        return pulse == .step ? 0.55 + amount * 0.45 : 0.16 + amount * 0.22
    }
    mutating func begin(_ value: Double) {
        guard value.isFinite else { end(); return }
        let clamped = min(10, max(1, value))
        previousValue = clamped
        previousGrid = Int(((clamped - 1) * Double(Self.subdivisions)).rounded())
        announcedStep = abs(clamped - clamped.rounded()) < 0.0001 ? Int(clamped.rounded()) : nil
        lastPulse = -.infinity; lastStep = -.infinity
    }
    mutating func end() { previousValue = nil; previousGrid = nil; announcedStep = nil; lastPulse = -.infinity; lastStep = -.infinity }
    mutating func update(_ value: Double, at time: Double, reduced: Bool) -> Pulse? {
        guard value.isFinite, time.isFinite, let previousValue, let previousGrid else { return nil }
        let clamped = min(10, max(1, value))
        let grid = Int(((clamped - 1) * Double(Self.subdivisions)).rounded())
        self.previousValue = clamped
        self.previousGrid = grid
        guard grid != previousGrid else { return nil }
        let crossed = clamped > previousValue ? floor(clamped) > floor(previousValue) : ceil(clamped) < ceil(previousValue)
        let tick = crossed ? Int(clamped > previousValue ? floor(clamped) : ceil(clamped))
            : (grid % Self.subdivisions == 0 ? 1 + grid / Self.subdivisions : nil)
        if let tick, announcedStep != tick {
            // Consume a crossed point even when throttled. Never replay queued pulses.
            announcedStep = tick
            // A quiet pulse must never consume the next strong integer tick.
            // Only another strong pulse can throttle a rapid multi-integer jump.
            guard time - lastStep >= 0.025 else { return nil }
            lastStep = time; lastPulse = time
            return .step
        }
        if tick != nil { return nil }
        // Reduce Motion controls visual expansion, not discrete tactile feedback.
        // At most one pulse per touch event, with no queued catch-up burst.
        guard time - lastPulse >= 0.012 else { return nil }
        lastPulse = time
        return .movement
    }
}

@MainActor
protocol WorkoutEffortHapticPlaying {
    func prepare()
    func play(_ pulse: WorkoutEffortHapticPolicy.Pulse, intensity: Double)
    func end()
}

@MainActor
private final class UIKitWorkoutEffortHapticPlayer: WorkoutEffortHapticPlaying {
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let step = UIImpactFeedbackGenerator(style: .rigid)
    func prepare() { soft.prepare(); step.prepare() }
    func play(_ pulse: WorkoutEffortHapticPolicy.Pulse, intensity: Double) {
        // UIKit handles hardware/user haptic settings. Do not gate these native
        // generators on the separate Core Haptics engine capability.
        switch pulse {
        case .movement: soft.impactOccurred(intensity: intensity); soft.prepare()
        case .step: step.impactOccurred(intensity: intensity); step.prepare()
        }
    }
    func end() {} // Transients are never scheduled or looped.
}

@MainActor
final class WorkoutEffortHaptics {
    private var policy = WorkoutEffortHapticPolicy()
    private let player: any WorkoutEffortHapticPlaying
    private let clock: () -> Double
    private let isActive: () -> Bool
    init(player: (any WorkoutEffortHapticPlaying)? = nil,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }) {
        self.player = player ?? UIKitWorkoutEffortHapticPlayer()
        self.clock = clock; self.isActive = isActive
    }
    func prepare() { if isActive() { player.prepare() } }
    func begin(_ value: Double) { policy.begin(value); prepare() }
    func move(_ value: Double, reduced: Bool) {
        guard isActive() else { end(); return }
        guard let pulse = policy.update(value, at: clock(), reduced: reduced) else { return }
        player.play(pulse, intensity: WorkoutEffortHapticPolicy.intensity(pulse, value: value))
    }
    func end() { policy.end(); player.end() }
}
