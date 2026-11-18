import SwiftUI

/// Geometry is handled without publishing per-frame changes to the screen tree.
/// Only a compact/expanded transition invalidates the tab bar's owner.
struct SOOMTabBarScrollSample: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    var position: CGFloat { offset + topInset }
    var maximum: CGFloat { max(0, contentHeight + topInset + bottomInset - viewportHeight) }
}

struct SOOMTabBarScrollReducer {
    static let compactScale: CGFloat = 0.76
    static let animationDuration: Double = 0.20
    static let collapseDistance: CGFloat = 24
    static let restoreDistance: CGFloat = 16
    static let layoutTolerance: CGFloat = 2

    private(set) var isCompact = false
    private var isUserScrolling = false
    private var isDecelerating = false
    private var isBoundaryRecoil = false
    private var lastSample: SOOMTabBarScrollSample?
    private var travel: CGFloat = 0

    mutating func reset() { self = Self() }

    mutating func beginGesture(at sample: SOOMTabBarScrollSample? = nil) {
        isUserScrolling = true
        isDecelerating = false
        isBoundaryRecoil = false
        // Preserve the idle baseline. Phase context seeds the first movement.
        if let sample { lastSample = sample }
        travel = 0
    }

    mutating func interact(at sample: SOOMTabBarScrollSample? = nil) {
        // A new drag can interrupt deceleration without an intervening tracking phase.
        if !isUserScrolling || isDecelerating { beginGesture(at: sample) }
    }

    mutating func decelerate(at sample: SOOMTabBarScrollSample? = nil) {
        isDecelerating = true
        if let sample = sample ?? lastSample,
           sample.position <= 1 || sample.position >= sample.maximum {
            isBoundaryRecoil = true
        }
    }

    mutating func endGesture() {
        isUserScrolling = false
        isDecelerating = false
        isBoundaryRecoil = false
        travel = 0
    }

    mutating func consume(_ sample: SOOMTabBarScrollSample) {
        guard sample.offset.isFinite, sample.contentHeight.isFinite,
              sample.viewportHeight.isFinite, sample.topInset.isFinite,
              sample.bottomInset.isFinite else { return }
        // Idle/programmatic geometry updates the baseline, never reading intent.
        defer { lastSample = sample }
        if sample.position <= 1 || sample.maximum <= 1 {
            isCompact = false
            travel = 0
            isBoundaryRecoil = isDecelerating
            return
        }
        guard isUserScrolling else { return }
        if sample.position >= sample.maximum {
            isBoundaryRecoil = true
            travel = 0
            return
        }
        // Once deceleration reaches an edge, ignore its entire spring re-entry.
        guard !isDecelerating || !isBoundaryRecoil else { return }
        isBoundaryRecoil = false
        guard let previous = lastSample else { return }
        // Pixel/one-point noise must not repeatedly clear reading intent.
        // Larger viewport/inset changes still restore and rebase.
        guard abs(previous.viewportHeight - sample.viewportHeight) <= Self.layoutTolerance,
              abs(previous.topInset - sample.topInset) <= Self.layoutTolerance,
              abs(previous.bottomInset - sample.bottomInset) <= Self.layoutTolerance else {
            isCompact = false
            travel = 0
            return
        }
        let previousPosition = min(max(0, previous.position), previous.maximum)
        let delta = sample.position - previousPosition
        guard abs(delta) <= max(120, sample.viewportHeight * 0.5) else {
            travel = 0
            return
        }
        guard delta != 0 else { return }
        // Net travel toward the NEXT state: short reversals subtract rather
        // than erase an otherwise consistent drag. No timers or debounce.
        travel = max(0, travel + (isCompact ? -delta : delta))
        if !isCompact && travel >= Self.collapseDistance {
            isCompact = true
            travel = 0
        } else if isCompact && travel >= Self.restoreDistance {
            isCompact = false
            travel = 0
        }
    }
}

/// Visual chrome contracts independently of unscaled, non-overlapping tap slots.
/// On narrow phones the slots extend slightly beyond the compact capsule.
struct SOOMTabBarTouchLayout {
    static let minimumTarget: CGFloat = 44
    let containerWidth: CGFloat
    let visualScale: CGFloat
    let tabCount: Int
    let horizontalPadding: CGFloat

    private var count: CGFloat { CGFloat(max(1, tabCount)) }
    var visualContainerWidth: CGFloat { containerWidth * visualScale }
    var expandedItemWidth: CGFloat { (containerWidth - 2 * horizontalPadding) / count }
    var targetRowWidth: CGFloat {
        max(count * Self.minimumTarget, (containerWidth - 2 * horizontalPadding) * visualScale)
    }
    var targetItemWidth: CGFloat { targetRowWidth / count }
    var visualItemWidth: CGFloat {
        // Keep the outer selection pills inside the visual capsule even when
        // the 44pt minimum makes touch slots wider than the compact chrome.
        min(expandedItemWidth,
            max(0, (visualContainerWidth - targetRowWidth + targetItemWidth) / visualScale))
    }
}

@MainActor
final class SOOMTabBarScrollMotion: ObservableObject {
    @Published private(set) var isCompact = false
    private var reducer = SOOMTabBarScrollReducer()
    private var activeSource: UUID?
    private var suspensions: Set<UUID> = []
    var isEnabled = true {
        didSet { if oldValue != isEnabled && !isEnabled { restore() } }
    }

    func restore() {
        reducer.reset()
        publishTransition()
    }

    func activate(_ source: UUID) {
        guard activeSource != source else { return }
        activeSource = source
        restore()
    }

    func deactivate(_ source: UUID) {
        guard activeSource == source else { return }
        activeSource = nil
        restore()
    }

    func suspend(_ suspended: Bool, source: UUID) {
        guard suspensions.contains(source) != suspended else { return }
        if suspended { suspensions.insert(source) } else { suspensions.remove(source) }
        restore()
    }

    func phaseChanged(_ phase: ScrollPhase, source: UUID, sample: SOOMTabBarScrollSample? = nil) {
        guard activeSource == source, isEnabled, suspensions.isEmpty else { return }
        switch phase {
        case .tracking: reducer.beginGesture(at: sample)
        case .interacting: reducer.interact(at: sample)
        case .decelerating: reducer.decelerate(at: sample)
        case .idle: reducer.endGesture()
        case .animating: reducer.endGesture()
        @unknown default: restore()
        }
    }

    func consume(_ sample: SOOMTabBarScrollSample, source: UUID) {
        guard activeSource == source, isEnabled, suspensions.isEmpty else { return }
        reducer.consume(sample)
        publishTransition()
    }

    private func publishTransition() {
        if isCompact != reducer.isCompact { isCompact = reducer.isCompact }
    }
}

private struct SOOMTabBarScrollMotionKey: EnvironmentKey {
    static let defaultValue: SOOMTabBarScrollMotion? = nil
}

extension EnvironmentValues {
    var soomTabBarScrollMotion: SOOMTabBarScrollMotion? {
        get { self[SOOMTabBarScrollMotionKey.self] }
        set { self[SOOMTabBarScrollMotionKey.self] = newValue }
    }
}

struct SOOMTabBarScrollTracking: ViewModifier {
    let enabled: Bool
    @Environment(\.soomTabBarScrollMotion) private var motion
    @State private var source = UUID()

    func body(content: Content) -> some View {
        // Keep the ScrollView's structural identity when a retained tab becomes inactive.
        content
            .onScrollGeometryChange(for: SOOMTabBarScrollSample.self) { geometry in
                Self.sample(geometry)
            } action: { _, sample in
                guard enabled else { return }
                motion?.consume(sample, source: source)
            }
            .onScrollPhaseChange { _, phase, context in
                guard enabled else { return }
                motion?.phaseChanged(phase, source: source, sample: Self.sample(context.geometry))
            }
            .onAppear { if enabled { motion?.activate(source) } }
            .onChange(of: enabled) { _, active in
                if active { motion?.activate(source) }
                else { motion?.deactivate(source) }
            }
            .onDisappear { motion?.deactivate(source) }
    }

    private static func sample(_ geometry: ScrollGeometry) -> SOOMTabBarScrollSample {
        SOOMTabBarScrollSample(offset: geometry.contentOffset.y,
                               contentHeight: geometry.contentSize.height,
                               viewportHeight: geometry.containerSize.height,
                               topInset: geometry.contentInsets.top,
                               bottomInset: geometry.contentInsets.bottom)
    }
}

private struct SOOMTabBarScrollSuspension: ViewModifier {
    let suspended: Bool
    @Environment(\.soomTabBarScrollMotion) private var motion
    @State private var source = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { motion?.suspend(suspended, source: source) }
            .onChange(of: suspended) { _, value in motion?.suspend(value, source: source) }
            .onDisappear { motion?.suspend(false, source: source) }
    }
}

extension View {
    func suspendsSOOMTabBarScrollMotion(when suspended: Bool) -> some View {
        modifier(SOOMTabBarScrollSuspension(suspended: suspended))
    }
}
